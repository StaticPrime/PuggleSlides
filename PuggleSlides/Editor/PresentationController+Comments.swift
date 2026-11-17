import AppKit
import PuggleSlidesKit

/// Insert ▸ Comment and the comment cards: each change is one undoable step.
extension PresentationController {
    /// The name comments are signed with: the Mac account's full name.
    var commentAuthor: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Me" : name
    }

    /// The open threads on a slide, oldest first.
    func openThreads(onSlide slideID: UUID?) -> [CommentThread] {
        guard let id = slideID, let index = presentation.slideIndex(id: id) else { return [] }
        return presentation.slides[index].comments.filter { !$0.isResolved }
    }

    var hasOpenComments: Bool { presentation.slides.contains { $0.comments.contains { !$0.isResolved } } }

    /// The open thread about an object, if any.
    func openThread(about elementID: UUID) -> CommentThread? {
        currentSlide?.comments.first { !$0.isResolved && $0.elementID == elementID }
    }

    /// A new thread about an object (or the slide when it's nil). Its marker goes at the object's top-right corner,
    /// or the slide's top-left, as PowerPoint places new comments.
    @discardableResult
    func addComment(_ text: String, about elementID: UUID?, onSlide slideID: UUID) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presentation.slideIndex(id: slideID) else { return nil }
        let slide = presentation.slides[index]
        let element = elementID.flatMap(slide.element(id:))
        var position = SlidePoint(x: 8, y: 8)
        if let element {
            let frame = presentation.placement(of: element, on: slide).frame
            position = SlidePoint(x: frame.x + frame.width, y: frame.y)
        }
        let thread = CommentThread(comments: [Comment(author: commentAuthor, text: trimmed)], elementID: element?.id, position: position)
        perform("Add Comment", update: .comments, showing: slideID) { $0.slides[index].comments.append(thread) }
        return thread.id
    }

    func replyToComment(_ threadID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editThread(threadID, actionName: "Reply") { $0.comments.append(Comment(author: commentAuthor, text: trimmed)) }
    }

    func editComment(_ commentID: UUID, inThread threadID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editThread(threadID, actionName: "Edit Comment") { thread in
            guard let index = thread.comments.firstIndex(where: { $0.id == commentID }), thread.comments[index].text != trimmed else { return }
            thread.comments[index].text = trimmed
            thread.comments[index].editedDate = Date()
        }
    }

    /// Deleting the first comment deletes the whole thread.
    func deleteComment(_ commentID: UUID, inThread threadID: UUID) {
        guard let location = presentation.commentLocation(of: threadID) else { return }
        let thread = presentation.slides[location.slide].comments[location.thread]
        if thread.comments.first?.id == commentID {
            perform("Delete Comment", update: .comments) { $0.slides[location.slide].comments.remove(at: location.thread) }
        } else {
            editThread(threadID, actionName: "Delete Reply") { $0.comments.removeAll { $0.id == commentID } }
        }
    }

    func setThread(_ threadID: UUID, resolved: Bool) {
        editThread(threadID, actionName: resolved ? "Resolve" : "Re-open") { $0.isResolved = resolved }
    }

    private func editThread(_ threadID: UUID, actionName: String, _ edit: (inout CommentThread) -> Void) {
        guard let location = presentation.commentLocation(of: threadID) else { return }
        perform(actionName, update: .comments) { edit(&$0.slides[location.slide].comments[location.thread]) }
    }
}
