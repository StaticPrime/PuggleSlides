import Foundation

/// PresentationML's color map: which theme color each name that text and shapes use (bg1, tx1, accent1 …)
/// stands for under a master, layout or slide. The model always assumes the standard map, so the reader
/// turns names into theme slots with the map in force where they appear.
struct PPTXColorMap: Hashable, Sendable {
    static let names = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]

    private(set) var slots: [String: ThemeColorSlot]

    static let standard = PPTXColorMap(slots: [
        "bg1": .light1, "tx1": .dark1, "bg2": .light2, "tx2": .dark2,
        "accent1": .accent1, "accent2": .accent2, "accent3": .accent3, "accent4": .accent4, "accent5": .accent5, "accent6": .accent6,
        "hlink": .hyperlink, "folHlink": .followedHyperlink,
    ])

    private init(slots: [String: ThemeColorSlot]) {
        self.slots = slots
    }

    /// The map a `clrMap` or `overrideClrMapping` element states, on top of `base` for anything it leaves out.
    init(node: XNode, base: PPTXColorMap = .standard) {
        var slots = base.slots
        for name in Self.names {
            if let value = node[name], let slot = ThemeColorSlot(rawValue: value) { slots[name] = slot }
        }
        self.slots = slots
    }

    /// The map a layout, slide or notes slide uses: its own override, else the master's.
    func overridden(by clrMapOvr: XNode?) -> PPTXColorMap {
        guard let override = clrMapOvr?.child("overrideClrMapping") else { return self }
        return PPTXColorMap(node: override, base: self)
    }

    /// The theme slot a scheme color name stands for: mapped names through the map, dk1 … folHlink directly.
    func slot(_ name: String) -> ThemeColorSlot? {
        slots[name] ?? ThemeColorSlot(rawValue: name)
    }
}

/// Reads DrawingML colors into `ColorRef`s.
struct PPTXColorReader {
    static let elementNames: Set<String> = ["srgbClr", "schemeClr", "sysClr", "prstClr", "hslClr", "scrgbClr"]

    var map: PPTXColorMap
    /// What `phClr` stands for, inside theme styles referenced by a shape's style.
    var placeholder: ColorRef?

    init(map: PPTXColorMap = .standard, placeholder: ColorRef? = nil) {
        self.map = map
        self.placeholder = placeholder
    }

    func with(placeholder: ColorRef?) -> PPTXColorReader {
        PPTXColorReader(map: map, placeholder: placeholder)
    }

    /// The color element among `parent`'s children.
    func color(in parent: XNode?) -> ColorRef? {
        guard let node = parent?.children.first(where: { Self.elementNames.contains($0.name) }) else { return nil }
        return color(node)
    }

    func color(_ node: XNode) -> ColorRef? {
        var color: ColorRef
        switch node.name {
        case "srgbClr":
            color = ColorRef(RGBColor(hex: node["val"] ?? "") ?? .black)
        case "schemeClr":
            let name = node["val"] ?? ""
            if name == "phClr" {
                color = placeholder ?? .black
            } else if let slot = map.slot(name) {
                color = ColorRef(theme: slot)
            } else {
                color = .black
            }
        case "sysClr":
            color = ColorRef(Self.systemColor(node))
        case "prstClr":
            color = ColorRef(Self.presetColor(node["val"] ?? ""))
        case "hslClr":
            let hue = (PPTXValue.degrees(node["hue"]) ?? 0) / 360
            let saturation = min(max(PPTXValue.fraction(node["sat"]) ?? 0, 0), 1)
            let lightness = min(max(PPTXValue.fraction(node["lum"]) ?? 0, 0), 1)
            let (red, green, blue) = ColorMath.rgb(hue - hue.rounded(.down), saturation, lightness)
            color = ColorRef(RGBColor(unitRed: red, unitGreen: green, unitBlue: blue))
        case "scrgbClr":
            func gamma(_ linear: Double) -> Double {
                let value = min(max(linear, 0), 1)
                return value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
            }
            color = ColorRef(RGBColor(unitRed: gamma(PPTXValue.fraction(node["r"]) ?? 0), unitGreen: gamma(PPTXValue.fraction(node["g"]) ?? 0),
                                      unitBlue: gamma(PPTXValue.fraction(node["b"]) ?? 0)))
        default:
            return nil
        }
        for transform in node.children {
            guard let value = PPTXValue.fraction(transform["val"]) else { continue }
            Self.apply(transform.name, value, to: &color)
        }
        return color
    }

    /// Applies one color transform on top of those already on `color` (from a style's placeholder color, say).
    /// The model applies luminance, then tint, then shade; transforms compose within that order.
    static func apply(_ name: String, _ value: Double, to color: inout ColorRef) {
        let before = color
        defer {
            // Absurd values can overflow; such a transform is dropped.
            let values = [color.lumMod, color.lumOff, color.tint, color.shade, color.alpha].compactMap { $0 }
            if values.contains(where: { !$0.isFinite }) { color = before }
        }
        switch name {
        case "lumMod":
            color.lumMod = (color.lumMod ?? 1) * value
            color.lumOff = color.lumOff.map { $0 * value }
        case "lumOff":
            color.lumOff = (color.lumOff ?? 0) + value
        case "tint":
            color.tint = min(max((color.tint ?? 1) * value, 0), 1)
        case "shade":
            color.shade = min(max((color.shade ?? 1) * value, 0), 1)
        case "alpha":
            color.alpha = alpha(value)
        case "alphaMod":
            color.alpha = alpha((color.alpha ?? 1) * value)
        case "alphaOff":
            color.alpha = alpha((color.alpha ?? 1) + value)
        default:
            // Saturation, hue, gamma and the rest have no place in the model.
            break
        }
    }

    private static func alpha(_ value: Double) -> Double? {
        let clamped = min(max(value, 0), 1)
        return clamped >= 1 ? nil : clamped
    }

    static func systemColor(_ node: XNode) -> RGBColor {
        if let last = node["lastClr"], let color = RGBColor(hex: last) { return color }
        switch node["val"] {
        case "window", "highlightText", "btnHighlight", "menu", "infoBk", "3dLight", "btnFace": return .white
        case "highlight", "hotLight": return RGBColor(red: 0x00, green: 0x78, blue: 0xD7)
        case "grayText", "btnShadow", "inactiveCaptionText": return RGBColor(red: 0x80, green: 0x80, blue: 0x80)
        default: return .black
        }
    }

    /// DrawingML's preset colors (ST_PresetColorVal), the common ones.
    static func presetColor(_ name: String) -> RGBColor {
        var key = name.lowercased()
        // "dkBlue", "ltGray" and "medPurple" are spellings of "darkBlue", "lightGray" and "mediumPurple".
        if key.hasPrefix("dk") { key = "dark" + key.dropFirst(2) }
        if key.hasPrefix("lt") { key = "light" + key.dropFirst(2) }
        if key.hasPrefix("med"), !key.hasPrefix("medium") { key = "medium" + key.dropFirst(3) }
        key = key.replacingOccurrences(of: "grey", with: "gray")
        let hex: String = switch key {
        case "black": "000000"
        case "white": "FFFFFF"
        case "red": "FF0000"
        case "green": "008000"
        case "lime": "00FF00"
        case "blue": "0000FF"
        case "yellow": "FFFF00"
        case "cyan", "aqua": "00FFFF"
        case "magenta", "fuchsia": "FF00FF"
        case "gray": "808080"
        case "darkgray": "A9A9A9"
        case "lightgray": "D3D3D3"
        case "dimgray": "696969"
        case "silver": "C0C0C0"
        case "orange": "FFA500"
        case "darkorange": "FF8C00"
        case "purple": "800080"
        case "mediumpurple": "9370DB"
        case "brown": "A52A2A"
        case "pink": "FFC0CB"
        case "hotpink": "FF69B4"
        case "navy": "000080"
        case "maroon": "800000"
        case "olive": "808000"
        case "teal": "008080"
        case "gold": "FFD700"
        case "darkblue": "00008B"
        case "darkred": "8B0000"
        case "darkgreen": "006400"
        case "lightblue": "ADD8E6"
        case "lightgreen": "90EE90"
        case "lightyellow": "FFFFE0"
        case "skyblue": "87CEEB"
        case "steelblue": "4682B4"
        case "royalblue": "4169E1"
        case "violet": "EE82EE"
        case "indigo": "4B0082"
        case "crimson": "DC143C"
        case "coral": "FF7F50"
        case "salmon": "FA8072"
        case "tomato": "FF6347"
        case "tan": "D2B48C"
        case "beige": "F5F5DC"
        case "ivory": "FFFFF0"
        case "khaki": "F0E68C"
        case "turquoise": "40E0D0"
        case "orchid": "DA70D6"
        case "plum": "DDA0DD"
        case "chocolate": "D2691E"
        case "firebrick": "B22222"
        case "forestgreen": "228B22"
        case "seagreen": "2E8B57"
        case "slategray": "708090"
        case "darkslategray": "2F4F4F"
        case "midnightblue": "191970"
        case "lavender": "E6E6FA"
        case "wheat": "F5DEB3"
        case "whitesmoke": "F5F5F5"
        case "gainsboro": "DCDCDC"
        default: "000000"
        }
        return RGBColor(hex: hex) ?? .black
    }
}

extension XMLWriter {
    /// A DrawingML color element: `srgbClr` or `schemeClr`, with the adjustments in the order the model applies them.
    mutating func color(_ color: ColorRef) {
        let name: String
        switch color.base {
        case .rgb(let rgb):
            name = "a:srgbClr"
            raw("<a:srgbClr")
            attribute("val", rgb.hex)
        case .theme(let slot):
            name = "a:schemeClr"
            raw("<a:schemeClr")
            attribute("val", slot.rawValue)
        }
        var transforms: [(String, Int)] = []
        if let lumMod = color.lumMod { transforms.append(("lumMod", PPTXValue.clamped(lumMod * 100_000, -100_000_000...100_000_000))) }
        if let lumOff = color.lumOff { transforms.append(("lumOff", PPTXValue.clamped(lumOff * 100_000, -100_000_000...100_000_000))) }
        if let tint = color.tint { transforms.append(("tint", PPTXValue.clamped(tint * 100_000, 0...100_000))) }
        if let shade = color.shade { transforms.append(("shade", PPTXValue.clamped(shade * 100_000, 0...100_000))) }
        if let alpha = color.alpha, alpha < 1 { transforms.append(("alpha", PPTXValue.clamped(alpha * 100_000, 0...100_000))) }
        guard !transforms.isEmpty else {
            raw("/>")
            return
        }
        raw(">")
        for (transform, value) in transforms { raw("<a:\(transform) val=\"\(value)\"/>") }
        raw("</\(name)>")
    }

    /// `<a:solidFill>` around a color.
    mutating func solidFill(_ color: ColorRef) {
        raw("<a:solidFill>")
        self.color(color)
        raw("</a:solidFill>")
    }
}
