import Foundation

/// Slide transitions.
public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case none, dissolve, fade, slideFromRight, slideFromLeft, flip, cube, gallery

    /// The names in the Motion panel.
    public var title: String {
        switch self {
        case .none: "None"
        case .dissolve: "Dissolve"
        case .fade: "Fade"
        case .slideFromRight: "Slide from right"
        case .slideFromLeft: "Slide from left"
        case .flip: "Flip"
        case .cube: "Cube"
        case .gallery: "Gallery"
        }
    }
}

/// How a slide arrives during a slideshow.
public struct SlideTransition: Hashable, Codable, Sendable {
    public var kind: TransitionKind
    /// Seconds.
    public var duration: Double

    public init(kind: TransitionKind, duration: Double = SlideTransition.defaultDuration) {
        self.kind = kind
        self.duration = max(0, duration)
    }

    /// The "Medium" speed.
    public static let defaultDuration: Double = 0.5
}

/// Object animations: entrances, then exits.
public enum AnimationEffect: String, Codable, CaseIterable, Sendable {
    case appear, fadeIn, flyInFromLeft, flyInFromRight, flyInFromBottom, flyInFromTop, zoomIn, spin
    case disappear, fadeOut, flyOutToLeft, flyOutToRight, flyOutToBottom, flyOutToTop, zoomOut

    /// The names in the Motion panel.
    public var title: String {
        switch self {
        case .appear: "Appear"
        case .fadeIn: "Fade in"
        case .flyInFromLeft: "Fly in from left"
        case .flyInFromRight: "Fly in from right"
        case .flyInFromBottom: "Fly in from bottom"
        case .flyInFromTop: "Fly in from top"
        case .zoomIn: "Zoom in"
        case .spin: "Spin"
        case .disappear: "Disappear"
        case .fadeOut: "Fade out"
        case .flyOutToLeft: "Fly out to left"
        case .flyOutToRight: "Fly out to right"
        case .flyOutToBottom: "Fly out to bottom"
        case .flyOutToTop: "Fly out to top"
        case .zoomOut: "Zoom out"
        }
    }

    /// The element is hidden before an entrance runs, and after an exit has run.
    public var isEntrance: Bool {
        switch self {
        case .appear, .fadeIn, .flyInFromLeft, .flyInFromRight, .flyInFromBottom, .flyInFromTop, .zoomIn: true
        case .spin, .disappear, .fadeOut, .flyOutToLeft, .flyOutToRight, .flyOutToBottom, .flyOutToTop, .zoomOut: false
        }
    }

    public var isExit: Bool {
        switch self {
        case .disappear, .fadeOut, .flyOutToLeft, .flyOutToRight, .flyOutToBottom, .flyOutToTop, .zoomOut: true
        default: false
        }
    }

    /// Effects that happen at once, with no duration to set.
    public var isInstant: Bool { self == .appear || self == .disappear }
}

/// When an animation starts.
public enum AnimationStart: String, Codable, CaseIterable, Sendable {
    case onClick, afterPrevious, withPrevious

    public var title: String {
        switch self {
        case .onClick: "On click"
        case .afterPrevious: "After previous"
        case .withPrevious: "With previous"
        }
    }
}

/// One object animation on a slide.
public struct SlideAnimation: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// The element animated, one of the slide's own elements.
    public var elementID: UUID
    public var effect: AnimationEffect
    public var start: AnimationStart
    /// Seconds.
    public var duration: Double
    /// Seconds to wait after the trigger.
    public var delay: Double
    /// Text animates a paragraph at a time.
    public var byParagraph: Bool

    public init(id: UUID = UUID(), elementID: UUID, effect: AnimationEffect = .appear, start: AnimationStart = .onClick,
                duration: Double = 0.5, delay: Double = 0, byParagraph: Bool = false) {
        self.id = id
        self.elementID = elementID
        self.effect = effect
        self.start = start
        self.duration = max(0, duration)
        self.delay = max(0, delay)
        self.byParagraph = byParagraph
    }
}

extension Slide {
    /// Drops animations whose element is gone.
    public mutating func pruneAnimations() {
        let ids = Set(elements.map(\.id))
        if animations.contains(where: { !ids.contains($0.elementID) }) {
            animations.removeAll { !ids.contains($0.elementID) }
        }
    }

    /// The slide's text in reading order: titles first, then everything else as it's layered.
    public var plainText: String {
        let texts = elements.sorted { a, b in
            let aTitle = a.placeholder?.type.isTitle == true, bTitle = b.placeholder?.type.isTitle == true
            return aTitle && !bTitle
        }.flatMap { element -> [String] in
            func texts(_ element: SlideElement) -> [String] {
                if let children = element.children { return children.flatMap(texts) }
                guard element.placeholder?.type != .slideNumber, let text = element.shape?.text, !text.isEmpty else { return [] }
                return [text.plainText.replacingOccurrences(of: TextRun.lineBreak, with: "\n")]
            }
            return texts(element)
        }
        return texts.joined(separator: "\n")
    }
}

extension Presentation {
    /// File ▸ Download ▸ Plain text: each slide's text, slides separated by a blank line.
    public var plainText: String {
        slides.map(\.plainText).joined(separator: "\n\n") + "\n"
    }
}
