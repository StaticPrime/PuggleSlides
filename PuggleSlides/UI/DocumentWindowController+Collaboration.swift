import AppKit
import PuggleSlidesKit

/// File ▸ Collaborate…, File ▸ Leave shared presentation…, and what the window does as sharing starts, changes and ends.
extension DocumentWindowController {
    /// The Collaborate sheet: sharing the presentation, or seeing and changing who it's shared with.
    func showCollaborate() {
        guard let controller = CollaborationController.shared else { return }
        finishEditing()
        let model = CollaborateModel(controller: controller, windowController: self)
        presentSheet { dismiss in
            model.done = dismiss
            return CollaborateView(model: model)
        }
    }

    func ppCollaborate(_ sender: Any?) { showCollaborate() }

    /// Leaves a presentation someone shared with this person, once they say so: it closes, and they're out of it.
    func ppLeaveShared(_ sender: Any?) {
        guard let document = presentationDocument, let session = document.collaboration, !session.isOwner, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Leave “\(state.title)”?"
        alert.informativeText = "It closes on this Mac, and you’re no longer in it. \(state.collaboration.ownerName) can share it with you again."
        alert.addButton(withTitle: "Leave")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                CollaborationController.shared?.service.leave(session.id) { error in
                    if let error {
                        let problem = NSAlert()
                        problem.messageText = "You couldn’t leave “\(self.state.title)”."
                        problem.informativeText = error.localizedDescription
                        problem.beginSheetModal(for: window)
                        return
                    }
                    session.end()
                    document.close()
                }
            }
        }
    }

    /// The header's Add comment, while the presentation can only be commented on.
    func startComment() { ppInsertComment(nil) }

    /// Locks or unlocks editing as sharing allows. People who may only comment can still select, present, comment,
    /// save a copy and print.
    func setAccess(_ access: DocumentAccess) {
        guard state.access != access else { return }
        if access != .full {
            // Text being typed ends (offline, what wasn't saved yet goes: nothing made then is kept).
            finishEditing()
            if controller.isThemeBuilderOpen { controller.closeThemeBuilder() }
            state.tool = .select
            paintFormat = nil
            state.isPaintFormatActive = false
            if let sidebar = state.sidebar, sidebar != .comments { closeSidebar() }
            if access != .commentOnly { state.commentDraft = nil }
            if isEditingNotes { window?.makeFirstResponder(canvas) }
        }
        state.access = access
        notes.reload()
        refreshState()
        updateStatus()
    }

    /// In a shared presentation: the text being typed on the slide goes into the presentation, for the others.
    func pushEditingText() { canvas.pushEditingText() }

    /// In a shared presentation: someone else changed the text being edited here.
    func reloadEditingText() { canvas.reloadEditingText() }

    /// The presentation stopped being shared: it carries on here as an ordinary presentation, saved in its file.
    func sharingEnded() {
        state.collaboration.reset()
        setAccess(.full)
        controller.collaboration = nil
        updateStatus()
        state.banner = "“\(state.title)” is no longer shared. It’s saved on this Mac, and nobody else can open it any longer."
    }

    /// A presentation someone shared went away: its slides go at once, the window says why, and closes.
    func sharedCopyWentAway(ownerName: String, reason: UnavailableReason) {
        guard let document = presentationDocument, let window else { return }
        let title = document.displayName ?? state.title
        setAccess(.locked)
        controller.collaboration = nil
        controller.replacePresentation(Presentation(themes: document.presentation.themes))
        state.collaboration.reset()
        guard reason == .stopped else {
            document.close()
            return
        }
        let alert = NSAlert()
        alert.messageText = "“\(title)” is no longer shared with you"
        alert.informativeText = "\(ownerName) stopped sharing it, so it can’t be opened here any longer."
        alert.addButton(withTitle: "OK")
        window.attachedSheet.map { window.endSheet($0) }
        alert.beginSheetModal(for: window) { _ in
            MainActor.assumeIsolated { document.close() }
        }
    }

    /// What may be done while the presentation can only be commented on: looking, presenting, commenting, finding,
    /// copying, saving a copy and printing.
    static let commentingActions: Set<Selector> = [
        #selector(NSText.copy(_:)), #selector(NSText.selectAll(_:)), #selector(SlideCommands.ppSelectNone(_:)),
        #selector(SlideCommands.ppInsertComment(_:)), #selector(SlideCommands.ppShowCommentHistory(_:)), #selector(SlideCommands.ppToggleComments(_:)),
        #selector(SlideCommands.ppFocusFilmstrip(_:)), #selector(SlideCommands.ppFocusCanvas(_:)), #selector(SlideCommands.ppFocusSpeakerNotes(_:)),
        #selector(SlideCommands.ppFind(_:)), #selector(SlideCommands.ppFindNext(_:)), #selector(SlideCommands.ppFindPrevious(_:)),
        #selector(SlideCommands.ppDownload(_:)), #selector(SlideCommands.ppPrintSettings(_:)), #selector(SlideCommands.ppPrint(_:)),
        #selector(SlideCommands.ppStartSlideshow(_:)), #selector(SlideCommands.ppStartSlideshowFromBeginning(_:)), #selector(SlideCommands.ppPresenterView(_:)),
        #selector(SlideCommands.ppToggleGridView(_:)), #selector(SlideCommands.ppToggleSpeakerNotes(_:)), #selector(SlideCommands.ppPlayClip(_:)),
        #selector(SlideCommands.ppZoomIn(_:)), #selector(SlideCommands.ppZoomOut(_:)), #selector(SlideCommands.ppZoomFit(_:)), #selector(SlideCommands.ppSetZoom(_:)),
        #selector(SlideCommands.ppShowRuler(_:)), #selector(SlideCommands.ppShowGuides(_:)), #selector(SlideCommands.ppToggleSpellCheck(_:)),
        #selector(SlideCommands.ppShowShortcuts(_:)),
        #selector(SlideCommands.ppCollaborate(_:)), #selector(SlideCommands.ppLeaveShared(_:)),
        #selector(UndoCommands.undo(_:)), #selector(UndoCommands.redo(_:)),
    ]

    /// Menu items for sharing, and what can't be done while the presentation can only be commented on.
    func validateCollaboration(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(SlideCommands.ppCollaborate(_:)):
            // Only a presentation's owner shares it, and changes who it's shared with.
            menuItem.isHidden = !state.showsCollaborateButton
            menuItem.title = state.collaboration.isShared ? "Collaborators…" : "Collaborate…"
            return state.showsCollaborateButton && (state.access != .locked || state.collaboration.isShared)
        case #selector(SlideCommands.ppLeaveShared(_:)):
            menuItem.isHidden = state.showsCollaborateButton
            return presentationDocument?.collaboration?.isOwner == false
        case #selector(NSDocument.rename(_:)):
            return presentationDocument?.sharedCopy == nil
        case #selector(SlideCommands.ppInsertComment(_:)):
            if !state.canComment { return false }
        default:
            break
        }
        if state.access != .full, let action = menuItem.action, !Self.commentingActions.contains(action) { return false }
        return nil
    }
}
