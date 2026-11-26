import AppKit
import CloudKit
import PuggleSlidesKit
import UserNotifications

extension Notification.Name {
    /// Posted by `CollaborationController` when presentations shared with this person come or go, or iCloud's status
    /// changes.
    static let collaborationDidChange = Notification.Name("PuggleSlides.collaborationDidChange")
}

/// A presentation someone shared with this person, open in a window here: it has no file, only its copy in iCloud.
struct SharedCopy: Equatable {
    var id: UUID
    var ownerID: String
    var title: String
}

/// Sharing presentations through iCloud for the whole app: the presentations shared with this person, which files of
/// theirs are shared, opening shared presentations from links and notifications, and the notifications themselves.
final class CollaborationController: NSObject {
    /// The app's one controller; set as PuggleSlides starts.
    static var shared: CollaborationController!

    let service: CollaborationService
    private let defaults: UserDefaults
    private var sessions: [UUID: PresentationCollaboration] = [:]
    /// What the last notices sent said, for the self-test.
    private(set) var sentNotices: [(title: String, body: String, document: UUID, to: [String])] = []
    private static let linksKey = "PPSharedPresentationFiles"

    init(service: CollaborationService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        super.init()
        service.onStatus = { [weak self] in self?.changed() }
        service.onSharedWithMeChange = { [weak self] in self?.changed() }
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        service.start()
    }

    var status: CollaborationStatus { service.status }
    var sharedWithMe: [SharedDocumentEntry] { service.sharedWithMe }

    private func changed() {
        NotificationCenter.default.post(name: .collaborationDidChange, object: self)
    }

    // MARK: Presentations and their sessions

    func unregister(_ session: PresentationCollaboration) {
        if sessions[session.id] === session { sessions[session.id] = nil }
    }

    /// A presentation's window is up: if it's shared (a file of this person's that is, or someone else's
    /// presentation), it joins its shared copy.
    func documentOpened(_ document: PresentationDocument, in windowController: DocumentWindowController) {
        if let copy = document.sharedCopy {
            attach(document, windowController: windowController, id: copy.id, isOwner: false, ownerID: copy.ownerID).connect()
        } else if let url = document.fileURL, let id = linkedDocument(at: url) {
            attach(document, windowController: windowController, id: id, isOwner: true, ownerID: nil).connect()
        }
    }

    @discardableResult
    private func attach(_ document: PresentationDocument, windowController: DocumentWindowController, id: UUID, isOwner: Bool,
                        ownerID: String?) -> PresentationCollaboration {
        sessions[id]?.close()
        let session = PresentationCollaboration(id: id, isOwner: isOwner, ownerID: ownerID, controller: self, document: document,
                                                windowController: windowController)
        document.collaboration = session
        windowController.controller.collaboration = session
        sessions[id] = session
        return session
    }

    /// Shares a presentation of this person's for the first time. It must be saved to a file first, which stays its
    /// copy on this Mac.
    func share(_ document: PresentationDocument, in windowController: DocumentWindowController, access: LinkAccess,
               permission: CollaboratorPermission, completion: @escaping (Error?) -> Void) {
        guard let url = document.fileURL else {
            completion(CollaborationError.failed("Save the presentation on this Mac first."))
            return
        }
        requestNotificationPermission()
        windowController.finishEditing()
        let id = UUID()
        let session = attach(document, windowController: windowController, id: id, isOwner: true, ownerID: nil)
        session.startSharing(access: access, permission: permission) { [weak self, weak document] error in
            guard let self else { return }
            if let error {
                document?.collaboration = nil
                windowController.controller.collaboration = nil
                sessions[id] = nil
                windowController.state.collaboration.reset()
                completion(error)
                return
            }
            link(id, to: url)
            completion(nil)
        }
    }

    /// Stops sharing a presentation of this person's: it goes out of iCloud and from everyone it was shared with, and
    /// stays here, saved in its file.
    func stopSharing(_ session: PresentationCollaboration, completion: @escaping (Error?) -> Void) {
        service.stopSharing(session.id) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(error)
                return
            }
            sharingEnded(session)
            completion(nil)
        }
    }

    /// A presentation of this person's stopped being shared (here, or from another of their Macs).
    func sharingEnded(_ session: PresentationCollaboration) {
        session.end()
        unregister(session)
        unlink(session.id)
        guard let document = session.document else { return }
        document.collaboration = nil
        (document.windowControllers.first as? DocumentWindowController)?.sharingEnded()
        // It's kept on this Mac: saved to its file now.
        if document.fileURL != nil { document.save(nil) }
    }

    /// A presentation shared with this person went away: its owner stopped sharing it (or took them out of it), or
    /// they left. Its window says so, and closes.
    func documentWentAway(_ session: PresentationCollaboration, ownerName: String, reason: UnavailableReason) {
        unregister(session)
        guard let document = session.document else { return }
        let title = document.displayName ?? session.title
        if reason == .stopped, !NSApp.isActive {
            showNotification(title: "“\(title)” is no longer shared with you", body: "\(ownerName) stopped sharing it.")
        }
        (document.windowControllers.first as? DocumentWindowController)?.sharedCopyWentAway(ownerName: ownerName, reason: reason)
    }

    // MARK: Opening shared presentations

    /// Opens a presentation shared with this person, or brings its window forward.
    func openShared(_ entry: SharedDocumentEntry) {
        if let open = NSDocumentController.shared.documents.compactMap({ $0 as? PresentationDocument }).first(where: { $0.sharedCopy?.id == entry.id }) {
            open.showWindows()
            return
        }
        if entry.ownerID == status.me?.id || entry.ownerID == CKCurrentUserDefaultName {
            openMine(entry.id)
            return
        }
        let document = PresentationDocument()
        document.sharedCopy = SharedCopy(id: entry.id, ownerID: entry.ownerID, title: entry.title)
        document.fileType = PresentationFormat.pptx.typeIdentifier
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    /// Opens a shared presentation of this person's from its file.
    private func openMine(_ id: UUID) {
        guard let url = fileURL(of: id) else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// Joins a presentation someone shared, from the link they sent, and opens it.
    func accept(_ metadata: CKShare.Metadata) {
        guard let cloud = service as? CloudKitCollaboration else { return }
        requestNotificationPermission()
        cloud.accept(metadata) { [weak self] result in
            switch result {
            case let .success(entry):
                self?.openShared(entry)
            case let .failure(error):
                let alert = NSAlert()
                alert.messageText = "The shared presentation couldn’t be opened."
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// Joins a presentation from an invitation link pasted into PuggleSlides, and opens it: for when clicking the link
    /// opened it in a web browser instead.
    func openInvitationLink(_ url: URL, completion: ((Error?) -> Void)? = nil) {
        requestNotificationPermission()
        service.open(link: url) { [weak self] result in
            switch result {
            case let .success(entry):
                self?.openShared(entry)
                completion?(nil)
            case let .failure(error):
                completion?(error)
            }
        }
    }

    /// Asks for an invitation link, offering the one on the clipboard, and opens its presentation.
    func askForInvitationLink() {
        let alert = NSAlert()
        alert.messageText = "Open an Invitation Link"
        alert.informativeText = "Paste the link someone sent you to a presentation they shared. PuggleSlides opens it as clicking the link would have."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://www.icloud.com/share/…"
        if let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           copied.hasPrefix("https://"), !copied.contains(" ") {
            field.stringValue = copied
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else {
            showProblem("That isn’t a link.", "Copy the whole link from the message it came in, starting with https://, and try again.")
            return
        }
        openInvitationLink(url) { [weak self] error in
            if let error { self?.showProblem("The shared presentation couldn’t be opened.", error.localizedDescription) }
        }
    }

    private func showProblem(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    /// A push from iCloud: something shared has changed.
    func receivedPush(_ userInfo: [String: Any]) {
        (service as? CloudKitCollaboration)?.receivedPush(userInfo)
    }

    // MARK: Files of this person's that are shared

    private var links: [String: Data] {
        get { defaults.dictionary(forKey: Self.linksKey) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: Self.linksKey) }
    }

    /// Remembers which file a shared presentation of this person's is kept in on this Mac (as a bookmark, so it's
    /// found again after it's moved or renamed).
    func link(_ id: UUID, to url: URL) {
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        links[id.uuidString] = bookmark
    }

    func unlink(_ id: UUID) { links[id.uuidString] = nil }

    private func fileURL(of id: UUID) -> URL? {
        guard let bookmark = links[id.uuidString] else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The shared presentation a file of this person's is, if it's one.
    func linkedDocument(at url: URL) -> UUID? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for key in links.keys {
            guard let id = UUID(uuidString: key), let linked = fileURL(of: id) else { continue }
            if linked.standardizedFileURL.resolvingSymlinksInPath().path == path { return id }
        }
        return nil
    }

    /// Shared presentations of this person's, by title, for the File menu.
    var mine: [(id: UUID, title: String)] {
        links.keys.compactMap { key in
            guard let id = UUID(uuidString: key), let url = fileURL(of: id) else { return nil }
            return (id, url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// Shows a notification from this Mac (iCloud shows the summaries of other people's changes itself).
    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func noticeSent(title: String, body: String, document: UUID, to people: [String]) {
        sentNotices.append((title, body, document, people))
    }

    /// The presentation a notification is about, from the fields iCloud put in it.
    fileprivate nonisolated static func sharedDocument(in userInfo: [AnyHashable: Any]) -> (UUID, String)? {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let id = (note.recordFields?[CollaborationRecords.documentKey] as? String).flatMap(UUID.init(uuidString:)),
              let owner = note.recordFields?[CollaborationRecords.ownerKey] as? String else { return nil }
        return (id, owner)
    }
}

extension CollaborationController: UNUserNotificationCenterDelegate {
    /// Notices show even while PuggleSlides is in front, unless their presentation is the one being looked at.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let document = Self.sharedDocument(in: notification.request.content.userInfo)?.0
        let handler = UncheckedSendable(value: completionHandler)
        Task { @MainActor in
            let front = (NSApp.keyWindow?.windowController as? DocumentWindowController)?.presentationDocument
            let looking = document != nil && NSApp.isActive && (front?.collaboration?.id == document)
            handler.value(looking ? [.list] : [.banner, .list, .sound])
        }
    }

    /// Clicking a notice opens its presentation.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let target = Self.sharedDocument(in: response.notification.request.content.userInfo)
        Task { @MainActor in
            guard let (id, owner) = target, let controller = CollaborationController.shared else { return }
            let entry = controller.sharedWithMe.first { $0.id == id } ?? SharedDocumentEntry(id: id, title: "Shared presentation", ownerName: "", ownerID: owner)
            // A notice clicked while PuggleSlides isn't open opens its presentation once PuggleSlides has.
            UpdateController.shared.whenLaunched(handoff: LaunchHandoff.shared(id: id, ownerID: owner, title: entry.title).encoded) {
                controller.openShared(entry)
            }
        }
        completionHandler()
    }
}

/// Carries a value the compiler can't see is safe across to the main actor.
private nonisolated struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}
