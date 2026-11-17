import CoreGraphics
import Foundation

public struct RGBColor: Hashable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Reads "RRGGBB" or "#RRGGBB".
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: UInt8((rgb >> 16) & 0xFF), green: UInt8((rgb >> 8) & 0xFF), blue: UInt8(rgb & 0xFF))
    }

    /// Rounds components in 0...1 to the nearest byte.
    public init(unitRed red: Double, unitGreen green: Double, unitBlue blue: Double) {
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        self.init(red: byte(red), green: byte(green), blue: byte(blue))
    }

    /// "RRGGBB", upper case.
    public var hex: String { String(format: "%02X%02X%02X", red, green, blue) }

    public static let black = RGBColor(red: 0, green: 0, blue: 0)
    public static let white = RGBColor(red: 255, green: 255, blue: 255)
}

/// The twelve colors of a theme, by their DrawingML names.
public enum ThemeColorSlot: String, Codable, CaseIterable, Sendable {
    case dark1 = "dk1", light1 = "lt1", dark2 = "dk2", light2 = "lt2"
    case accent1, accent2, accent3, accent4, accent5, accent6
    case hyperlink = "hlink", followedHyperlink = "folHlink"

    /// Reads a DrawingML scheme color name, mapping the text and background aliases (tx1, bg1, tx2, bg2)
    /// through the standard color map.
    public init?(schemeName: String) {
        switch schemeName {
        case "tx1": self = .dark1
        case "bg1": self = .light1
        case "tx2": self = .dark2
        case "bg2": self = .light2
        default: self.init(rawValue: schemeName)
        }
    }

    /// The names shown in the theme colors editor.
    public var title: String {
        switch self {
        case .dark1: "Dark 1"
        case .light1: "Light 1"
        case .dark2: "Dark 2"
        case .light2: "Light 2"
        case .accent1: "Accent 1"
        case .accent2: "Accent 2"
        case .accent3: "Accent 3"
        case .accent4: "Accent 4"
        case .accent5: "Accent 5"
        case .accent6: "Accent 6"
        case .hyperlink: "Link"
        case .followedHyperlink: "Followed link"
        }
    }
}

public struct ColorScheme: Hashable, Codable, Sendable {
    public var name: String
    public var colors: [ThemeColorSlot: RGBColor]

    public init(name: String, colors: [ThemeColorSlot: RGBColor]) {
        self.name = name
        self.colors = colors
    }

    public subscript(slot: ThemeColorSlot) -> RGBColor {
        if let color = colors[slot] { return color }
        switch slot {
        case .light1, .light2: return .white
        case .hyperlink, .followedHyperlink: return RGBColor(red: 0x11, green: 0x55, blue: 0xCC)
        default: return .black
        }
    }
}

/// A color as DrawingML stores it: a fixed color or one of the theme's, with optional adjustments.
public struct ColorRef: Hashable, Codable, Sendable {
    public enum Base: Hashable, Codable, Sendable {
        case rgb(RGBColor)
        case theme(ThemeColorSlot)
    }

    public var base: Base
    /// Luminance modulation and offset, as fractions (DrawingML's lumMod 75000 is 0.75).
    public var lumMod: Double?
    public var lumOff: Double?
    /// Tint toward white and shade toward black, as fractions (1 leaves the color alone).
    public var tint: Double?
    public var shade: Double?
    /// Opacity from 0 (clear) to 1; nil is opaque.
    public var alpha: Double?

    public init(_ base: Base, lumMod: Double? = nil, lumOff: Double? = nil, tint: Double? = nil, shade: Double? = nil, alpha: Double? = nil) {
        self.base = base
        self.lumMod = lumMod
        self.lumOff = lumOff
        self.tint = tint
        self.shade = shade
        self.alpha = alpha
    }

    public init(_ rgb: RGBColor, alpha: Double? = nil) {
        self.init(.rgb(rgb), alpha: alpha)
    }

    public init(theme slot: ThemeColorSlot) {
        self.init(.theme(slot))
    }

    public init?(hex: String) {
        guard let rgb = RGBColor(hex: hex) else { return nil }
        self.init(rgb)
    }

    public static let black = ColorRef(RGBColor.black)
    public static let white = ColorRef(RGBColor.white)

    public var themeSlot: ThemeColorSlot? {
        if case .theme(let slot) = base { return slot }
        return nil
    }

    public var rgb: RGBColor? {
        if case .rgb(let color) = base { return color }
        return nil
    }

    public var hasAdjustments: Bool { lumMod != nil || lumOff != nil || tint != nil || shade != nil }

    public func withAlpha(_ alpha: Double?) -> ColorRef {
        var copy = self
        copy.alpha = alpha.map { max(0, min(1, $0)) }
        if copy.alpha == 1 { copy.alpha = nil }
        return copy
    }

    /// The concrete color with the given theme colors.
    public func resolved(_ scheme: ColorScheme) -> ResolvedColor {
        let rgb: RGBColor = switch base {
        case .rgb(let color): color
        case .theme(let slot): scheme[slot]
        }
        var red = Double(rgb.red) / 255, green = Double(rgb.green) / 255, blue = Double(rgb.blue) / 255
        if lumMod != nil || lumOff != nil {
            var (hue, saturation, lightness) = ColorMath.hsl(red, green, blue)
            lightness = lightness * (lumMod ?? 1) + (lumOff ?? 0)
            lightness = max(0, min(1, lightness))
            (red, green, blue) = ColorMath.rgb(hue, saturation, lightness)
        }
        if let tint {
            let amount = max(0, min(1, tint))
            red = red * amount + (1 - amount)
            green = green * amount + (1 - amount)
            blue = blue * amount + (1 - amount)
        }
        if let shade {
            let amount = max(0, min(1, shade))
            red *= amount
            green *= amount
            blue *= amount
        }
        return ResolvedColor(red: red, green: green, blue: blue, alpha: alpha ?? 1)
    }
}

/// A color ready to draw, with components in 0...1 (sRGB).
public struct ResolvedColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ rgb: RGBColor, alpha: Double = 1) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255, alpha: alpha)
    }

    public static let black = ResolvedColor(red: 0, green: 0, blue: 0)
    public static let white = ResolvedColor(red: 1, green: 1, blue: 1)
    public static let clear = ResolvedColor(red: 0, green: 0, blue: 0, alpha: 0)

    public var rgb: RGBColor { RGBColor(unitRed: red, unitGreen: green, unitBlue: blue) }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    /// Relative luminance, for choosing contrasting text and handles.
    public var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

    /// The color darkened or lightened by a fraction, for shape faces such as a cube's sides.
    public func adjusted(lightness factor: Double) -> ResolvedColor {
        var (hue, saturation, lightness) = ColorMath.hsl(red, green, blue)
        lightness = max(0, min(1, lightness * factor))
        let (r, g, b) = ColorMath.rgb(hue, saturation, lightness)
        return ResolvedColor(red: r, green: g, blue: b, alpha: alpha)
    }
}

enum ColorMath {
    static func hsl(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        guard maximum != minimum else { return (0, 0, lightness) }
        let delta = maximum - minimum
        let saturation = lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        return (hue, saturation, lightness)
    }

    static func rgb(_ hue: Double, _ saturation: Double, _ lightness: Double) -> (Double, Double, Double) {
        guard saturation > 0 else { return (lightness, lightness, lightness) }
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        return (channel(p, q, hue + 1.0 / 3), channel(p, q, hue), channel(p, q, hue - 1.0 / 3))
    }
}
