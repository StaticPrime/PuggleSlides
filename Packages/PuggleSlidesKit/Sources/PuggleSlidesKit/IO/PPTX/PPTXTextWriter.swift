import Foundation

/// Writes DrawingML text. Only properties the model sets are written, in the schema's order, so everything
/// else keeps inheriting in other apps as it does in PuggleSlides.
extension PPTXPartWriter {
    mutating func textBody(_ body: TextBody, tag: String) {
        xml.raw("<\(tag)>")
        bodyProperties(body.properties)
        listStyle("a:lstStyle", body.listStyle)
        for paragraph in body.paragraphs { self.paragraph(paragraph) }
        xml.raw("</\(tag)>")
    }

    /// `bodyPr`: attributes in schema order (wrap, insets, anchor), then the children: word art's text warp and the
    /// autofit choice.
    mutating func bodyProperties(_ properties: TextBodyProperties) {
        let isWordArt = wordArtPaint != nil
        xml.raw("<a:bodyPr")
        if isWordArt {
            // Word art stretches each line across the shape, so its lines never wrap.
            xml.raw(" wrap=\"none\"")
        } else if let wraps = properties.wraps {
            xml.raw(wraps ? " wrap=\"square\"" : " wrap=\"none\"")
        }
        if let insets = properties.insets {
            let range = -2_147_483_648...2_147_483_647
            xml.attribute("lIns", PPTXValue.clamped(insets.left * EMU.perPoint, range))
            xml.attribute("tIns", PPTXValue.clamped(insets.top * EMU.perPoint, range))
            xml.attribute("rIns", PPTXValue.clamped(insets.right * EMU.perPoint, range))
            xml.attribute("bIns", PPTXValue.clamped(insets.bottom * EMU.perPoint, range))
        }
        if isWordArt { xml.raw(" fromWordArt=\"1\"") }
        switch properties.anchor {
        case .top?: xml.raw(" anchor=\"t\"")
        case .middle?: xml.raw(" anchor=\"ctr\"")
        case .bottom?: xml.raw(" anchor=\"b\"")
        case nil: break
        }
        guard isWordArt || properties.autofit != nil else {
            xml.raw("/>")
            return
        }
        xml.raw(">")
        // Plain text warp: the letters stretched to fill the shape, which is how word art is drawn.
        if isWordArt { xml.raw("<a:prstTxWarp prst=\"textPlain\"><a:avLst/></a:prstTxWarp>") }
        switch properties.autofit {
        case .none?:
            xml.raw("<a:noAutofit/>")
        case .shrinkOnOverflow?:
            xml.raw("<a:normAutofit")
            if let scale = properties.fontScale, scale != 1 {
                xml.attribute("fontScale", PPTXValue.clamped(scale * 100_000, 1_000...100_000))
            }
            if let reduction = properties.lineSpacingReduction, reduction != 0 {
                xml.attribute("lnSpcReduction", PPTXValue.clamped(reduction * 100_000, 0...100_000))
            }
            xml.raw("/>")
        case .resizeShape?:
            xml.raw("<a:spAutoFit/>")
        case nil:
            break
        }
        xml.raw("</a:bodyPr>")
    }

    /// Whether word art paint goes on runs being written: a word art shape with a fill or an outline.
    private var paintsRuns: Bool {
        guard let paint = wordArtPaint else { return false }
        return paint.fill != nil || paint.outline != nil
    }

    /// A list style: `a:lstStyle`, or a master's `p:titleStyle`, `p:bodyStyle`, `p:otherStyle` and so on.
    mutating func listStyle(_ tag: String, _ style: ListStyle) {
        let levels = (0...8).compactMap { level in style.levels[level].map { (level, $0) } }
        guard !levels.isEmpty else {
            xml.raw("<\(tag)/>")
            return
        }
        xml.raw("<\(tag)>")
        for (level, levelStyle) in levels {
            paragraphProperties("a:lvl\(level + 1)pPr", levelStyle.paragraph, level: 0, defaults: levelStyle.character)
        }
        xml.raw("</\(tag)>")
    }

    /// `pPr` or `lvlNpPr`. Attributes: marL, lvl, indent, algn. Children: lnSpc, spcBef, spcAft, buClr, buSzPct,
    /// buFont, the bullet, defRPr.
    mutating func paragraphProperties(_ tag: String, _ style: ParagraphStyle, level: Int, defaults: CharacterStyle?) {
        xml.raw("<\(tag)")
        if let margin = style.marginLeft { xml.attribute("marL", PPTXValue.clamped(margin * EMU.perPoint, 0...51_206_400)) }
        if level > 0 { xml.attribute("lvl", min(level, 8)) }
        if let indent = style.indent { xml.attribute("indent", PPTXValue.clamped(indent * EMU.perPoint, -51_206_400...51_206_400)) }
        switch style.alignment {
        case .left?: xml.raw(" algn=\"l\"")
        case .center?: xml.raw(" algn=\"ctr\"")
        case .right?: xml.raw(" algn=\"r\"")
        case .justified?: xml.raw(" algn=\"just\"")
        case nil: break
        }
        let bulletFont = style.bulletFont.flatMap { $0.isEmpty ? nil : $0 }
        let defaults = defaults.flatMap { $0.isEmpty ? nil : $0 }
        guard style.lineSpacing != nil || style.spaceBefore != nil || style.spaceAfter != nil || style.bulletColor != nil
            || style.bulletSize != nil || bulletFont != nil || style.bullet != nil || defaults != nil else {
            xml.raw("/>")
            return
        }
        xml.raw(">")
        if let spacing = style.lineSpacing {
            xml.raw("<a:lnSpc><a:spcPct val=\"\(PPTXValue.clamped(spacing * 100_000, 0...13_200_000))\"/></a:lnSpc>")
        }
        if let before = style.spaceBefore { xml.raw("<a:spcBef><a:spcPts val=\"\(PPTXValue.clamped(before * 100, 0...158_400))\"/></a:spcBef>") }
        if let after = style.spaceAfter { xml.raw("<a:spcAft><a:spcPts val=\"\(PPTXValue.clamped(after * 100, 0...158_400))\"/></a:spcAft>") }
        if let color = style.bulletColor {
            xml.raw("<a:buClr>")
            xml.color(color)
            xml.raw("</a:buClr>")
        }
        if let size = style.bulletSize { xml.raw("<a:buSzPct val=\"\(PPTXValue.clamped(size * 100_000, 25_000...400_000))\"/>") }
        if let bulletFont {
            xml.raw("<a:buFont")
            xml.attribute("typeface", bulletFont)
            xml.raw("/>")
        }
        switch style.bullet {
        case .none?:
            xml.raw("<a:buNone/>")
        case .character(let character)?:
            if character.isEmpty {
                xml.raw("<a:buNone/>")
            } else {
                xml.raw("<a:buChar")
                xml.attribute("char", character)
                xml.raw("/>")
            }
        case .number(let scheme, let start)?:
            xml.raw("<a:buAutoNum type=\"\(scheme.rawValue)\"")
            let start = min(max(start, 1), 32_767)
            if start != 1 { xml.attribute("startAt", start) }
            xml.raw("/>")
        case nil:
            break
        }
        if let defaults { characterProperties("a:defRPr", defaults) }
        xml.raw("</\(tag)>")
    }

    mutating func paragraph(_ paragraph: TextParagraph) {
        xml.raw("<a:p>")
        if paragraph.level > 0 || !paragraph.style.isEmpty {
            paragraphProperties("a:pPr", paragraph.style, level: paragraph.level, defaults: nil)
        }
        for run in paragraph.runs { self.run(run) }
        if !paragraph.endStyle.isEmpty || paintsRuns { characterProperties("a:endParaRPr", paragraph.endStyle) }
        xml.raw("</a:p>")
    }

    /// A run; line breaks inside it become `a:br` with the run's formatting. Fields become `a:fld`.
    mutating func run(_ run: TextRun) {
        if let field = run.field {
            xml.raw("<a:fld id=\"{\(UUID().uuidString)}\"")
            if !field.typeName.isEmpty { xml.attribute("type", field.typeName) }
            xml.raw(">")
            if !run.style.isEmpty || paintsRuns { characterProperties("a:rPr", run.style) }
            xml.raw("<a:t>")
            if field == .slideNumber, let slideNumber {
                xml.text(String(slideNumber))
            } else {
                xml.text(Self.lineBreaksNormalized(run.text).replacingOccurrences(of: TextRun.lineBreak, with: " "))
            }
            xml.raw("</a:t></a:fld>")
            return
        }
        let lines = Self.lineBreaksNormalized(run.text).components(separatedBy: TextRun.lineBreak)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                if run.style.isEmpty {
                    xml.raw("<a:br/>")
                } else {
                    xml.raw("<a:br>")
                    characterProperties("a:rPr", run.style)
                    xml.raw("</a:br>")
                }
            }
            guard !line.isEmpty else { continue }
            xml.raw("<a:r>")
            if !run.style.isEmpty || paintsRuns { characterProperties("a:rPr", run.style) }
            xml.raw("<a:t>")
            xml.text(line)
            xml.raw("</a:t></a:r>")
        }
    }

    /// Line feeds, carriage returns and vertical tabs inside a paragraph are line breaks.
    static func lineBreaksNormalized(_ text: String) -> String {
        guard text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" || $0 == "\u{0B}" }) else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0B}", with: "\n").replacingOccurrences(of: "\n", with: TextRun.lineBreak)
    }

    /// `rPr`, `defRPr` or `endParaRPr`. Attributes: sz, b, i, u, strike, baseline. Children: the outline (word art's),
    /// the fill, highlight, latin, hlinkClick.
    mutating func characterProperties(_ tag: String, _ style: CharacterStyle) {
        // Word art letters take the shape's fill and outline; list styles keep their own colors.
        let paint = tag == "a:rPr" || tag == "a:endParaRPr" ? wordArtPaint : nil
        xml.raw("<\(tag)")
        if let size = style.fontSize { xml.attribute("sz", PPTXValue.clamped(size * 100, 100...400_000)) }
        if let bold = style.bold { xml.raw(bold ? " b=\"1\"" : " b=\"0\"") }
        if let italic = style.italic { xml.raw(italic ? " i=\"1\"" : " i=\"0\"") }
        if let underline = style.underline { xml.raw(underline ? " u=\"sng\"" : " u=\"none\"") }
        if let strikethrough = style.strikethrough { xml.raw(strikethrough ? " strike=\"sngStrike\"" : " strike=\"noStrike\"") }
        switch style.baseline {
        case .superscript?: xml.raw(" baseline=\"30000\"")
        case .subscript?: xml.raw(" baseline=\"-25000\"")
        case .normal?: xml.raw(" baseline=\"0\"")
        case nil: break
        }
        let family = style.fontFamily.flatMap { $0.isEmpty ? nil : $0 }
        let link = style.link.flatMap { hyperlink($0) }
        let painted = paint.map { $0.fill != nil || $0.outline != nil } ?? false
        guard style.color != nil || style.highlight != nil || family != nil || link != nil || painted else {
            xml.raw("/>")
            return
        }
        xml.raw(">")
        if let paint {
            if let outline = paint.outline { line(outline) }
            if let fill = paint.fill {
                self.fill(fill)
            } else if let color = style.color {
                xml.solidFill(color)
            }
        } else if let color = style.color {
            xml.solidFill(color)
        }
        if let highlight = style.highlight {
            xml.raw("<a:highlight>")
            xml.color(highlight)
            xml.raw("</a:highlight>")
        }
        if let family {
            xml.raw("<a:latin")
            xml.attribute("typeface", family)
            xml.raw("/>")
        }
        if let link {
            xml.raw("<a:hlinkClick r:id=\"\(link.relationship)\"")
            if let action = link.action { xml.attribute("action", action) }
            xml.raw("/>")
        }
        xml.raw("</\(tag)>")
    }

    /// The relationship a link needs: an external one for addresses, one to the slide part for slide jumps.
    private mutating func hyperlink(_ link: Hyperlink) -> (relationship: String, action: String?)? {
        switch link {
        case .url(let address):
            let target = Self.uriTarget(address)
            guard !target.isEmpty else { return nil }
            let key = "url " + target
            if let known = linkRelationships[key] { return (known, nil) }
            let id = relationships.add(type: PPTXRelationshipType.hyperlink, target: target, isExternal: true)
            linkRelationships[key] = id
            return (id, nil)
        case .slide(let slideID):
            guard let slidePath = state.slidePaths[slideID] else { return nil }
            let key = "slide " + slidePath
            if let known = linkRelationships[key] { return (known, "ppaction://hlinksldjump") }
            let id = relationship(type: PPTXRelationshipType.slide, to: slidePath)
            linkRelationships[key] = id
            return (id, "ppaction://hlinksldjump")
        }
    }

    /// An address as a valid URI: Office refuses relationship targets with spaces and other stray characters,
    /// so those are percent-encoded (existing escapes are kept).
    static func uriTarget(_ address: String) -> String {
        let scalars = Array(address.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        func isHex(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isASCIIHexDigit }
        var result = ""
        for (index, scalar) in scalars.enumerated() {
            if scalar == "%" {
                let escaped = index + 2 < scalars.count && isHex(scalars[index + 1]) && isHex(scalars[index + 2])
                result += escaped ? "%" : "%25"
            } else if scalar.isASCII, uriCharacters.contains(UInt8(scalar.value)) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { result += String(format: "%%%02X", byte) }
            }
        }
        return result
    }

    private static let uriCharacters: Set<UInt8> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=".utf8)
}
