import AppKit
import PuggleSlidesKit

/// Wraps a value as an attribute that compares by value, so attribute runs merge and split correctly.
nonisolated final class AttributeBox<Value: Hashable>: NSObject {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    override func isEqual(_ object: Any?) -> Bool { (object as? AttributeBox<Value>)?.value == value }
    override var hash: Int { value.hashValue }
}

extension NSAttributedString.Key {
    /// The paragraph's list level (Int).
    nonisolated static let slideLevel = NSAttributedString.Key("PSLevel")
    /// The paragraph's bullet (`BulletInfo`), drawn by `SlideLayoutManager`.
    nonisolated static let slideBullet = NSAttributedString.Key("PSBullet")
    /// A run's color as stored (`AttributeBox<ColorRef>`), so theme colors survive editing.
    nonisolated static let slideColor = NSAttributedString.Key("PSColor")
    nonisolated static let slideHighlight = NSAttributedString.Key("PSHighlight")
    /// A run's link (`AttributeBox<Hyperlink>`).
    nonisolated static let slideLink = NSAttributedString.Key("PSLink")
    /// Superscript or subscript (raw value of `BaselineShift`); the font shown is smaller than the stored size.
    nonisolated static let slideBaseline = NSAttributedString.Key("PSBaseline")
    /// A field's DrawingML type ("slidenum").
    nonisolated static let slideField = NSAttributedString.Key("PSField")
    /// The paragraph's explicit model formatting (`AttributeBox<ParagraphStyle>`), kept through editing.
    nonisolated static let slideParagraph = NSAttributedString.Key("PSParagraph")
}

/// A paragraph's bullet: what to draw, and where.
nonisolated final class BulletInfo: NSObject {
    let bullet: Bullet
    let level: Int
    /// The bullet's own font and color, or nil to follow the text's first character.
    let fontFamily: String?
    let color: NSColor?
    let sizeFraction: CGFloat
    /// Where the bullet sits: `marginLeft + indent` from the text area's left edge.
    let marginLeft: CGFloat
    let indent: CGFloat

    init(bullet: Bullet, level: Int, fontFamily: String?, color: NSColor?, sizeFraction: CGFloat, marginLeft: CGFloat, indent: CGFloat) {
        self.bullet = bullet
        self.level = level
        self.fontFamily = fontFamily
        self.color = color
        self.sizeFraction = sizeFraction
        self.marginLeft = marginLeft
        self.indent = indent
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BulletInfo else { return false }
        return bullet == other.bullet && level == other.level && fontFamily == other.fontFamily && color == other.color
            && sizeFraction == other.sizeFraction && marginLeft == other.marginLeft && indent == other.indent
    }

    override var hash: Int { bullet.hashValue ^ level }
}

/// Fonts by family, size and style, with a fallback when a family isn't installed.
@MainActor
enum SlideFonts {
    private static var cache: [String: NSFont] = [:]

    static func font(family: String, size: Double, bold: Bool, italic: Bool) -> NSFont {
        let key = "\(family)|\(size)|\(bold)|\(italic)"
        if let font = cache[key] { return font }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let manager = NSFontManager.shared
        let size = CGFloat(max(1, size))
        var font = manager.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: size)
            ?? NSFont(name: family, size: size).map { manager.convert($0, toHaveTrait: traits) }
        if font == nil {
            // Office and web fonts that aren't installed fall back to Arial.
            let base = manager.font(withFamily: "Arial", traits: traits, weight: bold ? 9 : 5, size: size) ?? NSFont.systemFont(ofSize: size)
            font = base
        }
        if bold, let current = font, !manager.traits(of: current).contains(.boldFontMask) { font = manager.convert(current, toHaveTrait: .boldFontMask) }
        if italic, let current = font, !manager.traits(of: current).contains(.italicFontMask) { font = manager.convert(current, toHaveTrait: .italicFontMask) }
        cache[key] = font
        return font!
    }
}

extension ResolvedColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension NSColor {
    /// The color as a model color, in sRGB.
    var resolvedColor: ResolvedColor {
        let color = usingColorSpace(.sRGB) ?? self
        return ResolvedColor(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent),
                             alpha: Double(color.alphaComponent))
    }
}

/// Builds TextKit text from resolved paragraphs.
@MainActor
enum SlideText {
    /// Superscript and subscript text shows at two thirds of its size, raised or lowered.
    static let baselineScale: Double = 2.0 / 3.0

    static func attributes(for style: ResolvedCharacterStyle, explicit: CharacterStyle?) -> [NSAttributedString.Key: Any] {
        let size = style.baseline == .normal ? style.fontSize : style.fontSize * baselineScale
        let font = SlideFonts.font(family: style.fontFamily, size: size, bold: style.bold, italic: style.italic)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.color.nsColor]
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let highlight = style.highlight { attributes[.backgroundColor] = highlight.nsColor }
        switch style.baseline {
        case .superscript:
            attributes[.baselineOffset] = style.fontSize * 0.33
            attributes[.slideBaseline] = BaselineShift.superscript.rawValue
        case .subscript:
            attributes[.baselineOffset] = -style.fontSize * 0.15
            attributes[.slideBaseline] = BaselineShift.subscript.rawValue
        case .normal: break
        }
        if let link = style.link { attributes[.slideLink] = AttributeBox(link) }
        if let color = explicit?.color { attributes[.slideColor] = AttributeBox(color) }
        if let highlight = explicit?.highlight { attributes[.slideHighlight] = AttributeBox(highlight) }
        return attributes
    }

    static func paragraphStyle(for paragraph: ResolvedParagraph, firstFont: NSFont?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = switch paragraph.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
        style.lineBreakMode = .byWordWrapping
        if paragraph.lineSpacing > 0, abs(paragraph.lineSpacing - 1) > 0.001 { style.lineHeightMultiple = paragraph.lineSpacing }
        style.paragraphSpacingBefore = paragraph.spaceBefore
        style.paragraphSpacing = paragraph.spaceAfter
        style.headIndent = max(0, paragraph.marginLeft)
        if let bullet = paragraph.bullet {
            let font = SlideFonts.font(family: bullet.fontFamily, size: bullet.fontSize, bold: false, italic: false)
            let width = (bullet.text as NSString).size(withAttributes: [.font: font]).width
            let bulletX = paragraph.marginLeft + paragraph.indent
            style.firstLineHeadIndent = max(0, max(paragraph.marginLeft, bulletX + width + font.pointSize * 0.25))
        } else {
            style.firstLineHeadIndent = max(0, paragraph.marginLeft + paragraph.indent)
        }
        style.defaultTabInterval = 72
        style.tabStops = []
        return style
    }

    static func bulletInfo(for paragraph: ResolvedParagraph, model: TextParagraph?, levelStyle: ParagraphStyle?) -> BulletInfo? {
        guard paragraph.bullet != nil else { return nil }
        let merged = (model?.style ?? .empty).merged(over: levelStyle ?? .empty)
        guard let kind = merged.bullet, kind != .none else {
            return nil
        }
        return BulletInfo(bullet: kind, level: paragraph.level, fontFamily: paragraph.bullet?.fontFamily,
                          color: merged.bulletColor == nil ? nil : paragraph.bullet?.color.nsColor,
                          sizeFraction: CGFloat(merged.bulletSize ?? 1), marginLeft: paragraph.marginLeft, indent: paragraph.indent)
    }

    /// The text for resolved paragraphs. `body` and `style` add what editing needs to save the text again: stored
    /// colors, explicit paragraph formatting and bullet specifications. `trailingSpace` adds a zero-width space
    /// after an empty last paragraph so it takes up a line.
    static func attributedString(_ paragraphs: [ResolvedParagraph], body: TextBody? = nil, style: ElementStyle? = nil,
                                 trailingSpace: Bool = true) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let model = body.flatMap { index < $0.paragraphs.count ? $0.paragraphs[index] : nil }
            let start = result.length
            for (runIndex, run) in paragraph.runs.enumerated() where !run.text.isEmpty {
                let explicit = model.flatMap { runIndex < $0.runs.count ? $0.runs[runIndex].style : nil }
                var attributes = attributes(for: run.style, explicit: explicit)
                if let field = run.field { attributes[.slideField] = field.typeName }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            let isLast = index == paragraphs.count - 1
            let endAttributes = attributes(for: paragraph.isEmpty ? paragraph.endStyle : (paragraph.runs.last { !$0.text.isEmpty }?.style ?? paragraph.endStyle),
                                           explicit: paragraph.isEmpty ? model?.endStyle : nil)
            if !isLast {
                result.append(NSAttributedString(string: "\n", attributes: endAttributes))
            } else if paragraph.isEmpty, trailingSpace {
                result.append(NSAttributedString(string: "\u{200B}", attributes: endAttributes))
            }
            let range = NSRange(location: start, length: result.length - start)
            guard range.length > 0 else { continue }
            let firstFont = result.attribute(.font, at: start, effectiveRange: nil) as? NSFont
            result.addAttribute(.paragraphStyle, value: paragraphStyle(for: paragraph, firstFont: firstFont), range: range)
            result.addAttribute(.slideLevel, value: paragraph.level, range: range)
            if let model { result.addAttribute(.slideParagraph, value: AttributeBox(model.style), range: range) }
            let levelStyle = style.map { $0.levelStyle(paragraph.level).paragraph }
            let info = bulletInfo(for: paragraph, model: model, levelStyle: levelStyle) ?? paragraph.bullet.map { bullet in
                BulletInfo(bullet: .character(bullet.text), level: paragraph.level, fontFamily: bullet.fontFamily, color: bullet.color.nsColor,
                           sizeFraction: 1, marginLeft: paragraph.marginLeft, indent: paragraph.indent)
            }
            if let info { result.addAttribute(.slideBullet, value: info, range: range) }
        }
        return result
    }
}

/// Lays out slide text and draws bullets beside list paragraphs, numbering lists as it goes.
nonisolated final class SlideLayoutManager: NSLayoutManager {
    /// Shows bullets on empty paragraphs, as while editing.
    var showsEmptyBullets = false
    /// The bullet for an empty last paragraph that has no characters yet (the insertion point after Return).
    var trailingBullet: (info: BulletInfo, font: NSFont, color: NSColor)?
    private var labels: [Int: String]?

    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
                                 changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        labels = nil
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }

    /// Bullet labels by paragraph start, with numbering counted per level as in `ElementStyle.resolvedParagraphs`.
    func bulletLabels() -> [Int: String] {
        if let labels { return labels }
        var result: [Int: String] = [:]
        guard let storage = textStorage else { return result }
        let string = storage.string as NSString
        var counters: [Int: (scheme: AutoNumberScheme, next: Int)] = [:]
        var location = 0
        repeat {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let info = range.length > 0 ? storage.attribute(.slideBullet, at: range.location, effectiveRange: nil) as? BulletInfo : nil
            let level = info?.level ?? (range.length > 0 ? storage.attribute(.slideLevel, at: range.location, effectiveRange: nil) as? Int ?? 0 : 0)
            let content = string.substring(with: range).trimmingCharacters(in: CharacterSet(charactersIn: "\n\u{200B}\u{2029}"))
            switch info?.bullet ?? Bullet.none {
            case .none:
                counters = counters.filter { $0.key < level }
            case .character(let character):
                counters = counters.filter { $0.key < level }
                result[range.location] = character
            case .number(let scheme, let start):
                counters = counters.filter { $0.key <= level }
                var number = start
                if let counter = counters[level], counter.scheme == scheme { number = counter.next }
                if !content.isEmpty { counters[level] = (scheme, number + 1) }
                result[range.location] = scheme.label(for: number)
            }
            location = NSMaxRange(range)
        } while location < string.length
        labels = result
        return result
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawBullets(glyphRange: glyphsToShow, at: origin)
    }

    private func drawBullets(glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let labels = bulletLabels()
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var position = string.paragraphRange(for: NSRange(location: characters.location, length: 0)).location
        while position < NSMaxRange(characters) || (position == characters.location && string.length > 0) {
            let range = string.paragraphRange(for: NSRange(location: position, length: 0))
            defer { position = NSMaxRange(range) }
            guard range.length > 0, let info = storage.attribute(.slideBullet, at: range.location, effectiveRange: nil) as? BulletInfo,
                  let label = labels[range.location] else {
                if range.length == 0 { break }
                continue
            }
            let content = string.substring(with: range).trimmingCharacters(in: CharacterSet(charactersIn: "\n\u{200B}\u{2029}"))
            if content.isEmpty, !showsEmptyBullets { continue }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 18)
            let color = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? .black
            let glyph = glyphIndexForCharacter(at: range.location)
            guard glyph < numberOfGlyphs else { continue }
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = location(forGlyphAt: glyph).y
            draw(label, info: info, textFont: font, textColor: color, x: origin.x + info.marginLeft + info.indent,
                 baselineY: origin.y + fragment.minY + baseline)
            if range.length == 0 { break }
        }
        // The empty paragraph after a final Return has no characters; its bullet sits on the extra line.
        if showsEmptyBullets, let trailing = trailingBullet, string.length == 0 || string.hasSuffix("\n") {
            let fragment = extraLineFragmentRect
            guard fragment.height > 0 else { return }
            let label = trailingLabel(for: trailing.info, labels: labels, string: string)
            draw(label, info: trailing.info, textFont: trailing.font, textColor: trailing.color,
                 x: origin.x + trailing.info.marginLeft + trailing.info.indent, baselineY: origin.y + fragment.minY + trailing.font.ascender)
        }
    }

    private func trailingLabel(for info: BulletInfo, labels: [Int: String], string: NSString) -> String {
        switch info.bullet {
        case .none: return ""
        case .character(let character): return character
        case .number(let scheme, let start):
            // Count the numbered paragraphs at this level just before the end.
            var count = 0
            var location = string.length
            while location > 0 {
                let range = string.paragraphRange(for: NSRange(location: location - 1, length: 0))
                guard let previous = textStorage?.attribute(.slideBullet, at: range.location, effectiveRange: nil) as? BulletInfo,
                      case .number(let otherScheme, _) = previous.bullet, otherScheme == scheme, previous.level >= info.level else { break }
                if previous.level == info.level { count += 1 }
                location = range.location
            }
            return scheme.label(for: start + count)
        }
    }

    private func draw(_ label: String, info: BulletInfo, textFont: NSFont, textColor: NSColor, x: CGFloat, baselineY: CGFloat) {
        let size = textFont.pointSize * info.sizeFraction
        let family = info.fontFamily ?? textFont.familyName ?? "Arial"
        let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) ?? textFont.withSize(size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: info.color ?? textColor]
        (label as NSString).draw(at: NSPoint(x: x, y: baselineY - font.ascender), withAttributes: attributes)
    }
}

/// Laid-out text ready to draw at a point in a flipped graphics context.
@MainActor
final class TextLayout {
    let storage: NSTextStorage
    let layoutManager: SlideLayoutManager
    let container: NSTextContainer
    /// The height the text needs.
    let usedHeight: CGFloat

    init(_ text: NSAttributedString, width: CGFloat, wraps: Bool) {
        storage = NSTextStorage(attributedString: text)
        layoutManager = SlideLayoutManager()
        layoutManager.usesFontLeading = true
        container = NSTextContainer(size: NSSize(width: wraps ? max(1, width) : 100_000, height: 100_000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        usedHeight = layoutManager.usedRect(for: container).height
    }

    /// Draws with the text area's top-left at `origin`. Paragraph states fade, move or hide single paragraphs
    /// (animations by paragraph); paragraphs past the end of the list draw as they are.
    func draw(at origin: CGPoint, paragraphStates: [SlideRenderer.ParagraphRenderState]? = nil) {
        let glyphs = layoutManager.glyphRange(for: container)
        guard let states = paragraphStates, let context = NSGraphicsContext.current?.cgContext else {
            layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
            return
        }
        let string = storage.string as NSString
        var location = 0, index = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            defer {
                location = NSMaxRange(range)
                index += 1
            }
            let state = index < states.count ? states[index] : SlideRenderer.ParagraphRenderState()
            guard !state.isHidden, state.opacity > 0.001 else { continue }
            let paragraphGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            context.saveGState()
            context.translateBy(x: state.offset.width, y: state.offset.height)
            if state.opacity < 0.999 { context.setAlpha(state.opacity) }
            layoutManager.drawBackground(forGlyphRange: paragraphGlyphs, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: paragraphGlyphs, at: origin)
            context.restoreGState()
        }
    }

    /// The rectangles a character range covers, one per line, from the text's top-left.
    func rects(for range: NSRange) -> [CGRect] {
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clipped.length > 0 else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: clipped, actualCharacterRange: nil)
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                              in: container) { rect, _ in rects.append(rect) }
        return rects
    }

    private struct Key: Hashable {
        let paragraphs: [ResolvedParagraph]
        let width: CGFloat
        let wraps: Bool
    }

    private static var cache: [Key: TextLayout] = [:]

    /// A cached layout of resolved paragraphs.
    static func make(_ paragraphs: [ResolvedParagraph], width: CGFloat, wraps: Bool) -> TextLayout {
        let key = Key(paragraphs: paragraphs, width: (width * 100).rounded() / 100, wraps: wraps)
        if let layout = cache[key] { return layout }
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        let layout = TextLayout(SlideText.attributedString(paragraphs), width: width, wraps: wraps)
        cache[key] = layout
        return layout
    }
}

/// Where an element's text goes and how big it is.
@MainActor
enum TextMetrics {
    /// The text area in shape space: the geometry's text rectangle minus the insets.
    static func textArea(for style: ElementStyle, size: CGSize) -> CGRect {
        let rect = PresetGeometry.textRect(for: style.geometry, in: CGRect(origin: .zero, size: size))
        let insets = style.bodyProperties.insets
        return CGRect(x: rect.minX + insets.left, y: rect.minY + insets.top,
                      width: max(1, rect.width - insets.left - insets.right), height: rect.height - insets.top - insets.bottom)
    }

    /// The height the element's text needs at its current width.
    static func textHeight(_ paragraphs: [ResolvedParagraph], style: ElementStyle, size: CGSize) -> CGFloat {
        let area = textArea(for: style, size: size)
        return TextLayout.make(paragraphs, width: area.width, wraps: style.bodyProperties.wraps).usedHeight
    }

    /// For "Resize shape to fit text": the frame height that fits the text exactly.
    static func fittedHeight(_ paragraphs: [ResolvedParagraph], style: ElementStyle, size: CGSize) -> CGFloat {
        let area = textArea(for: style, size: size)
        let chrome = size.height - area.height
        return max(1, textHeight(paragraphs, style: style, size: size) + chrome)
    }

    /// "Shrink text on overflow": the largest font scale (and line spacing reduction) that fits.
    static func shrinkScale(for element: SlideElement, style: ElementStyle, size: CGSize) -> (scale: Double, reduction: Double) {
        guard var shape = element.shape, var text = shape.text else { return (1, 0) }
        let area = textArea(for: style, size: size)
        let steps: [(Double, Double)] = [(1, 0), (0.925, 0.1), (0.85, 0.1), (0.775, 0.2), (0.7, 0.2), (0.625, 0.2), (0.55, 0.2),
                                         (0.475, 0.2), (0.4, 0.2), (0.325, 0.2), (0.25, 0.2)]
        for (scale, reduction) in steps {
            text.properties.fontScale = scale
            text.properties.lineSpacingReduction = reduction
            shape.text = text
            var probe = element
            probe.shape = shape
            let probeStyle = ElementStyle(element: probe, parents: style.parents, theme: style.theme, defaultTextStyle: style.defaultTextStyle)
            let height = TextLayout.make(probeStyle.resolvedParagraphs(), width: area.width, wraps: style.bodyProperties.wraps).usedHeight
            if height <= area.height + 0.5 { return (scale, reduction) }
        }
        return (0.25, 0.2)
    }
}
