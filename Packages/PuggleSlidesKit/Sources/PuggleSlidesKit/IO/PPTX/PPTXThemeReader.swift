import Foundation

/// What a theme part holds: colors, fonts, and the formatting styles shapes refer to by number.
struct PPTXThemeData {
    var name: String
    var colors: ColorScheme
    var fonts: FontScheme
    /// fmtScheme's fill, line and background fill styles, kept as found: they're read with a shape's own
    /// placeholder color (phClr) each time one is used.
    var fillStyles: [XNode] = []
    var lineStyles: [XNode] = []
    var backgroundStyles: [XNode] = []
    /// Pictures the styles show, from the theme part's relationships.
    var media: (String?) -> MediaID? = { _ in nil }

    /// Office's colors and fonts, for masters whose theme part is missing or damaged.
    static var fallback: PPTXThemeData { PPTXThemeData(
        name: "Office Theme",
        colors: ColorScheme(name: "Office", colors: [
            .dark1: .black, .light1: .white, .dark2: RGBColor(red: 0x44, green: 0x54, blue: 0x6A),
            .light2: RGBColor(red: 0xE7, green: 0xE6, blue: 0xE6), .accent1: RGBColor(red: 0x44, green: 0x72, blue: 0xC4),
            .accent2: RGBColor(red: 0xED, green: 0x7D, blue: 0x31), .accent3: RGBColor(red: 0xA5, green: 0xA5, blue: 0xA5),
            .accent4: RGBColor(red: 0xFF, green: 0xC0, blue: 0x00), .accent5: RGBColor(red: 0x5B, green: 0x9B, blue: 0xD5),
            .accent6: RGBColor(red: 0x70, green: 0xAD, blue: 0x47), .hyperlink: RGBColor(red: 0x05, green: 0x63, blue: 0xC1),
            .followedHyperlink: RGBColor(red: 0x95, green: 0x4F, blue: 0x72),
        ]),
        fonts: FontScheme(name: "Office", major: "Calibri Light", minor: "Calibri")) }

    static let fillNames: Set<String> = ["noFill", "solidFill", "gradFill", "blipFill", "pattFill", "grpFill"]

    /// Reads a theme part (`a:theme`); anything missing comes from Office's defaults.
    init(_ root: XNode) {
        var data = PPTXThemeData.fallback
        data.name = root["name"].flatMap { $0.isEmpty ? nil : $0 } ?? data.name
        let elements = root.child("themeElements")
        if let scheme = elements?.child("clrScheme") {
            var colors = data.colors.colors
            for slot in ThemeColorSlot.allCases {
                guard let node = scheme.child(slot.rawValue)?.children.first(where: { PPTXColorReader.elementNames.contains($0.name) })
                else { continue }
                // Scheme colors are absolute; a scheme reference here would be circular.
                switch node.name {
                case "srgbClr": if let color = RGBColor(hex: node["val"] ?? "") { colors[slot] = color }
                case "sysClr": colors[slot] = PPTXColorReader.systemColor(node)
                case "schemeClr": continue
                default: if let color = PPTXColorReader().color(node) { colors[slot] = color.resolved(data.colors).rgb }
                }
            }
            data.colors = ColorScheme(name: scheme["name"] ?? data.colors.name, colors: colors)
        }
        if let fonts = elements?.child("fontScheme") {
            func typeface(_ name: String) -> String? {
                guard let face = fonts.child(name)?.child("latin")?["typeface"], !face.isEmpty else { return nil }
                return face
            }
            data.fonts = FontScheme(name: fonts["name"] ?? data.fonts.name, major: typeface("majorFont") ?? data.fonts.major,
                                    minor: typeface("minorFont") ?? data.fonts.minor)
        }
        if let format = elements?.child("fmtScheme") {
            data.fillStyles = format.child("fillStyleLst")?.children.filter { Self.fillNames.contains($0.name) } ?? []
            data.lineStyles = format.child("lnStyleLst")?.children("ln") ?? []
            data.backgroundStyles = format.child("bgFillStyleLst")?.children.filter { Self.fillNames.contains($0.name) } ?? []
        }
        self = data
    }

    private init(name: String, colors: ColorScheme, fonts: FontScheme) {
        self.name = name
        self.colors = colors
        self.fonts = fonts
    }

    /// The fill a `fillRef` or `bgRef` index names: 1… are fill styles, 1001… background fill styles, 0 is none.
    func fillStyle(_ index: Int) -> XNode? {
        if index >= 1001 {
            let position = index - 1001
            return position < backgroundStyles.count ? backgroundStyles[position] : backgroundStyles.last
        }
        guard index >= 1 else { return nil }
        let position = index - 1
        return position < fillStyles.count ? fillStyles[position] : fillStyles.last
    }

    /// The line an `lnRef` index names (1…).
    func lineStyle(_ index: Int) -> XNode? {
        guard index >= 1 else { return nil }
        let position = index - 1
        return position < lineStyles.count ? lineStyles[position] : lineStyles.last
    }
}
