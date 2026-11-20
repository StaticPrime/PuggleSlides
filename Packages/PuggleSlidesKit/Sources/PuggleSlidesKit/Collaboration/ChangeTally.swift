import Foundation

/// What someone has changed in a shared presentation since the people they share it with were last told, and the
/// short summary that tells them: slides added, taken out or edited, the theme changed, comments made, not every change.
public struct ChangeTally: Equatable, Sendable {
    public private(set) var slidesAdded: Set<UUID> = []
    public private(set) var slidesDeleted: Set<UUID> = []
    /// Slides that were there before whose content changed.
    public private(set) var slidesEdited: Set<UUID> = []
    public private(set) var slidesMoved = false
    public private(set) var imagesAdded = 0
    public private(set) var tablesAdded = 0
    public private(set) var chartsAdded = 0
    public private(set) var mediaAdded = 0
    public private(set) var designChanged = false
    public private(set) var commentsAdded = 0
    public private(set) var repliesAdded = 0
    public private(set) var commentsResolved = 0
    /// The words of the latest comment or reply.
    public private(set) var commentExcerpt: String?

    public init() {}

    public var isEmpty: Bool { self == ChangeTally() }

    // MARK: Counting

    /// A change made here, to the presentation as it was (`before`).
    public mutating func record(_ change: PresentationChange, before: Presentation) {
        let slidesBefore = Set(before.slides.map(\.id))
        let elementsBefore = Dictionary(before.slides.map { ($0.id, Set($0.elements.map(\.id))) }, uniquingKeysWith: { first, _ in first })
        var touched: Set<UUID> = []
        var removed: Set<UUID> = []
        for (key, value) in change.parts {
            switch key {
            case let .slideOrder(id):
                if value == nil {
                    removed.insert(id)
                    if slidesAdded.remove(id) == nil { slidesDeleted.insert(id) }
                    slidesEdited.remove(id)
                } else if !slidesBefore.contains(id) {
                    slidesAdded.insert(id)
                } else {
                    slidesMoved = true
                }
            case let .slide(id, _):
                touched.insert(id)
            case let .elementOrder(slide, element):
                touched.insert(slide)
                if value != nil, elementsBefore[slide]?.contains(element) != true,
                   case let .element(added)?? = change.parts[.element(slide: slide, element: element, part: .body)] {
                    switch added.content {
                    case .picture: imagesAdded += 1
                    case .table: tablesAdded += 1
                    case .chart: chartsAdded += 1
                    case .media: mediaAdded += 1
                    case .shape, .group: break
                    }
                }
            case let .element(slide, _, _):
                touched.insert(slide)
            case .theme, .themeOrder, .layout, .layoutOrder, .slideSize, .defaultTextStyle:
                designChanged = true
            case .title, .guides, .media:
                break
            }
        }
        for id in touched where slidesBefore.contains(id) && !removed.contains(id) && !slidesAdded.contains(id) && !slidesDeleted.contains(id) {
            slidesEdited.insert(id)
        }
    }

    public mutating func recordComment(_ text: String) {
        commentsAdded += 1
        commentExcerpt = Self.excerpt(text)
    }

    public mutating func recordReply(_ text: String) {
        repliesAdded += 1
        commentExcerpt = Self.excerpt(text)
    }

    public mutating func recordResolved() { commentsResolved += 1 }

    private static func excerpt(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return words.count > 70 ? String(words.prefix(70)) + "…" : words
    }

    // MARK: Words

    /// The notification: a title naming who changed which presentation, and a line saying roughly what they did. Nil
    /// when there's nothing to tell.
    public func notice(author: String, documentTitle: String) -> (title: String, body: String)? {
        guard !isEmpty else { return nil }
        let name = author.isEmpty ? "Someone" : author
        let title = documentTitle.count > 48 ? String(documentTitle.prefix(47)) + "…" : documentTitle
        let edited = !slidesAdded.isEmpty || !slidesDeleted.isEmpty || !slidesEdited.isEmpty || slidesMoved || designChanged
        let commented = commentsAdded + repliesAdded + commentsResolved > 0
        if !edited, !commented { return nil }
        if !edited {
            let heading = commentsAdded == 0 && repliesAdded > 0 ? "\(name) replied in “\(title)”"
                : (commentsAdded == 0 && repliesAdded == 0 ? "\(name) resolved comments in “\(title)”" : "\(name) commented on “\(title)”")
            if commentsAdded + repliesAdded == 1, commentsResolved == 0, let commentExcerpt {
                return (heading, "“\(commentExcerpt)”")
            }
            return (heading, Self.sentence(commentParts))
        }
        var parts: [String] = []
        if !slidesAdded.isEmpty { parts.append("added " + Self.count(slidesAdded.count, "slide")) }
        if !slidesDeleted.isEmpty { parts.append("deleted " + Self.count(slidesDeleted.count, "slide")) }
        if !slidesEdited.isEmpty { parts.append("edited " + Self.count(slidesEdited.count, "slide")) }
        if imagesAdded > 0 { parts.append("added " + Self.count(imagesAdded, "image")) }
        if tablesAdded > 0 { parts.append("added " + Self.count(tablesAdded, "table")) }
        if chartsAdded > 0 { parts.append("added " + Self.count(chartsAdded, "chart")) }
        if mediaAdded > 0 { parts.append("added " + Self.count(mediaAdded, "video or sound", plural: "videos or sounds")) }
        if slidesMoved, slidesAdded.isEmpty, slidesDeleted.isEmpty { parts.append("reordered the slides") }
        if designChanged { parts.append("changed the theme") }
        parts += commentParts
        return ("\(name) edited “\(title)”", Self.sentence(parts))
    }

    private var commentParts: [String] {
        var parts: [String] = []
        if commentsAdded > 0 { parts.append("added " + Self.count(commentsAdded, "comment")) }
        if repliesAdded > 0 { parts.append(repliesAdded == 1 ? "replied to a comment" : "added \(repliesAdded) replies") }
        if commentsResolved > 0 { parts.append("resolved " + Self.count(commentsResolved, "comment")) }
        return parts
    }

    /// "a slide", "3 slides", "an image".
    private static func count(_ value: Int, _ noun: String, plural: String? = nil) -> String {
        if value == 1 { return (noun.first.map { "aeiou".contains($0) } ?? false ? "an " : "a ") + noun }
        return "\(value) \(plural ?? noun + "s")"
    }

    /// "Added 2 slides, edited 3 slides and added a comment."
    private static func sentence(_ parts: [String]) -> String {
        guard var first = parts.first else { return "" }
        first = first.prefix(1).uppercased() + first.dropFirst()
        let all = [first] + parts.dropFirst()
        let joined = all.count <= 1 ? all.joined() : all.dropLast().joined(separator: ", ") + " and " + all.last!
        return joined + "."
    }
}
