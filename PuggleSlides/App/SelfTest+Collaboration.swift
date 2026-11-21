#if DEBUG
import AppKit
import PuggleSlidesKit

/// Drives collaboration end to end on the stand-in "iCloud" (`-PPSelfTest YES -PPSelfTestSuite collaboration`):
/// sharing the window's presentation, people on other "Macs" editing and commenting along with it, edits at the same
/// time, live typing, undo, access, the summaries sent after a quiet spell, the theme builder, stopping sharing, and
/// presentations other people share, to comment on and through an invitation link.
@MainActor
final class CollaborationSelfTest {
    private struct Step {
        let name: String
        let timeout: TimeInterval
        let act: () -> Void
        let check: () -> Bool
    }

    private let window: DocumentWindowController
    private var steps: [Step] = []
    private var failures = 0
    private let cloud = StandInCloud.shared
    private let ana = StandInPerson(Collaborator(id: "ana@example.com", name: "Ana Lopez", address: "ana@example.com"))
    private let ben = StandInPerson(Collaborator(id: "ben@example.com", name: "Ben Carter", address: "ben@example.com"))
    private let cy = StandInPerson(Collaborator(id: "cy@example.com", name: "Cy Park", address: "cy@example.com"))
    private var model: CollaborateModel!
    private var startedNotices = 0
    private var threadID: UUID?
    private var addedHere: UUID?
    private var addedThere: UUID?
    private var bensDocument: UUID?
    private var bensWindow: DocumentWindowController?
    private var renameRequestsBefore = 0
    private var titleBeforeRename = ""
    private var linkedDocument: UUID?
    private var linkRefused = false
    private var titleBeforeMine = ""
    private var offlinePresentation: Presentation?
    private var openedOffline: UUID?

    /// The window showing a presentation someone shared with this person.
    private func sharedWindow(_ id: UUID?) -> DocumentWindowController? {
        NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }.first { $0.presentationDocument?.sharedCopy?.id == id }
    }

    init(window: DocumentWindowController) { self.window = window }

    static func run() {
        PresentationCollaboration.noticeDelay = 1
        StandInCloud.shared.latency = 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // A fresh presentation of its own, so presentations macOS restored at launch are left alone.
            let existing = Set(NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }.map(ObjectIdentifier.init))
            NSDocumentController.shared.newDocument(nil)
            guard let window = NSApp.windows.compactMap({ $0.windowController as? DocumentWindowController })
                .first(where: { !existing.contains(ObjectIdentifier($0)) }) else {
                print("SELFTEST FAIL: no presentation window")
                exit(1)
            }
            window.window?.makeKeyAndOrderFront(nil)
            let test = CollaborationSelfTest(window: window)
            test.defineSteps()
            test.next()
        }
    }

    private var controller: PresentationController { window.controller }
    private var presentation: Presentation { controller.realPresentation }
    private var document: PresentationDocument { window.presentationDocument! }
    private var state: CollaborationState { window.state.collaboration }
    private var session: PresentationCollaboration? { document.collaboration }
    private var everythingSent: Bool { !(session?.hasUnsentChanges ?? true) }

    /// A picture too big to travel inside a change record (its noise doesn't compress), as a pasted photo is.
    private static let testPicture: Data = {
        let width = 640, height = 480
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 3,
                                         hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 3, bitsPerPixel: 24),
              let pixels = rep.bitmapData else { return Data() }
        var seed: UInt32 = 20_261_120
        for index in 0..<(width * height * 3) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }()

    /// Whether a slide's last object is the test picture, its media there with it.
    private static func holdsTestPicture(_ presentation: Presentation?, slide: Int) -> Bool {
        guard let presentation, presentation.slides.indices.contains(slide), let picture = presentation.slides[slide].elements.last?.picture
        else { return false }
        return presentation.media[picture.mediaID]?.data == testPicture
    }

    /// The slides, themes and size, without comments: what two Macs must agree on.
    private func same(_ a: Presentation, _ b: Presentation) -> Bool {
        func plain(_ presentation: Presentation) -> Presentation {
            var presentation = presentation
            presentation.media = [:]
            for index in presentation.slides.indices { presentation.slides[index].comments = [] }
            return presentation
        }
        return plain(a) == plain(b)
    }

    private func text(_ slide: Int, _ element: Int, in presentation: Presentation? = nil) -> String? {
        let presentation = presentation ?? self.presentation
        guard presentation.slides.indices.contains(slide), presentation.slides[slide].elements.indices.contains(element) else { return nil }
        return presentation.slides[slide].elements[element].shape?.text?.plainText
    }

    private func thread(_ text: String) -> CommentThread? {
        presentation.commentThreads.first { $0.thread.first?.text == text }?.thread
    }

    /// Edits an object on a slide, as a person would through the toolbar or a panel.
    private func editHere(slide: Int, element: Int, _ actionName: String, _ edit: @escaping (inout SlideElement) -> Void) {
        controller.selectSlide(presentation.slides[slide].id)
        let id = presentation.slides[slide].elements[element].id
        controller.editElements([id], actionName) { element, _ in edit(&element) }
    }

    /// A step that acts, then waits until its check passes (or gives up).
    private func step(_ name: String, timeout: TimeInterval = 4, _ act: @escaping () -> Void = {}, until check: @escaping () -> Bool) {
        steps.append(Step(name: name, timeout: timeout, act: act, check: check))
    }

    private func next() {
        guard !steps.isEmpty else {
            print(failures == 0 ? "SELFTEST DONE: all passed" : "SELFTEST DONE: \(failures) failed")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        let step = steps.removeFirst()
        step.act()
        // Steps run from timers, not events: an empty application event closes the undo group an edit opened, as a
        // key press or click would.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
        let deadline = Date().addingTimeInterval(step.timeout)
        func poll() {
            if step.check() {
                print("SELFTEST PASS: \(step.name)")
                fflush(stdout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.next() }
            } else if Date() > deadline {
                failures += 1
                print("SELFTEST FAIL: \(step.name) — slides here \(presentation.slides.count), there \(ana.presentation.slides.count); "
                      + "titles here \(presentation.slides.map { $0.elements.first?.shape?.text?.plainText ?? "-" }), "
                      + "there \(ana.presentation.slides.map { $0.elements.first?.shape?.text?.plainText ?? "-" }); "
                      + "pending \(session?.hasUnsentChanges ?? false) \(session?.undoDescription ?? "")")
                print("SELFTEST INFO: notices \(cloud.notices.dropFirst(startedNotices).map { "\($0.to): \($0.title) / \($0.body)" })")
                fflush(stdout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.next() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
    }

    /// Has the stand-in tell everyone in the window's presentation how it's shared, afresh.
    private func refreshSharing() {
        guard let id = session?.id, let document = cloud.documents[id] else { return }
        document.sharingVersion += 1
        cloud.changed(id)
    }

    /// Runs `work` once `window` is the key window: a window brought to the front becomes key a moment later.
    private static func whenKey(_ window: NSWindow?, attempt: Int = 0, _ work: @escaping () -> Void) {
        if NSApp.keyWindow === window || attempt >= 40 {
            work()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { whenKey(window, attempt: attempt + 1, work) }
        }
    }

    private func defineSteps() {
        // MARK: Renaming

        step("the File menu has one Rename, the standard one") {} until: {
            let file = NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu
            file?.update()
            let renames = file?.items.filter { $0.title.hasPrefix("Rename") } ?? []
            return renames.count == 1 && renames.first?.action == NSSelectorFromString("renameDocument:")
        }
        step("Rename selects the whole name in the header, ready to type over") {
            self.renameRequestsBefore = self.window.state.renameRequest
            self.titleBeforeRename = self.window.state.title
            self.window.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            // As File ▸ Rename is chosen: from the window in front, once it is.
            Self.whenKey(self.window.window) { NSApp.sendAction(NSSelectorFromString("renameDocument:"), to: nil, from: nil) }
        } until: {
            guard self.window.state.renameRequest > self.renameRequestsBefore,
                  let field = self.window.window?.firstResponder as? NSTextView, field.isFieldEditor, !field.string.isEmpty
            else { return false }
            return field.selectedRange() == NSRange(location: 0, length: (field.string as NSString).length)
        }
        step("leaving the name as it was changes nothing") {
            self.window.window?.makeFirstResponder(nil)
        } until: {
            !((self.window.window?.firstResponder as? NSTextView)?.isFieldEditor ?? false) && self.window.state.title == self.titleBeforeRename
        }

        // MARK: Sharing a presentation of this person's

        step("a new presentation isn't shared") {
            self.editHere(slide: 0, element: 0, "Typing") { $0.shape?.text = TextBody("Launch plan") }
        } until: {
            !self.state.isShared && self.text(0, 0) == "Launch plan" && self.window.state.showsCollaborateButton
        }
        step("it's saved on this Mac before it's shared") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Collaboration self-test \(UUID().uuidString.prefix(6)).pptx")
            self.document.save(to: url, ofType: PresentationFormat.pptx.typeIdentifier, for: .saveAsOperation) { _ in }
        } until: {
            self.document.fileURL != nil
        }
        step("sharing makes it live, with undo kept for the shared presentation") {
            self.model = CollaborateModel(controller: CollaborationController.shared, windowController: self.window)
            self.model.share()
        } until: {
            self.state.isShared && self.session?.phase == .live && self.controller.collaboration === self.session
                && self.cloud.documents[self.session?.id ?? UUID()] != nil && self.state.statusText == "Saved in iCloud"
                && self.document.undoManager?.canUndo == false
        }
        step("invited people join, one to edit and one to comment") {
            self.model.address = "ana@example.com"
            self.model.invitePermission = .edit
            self.model.invite()
            self.model.address = "ben@example.com"
            self.model.invitePermission = .comment
            self.model.invite()
        } until: {
            self.state.collaborators.count == 3 && self.state.collaborators.allSatisfy { $0.status == .joined }
                && self.state.collaborators.first(where: { $0.id == "ben@example.com" })?.permission == .comment
        }
        step("a collaborator's Mac opens it with the same slides") {
            self.ana.join(self.session!.id)
        } until: {
            self.ana.presentation.slides.count == 1 && self.same(self.ana.presentation, self.presentation)
        }
        step("their edit shows up here") {
            self.ana.edit { $0.slides[0].elements[1].shape?.text = TextBody("From Ana") }
        } until: {
            self.text(0, 1) == "From Ana"
        }
        step("a picture they paste arrives as the same picture") {
            self.ana.insertPicture(Self.testPicture, onSlide: 0)
        } until: {
            Self.holdsTestPicture(self.presentation, slide: 0) && self.same(self.ana.presentation, self.presentation)
        }
        step("a slide added here reaches them") {
            self.controller.newSlide()
            self.addedHere = self.controller.currentSlideID
        } until: {
            self.presentation.slides.count == 2 && self.same(self.ana.presentation, self.presentation) && self.everythingSent
        }
        step("typing in a text box reaches them before editing ends") {
            guard let slide = self.controller.currentSlide, let title = slide.elements.first else { return }
            self.window.canvas.beginEditing(title.id, at: nil)
            for character in "Live words" {
                self.window.canvas.editor?.textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        } until: {
            self.window.canvas.editor != nil && self.text(1, 0, in: self.ana.presentation) == "Live words"
        }
        step("finishing typing makes one undo step, and leaves both Macs the same") {
            self.window.canvas.endEditing()
        } until: {
            self.window.canvas.editor == nil && self.document.undoManager?.undoActionName == "Typing" && self.everythingSent
                && self.same(self.ana.presentation, self.presentation)
        }

        // MARK: Editing at the same time

        step("moving an object here while they type in it keeps both") {
            self.editHere(slide: 0, element: 1, "Move") { $0.placement = Placement(frame: SlideRect(x: 50, y: 60, width: 300, height: 80)) }
            self.ana.edit { $0.slides[0].elements[1].shape?.text = TextBody("Ana typed while it moved") }
        } until: {
            let element = self.presentation.slides[0].elements[1]
            return element.placement?.frame.x == 50 && element.shape?.text?.plainText == "Ana typed while it moved"
                && self.everythingSent && !self.ana.hasPending && self.same(self.ana.presentation, self.presentation)
        }
        step("different objects on one slide, changed at once, both change") {
            self.editHere(slide: 0, element: 0, "Fill") { $0.shape?.fill = .solid(ColorRef(RGBColor(red: 250, green: 240, blue: 200))) }
            self.ana.edit { $0.slides[0].elements[1].placement = Placement(frame: SlideRect(x: 70, y: 60, width: 300, height: 80)) }
        } until: {
            let slide = self.presentation.slides[0]
            return slide.elements[0].shape?.fill == .solid(ColorRef(RGBColor(red: 250, green: 240, blue: 200)))
                && slide.elements[1].placement?.frame.x == 70 && self.everythingSent && !self.ana.hasPending
                && self.same(self.ana.presentation, self.presentation)
        }
        step("slides added on both Macs at once both stay, in the same order") {
            self.controller.selectSlide(self.presentation.slides[1].id)
            self.controller.newSlide()
            self.addedHere = self.controller.currentSlideID
            self.ana.edit { presentation in
                var slide = presentation.makeSlide(layoutID: presentation.themes[0].layouts[0].id)
                slide.notes = TextBody("Ana’s slide")
                self.addedThere = slide.id
                presentation.slides.append(slide)
            }
        } until: {
            let ids = Set(self.presentation.slides.map(\.id))
            return self.presentation.slides.count == 4 && ids.contains(self.addedHere ?? UUID()) && ids.contains(self.addedThere ?? UUID())
                && self.everythingSent && !self.ana.hasPending && self.same(self.ana.presentation, self.presentation)
        }

        // MARK: Undo

        step("a change here goes to them") {
            self.titleBeforeMine = self.text(0, 0) ?? ""
            self.editHere(slide: 0, element: 0, "Edit Title") { $0.shape?.text = TextBody("Mine") }
        } until: {
            self.text(0, 0, in: self.ana.presentation) == "Mine" && self.everythingSent
        }
        step("their change comes in after it") {
            self.ana.edit { $0.slides[0].elements[1].shape?.text = TextBody("Theirs after") }
        } until: {
            self.text(0, 1) == "Theirs after"
        }
        step("undo takes back only this Mac's change, for everyone") {
            self.document.undoManager?.undo()
        } until: {
            self.text(0, 0) == self.titleBeforeMine && self.text(0, 1) == "Theirs after" && self.everythingSent
                && self.same(self.ana.presentation, self.presentation)
        }
        step("redo brings it back for everyone") {
            self.document.undoManager?.redo()
        } until: {
            self.text(0, 0) == "Mine" && self.text(0, 1) == "Theirs after" && self.everythingSent && self.same(self.ana.presentation, self.presentation)
        }

        // MARK: Who's here

        step("the header shows who else is in it, viewing now") {} until: {
            let others = self.state.others
            guard let ana = others.first(where: { $0.id == "ana@example.com" }) else { return false }
            return others.count == 2 && ana.initials == "AL" && self.state.isViewing(ana)
        }
        step("when iCloud doesn't say who people are, the header still names them") {
            self.cloud.hidesIdentities = true
            self.refreshSharing()
        } until: {
            guard self.state.collaborators.contains(where: { $0.id.hasPrefix("hidden-") }) else { return false }
            let others = self.state.others
            guard let ana = others.first(where: { $0.displayName == "Ana Lopez" }) else { return false }
            return ana.initials == "AL" && self.state.isViewing(ana) && !others.contains { $0.displayName == "Someone" }
        }
        step("and iCloud's names come back when it says them") {
            self.cloud.hidesIdentities = false
            self.refreshSharing()
        } until: {
            !self.state.collaborators.contains { $0.id.hasPrefix("hidden-") } && self.state.others.contains { $0.id == "ana@example.com" }
        }

        // MARK: Comments

        step("their comment shows here, on its slide") {
            self.threadID = self.ana.comment("Can we add dates?", onSlide: self.presentation.slides[0].id)
        } until: {
            self.presentation.slides[0].comments.contains { $0.first?.text == "Can we add dates?" }
        }
        step("a comment here reaches them, signed by this Mac's person") {
            self.controller.addComment("Which dates?", about: nil, onSlide: self.presentation.slides[1].id)
        } until: {
            self.ana.comments.values.contains { $0.thread.first?.text == "Which dates?" && $0.thread.first?.authorID == StandInCloud.me.id
                && $0.slideID == self.presentation.slides[1].id }
        }
        step("replies go both ways") {
            guard let id = self.threadID else { return }
            self.controller.replyToComment(id, text: "Yes, by Friday.")
            self.ana.reply("Thanks!", to: id)
        } until: {
            guard let thread = self.thread("Can we add dates?") else { return false }
            return Set(thread.comments.dropFirst().map(\.text)) == ["Yes, by Friday.", "Thanks!"]
                && Set(self.ana.comments[thread.id]?.thread.comments.dropFirst().map(\.text) ?? []) == ["Yes, by Friday.", "Thanks!"]
        }
        step("resolving here reaches them") {
            guard let id = self.threadID else { return }
            self.controller.setThread(id, resolved: true)
        } until: {
            self.ana.comments[self.threadID ?? UUID()]?.thread.isResolved == true
        }
        step("their reply comes in while it's resolved") {
            guard let id = self.threadID else { return }
            self.ana.reply("One more thing", to: id)
        } until: {
            self.thread("Can we add dates?")?.comments.contains { $0.text == "One more thing" } == true
        }
        step("undo opens it again here and there, and keeps their reply") {
            self.document.undoManager?.undo()
        } until: {
            guard let here = self.thread("Can we add dates?"), let there = self.ana.comments[here.id]?.thread else { return false }
            return !here.isResolved && here.comments.contains { $0.text == "One more thing" }
                && !there.isResolved && there.comments.contains { $0.text == "One more thing" }
        }
        step("people edit only their own comments") {} until: {
            guard let thread = self.thread("Can we add dates?"), let theirs = thread.first,
                  let mine = thread.comments.first(where: { $0.text == "Yes, by Friday." }) else { return false }
            return !self.controller.mayEditComment(theirs) && self.controller.mayEditComment(mine) && self.controller.mayDeleteComment(theirs)
        }

        // MARK: Access

        step("taking them down to commenting stops their edits") {
            guard let ana = self.state.collaborators.first(where: { $0.id == "ana@example.com" }) else { return }
            self.model.setPermission(.comment, for: ana)
        } until: {
            self.ana.sharing?.myPermission == .comment
        }
        step("their changes are turned down, and don't reach this Mac") {
            self.ana.edit { $0.slides[0].elements[0].shape?.text = TextBody("NOPE") }
        } until: {
            self.ana.refusals > 0 && self.text(0, 0) == "Mine" && self.text(0, 0, in: self.ana.presentation) == "Mine"
        }
        step("but they can still comment") {
            self.ana.comment("Still reading along", onSlide: self.presentation.slides[0].id)
        } until: {
            self.presentation.slides[0].comments.contains { $0.first?.text == "Still reading along" }
        }

        // MARK: Telling the others

        step("after a quiet spell the others get one summary of it all") {
            self.startedNotices = self.cloud.notices.count
        } until: {
            let fresh = self.cloud.notices.dropFirst(self.startedNotices)
            let toAna = fresh.filter { $0.to == "ana@example.com" }
            guard toAna.count == 1, let notice = toAna.first else { return false }
            return notice.title.hasPrefix("Alex Morgan ") && !notice.body.isEmpty && fresh.contains { $0.to == "ben@example.com" }
        }
        step("the next quiet spell brings a summary of what's new since") {
            self.startedNotices = self.cloud.notices.count
            self.controller.newSlide()
        } until: {
            let toAna = self.cloud.notices.dropFirst(self.startedNotices).filter { $0.to == "ana@example.com" }
            return toAna.count == 1 && toAna.first?.title.hasPrefix("Alex Morgan edited “Collaboration self-test") == true
                && toAna.first?.body == "Added a slide."
        }

        // MARK: Offline

        step("when iCloud can't be reached, it can't be changed, and the window says why") {
            // Typing under way when the connection drops ends without what wasn't saved yet.
            self.controller.selectSlide(self.presentation.slides[0].id)
            if let title = self.presentation.slides[0].elements.first {
                self.window.canvas.beginEditing(title.id, at: nil)
                self.window.canvas.editor?.textView.insertText(" Unsaved", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            self.cloud.isReachable = false
        } until: {
            let undo = NSMenuItem(title: "Undo", action: #selector(UndoCommands.undo(_:)), keyEquivalent: "")
            let comment = NSMenuItem(title: "Comment", action: #selector(SlideCommands.ppInsertComment(_:)), keyEquivalent: "")
            let theme = NSMenuItem(title: "Edit theme", action: #selector(SlideCommands.ppEditTheme(_:)), keyEquivalent: "")
            guard let mine = self.thread("Which dates?")?.first else { return false }
            return self.window.state.access == .offline && !self.controller.canEditContent && self.window.canvas.editor == nil
                && self.text(0, 0)?.contains("Unsaved") == false
                && self.state.statusText == "Offline · Changes can’t be saved until iCloud can be reached"
                && (self.window.state.banner ?? "").hasPrefix("You’re offline, so changes to")
                && self.window.window?.undoManager == nil && !(self.window.window?.validateUserInterfaceItem(undo) ?? true)
                && !self.window.validateMenuItem(comment) && !self.window.validateMenuItem(theme)
                && self.controller.commentsAreReadOnly && !self.controller.mayEditComment(mine) && !self.controller.mayDeleteComment(mine)
                && !self.window.notes.textView.isEditable && !(self.session?.hasUnsentChanges ?? true)
        }
        step("meanwhile editing, commenting and undo change nothing, and nothing waits to be sent") {
            self.offlinePresentation = self.presentation
            self.editHere(slide: 0, element: 0, "Typing") { $0.shape?.text = TextBody("Offline?") }
            self.controller.newSlide()
            self.controller.addComment("Offline comment", about: nil, onSlide: self.presentation.slides[0].id)
            if let id = self.threadID {
                self.controller.replyToComment(id, text: "Offline reply")
                self.controller.setThread(id, resolved: true)
            }
            self.window.window?.undoManager?.undo()
            self.controller.openThemeBuilder()
            // Someone else comments while this Mac is away.
            self.ana.comment("While you were away", onSlide: self.presentation.slides[0].id)
        } until: {
            self.presentation == self.offlinePresentation && !self.controller.isThemeBuilderOpen && !(self.session?.hasUnsentChanges ?? true)
        }
        step("once iCloud's back, it can be changed again and catches up with what others did", timeout: 12) {
            self.cloud.isReachable = true
        } until: {
            self.window.state.access == .full && self.controller.canEditContent && self.window.state.banner == nil
                && !self.state.statusText.hasPrefix("Offline") && self.window.window?.undoManager === self.document.undoManager
                && !self.controller.commentsAreReadOnly && self.window.notes.textView.isEditable
                && self.presentation.slides[0].comments.contains { $0.first?.text == "While you were away" }
        }

        // MARK: The theme builder

        step("theme changes made in the theme builder reach them as one undo step") {
            self.controller.openThemeBuilder()
            self.controller.setBuilderThemeColor(.accent1, to: RGBColor(red: 200, green: 20, blue: 20))
            self.controller.closeThemeBuilder()
        } until: {
            self.ana.presentation.themes.first?.colors.colors[.accent1] == RGBColor(red: 200, green: 20, blue: 20)
                && !self.controller.isThemeBuilderOpen && self.document.undoManager?.undoActionName == "Edit Theme" && self.everythingSent
        }
        step("renaming it here renames it for everyone it's shared with") {
            self.window.rename(to: "Renamed launch plan")
        } until: {
            self.cloud.documents[self.session?.id ?? UUID()]?.title == "Renamed launch plan" && self.window.state.title == "Renamed launch plan"
                && self.window.state.showsCollaborateButton
        }

        // MARK: Stopping

        step("stopping sharing keeps the presentation here, and closes it for the others") {
            self.model.stopSharing()
        } until: {
            !self.state.isShared && self.document.collaboration == nil && self.controller.collaboration == nil && self.ana.isGone
                && self.window.state.access == .full && self.text(0, 0) == "Mine" && self.cloud.documents.isEmpty
        }

        // MARK: A presentation someone else shares

        step("a presentation shared with this person opens in a window of its own") {
            var deck = Presentation.makeDefault()
            deck.slides[0].elements[0].shape?.text = TextBody("Ben’s deck")
            self.bensDocument = self.ben.share(title: "Ben’s deck", presentation: deck, with: [(StandInCloud.me, .comment)])
        } until: {
            guard let id = self.bensDocument, let entry = CollaborationController.shared.sharedWithMe.first(where: { $0.id == id }) else { return false }
            if self.bensWindow == nil {
                CollaborationController.shared.openShared(entry)
                self.bensWindow = NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }
                    .first { $0.presentationDocument?.sharedCopy?.id == id }
            }
            guard let window = self.bensWindow else { return false }
            return self.same(window.controller.realPresentation, self.ben.presentation) && window.presentationDocument?.collaboration?.phase == .live
        }
        step("it's view-only here, but can be commented on") {
            guard let window = self.bensWindow, let slide = window.controller.currentSlideID else { return }
            window.controller.addComment("Thanks for these", about: nil, onSlide: slide)
        } until: {
            guard let window = self.bensWindow else { return false }
            let collaborate = NSMenuItem(title: "Collaborate…", action: #selector(SlideCommands.ppCollaborate(_:)), keyEquivalent: "")
            let leave = NSMenuItem(title: "Leave", action: #selector(SlideCommands.ppLeaveShared(_:)), keyEquivalent: "")
            let newSlide = NSMenuItem(title: "New slide", action: #selector(SlideCommands.ppNewSlide(_:)), keyEquivalent: "")
            let comment = NSMenuItem(title: "Comment", action: #selector(SlideCommands.ppInsertComment(_:)), keyEquivalent: "")
            return window.state.access == .commentOnly && self.ben.comments.values.contains { $0.thread.first?.text == "Thanks for these" }
                && !window.state.showsCollaborateButton && !window.validateMenuItem(collaborate) && collaborate.isHidden
                && window.validateMenuItem(leave) && !leave.isHidden && !window.validateMenuItem(newSlide) && window.validateMenuItem(comment)
                && !window.notes.textView.isEditable
        }
        step("editing it changes nothing") {
            guard let window = self.bensWindow, let slide = window.controller.currentSlide, let title = slide.elements.first else { return }
            window.controller.newSlide()
            window.controller.editElements([title.id], "Typing") { element, _ in element.shape?.text = TextBody("Sneaky") }
            window.canvas.beginEditing(title.id, at: nil)
        } until: {
            guard let window = self.bensWindow else { return false }
            return window.canvas.editor == nil && self.same(window.controller.realPresentation, self.ben.presentation)
                && window.controller.realPresentation.slides.count == 1 && self.text(0, 0, in: self.ben.presentation) == "Ben’s deck"
        }
        step("its owner's edits show up live") {
            self.ben.edit { $0.slides[0].elements[0].shape?.text = TextBody("Ben’s updated deck") }
        } until: {
            self.text(0, 0, in: self.bensWindow?.controller.realPresentation) == "Ben’s updated deck"
        }
        step("a change iCloud passes over while reading still comes, and so do the ones after it", timeout: 12) {
            guard let id = self.bensDocument else { return }
            self.cloud.skippedRevisions = [(self.cloud.documents[id]?.changes.keys.max() ?? 0) + 1]
            self.ben.edit { $0.slides[0].elements[0].shape?.text = TextBody("Skipped?") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.ben.edit { $0.slides[0].elements[1].shape?.text = TextBody("After.") } }
        } until: {
            guard let window = self.bensWindow else { return false }
            let shown = window.controller.realPresentation
            return self.text(0, 0, in: shown) == "Skipped?" && self.text(0, 1, in: shown) == "After." && self.same(shown, self.ben.presentation)
                && (window.presentationDocument?.collaboration?.gapRequests ?? 0) > 0
        }
        step("its owner's comments show up here as they're made, on their slide") {
            self.cloud.skippedRevisions = []
            if let slide = self.ben.presentation.slides.first?.id { self.ben.comment("Dates are in the appendix", onSlide: slide) }
        } until: {
            self.bensWindow?.controller.realPresentation.slides.first?.comments.contains { $0.first?.text == "Dates are in the appendix" } == true
        }
        step("a picture its owner pastes shows up here") {
            self.ben.insertPicture(Self.testPicture, onSlide: 0)
        } until: {
            guard let window = self.bensWindow else { return false }
            return Self.holdsTestPicture(window.controller.realPresentation, slide: 0) && self.same(window.controller.realPresentation, self.ben.presentation)
        }
        step("its owner renaming it renames it here") {
            self.ben.rename("Ben’s renamed deck")
        } until: {
            self.bensWindow?.state.title == "Ben’s renamed deck" && self.bensWindow?.presentationDocument?.displayName == "Ben’s renamed deck"
        }
        step("it can still be presented, printed, downloaded and copied") {} until: {
            guard let window = self.bensWindow, let document = window.presentationDocument else { return false }
            let present = NSMenuItem(title: "Slideshow", action: #selector(SlideCommands.ppStartSlideshow(_:)), keyEquivalent: "")
            let print = NSMenuItem(title: "Print", action: #selector(SlideCommands.ppPrint(_:)), keyEquivalent: "")
            let download = NSMenuItem(title: "Download", action: #selector(SlideCommands.ppDownload(_:)), keyEquivalent: "")
            let copy = NSMenuItem(title: "Make a copy", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "")
            return window.validateMenuItem(present) && window.validateMenuItem(print) && window.validateMenuItem(download)
                && document.validateUserInterfaceItem(copy) && (try? document.data(ofType: PresentationFormat.pptx.typeIdentifier)) != nil
        }
        step("when its owner stops sharing, it goes, saying so") {
            self.ben.stopSharing()
        } until: {
            guard let window = self.bensWindow?.window else { return true }
            guard let alert = window.attachedSheet, self.bensWindow?.controller.realPresentation.slides.isEmpty == true else { return false }
            window.endSheet(alert, returnCode: .alertFirstButtonReturn)
            return true
        }
        step("its window closes") {} until: {
            !NSApp.windows.contains { ($0.windowController as? DocumentWindowController)?.presentationDocument?.sharedCopy != nil }
        }

        // MARK: An invitation link pasted in

        step("an invitation link pasted into PuggleSlides opens its presentation") {
            let id = self.cy.share(title: "Cy’s slides", presentation: Presentation.makeDefault(), with: [], access: .anyoneWithLink)
            self.linkedDocument = id
            CollaborationController.shared.openInvitationLink(URL(string: "https://share.pugglesoft.invalid/\(id.uuidString.lowercased())")!)
        } until: {
            NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }.contains {
                $0.presentationDocument?.sharedCopy?.id == self.linkedDocument && $0.state.access == .commentOnly
            } && CollaborationController.shared.sharedWithMe.contains { $0.id == self.linkedDocument }
        }
        step("a shared presentation opened while offline waits, saying so") {
            let id = self.cy.share(title: "Cy’s offline slides", presentation: Presentation.makeDefault(), with: [(StandInCloud.me, .comment)])
            self.openedOffline = id
            self.cloud.isReachable = false
            if let entry = CollaborationController.shared.sharedWithMe.first(where: { $0.id == id }) { CollaborationController.shared.openShared(entry) }
        } until: {
            guard let window = self.sharedWindow(self.openedOffline) else { return false }
            return window.state.access == .locked && window.state.collaboration.statusText == "Offline · It opens when iCloud can be reached"
                && (window.state.banner ?? "").hasPrefix("You’re offline, so “Cy’s offline slides” can’t be opened")
                && window.controller.realPresentation.slides.count == 1
        }
        step("and opens once iCloud can be reached", timeout: 12) {
            self.cloud.isReachable = true
        } until: {
            guard let window = self.sharedWindow(self.openedOffline) else { return false }
            return window.state.access == .commentOnly && window.state.banner == nil
                && window.presentationDocument?.collaboration?.phase == .live && self.same(window.controller.realPresentation, self.cy.presentation)
        }
        step("a link to a presentation shared only with other people doesn't open") {
            let id = self.cy.share(title: "Cy’s private slides", presentation: Presentation.makeDefault(), with: [], access: .invited)
            CollaborationController.shared.openInvitationLink(URL(string: "https://share.pugglesoft.invalid/\(id.uuidString.lowercased())")!) { error in
                self.linkRefused = error != nil
            }
        } until: {
            self.linkRefused
        }
    }
}
#endif
