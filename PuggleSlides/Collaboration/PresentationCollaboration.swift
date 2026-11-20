import AppKit
import Observation
import PuggleSlidesKit

/// What the header shows about a presentation's sharing: who's in it, who has it open, and how it's keeping up.
@Observable
final class CollaborationState {
    var isShared = false
    var isOwner = true
    var ownerName = ""
    /// What this Mac's person can do.
    var permission: CollaboratorPermission = .edit
    /// Everyone it's shared with, the owner first.
    var collaborators: [Collaborator] = []
    /// Who has it open, as last heard, by iCloud identity.
    var presence: [String: Presence] = [:]
    var meID: String?
    /// Words for how the shared copy is keeping up, in place of the file's save status.
    var statusText = ""
    var statusSymbol = "icloud"
    /// Bumped as time passes, so "last seen" words keep up.
    var clock = Date()

    /// The people other than this Mac's who are in it, the owner first: the round badges in the header. Everyone who
    /// has opened it, named as they name themselves, so they show even when iCloud doesn't say who they are; then
    /// those iCloud lists as joined who haven't, by names not shown already, so nobody shows twice.
    var others: [Collaborator] {
        var people: [Collaborator] = []
        for item in presence.values where item.person != meID {
            var person = collaborators.first { $0.id == item.person }
                ?? Collaborator(id: item.person, name: item.info.name, isOwner: item.info.isOwner ?? false,
                                permission: item.info.permission ?? .comment, status: .joined)
            if person.name.isEmpty { person.name = item.info.name }
            people.append(person)
        }
        for person in collaborators where person.id != meID && person.status == .joined && !people.contains(where: { $0.id == person.id }) {
            guard people.isEmpty || (!person.name.isEmpty && !people.contains { $0.name == person.name }) else { continue }
            people.append(person)
        }
        return people.sorted { ($0.isOwner ? 0 : 1, $0.displayName.lowercased()) < ($1.isOwner ? 0 : 1, $1.displayName.lowercased()) }
    }

    func isViewing(_ person: Collaborator) -> Bool { presence[person.id]?.isActive(now: clock) ?? false }

    func lastSeen(_ person: Collaborator) -> Date? { presence[person.id]?.date }

    func reset() {
        isShared = false
        isOwner = true
        ownerName = ""
        permission = .edit
        collaborators = []
        presence = [:]
        statusText = ""
    }
}

/// What's selected, to bring back with an undo step.
struct SharedSelection {
    var slideID: UUID?
    var elements: [UUID]
}

/// An undo step of this Mac's in a shared presentation: each part it changed (what it set there, and what was there
/// before), each comment thread it changed, and what was selected before it. Undo puts back only the parts that are
/// still as this Mac left them, so it takes back this person's own changes and never someone else's.
private final class SharedUndoStep {
    let actionName: String
    var parts: [PartKey: (mine: PartValue?, old: PartValue?)]
    var comments: [UUID: (slideID: UUID, before: CommentThread?, after: CommentThread?)]
    let selection: SharedSelection?

    init(actionName: String, parts: [PartKey: (mine: PartValue?, old: PartValue?)] = [:],
         comments: [UUID: (slideID: UUID, before: CommentThread?, after: CommentThread?)] = [:], selection: SharedSelection?) {
        self.actionName = actionName
        self.parts = parts
        self.comments = comments
        self.selection = selection
    }

    var isEmpty: Bool { parts.isEmpty && comments.isEmpty }
}

/// One open presentation's part in sharing: its slides kept the same as everyone else's through the presentation's
/// log, its comments through the talk zone, who's in it, and the short summaries that tell the others what changed.
///
/// While a presentation is shared, the edits made here are taken in as they're recorded (see
/// `PresentationController`): what changed between the presentation as it showed and as the edit left it becomes a
/// change of parts (see `PresentationState`), sent one after another. Other people's changes are applied as they come,
/// with this Mac's changes still on their way kept over them where both changed the same part. Undo works on this Mac's
/// own changes, through steps kept here.
final class PresentationCollaboration: NSObject {
    enum Phase: Equatable {
        /// Waiting for the shared copy to load.
        case connecting
        case live
        case ended
    }

    /// How long a run of changes waits for the next before the others are told about it.
    static var noticeDelay: TimeInterval = 120

    let id: UUID
    let isOwner: Bool
    /// For presentations shared with this person, whose iCloud they're in.
    let ownerID: String?
    private unowned let controller: CollaborationController
    private(set) weak var document: PresentationDocument?
    private weak var windowController: DocumentWindowController?
    private(set) var client: SyncClient<PresentationChange>?
    private var channel: CollaborationChannel?
    private(set) var sharing: DocumentSharing?
    private(set) var phase: Phase = .connecting
    private var info: SharedDocumentInfo?
    /// Changes that came before the snapshot they follow.
    private var earlyChanges: [LoggedPresentationChange] = []
    /// The shared presentation's parts: the log's, with this Mac's changes on their way laid over them.
    private(set) var state = PresentationState()
    /// The presentation as the parts and comments last showed it here: what edits here are measured from.
    private var shown = Presentation(themes: [])
    private var isApplyingRemote = false
    /// What's been changed here since the last undo step was made, for the next one.
    private var group: [PartKey: (mine: PartValue?, old: PartValue?)] = [:]
    private var groupComments: [UUID: (slideID: UUID, before: CommentThread?, after: CommentThread?)] = [:]
    private var captureScheduled = false
    /// Every comment thread, by id, with its slide. Threads on slides that are gone stay, for if the slides come back.
    private var threads: [UUID: SharedComment] = [:]
    /// Threads as iCloud last had them.
    private var serverComments: [UUID: SharedComment] = [:]
    private var tally = ChangeTally()
    private var noticeWork: DispatchWorkItem?
    private var snapshotWork: DispatchWorkItem?
    private var lastSnapshotRevision = 0
    private var retryDelay: TimeInterval = 1
    private var retryScheduled = false
    /// Why changes can't be saved to iCloud just now, when they can't. Meanwhile the window takes none: nothing made
    /// in a shared presentation is kept to send later.
    private enum Blocked: Equatable {
        /// iCloud can't be reached: the Mac is offline, say.
        case offline
        /// iCloud turned a change down, saying why.
        case refused(String)
    }
    private var blocked: Blocked?
    /// The window's banner as this session last set it, so coming back online takes away only its own.
    private var blockedBanner: String?
    private var heartbeat: Timer?
    /// Looking again for a change of the log that others came ahead of, longer apart each time.
    private var gapCheck: DispatchWorkItem?
    private var gapDelay: TimeInterval = 1
    #if DEBUG
    /// How many times missing changes were asked for again, for the self-test.
    private(set) var gapRequests = 0
    #endif

    init(id: UUID, isOwner: Bool, ownerID: String?, controller: CollaborationController, document: PresentationDocument,
         windowController: DocumentWindowController) {
        self.id = id
        self.isOwner = isOwner
        self.ownerID = ownerID
        self.controller = controller
        self.document = document
        self.windowController = windowController
        super.init()
    }

    private var editor: PresentationController? { windowController?.controller }
    private var collaborationState: CollaborationState? { windowController?.state.collaboration }
    var title: String { document?.displayName ?? info?.title ?? "Untitled presentation" }
    var me: Collaborator? { controller.status.me }
    var isLive: Bool { phase == .live }

    /// Whether this person may change the slides.
    var canEdit: Bool { isOwner || (sharing?.myPermission ?? .comment) == .edit }

    /// Whether changes made here haven't all reached iCloud.
    var hasUnsentChanges: Bool { phase == .live && (client?.hasPending ?? false) }

    // MARK: Starting and ending

    /// Shares the presentation for the first time, as it is now, then carries on live.
    func startSharing(access: LinkAccess, permission: CollaboratorPermission, completion: @escaping (Error?) -> Void) {
        guard let editor else { return }
        let presentation = editor.realPresentation
        let start = PresentationState(presentation)
        let snapshot = SyncSnapshot(revision: 0, state: start)
        let comments = presentation.commentThreads.map { SharedComment(thread: $0.thread, slideID: $0.slideID) }
        controller.service.share(id, title: title, snapshot: snapshot, comments: comments, access: access, permission: permission) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(sharing):
                self.sharing = sharing
                state = start
                for comment in comments {
                    threads[comment.thread.id] = comment
                    serverComments[comment.thread.id] = comment
                }
                client = SyncClient(revision: 0, author: me?.id ?? "me", authorName: me?.name ?? NSFullUserName())
                lastSnapshotRevision = 0
                info = SharedDocumentInfo(title: title, ownerName: me?.name ?? "")
                // Edits made while it was being shared are measured from the presentation as it was shared.
                shown = withComments(start.presentation())
                updateState()
                goLive()
                connectChannel()
                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    /// Opens the shared copy: until it's here, the window shows what it has, and nothing can be changed.
    func connect() {
        phase = .connecting
        windowController?.setAccess(.locked)
        updateState()
        connectChannel()
    }

    private func connectChannel() {
        let channel = controller.service.connect(id, owner: isOwner ? nil : ownerID, delegate: self)
        self.channel = channel
        channel.start()
    }

    private func goLive() {
        guard phase != .ended else { return }
        phase = .live
        // Undo steps from before were whole presentations, which would take back other people's changes.
        document?.undoManager?.removeAllActions()
        group = [:]
        groupComments = [:]
        applyPermission()
        announcePresence(viewing: true)
        // A file of this person's renamed while it was closed: everyone gets its new name.
        titleChanged()
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.announcePresence(viewing: true)
                self.collaborationState?.clock = Date()
            }
        }
        updateState()
        captureLocal()
        flush()
    }

    /// Stops taking part: the channel closes, and undo goes back to whole presentations.
    func end(saying presenceEnds: Bool = true) {
        guard phase != .ended else { return }
        if phase == .live { captureLocal() }
        sendNotice()
        if presenceEnds { announcePresence(viewing: false) }
        phase = .ended
        channel?.stop()
        channel = nil
        heartbeat?.invalidate()
        heartbeat = nil
        snapshotWork?.cancel()
        noticeWork?.cancel()
        gapCheck?.cancel()
        gapCheck = nil
        group = [:]
        groupComments = [:]
        document?.undoManager?.removeAllActions()
    }

    /// The owner renamed the presentation: its name in iCloud follows, and with it the name everyone else sees.
    func titleChanged() {
        guard isOwner, phase == .live else { return }
        channel?.setTitle(title)
    }

    /// Tells the others whether this person has the presentation open, and who they are in it.
    private func announcePresence(viewing: Bool) {
        channel?.setPresence(viewing: viewing, isOwner: isOwner, permission: isOwner ? .edit : (sharing?.myPermission ?? .comment))
    }

    /// The window is closing: everyone's told this person has gone.
    func close() {
        end()
        controller.unregister(self)
    }

    private func applyPermission() {
        switch phase {
        case .connecting: windowController?.setAccess(.locked)
        case .ended: break
        case .live: windowController?.setAccess(blocked != nil ? .offline : (canEdit ? .full : .commentOnly))
        }
    }

    // MARK: Changes made here

    /// The presentation changed here: what changed is taken in once the edit is done (a drag, once it ends).
    func noteLocalChange() {
        guard phase == .live, !isApplyingRemote, !captureScheduled else { return }
        if editor?.isInteractive == true { return }
        captureScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            captureScheduled = false
            captureLocal()
        }
    }

    /// Takes in what's been edited here since the last look: changed parts go to the others and into the undo step
    /// being made, and comments go to the talk zone.
    func captureLocal() {
        guard phase == .live, !isApplyingRemote, let client, let editor else { return }
        let current = editor.realPresentation
        guard current != shown else { return }
        if blocked != nil {
            // Changes can't be saved to iCloud just now, so none are taken: whatever got into the presentation here
            // goes, and it shows what the parts say.
            isApplyingRemote = true
            editor.applyShared(shown, update: Self.update(from: current, to: shown))
            isApplyingRemote = false
            return
        }
        captureComments(from: shown, to: current)
        // Someone who may only comment never changes the slides; anything that tried stays here only until now.
        let change = canEdit ? state.change(from: shown, to: current) : PresentationChange()
        if !change.isEmpty {
            for (key, value) in change.parts {
                if let existing = group[key] {
                    group[key] = (mine: value, old: existing.old)
                } else {
                    group[key] = (mine: value, old: state[key])
                }
            }
            tally.record(change, before: shown)
            state.apply(change)
            client.local(change)
            noteLocalAction()
        }
        // What this Mac shows is always what the parts say (media taken out stay, for others still using them).
        let expected = withComments(state.presentation())
        shown = expected
        if expected != current {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "PPLogCollaboration") { print("COLLABORATION: shown again from the parts") }
            #endif
            isApplyingRemote = true
            editor.applyShared(expected, update: Self.update(from: current, to: expected))
            isApplyingRemote = false
        }
        flush()
    }

    /// An edit finished here (`PresentationController.perform`, or a drag or typing ending): its changes become one
    /// undo step, which brings back `selection`.
    func recorded(actionName: String, selection: SharedSelection) {
        captureLocal()
        guard !group.isEmpty || !groupComments.isEmpty else { return }
        let step = SharedUndoStep(actionName: actionName, parts: group, comments: groupComments, selection: selection)
        group = [:]
        groupComments = [:]
        register(step)
    }

    /// An edit given up on (a drag cancelled): what it changed goes back, with no undo step.
    func cancelGroup() {
        if group.isEmpty, groupComments.isEmpty, let editor {
            // None of it reached the others: the presentation goes back to what the parts say.
            isApplyingRemote = true
            editor.applyShared(shown, update: .content)
            isApplyingRemote = false
            return
        }
        captureLocal()
        let step = SharedUndoStep(actionName: "", parts: group, comments: groupComments, selection: nil)
        group = [:]
        groupComments = [:]
        _ = revert(step)
    }

    private func register(_ step: SharedUndoStep) {
        guard let undoManager = document?.undoManager, undoManager.isUndoRegistrationEnabled else { return }
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.undo(step) }
        }
        undoManager.setActionName(step.actionName)
    }

    /// Undoes (or redoes) a step, and registers the step that takes it back again.
    private func undo(_ step: SharedUndoStep) {
        guard phase == .live, blocked == nil else { return }
        captureLocal()
        let selection = editor.map { SharedSelection(slideID: $0.currentSlideID, elements: $0.selectedElementIDs) }
        let reverse = revert(step)
        if let target = step.selection { editor?.restoreSharedSelection(slideID: target.slideID, elements: target.elements) }
        register(SharedUndoStep(actionName: step.actionName, parts: reverse.parts, comments: reverse.comments, selection: selection))
    }

    /// Puts back what a step changed, wherever it's still as the step left it; answers what changing it again takes.
    private func revert(_ step: SharedUndoStep) -> SharedUndoStep {
        let reverse = SharedUndoStep(actionName: step.actionName, selection: nil)
        var change = PresentationChange()
        if canEdit {
            for (key, values) in step.parts where state[key] == values.mine {
                change.parts[key] = values.old
                reverse.parts[key] = (mine: values.old, old: values.mine)
            }
        }
        if let client, !change.isEmpty {
            tally.record(change, before: shown)
            state.apply(change)
            client.local(change)
            noteLocalAction()
        }
        for (id, values) in step.comments {
            let current = threads[id]?.thread
            let reverted = Self.revert(current, from: values.after, to: values.before)
            reverse.comments[id] = (values.slideID, current, reverted)
            if let reverted {
                let comment = SharedComment(thread: reverted, slideID: values.slideID)
                threads[id] = comment
                if let channel { save(comment, base: current, using: channel) }
            } else if current != nil {
                threads[id] = nil
                serverComments[id] = nil
                channel?.deleteComment(id)
            }
        }
        show()
        flush()
        return reverse
    }

    /// `current` with the change from `before` to `after` taken back, leaving the rest of it as it is now.
    static func revert(_ current: CommentThread?, from after: CommentThread?, to before: CommentThread?) -> CommentThread? {
        // A thread the change made goes; one it deleted comes back.
        guard let before else { return nil }
        guard let after, var thread = current else { return before }
        if after.isResolved != before.isResolved { thread.isResolved = before.isResolved }
        let beforeIDs = Set(before.comments.map(\.id))
        let afterIDs = Set(after.comments.map(\.id))
        thread.comments.removeAll { afterIDs.contains($0.id) && !beforeIDs.contains($0.id) }
        for comment in before.comments {
            if !afterIDs.contains(comment.id) {
                if !thread.comments.contains(where: { $0.id == comment.id }) { thread.comments.append(comment) }
            } else if let edited = after.comments.first(where: { $0.id == comment.id }), edited.text != comment.text,
                      let index = thread.comments.firstIndex(where: { $0.id == comment.id }) {
                thread.comments[index].text = comment.text
                thread.comments[index].editedDate = comment.editedDate
            }
        }
        if let starter = before.comments.first?.id, let index = thread.comments.firstIndex(where: { $0.id == starter }) {
            let first = thread.comments.remove(at: index)
            thread.comments = [first] + thread.comments.sorted { $0.date < $1.date }
        }
        return thread.comments.isEmpty ? nil : thread
    }

    #if DEBUG
    /// What undo holds, for the self-test.
    var undoDescription: String {
        "group \(group.count) manager canUndo \(document?.undoManager?.canUndo ?? false) name \(document?.undoManager?.undoActionName ?? "")"
    }
    #endif

    /// Sends the next change, if one's waiting and none is on its way.
    func flush() {
        guard phase == .live, let client, let channel else { return }
        guard let next = client.nextToSend() else {
            updateState()
            return
        }
        updateState()
        channel.claim(next) { [weak self] result in
            guard let self, let client = self.client else { return }
            switch result {
            case .claimed:
                client.sent(next.id)
                markOnline()
                afterConfirm()
            case let .taken(existing):
                prepareForRemote()
                apply(client.sendTaken(next.id, by: existing))
                lookForGap()
                markOnline()
            case .notAllowed:
                client.sendFailed(next.id)
                lostEditing()
                return
            case let .failed(error):
                client.sendFailed(next.id)
                markOffline(because: error)
                return
            }
            flush()
        }
    }

    /// A change went in: whatever kept the window from being changed is over.
    private func markOnline() {
        retryDelay = 1
        guard blocked != nil else { return }
        blocked = nil
        cameBack()
    }

    /// Sending failed: the window stops taking changes, saying why, and the change is tried again in a while, longer
    /// each time. (It was made while iCloud could still be reached; it goes in, merged, once it can be again.)
    private func markOffline(because error: Error) {
        block(isConnectionProblem(error) ? .offline : .refused(error.localizedDescription))
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self else { return }
            retryScheduled = false
            flush()
        }
        retryDelay = min(retryDelay * 2, 30)
    }

    /// Changes can't be saved to iCloud: the window stops taking any, and says why, until they can again. It's still
    /// looked at for others' changes, more often, so it knows as soon as iCloud's back.
    private func block(_ reason: Blocked) {
        guard blocked != reason else { return }
        blocked = reason
        channel?.pollInterval = 5
        applyPermission()
        updateState()
        explainOffline()
    }

    /// Says in the window why it can't be changed just now (again, when someone tries).
    func explainOffline() {
        guard let blocked else { return }
        let banner = switch (blocked, phase) {
        case (.offline, .connecting):
            "You’re offline, so “\(title)” can’t be opened from iCloud yet. It opens as soon as iCloud can be reached."
        case (.offline, _):
            "You’re offline, so changes to “\(title)” can’t be saved. You can still read it, print it or save a copy, and editing comes back as soon as iCloud can be reached."
        case let (.refused(reason), _):
            "Changes to “\(title)” can’t be saved to iCloud right now (\(reason)). You can still read it, print it or save a copy."
        }
        blockedBanner = banner
        windowController?.state.banner = banner
    }

    /// Changes can be saved again: the window takes them, catches up with what others did meanwhile, and its own
    /// message about it goes.
    private func cameBack() {
        if let banner = windowController?.state.banner, banner == blockedBanner { windowController?.state.banner = nil }
        blockedBanner = nil
        applyPermission()
        updateState()
        titleChanged()
        channel?.fetchSoon()
        flush()
    }

    /// iCloud turned a change down: this person may no longer edit. Their changes not yet in go, and the presentation
    /// starts again from iCloud's copy.
    private func lostEditing() {
        windowController?.state.banner = "You can no longer edit “\(title)”, only comment on it. Your latest changes weren’t kept."
        resync()
    }

    /// Starts over from iCloud's copy: its snapshot and the changes since.
    private func resync() {
        guard phase != .ended else { return }
        channel?.stop()
        channel = nil
        client = nil
        group = [:]
        groupComments = [:]
        phase = .connecting
        applyPermission()
        updateState()
        connectChannel()
    }

    // MARK: Changes from others

    /// Before changes from others are applied: whatever's been edited here goes first, so it's among this Mac's own
    /// changes and stays.
    private func prepareForRemote() {
        windowController?.pushEditingText()
        captureLocal()
    }

    private func apply(_ changes: [PresentationChange]) {
        guard !changes.isEmpty else { return }
        for change in changes { state.apply(change) }
        show()
        // The owner's file follows the shared copy.
        if isOwner { document?.updateChangeCount(.changeDone) }
        windowController?.reloadEditingText()
    }

    /// Shows the presentation as the parts and comments have it now.
    private func show() {
        guard let editor else { return }
        let presentation = withComments(state.presentation())
        let update = Self.update(from: shown, to: presentation)
        shown = presentation
        guard !update.isEmpty else { return }
        isApplyingRemote = true
        editor.applyShared(presentation, update: update)
        isApplyingRemote = false
    }

    /// What views need to refresh after the presentation went from `old` to `new`.
    private static func update(from old: Presentation, to new: Presentation) -> PresentationUpdate {
        guard old != new else { return [] }
        var update: PresentationUpdate = []
        if old.themes != new.themes || old.slideSize != new.slideSize || old.defaultTextStyle != new.defaultTextStyle { update.insert(.theme) }
        if old.slides.map(\.id) != new.slides.map(\.id) || zip(old.slides, new.slides).contains(where: { $0.layoutID != $1.layoutID || $0.isSkipped != $1.isSkipped }) {
            update.insert(.slides)
        }
        let oldSlides = Dictionary(old.slides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for slide in new.slides {
            guard let previous = oldSlides[slide.id] else { continue }
            if previous.notes != slide.notes { update.insert(.notes) }
            if previous.comments != slide.comments { update.insert(.comments) }
            var a = previous, b = slide
            a.notes = .empty
            b.notes = .empty
            a.comments = []
            b.comments = []
            if a != b { update.insert(.content) }
        }
        if old.media != new.media || old.guides != new.guides { update.insert(.content) }
        if update.isEmpty { update.insert(.content) }
        return update
    }

    // MARK: Snapshots

    /// After changes go in: now and then, when everything here is in, a snapshot for people joining to start from.
    private func afterConfirm() {
        updateState()
        guard canEdit, let client, !client.hasPending, client.revision > lastSnapshotRevision else { return }
        snapshotWork?.cancel()
        if client.revision - lastSnapshotRevision >= 100 {
            saveSnapshot()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.saveSnapshot() }
        snapshotWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    private func saveSnapshot() {
        guard phase == .live, canEdit, let client, !client.hasPending, client.revision > lastSnapshotRevision else { return }
        lastSnapshotRevision = client.revision
        channel?.saveSnapshot(SyncSnapshot(revision: client.revision, state: state), title: title)
    }

    /// Starts from a snapshot: the presentation becomes iCloud's, and changes go on from its revision.
    private func load(_ snapshot: SyncSnapshot) {
        guard let editor else { return }
        state = snapshot.state
        lastSnapshotRevision = snapshot.revision
        if let client {
            client.reset(to: snapshot.revision)
        } else {
            client = SyncClient(revision: snapshot.revision, author: me?.id ?? "me", authorName: me?.name ?? NSFullUserName())
        }
        shown = withComments(state.presentation())
        isApplyingRemote = true
        editor.replacePresentation(shown)
        isApplyingRemote = false
        group = [:]
        groupComments = [:]
        document?.undoManager?.removeAllActions()
    }

    // MARK: Comments

    /// The presentation with every thread on its slide, oldest first.
    private func withComments(_ presentation: Presentation) -> Presentation {
        var presentation = presentation
        var bySlide: [UUID: [CommentThread]] = [:]
        for comment in threads.values { bySlide[comment.slideID, default: []].append(comment.thread) }
        for index in presentation.slides.indices {
            presentation.slides[index].comments = (bySlide[presentation.slides[index].id] ?? []).sorted { a, b in
                let first = a.comments.first?.date ?? .distantPast, second = b.comments.first?.date ?? .distantPast
                return first != second ? first < second : a.id.uuidString < b.id.uuidString
            }
        }
        return presentation
    }

    /// Comment threads made, changed or deleted here go to the talk zone. A slide deleted takes its threads out of
    /// sight only: they come back with the slide.
    private func captureComments(from old: Presentation, to new: Presentation) {
        let before = Dictionary(old.commentThreads.map { ($0.thread.id, (slide: $0.slideID, thread: $0.thread)) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.commentThreads.map { ($0.thread.id, (slide: $0.slideID, thread: $0.thread)) }, uniquingKeysWith: { first, _ in first })
        guard before.count != after.count || after.contains(where: { before[$0.key]?.thread != $0.value.thread }) else { return }
        let slides = Set(new.slides.map(\.id))
        var changed = false
        for (id, item) in after where before[id]?.thread != item.thread {
            let previous = before[id]?.thread
            if let previous {
                let known = Set(previous.comments.map(\.id))
                for reply in item.thread.comments.dropFirst() where !known.contains(reply.id) { tally.recordReply(reply.text) }
                if item.thread.isResolved, !previous.isResolved { tally.recordResolved() }
            } else {
                tally.recordComment(item.thread.first?.text ?? "")
            }
            noteGroupComment(id, slide: item.slide, before: previous, after: item.thread)
            let comment = SharedComment(thread: item.thread, slideID: item.slide)
            threads[id] = comment
            if let channel { save(comment, base: previous, using: channel) }
            changed = true
        }
        for (id, item) in before where after[id] == nil && slides.contains(item.slide) {
            noteGroupComment(id, slide: item.slide, before: item.thread, after: nil)
            threads[id] = nil
            serverComments[id] = nil
            channel?.deleteComment(id)
            changed = true
        }
        if changed { noteLocalAction() }
    }

    private func noteGroupComment(_ id: UUID, slide: UUID, before: CommentThread?, after: CommentThread?) {
        if let existing = groupComments[id] {
            groupComments[id] = (slide, existing.before, after)
        } else {
            groupComments[id] = (slide, before, after)
        }
    }

    /// Saves a thread to iCloud, trying again a few times, further apart, while it can't be reached.
    private func save(_ comment: SharedComment, base: CommentThread?, using channel: CollaborationChannel, attempt: Int = 0) {
        channel.save(comment, base: base) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(saved):
                serverComments[saved.thread.id] = saved
                // Someone else changed the thread meanwhile: theirs and ours, merged.
                if saved.thread != comment.thread { received([saved], deleted: []) }
            case .failure where attempt < 6:
                DispatchQueue.main.asyncAfter(deadline: .now() + pow(2, Double(attempt))) { [weak self] in
                    guard let self, phase == .live, let channel = self.channel, threads[comment.thread.id] == comment else { return }
                    save(comment, base: base, using: channel, attempt: attempt + 1)
                }
            case let .failure(error):
                windowController?.state.banner = "A comment couldn’t be saved to iCloud: \(error.localizedDescription)"
            }
        }
    }

    private func received(_ comments: [SharedComment], deleted: [UUID]) {
        guard phase != .ended else { return }
        if phase == .live { captureLocal() }
        for comment in comments {
            serverComments[comment.thread.id] = comment
            threads[comment.thread.id] = comment
        }
        for id in deleted {
            serverComments[id] = nil
            threads[id] = nil
        }
        guard let editor else { return }
        let presentation = withComments(shown)
        guard presentation != shown else { return }
        shown = presentation
        isApplyingRemote = true
        editor.applyShared(presentation, update: .comments)
        isApplyingRemote = false
    }

    /// Whether this person may change a comment: in a shared presentation, only what they wrote (the owner, what was
    /// written before it was shared).
    func mayEdit(authorID: String?) -> Bool {
        guard let me = me?.id else { return true }
        return authorID == me || (authorID == nil && isOwner)
    }

    /// And delete it: what they wrote, or anything if they can edit the presentation.
    func mayDelete(authorID: String?) -> Bool { mayEdit(authorID: authorID) || canEdit }

    // MARK: Telling the others

    private func noteLocalAction() {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.noticeDelay, execute: work)
    }

    /// Sends what's changed since the others were last told, to everyone else who's joined.
    func sendNotice() {
        noticeWork?.cancel()
        noticeWork = nil
        defer { tally = ChangeTally() }
        guard let me, let notice = tally.notice(author: me.name, documentTitle: title) else { return }
        let others = (sharing?.collaborators ?? []).filter { $0.id != me.id && $0.status == .joined }.map(\.id)
        guard !others.isEmpty else { return }
        channel?.sendNotice(title: notice.title, body: notice.body, to: others)
        controller.noticeSent(title: notice.title, body: notice.body, document: id, to: others)
    }

    // MARK: The header

    private func updateState() {
        guard let state = collaborationState else { return }
        state.isShared = phase != .ended
        state.isOwner = isOwner
        state.meID = me?.id
        if let sharing {
            let people = named(sharing.collaborators)
            state.collaborators = people
            state.permission = sharing.myPermission
            state.ownerName = people.first(where: \.isOwner)?.displayName ?? sharing.owner.displayName
        } else if let info {
            state.ownerName = info.ownerName
        }
        switch phase {
        case .connecting:
            if blocked == .offline {
                state.statusText = "Offline · It opens when iCloud can be reached"
                state.statusSymbol = "icloud.slash"
            } else {
                state.statusText = "Opening the shared copy from iCloud…"
                state.statusSymbol = "icloud.and.arrow.down"
            }
        case .ended:
            state.statusText = "No longer shared"
            state.statusSymbol = "icloud.slash"
        case .live:
            if let blocked {
                state.statusText = blocked == .offline ? "Offline · Changes can’t be saved until iCloud can be reached"
                    : "Changes can’t be saved to iCloud right now"
                state.statusSymbol = blocked == .offline ? "icloud.slash" : "exclamationmark.icloud"
            } else if client?.hasPending == true {
                state.statusText = "Saving to iCloud…"
                state.statusSymbol = "arrow.triangle.2.circlepath.icloud"
            } else if !canEdit {
                state.statusText = isOwner ? "Saved in iCloud" : "Shared by \(state.ownerName) · You can comment"
                state.statusSymbol = "icloud"
            } else {
                state.statusText = isOwner ? "Saved in iCloud" : "Shared by \(state.ownerName) · Saved in iCloud"
                state.statusSymbol = "checkmark.icloud"
            }
        }
    }

    /// The people in the share, named where iCloud doesn't say who they are: the owner as the presentation names them,
    /// anyone else as they name themselves when they open it.
    private func named(_ people: [Collaborator]) -> [Collaborator] {
        let presence = collaborationState?.presence ?? [:]
        var people = people
        for index in people.indices where people[index].name.isEmpty {
            if let seen = presence[people[index].id] {
                people[index].name = seen.info.name
            } else if people[index].isOwner, let owner = info?.ownerName, !owner.isEmpty {
                people[index].name = owner
            }
        }
        // One person iCloud says nothing about, and one person who opened it whom iCloud lists under no identity of
        // theirs: the same person.
        let listed = Set(people.map(\.id))
        let unlisted = presence.values.filter { $0.person != me?.id && !listed.contains($0.person) }
        let nameless = people.indices.filter {
            people[$0].name.isEmpty && people[$0].address == nil && people[$0].id != me?.id && people[$0].status == .joined
        }
        if nameless.count == 1, unlisted.count == 1, let only = unlisted.first { people[nameless[0]].name = only.info.name }
        return people
    }

    /// The owner changed how it's shared, from the sharing sheet.
    func sharingUpdated(_ sharing: DocumentSharing) {
        self.sharing = sharing
        applyPermission()
        updateState()
    }
}

// MARK: - The channel

extension PresentationCollaboration: CollaborationChannelDelegate {
    func channel(_ channel: CollaborationChannel, loaded snapshot: SyncSnapshot, info: SharedDocumentInfo) {
        guard channel === self.channel else { return }
        self.info = info
        if !isOwner, let document, document.sharedCopy?.title != info.title {
            document.sharedCopy?.title = info.title
            windowController?.updateStatus()
        }
        // A Mac that's following the log needs no snapshot; one starting, or one so far behind that the changes it's
        // missing are gone, starts from it.
        if let client, phase == .live, client.revision >= snapshot.revision || !client.isMissingChanges { return }
        let catchingUp = phase == .live
        if catchingUp {
            windowController?.pushEditingText()
            captureLocal()
            if let client, client.hasPending {
                // What's waiting to go was made on a presentation the snapshot moves past, so it can't follow.
                client.discardPending()
                windowController?.state.banner = "Your latest changes to “\(title)” couldn’t be kept while it caught up with iCloud."
            }
        }
        load(snapshot)
        if catchingUp { restoreComments() }
        let early = earlyChanges
        earlyChanges = []
        // With the changes that came ahead of the ones the snapshot now covers.
        if let client { apply(client.receive(early)) }
        if phase == .connecting { goLive() }
        lookForGap()
    }

    func channel(_ channel: CollaborationChannel, received changes: [LoggedPresentationChange]) {
        guard channel === self.channel else { return }
        guard let client, phase == .live else {
            earlyChanges += changes
            return
        }
        prepareForRemote()
        apply(client.receive(changes))
        lookForGap()
        afterConfirm()
        flush()
    }

    /// Changes came ahead of one that hasn't (iCloud passed over it while reading, say). If it still hasn't a moment
    /// later, it's asked for by name, and failing that the presentation starts again from its latest snapshot; until
    /// then nothing after it can be shown.
    private func lookForGap() {
        guard phase == .live, client?.missingRevisions != nil else {
            gapCheck?.cancel()
            gapCheck = nil
            gapDelay = 1
            return
        }
        guard gapCheck == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            gapCheck = nil
            guard phase == .live, let missing = client?.missingRevisions else { return lookForGap() }
            collaborationLog.notice("Asking again for changes \(missing.lowerBound)–\(missing.upperBound)")
            #if DEBUG
            gapRequests += 1
            #endif
            channel?.fetchChanges(missing)
            gapDelay = min(gapDelay * 2, 60)
            lookForGap()
        }
        gapCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gapDelay, execute: work)
    }

    /// After starting over from a snapshot: the comment threads as iCloud last had them.
    private func restoreComments() {
        guard let editor else { return }
        threads = serverComments
        let presentation = withComments(shown)
        guard presentation != shown else { return }
        shown = presentation
        isApplyingRemote = true
        editor.applyShared(presentation, update: .comments)
        isApplyingRemote = false
    }

    func channel(_ channel: CollaborationChannel, retitled title: String) {
        guard channel === self.channel else { return }
        info?.title = title
        guard !isOwner, let document, document.sharedCopy?.title != title else { return }
        document.sharedCopy?.title = title
        windowController?.synchronizeWindowTitleWithDocumentName()
    }

    func channel(_ channel: CollaborationChannel, receivedComments comments: [SharedComment], deleted: [UUID]) {
        guard channel === self.channel else { return }
        received(comments, deleted: deleted)
    }

    func channel(_ channel: CollaborationChannel, receivedPresence presence: [Presence]) {
        guard channel === self.channel, let state = collaborationState else { return }
        for item in presence { state.presence[item.person] = item }
        state.clock = Date()
        updateState()
        let othersActive = state.presence.values.contains { $0.person != me?.id && $0.isActive() }
        channel.pollInterval = othersActive ? 2 : 15
    }

    func channel(_ channel: CollaborationChannel, sharingChanged sharing: DocumentSharing) {
        guard channel === self.channel else { return }
        let couldEdit = canEdit
        self.sharing = sharing
        if phase == .live {
            if couldEdit, !canEdit { captureLocal() }
            applyPermission()
            if couldEdit != canEdit { announcePresence(viewing: true) }
            if couldEdit != canEdit, !isOwner {
                windowController?.state.banner = canEdit
                    ? "\(sharing.owner.displayName) changed your access: you can now edit “\(title)”."
                    : "\(sharing.owner.displayName) changed your access: you can now comment on “\(title)”, but not change it."
            }
        }
        updateState()
    }

    func channel(_ channel: CollaborationChannel, reachable: Bool) {
        guard channel === self.channel else { return }
        if reachable {
            // iCloud answers again. (A change it turned down is over only when one goes in.)
            if blocked == .offline { markOnline() }
        } else {
            block(.offline)
        }
    }

    func channel(_ channel: CollaborationChannel, becameUnavailable reason: UnavailableReason) {
        guard channel === self.channel, phase != .ended else { return }
        let ownerName = sharing?.owner.displayName ?? info?.ownerName ?? "The owner"
        end(saying: false)
        updateState()
        if isOwner {
            controller.sharingEnded(self)
        } else {
            controller.documentWentAway(self, ownerName: ownerName, reason: reason)
        }
    }
}
