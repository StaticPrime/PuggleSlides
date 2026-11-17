import Foundation

/// Reads DrawingML fills, lines and shape style references.
struct PPTXFillReader {
    var colors: PPTXColorReader
    var theme: PPTXThemeData
    /// The media an `r:embed` relationship id names, stored once in the presentation.
    var media: (String?) -> MediaID?
    /// What `grpFill` stands for: the enclosing group's fill.
    var groupFill: Fill?

    func with(placeholder: ColorRef?) -> PPTXFillReader {
        var copy = self
        copy.colors = colors.with(placeholder: placeholder)
        return copy
    }

    /// A reader for the theme's own styles: `phClr` is `placeholder`, and pictures come from the theme part.
    func themeStyles(placeholder: ColorRef?) -> PPTXFillReader {
        var copy = with(placeholder: placeholder)
        copy.media = theme.media
        return copy
    }

    /// The fill among `parent`'s children; nil when it states none.
    func fill(in parent: XNode?) -> Fill? {
        guard let node = parent?.children.first(where: { PPTXThemeData.fillNames.contains($0.name) }) else { return nil }
        return fill(node)
    }

    func fill(_ node: XNode) -> Fill? {
        switch node.name {
        case "noFill":
            return Fill.none
        case "solidFill":
            return .solid(colors.color(in: node) ?? .black)
        case "gradFill":
            return gradient(node)
        case "blipFill":
            guard let id = media(node.child("blip")?["embed"]) else { return nil }
            return .picture(PictureFill(mediaID: id, stretches: node.child("tile") == nil))
        case "pattFill":
            // Patterns show as their foreground color.
            return .solid(colors.color(in: node.child("fgClr")) ?? .black)
        case "grpFill":
            return groupFill
        default:
            return nil
        }
    }

    func gradient(_ node: XNode) -> Fill {
        var stops: [GradientStop] = []
        for stop in node.child("gsLst")?.children("gs") ?? [] {
            let position = min(max(PPTXValue.fraction(stop["pos"]) ?? 0, 0), 1)
            stops.append(GradientStop(position: position, color: colors.color(in: stop) ?? .black))
        }
        guard !stops.isEmpty else { return Fill.none }
        let kind: GradientFill.Kind
        if let linear = node.child("lin") {
            kind = .linear(angle: Placement.normalized(PPTXValue.degrees(linear["ang"]) ?? 0))
        } else if node.child("path") != nil {
            kind = .radial
        } else {
            kind = .linear(angle: 0)
        }
        return .gradient(GradientFill(kind: kind, stops: stops))
    }

    /// A line from `ln`, on top of `base` (what the shape's style gives) for anything `ln` leaves out.
    func outline(_ line: XNode?, base: Outline?) -> Outline? {
        guard let line else { return base }
        var outline = base ?? Outline(fill: Fill.none)
        if let width = PPTXValue.points(line["w"]) { outline.width = max(0, width) }
        if let node = line.children.first(where: { ["noFill", "solidFill", "gradFill", "pattFill"].contains($0.name) }),
           let fill = fill(node) {
            outline.fill = fill
        }
        if let dash = line.child("prstDash") {
            outline.dash = DashStyle(preset: dash["val"] ?? "solid")
        } else if line.child("custDash") != nil {
            outline.dash = .dash
        }
        if let head = line.child("headEnd") { outline.head = Self.lineEnd(head["type"]) }
        if let tail = line.child("tailEnd") { outline.tail = Self.lineEnd(tail["type"]) }
        return outline
    }

    static func lineEnd(_ type: String?) -> LineEnd {
        switch type {
        case "triangle", "stealth": .fillArrow
        case "arrow": .strokeArrow
        case "oval": .fillCircle
        case "diamond": .fillDiamond
        default: .none
        }
    }

    /// What a shape's `p:style` gives it: a fill and line from the theme's styles, and a font and color for its text.
    struct StyleReferences {
        var fill: Fill?
        var outline: Outline?
        var fontColor: ColorRef?
        /// "+mj-lt" or "+mn-lt".
        var fontFamily: String?
    }

    func styleReferences(_ style: XNode?) -> StyleReferences {
        var result = StyleReferences()
        guard let style else { return result }
        if let reference = style.child("fillRef"), let index = PPTXValue.int(reference["idx"]), index > 0 {
            let reader = themeStyles(placeholder: colors.color(in: reference))
            result.fill = theme.fillStyle(index).flatMap(reader.fill) ?? reader.colors.placeholder.map(Fill.solid)
        }
        if let reference = style.child("lnRef"), let index = PPTXValue.int(reference["idx"]), index > 0 {
            let reader = themeStyles(placeholder: colors.color(in: reference))
            if let line = theme.lineStyle(index) {
                result.outline = reader.outline(line, base: nil)
            } else if let color = reader.colors.placeholder {
                result.outline = .solid(color)
            }
        }
        if let reference = style.child("fontRef") {
            result.fontColor = colors.color(in: reference)
            switch reference["idx"] {
            case "major": result.fontFamily = "+mj-lt"
            case "minor": result.fontFamily = "+mn-lt"
            default: break
            }
        }
        return result
    }

    /// A slide, layout or master background: `bgPr` with a fill, or `bgRef` to the theme's background styles.
    func background(_ bg: XNode?) -> Fill? {
        guard let bg else { return nil }
        if let properties = bg.child("bgPr") { return fill(in: properties) }
        if let reference = bg.child("bgRef"), let index = PPTXValue.int(reference["idx"]) {
            let reader = themeStyles(placeholder: colors.color(in: reference))
            if index == 0 { return Fill.none }
            return theme.fillStyle(index).flatMap(reader.fill) ?? reader.colors.placeholder.map(Fill.solid)
        }
        return nil
    }
}
