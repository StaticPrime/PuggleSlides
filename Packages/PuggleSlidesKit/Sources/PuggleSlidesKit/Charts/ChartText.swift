import CoreGraphics
import CoreText
import Foundation

/// A font as charts use it: an installed family and a size in points.
struct ChartFont: Hashable, Sendable {
    var family: String
    var size: Double
}

/// Fonts, text widths and laid-out lines, cached. Slides redraw their charts as the canvas scrolls and zooms and as
/// thumbnails update, so the same labels are measured and drawn over and over. Safe to use from any thread.
final class ChartTextEngine: @unchecked Sendable {
    static let shared = ChartTextEngine()

    struct Metrics: Sendable {
        var ascent: Double
        var descent: Double
        var height: Double { ascent + descent }
        /// The distance from the baseline to the middle of a capital letter.
        var middle: Double { ascent * 0.36 }
    }

    private final class FontEntry {
        let font: CTFont
        let metrics: Metrics
        /// Advances of ASCII characters, so ASCII text is measured without laying it out.
        let asciiAdvances: [Double]

        init(_ spec: ChartFont) {
            let font = FontRequests.shared.one {
                let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: spec.family] as CFDictionary)
                return CTFontCreateWithFontDescriptor(descriptor, CGFloat(spec.size), nil)
            }
            self.font = font
            metrics = Metrics(ascent: Double(CTFontGetAscent(font)), descent: Double(CTFontGetDescent(font)))
            var characters = (0..<128).map { UniChar($0) }
            var glyphs = [CGGlyph](repeating: 0, count: 128)
            _ = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 128)
            var advances = [CGSize](repeating: .zero, count: 128)
            _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, 128)
            asciiAdvances = advances.enumerated().map { $0.offset < 32 ? 0 : Double($0.element.width) }
        }
    }

    private struct LineKey: Hashable {
        var text: String
        var font: ChartFont
    }

    private struct LineEntry {
        var line: CTLine
        var width: Double
    }

    private let lock = NSLock()
    private var families: [String: String] = [:]
    private var fonts: [ChartFont: FontEntry] = [:]
    private var lines: [LineKey: LineEntry] = [:]
    private let lineLimit = 8192

    /// The families tried in order after the chart's own: Roboto, then Arial and Helvetica.
    static let fallbackFamilies = ["Roboto", "Arial", "Helvetica"]

    /// The first installed family among `requested`, Roboto, Arial and Helvetica, spelled as installed ("arial" is
    /// "Arial"), since Core Text matches family names exactly.
    func family(for requested: String?) -> String {
        let key = requested ?? ""
        lock.lock()
        let cached = families[key]
        lock.unlock()
        if let cached { return cached }
        var candidates: [String] = []
        if let requested, !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(requested.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        candidates += Self.fallbackFamilies
        let resolved = candidates.lazy.compactMap(Self.installedName).first ?? "Helvetica"
        lock.lock()
        families[key] = resolved
        lock.unlock()
        return resolved
    }

    static func isInstalled(_ family: String) -> Bool {
        installedName(family) != nil
    }

    /// `family` as installed, whatever its case; nil when it isn't installed. Charts only ask Core Text for installed
    /// families: for others it looks for downloadable fonts, which can block for a long time.
    static func installedName(_ family: String) -> String? {
        FontRequests.installedName(family)
    }

    private func entry(_ font: ChartFont) -> FontEntry {
        lock.lock()
        let cached = fonts[font]
        lock.unlock()
        if let cached { return cached }
        let made = FontEntry(font)
        lock.lock()
        defer { lock.unlock() }
        if let raced = fonts[font] { return raced }
        fonts[font] = made
        return made
    }

    func metrics(_ font: ChartFont) -> Metrics { entry(font).metrics }

    /// The width of `text` in `font`. ASCII text is measured from cached advances; other text is laid out.
    func width(_ text: String, _ font: ChartFont) -> Double {
        let fontEntry = entry(font)
        var total = 0.0
        for byte in text.utf8 {
            guard byte < 128 else { return line(text, font).width }
            total += fontEntry.asciiAdvances[Int(byte)]
        }
        return total
    }

    /// `text` laid out in `font`, colored by the context's fill color when drawn.
    func line(_ text: String, _ font: ChartFont) -> (line: CTLine, width: Double) {
        let key = LineKey(text: text, font: font)
        lock.lock()
        let cached = lines[key]
        lock.unlock()
        if let cached { return (cached.line, cached.width) }
        let fontEntry = entry(font)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): fontEntry.font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        // Laying out finds fonts for characters the font lacks.
        let (line, width) = FontRequests.shared.one {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            return (line, Double(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        lock.lock()
        if lines.count >= lineLimit { lines.removeAll(keepingCapacity: true) }
        lines[key] = LineEntry(line: line, width: width)
        lock.unlock()
        return (line, width)
    }

    /// `text` cut to `maxWidth` with an ellipsis ("Long categ…"); empty when not even that fits.
    func truncated(_ text: String, _ font: ChartFont, maxWidth: Double) -> String {
        if width(text, font) <= maxWidth { return text }
        let ellipsis = "…"
        let ellipsisWidth = width(ellipsis, font)
        guard maxWidth >= ellipsisWidth else { return "" }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if width(String(characters[..<middle]), font) + ellipsisWidth <= maxWidth { low = middle } else { high = middle - 1 }
        }
        var kept = String(characters[..<low])
        while kept.last?.isWhitespace == true { kept.removeLast() }
        return kept + ellipsis
    }
}
