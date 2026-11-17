import Foundation

/// Identifies an image (or other media) stored once in a presentation and shared by every element that shows it.
public typealias MediaID = String

public struct GradientStop: Hashable, Codable, Sendable {
    /// Where the stop sits along the gradient, 0...1.
    public var position: Double
    public var color: ColorRef

    public init(position: Double, color: ColorRef) {
        self.position = position
        self.color = color
    }
}

public struct GradientFill: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        /// Degrees clockwise from left-to-right.
        case linear(angle: Double)
        case radial
    }

    public var kind: Kind
    public var stops: [GradientStop]

    public init(kind: Kind, stops: [GradientStop]) {
        self.kind = kind
        self.stops = stops
    }
}

public struct PictureFill: Hashable, Codable, Sendable {
    public var mediaID: MediaID
    /// Stretched to fill the area; otherwise tiled at the image's own size.
    public var stretches: Bool

    public init(mediaID: MediaID, stretches: Bool = true) {
        self.mediaID = mediaID
        self.stretches = stretches
    }
}

/// How an area (a shape, a slide background) is painted.
public enum Fill: Hashable, Codable, Sendable {
    case none
    case solid(ColorRef)
    case gradient(GradientFill)
    case picture(PictureFill)

    public var solidColor: ColorRef? {
        if case .solid(let color) = self { return color }
        return nil
    }

    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    /// Media this fill shows, if any.
    public var mediaID: MediaID? {
        if case .picture(let picture) = self { return picture.mediaID }
        return nil
    }
}

/// The border dash choices, by their DrawingML preset names.
public enum DashStyle: String, Codable, CaseIterable, Sendable {
    case solid
    case dot = "sysDot"
    case dash
    case dashDot
    case longDash = "lgDash"
    case longDashDot = "lgDashDot"

    /// Reads any DrawingML preset dash, mapping the ones not offered here to the closest one that is.
    public init(preset: String) {
        switch preset {
        case "solid": self = .solid
        case "dot", "sysDot": self = .dot
        case "dash", "sysDash": self = .dash
        case "dashDot", "sysDashDot": self = .dashDot
        case "lgDash": self = .longDash
        case "lgDashDot", "lgDashDotDot", "sysDashDotDot": self = .longDashDot
        default: self = .solid
        }
    }

    public var title: String {
        switch self {
        case .solid: "Solid"
        case .dot: "Dot"
        case .dash: "Dash"
        case .dashDot: "Dash-dot"
        case .longDash: "Long dash"
        case .longDashDot: "Long dash-dot"
        }
    }

    /// Dash and gap lengths as multiples of the line width.
    public var pattern: [Double] {
        switch self {
        case .solid: []
        case .dot: [1, 1]
        case .dash: [4, 3]
        case .dashDot: [4, 3, 1, 3]
        case .longDash: [8, 3]
        case .longDashDot: [8, 3, 1, 3]
        }
    }
}

/// The line start and line end choices.
public enum LineEnd: String, Codable, CaseIterable, Sendable {
    case none
    case fillArrow, strokeArrow
    case fillCircle, strokeCircle
    case fillSquare, strokeSquare
    case fillDiamond, strokeDiamond

    public var title: String {
        switch self {
        case .none: "None"
        case .fillArrow: "Fill arrow"
        case .strokeArrow: "Stroke arrow"
        case .fillCircle: "Fill circle"
        case .strokeCircle: "Stroke circle"
        case .fillSquare: "Fill square"
        case .strokeSquare: "Stroke square"
        case .fillDiamond: "Fill diamond"
        case .strokeDiamond: "Stroke diamond"
        }
    }

    public var isFilled: Bool {
        switch self {
        case .fillArrow, .fillCircle, .fillSquare, .fillDiamond: true
        default: false
        }
    }
}

/// A shape's border, or a line.
public struct Outline: Hashable, Codable, Sendable {
    /// `.none` hides the border.
    public var fill: Fill
    /// Points.
    public var width: Double
    public var dash: DashStyle
    /// The end where the line starts and the end where it finishes.
    public var head: LineEnd
    public var tail: LineEnd

    public init(fill: Fill, width: Double = 0.75, dash: DashStyle = .solid, head: LineEnd = .none, tail: LineEnd = .none) {
        self.fill = fill
        self.width = width
        self.dash = dash
        self.head = head
        self.tail = tail
    }

    public static let none = Outline(fill: .none)

    public var isVisible: Bool { !fill.isNone && width > 0 }

    /// A solid border in a color.
    public static func solid(_ color: ColorRef, width: Double = 0.75) -> Outline {
        Outline(fill: .solid(color), width: width)
    }
}
