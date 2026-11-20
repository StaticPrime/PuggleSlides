import Foundation

// A shared presentation is kept, on every Mac and in its log, as a set of parts: small pieces that each change as a
// whole. The slide size, the default text styles and the guides are one part each; a theme is one (without its
// layouts), and each layout one more. A slide is six: its layout, background, notes, whether it's skipped, its
// transition and its animations. An object on a slide is three: its place (position, size, rotation), its text, and
// the rest of it (fill, border, picture, table and so on). Every list (slides, a slide's objects, themes, a theme's
// layouts) also gives each item an order part, a key that sorts (see `OrderKeys`). Media are parts too, added and
// never taken out, since something may still refer to them.
//
// A change sets parts, or removes them. Changes go into the log one after another, and when two people change the
// same part at the same time, the one later in the log wins; changes to different parts all stand. So two people
// editing different objects, or one moving an object while the other types in it, or both adding slides, both keep
// what they did, on every Mac; only changes to the very same part replace one another. A Mac's presentation is always
// what its parts say (see `PresentationState.presentation()`), so every Mac with the same parts shows the same thing.
//
// Comments aren't parts: they go through the shared presentation's talk zone, which people who may only comment can
// write to as well (see `SharedComment`).

/// One part of a shared presentation.
public enum PartKey: Hashable, Sendable, Codable {
    case slideSize
    case defaultTextStyle
    case title
    case guides
    case themeOrder(UUID)
    /// A theme without its layouts.
    case theme(UUID)
    case layoutOrder(theme: UUID, layout: UUID)
    case layout(theme: UUID, layout: UUID)
    case slideOrder(UUID)
    case slide(UUID, SlidePart)
    case elementOrder(slide: UUID, element: UUID)
    case element(slide: UUID, element: UUID, part: ElementPart)
    case media(String)

    /// The slide it's part of, if any.
    public var slideID: UUID? {
        switch self {
        case let .slideOrder(id), let .slide(id, _): id
        case let .elementOrder(slide, _), let .element(slide, _, _): slide
        default: nil
        }
    }

    /// The theme it's part of, if any.
    public var themeID: UUID? {
        switch self {
        case let .themeOrder(id), let .theme(id): id
        case let .layoutOrder(theme, _), let .layout(theme, _): theme
        default: nil
        }
    }
}

/// The parts of a slide, apart from its objects.
public enum SlidePart: String, Hashable, Sendable, Codable, CaseIterable {
    case layout, background, notes, skipped, transition, animations
}

/// The parts of an object on a slide.
public enum ElementPart: String, Hashable, Sendable, Codable, CaseIterable {
    /// Everything but its place and its text.
    case body
    /// Its position, size, rotation and flips.
    case placement
    /// A shape's text.
    case text
}

/// What a part holds. A part that would hold nothing (no background of its own, no transition) isn't there at all.
public enum PartValue: Hashable, Sendable, Codable {
    case slideSize(SlideSize)
    case textStyle(ListStyle)
    case string(String)
    case guides([Guide])
    case theme(Theme)
    case layout(Layout)
    case order(String)
    case id(UUID)
    case fill(Fill)
    case text(TextBody)
    case flag(Bool)
    case transition(SlideTransition)
    case animations([SlideAnimation])
    case placement(Placement)
    case element(SlideElement)
    case media(MediaItem)

    var orderKey: String? {
        if case let .order(key) = self { return key }
        return nil
    }
}

/// A change to a shared presentation: the parts it sets, and those it removes (with no value).
public struct PresentationChange: SharedChange {
    public var parts: [PartKey: PartValue?]

    public init(parts: [PartKey: PartValue?] = [:]) {
        self.parts = parts
    }

    public var isEmpty: Bool { parts.isEmpty }

    public func compose(_ later: PresentationChange) -> PresentationChange {
        PresentationChange(parts: parts.merging(later.parts) { $1 })
    }

    /// Where both set a part, the change later in the log wins: `other` keeps it with `priority` (this change came
    /// first), and leaves it to this change without.
    public func transform(_ other: PresentationChange, priority: Bool) -> PresentationChange {
        priority ? other : PresentationChange(parts: other.parts.filter { parts[$0.key] == nil })
    }

    private struct Entry: Codable {
        var key: PartKey
        var value: PartValue?
    }

    public var encoded: Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return (try? encoder.encode(parts.map { Entry(key: $0.key, value: $0.value) })) ?? Data()
    }

    public init(encoded data: Data) throws {
        let entries = try PropertyListDecoder().decode([Entry].self, from: data)
        parts = Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}

/// A shared presentation as its parts.
public struct PresentationState: Equatable, Sendable {
    public private(set) var parts: [PartKey: PartValue] = [:]

    public init() {}

    /// A presentation starting out shared: its parts, every list in the order it's in now.
    public init(_ presentation: Presentation) {
        var change = PresentationState().change(from: Presentation(themes: []), to: presentation)
        // A fresh start: every part of the presentation, whatever it holds.
        change.parts[.slideSize] = .slideSize(presentation.slideSize)
        change.parts[.defaultTextStyle] = .textStyle(presentation.defaultTextStyle)
        change.parts[.guides] = .guides(presentation.guides)
        apply(change)
    }

    public subscript(key: PartKey) -> PartValue? { parts[key] }

    /// Sets and removes the change's parts. Media stay, whatever the change says.
    public mutating func apply(_ change: PresentationChange) {
        for (key, value) in change.parts {
            if let value {
                parts[key] = value
            } else if case .media = key {
                continue
            } else {
                parts[key] = nil
            }
        }
    }

    // MARK: The presentation the parts make

    /// The presentation the parts describe, without comments: lists in their keys' order, and only items whose parts
    /// say what they are (an object needs its body, a slide its layout, a theme itself).
    public func presentation() -> Presentation {
        var themeOrder: [(id: UUID, key: String)] = []
        var themes: [UUID: Theme] = [:]
        var layoutOrder: [UUID: [(id: UUID, key: String)]] = [:]
        var layouts: [UUID: [UUID: Layout]] = [:]
        var slideOrder: [(id: UUID, key: String)] = []
        var slideParts: [UUID: [SlidePart: PartValue]] = [:]
        var elementOrder: [UUID: [(id: UUID, key: String)]] = [:]
        var elementParts: [UUID: [UUID: [ElementPart: PartValue]]] = [:]
        var media: [MediaID: MediaItem] = [:]
        for (key, value) in parts {
            switch key {
            case .slideSize, .defaultTextStyle, .title, .guides:
                break
            case let .themeOrder(id):
                if let order = value.orderKey { themeOrder.append((id, order)) }
            case let .theme(id):
                if case let .theme(theme) = value { themes[id] = theme }
            case let .layoutOrder(theme, layout):
                if let order = value.orderKey { layoutOrder[theme, default: []].append((layout, order)) }
            case let .layout(theme, id):
                if case let .layout(layout) = value { layouts[theme, default: [:]][id] = layout }
            case let .slideOrder(id):
                if let order = value.orderKey { slideOrder.append((id, order)) }
            case let .slide(id, part):
                slideParts[id, default: [:]][part] = value
            case let .elementOrder(slide, element):
                if let order = value.orderKey { elementOrder[slide, default: []].append((element, order)) }
            case let .element(slide, element, part):
                elementParts[slide, default: [:]][element, default: [:]][part] = value
            case let .media(id):
                if case let .media(item) = value { media[id] = item }
            }
        }
        let tie: (UUID) -> String = { $0.uuidString }
        var result = Presentation(themes: [])
        if case let .slideSize(size)? = parts[.slideSize] { result.slideSize = size }
        if case let .textStyle(style)? = parts[.defaultTextStyle] { result.defaultTextStyle = style }
        if case let .string(title)? = parts[.title] { result.title = title }
        if case let .guides(guides)? = parts[.guides] { result.guides = guides }
        result.media = media
        result.themes = OrderKeys.sorted(themeOrder, tieBreak: tie).compactMap { id in
            guard var theme = themes[id] else { return nil }
            let own = layouts[id] ?? [:]
            theme.layouts = OrderKeys.sorted(layoutOrder[id] ?? [], tieBreak: tie).compactMap { own[$0] }
            return theme
        }
        result.slides = OrderKeys.sorted(slideOrder, tieBreak: tie).compactMap { id in
            guard let values = slideParts[id], case let .id(layoutID)? = values[.layout] else { return nil }
            var slide = Slide(id: id, layoutID: layoutID)
            if case let .fill(fill)? = values[.background] { slide.background = fill }
            if case let .text(notes)? = values[.notes] { slide.notes = notes }
            if case let .flag(skipped)? = values[.skipped] { slide.isSkipped = skipped }
            if case let .transition(transition)? = values[.transition] { slide.transition = transition }
            if case let .animations(animations)? = values[.animations] { slide.animations = animations }
            let own = elementParts[id] ?? [:]
            slide.elements = OrderKeys.sorted(elementOrder[id] ?? [], tieBreak: tie).compactMap { elementID in
                guard let values = own[elementID] else { return nil }
                return Self.element(elementID, values)
            }
            return slide
        }
        return result
    }

    private static func element(_ id: UUID, _ values: [ElementPart: PartValue]) -> SlideElement? {
        guard case var .element(element)? = values[.body] else { return nil }
        element.id = id
        if case let .placement(placement)? = values[.placement] { element.placement = placement }
        if case var .shape(shape) = element.content {
            if case let .text(text)? = values[.text] { shape.text = text }
            element.content = .shape(shape)
        }
        return element
    }

    /// An object split into its parts: the body (without its place and text), its place and its text.
    static func split(_ element: SlideElement) -> (body: SlideElement, placement: Placement?, text: TextBody?) {
        var body = element
        body.placement = nil
        var text: TextBody?
        if case var .shape(shape) = body.content {
            text = shape.text
            shape.text = nil
            body.content = .shape(shape)
        }
        return (body, element.placement, text)
    }

    // MARK: From an edit to a change

    /// Where every list's items are, and which parts belong to each slide and theme.
    private struct Index {
        var themes: [UUID: String] = [:]
        var layouts: [UUID: [UUID: String]] = [:]
        var slides: [UUID: String] = [:]
        var elements: [UUID: [UUID: String]] = [:]
        var bySlide: [UUID: [PartKey]] = [:]
        var byTheme: [UUID: [PartKey]] = [:]
    }

    private var index: Index {
        var index = Index()
        for (key, value) in parts {
            if let slide = key.slideID { index.bySlide[slide, default: []].append(key) }
            if let theme = key.themeID { index.byTheme[theme, default: []].append(key) }
            guard let order = value.orderKey else { continue }
            switch key {
            case let .themeOrder(id): index.themes[id] = order
            case let .layoutOrder(theme, layout): index.layouts[theme, default: [:]][layout] = order
            case let .slideOrder(id): index.slides[id] = order
            case let .elementOrder(slide, element): index.elements[slide, default: [:]][element] = order
            default: break
            }
        }
        return index
    }

    /// The change that turns the presentation these parts show (`shown`) into `edited`: every part that's different,
    /// set or removed, and new order keys for whatever was added or moved. Comments and media taken out don't count.
    public func change(from shown: Presentation, to edited: Presentation) -> PresentationChange {
        var change = PresentationChange()
        let index = self.index
        func set(_ key: PartKey, _ value: PartValue?) {
            if parts[key] != value { change.parts[key] = value }
        }
        let tie: (UUID) -> String = { $0.uuidString }

        if shown.slideSize != edited.slideSize { set(.slideSize, .slideSize(edited.slideSize)) }
        if shown.defaultTextStyle != edited.defaultTextStyle { set(.defaultTextStyle, .textStyle(edited.defaultTextStyle)) }
        if shown.title != edited.title { set(.title, edited.title.map { .string($0) }) }
        if shown.guides != edited.guides { set(.guides, .guides(edited.guides)) }
        for (id, item) in edited.media where parts[.media(id)] == nil { change.parts[.media(id)] = .media(item) }

        // Themes and their layouts.
        let shownThemes = Dictionary(shown.themes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editedThemes = Dictionary(edited.themes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for theme in edited.themes where shownThemes[theme.id] != theme {
            var head = theme
            head.layouts = []
            set(.theme(theme.id), .theme(head))
            let old = Dictionary((shownThemes[theme.id]?.layouts ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for layout in theme.layouts where old[layout.id] != layout { set(.layout(theme: theme.id, layout: layout.id), .layout(layout)) }
            let kept = Set(theme.layouts.map(\.id))
            for gone in old.keys where !kept.contains(gone) {
                set(.layout(theme: theme.id, layout: gone), nil)
                set(.layoutOrder(theme: theme.id, layout: gone), nil)
            }
            if theme.layouts.map(\.id) != shownThemes[theme.id]?.layouts.map(\.id) {
                let keys = index.layouts[theme.id] ?? [:]
                for (id, key) in OrderKeys.assign(theme.layouts.map(\.id), keys: keys.filter { kept.contains($0.key) }, tieBreak: tie) {
                    set(.layoutOrder(theme: theme.id, layout: id), .order(key))
                }
            }
        }
        for theme in shown.themes where editedThemes[theme.id] == nil {
            for key in index.byTheme[theme.id] ?? [] { set(key, nil) }
        }
        if edited.themes.map(\.id) != shown.themes.map(\.id) {
            let kept = Set(edited.themes.map(\.id))
            for (id, key) in OrderKeys.assign(edited.themes.map(\.id), keys: index.themes.filter { kept.contains($0.key) }, tieBreak: tie) {
                set(.themeOrder(id), .order(key))
            }
        }

        // Slides and their objects.
        let shownSlides = Dictionary(shown.slides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editedSlides = Dictionary(edited.slides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for slide in edited.slides {
            let old = shownSlides[slide.id]
            if let old, Self.sameIgnoringComments(old, slide) { continue }
            set(.slide(slide.id, .layout), .id(slide.layoutID))
            set(.slide(slide.id, .background), slide.background.map { .fill($0) })
            set(.slide(slide.id, .notes), slide.notes == .empty ? nil : .text(slide.notes))
            set(.slide(slide.id, .skipped), slide.isSkipped ? .flag(true) : nil)
            set(.slide(slide.id, .transition), slide.transition.map { .transition($0) })
            set(.slide(slide.id, .animations), slide.animations.isEmpty ? nil : .animations(slide.animations))
            let oldElements = Dictionary((old?.elements ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for element in slide.elements where oldElements[element.id] != element {
                let parts = Self.split(element)
                set(.element(slide: slide.id, element: element.id, part: .body), .element(parts.body))
                set(.element(slide: slide.id, element: element.id, part: .placement), parts.placement.map { .placement($0) })
                set(.element(slide: slide.id, element: element.id, part: .text), parts.text.map { .text($0) })
            }
            let kept = Set(slide.elements.map(\.id))
            for gone in oldElements.keys where !kept.contains(gone) {
                set(.elementOrder(slide: slide.id, element: gone), nil)
                for part in ElementPart.allCases { set(.element(slide: slide.id, element: gone, part: part), nil) }
            }
            if slide.elements.map(\.id) != old?.elements.map(\.id) {
                let keys = (index.elements[slide.id] ?? [:]).filter { kept.contains($0.key) }
                for (id, key) in OrderKeys.assign(slide.elements.map(\.id), keys: keys, tieBreak: tie) {
                    set(.elementOrder(slide: slide.id, element: id), .order(key))
                }
            }
        }
        for slide in shown.slides where editedSlides[slide.id] == nil {
            for key in index.bySlide[slide.id] ?? [] { set(key, nil) }
        }
        if edited.slides.map(\.id) != shown.slides.map(\.id) {
            let kept = Set(edited.slides.map(\.id))
            for (id, key) in OrderKeys.assign(edited.slides.map(\.id), keys: index.slides.filter { kept.contains($0.key) }, tieBreak: tie) {
                set(.slideOrder(id), .order(key))
            }
        }
        return change
    }

    static func sameIgnoringComments(_ a: Slide, _ b: Slide) -> Bool {
        guard a.comments != b.comments else { return a == b }
        var a = a
        a.comments = b.comments
        return a == b
    }
}

/// A shared presentation as a whole at one revision of its log, for a Mac joining it to start from.
public struct SyncSnapshot: Sendable {
    public var revision: Int
    public var state: PresentationState

    public init(revision: Int, state: PresentationState) {
        self.revision = revision
        self.state = state
    }

    private struct Coded: Codable {
        var revision: Int
        var parts: Data
    }

    public var encoded: Data {
        let all = PresentationChange(parts: state.parts.mapValues { Optional($0) })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return (try? encoder.encode(Coded(revision: revision, parts: all.encoded))) ?? Data()
    }

    public init(encoded data: Data) throws {
        let coded = try PropertyListDecoder().decode(Coded.self, from: data)
        revision = coded.revision
        var state = PresentationState()
        state.apply(try PresentationChange(encoded: coded.parts))
        self.state = state
    }
}
