import Foundation

/// Reads DrawingML text: bodies, list styles, paragraphs and runs. Only what the file states is kept;
/// everything else stays nil and inherits.
struct PPTXTextReader {
    var colors: PPTXColorReader
    /// Turns an `hlinkClick` into a link, through the part's relationships.
    var link: (XNode) -> Hyperlink?

    /// Font size assumed when spacing or bullet sizes are given in points and the text's own size isn't known.
    static let assumedFontSize = 18.0

    func body(_ node: XNode) -> TextBody {
        let properties = bodyProperties(node.child("bodyPr"))
        let listStyle = node.child("lstStyle").map(listStyle) ?? .empty
        let paragraphs = node.children("p").map(paragraph)
        return TextBody(paragraphs: paragraphs.isEmpty ? [TextParagraph()] : paragraphs, properties: properties, listStyle: listStyle)
    }

    // MARK: Body properties

    func bodyProperties(_ node: XNode?) -> TextBodyProperties {
        guard let node else { return .empty }
        var properties = TextBodyProperties()
        switch node["anchor"] {
        case "t", "just", "dist": properties.anchor = .top
        case "ctr": properties.anchor = .middle
        case "b": properties.anchor = .bottom
        default: break
        }
        let insets = ["lIns", "tIns", "rIns", "bIns"].map { PPTXValue.points(node[$0]) }
        if insets.contains(where: { $0 != nil }) {
            // Sides the file leaves out keep DrawingML's defaults.
            let defaults = TextInsets.office
            properties.insets = TextInsets(left: insets[0] ?? defaults.left, top: insets[1] ?? defaults.top,
                                           right: insets[2] ?? defaults.right, bottom: insets[3] ?? defaults.bottom)
        }
        switch node["wrap"] {
        case "none": properties.wraps = false
        case "square": properties.wraps = true
        default: break
        }
        if node.child("noAutofit") != nil {
            properties.autofit = Autofit.none
        } else if let fit = node.child("normAutofit") {
            properties.autofit = .shrinkOnOverflow
            properties.fontScale = PPTXValue.fraction(fit["fontScale"]).map { min(max($0, 0.01), 1) }
            properties.lineSpacingReduction = PPTXValue.fraction(fit["lnSpcReduction"]).map { min(max($0, 0), 1) }
        } else if node.child("spAutoFit") != nil {
            properties.autofit = .resizeShape
        }
        return properties
    }

    // MARK: List styles

    func listStyle(_ node: XNode) -> ListStyle {
        let base = node.child("defPPr").map { levelStyle($0) }
        var levels: [Int: LevelStyle] = [:]
        for level in 0...8 {
            let own = node.child("lvl\(level + 1)pPr").map { levelStyle($0) }
            switch (own, base) {
            case let (own?, base?): levels[level] = own.merged(over: base)
            case let (own?, nil): levels[level] = own
            case let (nil, base?): levels[level] = base
            case (nil, nil): continue
            }
        }
        return ListStyle(levels: levels)
    }

    /// One `lvlNpPr` (or `defPPr`): paragraph properties with default run properties.
    func levelStyle(_ node: XNode) -> LevelStyle {
        let character = characterStyle(node.child("defRPr"))
        return LevelStyle(paragraph: paragraphStyle(node, fontSize: character.fontSize), character: character)
    }

    // MARK: Paragraphs

    func paragraph(_ node: XNode) -> TextParagraph {
        var runs: [TextRun] = []
        for child in node.children {
            switch child.name {
            case "r":
                let text = Self.runText(child.child("t")?.text ?? "")
                guard !text.isEmpty else { continue }
                runs.append(TextRun(text, style: characterStyle(child.child("rPr"))))
            case "br":
                runs.append(TextRun(TextRun.lineBreak, style: characterStyle(child.child("rPr"))))
            case "fld":
                let text = Self.runText(child.child("t")?.text ?? "")
                let style = characterStyle(child.child("rPr"))
                if let type = child["type"], !type.isEmpty {
                    runs.append(TextRun(text, style: style, field: TextFieldKind(typeName: type)))
                } else if !text.isEmpty {
                    runs.append(TextRun(text, style: style))
                }
            default:
                continue
            }
        }
        let endStyle = characterStyle(node.child("endParaRPr"))
        let pPr = node.child("pPr")
        let fontSize = runs.lazy.compactMap(\.style.fontSize).first ?? endStyle.fontSize
        return TextParagraph(runs: Self.merged(runs), level: PPTXValue.int(pPr?["lvl"]) ?? 0, style: paragraphStyle(pPr, fontSize: fontSize),
                             endStyle: endStyle)
    }

    /// Line feeds inside a run are line breaks; carriage returns go.
    static func runText(_ text: String) -> String {
        guard text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{0B}" || $0 == "\r\n" }) else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0B}", with: "\n").replacingOccurrences(of: "\n", with: TextRun.lineBreak)
    }

    /// Joins neighboring runs with the same style (line breaks included), as the model keeps them.
    static func merged(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        result.reserveCapacity(runs.count)
        for run in runs {
            if run.field == nil, let last = result.last, last.field == nil, last.style == run.style {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }

    func paragraphStyle(_ node: XNode?, fontSize: Double?) -> ParagraphStyle {
        guard let node else { return .empty }
        var style = ParagraphStyle()
        switch node["algn"] {
        case "l": style.alignment = .left
        case "ctr": style.alignment = .center
        case "r": style.alignment = .right
        case "just", "justLow", "dist", "thaiDist": style.alignment = .justified
        default: break
        }
        style.marginLeft = PPTXValue.points(node["marL"])
        style.indent = PPTXValue.points(node["indent"])
        let size = fontSize ?? Self.assumedFontSize
        if let spacing = node.child("lnSpc") {
            if let percent = PPTXValue.fraction(spacing.child("spcPct")?["val"]) {
                style.lineSpacing = max(0, percent)
            } else if let points = PPTXValue.centipoints(spacing.child("spcPts")?["val"]), size > 0 {
                // Exact spacing, as a multiple of single spacing (1.2 × the font size).
                style.lineSpacing = max(0, points / (1.2 * size))
            }
        }
        style.spaceBefore = spacing(node.child("spcBef"), fontSize: size)
        style.spaceAfter = spacing(node.child("spcAft"), fontSize: size)

        if let color = node.child("buClr") { style.bulletColor = colors.color(in: color) }
        if let percent = PPTXValue.fraction(node.child("buSzPct")?["val"]) {
            style.bulletSize = min(max(percent, 0.25), 4)
        } else if let points = PPTXValue.centipoints(node.child("buSzPts")?["val"]), let fontSize, fontSize > 0 {
            style.bulletSize = min(max(points / fontSize, 0.25), 4)
        }
        if let font = node.child("buFont")?["typeface"], !font.isEmpty { style.bulletFont = font }

        if node.child("buNone") != nil {
            style.bullet = Bullet.none
        } else if let number = node.child("buAutoNum") {
            let start = min(max(PPTXValue.int(number["startAt"]) ?? 1, 1), 32_767)
            style.bullet = .number(Self.numberScheme(number["type"] ?? ""), startAt: start)
        } else if let character = node.child("buChar") {
            let text = character["char"] ?? ""
            style.bullet = text.isEmpty ? Bullet.none : .character(text)
        } else if node.child("buBlip") != nil {
            style.bullet = .character("•")
        }
        return style
    }

    /// Space before or after, in points: `spcPts` is hundredths of a point; `spcPct` is a share of a line.
    private func spacing(_ node: XNode?, fontSize: Double) -> Double? {
        guard let node else { return nil }
        if let points = PPTXValue.centipoints(node.child("spcPts")?["val"]) { return max(0, points) }
        if let percent = PPTXValue.fraction(node.child("spcPct")?["val"]) { return max(0, percent * 1.2 * fontSize) }
        return nil
    }

    /// The model's numbering schemes cover the list presets; others map to the closest of them.
    static func numberScheme(_ type: String) -> AutoNumberScheme {
        if let scheme = AutoNumberScheme(rawValue: type) { return scheme }
        let family = type.hasPrefix("alphaLc") ? "alphaLc" : type.hasPrefix("alphaUc") ? "alphaUc"
            : type.hasPrefix("romanLc") ? "romanLc" : type.hasPrefix("romanUc") ? "romanUc" : "arabic"
        let punctuation = type.hasSuffix("ParenBoth") ? "ParenBoth" : type.hasSuffix("ParenR") ? "ParenR"
            : type.hasSuffix("Plain") && family == "arabic" ? "Plain" : "Period"
        return AutoNumberScheme(rawValue: family + punctuation) ?? .arabicPeriod
    }

    // MARK: Runs

    func characterStyle(_ node: XNode?) -> CharacterStyle {
        guard let node else { return .empty }
        var style = CharacterStyle()
        if let size = PPTXValue.centipoints(node["sz"]), size > 0 { style.fontSize = min(size, 4000) }
        style.bold = PPTXValue.bool(node["b"])
        style.italic = PPTXValue.bool(node["i"])
        if let underline = node["u"] { style.underline = underline != "none" }
        if let strike = node["strike"] { style.strikethrough = strike != "noStrike" }
        if let baseline = PPTXValue.double(node["baseline"]) {
            style.baseline = baseline > 0 ? .superscript : baseline < 0 ? .subscript : .normal
        }
        for child in node.children {
            switch child.name {
            case "solidFill":
                style.color = colors.color(in: child)
            case "gradFill":
                // Gradient text shows in its first color.
                style.color = child.child("gsLst")?.children("gs").first.flatMap { colors.color(in: $0) }
            case "highlight":
                style.highlight = colors.color(in: child)
            case "latin":
                if let face = child["typeface"], !face.isEmpty { style.fontFamily = face }
            case "hlinkClick":
                style.link = link(child)
            default:
                continue
            }
        }
        return style
    }
}
