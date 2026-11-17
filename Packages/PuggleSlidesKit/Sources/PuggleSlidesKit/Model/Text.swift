import Foundation

/// Where a link goes: a web or email address, or another slide in the presentation.
public enum Hyperlink: Hashable, Codable, Sendable {
    case url(String)
    case slide(UUID)
}

public enum BaselineShift: String, Codable, CaseIterable, Sendable {
    case normal, superscript, `subscript`
}

/// Character formatting. A nil property inherits: from the paragraph's list level, the layout and
/// the theme, down to the presentation's defaults.
public struct CharacterStyle: Hashable, Codable, Sendable {
    /// A font family name, or a theme font reference such as "+mn-lt" (body) or "+mj-lt" (headings).
    public var fontFamily: String?
    /// Points.
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var color: ColorRef?
    public var highlight: ColorRef?
    public var baseline: BaselineShift?
    public var link: Hyperlink?

    public init(fontFamily: String? = nil, fontSize: Double? = nil, bold: Bool? = nil, italic: Bool? = nil,
                underline: Bool? = nil, strikethrough: Bool? = nil, color: ColorRef? = nil, highlight: ColorRef? = nil,
                baseline: BaselineShift? = nil, link: Hyperlink? = nil) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.color = color
        self.highlight = highlight
        self.baseline = baseline
        self.link = link
    }

    public static let empty = CharacterStyle()

    public var isEmpty: Bool { self == .empty }

    /// This style, with the properties it leaves unset taken from `base`.
    public func merged(over base: CharacterStyle) -> CharacterStyle {
        CharacterStyle(fontFamily: fontFamily ?? base.fontFamily, fontSize: fontSize ?? base.fontSize, bold: bold ?? base.bold,
                       italic: italic ?? base.italic, underline: underline ?? base.underline,
                       strikethrough: strikethrough ?? base.strikethrough, color: color ?? base.color,
                       highlight: highlight ?? base.highlight, baseline: baseline ?? base.baseline, link: link ?? base.link)
    }
}

public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right, justified
}

/// DrawingML's numbering schemes (a subset of ST_TextAutonumberScheme covering the list presets).
public enum AutoNumberScheme: String, Codable, CaseIterable, Sendable {
    case arabicPeriod, arabicParenR, arabicParenBoth, arabicPlain
    case alphaLcPeriod, alphaUcPeriod, alphaLcParenR, alphaUcParenR, alphaLcParenBoth, alphaUcParenBoth
    case romanLcPeriod, romanUcPeriod, romanLcParenR, romanUcParenR, romanLcParenBoth, romanUcParenBoth

    /// The label shown for item `number` (1-based): "3.", "c)", "(iv)".
    public func label(for number: Int) -> String {
        let core: String
        switch self {
        case .arabicPeriod, .arabicParenR, .arabicParenBoth, .arabicPlain:
            core = String(number)
        case .alphaLcPeriod, .alphaLcParenR, .alphaLcParenBoth:
            core = Self.alphabetic(number).lowercased()
        case .alphaUcPeriod, .alphaUcParenR, .alphaUcParenBoth:
            core = Self.alphabetic(number)
        case .romanLcPeriod, .romanLcParenR, .romanLcParenBoth:
            core = Self.roman(number).lowercased()
        case .romanUcPeriod, .romanUcParenR, .romanUcParenBoth:
            core = Self.roman(number)
        }
        switch self {
        case .arabicPeriod, .alphaLcPeriod, .alphaUcPeriod, .romanLcPeriod, .romanUcPeriod: return core + "."
        case .arabicParenR, .alphaLcParenR, .alphaUcParenR, .romanLcParenR, .romanUcParenR: return core + ")"
        case .arabicParenBoth, .alphaLcParenBoth, .alphaUcParenBoth, .romanLcParenBoth, .romanUcParenBoth: return "(" + core + ")"
        case .arabicPlain: return core
        }
    }

    /// A, B, … Z, AA, BB, … as Office counts.
    static func alphabetic(_ number: Int) -> String {
        guard number > 0 else { return String(number) }
        let letter = Character(UnicodeScalar(UInt8(65 + (number - 1) % 26)))
        return String(repeating: letter, count: (number - 1) / 26 + 1)
    }

    static func roman(_ number: Int) -> String {
        guard number > 0, number < 4000 else { return String(number) }
        let values = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = number, result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}

public enum Bullet: Hashable, Codable, Sendable {
    case none
    /// A bullet character such as "●".
    case character(String)
    /// Automatic numbering, starting at `startAt`.
    case number(AutoNumberScheme, startAt: Int)
}

/// Paragraph formatting. A nil property inherits, like `CharacterStyle`.
public struct ParagraphStyle: Hashable, Codable, Sendable {
    public var alignment: TextAlignment?
    /// A multiple of single spacing, such as 1.15.
    public var lineSpacing: Double?
    /// Points.
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    /// Distance in points from the text area's left edge to the text (DrawingML's marL).
    public var marginLeft: Double?
    /// The first line's offset from `marginLeft`; negative values hang the bullet to the left.
    public var indent: Double?
    public var bullet: Bullet?
    /// The bullet's font, or nil to use the text's.
    public var bulletFont: String?
    /// The bullet's color, or nil to use the text's.
    public var bulletColor: ColorRef?
    /// The bullet's size as a fraction of the text's, or nil for the same size.
    public var bulletSize: Double?

    public init(alignment: TextAlignment? = nil, lineSpacing: Double? = nil, spaceBefore: Double? = nil, spaceAfter: Double? = nil,
                marginLeft: Double? = nil, indent: Double? = nil, bullet: Bullet? = nil, bulletFont: String? = nil,
                bulletColor: ColorRef? = nil, bulletSize: Double? = nil) {
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.marginLeft = marginLeft
        self.indent = indent
        self.bullet = bullet
        self.bulletFont = bulletFont
        self.bulletColor = bulletColor
        self.bulletSize = bulletSize
    }

    public static let empty = ParagraphStyle()

    public var isEmpty: Bool { self == .empty }

    public func merged(over base: ParagraphStyle) -> ParagraphStyle {
        ParagraphStyle(alignment: alignment ?? base.alignment, lineSpacing: lineSpacing ?? base.lineSpacing,
                       spaceBefore: spaceBefore ?? base.spaceBefore, spaceAfter: spaceAfter ?? base.spaceAfter,
                       marginLeft: marginLeft ?? base.marginLeft, indent: indent ?? base.indent, bullet: bullet ?? base.bullet,
                       bulletFont: bulletFont ?? base.bulletFont, bulletColor: bulletColor ?? base.bulletColor,
                       bulletSize: bulletSize ?? base.bulletSize)
    }
}

/// Text that fills itself in, such as the slide number.
public enum TextFieldKind: Hashable, Codable, Sendable {
    case slideNumber
    /// A date or time, by its DrawingML field type ("datetime1" …).
    case dateTime(String)
    /// Any other DrawingML field type, kept as found.
    case other(String)

    /// The DrawingML field type.
    public var typeName: String {
        switch self {
        case .slideNumber: "slidenum"
        case .dateTime(let type): type
        case .other(let type): type
        }
    }

    public init(typeName: String) {
        switch typeName {
        case "slidenum": self = .slideNumber
        case let name where name.hasPrefix("datetime"): self = .dateTime(name)
        default: self = .other(typeName)
        }
    }
}

/// A stretch of text with one style. A line break inside a paragraph is U+2028 (LINE SEPARATOR).
public struct TextRun: Hashable, Codable, Sendable {
    public var text: String
    public var style: CharacterStyle
    /// Set when the run is a field; `text` is then the last value shown.
    public var field: TextFieldKind?

    public init(_ text: String, style: CharacterStyle = .empty, field: TextFieldKind? = nil) {
        self.text = text
        self.style = style
        self.field = field
    }

    public static let lineBreak = "\u{2028}"
}

public struct TextParagraph: Hashable, Codable, Sendable {
    public var runs: [TextRun]
    /// The list level, 0...8 (the indent level).
    public var level: Int
    public var style: ParagraphStyle
    /// The style of the paragraph mark, which decides an empty paragraph's height and new text's look.
    public var endStyle: CharacterStyle

    public init(runs: [TextRun] = [], level: Int = 0, style: ParagraphStyle = .empty, endStyle: CharacterStyle = .empty) {
        self.runs = runs
        self.level = max(0, min(8, level))
        self.style = style
        self.endStyle = endStyle
    }

    public init(_ text: String, style: CharacterStyle = .empty, level: Int = 0) {
        self.init(runs: text.isEmpty ? [] : [TextRun(text, style: style)], level: level, endStyle: style)
    }

    public var text: String { runs.map(\.text).joined() }
    public var isEmpty: Bool { runs.allSatisfy { $0.text.isEmpty } }
}

/// The text fitting choices.
public enum Autofit: String, Codable, CaseIterable, Sendable {
    case none, shrinkOnOverflow, resizeShape

    public var title: String {
        switch self {
        case .none: "Do not autofit"
        case .shrinkOnOverflow: "Shrink text on overflow"
        case .resizeShape: "Resize shape to fit text"
        }
    }
}

public enum VerticalAnchor: String, Codable, CaseIterable, Sendable {
    case top, middle, bottom
}

/// Padding between a shape's edge and its text, in points.
public struct TextInsets: Hashable, Codable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public init(all value: Double) {
        self.init(left: value, top: value, right: value, bottom: value)
    }

    /// DrawingML's defaults when a file says nothing: 0.1 inch left and right, 0.05 inch top and bottom.
    public static let office = TextInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)
    /// The "Indentation padding" of new shapes and text boxes: 0.1 inch all round.
    public static let standard = TextInsets(all: 7.2)
}

/// How text sits in its shape. Nil properties inherit.
public struct TextBodyProperties: Hashable, Codable, Sendable {
    public var anchor: VerticalAnchor?
    public var insets: TextInsets?
    public var autofit: Autofit?
    /// With `.shrinkOnOverflow`, the scale applied to font sizes to make the text fit (1 = 100%).
    public var fontScale: Double?
    /// With `.shrinkOnOverflow`, how much line spacing is reduced (0.2 = 20%).
    public var lineSpacingReduction: Double?
    /// False keeps each paragraph on one line.
    public var wraps: Bool?

    public init(anchor: VerticalAnchor? = nil, insets: TextInsets? = nil, autofit: Autofit? = nil, fontScale: Double? = nil,
                lineSpacingReduction: Double? = nil, wraps: Bool? = nil) {
        self.anchor = anchor
        self.insets = insets
        self.autofit = autofit
        self.fontScale = fontScale
        self.lineSpacingReduction = lineSpacingReduction
        self.wraps = wraps
    }

    public static let empty = TextBodyProperties()

    public func merged(over base: TextBodyProperties) -> TextBodyProperties {
        TextBodyProperties(anchor: anchor ?? base.anchor, insets: insets ?? base.insets, autofit: autofit ?? base.autofit,
                           fontScale: fontScale ?? base.fontScale, lineSpacingReduction: lineSpacingReduction ?? base.lineSpacingReduction,
                           wraps: wraps ?? base.wraps)
    }
}

/// The default formatting for one list level.
public struct LevelStyle: Hashable, Codable, Sendable {
    public var paragraph: ParagraphStyle
    public var character: CharacterStyle

    public init(paragraph: ParagraphStyle = .empty, character: CharacterStyle = .empty) {
        self.paragraph = paragraph
        self.character = character
    }

    public static let empty = LevelStyle()

    public var isEmpty: Bool { paragraph.isEmpty && character.isEmpty }

    public func merged(over base: LevelStyle) -> LevelStyle {
        LevelStyle(paragraph: paragraph.merged(over: base.paragraph), character: character.merged(over: base.character))
    }
}

/// Default formatting for each of the nine list levels (DrawingML's list style).
public struct ListStyle: Hashable, Codable, Sendable {
    /// Keyed by level, 0...8; missing levels have no defaults.
    public var levels: [Int: LevelStyle]

    public init(levels: [Int: LevelStyle] = [:]) {
        self.levels = levels.filter { (0...8).contains($0.key) && !$0.value.isEmpty }
    }

    public static let empty = ListStyle()

    public var isEmpty: Bool { levels.isEmpty }

    public subscript(level: Int) -> LevelStyle {
        get { levels[level] ?? .empty }
        set {
            guard (0...8).contains(level) else { return }
            levels[level] = newValue.isEmpty ? nil : newValue
        }
    }

    public func merged(over base: ListStyle) -> ListStyle {
        var result = base
        for (level, style) in levels { result[level] = style.merged(over: base[level]) }
        return result
    }
}

/// The text in a shape: paragraphs, how they sit in the shape, and per-level defaults.
public struct TextBody: Hashable, Codable, Sendable {
    /// Never empty: an empty text body has one empty paragraph.
    public var paragraphs: [TextParagraph] {
        didSet { if paragraphs.isEmpty { paragraphs = [TextParagraph()] } }
    }
    public var properties: TextBodyProperties
    public var listStyle: ListStyle

    public init(paragraphs: [TextParagraph] = [TextParagraph()], properties: TextBodyProperties = .empty, listStyle: ListStyle = .empty) {
        self.paragraphs = paragraphs.isEmpty ? [TextParagraph()] : paragraphs
        self.properties = properties
        self.listStyle = listStyle
    }

    /// Plain text, one paragraph per line.
    public init(_ text: String, style: CharacterStyle = .empty, properties: TextBodyProperties = .empty) {
        let lines = text.components(separatedBy: "\n")
        self.init(paragraphs: lines.map { TextParagraph($0, style: style) }, properties: properties)
    }

    public static let empty = TextBody()

    /// The text with paragraphs separated by newlines.
    public var plainText: String { paragraphs.map(\.text).joined(separator: "\n") }

    public var isEmpty: Bool { paragraphs.allSatisfy(\.isEmpty) }
}
