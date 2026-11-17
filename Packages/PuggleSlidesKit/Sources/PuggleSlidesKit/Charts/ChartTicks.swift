import Foundation

/// An axis' range and the values its gridlines and labels sit at.
struct ChartScale: Sendable {
    var lower: Double
    var upper: Double
    var ticks: [Double]
    /// The distance between ticks.
    var step: Double

    /// Where `value` falls between the ends: 0 at `lower`, 1 at `upper`.
    @inline(__always) func fraction(_ value: Double) -> Double {
        let span = upper - lower
        return span == 0 ? 0.5 : (value - lower) / span
    }

    /// Where columns, bars and areas start: zero, or the end of the axis nearest to it.
    var baseline: Double { Swift.min(Swift.max(0, lower), upper) }
}

/// "Nice" axis ticks: steps of 1, 2, 2.5 or 5 times a power of ten.
enum ChartTicks {
    static let mantissas: [Double] = [1, 2, 2.5, 5, 10]

    /// The smallest nice step that is at least `raw`.
    static func niceStep(atLeast raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        let power = pow(10, (log10(raw)).rounded(.down))
        for mantissa in mantissas where mantissa * power >= raw * (1 - 1e-12) {
            return mantissa * power
        }
        return 10 * power
    }

    /// Ticks covering `lower...upper` in about `intervals` nice steps. `fixedLower` and `fixedUpper` pin the ends
    /// (the axis minimum and maximum); ticks then fall on multiples of the step between them. Pinned ends the wrong
    /// way round are swapped, and a maximum equal to the minimum is left to the data.
    static func linear(lower dataLower: Double, upper dataUpper: Double, intervals: Int,
                       fixedLower requestedLower: Double? = nil, fixedUpper requestedUpper: Double? = nil) -> ChartScale {
        var fixedLower = requestedLower.flatMap { $0.isFinite ? $0 : nil }
        var fixedUpper = requestedUpper.flatMap { $0.isFinite ? $0 : nil }
        if let pinnedLower = fixedLower, let pinnedUpper = fixedUpper, pinnedLower >= pinnedUpper {
            if pinnedLower == pinnedUpper { fixedUpper = nil } else { (fixedLower, fixedUpper) = (pinnedUpper, pinnedLower) }
        }
        var low = fixedLower ?? dataLower
        var high = fixedUpper ?? dataUpper
        if !low.isFinite || !high.isFinite { (low, high) = (0, 1) }
        if low > high {
            if fixedLower != nil, fixedUpper == nil { high = low } else if fixedUpper != nil, fixedLower == nil { low = high } else { swap(&low, &high) }
        }
        if high - low <= Swift.max(abs(low), abs(high)) * 1e-12 {
            // One value: give it room around it.
            let room = low == 0 ? 1 : abs(low) * 0.1
            switch (fixedLower, fixedUpper) {
            case (nil, nil):
                if low == 0 { high = 1 } else { low -= room; high += room }
            case (_, nil): high = low + room
            case (nil, _): low = high - room
            default: high = low + room
            }
        }
        // The nice step at or above the even split, or the one below it when that comes closer to the wanted
        // number of intervals (ties go to the tighter fit).
        let target = Swift.max(1, intervals)
        let above = niceStep(atLeast: (high - low) / Double(target))
        let below = previousNiceStep(above)
        func span(_ step: Double) -> (count: Double, size: Double) {
            let first = fixedLower.map { $0 / step } ?? (low / step + 1e-9).rounded(.down)
            let last = fixedUpper.map { $0 / step } ?? (high / step - 1e-9).rounded(.up)
            return (last - first, (last - first) * step)
        }
        let (aboveSpan, belowSpan) = (span(above), span(below))
        let aboveMiss = abs(aboveSpan.count - Double(target)), belowMiss = abs(belowSpan.count - Double(target))
        let step = belowMiss < aboveMiss || (belowMiss == aboveMiss && belowSpan.size < aboveSpan.size - 1e-9 * above) ? below : above
        let lower = fixedLower ?? ((low / step + 1e-9).rounded(.down) * step)
        let upper = fixedUpper ?? ((high / step - 1e-9).rounded(.up) * step)
        return ChartScale(lower: lower, upper: upper, ticks: multiples(of: step, from: lower, to: upper), step: step)
    }

    /// The nice step just below `step` (itself nice): 5 → 2.5, 2.5 → 2, 2 → 1, 1 → 0.5.
    static func previousNiceStep(_ step: Double) -> Double {
        guard step.isFinite, step > 0 else { return 1 }
        let power = pow(10, (log10(step) + 1e-9).rounded(.down))
        let mantissa = step / power
        if mantissa > 4.9 { return 2.5 * power }
        if mantissa > 2.4 { return 2 * power }
        if mantissa > 1.9 { return power }
        return 0.5 * power
    }

    /// The axis of a 100% chart: 0 to 100% in quarters (or −100% to 100% in halves with negative values).
    static func percent(hasNegative: Bool, hasPositive: Bool) -> ChartScale {
        switch (hasNegative, hasPositive) {
        case (true, true): return ChartScale(lower: -1, upper: 1, ticks: [-1, -0.5, 0, 0.5, 1], step: 0.5)
        case (true, false): return ChartScale(lower: -1, upper: 0, ticks: [-1, -0.75, -0.5, -0.25, 0], step: 0.25)
        default: return ChartScale(lower: 0, upper: 1, ticks: [0, 0.25, 0.5, 0.75, 1], step: 0.25)
        }
    }

    /// Multiples of `step` from `lower` to `upper`, rounded to the step's decimals.
    static func multiples(of step: Double, from lower: Double, to upper: Double) -> [Double] {
        guard step > 0, step.isFinite, upper >= lower else { return [] }
        let decimals = self.decimals(of: step)
        var ticks: [Double] = []
        var index = (lower / step - 1e-9).rounded(.up)
        while index * step <= upper + step * 1e-9, ticks.count < 1000 {
            ticks.append(rounded(index * step, decimals: decimals))
            index += 1
        }
        return ticks
    }

    /// The most decimals `decimals(of:)` looks for; steps that need more are written in scientific notation.
    static let maximumDecimals = 12

    /// The decimals needed to write multiples of `step` exactly (0.25 → 2), at most `maximumDecimals`. The
    /// tolerance is relative, so steps far below 1 aren't taken for whole numbers.
    static func decimals(of step: Double) -> Int {
        guard step > 0, step.isFinite else { return 0 }
        var decimals = 0
        var scaled = step
        while decimals < maximumDecimals, abs(scaled - scaled.rounded()) > 1e-6 * abs(scaled) {
            scaled *= 10
            decimals += 1
        }
        return decimals
    }

    /// `value` rounded to `decimals`, which clears the float noise of multiplying a step (0.30000000000000004).
    /// Values whose step needs more decimals than `decimals(of:)` looks for are left alone, so tiny ticks stay apart.
    static func rounded(_ value: Double, decimals: Int) -> Double {
        guard decimals > 0 else { return value.rounded() == 0 ? 0 : value.rounded() }
        guard decimals < maximumDecimals else { return value }
        let factor = pow(10, Double(decimals))
        let result = (value * factor).rounded() / factor
        return result == 0 ? 0 : result
    }
}
