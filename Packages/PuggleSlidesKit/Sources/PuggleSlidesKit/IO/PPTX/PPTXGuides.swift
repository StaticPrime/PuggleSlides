import Foundation

/// View ▸ Guides, kept as PowerPoint 2013 and later keep a presentation's guides: `p15:sldGuideLst` in an extension
/// of the presentation part. Extensions are skipped by apps that don't know them, so no `mc:Ignorable` is needed;
/// the `p15` prefix is declared on the list itself, as PowerPoint does.
enum PPTXGuides {
    static let extensionURI = "{EFAFB233-063F-42B5-8137-9DF3F51BA10A}"
    /// Guide positions are in PowerPoint's master units: eighths of a point.
    static let unitsPerPoint = 8.0

    static func write(_ guides: [Guide], into xml: inout XMLWriter) {
        guard !guides.isEmpty else { return }
        xml.raw("<p:extLst><p:ext uri=\"\(extensionURI)\"><p15:sldGuideLst xmlns:p15=\"\(PPTXNamespace.powerPoint2012)\">")
        for (index, guide) in guides.enumerated() {
            xml.raw("<p15:guide id=\"\(index + 1)\"")
            // Vertical is the default orientation.
            if guide.orientation == .horizontal { xml.raw(" orient=\"horz\"") }
            xml.raw(" pos=\"\(PPTXValue.clamped(guide.position * unitsPerPoint, -2_147_483_648...2_147_483_647))\" userDrawn=\"1\"")
            guard let color = guide.color else {
                xml.raw("/>")
                continue
            }
            xml.raw("><p15:clr><a:srgbClr val=\"\(color.hex)\"/></p15:clr></p15:guide>")
        }
        xml.raw("</p15:sldGuideLst></p:ext></p:extLst>")
    }

    /// The guides of a presentation part, or failing those the older ones in its view properties (`p:guideLst`).
    /// Colors given as theme colors are resolved with `colors`.
    static func read(_ presentation: XNode, viewProperties: XNode?, colors: ColorScheme) -> [Guide] {
        for item in presentation.child("extLst")?.children("ext") ?? [] {
            guard let list = item.child("sldGuideLst") else { continue }
            return list.children("guide").map { guide($0, colors: colors) }
        }
        let older = viewProperties?.child("slideViewPr")?.child("cSldViewPr")?.child("guideLst")
        return older?.children("guide").map { guide($0, colors: colors) } ?? []
    }

    private static func guide(_ node: XNode, colors: ColorScheme) -> Guide {
        let orientation: Guide.Orientation = node["orient"] == "horz" ? .horizontal : .vertical
        var position = 0.0
        if let units = PPTXValue.double(node["pos"]) {
            position = units / unitsPerPoint
        } else if let points = PPTXValue.points(node["pos"]) {
            // Strict files may give a length with its unit.
            position = points
        }
        let color = PPTXColorReader().color(in: node.child("clr")).map { $0.resolved(colors).rgb }
        return Guide(orientation: orientation, position: position, color: color)
    }
}
