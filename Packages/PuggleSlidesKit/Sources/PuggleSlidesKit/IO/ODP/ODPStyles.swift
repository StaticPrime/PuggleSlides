import Foundation

// MARK: - Properties

/// A text highlight: none ("transparent") or a color.
enum ODFHighlight: Hashable {
    case none
    case color(RGBColor)
}

/// Character formatting an ODF style states (`style:text-properties`); nil properties inherit.
struct ODFTextProperties: Hashable {
    var fontFamily: String?
    /// Points.
    var fontSize: Double?
    /// A size relative to what's inherited ("80%"), as list levels give their bullets.
    var relativeFontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strikethrough: Bool?
    var color: RGBColor?
    /// `style:use-window-font-color`: for bullets, the text's own color.
    var usesTextColor: Bool?
    var highlight: ODFHighlight?
    var baseline: BaselineShift?

    var isEmpty: Bool { self == ODFTextProperties() }

    func merged(over base: ODFTextProperties) -> ODFTextProperties {
        var result = self
        if fontSize == nil {
            if let relative = relativeFontSize, let size = base.fontSize {
                result.fontSize = size * relative
                result.relativeFontSize = nil
            } else if relativeFontSize == nil {
                result.fontSize = base.fontSize
                result.relativeFontSize = base.relativeFontSize
            }
        } else {
            result.relativeFontSize = nil
        }
        result.fontFamily = fontFamily ?? base.fontFamily
        result.bold = bold ?? base.bold
        result.italic = italic ?? base.italic
        result.underline = underline ?? base.underline
        result.strikethrough = strikethrough ?? base.strikethrough
        result.color = color ?? base.color
        result.usesTextColor = usesTextColor ?? base.usesTextColor
        result.highlight = highlight ?? base.highlight
        result.baseline = baseline ?? base.baseline
        return result
    }

    init() {}

    init(_ node: ODFNode?, fonts: [String: String]) {
        guard let node else { return }
        if let name = node["style:font-name"], !name.isEmpty {
            fontFamily = fonts[name] ?? name
        } else if let family = node["fo:font-family"] {
            fontFamily = Self.firstFamily(family)
        }
        if let size = node["fo:font-size"] {
            if let points = ODFValue.length(size), points > 0 {
                fontSize = min(points, 4000)
            } else if let percent = ODFValue.percent(size), percent > 0 {
                relativeFontSize = min(percent, 40)
            }
        }
        if let weight = node["fo:font-weight"]?.lowercased() {
            bold = weight == "bold" || (Int(weight) ?? 400) >= 600
        }
        if let style = node["fo:font-style"]?.lowercased() { italic = style != "normal" }
        if let style = node["style:text-underline-style"] {
            underline = style != "none" && node["style:text-underline-type"] != "none"
        } else if node["style:text-underline-type"] == "none" {
            underline = false
        }
        if let style = node["style:text-line-through-style"] {
            strikethrough = style != "none" && node["style:text-line-through-type"] != "none"
        } else if let type = node["style:text-line-through-type"] {
            strikethrough = type != "none"
        }
        color = ODFValue.color(node["fo:color"])
        usesTextColor = ODFValue.bool(node["style:use-window-font-color"])
        if let background = node["fo:background-color"] {
            highlight = background == "transparent" ? ODFHighlight.none : ODFValue.color(background).map { .color($0) }
        }
        if let position = node["style:text-position"]?.lowercased() {
            let first = position.split(separator: " ").first.map(String.init) ?? ""
            if first == "super" {
                baseline = .superscript
            } else if first == "sub" {
                baseline = .subscript
            } else if let shift = ODFValue.percent(first) {
                baseline = shift > 0 ? .superscript : shift < 0 ? .subscript : .normal
            }
        }
    }

    /// The first family of a CSS-style list ("'Avenir Next', sans-serif" is "Avenir Next").
    static func firstFamily(_ list: String) -> String? {
        let first = list.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let unquoted = first.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return unquoted.isEmpty ? nil : unquoted
    }

    /// The attributes of `style:text-properties`; Asian and complex-script variants follow the Western ones.
    func write(to xml: inout XMLWriter) {
        if let fontFamily {
            xml.attribute("style:font-name", fontFamily)
            xml.attribute("style:font-name-asian", fontFamily)
            xml.attribute("style:font-name-complex", fontFamily)
        }
        if let fontSize {
            let size = ODFFormat.pt(min(max(fontSize, 0.5), 4000))
            xml.raw(" fo:font-size=\"\(size)\" style:font-size-asian=\"\(size)\" style:font-size-complex=\"\(size)\"")
        } else if let relativeFontSize {
            xml.raw(" fo:font-size=\"\(ODFFormat.percent(min(max(relativeFontSize, 0.01), 40)))\"")
        }
        if let bold {
            let value = bold ? "bold" : "normal"
            xml.raw(" fo:font-weight=\"\(value)\" style:font-weight-asian=\"\(value)\" style:font-weight-complex=\"\(value)\"")
        }
        if let italic {
            let value = italic ? "italic" : "normal"
            xml.raw(" fo:font-style=\"\(value)\" style:font-style-asian=\"\(value)\" style:font-style-complex=\"\(value)\"")
        }
        if let underline {
            xml.raw(underline ? " style:text-underline-style=\"solid\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""
                    : " style:text-underline-style=\"none\"")
        }
        if let strikethrough {
            xml.raw(strikethrough ? " style:text-line-through-style=\"solid\" style:text-line-through-type=\"single\""
                    : " style:text-line-through-style=\"none\"")
        }
        if let color { xml.raw(" fo:color=\"\(ODFFormat.color(color))\"") }
        if let usesTextColor { xml.raw(" style:use-window-font-color=\"\(usesTextColor)\"") }
        switch highlight {
        case .none?: xml.raw(" fo:background-color=\"transparent\"")
        case .color(let color)?: xml.raw(" fo:background-color=\"\(ODFFormat.color(color))\"")
        case nil: break
        }
        switch baseline {
        case .superscript?: xml.raw(" style:text-position=\"super 58%\"")
        case .subscript?: xml.raw(" style:text-position=\"sub 58%\"")
        case .normal?: xml.raw(" style:text-position=\"0% 100%\"")
        case nil: break
        }
    }
}

/// Paragraph formatting an ODF style states (`style:paragraph-properties`); nil properties inherit.
struct ODFParagraphProperties: Hashable {
    var alignment: TextAlignment?
    /// Proportional line spacing, as a multiple of single spacing.
    var lineSpacing: Double?
    /// Exact or minimum line height in points, turned into a multiple once the font size is known.
    var lineHeight: Double?
    var spaceBefore: Double?
    var spaceAfter: Double?
    var marginLeft: Double?
    var indent: Double?

    var isEmpty: Bool { self == ODFParagraphProperties() }

    func merged(over base: ODFParagraphProperties) -> ODFParagraphProperties {
        var result = ODFParagraphProperties()
        result.alignment = alignment ?? base.alignment
        if lineSpacing != nil || lineHeight != nil {
            result.lineSpacing = lineSpacing
            result.lineHeight = lineHeight
        } else {
            result.lineSpacing = base.lineSpacing
            result.lineHeight = base.lineHeight
        }
        result.spaceBefore = spaceBefore ?? base.spaceBefore
        result.spaceAfter = spaceAfter ?? base.spaceAfter
        result.marginLeft = marginLeft ?? base.marginLeft
        result.indent = indent ?? base.indent
        return result
    }

    init() {}

    init(_ node: ODFNode?) {
        guard let node else { return }
        switch node["fo:text-align"] {
        case "start", "left": alignment = .left
        case "end", "right": alignment = .right
        case "center": alignment = .center
        case "justify": alignment = .justified
        default: break
        }
        if let height = node["fo:line-height"] {
            if height == "normal" {
                lineSpacing = 1
            } else if let percent = ODFValue.percent(height) {
                lineSpacing = min(max(percent, 0), 132)
            } else if let points = ODFValue.length(height), points >= 0 {
                lineHeight = points
            }
        } else if let minimum = ODFValue.length(node["style:line-height-at-least"]), minimum > 0 {
            lineHeight = minimum
        }
        spaceBefore = ODFValue.length(node["fo:margin-top"]).map { max(0, $0) }
        spaceAfter = ODFValue.length(node["fo:margin-bottom"]).map { max(0, $0) }
        marginLeft = ODFValue.length(node["fo:margin-left"])
        indent = ODFValue.length(node["fo:text-indent"])
    }

    func write(to xml: inout XMLWriter) {
        switch alignment {
        case .left?: xml.raw(" fo:text-align=\"start\"")
        case .center?: xml.raw(" fo:text-align=\"center\"")
        case .right?: xml.raw(" fo:text-align=\"end\"")
        case .justified?: xml.raw(" fo:text-align=\"justify\"")
        case nil: break
        }
        if let lineSpacing { xml.raw(" fo:line-height=\"\(ODFFormat.percent(min(max(lineSpacing, 0), 132)))\"") }
        if let spaceBefore { xml.raw(" fo:margin-top=\"\(ODFFormat.pt(max(0, spaceBefore)))\"") }
        if let spaceAfter { xml.raw(" fo:margin-bottom=\"\(ODFFormat.pt(max(0, spaceAfter)))\"") }
        if let marginLeft { xml.raw(" fo:margin-left=\"\(ODFFormat.pt(marginLeft))\"") }
        if let indent { xml.raw(" fo:text-indent=\"\(ODFFormat.pt(indent))\"") }
    }
}

/// A picture's crop, as lengths cut from each edge of its natural size.
struct ODFClip: Hashable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    /// "rect(1pt, 2pt, 3pt, 4pt)", with or without commas.
    init?(_ text: String?) {
        guard let text, let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        let parts = text[text.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        guard parts.count == 4 else { return nil }
        let values = parts.map { $0 == "auto" ? 0 : ODFValue.length($0) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        (top, right, bottom, left) = (values[0]!, values[1]!, values[2]!, values[3]!)
    }

    init(top: Double, right: Double, bottom: Double, left: Double) {
        (self.top, self.right, self.bottom, self.left) = (top, right, bottom, left)
    }

    var text: String { "rect(\(ODFFormat.pt(top)), \(ODFFormat.pt(right)), \(ODFFormat.pt(bottom)), \(ODFFormat.pt(left)))" }
}

/// What a graphic or presentation style states about a shape: fill, stroke, crop, mirroring and how text sits.
struct ODFGraphicProperties: Hashable {
    var fill: String?
    var fillColor: RGBColor?
    var gradientName: String?
    var imageName: String?
    var hatchName: String?
    var repeatMode: String?
    var opacity: Double?
    var stroke: String?
    var strokeColor: RGBColor?
    var strokeWidth: Double?
    var strokeOpacity: Double?
    var dashName: String?
    var markerStart: String?
    var markerEnd: String?
    var markerStartWidth: Double?
    var markerEndWidth: Double?
    var markerStartCenter: Bool?
    var markerEndCenter: Bool?
    var clip: ODFClip?
    var mirrorHorizontal: Bool?
    var mirrorVertical: Bool?
    var anchor: VerticalAnchor?
    var paddingLeft: Double?
    var paddingTop: Double?
    var paddingRight: Double?
    var paddingBottom: Double?
    var autoGrowHeight: Bool?
    var shrinkToFit: Bool?
    var fitToSize: Bool?
    var wraps: Bool?
    /// A picture's own opacity (`draw:image-opacity`), 0...1.
    var imageOpacity: Double?
    /// A picture's brightness and contrast change (`draw:luminance`, `draw:contrast`), -1...1.
    var luminance: Double?
    var contrast: Double?
    /// `draw:color-mode`: "standard", "greyscale", "mono" or "watermark".
    var colorMode: String?
    /// `draw:color-inversion`: the picture's colors inverted.
    var colorInversion: Bool?

    var isEmpty: Bool { self == ODFGraphicProperties() }

    /// The color modes ODF names; anything else is left unwritten.
    static let colorModes: Set<String> = ["standard", "greyscale", "mono", "watermark"]

    func merged(over base: ODFGraphicProperties) -> ODFGraphicProperties {
        var result = ODFGraphicProperties()
        result.fill = fill ?? base.fill
        result.fillColor = fillColor ?? base.fillColor
        result.gradientName = gradientName ?? base.gradientName
        result.imageName = imageName ?? base.imageName
        result.hatchName = hatchName ?? base.hatchName
        result.repeatMode = repeatMode ?? base.repeatMode
        result.opacity = opacity ?? base.opacity
        result.stroke = stroke ?? base.stroke
        result.strokeColor = strokeColor ?? base.strokeColor
        result.strokeWidth = strokeWidth ?? base.strokeWidth
        result.strokeOpacity = strokeOpacity ?? base.strokeOpacity
        result.dashName = dashName ?? base.dashName
        result.markerStart = markerStart ?? base.markerStart
        result.markerEnd = markerEnd ?? base.markerEnd
        result.markerStartWidth = markerStartWidth ?? base.markerStartWidth
        result.markerEndWidth = markerEndWidth ?? base.markerEndWidth
        result.markerStartCenter = markerStartCenter ?? base.markerStartCenter
        result.markerEndCenter = markerEndCenter ?? base.markerEndCenter
        result.clip = clip ?? base.clip
        result.mirrorHorizontal = mirrorHorizontal ?? base.mirrorHorizontal
        result.mirrorVertical = mirrorVertical ?? base.mirrorVertical
        result.anchor = anchor ?? base.anchor
        result.paddingLeft = paddingLeft ?? base.paddingLeft
        result.paddingTop = paddingTop ?? base.paddingTop
        result.paddingRight = paddingRight ?? base.paddingRight
        result.paddingBottom = paddingBottom ?? base.paddingBottom
        result.autoGrowHeight = autoGrowHeight ?? base.autoGrowHeight
        result.shrinkToFit = shrinkToFit ?? base.shrinkToFit
        result.fitToSize = fitToSize ?? base.fitToSize
        result.wraps = wraps ?? base.wraps
        result.imageOpacity = imageOpacity ?? base.imageOpacity
        result.luminance = luminance ?? base.luminance
        result.contrast = contrast ?? base.contrast
        result.colorMode = colorMode ?? base.colorMode
        result.colorInversion = colorInversion ?? base.colorInversion
        return result
    }

    init() {}

    /// Reads fill attributes from `style:graphic-properties` or `style:drawing-page-properties`, and the rest when present.
    init(_ node: ODFNode?) {
        guard let node else { return }
        fill = node["draw:fill"]
        fillColor = ODFValue.color(node["draw:fill-color"])
        gradientName = node["draw:fill-gradient-name"]
        imageName = node["draw:fill-image-name"]
        hatchName = node["draw:fill-hatch-name"]
        repeatMode = node["style:repeat"]
        opacity = ODFValue.percent(node["draw:opacity"]).map { min(max($0, 0), 1) }
        stroke = node["draw:stroke"]
        strokeColor = ODFValue.color(node["svg:stroke-color"])
        strokeWidth = ODFValue.length(node["svg:stroke-width"]).map { max(0, $0) }
        strokeOpacity = ODFValue.percent(node["svg:stroke-opacity"]).map { min(max($0, 0), 1) }
        dashName = node["draw:stroke-dash"]
        markerStart = node["draw:marker-start"]
        markerEnd = node["draw:marker-end"]
        markerStartWidth = ODFValue.length(node["draw:marker-start-width"])
        markerEndWidth = ODFValue.length(node["draw:marker-end-width"])
        markerStartCenter = ODFValue.bool(node["draw:marker-start-center"])
        markerEndCenter = ODFValue.bool(node["draw:marker-end-center"])
        clip = ODFClip(node["fo:clip"])
        if let mirror = node["style:mirror"]?.lowercased() {
            mirrorHorizontal = mirror.contains("horizontal")
            mirrorVertical = mirror.contains("vertical")
        }
        switch node["draw:textarea-vertical-align"] {
        case "top", "justify": anchor = .top
        case "middle": anchor = .middle
        case "bottom": anchor = .bottom
        default: break
        }
        let all = ODFValue.length(node["fo:padding"])
        paddingLeft = ODFValue.length(node["fo:padding-left"]) ?? all
        paddingTop = ODFValue.length(node["fo:padding-top"]) ?? all
        paddingRight = ODFValue.length(node["fo:padding-right"]) ?? all
        paddingBottom = ODFValue.length(node["fo:padding-bottom"]) ?? all
        autoGrowHeight = ODFValue.bool(node["draw:auto-grow-height"])
        shrinkToFit = ODFValue.bool(node["style:shrink-to-fit"])
        if let fit = node["draw:fit-to-size"] {
            // LibreOffice writes its autofit as "shrink-to-fit" here.
            if fit == "shrink-to-fit" || fit == "autofit" { shrinkToFit = shrinkToFit ?? true } else { fitToSize = fit == "true" || fit == "all" }
        }
        switch node["fo:wrap-option"] {
        case "wrap": wraps = true
        case "no-wrap": wraps = false
        default: break
        }
        imageOpacity = ODFValue.percent(node["draw:image-opacity"]).map { min(max($0, 0), 1) }
        luminance = ODFValue.percent(node["draw:luminance"]).map { min(max($0, -1), 1) }
        contrast = ODFValue.percent(node["draw:contrast"]).map { min(max($0, -1), 1) }
        colorMode = node["draw:color-mode"]
        colorInversion = ODFValue.bool(node["draw:color-inversion"])
    }

    /// Fill attributes alone, for `style:drawing-page-properties`.
    func writeFill(to xml: inout XMLWriter) {
        if let fill { xml.raw(" draw:fill=\"\(fill)\"") }
        if let fillColor { xml.raw(" draw:fill-color=\"\(ODFFormat.color(fillColor))\"") }
        if let gradientName { xml.attribute("draw:fill-gradient-name", gradientName) }
        if let imageName { xml.attribute("draw:fill-image-name", imageName) }
        if let repeatMode { xml.raw(" style:repeat=\"\(repeatMode)\"") }
        if let opacity { xml.raw(" draw:opacity=\"\(ODFFormat.percent(min(max(opacity, 0), 1)))\"") }
    }

    func write(to xml: inout XMLWriter) {
        writeFill(to: &xml)
        if let stroke { xml.raw(" draw:stroke=\"\(stroke)\"") }
        if let dashName { xml.attribute("draw:stroke-dash", dashName) }
        if let strokeColor { xml.raw(" svg:stroke-color=\"\(ODFFormat.color(strokeColor))\"") }
        if let strokeWidth { xml.raw(" svg:stroke-width=\"\(ODFFormat.pt(max(0, strokeWidth)))\"") }
        if let strokeOpacity { xml.raw(" svg:stroke-opacity=\"\(ODFFormat.percent(min(max(strokeOpacity, 0), 1)))\"") }
        if let markerStart { xml.attribute("draw:marker-start", markerStart) }
        if let markerStartWidth { xml.raw(" draw:marker-start-width=\"\(ODFFormat.pt(max(0, markerStartWidth)))\"") }
        if let markerStartCenter { xml.raw(" draw:marker-start-center=\"\(markerStartCenter)\"") }
        if let markerEnd { xml.attribute("draw:marker-end", markerEnd) }
        if let markerEndWidth { xml.raw(" draw:marker-end-width=\"\(ODFFormat.pt(max(0, markerEndWidth)))\"") }
        if let markerEndCenter { xml.raw(" draw:marker-end-center=\"\(markerEndCenter)\"") }
        if let clip { xml.raw(" fo:clip=\"\(clip.text)\"") }
        switch (mirrorHorizontal ?? false, mirrorVertical ?? false) {
        case (true, true): xml.raw(" style:mirror=\"horizontal vertical\"")
        case (true, false): xml.raw(" style:mirror=\"horizontal\"")
        case (false, true): xml.raw(" style:mirror=\"vertical\"")
        case (false, false): if mirrorHorizontal != nil || mirrorVertical != nil { xml.raw(" style:mirror=\"none\"") }
        }
        switch anchor {
        case .top?: xml.raw(" draw:textarea-vertical-align=\"top\"")
        case .middle?: xml.raw(" draw:textarea-vertical-align=\"middle\"")
        case .bottom?: xml.raw(" draw:textarea-vertical-align=\"bottom\"")
        case nil: break
        }
        if let autoGrowHeight { xml.raw(" draw:auto-grow-height=\"\(autoGrowHeight)\"") }
        if let shrinkToFit { xml.raw(" style:shrink-to-fit=\"\(shrinkToFit)\"") }
        if let fitToSize { xml.raw(" draw:fit-to-size=\"\(fitToSize)\"") }
        if let wraps { xml.raw(wraps ? " fo:wrap-option=\"wrap\"" : " fo:wrap-option=\"no-wrap\"") }
        if let paddingLeft { xml.raw(" fo:padding-left=\"\(ODFFormat.pt(paddingLeft))\"") }
        if let paddingTop { xml.raw(" fo:padding-top=\"\(ODFFormat.pt(paddingTop))\"") }
        if let paddingRight { xml.raw(" fo:padding-right=\"\(ODFFormat.pt(paddingRight))\"") }
        if let paddingBottom { xml.raw(" fo:padding-bottom=\"\(ODFFormat.pt(paddingBottom))\"") }
        if let colorMode, Self.colorModes.contains(colorMode) { xml.raw(" draw:color-mode=\"\(colorMode)\"") }
        if let colorInversion { xml.raw(" draw:color-inversion=\"\(colorInversion)\"") }
        if let luminance { xml.raw(" draw:luminance=\"\(ODFFormat.percent(min(max(luminance, -1), 1)))\"") }
        if let contrast { xml.raw(" draw:contrast=\"\(ODFFormat.percent(min(max(contrast, -1), 1)))\"") }
        if let imageOpacity { xml.raw(" draw:image-opacity=\"\(ODFFormat.percent(min(max(imageOpacity, 0), 1)))\"") }
    }
}

/// What a drawing-page style states: the background, the transition, and what shows on the page.
struct ODFPageProperties: Hashable {
    var fill = ODFGraphicProperties()
    var transitionType: String?
    var transitionSubtype: String?
    var transitionReverse: Bool?
    var transitionSpeed: String?
    var legacyTransition: String?
    var visible: Bool?
    var backgroundVisible: Bool?
    var backgroundObjectsVisible: Bool?
    var displayPageNumber: Bool?
    var displayFooter: Bool?
    var displayDateTime: Bool?
    var displayHeader: Bool?

    init() {}

    init(_ node: ODFNode?) {
        guard let node else { return }
        fill = ODFGraphicProperties(node)
        transitionType = node["smil:type"]
        transitionSubtype = node["smil:subtype"]
        transitionReverse = node["smil:direction"].map { $0 == "reverse" }
        transitionSpeed = node["presentation:transition-speed"]
        legacyTransition = node["presentation:transition-style"]
        visible = node["presentation:visibility"].map { $0 != "hidden" }
        backgroundVisible = ODFValue.bool(node["presentation:background-visible"])
        backgroundObjectsVisible = ODFValue.bool(node["presentation:background-objects-visible"])
        displayPageNumber = ODFValue.bool(node["presentation:display-page-number"])
        displayFooter = ODFValue.bool(node["presentation:display-footer"])
        displayDateTime = ODFValue.bool(node["presentation:display-date-time"])
        displayHeader = ODFValue.bool(node["presentation:display-header"])
    }

    func merged(over base: ODFPageProperties) -> ODFPageProperties {
        var result = self
        result.fill = fill.merged(over: base.fill)
        result.transitionType = transitionType ?? base.transitionType
        result.transitionSubtype = transitionSubtype ?? base.transitionSubtype
        result.transitionReverse = transitionReverse ?? base.transitionReverse
        result.transitionSpeed = transitionSpeed ?? base.transitionSpeed
        result.legacyTransition = legacyTransition ?? base.legacyTransition
        result.visible = visible ?? base.visible
        result.backgroundVisible = backgroundVisible ?? base.backgroundVisible
        result.backgroundObjectsVisible = backgroundObjectsVisible ?? base.backgroundObjectsVisible
        result.displayPageNumber = displayPageNumber ?? base.displayPageNumber
        result.displayFooter = displayFooter ?? base.displayFooter
        result.displayDateTime = displayDateTime ?? base.displayDateTime
        result.displayHeader = displayHeader ?? base.displayHeader
        return result
    }

    func write(to xml: inout XMLWriter) {
        fill.writeFill(to: &xml)
        if fill.fill != nil { xml.raw(" draw:background-size=\"full\"") }
        if let backgroundVisible { xml.raw(" presentation:background-visible=\"\(backgroundVisible)\"") }
        if let backgroundObjectsVisible { xml.raw(" presentation:background-objects-visible=\"\(backgroundObjectsVisible)\"") }
        if let displayFooter { xml.raw(" presentation:display-footer=\"\(displayFooter)\"") }
        if let displayPageNumber { xml.raw(" presentation:display-page-number=\"\(displayPageNumber)\"") }
        if let displayDateTime { xml.raw(" presentation:display-date-time=\"\(displayDateTime)\"") }
        if let displayHeader { xml.raw(" presentation:display-header=\"\(displayHeader)\"") }
        if let visible, !visible { xml.raw(" presentation:visibility=\"hidden\"") }
        if let transitionType {
            xml.attribute("smil:type", transitionType)
            if let transitionSubtype { xml.attribute("smil:subtype", transitionSubtype) }
            if transitionReverse == true { xml.raw(" smil:direction=\"reverse\"") }
        }
        if let transitionSpeed { xml.raw(" presentation:transition-speed=\"\(transitionSpeed)\"") }
    }
}

// MARK: - Lists

/// One level of a list style: its label and where the label and text sit.
struct ODFListLevel: Hashable {
    enum Label: Hashable {
        case bullet(String)
        /// `style:num-format` ("1", "a", "A", "i", "I", or "" for none), prefix, suffix and first number.
        case number(format: String, prefix: String, suffix: String, start: Int)
        case image
    }

    var label: Label
    /// Where the label starts, from the paragraph's left edge.
    var spaceBefore: Double?
    /// From the label's start to the text.
    var minLabelWidth: Double?
    /// Label-alignment mode's text start and first-line offset.
    var marginLeft: Double?
    var indent: Double?
    var text = ODFTextProperties()

    /// The model's text start and first-line offset for a paragraph in a list at this level. As ODF says, the level's
    /// space before the label and the label's width add to the paragraph's own margin; the paragraph's first-line
    /// indent moves the label. Levels in label-alignment mode give the margins themselves.
    func modelMargins(margin: Double, textIndent: Double) -> (left: Double, indent: Double) {
        if let marginLeft { return (marginLeft, indent ?? 0) }
        let label = max(0, minLabelWidth ?? 0)
        return (margin + (spaceBefore ?? 0) + label, textIndent - label)
    }

    /// The paragraph margin and first-line indent that, with a level made by `ODFBulletValues.level(margins:)`, give the
    /// model's text start and first-line offset: the level holds the indentation, as LibreOffice's outline styles do.
    static func paragraphMargins(left: Double, indent: Double) -> (margin: Double, textIndent: Double) {
        (0, indent + max(0, -indent))
    }

    init(label: Label, spaceBefore: Double? = nil, minLabelWidth: Double? = nil, text: ODFTextProperties = ODFTextProperties()) {
        self.label = label
        self.spaceBefore = spaceBefore
        self.minLabelWidth = minLabelWidth
        self.text = text
    }

    init?(_ node: ODFNode, fonts: [String: String]) {
        switch node.name {
        case "text:list-level-style-bullet":
            label = .bullet(node["text:bullet-char"] ?? "•")
        case "text:list-level-style-number":
            label = .number(format: node["style:num-format"] ?? "", prefix: node["style:num-prefix"] ?? "", suffix: node["style:num-suffix"] ?? "",
                            start: min(max(ODFValue.int(node["text:start-value"]) ?? 1, 1), 32_767))
        case "text:list-level-style-image":
            label = .image
        default:
            return nil
        }
        let properties = node.child("style:list-level-properties")
        spaceBefore = ODFValue.length(properties?["text:space-before"])
        minLabelWidth = ODFValue.length(properties?["text:min-label-width"])
        if properties?["text:list-level-position-and-space-mode"] == "label-alignment",
           let alignment = properties?.child("style:list-level-label-alignment") {
            marginLeft = ODFValue.length(alignment["fo:margin-left"])
            indent = ODFValue.length(alignment["fo:text-indent"])
        }
        text = ODFTextProperties(node.child("style:text-properties"), fonts: fonts)
        if let relative = ODFValue.percent(node["text:bullet-relative-size"]), relative > 0, text.fontSize == nil {
            text.relativeFontSize = min(relative, 40)
        }
    }

    func write(level: Int, to xml: inout XMLWriter) {
        let tag: String
        switch label {
        case .bullet(let character):
            tag = "text:list-level-style-bullet"
            xml.raw("<\(tag) text:level=\"\(level + 1)\"")
            xml.attribute("text:bullet-char", String(character.prefix(1)).isEmpty ? "•" : String(character.prefix(1)))
            if let relative = text.relativeFontSize { xml.raw(" text:bullet-relative-size=\"\(ODFFormat.percent(min(max(relative, 0.01), 40)))\"") }
        case .number(let format, let prefix, let suffix, let start):
            tag = "text:list-level-style-number"
            xml.raw("<\(tag) text:level=\"\(level + 1)\"")
            if !prefix.isEmpty { xml.attribute("style:num-prefix", prefix) }
            if !suffix.isEmpty { xml.attribute("style:num-suffix", suffix) }
            xml.attribute("style:num-format", format)
            if start != 1 { xml.attribute("text:start-value", min(max(start, 1), 32_767)) }
        case .image:
            tag = "text:list-level-style-number"
            xml.raw("<\(tag) text:level=\"\(level + 1)\" style:num-format=\"\"")
        }
        xml.raw("><style:list-level-properties")
        if let spaceBefore { xml.raw(" text:space-before=\"\(ODFFormat.pt(spaceBefore))\"") }
        if let minLabelWidth { xml.raw(" text:min-label-width=\"\(ODFFormat.pt(max(0, minLabelWidth)))\"") }
        xml.raw("/>")
        var properties = text
        if case .bullet = label { properties.relativeFontSize = nil }
        if !properties.isEmpty {
            xml.raw("<style:text-properties")
            properties.write(to: &xml)
            xml.raw("/>")
        }
        xml.raw("</\(tag)>")
    }
}

/// A list style's levels, by level 0...9.
typealias ODFListStyle = [Int: ODFListLevel]

enum ODFLists {
    static func parse(_ node: ODFNode?, fonts: [String: String]) -> ODFListStyle? {
        guard let node else { return nil }
        var levels: ODFListStyle = [:]
        for child in node.elements {
            guard let level = ODFValue.int(child["text:level"]), (1...10).contains(level), let style = ODFListLevel(child, fonts: fonts) else { continue }
            levels[level - 1] = style
        }
        return levels
    }

    /// The `style:num-format`, prefix and suffix of a numbering scheme.
    static func format(_ scheme: AutoNumberScheme) -> (format: String, prefix: String, suffix: String) {
        let name = scheme.rawValue
        let format = name.hasPrefix("alphaLc") ? "a" : name.hasPrefix("alphaUc") ? "A" : name.hasPrefix("romanLc") ? "i" : name.hasPrefix("romanUc") ? "I" : "1"
        if name.hasSuffix("ParenBoth") { return (format, "(", ")") }
        if name.hasSuffix("ParenR") { return (format, "", ")") }
        if name.hasSuffix("Plain") { return (format, "", "") }
        return (format, "", ".")
    }

    /// The numbering scheme of an ODF number format; nil when it numbers nothing.
    static func scheme(format: String, prefix: String, suffix: String) -> AutoNumberScheme? {
        let family: String
        switch format.first {
        case "a": family = "alphaLc"
        case "A": family = "alphaUc"
        case "i": family = "romanLc"
        case "I": family = "romanUc"
        case "1": family = "arabic"
        default: return nil
        }
        let close = suffix.trimmingCharacters(in: .whitespaces)
        let punctuation = prefix.hasSuffix("(") && close.hasPrefix(")") ? "ParenBoth" : close.hasPrefix(")") ? "ParenR"
            : (close.isEmpty && family == "arabic") ? "Plain" : "Period"
        return AutoNumberScheme(rawValue: family + punctuation) ?? .arabicPeriod
    }
}

// MARK: - Styles

/// One `style:style` or `style:default-style`.
struct ODFStyle {
    var family: String
    var parent: String?
    var graphic = ODFGraphicProperties()
    var paragraph = ODFParagraphProperties()
    var text = ODFTextProperties()
    /// A `text:list-style` inside the graphic properties (presentation outline styles have one).
    var listStyle: ODFListStyle?
    var page = ODFPageProperties()
    /// A table cell's fill, borders, padding and alignment.
    var cell = ODFCellProperties()
    /// A table column's width and a table row's height (`style:row-height`, or `style:min-row-height`).
    var columnWidth: Double?
    var rowHeight: Double?

    init(family: String, parent: String? = nil) {
        self.family = family
        self.parent = parent
    }

    init(_ node: ODFNode, fonts: [String: String]) {
        family = node["style:family"] ?? ""
        parent = node["style:parent-style-name"]
        let graphicNode = node.child("style:graphic-properties")
        graphic = ODFGraphicProperties(graphicNode)
        listStyle = ODFLists.parse(graphicNode?.child("text:list-style"), fonts: fonts)
        paragraph = ODFParagraphProperties(node.child("style:paragraph-properties"))
        text = ODFTextProperties(node.child("style:text-properties"), fonts: fonts)
        page = ODFPageProperties(node.child("style:drawing-page-properties"))
        if family == "table-cell" || node.child("style:table-cell-properties") != nil { cell = ODFCellProperties(style: node, family: family) }
        if let column = node.child("style:table-column-properties") {
            columnWidth = ODFValue.length(column["style:column-width"]).flatMap { $0 > 0 ? min($0, 100_000) : nil }
        }
        if let row = node.child("style:table-row-properties") {
            rowHeight = (ODFValue.length(row["style:row-height"]) ?? ODFValue.length(row["style:min-row-height"])).flatMap { $0 > 0 ? min($0, 100_000) : nil }
        }
    }

    /// This style over its parent: everything this one leaves unset comes from `base`.
    func merged(over base: ODFStyle) -> ODFStyle {
        var result = self
        result.graphic = graphic.merged(over: base.graphic)
        result.paragraph = paragraph.merged(over: base.paragraph)
        result.text = text.merged(over: base.text)
        result.listStyle = listStyle ?? base.listStyle
        result.page = page.merged(over: base.page)
        result.cell = cell.merged(over: base.cell)
        result.columnWidth = columnWidth ?? base.columnWidth
        result.rowHeight = rowHeight ?? base.rowHeight
        return result
    }

    /// The properties elements, in schema order. `name` names a list style inside the graphic properties.
    func writeBody(name: String, to xml: inout XMLWriter) {
        switch family {
        case "drawing-page":
            xml.raw("<style:drawing-page-properties")
            page.write(to: &xml)
            xml.raw("/>")
            return
        case "table-column":
            if let columnWidth { xml.raw("<style:table-column-properties style:column-width=\"\(ODFFormat.pt(min(max(columnWidth, 0.01), 100_000)))\"/>") }
            return
        case "table-row":
            if let rowHeight { xml.raw("<style:table-row-properties style:row-height=\"\(ODFFormat.pt(min(max(rowHeight, 0.01), 100_000)))\"/>") }
            return
        case "table-cell":
            if !cell.isEmpty { cell.write(to: &xml) }
        case "graphic", "presentation":
            if !graphic.isEmpty || listStyle != nil {
                xml.raw("<style:graphic-properties")
                graphic.write(to: &xml)
                if let listStyle, !listStyle.isEmpty {
                    xml.raw("><text:list-style")
                    xml.attribute("style:name", name)
                    xml.raw(">")
                    for level in listStyle.keys.sorted() { listStyle[level]?.write(level: level, to: &xml) }
                    xml.raw("</text:list-style></style:graphic-properties>")
                } else {
                    xml.raw("/>")
                }
            }
        default:
            break
        }
        if family != "text", !paragraph.isEmpty {
            xml.raw("<style:paragraph-properties")
            paragraph.write(to: &xml)
            xml.raw("/>")
        }
        if !text.isEmpty {
            xml.raw("<style:text-properties")
            text.write(to: &xml)
            xml.raw("/>")
        }
    }
}

/// A linear, axial or radial ODF gradient.
struct ODFGradient: Hashable {
    var style: String
    var start: RGBColor
    var end: RGBColor
    /// Degrees counterclockwise; 0 runs from top to bottom.
    var angle: Double = 0
    /// The share of the gradient that stays in the start color.
    var border: Double = 0
    var centerX: Double = 0.5
    var centerY: Double = 0.5

    init(style: String, start: RGBColor, end: RGBColor, angle: Double = 0, border: Double = 0) {
        self.style = style
        self.start = start
        self.end = end
        self.angle = angle
        self.border = border
    }

    init(_ node: ODFNode) {
        style = node["draw:style"] ?? "linear"
        func color(_ name: String, _ intensity: String) -> RGBColor {
            let base = ODFValue.color(node[name]) ?? .black
            let amount = min(max(ODFValue.percent(node[intensity]) ?? 1, 0), 1)
            guard amount < 1 else { return base }
            return RGBColor(unitRed: Double(base.red) / 255 * amount, unitGreen: Double(base.green) / 255 * amount, unitBlue: Double(base.blue) / 255 * amount)
        }
        start = color("draw:start-color", "draw:start-intensity")
        end = color("draw:end-color", "draw:end-intensity")
        // LibreOffice wrote bare numbers in tenths of a degree.
        angle = ODFValue.angle(node["draw:angle"], unitless: 0.1) ?? 0
        border = min(max(ODFValue.percent(node["draw:border"]) ?? 0, 0), 1)
        centerX = min(max(ODFValue.percent(node["draw:cx"]) ?? 0.5, 0), 1)
        centerY = min(max(ODFValue.percent(node["draw:cy"]) ?? 0.5, 0), 1)
    }

    func write(name: String, displayName: String, to xml: inout XMLWriter) {
        xml.raw("<draw:gradient")
        xml.attribute("draw:name", name)
        xml.attribute("draw:display-name", displayName)
        xml.raw(" draw:style=\"\(style)\"")
        if style != "linear" && style != "axial" {
            xml.raw(" draw:cx=\"\(ODFFormat.percent(centerX))\" draw:cy=\"\(ODFFormat.percent(centerY))\"")
        }
        xml.raw(" draw:start-color=\"\(ODFFormat.color(start))\" draw:end-color=\"\(ODFFormat.color(end))\"")
        xml.raw(" draw:start-intensity=\"100%\" draw:end-intensity=\"100%\"")
        xml.raw(" draw:angle=\"\(ODFFormat.number(Placement.normalized(angle), decimals: 1))deg\" draw:border=\"\(ODFFormat.percent(border))\"/>")
    }
}

/// A line-end marker: a path in its own box.
struct ODFMarker: Hashable {
    var viewBox: String
    var path: String
}

/// A dash pattern, with lengths as multiples of the line width.
struct ODFDash: Hashable {
    var dots1: Int
    var dots1Length: Double
    var dots2: Int
    var dots2Length: Double
    var distance: Double

    init(dots1: Int, dots1Length: Double, dots2: Int = 0, dots2Length: Double = 0, distance: Double) {
        self.dots1 = dots1
        self.dots1Length = dots1Length
        self.dots2 = dots2
        self.dots2Length = dots2Length
        self.distance = distance
    }

    /// Whether the lengths are absolute (points) rather than multiples of the line width.
    var isAbsolute = false

    /// Lengths are percentages of the line width, or absolute.
    init(_ node: ODFNode) {
        var absolute = false
        func length(_ name: String) -> Double {
            if let percent = ODFValue.percent(node[name]) { return max(0, percent) }
            if node[name] != nil { absolute = true }
            return max(0, ODFValue.length(node[name]) ?? 0)
        }
        dots1 = max(0, ODFValue.int(node["draw:dots1"]) ?? 1)
        dots1Length = length("draw:dots1-length")
        dots2 = max(0, ODFValue.int(node["draw:dots2"]) ?? 0)
        dots2Length = length("draw:dots2-length")
        distance = length("draw:distance")
        isAbsolute = absolute
    }

    func write(name: String, displayName: String, to xml: inout XMLWriter) {
        xml.raw("<draw:stroke-dash")
        xml.attribute("draw:name", name)
        xml.attribute("draw:display-name", displayName)
        xml.raw(" draw:style=\"rect\" draw:dots1=\"\(dots1)\" draw:dots1-length=\"\(ODFFormat.percent(dots1Length))\"")
        if dots2 > 0 { xml.raw(" draw:dots2=\"\(dots2)\" draw:dots2-length=\"\(ODFFormat.percent(dots2Length))\"") }
        xml.raw(" draw:distance=\"\(ODFFormat.percent(distance))\"/>")
    }
}

/// A `style:presentation-page-layout`: a named set of placeholder areas.
struct ODFPageLayout {
    var name: String
    var displayName: String
    var placeholders: [(object: String, frame: SlideRect)]
}

/// Every style of a part, and the shared resources of styles.xml. Automatic styles in content.xml see the common styles
/// of styles.xml through `fallback`.
final class ODFStyleSheet {
    let fallback: ODFStyleSheet?
    var styles: [String: ODFStyle] = [:]
    var defaults: [String: ODFStyle] = [:]
    var listStyles: [String: ODFListStyle] = [:]
    var gradients: [String: ODFGradient] = [:]
    var fillImages: [String: String] = [:]
    var hatchColors: [String: RGBColor] = [:]
    var markers: [String: (marker: ODFMarker, name: String)] = [:]
    var dashes: [String: (dash: ODFDash, name: String)] = [:]
    var pageSizes: [String: SlideSize] = [:]
    var pageLayouts: [ODFPageLayout] = []
    var fonts: [String: String] = [:]
    /// Table designs (`table:table-template`) by name: the cell style each part of a table takes ("first-row", "body",
    /// "odd-rows" …).
    var tableTemplates: [String: [String: String]] = [:]
    private var resolvedCache: [String: ODFStyle] = [:]

    init(fallback: ODFStyleSheet? = nil) {
        self.fallback = fallback
        if let fallback { fonts = fallback.fonts }
    }

    static func key(_ family: String, _ name: String) -> String {
        // Presentation and graphic styles behave alike and LibreOffice mixes their references.
        (family == "presentation" ? "graphic" : family) + ":" + name
    }

    func add(_ style: ODFStyle, name: String) {
        styles[Self.key(style.family, name)] = style
        resolvedCache.removeAll()
    }

    func style(_ family: String, _ name: String) -> ODFStyle? {
        styles[Self.key(family, name)] ?? fallback?.style(family, name)
    }

    func defaultStyle(_ family: String) -> ODFStyle? {
        let key = family == "presentation" ? "graphic" : family
        return defaults[key] ?? fallback?.defaultStyle(family)
    }

    func listStyle(_ name: String) -> ODFListStyle? {
        listStyles[name] ?? fallback?.listStyles[name]
    }

    /// A style merged with its parents and the family's default style. Unknown names give the default style.
    func resolved(_ family: String, _ name: String?) -> ODFStyle {
        let cacheKey = Self.key(family, name ?? "")
        if let cached = resolvedCache[cacheKey] { return cached }
        var result = ODFStyle(family: family)
        var current = name
        var seen = Set<String>()
        while let styleName = current, seen.count < 32, seen.insert(styleName).inserted, let style = style(family, styleName) {
            result = result.merged(over: style)
            current = style.parent
        }
        if let base = defaultStyle(family) { result = result.merged(over: base) }
        resolvedCache[cacheKey] = result
        return result
    }

    /// A style merged with its parents but not the family's default style, for styles that stack on others (a table
    /// cell's own style over the style its table design gives it).
    func chained(_ family: String, _ name: String?) -> ODFStyle {
        var result = ODFStyle(family: family)
        var current = name
        var seen = Set<String>()
        while let styleName = current, seen.count < 32, seen.insert(styleName).inserted, let style = style(family, styleName) {
            result = result.merged(over: style)
            current = style.parent
        }
        return result
    }

    /// A table design by the name a table gives, as written or with its "_20_"-style escapes undone.
    func tableTemplate(_ name: String) -> [String: String]? {
        if let template = tableTemplates[name] ?? fallback?.tableTemplates[name] { return template }
        let decoded = ODFFormat.decodedStyleName(name)
        let all = (fallback?.tableTemplates ?? [:]).merging(tableTemplates) { $1 }
        return all.first { ODFFormat.decodedStyleName($0.key) == decoded }?.value
    }

    // MARK: Reading

    /// Reads `office:font-face-decls`.
    func readFonts(_ node: ODFNode?) {
        for face in node?.children("style:font-face") ?? [] {
            guard let name = face["style:name"] else { continue }
            fonts[name] = face["svg:font-family"].flatMap(ODFTextProperties.firstFamily) ?? name
        }
    }

    /// Reads `office:styles` or `office:automatic-styles`.
    func read(_ node: ODFNode?) {
        guard let node else { return }
        for child in node.elements {
            switch child.name {
            case "style:style":
                guard let name = child["style:name"] else { continue }
                add(ODFStyle(child, fonts: fonts), name: name)
            case "style:default-style":
                let style = ODFStyle(child, fonts: fonts)
                defaults[style.family == "presentation" ? "graphic" : style.family] = style
            case "text:list-style":
                if let name = child["style:name"] { listStyles[name] = ODFLists.parse(child, fonts: fonts) ?? [:] }
            case "draw:gradient":
                if let name = child["draw:name"] { gradients[name] = ODFGradient(child) }
            case "draw:fill-image":
                if let name = child["draw:name"], let href = child["xlink:href"] { fillImages[name] = href }
            case "draw:hatch":
                if let name = child["draw:name"] { hatchColors[name] = ODFValue.color(child["draw:color"]) ?? .black }
            case "draw:marker":
                if let name = child["draw:name"] {
                    markers[name] = (ODFMarker(viewBox: child["svg:viewBox"] ?? "", path: child["svg:d"] ?? ""),
                                     child["draw:display-name"] ?? ODFFormat.decodedStyleName(name))
                }
            case "draw:stroke-dash":
                if let name = child["draw:name"] { dashes[name] = (ODFDash(child), child["draw:display-name"] ?? ODFFormat.decodedStyleName(name)) }
            case "style:page-layout":
                if let name = child["style:name"], let properties = child.child("style:page-layout-properties"),
                   let width = ODFValue.length(properties["fo:page-width"]), let height = ODFValue.length(properties["fo:page-height"]),
                   width > 0, height > 0 {
                    pageSizes[name] = SlideSize(width: width, height: height)
                }
            case "style:presentation-page-layout":
                guard let name = child["style:name"] else { continue }
                var placeholders: [(String, SlideRect)] = []
                for placeholder in child.children("presentation:placeholder") {
                    guard let object = placeholder["presentation:object"] else { continue }
                    let frame = SlideRect(x: ODFValue.length(placeholder["svg:x"]) ?? 0, y: ODFValue.length(placeholder["svg:y"]) ?? 0,
                                          width: max(0, ODFValue.length(placeholder["svg:width"]) ?? 0),
                                          height: max(0, ODFValue.length(placeholder["svg:height"]) ?? 0))
                    placeholders.append((object, frame))
                }
                pageLayouts.append(ODFPageLayout(name: name, displayName: child["style:display-name"] ?? ODFFormat.decodedStyleName(name),
                                                 placeholders: placeholders))
            case "table:table-template":
                // ODF 1.3 names designs with table:name; LibreOffice before 5.3 used text:style-name.
                guard let name = child["table:name"] ?? child["text:style-name"] else { continue }
                var parts: [String: String] = [:]
                for part in child.elements {
                    guard part.name.hasPrefix("table:"), let style = part["table:style-name"] else { continue }
                    parts[String(part.name.dropFirst("table:".count))] = style
                }
                tableTemplates[name] = parts
            default:
                continue
            }
        }
        resolvedCache.removeAll()
    }
}

// MARK: - Resolved values

/// Character formatting with every property known: what a run looks like. Comparing these decides what a file
/// states explicitly (writing) and what a model element states explicitly (reading).
struct ODFTextValues: Equatable {
    var fontFamily: String
    var fontSize: Double
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var color: RGBColor
    var highlight: RGBColor?
    var baseline: BaselineShift

    /// What applications assume when no style says otherwise.
    static let fallback = ODFTextValues(fontFamily: "Liberation Sans", fontSize: 18, bold: false, italic: false, underline: false,
                                        strikethrough: false, color: .black, highlight: nil, baseline: .normal)

    init(fontFamily: String, fontSize: Double, bold: Bool, italic: Bool, underline: Bool, strikethrough: Bool, color: RGBColor,
         highlight: RGBColor?, baseline: BaselineShift) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.color = color
        self.highlight = highlight
        self.baseline = baseline
    }

    init(_ resolved: ResolvedCharacterStyle) {
        self.init(fontFamily: resolved.fontFamily, fontSize: resolved.fontSize, bold: resolved.bold, italic: resolved.italic,
                  underline: resolved.underline, strikethrough: resolved.strikethrough, color: resolved.color.rgb,
                  highlight: resolved.highlight?.rgb, baseline: resolved.baseline)
    }

    /// ODF properties applied over these values.
    func applying(_ properties: ODFTextProperties) -> ODFTextValues {
        var result = self
        if let family = properties.fontFamily { result.fontFamily = family }
        if let size = properties.fontSize { result.fontSize = size } else if let relative = properties.relativeFontSize { result.fontSize = fontSize * relative }
        if let bold = properties.bold { result.bold = bold }
        if let italic = properties.italic { result.italic = italic }
        if let underline = properties.underline { result.underline = underline }
        if let strikethrough = properties.strikethrough { result.strikethrough = strikethrough }
        if let color = properties.color { result.color = color }
        switch properties.highlight {
        case .none?: result.highlight = nil
        case .color(let color)?: result.highlight = color
        case nil: break
        }
        if let baseline = properties.baseline { result.baseline = baseline }
        return result
    }

    /// The properties that turn `base` into these values.
    func difference(from base: ODFTextValues) -> ODFTextProperties {
        var result = ODFTextProperties()
        if fontFamily != base.fontFamily { result.fontFamily = fontFamily }
        if !ODFCompare.same(fontSize, base.fontSize) { result.fontSize = fontSize }
        if bold != base.bold { result.bold = bold }
        if italic != base.italic { result.italic = italic }
        if underline != base.underline { result.underline = underline }
        if strikethrough != base.strikethrough { result.strikethrough = strikethrough }
        if color != base.color { result.color = color }
        if highlight != base.highlight { result.highlight = highlight.map { .color($0) } ?? ODFHighlight.none }
        if baseline != base.baseline { result.baseline = baseline }
        return result
    }
}

/// Paragraph formatting with every property known.
struct ODFParagraphValues: Equatable {
    var alignment: TextAlignment
    var lineSpacing: Double
    var spaceBefore: Double
    var spaceAfter: Double
    var marginLeft: Double
    var indent: Double

    static let fallback = ODFParagraphValues(alignment: .left, lineSpacing: 1, spaceBefore: 0, spaceAfter: 0, marginLeft: 0, indent: 0)

    func applying(_ properties: ODFParagraphProperties, fontSize: Double) -> ODFParagraphValues {
        var result = self
        if let alignment = properties.alignment { result.alignment = alignment }
        if let spacing = properties.lineSpacing {
            result.lineSpacing = spacing
        } else if let height = properties.lineHeight {
            result.lineSpacing = fontSize > 0 ? min(max(height / (1.2 * fontSize), 0), 132) : 1
        }
        if let before = properties.spaceBefore { result.spaceBefore = before }
        if let after = properties.spaceAfter { result.spaceAfter = after }
        if let margin = properties.marginLeft { result.marginLeft = margin }
        if let indent = properties.indent { result.indent = indent }
        return result
    }

    func difference(from base: ODFParagraphValues) -> ODFParagraphProperties {
        var result = ODFParagraphProperties()
        if alignment != base.alignment { result.alignment = alignment }
        if !ODFCompare.same(lineSpacing, base.lineSpacing) { result.lineSpacing = lineSpacing }
        if !ODFCompare.same(spaceBefore, base.spaceBefore) { result.spaceBefore = spaceBefore }
        if !ODFCompare.same(spaceAfter, base.spaceAfter) { result.spaceAfter = spaceAfter }
        if !ODFCompare.same(marginLeft, base.marginLeft) { result.marginLeft = marginLeft }
        if !ODFCompare.same(indent, base.indent) { result.indent = indent }
        return result
    }
}

/// A paragraph's label: none, a character or a numbering scheme, with its font, color and size when they're its own.
struct ODFBulletValues: Equatable {
    var bullet: Bullet
    var font: String?
    var color: RGBColor?
    var size: Double?

    static let none = ODFBulletValues(bullet: Bullet.none, font: nil, color: nil, size: nil)

    static func == (lhs: ODFBulletValues, rhs: ODFBulletValues) -> Bool {
        guard lhs.bullet == rhs.bullet else { return false }
        if case .none = lhs.bullet { return true }
        return lhs.font == rhs.font && lhs.color == rhs.color && ODFCompare.same(lhs.size ?? 1, rhs.size ?? 1)
    }

    /// The list level that shows this label.
    func level(margins: (left: Double, indent: Double)) -> ODFListLevel {
        var text = ODFTextProperties()
        text.fontFamily = font
        text.color = color
        if color == nil { text.usesTextColor = true }
        if let size, !ODFCompare.same(size, 1) { text.relativeFontSize = size }
        let label: ODFListLevel.Label
        switch bullet {
        case .none:
            label = .number(format: "", prefix: "", suffix: "", start: 1)
        case .character(let character):
            label = .bullet(character.isEmpty ? "•" : character)
        case .number(let scheme, let start):
            let format = ODFLists.format(scheme)
            label = .number(format: format.format, prefix: format.prefix, suffix: format.suffix, start: start)
        }
        let labelWidth = max(0, -margins.indent)
        return ODFListLevel(label: label, spaceBefore: margins.left - labelWidth, minLabelWidth: labelWidth, text: text)
    }

    /// The label a list level shows.
    init(_ level: ODFListLevel?) {
        guard let level else {
            self = .none
            return
        }
        switch level.label {
        case .bullet(let character):
            bullet = .character(character)
        case .number(let format, let prefix, let suffix, let start):
            if let scheme = ODFLists.scheme(format: format, prefix: prefix, suffix: suffix) {
                bullet = .number(scheme, startAt: start)
            } else {
                bullet = Bullet.none
            }
        case .image:
            bullet = .character("•")
        }
        font = level.text.fontFamily
        color = level.text.usesTextColor == true ? nil : level.text.color
        size = level.text.relativeFontSize
    }

    init(bullet: Bullet, font: String?, color: RGBColor?, size: Double?) {
        self.bullet = bullet
        self.font = font
        self.color = color
        self.size = size
    }
}

enum ODFCompare {
    /// Lengths and sizes are written to four decimals; anything closer than that is the same.
    static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0005 }

    static func same(_ a: SlideRect, _ b: SlideRect) -> Bool {
        abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }
}
