import CoreGraphics
import CoreText
import Foundation

enum ChartTextAnchor: Sendable {
    case start, middle, end
}

/// One line of text, placed by its baseline.
struct ChartText {
    var string: String
    var font: ChartFont
    var color: ChartColor
    /// The anchor point on the baseline: its start, middle or end.
    var x: Double
    var y: Double
    var anchor: ChartTextAnchor = .start
    /// Rotation about the anchor in degrees; positive turns clockwise (the y axis points down).
    var angle: Double = 0
}

enum ChartItem {
    case fill(CGPath, ChartColor)
    case stroke(CGPath, ChartColor, width: Double)
    /// Round points (scatter points, lone line points), each filled on its own: Core Graphics slows down badly when
    /// one path holds thousands of overlapping shapes.
    case dots([CGPoint], radius: Double, ChartColor)
    case text(ChartText)
    /// Clips what follows to a rectangle until the matching `endClip`.
    case clip(CGRect)
    case endClip
}

/// A chart laid out and ready to draw, in points with the y axis pointing down. The same scene draws into a context
/// (screen, thumbnails, PDF, pictures) or writes SVG, so every output looks the same.
struct ChartScene {
    var size: CGSize
    var background: ChartColor
    /// The CSS font stack SVG output names.
    var svgFontFamily: String
    private(set) var items: [ChartItem] = []

    init(size: CGSize, background: ChartColor, svgFontFamily: String) {
        self.size = size
        self.background = background
        self.svgFontFamily = svgFontFamily
    }

    mutating func fill(_ path: CGPath, _ color: ChartColor) {
        guard !path.isEmpty, color.alpha > 0 else { return }
        items.append(.fill(path, color))
    }

    mutating func fill(_ rect: CGRect, _ color: ChartColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        fill(CGPath(rect: rect, transform: nil), color)
    }

    mutating func stroke(_ path: CGPath, _ color: ChartColor, width: Double) {
        guard !path.isEmpty, width > 0, color.alpha > 0 else { return }
        items.append(.stroke(path, color, width: width))
    }

    mutating func dots(_ points: [CGPoint], radius: Double, _ color: ChartColor) {
        guard !points.isEmpty, radius > 0, color.alpha > 0 else { return }
        items.append(.dots(points, radius: radius, color))
    }

    mutating func text(_ text: ChartText) {
        guard !text.string.isEmpty else { return }
        items.append(.text(text))
    }

    mutating func clip(_ rect: CGRect) { items.append(.clip(rect)) }
    mutating func endClip() { items.append(.endClip) }

    /// The strings of every text item, in drawing order.
    var strings: [String] {
        items.compactMap { item in
            if case .text(let text) = item { return text.string }
            return nil
        }
    }

    /// A unit circle as a 12-gon, pushed out a little so it covers about as much as the circle.
    static let dodecagon: [CGPoint] = (0..<12).map { index in
        let angle = Double(index) * .pi / 6
        let reach = 1 / cos(Double.pi / 12) * 0.985
        return CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
    }

    /// Draws the scene with its top-left corner at the origin of `context`, whose y axis points down. Text is drawn
    /// upright: Core Text lays glyphs out with y pointing up, so each line is drawn through a text matrix that flips
    /// it back. The text matrix isn't part of the graphics state, so it's put back by hand.
    func render(in context: CGContext) {
        let savedTextMatrix = context.textMatrix
        context.saveGState()
        context.setFillColor(background.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        let engine = ChartTextEngine.shared
        let upright = CGAffineTransform(scaleX: 1, y: -1)
        var clips = 0
        for item in items {
            switch item {
            case .fill(let path, let color):
                context.setFillColor(color.cgColor)
                context.addPath(path)
                context.fillPath()
            case .stroke(let path, let color, let width):
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(CGFloat(width))
                context.addPath(path)
                context.strokePath()
            case .dots(let points, let radius, let color):
                context.setFillColor(color.cgColor)
                let r = CGFloat(radius)
                if points.count <= 1500 {
                    for point in points { context.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)) }
                } else {
                    // Thousands of points: 12-gons draw twice as fast and look the same at this size.
                    let corners = ChartScene.dodecagon.map { CGPoint(x: $0.x * r, y: $0.y * r) }
                    var shape = corners
                    for point in points {
                        for index in corners.indices { shape[index] = CGPoint(x: point.x + corners[index].x, y: point.y + corners[index].y) }
                        context.beginPath()
                        context.addLines(between: shape)
                        context.closePath()
                        context.fillPath()
                    }
                }
            case .text(let text):
                let (line, width) = engine.line(text.string, text.font)
                let offset: Double
                switch text.anchor {
                case .start: offset = 0
                case .middle: offset = -width / 2
                case .end: offset = -width
                }
                context.setFillColor(text.color.cgColor)
                if text.angle == 0 {
                    context.textMatrix = upright
                    context.textPosition = CGPoint(x: text.x + offset, y: text.y)
                    CTLineDraw(line, context)
                } else {
                    context.saveGState()
                    context.translateBy(x: CGFloat(text.x), y: CGFloat(text.y))
                    context.rotate(by: CGFloat(text.angle * .pi / 180))
                    context.textMatrix = upright
                    context.textPosition = CGPoint(x: offset, y: 0)
                    CTLineDraw(line, context)
                    context.restoreGState()
                }
            case .clip(let rect):
                context.saveGState()
                context.clip(to: rect)
                clips += 1
            case .endClip:
                if clips > 0 {
                    context.restoreGState()
                    clips -= 1
                }
            }
        }
        while clips > 0 {
            context.restoreGState()
            clips -= 1
        }
        context.restoreGState()
        context.textMatrix = savedTextMatrix
    }
}
