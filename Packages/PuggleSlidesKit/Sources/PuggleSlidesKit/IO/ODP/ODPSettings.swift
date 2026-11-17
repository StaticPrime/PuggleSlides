import Foundation

/// View ▸ Guides as LibreOffice Impress keeps its snap lines: in `settings.xml`, the view's "SnapLinesDrawing" item, a
/// string of lines run together, each "V" (a vertical line) or "H" (a horizontal one) and its position in hundredths of a
/// millimeter from the slide's top-left corner ("V12700H2540"). LibreOffice's snap points ("P<x>,<y>") have no place in
/// the model and are skipped. Snap lines have no color, so guides come back in the default color.
enum ODPSettings {
    static let unitsPerPoint = 2540.0 / 72

    /// The snap line string for guides.
    static func snapLines(_ guides: [Guide]) -> String {
        var result = ""
        for guide in guides where guide.position.isFinite {
            let value = Int((min(max(guide.position, -1_000_000), 1_000_000) * unitsPerPoint).rounded())
            result += (guide.orientation == .vertical ? "V" : "H") + String(value)
        }
        return result
    }

    /// Guides from a snap line string; damaged entries end the list, as they do in LibreOffice.
    static func guides(snapLines: String) -> [Guide] {
        var result: [Guide] = []
        var characters = snapLines.unicodeScalars[...]
        func number() -> Int? {
            var digits = ""
            while let next = characters.first, next == "+" || next == "-" || ("0"..."9").contains(next), digits.count < 12 {
                digits.unicodeScalars.append(next)
                characters = characters.dropFirst()
            }
            return Int(digits)
        }
        while let kind = characters.first, result.count < 1_000 {
            characters = characters.dropFirst()
            switch kind {
            case "V", "H":
                guard let value = number() else { return result }
                result.append(Guide(orientation: kind == "V" ? .vertical : .horizontal, position: Double(value) / unitsPerPoint))
            case "P":
                guard number() != nil, characters.first == "," else { return result }
                characters = characters.dropFirst()
                guard number() != nil else { return result }
            default:
                return result
            }
        }
        return result
    }

    /// `settings.xml` holding the guides as the view's snap lines; nil when there are none, so no settings are written.
    static func part(guides: [Guide]) -> Data? {
        let lines = snapLines(guides)
        guard !lines.isEmpty else { return nil }
        var xml = XMLWriter(reservingCapacity: 1024)
        xml.raw("<office:document-settings xmlns:office=\"\(ODFNamespace.office)\" xmlns:config=\"\(ODFNamespace.config)\" office:version=\"1.3\">")
        xml.raw("<office:settings><config:config-item-set config:name=\"ooo:view-settings\"><config:config-item-map-indexed config:name=\"Views\">")
        xml.raw("<config:config-item-map-entry><config:config-item config:name=\"ViewId\" config:type=\"string\">view1</config:config-item>")
        xml.raw("<config:config-item config:name=\"SnapLinesDrawing\" config:type=\"string\">")
        xml.text(lines)
        xml.raw("</config:config-item></config:config-item-map-entry></config:config-item-map-indexed></config:config-item-set>")
        xml.raw("</office:settings></office:document-settings>")
        return xml.data
    }

    /// The guides of the first view in `settings.xml`.
    static func guides(_ root: ODFNode) -> [Guide] {
        guard root.name == "office:document-settings", let settings = root.child("office:settings") else { return [] }
        let view = settings.children("config:config-item-set").first { $0["config:name"] == "ooo:view-settings" }
        let views = view?.children("config:config-item-map-indexed").first { $0["config:name"] == "Views" }
        guard let entry = views?.child("config:config-item-map-entry"),
              let item = entry.children("config:config-item").first(where: { $0["config:name"] == "SnapLinesDrawing" }) else { return [] }
        return guides(snapLines: item.textContent.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
