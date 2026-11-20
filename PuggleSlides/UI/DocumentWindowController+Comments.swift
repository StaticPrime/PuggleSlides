import AppKit
import PuggleSlidesKit

/// Insert ▸ Comment, the comment cards beside the slide, and the comments panel.
extension DocumentWindowController: CommentActions {
    func ppInsertComment(_ sender: Any?) {
        guard let slideID = controller.currentSlideID, controller.builder == nil else { return }
        guard state.canComment else {
            NSSound.beep()
            presentationDocument?.collaboration?.explainOffline()
            return
        }
        finishEditing()
        if isGridView { ppToggleGridView(nil) }
        if !state.showsComments { setShowsComments(true) }
        state.selectedCommentID = nil
        state.commentDraft = CommentDraft(slideID: slideID, elementID: controller.selectedElementIDs.first)
        updateCommentsColumn()
        state.revision += 1
    }

    func ppShowCommentHistory(_ sender: Any?) {
        finishEditing()
        showSidebar(.comments)
    }

    func ppToggleComments(_ sender: Any?) { setShowsComments(!state.showsComments) }

    /// The header's "Show all comments" button.
    func toggleCommentsPanel() {
        if state.sidebar == .comments { closeSidebar() } else { ppShowCommentHistory(nil) }
    }

    func setShowsComments(_ shows: Bool) {
        state.showsComments = shows
        UserDefaults.standard.set(shows, forKey: "PPShowComments")
        if !shows { state.commentDraft = nil }
        updateCommentsColumn()
    }

    // MARK: CommentActions

    func postComment(_ text: String) {
        guard let draft = state.commentDraft else { return }
        state.commentDraft = nil
        if let id = controller.addComment(text, about: draft.elementID, onSlide: draft.slideID) { state.selectedCommentID = id }
        focusCanvas()
    }

    func cancelComment() {
        state.commentDraft = nil
        updateCommentsColumn()
        focusCanvas()
    }

    func selectThread(_ id: UUID) {
        state.commentDraft = nil
        state.selectedCommentID = id
        if let slide = controller.currentSlide, let elementID = slide.comments.first(where: { $0.id == id })?.elementID,
           slide.element(id: elementID) != nil {
            controller.selectElements([elementID])
        }
        state.revision += 1
    }

    func openComment(_ threadID: UUID) {
        guard let location = controller.presentation.commentLocation(of: threadID) else { return }
        finishEditing()
        if isGridView { ppToggleGridView(nil) }
        let slide = controller.presentation.slides[location.slide]
        let thread = slide.comments[location.thread]
        controller.selectSlide(slide.id)
        state.selectedCommentID = thread.isResolved ? nil : threadID
        if let elementID = thread.elementID, slide.element(id: elementID) != nil { controller.selectElements([elementID]) }
        if !thread.isResolved, !state.showsComments { setShowsComments(true) }
    }

    // MARK: Keeping the column in step

    /// The composer belongs to its slide; selecting an object with a thread selects its card, and selecting another
    /// object lets go of it.
    func syncComments() {
        if let draft = state.commentDraft, draft.slideID != controller.currentSlideID || controller.builder != nil { state.commentDraft = nil }
        let threads = controller.openThreads(onSlide: controller.currentSlideID)
        var selected = state.selectedCommentID.flatMap { id in threads.first { $0.id == id } }
        let elements = controller.selectedElementIDs
        if elements.count == 1, selected?.elementID != elements[0], let thread = threads.first(where: { $0.elementID == elements[0] }) {
            selected = thread
        }
        if let thread = selected, let elementID = thread.elementID, controller.currentSlide?.element(id: elementID) != nil,
           !elements.contains(elementID) {
            selected = nil
        }
        // While a new comment is written, it's the only card taking input.
        if state.commentDraft != nil { selected = nil }
        if state.selectedCommentID != selected?.id { state.selectedCommentID = selected?.id }
        updateCommentsColumn()
    }

    /// The column shows while the presentation has open comments (or one is being written), so the slide keeps its
    /// size from slide to slide. With the comments panel open, which lists them all, it only shows on slides that have
    /// some.
    func updateCommentsColumn() {
        let slideHasComments = !controller.openThreads(onSlide: controller.currentSlideID).isEmpty
        let shows = state.showsComments && !isGridView && controller.builder == nil
            && (state.commentDraft != nil || (controller.hasOpenComments && (state.sidebar != .comments || slideHasComments)))
        let width: CGFloat = shows ? 300 : 0
        guard commentsWidth.constant != width else { return }
        commentsWidth.constant = width
        DispatchQueue.main.async { [weak self] in self?.canvasScroll.refit() }
    }

    func validateComments(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(SlideCommands.ppInsertComment(_:)):
            return controller.currentSlide != nil && controller.builder == nil
        case #selector(SlideCommands.ppToggleComments(_:)):
            item.state = state.showsComments ? .on : .off
            return controller.builder == nil
        case #selector(SlideCommands.ppShowCommentHistory(_:)):
            return true
        default:
            return nil
        }
    }
}
