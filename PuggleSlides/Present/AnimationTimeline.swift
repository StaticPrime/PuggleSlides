import AppKit
import PuggleSlidesKit

/// A slide's animations laid out in time, as they play: whatever comes before the first "On click"
/// plays by itself when the slide appears, and each "On click" starts a group that waits for a click. Within a
/// group, "With previous" starts with the animation before it and "After previous" when it ends.
struct AnimationTimeline {
    struct Item {
        var effect: AnimationEffect
        var elementID: UUID
        /// For animations by paragraph: the paragraph this item moves.
        var paragraph: Int?
        /// Seconds from the group's start.
        var start: Double
        var duration: Double

        var end: Double { start + duration }
    }

    typealias State = SlideRenderer.ElementRenderState

    /// Group 0 plays when the slide appears (it may be empty); each later group waits for a click.
    private(set) var groups: [[Item]] = [[]]
    private var initial: [UUID: State] = [:]
    private var boxes: [UUID: SlideRect] = [:]
    private let slideSize: SlideSize

    init(slide: Slide, presentation: Presentation) {
        slideSize = presentation.slideSize
        var paragraphs: [UUID: [Int]] = [:]
        for element in slide.elements {
            boxes[element.id] = presentation.placement(of: element, on: slide).boundingBox
            let body = element.shape?.text?.paragraphs ?? []
            paragraphs[element.id] = body.indices.filter { !body[$0].isEmpty }
        }
        var groups: [[Item]] = [[]]
        var previousStart = 0.0, previousEnd = 0.0
        func add(_ effect: AnimationEffect, _ elementID: UUID, paragraph: Int?, start: AnimationStart, duration: Double, delay: Double) {
            let length = effect.isInstant ? 0 : max(0.01, duration)
            let begin: Double
            switch start {
            case .onClick:
                groups.append([])
                begin = delay
            case .withPrevious:
                begin = previousStart + delay
            case .afterPrevious:
                begin = previousEnd + delay
            }
            groups[groups.count - 1].append(Item(effect: effect, elementID: elementID, paragraph: paragraph, start: begin, duration: length))
            previousStart = begin
            previousEnd = begin + length
        }
        var seenElements = Set<UUID>()
        var seenParagraphs: [UUID: Set<Int>] = [:]
        for animation in slide.animations where boxes[animation.elementID] != nil {
            let id = animation.elementID
            if animation.byParagraph, let indexes = paragraphs[id], !indexes.isEmpty {
                var state = initial[id] ?? State()
                var paragraphStates = state.paragraphs ?? Array(repeating: SlideRenderer.ParagraphRenderState(), count: (indexes.last ?? 0) + 1)
                for (offset, paragraph) in indexes.enumerated() {
                    // Before a paragraph's first animation, an entrance keeps it hidden.
                    if !(seenParagraphs[id]?.contains(paragraph) ?? false), !seenElements.contains(id), animation.effect.isEntrance {
                        paragraphStates[paragraph].isHidden = true
                    }
                    seenParagraphs[id, default: []].insert(paragraph)
                    let start: AnimationStart = offset == 0 ? animation.start : (animation.start == .onClick ? .onClick : .afterPrevious)
                    add(animation.effect, id, paragraph: paragraph, start: start, duration: animation.duration, delay: offset == 0 ? animation.delay : 0)
                }
                state.paragraphs = paragraphStates
                initial[id] = state
            } else {
                if !seenElements.contains(id), seenParagraphs[id] == nil, animation.effect.isEntrance { initial[id] = .hidden }
                add(animation.effect, id, paragraph: nil, start: animation.start, duration: animation.duration, delay: animation.delay)
            }
            seenElements.insert(id)
        }
        self.groups = groups
    }

    var isEmpty: Bool { groups.allSatisfy(\.isEmpty) }

    /// How long a group takes once started.
    func duration(ofGroup index: Int) -> Double {
        guard groups.indices.contains(index) else { return 0 }
        return groups[index].map(\.end).max() ?? 0
    }

    /// The slide before anything has played.
    var initialStates: [UUID: State] { initial }

    /// Every element's state with groups before `group` finished and `group` at `time` seconds (infinity: finished).
    func states(group: Int, time: Double) -> [UUID: State] {
        var states = initial
        for (index, items) in groups.enumerated() {
            if index > group { break }
            for item in items {
                let elapsed = index < group ? Double.infinity : time
                guard elapsed >= item.start else { continue }
                let progress = item.duration > 0 ? min(1, (elapsed - item.start) / item.duration) : 1
                apply(item, progress: progress, to: &states)
            }
        }
        return states
    }

    /// Where an element flies in from or out to: just past the slide's edge.
    private func offset(for effect: AnimationEffect, box: SlideRect) -> CGSize {
        switch effect {
        case .flyInFromLeft, .flyOutToLeft: CGSize(width: -(box.maxX + 20), height: 0)
        case .flyInFromRight, .flyOutToRight: CGSize(width: slideSize.width - box.minX + 20, height: 0)
        case .flyInFromBottom, .flyOutToBottom: CGSize(width: 0, height: slideSize.height - box.minY + 20)
        case .flyInFromTop, .flyOutToTop: CGSize(width: 0, height: -(box.maxY + 20))
        default: .zero
        }
    }

    private func apply(_ item: Item, progress p: Double, to states: inout [UUID: State]) {
        let eased = 1 - pow(1 - p, 3)
        let box = boxes[item.elementID] ?? .zero
        let distance = offset(for: item.effect, box: box)
        var state = states[item.elementID] ?? State()
        if let paragraph = item.paragraph {
            var paragraphs = state.paragraphs ?? []
            while paragraphs.count <= paragraph { paragraphs.append(SlideRenderer.ParagraphRenderState()) }
            var target = paragraphs[paragraph]
            switch item.effect {
            case .appear: target = SlideRenderer.ParagraphRenderState()
            case .fadeIn, .zoomIn: target = SlideRenderer.ParagraphRenderState(opacity: p)
            case .flyInFromLeft, .flyInFromRight, .flyInFromBottom, .flyInFromTop:
                target = SlideRenderer.ParagraphRenderState(offset: CGSize(width: distance.width * (1 - eased), height: distance.height * (1 - eased)))
            case .spin: break
            case .disappear: target.isHidden = true
            case .fadeOut, .zoomOut: target = SlideRenderer.ParagraphRenderState(opacity: 1 - p, isHidden: p >= 1)
            case .flyOutToLeft, .flyOutToRight, .flyOutToBottom, .flyOutToTop:
                target = SlideRenderer.ParagraphRenderState(offset: CGSize(width: distance.width * eased, height: distance.height * eased), isHidden: p >= 1)
            }
            paragraphs[paragraph] = target
            state.paragraphs = paragraphs
            state.isHidden = false
        } else {
            let paragraphs = state.paragraphs
            switch item.effect {
            case .appear: state = State()
            case .fadeIn: state = State(opacity: p)
            case .flyInFromLeft, .flyInFromRight, .flyInFromBottom, .flyInFromTop:
                state = State(offset: CGSize(width: distance.width * (1 - eased), height: distance.height * (1 - eased)))
            case .zoomIn: state = State(opacity: p, scale: max(0.01, eased))
            case .spin:
                state.rotation = p >= 1 ? 0 : 360 * eased
            case .disappear: state = .hidden
            case .fadeOut: state = State(opacity: 1 - p, isHidden: p >= 1)
            case .flyOutToLeft, .flyOutToRight, .flyOutToBottom, .flyOutToTop:
                state = State(offset: CGSize(width: distance.width * eased, height: distance.height * eased), isHidden: p >= 1)
            case .zoomOut: state = State(opacity: 1 - p, scale: max(0.01, 1 - eased), isHidden: p >= 1)
            }
            if !state.isHidden, state.paragraphs == nil { state.paragraphs = paragraphs }
        }
        states[item.elementID] = state
    }
}
