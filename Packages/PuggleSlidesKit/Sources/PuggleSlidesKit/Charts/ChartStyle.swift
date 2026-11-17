import CoreGraphics
import Foundation

/// An sRGB color with opacity.
struct ChartColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: RGBColor, alpha: Double = 1) {
        self.init(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, alpha: alpha)
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    func opacity(_ alpha: Double) -> ChartColor {
        ChartColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// "#4285F4".
    var hex: String {
        func byte(_ component: Double) -> Int { Int((Swift.min(1, Swift.max(0, component)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Relative luminance, 0 (black) to 1 (white).
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    static let white = ChartColor(hex: 0xFFFFFF)
}

/// The chart look for one chart, in points: Roboto (else Arial, else Helvetica), a 16 px title at the top left,
/// 12 px gray axis labels, light gray gridlines with a darker zero line, and 12 px legend text with round color
/// markers.
///
/// A chart pixel is 0.75 point, so Insert ▸ Chart's 450 × 278 point chart is a 600 × 371 pixel chart: its 16 px
/// title is 12 pt and its 12 px labels are 9 pt. Smaller charts shrink text and spacing with them, but only down to
/// labels of 7 pt so they stay readable. Bigger charts grow them with the square root of their size, up to labels
/// of about 12 pt, so a chart filling a slide keeps its text in proportion without it looking blown up.
struct ChartStyle {
    /// The size `scale` is measured against: Insert ▸ Chart's chart, 600 × 371 pixels.
    static let referenceSize = CGSize(width: 450, height: 278)
    /// Points per chart pixel at the reference size.
    static let pointsPerPixel = 0.75
    /// How far text and spacing shrink and grow from their size at the reference size.
    static let smallestFactor = 0.78
    static let largestFactor = 1.35
    /// How far a small chart's tick and gridline spacing shrinks.
    static let smallestGridFactor = 0.6

    /// The installed family that measures and draws text.
    let family: String
    /// The CSS font stack SVG output names.
    let svgFontFamily: String
    /// Points per chart pixel: 0.75 at the reference size, from about 0.59 for small charts to about 1
    /// for big ones. Every size below is its size in pixels times this.
    let scale: Double
    /// Points per chart pixel for how far apart ticks and gridlines are: `scale` without the floor that
    /// keeps small charts' text readable, so small charts don't lose gridlines to it.
    let gridScale: Double
    let background: ChartColor
    let dark: Bool

    let titleFont: ChartFont
    let labelFont: ChartFont
    let axisTitleFont: ChartFont
    let legendFont: ChartFont
    let dataLabelFont: ChartFont
    let sliceFont: ChartFont
    let messageFont: ChartFont

    let titleColor: ChartColor
    let verticalLabelColor: ChartColor
    let horizontalLabelColor: ChartColor
    let axisTitleColor: ChartColor
    let legendColor: ChartColor
    let gridlineColor: ChartColor
    let baselineColor: ChartColor
    let dataLabelColor: ChartColor
    let messageColor: ChartColor
    let sliceTextColor: ChartColor

    /// Space between the chart's edge and its content.
    let padding: Double
    /// Space between axis labels and the plot.
    let labelGap: Double
    /// Space between the title and what's below it.
    let titleGap: Double
    /// Diameter of the legend's color circles.
    let markerSize: Double
    /// The thickness of gridlines and the zero line: one chart pixel.
    let hairline: Double

    /// The translucent area fill.
    static let areaOpacity = 0.3
    /// The share of a category's slot its columns fill (a golden-ratio group width).
    static let groupWidth = 0.618

    /// Points per chart pixel for a chart of `size` points, shrinking no further than `smallest` times the
    /// reference size's.
    static func scale(for size: CGSize, smallest: Double = smallestFactor) -> Double {
        let width = Double(size.width), height = Double(size.height)
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return pointsPerPixel * smallest }
        let ratio = Swift.min(width / Double(referenceSize.width), height / Double(referenceSize.height))
        // Full size down to 80% of the reference size, then shrinking with the chart.
        let factor = ratio >= 1 ? Swift.min(largestFactor, ratio.squareRoot()) : Swift.max(smallest, Swift.min(1, ratio / 0.8))
        return pointsPerPixel * factor
    }

    init(chart: Chart, size: CGSize) {
        let engine = ChartTextEngine.shared
        let family = engine.family(for: chart.fontFamily)
        self.family = family
        var stack: [String] = []
        if let requested = chart.fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty { stack.append(requested) }
        for fallback in ChartTextEngine.fallbackFamilies where !stack.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) {
            stack.append(fallback)
        }
        svgFontFamily = (stack.map { $0.contains(" ") ? "'\($0)'" : $0 } + ["sans-serif"]).joined(separator: ", ")

        let scale = ChartStyle.scale(for: size)
        self.scale = scale
        gridScale = ChartStyle.scale(for: size, smallest: ChartStyle.smallestGridFactor)
        let background = chart.backgroundColor.map { ChartColor($0) } ?? .white
        self.background = background
        let dark = background.luminance < 0.45
        self.dark = dark

        func font(_ pixels: Double) -> ChartFont {
            ChartFont(family: family, size: (pixels * scale * 2).rounded() / 2)
        }
        titleFont = font(16)
        labelFont = font(12)
        axisTitleFont = font(12)
        legendFont = font(12)
        dataLabelFont = font(11)
        sliceFont = font(12)
        messageFont = font(13)

        if dark {
            titleColor = ChartColor(hex: 0xFFFFFF)
            verticalLabelColor = ChartColor(hex: 0xD0D0D0)
            horizontalLabelColor = ChartColor(hex: 0xE0E0E0)
            axisTitleColor = ChartColor(hex: 0xE0E0E0)
            legendColor = ChartColor(hex: 0xE0E0E0)
            gridlineColor = ChartColor(hex: 0xFFFFFF, alpha: 0.25)
            baselineColor = ChartColor(hex: 0xFFFFFF, alpha: 0.7)
            dataLabelColor = ChartColor(hex: 0xE0E0E0)
            messageColor = ChartColor(hex: 0xBDBDBD)
        } else {
            titleColor = ChartColor(hex: 0x000000)
            verticalLabelColor = ChartColor(hex: 0x444444)
            horizontalLabelColor = ChartColor(hex: 0x222222)
            axisTitleColor = ChartColor(hex: 0x222222)
            legendColor = ChartColor(hex: 0x222222)
            gridlineColor = ChartColor(hex: 0xCCCCCC)
            baselineColor = ChartColor(hex: 0x333333)
            dataLabelColor = ChartColor(hex: 0x444444)
            messageColor = ChartColor(hex: 0x757575)
        }
        sliceTextColor = .white

        padding = (16 * scale).rounded()
        labelGap = (8 * scale).rounded()
        titleGap = (16 * scale).rounded()
        markerSize = 9 * scale
        hairline = Swift.max(0.5, scale)
    }
}
