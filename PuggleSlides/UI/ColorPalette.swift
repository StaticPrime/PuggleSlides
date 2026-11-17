import AppKit

extension NSColor {
    /// Creates an sRGB color from "RRGGBB" or "#RRGGBB".
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// The text, fill and tab color grid shown in the toolbar color pickers.
enum ColorPalette {
    struct Swatch: Identifiable {
        let hex: String
        let name: String
        var id: String { hex + name }
        var color: NSColor { NSColor(hex: hex) ?? .black }
    }

    private static let grayNames = ["black", "dark gray 4", "dark gray 3", "dark gray 2", "dark gray 1",
                                    "gray", "light gray 1", "light gray 2", "light gray 3", "white"]
    private static let hueNames = ["red berry", "red", "orange", "yellow", "green", "cyan", "cornflower blue", "blue", "purple", "magenta"]

    private static let grays = ["000000", "434343", "666666", "999999", "B7B7B7", "CCCCCC", "D9D9D9", "EFEFEF", "F3F3F3", "FFFFFF"]
    private static let brights = ["980000", "FF0000", "FF9900", "FFFF00", "00FF00", "00FFFF", "4A86E8", "0000FF", "9900FF", "FF00FF"]
    private static let shades: [(String, [String])] = [
        ("light 3", ["E6B8AF", "F4CCCC", "FCE5CD", "FFF2CC", "D9EAD3", "D0E0E3", "C9DAF8", "CFE2F3", "D9D2E9", "EAD1DC"]),
        ("light 2", ["DD7E6B", "EA9999", "F9CB9C", "FFE599", "B6D7A8", "A2C4C9", "A4C2F4", "9FC5E8", "B4A7D6", "D5A6BD"]),
        ("light 1", ["CC4125", "E06666", "F6B26B", "FFD966", "93C47D", "76A5AF", "6D9EEB", "6FA8DC", "8E7CC3", "C27BA0"]),
        ("dark 1", ["A61C00", "CC0000", "E69138", "F1C232", "6AA84F", "45818E", "3C78D8", "3D85C6", "674EA7", "A64D79"]),
        ("dark 2", ["85200C", "990000", "B45F06", "BF9000", "38761D", "134F5C", "1155CC", "0B5394", "351C75", "741B47"]),
        ("dark 3", ["5B0F00", "660000", "783F04", "7F6000", "274E13", "0C343D", "1C4587", "073763", "20124D", "4C1130"]),
    ]

    static var grayRow: [Swatch] { zip(grays, grayNames).map { Swatch(hex: $0, name: $1) } }
    static var brightRow: [Swatch] { zip(brights, hueNames).map { Swatch(hex: $0, name: $1) } }
    static var shadeRows: [[Swatch]] {
        shades.map { label, row in zip(row, hueNames).map { Swatch(hex: $0, name: "\(label) \($1)") } }
    }
}
