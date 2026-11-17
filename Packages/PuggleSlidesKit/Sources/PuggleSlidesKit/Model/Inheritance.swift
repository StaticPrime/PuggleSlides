import Foundation

/// Which of a theme's text styles text starts from.
public enum TextCategory: Sendable {
    case title, body, other

    init(_ placeholder: PlaceholderType?) {
        switch placeholder {
        case .title?, .centeredTitle?: self = .title
        case .body?, .subtitle?, .object?, .picture?, .chart?, .table?, .clipArt?, .diagram?, .media?: self = .body
        default: self = .other
        }
    }
}

public struct ResolvedCharacterStyle: Hashable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var color: ResolvedColor
    public var highlight: ResolvedColor?
    public var baseline: BaselineShift
    public var link: Hyperlink?
}

public struct ResolvedRun: Hashable, Sendable {
    public var text: String
    public var style: ResolvedCharacterStyle
    public var field: TextFieldKind?
}

public struct ResolvedBullet: Hashable, Sendable {
    public var text: String
    public var fontFamily: String
    public var fontSize: Double
    public var color: ResolvedColor
}

public struct ResolvedParagraph: Hashable, Sendable {
    public var runs: [ResolvedRun]
    public var level: Int
    public var alignment: TextAlignment
    public var lineSpacing: Double
    public var spaceBefore: Double
    public var spaceAfter: Double
    public var marginLeft: Double
    public var indent: Double
    /// Set for list paragraphs. Empty paragraphs keep theirs so an editor can show it at the insertion point.
    public var bullet: ResolvedBullet?
    public var endStyle: ResolvedCharacterStyle

    public var text: String { runs.map(\.text).joined() }
    public var isEmpty: Bool { runs.allSatisfy { $0.text.isEmpty } }
}

public struct ResolvedBodyProperties: Hashable, Sendable {
    public var anchor: VerticalAnchor
    public var insets: TextInsets
    public var autofit: Autofit
    public var fontScale: Double
    public var lineSpacingReduction: Double
    public var wraps: Bool
}

extension Theme {
    /// The theme placeholder that layout and slide placeholders of a type inherit from.
    public func placeholder(matching ref: PlaceholderRef) -> SlideElement? {
        func family(_ type: PlaceholderType) -> PlaceholderType {
            switch type {
            case .centeredTitle: .title
            case .subtitle, .object, .chart, .table, .clipArt, .diagram, .media, .picture: .body
            default: type
            }
        }
        let wanted = family(ref.type)
        return elements.first { $0.placeholder.map { family($0.type) } == wanted }
    }
}

extension Layout {
    /// The layout placeholder a slide placeholder inherits from: the same index, then the same type, then a
    /// compatible type (a title for a centered title, a body for an object).
    public func placeholder(matching ref: PlaceholderRef) -> SlideElement? {
        let placeholders = elements.filter { $0.placeholder != nil }
        if ref.index != 0, let match = placeholders.first(where: { $0.placeholder?.index == ref.index }) { return match }
        if let match = placeholders.first(where: { $0.placeholder?.type == ref.type }) { return match }
        let compatible: [PlaceholderType] = switch ref.type {
        case .title: [.centeredTitle]
        case .centeredTitle: [.title]
        case .body, .object: [.body, .object, .subtitle]
        case .subtitle: [.body, .object]
        default: []
        }
        return placeholders.first { compatible.contains($0.placeholder!.type) }
    }
}

/// Everything an element inherits, gathered once: its own values first, then its layout's matching
/// placeholder, then the theme's, then the theme's text styles and the presentation's defaults.
public struct ElementStyle {
    public let element: SlideElement
    /// Nearest first.
    public let parents: [SlideElement]
    public let theme: Theme
    public let defaultTextStyle: ListStyle
    public let category: TextCategory

    public init(element: SlideElement, parents: [SlideElement], theme: Theme, defaultTextStyle: ListStyle) {
        self.element = element
        self.parents = parents
        self.theme = theme
        self.defaultTextStyle = defaultTextStyle
        category = TextCategory(element.placeholder?.type ?? parents.first?.placeholder?.type)
    }

    /// Text defaults when nothing in the chain sets a value: the body font at 18 points in the theme's first dark color.
    public static let builtInLevel = LevelStyle(
        paragraph: ParagraphStyle(alignment: .left, lineSpacing: 1, spaceBefore: 0, spaceAfter: 0, marginLeft: 0, indent: 0, bullet: Bullet.none),
        character: CharacterStyle(fontFamily: "+mn-lt", fontSize: 18, bold: false, italic: false, underline: false,
                                  strikethrough: false, color: ColorRef(theme: .dark1), baseline: .normal))

    private var inheritsFromParents: Bool { element.placeholder != nil }

    public var placement: Placement {
        if let placement = element.placement { return placement }
        for parent in parents { if let placement = parent.placement { return placement } }
        return Placement(frame: .zero)
    }

    public var geometry: ShapeGeometry {
        switch element.content {
        case .shape(let shape): shape.geometry
        case .picture(let picture): picture.geometry
        case .group, .table, .chart, .media: .rectangle
        }
    }

    public var fill: Fill {
        if let fill = element.shape?.fill { return fill }
        if inheritsFromParents { for parent in parents { if let fill = parent.shape?.fill { return fill } } }
        return .none
    }

    public var outline: Outline {
        if let outline = element.shape?.outline ?? element.picture?.outline { return outline }
        if inheritsFromParents { for parent in parents { if let outline = parent.shape?.outline { return outline } } }
        return .none
    }

    /// The text body properties set along the chain, before defaults.
    public var inheritedBodyProperties: TextBodyProperties {
        var properties = TextBodyProperties.empty
        if inheritsFromParents {
            for parent in parents.reversed() {
                if let parentProperties = parent.shape?.text?.properties { properties = parentProperties.merged(over: properties) }
            }
        }
        return properties
    }

    public var bodyProperties: ResolvedBodyProperties {
        let own = element.shape?.text?.properties ?? .empty
        let merged = own.merged(over: inheritedBodyProperties)
        return ResolvedBodyProperties(anchor: merged.anchor ?? .top, insets: merged.insets ?? .office, autofit: merged.autofit ?? .none,
                                      fontScale: merged.fontScale ?? 1, lineSpacingReduction: merged.lineSpacingReduction ?? 0,
                                      wraps: merged.wraps ?? true)
    }

    /// The theme's text style for this element's category.
    public var themeListStyle: ListStyle {
        switch category {
        case .title: theme.titleStyle
        case .body: theme.bodyStyle
        case .other: theme.otherStyle
        }
    }

    /// A level's formatting inherited from everything except the element's own list style and text.
    public func inheritedLevelStyle(_ level: Int) -> LevelStyle {
        var style = LevelStyle.empty
        if inheritsFromParents {
            for parent in parents { style = style.merged(over: parent.shape?.text?.listStyle[level] ?? .empty) }
        }
        style = style.merged(over: themeListStyle[level])
        style = style.merged(over: defaultTextStyle[level])
        return style.merged(over: Self.builtInLevel)
    }

    /// A level's complete formatting, including the element's own list style.
    public func levelStyle(_ level: Int) -> LevelStyle {
        (element.shape?.text?.listStyle[level] ?? .empty).merged(over: inheritedLevelStyle(level))
    }

    public func resolve(_ color: ColorRef) -> ResolvedColor { color.resolved(theme.colors) }

    public func resolve(_ style: CharacterStyle, scale: Double = 1) -> ResolvedCharacterStyle {
        var color = style.color.map(resolve) ?? .black
        var underline = style.underline ?? false
        if style.link != nil {
            // Links show in the theme's link color, underlined, unless the text says otherwise.
            if style.color == nil { color = resolve(ColorRef(theme: .hyperlink)) }
            if style.underline == nil { underline = true }
        }
        return ResolvedCharacterStyle(fontFamily: theme.fonts.resolve(style.fontFamily ?? "+mn-lt"),
                                      fontSize: max(1, (style.fontSize ?? 18) * scale), bold: style.bold ?? false,
                                      italic: style.italic ?? false, underline: underline, strikethrough: style.strikethrough ?? false,
                                      color: color, highlight: style.highlight.map(resolve), baseline: style.baseline ?? .normal,
                                      link: style.link)
    }

    /// The gray prompt shown while editing when this placeholder is empty.
    public var prompt: String? {
        guard let type = element.placeholder?.type, element.shape?.text?.isEmpty ?? true else { return nil }
        return type.prompt
    }

    /// The text ready to lay out. Slide number fields show `slideNumber` when given.
    public func resolvedParagraphs(_ body: TextBody? = nil, slideNumber: Int? = nil) -> [ResolvedParagraph] {
        guard let body = body ?? element.shape?.text else { return [] }
        let properties = bodyProperties
        let scale = properties.autofit == .shrinkOnOverflow ? max(0.05, min(1, properties.fontScale)) : 1
        let spacingFactor = properties.autofit == .shrinkOnOverflow ? max(0, 1 - properties.lineSpacingReduction) : 1
        var counters: [Int: (scheme: AutoNumberScheme, next: Int)] = [:]
        var levelCache: [Int: LevelStyle] = [:]
        var result: [ResolvedParagraph] = []
        result.reserveCapacity(body.paragraphs.count)
        for paragraph in body.paragraphs {
            let level: LevelStyle
            if let cached = levelCache[paragraph.level] {
                level = cached
            } else {
                level = (body.listStyle[paragraph.level]).merged(over: inheritedLevelStyle(paragraph.level))
                levelCache[paragraph.level] = level
            }
            let paragraphStyle = paragraph.style.merged(over: level.paragraph)
            let runs = paragraph.runs.map { run -> ResolvedRun in
                var text = run.text
                if run.field == .slideNumber, let slideNumber { text = String(slideNumber) }
                return ResolvedRun(text: text, style: resolve(run.style.merged(over: level.character), scale: scale), field: run.field)
            }
            let endStyle = resolve(paragraph.endStyle.merged(over: level.character), scale: scale)
            let firstStyle = runs.first(where: { !$0.text.isEmpty })?.style ?? endStyle

            var bulletText: String?
            switch paragraphStyle.bullet ?? Bullet.none {
            case .none:
                counters = counters.filter { $0.key < paragraph.level }
            case .character(let character):
                counters = counters.filter { $0.key < paragraph.level }
                bulletText = character
            case .number(let scheme, let start):
                counters = counters.filter { $0.key <= paragraph.level }
                var number = start
                if let counter = counters[paragraph.level], counter.scheme == scheme { number = counter.next }
                if !paragraph.isEmpty { counters[paragraph.level] = (scheme, number + 1) }
                bulletText = scheme.label(for: number)
            }
            let bullet = bulletText.map { text in
                ResolvedBullet(text: text, fontFamily: paragraphStyle.bulletFont.map(theme.fonts.resolve) ?? firstStyle.fontFamily,
                               fontSize: firstStyle.fontSize * (paragraphStyle.bulletSize ?? 1),
                               color: paragraphStyle.bulletColor.map(resolve) ?? firstStyle.color)
            }
            result.append(ResolvedParagraph(runs: runs, level: paragraph.level, alignment: paragraphStyle.alignment ?? .left,
                                            lineSpacing: (paragraphStyle.lineSpacing ?? 1) * spacingFactor,
                                            spaceBefore: (paragraphStyle.spaceBefore ?? 0) * spacingFactor,
                                            spaceAfter: (paragraphStyle.spaceAfter ?? 0) * spacingFactor,
                                            marginLeft: paragraphStyle.marginLeft ?? 0, indent: paragraphStyle.indent ?? 0,
                                            bullet: bullet, endStyle: endStyle))
        }
        return result
    }
}

extension Presentation {
    /// The inheritance chain for an element on a slide.
    public func style(for element: SlideElement, on slide: Slide) -> ElementStyle {
        let theme = theme(for: slide)
        var parents: [SlideElement] = []
        if let ref = element.placeholder {
            if let layout = layout(for: slide), let match = layout.placeholder(matching: ref) {
                parents.append(match)
                if let master = theme.placeholder(matching: match.placeholder ?? ref) { parents.append(master) }
            } else if let master = theme.placeholder(matching: ref) {
                parents.append(master)
            }
        }
        return ElementStyle(element: element, parents: parents, theme: theme, defaultTextStyle: defaultTextStyle)
    }

    /// The inheritance chain for an element on a layout: layout placeholders inherit from the theme's.
    public func style(for element: SlideElement, inLayout layout: Layout, theme: Theme) -> ElementStyle {
        var parents: [SlideElement] = []
        if let ref = element.placeholder, let master = theme.placeholder(matching: ref) { parents.append(master) }
        return ElementStyle(element: element, parents: parents, theme: theme, defaultTextStyle: defaultTextStyle)
    }

    /// The inheritance chain for one of a theme's own elements.
    public func style(forThemeElement element: SlideElement, theme: Theme) -> ElementStyle {
        ElementStyle(element: element, parents: [], theme: theme, defaultTextStyle: defaultTextStyle)
    }

    /// Where an element on a slide sits, after inheritance.
    public func placement(of element: SlideElement, on slide: Slide) -> Placement {
        if let placement = element.placement { return placement }
        return style(for: element, on: slide).placement
    }

    /// A slide's background: its own, else its layout's, else its theme's.
    public func background(for slide: Slide) -> Fill {
        if let background = slide.background { return background }
        if let background = layout(for: slide)?.background { return background }
        return theme(for: slide).background
    }

    /// The layout's and theme's decorations a slide shows behind its own elements, back to front.
    public func backdropElements(for slide: Slide) -> [(element: SlideElement, style: ElementStyle)] {
        let theme = theme(for: slide)
        var result: [(SlideElement, ElementStyle)] = []
        let layout = layout(for: slide)
        if layout?.showsThemeElements ?? true {
            for element in theme.elements where element.placeholder == nil {
                result.append((element, style(forThemeElement: element, theme: theme)))
            }
        }
        if let layout {
            for element in layout.elements where element.placeholder == nil {
                result.append((element, style(for: element, inLayout: layout, theme: theme)))
            }
        }
        return result
    }
}
