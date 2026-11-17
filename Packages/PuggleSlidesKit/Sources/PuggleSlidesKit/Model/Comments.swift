import Foundation

/// One comment in a thread: the first is the comment itself, the rest are replies.
public struct Comment: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var author: String
    public var date: Date
    public var text: String
    /// When the text was last changed, if it was.
    public var editedDate: Date?

    public init(id: UUID = UUID(), author: String, date: Date = Date(), text: String, editedDate: Date? = nil) {
        self.id = id
        self.author = author
        self.date = date
        self.text = text
        self.editedDate = editedDate
    }
}

/// Insert ▸ Comment: a discussion about a slide or one of its objects. Resolved threads stay with the slide and are
/// listed in the comments panel, but no longer show beside it.
public struct CommentThread: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// Never empty: the comment, then its replies, oldest first.
    public var comments: [Comment]
    public var isResolved: Bool
    /// The object the thread is about; nil for the slide as a whole. A thread whose object is deleted stays on the
    /// slide, about the slide.
    public var elementID: UUID?
    /// Where the thread's marker sits, in points from the slide's top-left corner. Files place comments by position;
    /// for an object it's the object's top-right corner when the comment was made.
    public var position: SlidePoint

    public init(id: UUID = UUID(), comments: [Comment], isResolved: Bool = false, elementID: UUID? = nil,
                position: SlidePoint = SlidePoint(x: 0, y: 0)) {
        self.id = id
        self.comments = comments
        self.isResolved = isResolved
        self.elementID = elementID
        self.position = position
    }

    /// The comment that started the thread.
    public var first: Comment? { comments.first }
}

extension Presentation {
    /// Every thread with the slide it's on, in slide order.
    public var commentThreads: [(slideID: UUID, thread: CommentThread)] {
        slides.flatMap { slide in slide.comments.map { (slide.id, $0) } }
    }

    /// The slide holding a thread, and the thread's index there.
    public func commentLocation(of threadID: UUID) -> (slide: Int, thread: Int)? {
        for (slideIndex, slide) in slides.enumerated() {
            if let threadIndex = slide.comments.firstIndex(where: { $0.id == threadID }) { return (slideIndex, threadIndex) }
        }
        return nil
    }
}
