import AppKit
import PuggleSlidesKit

/// File ▸ Download ▸ Scalable Vector Graphics: one slide as SVG, with shapes as paths, pictures embedded and text
/// placed line by line where the slide shows it.
@MainActor
struct SVGExport {
    let presentation: Presentation
    let slide: Slide
    let slideNumber: Int
    private var defs: [String] = []
    private var body: [String] = []
    private var nextID = 0

    static func svg(for slide: Slide, number: Int, in presentation: Presentation) -> String {
        var export = SVGExport(presentation: presentation, slide: slide, slideNumber: number)
        return export.write()
    }

    private init(presentation: Presentation, slide: Slide, slideNumber: Int) {
        self.presentation = presentation
        self.slide = slide
        self.slideNumber = slideNumber
    }

    private mutating func write() -> String {
        let size = presentation.slideSize
        let theme = presentation.theme(for: slide)
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        body.append("<rect width=\"\(n(size.width))\" height=\"\(n(size.height))\" fill=\"#FFFFFF\"/>")
        let background = presentation.background(for: slide)
        if !background.isNone { fill(CGPath(rect: bounds, transform: nil), with: background, theme: theme, mode: .normal) }
        for (element, style) in presentation.backdropElements(for: slide) { write(element, style: style) }
        for element in slide.elements { write(element, style: presentation.style(for: element, on: slide)) }
        // A browser's 96 pixels per inch.
        let width = size.width * 96 / 72, height = size.height * 96 / 72
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="\(n(width))" height="\(n(height))" viewBox="0 0 \(n(size.width)) \(n(size.height))">
        <defs>\(defs.joined(separator: "\n"))</defs>
        \(body.joined(separator: "\n"))
        </svg>

        """
    }

    // MARK: Formatting

    private func n(_ value: CGFloat) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.3f", rounded).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    private func n(_ value: Double) -> String { n(CGFloat(value)) }

    private func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default:
                if scalar.value < 0x20, scalar != "\t" { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private func color(_ color: ResolvedColor) -> String {
        "#" + color.rgb.hex
    }

    private func matrix(_ transform: CGAffineTransform) -> String {
        "matrix(\(n(transform.a)) \(n(transform.b)) \(n(transform.c)) \(n(transform.d)) \(n(transform.tx)) \(n(transform.ty)))"
    }

    private mutating func newID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)\(nextID)"
    }

    /// SVG path data for a Core Graphics path.
    private func data(_ path: CGPath) -> String {
        var parts: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: parts.append("M\(n(points[0].x)) \(n(points[0].y))")
            case .addLineToPoint: parts.append("L\(n(points[0].x)) \(n(points[0].y))")
            case .addQuadCurveToPoint: parts.append("Q\(n(points[0].x)) \(n(points[0].y)) \(n(points[1].x)) \(n(points[1].y))")
            case .addCurveToPoint:
                parts.append("C\(n(points[0].x)) \(n(points[0].y)) \(n(points[1].x)) \(n(points[1].y)) \(n(points[2].x)) \(n(points[2].y))")
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: Elements

    private mutating func write(_ element: SlideElement, style: ElementStyle) {
        switch element.content {
        case .group(let children):
            for child in children {
                write(child, style: ElementStyle(element: child, parents: [], theme: style.theme, defaultTextStyle: style.defaultTextStyle))
            }
        case .shape(let shape) where shape.isWordArt:
            let placement = style.placement
            let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
            guard let path = WordArt.fittedPath(style.resolvedParagraphs(slideNumber: slideNumber), size: size) else { return }
            body.append("<g transform=\"\(matrix(placement.transform))\">")
            fill(path, with: style.fill, theme: style.theme, mode: .normal)
            stroke([ShapePath(path: path, fill: .none)], outline: style.outline, theme: style.theme, isLine: false)
            closeGroup()
        case .table(let table):
            write(table, style: style)
        case .chart(let chart):
            let placement = style.placement
            let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
            var markup = ChartRenderer.svg(chart, size: size)
            if markup.hasPrefix("<?xml"), let prolog = markup.range(of: "?>") { markup = String(markup[prolog.upperBound...]) }
            body.append("<g transform=\"\(matrix(placement.transform))\">")
            body.append(markup.trimmingCharacters(in: .whitespacesAndNewlines))
            body.append("</g>")
        case .media(let clip):
            // A video as its poster on a dark box; a sound as its speaker icon.
            let placement = style.placement
            let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
            let box = "x=\"0\" y=\"0\" width=\"\(n(size.width))\" height=\"\(n(size.height))\""
            body.append("<g transform=\"\(matrix(placement.transform))\">")
            if clip.isVideo {
                body.append("<rect \(box) fill=\"#141414\"/>")
                if let id = clip.posterID, let item = presentation.media[id] {
                    body.append("<image \(box) preserveAspectRatio=\"xMidYMid meet\" xlink:href=\"data:\(item.contentType);base64,\(item.data.base64EncodedString())\"/>")
                }
            } else if let png = MediaIcons.speakerPNG(side: max(size.width, size.height) * 2) {
                body.append("<image \(box) preserveAspectRatio=\"xMidYMid meet\" xlink:href=\"data:image/png;base64,\(png.base64EncodedString())\"/>")
            }
            body.append("</g>")
        case .shape(let shape):
            let placement = style.placement
            let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
            let parts = PresetGeometry.paths(for: style.geometry, in: CGRect(origin: .zero, size: size))
            body.append("<g transform=\"\(matrix(placement.transform))\">")
            if !style.geometry.isLine {
                for part in parts where part.fill != .none { fill(part.path, with: style.fill, theme: style.theme, mode: part.fill) }
            }
            stroke(parts, outline: style.outline, theme: style.theme, isLine: style.geometry.isLine)
            closeGroup()
            if shape.text != nil { text(of: element, style: style) }
        case .picture(let picture):
            let placement = style.placement
            let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
            let parts = PresetGeometry.paths(for: picture.geometry, in: CGRect(origin: .zero, size: size))
            let clip = newID("clip")
            defs.append("<clipPath id=\"\(clip)\"><path clip-rule=\"evenodd\" d=\"\(parts.map { data($0.path) }.joined(separator: " "))\"/></clipPath>")
            body.append("<g transform=\"\(matrix(placement.transform))\">")
            let crop = picture.crop
            let visibleWidth = max(0.01, 1 - crop.left - crop.right), visibleHeight = max(0.01, 1 - crop.top - crop.bottom)
            let full = CGRect(x: -crop.left / visibleWidth * size.width, y: -crop.top / visibleHeight * size.height,
                              width: size.width / visibleWidth, height: size.height / visibleHeight)
            if let item = presentation.media[picture.mediaID] {
                // Adjusted and recolored pictures are embedded as they show, since SVG viewers differ in their filters.
                var source = "data:\(item.contentType);base64,\(item.data.base64EncodedString())"
                let adjustments = picture.adjustments
                if adjustments.brightness != 0 || adjustments.contrast != 0 || adjustments.recolor != nil,
                   let image = AdjustedImages.image(picture, theme: style.theme, presentation: presentation),
                   let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    source = "data:image/png;base64,\(png.base64EncodedString())"
                }
                let opacity = adjustments.transparency > 0 ? " opacity=\"\(n(max(0, 1 - adjustments.transparency)))\"" : ""
                body.append("<image clip-path=\"url(#\(clip))\" x=\"\(n(full.minX))\" y=\"\(n(full.minY))\" width=\"\(n(full.width))\" height=\"\(n(full.height))\" preserveAspectRatio=\"none\"\(opacity) xlink:href=\"\(source)\"/>")
            }
            stroke(parts, outline: style.outline, theme: style.theme, isLine: false)
            body.append("</g>")
        }
    }

    private mutating func fill(_ path: CGPath, with fill: Fill, theme: SlideTheme, mode: PathFillMode) {
        let shade: (ResolvedColor) -> ResolvedColor = { color in
            switch mode {
            case .darken: color.adjusted(lightness: 0.6)
            case .darkenLess: color.adjusted(lightness: 0.8)
            case .lighten: ResolvedColor(red: color.red + (1 - color.red) * 0.4, green: color.green + (1 - color.green) * 0.4,
                                         blue: color.blue + (1 - color.blue) * 0.4, alpha: color.alpha)
            case .lightenLess: ResolvedColor(red: color.red + (1 - color.red) * 0.2, green: color.green + (1 - color.green) * 0.2,
                                             blue: color.blue + (1 - color.blue) * 0.2, alpha: color.alpha)
            default: color
            }
        }
        let paint: String
        switch fill {
        case .none:
            return
        case .solid(let ref):
            let resolved = shade(ref.resolved(theme.colors))
            paint = "fill=\"\(color(resolved))\"" + (resolved.alpha < 1 ? " fill-opacity=\"\(n(resolved.alpha))\"" : "")
        case .gradient(let gradient):
            let id = newID("gradient")
            let stops = gradient.stops.sorted { $0.position < $1.position }.map { stop -> String in
                let resolved = shade(stop.color.resolved(theme.colors))
                return "<stop offset=\"\(n(stop.position))\" stop-color=\"\(color(resolved))\"" + (resolved.alpha < 1 ? " stop-opacity=\"\(n(resolved.alpha))\"" : "") + "/>"
            }.joined()
            switch gradient.kind {
            case .linear(let angle):
                let radians = angle * .pi / 180
                let dx = cos(radians) / 2, dy = sin(radians) / 2
                defs.append("<linearGradient id=\"\(id)\" x1=\"\(n(0.5 - dx))\" y1=\"\(n(0.5 - dy))\" x2=\"\(n(0.5 + dx))\" y2=\"\(n(0.5 + dy))\">\(stops)</linearGradient>")
            case .radial:
                defs.append("<radialGradient id=\"\(id)\" cx=\"0.5\" cy=\"0.5\" r=\"0.71\">\(stops)</radialGradient>")
            }
            paint = "fill=\"url(#\(id))\""
        case .picture(let picture):
            guard let item = presentation.media[picture.mediaID] else { return }
            let box = path.boundingBoxOfPath
            let clip = newID("clip")
            defs.append("<clipPath id=\"\(clip)\"><path clip-rule=\"evenodd\" d=\"\(data(path))\"/></clipPath>")
            body.append("<image clip-path=\"url(#\(clip))\" x=\"\(n(box.minX))\" y=\"\(n(box.minY))\" width=\"\(n(box.width))\" height=\"\(n(box.height))\" preserveAspectRatio=\"none\" xlink:href=\"data:\(item.contentType);base64,\(item.data.base64EncodedString())\"/>")
            return
        }
        body.append("<path fill-rule=\"evenodd\" \(paint) d=\"\(data(path))\"/>")
    }

    private mutating func stroke(_ parts: [ShapePath], outline: Outline, theme: SlideTheme, isLine: Bool) {
        guard outline.isVisible, case .solid(let ref) = outline.fill else { return }
        let resolved = ref.resolved(theme.colors)
        let width = CGFloat(outline.width)
        var attributes = "fill=\"none\" stroke=\"\(color(resolved))\" stroke-width=\"\(n(width))\" stroke-linejoin=\"round\""
        if resolved.alpha < 1 { attributes += " stroke-opacity=\"\(n(resolved.alpha))\"" }
        attributes += outline.dash == .solid ? (isLine ? " stroke-linecap=\"round\"" : "") : ""
        if !outline.dash.pattern.isEmpty {
            attributes += " stroke-dasharray=\"\(outline.dash.pattern.map { n(CGFloat($0) * max(width, 0.75)) }.joined(separator: " "))\""
        }
        let stroked = parts.filter(\.stroke)
        let hasEnds = isLine && (outline.head != .none || outline.tail != .none)
        for (index, part) in stroked.enumerated() {
            if hasEnds, index == stroked.count - 1 {
                let ends = SlideRenderer.EndPoints(part.path)
                let trimmed = ends.trimmed(head: SlideRenderer.trim(for: outline.head, width: width), tail: SlideRenderer.trim(for: outline.tail, width: width))
                body.append("<path \(attributes) d=\"\(data(trimmed))\"/>")
                for (end, tip) in [(outline.head, ends.head), (outline.tail, ends.tail)] {
                    guard let tip, let shape = SlideRenderer.endShape(end, at: tip.point, direction: tip.direction, width: width) else { continue }
                    body.append(shape.filled ? "<path fill=\"\(color(resolved))\" d=\"\(data(shape.path))\"/>"
                                : "<path fill=\"none\" stroke=\"\(color(resolved))\" stroke-width=\"\(n(width))\" stroke-linecap=\"round\" d=\"\(data(shape.path))\"/>")
                }
            } else {
                body.append("<path \(attributes) d=\"\(data(part.path))\"/>")
            }
        }
    }

    // MARK: Text

    private mutating func text(of element: SlideElement, style: ElementStyle) {
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let paragraphs = style.resolvedParagraphs(slideNumber: slideNumber)
        guard !paragraphs.allSatisfy(\.isEmpty) else { return }
        let area = TextMetrics.textArea(for: style, size: size)
        let layout = TextLayout.make(paragraphs, width: area.width, wraps: style.bodyProperties.wraps)
        let offset: CGFloat = switch style.bodyProperties.anchor {
        case .top: 0
        case .middle: (area.height - layout.usedHeight) / 2
        case .bottom: area.height - layout.usedHeight
        }
        body.append("<g transform=\"\(matrix(SlideRenderer.textTransform(for: placement)))\">")
        body += textElements(layout, origin: CGPoint(x: area.minX, y: area.minY + offset))
        closeGroup()
    }

    /// A table: cell fills, text, then the borders that show.
    private mutating func write(_ table: Table, style: ElementStyle) {
        guard table.rowCount > 0, table.columnCount > 0 else { return }
        let layout = TableLayout(table, style: style, slideNumber: slideNumber)
        let frame = style.placement.frame
        let transform = Placement(frame: SlideRect(x: frame.x, y: frame.y, width: layout.size.width, height: layout.size.height),
                                  rotation: style.placement.rotation).transform
        body.append("<g transform=\"\(matrix(transform))\">")
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            if !cell.fill.isNone { fill(CGPath(rect: layout.rect(row: row, column: column), transform: nil), with: cell.fill, theme: style.theme, mode: .normal) }
        }
        for (row, column) in table.visibleCells {
            guard let text = layout.text(row: row, column: column), !text.paragraphs.allSatisfy(\.isEmpty) else { continue }
            body += textElements(text.layout, origin: layout.textOrigin(row: row, column: column))
        }
        for segment in SlideRenderer.tableBorderSegments(table, layout: layout) {
            guard case .solid(let ref) = segment.outline.fill else { continue }
            let resolved = ref.resolved(style.theme.colors)
            let width = CGFloat(segment.outline.width)
            var line = "<line x1=\"\(n(segment.from.x))\" y1=\"\(n(segment.from.y))\" x2=\"\(n(segment.to.x))\" y2=\"\(n(segment.to.y))\" stroke=\"\(color(resolved))\" stroke-width=\"\(n(width))\""
            if resolved.alpha < 1 { line += " stroke-opacity=\"\(n(resolved.alpha))\"" }
            if segment.outline.dash.pattern.isEmpty {
                line += " stroke-linecap=\"square\""
            } else {
                line += " stroke-dasharray=\"\(segment.outline.dash.pattern.map { n(CGFloat($0) * max(width, 0.75)) }.joined(separator: " "))\""
            }
            body.append(line + "/>")
        }
        closeGroup()
    }

    /// `<text>` elements for laid-out text: bullets where the layout manager draws them, and each line's runs at the
    /// positions TextKit gave them.
    private func textElements(_ layout: TextLayout, origin: CGPoint) -> [String] {
        var result: [String] = []
        let manager = layout.layoutManager, storage = layout.storage
        let string = storage.string as NSString
        for (location, label) in manager.bulletLabels().sorted(by: { $0.key < $1.key }) {
            guard location < string.length, let info = storage.attribute(.slideBullet, at: location, effectiveRange: nil) as? BulletInfo else { continue }
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let content = string.substring(with: range).trimmingCharacters(in: CharacterSet(charactersIn: "\n\u{200B}"))
            guard !content.isEmpty else { continue }
            let glyph = manager.glyphIndexForCharacter(at: location)
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = origin.y + fragment.minY + manager.location(forGlyphAt: glyph).y
            let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            let textColor = (storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)?.resolvedColor ?? .black
            let bulletColor = info.color?.resolvedColor ?? textColor
            result.append("<text x=\"\(n(origin.x + info.marginLeft + info.indent))\" y=\"\(n(baseline))\" font-family=\"\(escape(info.fontFamily ?? font?.familyName ?? "Arial"))\" font-size=\"\(n((font?.pointSize ?? 18) * info.sizeFraction))\" fill=\"\(color(bulletColor))\">\(escape(label))</text>")
        }
        let glyphs = manager.glyphRange(for: layout.container)
        let format = self
        var lines: [String] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            let lineCharacters = manager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: lineCharacters) { attributes, range, _ in
                // Start at the first visible character, so renderers that drop leading spaces still place the words right.
                var start = range.location
                while start < NSMaxRange(range), let scalar = Unicode.Scalar(string.character(at: start)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{200B}" { start += 1 }
                guard start < NSMaxRange(range) else { return }
                let text = string.substring(with: NSRange(location: start, length: NSMaxRange(range) - start))
                    .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\u{200B}", with: "")
                    .replacingOccurrences(of: "\u{2028}", with: "")
                let glyph = manager.glyphIndexForCharacter(at: start)
                let location = manager.location(forGlyphAt: glyph)
                let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
                let traits = NSFontManager.shared.traits(of: font)
                let fill = (attributes[.foregroundColor] as? NSColor)?.resolvedColor ?? .black
                let shift = (attributes[.baselineOffset] as? CGFloat) ?? 0
                var decoration: [String] = []
                if (attributes[.underlineStyle] as? Int ?? 0) != 0 { decoration.append("underline") }
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { decoration.append("line-through") }
                var element = "<text x=\"\(format.n(origin.x + fragment.minX + location.x))\" y=\"\(format.n(origin.y + fragment.minY + location.y - shift))\""
                element += " font-family=\"\(format.escape(font.familyName ?? "Arial"))\" font-size=\"\(format.n(font.pointSize))\" fill=\"\(format.color(fill))\""
                if fill.alpha < 1 { element += " fill-opacity=\"\(format.n(fill.alpha))\"" }
                if traits.contains(.boldFontMask) { element += " font-weight=\"bold\"" }
                if traits.contains(.italicFontMask) { element += " font-style=\"italic\"" }
                if !decoration.isEmpty { element += " text-decoration=\"\(decoration.joined(separator: " "))\"" }
                element += " xml:space=\"preserve\">\(format.escape(text))</text>"
                lines.append(element)
            }
        }
        return result + lines
    }

    /// Ends a group, or leaves it out when nothing was drawn in it.
    private mutating func closeGroup() {
        if body.last?.hasPrefix("<g ") == true { body.removeLast() } else { body.append("</g>") }
    }
}
