import CoreGraphics
import Foundation

/// Lengths in the model are points (1/72 inch), measured from a slide's top-left corner with y pointing down.
/// Office files store English Metric Units instead: 914,400 per inch, 12,700 per point.
public enum EMU {
    public static let perPoint: Double = 12_700
    public static let perInch: Double = 914_400

    public static func points(_ emu: Int64) -> Double { Double(emu) / perPoint }
    public static func points(_ emu: Double) -> Double { emu / perPoint }
    public static func emu(_ points: Double) -> Int64 {
        guard points.isFinite else { return 0 }
        return Int64((points * perPoint).rounded())
    }
}

public struct SlidePoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public static let zero = SlidePoint(x: 0, y: 0)
    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct SlideSize: Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The default page: 16:9, 10 × 5.625 inches.
    public static let widescreen = SlideSize(width: 720, height: 405)
    /// 16:10, 10 × 6.25 inches.
    public static let widescreen16x10 = SlideSize(width: 720, height: 450)
    /// 4:3, 10 × 7.5 inches.
    public static let standard = SlideSize(width: 720, height: 540)

    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var aspectRatio: Double { height == 0 ? 0 : width / height }
}

public struct SlideRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y), width: Double(rect.size.width), height: Double(rect.size.height))
    }

    public init(origin: SlidePoint, size: SlideSize) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public static let zero = SlideRect(x: 0, y: 0, width: 0, height: 0)

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var origin: SlidePoint { SlidePoint(x: x, y: y) }
    public var center: SlidePoint { SlidePoint(x: midX, y: midY) }
    public var size: SlideSize { SlideSize(width: width, height: height) }

    public func offsetBy(dx: Double, dy: Double) -> SlideRect {
        SlideRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func insetBy(dx: Double, dy: Double) -> SlideRect {
        SlideRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    /// The same rectangle with a non-negative width and height.
    public var standardized: SlideRect {
        SlideRect(x: min(x, x + width), y: min(y, y + height), width: abs(width), height: abs(height))
    }

    public func union(_ other: SlideRect) -> SlideRect {
        let a = standardized, b = other.standardized
        let left = min(a.minX, b.minX), top = min(a.minY, b.minY)
        return SlideRect(x: left, y: top, width: max(a.maxX, b.maxX) - left, height: max(a.maxY, b.maxY) - top)
    }

    public func intersects(_ other: SlideRect) -> Bool {
        let a = standardized, b = other.standardized
        return a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    public func contains(_ point: SlidePoint) -> Bool {
        let a = standardized
        return point.x >= a.minX && point.x <= a.maxX && point.y >= a.minY && point.y <= a.maxY
    }
}

/// Where an element sits: its unrotated frame, a clockwise rotation about the frame's center, and flips.
/// Flips apply before the rotation, as in Office files.
public struct Placement: Hashable, Codable, Sendable {
    public var frame: SlideRect
    /// Degrees clockwise, kept in 0..<360.
    public var rotation: Double
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(frame: SlideRect, rotation: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.frame = frame
        self.rotation = Placement.normalized(rotation)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    /// An angle in degrees brought into 0..<360.
    public static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let value = degrees.truncatingRemainder(dividingBy: 360)
        let positive = value < 0 ? value + 360 : value
        return positive >= 360 - 1e-9 ? 0 : positive
    }

    /// Maps shape space (origin at the frame's top-left corner, before rotation and flips) to slide space.
    public var transform: CGAffineTransform {
        let frame = self.frame
        return CGAffineTransform(translationX: frame.midX, y: frame.midY)
            .rotated(by: rotation * .pi / 180)
            .scaledBy(x: flipHorizontal ? -1 : 1, y: flipVertical ? -1 : 1)
            .translatedBy(x: -frame.width / 2, y: -frame.height / 2)
    }

    /// The smallest upright rectangle around the rotated frame.
    public var boundingBox: SlideRect {
        guard rotation != 0 else { return frame.standardized }
        let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height).applying(transform)
        return SlideRect(rect)
    }

    /// Converts a slide-space point into shape space.
    public func shapePoint(fromSlide point: SlidePoint) -> SlidePoint {
        SlidePoint(point.cgPoint.applying(transform.inverted()))
    }

    /// Converts a shape-space point into slide space.
    public func slidePoint(fromShape point: SlidePoint) -> SlidePoint {
        SlidePoint(point.cgPoint.applying(transform))
    }
}
