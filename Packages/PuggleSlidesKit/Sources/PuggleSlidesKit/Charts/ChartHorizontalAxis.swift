import CoreGraphics
import Foundation

/// The horizontal axis of column, line, area and scatter charts: category labels centered under their slots, tilted
/// 30° when text labels don't fit and thinned to every n-th when even that doesn't work, or the nice ticks of a
/// continuous axis for scatter charts whose labels are all numbers. Bar charts measure and center their labels with
/// the same helpers.
extension ChartComposer {
    enum XMode {
        case categories
        /// Positions by label value; the ends widen to nice ticks.
        case continuous(lower: Double, upper: Double)
    }

    /// The horizontal axis' labels: categories (with thinning and tilt) or ticks of a continuous axis.
    struct XPlan {
        var height = 0.0
        var every = 1
        var slanted = false
        var maxTextWidth = 0.0
        var ticks: [Double] = []
        var labels: [String] = []
        var lower = 0.0
        var upper = 1.0
    }

    static let slantAngle = -30.0

    /// Text labels (not numbers) may tilt; numeric ones only thin out, like an axis.
    var labelsAreText: Bool {
        for index in 0..<rows.count where rows.labelValues[index] == nil && !rows.labels[index].isEmpty { return true }
        return false
    }

    func xMode() -> XMode {
        guard chart.kind == .scatter, rows.count > 0 else { return .categories }
        var low = Double.infinity, high = -Double.infinity
        for index in 0..<rows.count {
            if let value = rows.labelValues[index] {
                low = Swift.min(low, value)
                high = Swift.max(high, value)
            } else if !rows.labels[index].trimmingCharacters(in: .whitespaces).isEmpty {
                return .categories
            }
        }
        guard low <= high else { return .categories }
        return .continuous(lower: low, upper: high)
    }

    /// Category labels under their slots: every `plan.every`-th one, level or tilted.
    mutating func emitCategoryLabels(_ plan: XPlan, plotLeft: Double, slot: Double, top: Double) {
        let font = style.labelFont
        let metrics = engine.metrics(font)
        let radians = -ChartComposer.slantAngle * .pi / 180
        for index in stride(from: 0, to: rows.count, by: Swift.max(1, plan.every)) {
            let center = plotLeft + (Double(index) + 0.5) * slot
            if plan.slanted {
                // The label ends at its slot, its top corner at the axis, and is cut short rather than run off the
                // chart's left edge.
                let anchor = center + sin(radians) * metrics.ascent
                let room = (anchor - 2) / cos(radians)
                let label = engine.truncated(rows.labels[index], font, maxWidth: Swift.min(plan.maxTextWidth, room))
                scene.text(ChartText(string: label, font: font, color: style.horizontalLabelColor,
                                     x: anchor, y: top + cos(radians) * metrics.ascent,
                                     anchor: .end, angle: ChartComposer.slantAngle))
            } else {
                let label = engine.truncated(rows.labels[index], font, maxWidth: plan.maxTextWidth)
                emitCenteredLabel(label, x: center, baseline: top + metrics.ascent)
            }
        }
    }

    /// A horizontal axis label centered at `x`, kept inside the chart.
    mutating func emitCenteredLabel(_ label: String, x: Double, baseline: Double) {
        let font = style.labelFont
        let half = engine.width(label, font) / 2
        let position = Swift.min(Swift.max(x, half + 2), width - half - 2)
        scene.text(ChartText(string: label, font: font, color: style.horizontalLabelColor, x: position, y: baseline, anchor: .middle))
    }

    // MARK: Horizontal axis plans

    func planX(_ mode: XMode, plotWidth: Double, maxHeight: Double) -> XPlan {
        switch mode {
        case .categories:
            return planCategories(plotWidth: plotWidth, maxHeight: maxHeight)
        case .continuous(let lower, let upper):
            return planContinuous(lower: lower, upper: upper, plotWidth: plotWidth)
        }
    }

    /// Fits category labels: level when they fit their slots; tilted when they're text, every slot has room for a
    /// tilted line and the tilt keeps within `maxHeight`; otherwise level, showing every n-th label (tilted every
    /// n-th when that shows many more of a text axis' labels).
    func planCategories(plotWidth: Double, maxHeight: Double) -> XPlan {
        var plan = XPlan()
        let count = rows.count
        guard count > 0 else { return plan }
        let font = style.labelFont
        let metrics = engine.metrics(font)
        let slot = plotWidth / Double(count)
        let gap = 8 * style.scale
        let widest = widestLabel(rows.labels, font)
        guard widest > 0 else { return plan }
        plan.height = metrics.height
        plan.maxTextWidth = widest
        if widest + gap <= slot { return plan }

        let radians = -ChartComposer.slantAngle * .pi / 180
        let slantPitch = metrics.height / sin(radians)
        let maxSlantWidth = Swift.max(0, (maxHeight - metrics.height * cos(radians)) / sin(radians))
        let slantWidth = Swift.min(widest, maxSlantWidth)
        let slantHeight = slantWidth * sin(radians) + metrics.height * cos(radians)
        let canSlant = labelsAreText && maxSlantWidth >= 3 * metrics.height
        if canSlant, slot >= slantPitch {
            plan.slanted = true
            plan.maxTextWidth = slantWidth
            plan.height = slantHeight
            return plan
        }
        let capped = Swift.min(widest, Swift.max(plotWidth / 3, 40 * style.scale))
        let everyLevel = Swift.max(1, Int(((capped + gap) / slot).rounded(.up)))
        if canSlant {
            let everySlanted = Swift.max(1, Int((slantPitch / slot).rounded(.up)))
            if Double(everySlanted) * 1.5 < Double(everyLevel) {
                plan.slanted = true
                plan.every = everySlanted
                plan.maxTextWidth = slantWidth
                plan.height = slantHeight
                return plan
            }
        }
        plan.every = everyLevel
        plan.maxTextWidth = capped
        return plan
    }

    /// Ticks for a continuous axis: as many nice ticks as fit their labels, with the ends widened to ticks.
    func planContinuous(lower: Double, upper: Double, plotWidth: Double) -> XPlan {
        var plan = XPlan()
        let font = style.labelFont
        plan.height = engine.metrics(font).height
        var target = Swift.max(2, Swift.min(10, Int(plotWidth / (90 * style.gridScale))))
        for _ in 0..<6 {
            let scale = ChartTicks.linear(lower: lower, upper: upper, intervals: target)
            plan.ticks = scale.ticks
            plan.labels = ChartNumberText.tickLabels(scale.ticks, step: scale.step, grouping: false)
            plan.lower = scale.lower
            plan.upper = scale.upper
            let widest = plan.labels.reduce(0) { Swift.max($0, engine.width($1, font)) }
            let span = scale.upper - scale.lower > 0 ? scale.upper - scale.lower : 1
            var spacing = plotWidth
            for (first, second) in zip(scale.ticks, scale.ticks.dropFirst()) { spacing = Swift.min(spacing, (second - first) / span * plotWidth) }
            if widest + 12 * style.scale <= spacing || target <= 1 { break }
            target = Swift.max(1, Swift.min(target - 1, Int(Double(target) * spacing / (widest + 12 * style.scale))))
        }
        return plan
    }

    /// The widest label's width. Thousands of labels are sampled: only the longest ones by length are measured.
    func widestLabel(_ labels: [String], _ font: ChartFont) -> Double {
        if labels.count <= 400 { return labels.reduce(0) { Swift.max($0, engine.width($1, font)) } }
        var longest = 0
        for label in labels { longest = Swift.max(longest, label.utf8.count) }
        let threshold = longest * 3 / 4
        var candidates: [Int] = []
        for (index, label) in labels.enumerated() where label.utf8.count >= threshold { candidates.append(index) }
        let step = Swift.max(1, candidates.count / 400)
        var widest = 0.0
        for position in stride(from: 0, to: candidates.count, by: step) {
            widest = Swift.max(widest, engine.width(labels[candidates[position]], font))
        }
        return widest
    }
}
