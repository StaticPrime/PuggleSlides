import Foundation

/// Inverts a preset's guides numerically: finds the adjust values that put an adjust handle where it was dragged.
///
/// ahXY handles match the drag point's x (gdRefX) and y (gdRefY); ahPolar handles match its angle (gdRefAng) and
/// distance (gdRefR) from the shape's center. Each axis is a one-dimensional search over the handle's min…max:
/// sampling finds the brackets, bisection the exact value; two-axis handles alternate until they settle.
enum AdjustHandleSolver {
    /// How close (in points, or radians for angles) counts as the same position.
    static let tolerance = 1e-7
    static let samples = 96

    /// The adjust values (in `definition.adjusts` order) after dragging `handle` to `target`, relative to the frame.
    static func solve(_ definition: PresetShapeDefinition, handle: PresetShapeDefinition.Handle, width: Double,
                      height: Double, start: [Double], target: (x: Double, y: Double)) -> [Double] {
        var values = start
        let center = (x: width / 2, y: height / 2)
        let rounds = handle.axes.count > 1 ? 4 : 1
        for _ in 0..<rounds {
            var changed = false
            for axis in handle.axes {
                let guides = definition.evaluate(width: width, height: height, adjustValues: values)
                var lower = axis.minimum?.value(in: guides) ?? -2_147_483_647
                var upper = axis.maximum?.value(in: guides) ?? 2_147_483_647
                if lower > upper { swap(&lower, &upper) }
                let goal = measure(axis.role, target, center: center)
                let current = values[axis.adjust]
                let solved = solve(lower: lower, upper: upper, current: current) { candidate in
                    var trial = values
                    trial[axis.adjust] = candidate
                    let guides = definition.evaluate(width: width, height: height, adjustValues: trial)
                    let position = (x: handle.x.value(in: guides), y: handle.y.value(in: guides))
                    return difference(axis.role, measure(axis.role, position, center: center), goal)
                }
                if solved != current {
                    values[axis.adjust] = solved
                    changed = true
                }
            }
            if !changed { break }
        }
        return values
    }

    static func measure(_ role: PresetShapeDefinition.AxisRole, _ point: (x: Double, y: Double),
                        center: (x: Double, y: Double)) -> Double {
        switch role {
        case .x: point.x
        case .y: point.y
        case .angle: atan2(point.y - center.y, point.x - center.x)
        case .radius: hypot(point.x - center.x, point.y - center.y)
        }
    }

    static func difference(_ role: PresetShapeDefinition.AxisRole, _ value: Double, _ goal: Double) -> Double {
        guard role == .angle else { return value - goal }
        var delta = (value - goal).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta <= -.pi { delta += 2 * .pi }
        return delta
    }

    /// The value in lower…upper whose residual is nearest zero, preferring `current` and then values near it.
    static func solve(lower: Double, upper: Double, current: Double, residual: (Double) -> Double) -> Double {
        if abs(residual(current)) <= tolerance { return current }
        let clamped = min(max(current, lower), upper)
        var best = (value: clamped, error: abs(residual(clamped)))
        func consider(_ value: Double, _ error: Double) {
            if error < best.error - tolerance
                || (abs(error - best.error) <= tolerance && abs(value - current) < abs(best.value - current)) {
                best = (value, error)
            }
        }
        guard upper > lower else { return best.value }

        let step = (upper - lower) / Double(samples)
        var previous = (value: lower, residual: residual(lower))
        consider(previous.value, abs(previous.residual))
        for index in 1...samples {
            let value = index == samples ? upper : lower + step * Double(index)
            let sample = (value: value, residual: residual(value))
            consider(sample.value, abs(sample.residual))
            if previous.residual * sample.residual < 0 {
                // A sign change: bisect to the crossing (a root, or a jump such as an angle wrapping around).
                var low = previous, high = sample
                var iterations = 0
                while high.value - low.value > 1e-4, iterations < 100 {
                    let middle = (low.value + high.value) / 2
                    guard middle > low.value, middle < high.value else { break }
                    let probe = (value: middle, residual: residual(middle))
                    if (probe.residual < 0) == (low.residual < 0) { low = probe } else { high = probe }
                    iterations += 1
                }
                let root = abs(low.residual) <= abs(high.residual) ? low : high
                consider(root.value, abs(root.residual))
            }
            previous = sample
        }

        if best.error > tolerance {
            // No exact solution: the closest approach lies within a step of the best sample.
            var low = max(lower, best.value - step), high = min(upper, best.value + step)
            let ratio = (5.0.squareRoot() - 1) / 2
            for _ in 0..<60 {
                let a = high - ratio * (high - low), b = low + ratio * (high - low)
                if abs(residual(a)) <= abs(residual(b)) { high = b } else { low = a }
            }
            let value = (low + high) / 2
            consider(value, abs(residual(value)))
        }
        return best.value
    }
}
