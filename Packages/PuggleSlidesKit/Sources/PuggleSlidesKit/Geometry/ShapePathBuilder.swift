import CoreGraphics
import Foundation

/// Builds a Core Graphics path from DrawingML path commands given in a path's own coordinate space, which is
/// scaled to the shape's frame (so arcs are computed before scaling, as the path space defines them).
struct ShapePathBuilder {
    let path = CGMutablePath()
    private let originX: Double
    private let originY: Double
    private let scaleX: Double
    private let scaleY: Double
    /// The current point and the start of the current subpath, in path space.
    private(set) var current: (x: Double, y: Double)?
    private var subpathStart: (x: Double, y: Double)?
    private var subpathOpen = false

    init(origin: CGPoint, scaleX: Double, scaleY: Double) {
        originX = Double(origin.x)
        originY = Double(origin.y)
        self.scaleX = scaleX.isFinite ? scaleX : 1
        self.scaleY = scaleY.isFinite ? scaleY : 1
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: originX + x * scaleX, y: originY + y * scaleY)
    }

    mutating func move(_ x: Double, _ y: Double) {
        path.move(to: point(x, y))
        current = (x, y)
        subpathStart = (x, y)
        subpathOpen = true
    }

    /// Starts a subpath where drawing continues (after a close, or at the origin before any move).
    private mutating func ensureSubpath() {
        guard !subpathOpen else { return }
        let start = current ?? (0, 0)
        move(start.x, start.y)
    }

    mutating func line(_ x: Double, _ y: Double) {
        ensureSubpath()
        path.addLine(to: point(x, y))
        current = (x, y)
    }

    mutating func quadratic(_ x1: Double, _ y1: Double, _ x: Double, _ y: Double) {
        ensureSubpath()
        path.addQuadCurve(to: point(x, y), control: point(x1, y1))
        current = (x, y)
    }

    mutating func cubic(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        ensureSubpath()
        path.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
        current = (x, y)
    }

    /// DrawingML's arcTo: an arc of the ellipse with radii `widthRadius` × `heightRadius` placed so the current point
    /// lies on it at `start`, sweeping `sweep` (radians; positive is clockwise with y down). Angles are the visual
    /// angles of rays from the ellipse's center, as the preset guides compute them.
    mutating func arc(widthRadius: Double, heightRadius: Double, start: Double, sweep: Double) {
        ensureSubpath()
        let a = abs(widthRadius), b = abs(heightRadius)
        guard let from = current, start.isFinite, sweep.isFinite, a.isFinite, b.isFinite else { return }
        guard sweep != 0, a != 0 || b != 0 else { return }
        let startParameter = Self.parameter(a, b, start)
        let centerX = from.x - a * cos(startParameter)
        let centerY = from.y - b * sin(startParameter)
        let parameterSweep = Self.parameterSweep(a, b, start: start, sweep: sweep)
        let segments = max(1, Int((abs(parameterSweep) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let step = parameterSweep / Double(segments)
        let k = 4 / 3 * tan(step / 4)
        var t = startParameter
        var x0 = from.x, y0 = from.y
        for index in 0..<segments {
            let t1 = index == segments - 1 ? startParameter + parameterSweep : t + step
            let x3 = centerX + a * cos(t1), y3 = centerY + b * sin(t1)
            let c1x = x0 - k * a * sin(t), c1y = y0 + k * b * cos(t)
            let c2x = x3 + k * a * sin(t1), c2y = y3 - k * b * cos(t1)
            path.addCurve(to: point(x3, y3), control1: point(c1x, c1y), control2: point(c2x, c2y))
            t = t1
            x0 = x3
            y0 = y3
        }
        current = (x0, y0)
    }

    mutating func close() {
        guard subpathOpen else { return }
        path.closeSubpath()
        current = subpathStart
        subpathOpen = false
    }

    /// The ellipse parameter of the point at visual angle `angle`: the point is (a·cos t, b·sin t) from the center.
    static func parameter(_ a: Double, _ b: Double, _ angle: Double) -> Double {
        atan2(a * sin(angle), b * cos(angle))
    }

    /// The parameter sweep matching a visual sweep: same direction and end point, and a whole turn when the sweep
    /// is one or more (more turns would only retrace it).
    static func parameterSweep(_ a: Double, _ b: Double, start: Double, sweep: Double) -> Double {
        let turn = 2 * Double.pi
        let magnitude = abs(sweep)
        let wholeTurns = min((magnitude / turn).rounded(.down), 1)
        let remainder = magnitude.truncatingRemainder(dividingBy: turn)
        let sign: Double = sweep < 0 ? -1 : 1
        guard remainder > 1e-9 else { return sign * wholeTurns * turn }
        guard a != 0, b != 0 else {
            // A flat ellipse: the parameter jumps between 0 and π, so follow the visual sweep.
            return sign * (wholeTurns * turn + remainder)
        }
        var delta = parameter(a, b, start + sign * remainder) - parameter(a, b, start)
        if sign > 0 {
            while delta < 0 { delta += turn }
            while delta >= turn { delta -= turn }
        } else {
            while delta > 0 { delta -= turn }
            while delta <= -turn { delta += turn }
        }
        return delta + sign * wholeTurns * turn
    }
}
