import CoreGraphics
import Foundation

/// Bar charts: categories down the left, values along the bottom, with vertical gridlines and a dark line at zero.
extension ChartComposer {
    mutating func composeBars(_ series: [PlotSeries], stacking: Stacking, frame: ChartFrame) -> CGRect {
        let count = rows.count
        let font = style.labelFont
        let metrics = engine.metrics(font)
        let gap = style.labelGap
        let range = valueRange(series, stacking: stacking)
        let plotTop = frame.top
        let plotBottom = frame.bottom - (metrics.height + gap)
        let labelWidth = Swift.min(widestLabel(rows.labels, font), Swift.max(60 * style.scale, width * 0.3))
        let plotLeft = frame.left + (labelWidth > 0 ? labelWidth + gap : 0)
        var plotRight = frame.right
        var scale = ChartTicks.linear(lower: 0, upper: 1, intervals: 4)
        var tickLabels: [String] = []
        var target = Swift.max(2, Swift.min(8, Int((plotRight - plotLeft) / (90 * style.gridScale))))
        for _ in 0..<6 {
            scale = valueScale(range, intervals: target, stacking: stacking)
            tickLabels = valueLabels(scale, stacking: stacking)
            let widest = tickLabels.reduce(0) { Swift.max($0, engine.width($1, font)) }
            // The last value label is centered on the plot's right edge: leave room for its right half.
            plotRight = frame.right - Swift.max(0, widest / 2 - style.padding / 2)
            let spacing = (plotRight - plotLeft) / Double(Swift.max(1, scale.ticks.count - 1))
            if widest + 12 * style.scale <= spacing || target <= 1 { break }
            target -= 1
        }
        let plot = CGRect(x: plotLeft, y: plotTop, width: Swift.max(1, plotRight - plotLeft), height: Swift.max(1, plotBottom - plotTop))
        let minX = Double(plot.minX), maxX = Double(plot.maxX), minY = Double(plot.minY), maxY = Double(plot.maxY)
        let plotWidth = Double(plot.width), plotHeight = Double(plot.height)
        let valueScale = scale
        func x(_ value: Double) -> Double { minX + valueScale.fraction(value) * plotWidth }
        let slot = plotHeight / Double(Swift.max(1, count))

        let hairline = style.hairline
        if chart.showsGridlines {
            let path = CGMutablePath()
            for tick in valueScale.ticks {
                let position = x(tick)
                if position >= minX - 0.5, position <= maxX + 0.5 {
                    path.addRect(CGRect(x: position - hairline / 2, y: minY, width: hairline, height: plotHeight))
                }
            }
            scene.fill(path, style.gridlineColor)
        }
        let clips = clipsToPlot
        if clips { scene.clip(plot.insetBy(dx: -1, dy: -12 * style.scale)) }
        let groups = stacking == .none ? series.count : 1
        let groupHeight = slot * ChartStyle.groupWidth
        let barHeight = Swift.max(groupHeight / Double(Swift.max(1, groups)), Swift.min(1, slot))
        func barCenter(_ order: Int, _ index: Int) -> Double {
            let center = minY + (Double(index) + 0.5) * slot
            if stacking != .none || groups <= 1 { return center }
            return center - groupHeight / 2 + (Double(order) + 0.5) * barHeight
        }
        for (order, item) in series.enumerated() {
            var rects = ChartRectBatch(decimate: slot < 1)
            for index in 0..<count {
                guard let top = item.tops[index] else { continue }
                let xTop = x(top), xBase = x(item.bases?[index] ?? valueScale.baseline)
                var upper = barCenter(order, index) - barHeight / 2
                var lower = upper + barHeight
                if barHeight >= 2 {
                    upper = (upper * 2).rounded() / 2
                    lower = Swift.max(upper + 0.5, (lower * 2).rounded() / 2)
                }
                var rect = CGRect(x: Swift.min(xTop, xBase), y: upper, width: abs(xTop - xBase), height: lower - upper)
                // Past a pinned end, bars stop at the plot's edge.
                if clips { rect = rect.intersection(plot) }
                if !rect.isNull { rects.add(rect, bucket: upper) }
            }
            scene.fill(rects.finish(), item.color)
        }
        if valueScale.lower <= 0, valueScale.upper >= 0 {
            scene.fill(CGRect(x: x(0) - hairline / 2, y: minY, width: hairline, height: plotHeight), style.baselineColor)
        }
        if clips { scene.endClip() }

        // Data labels past the bars' ends (inside stacked segments when they fit).
        if chart.showsDataLabels {
            let labelFont = style.dataLabelFont
            let labelMetrics = engine.metrics(labelFont)
            for (order, item) in series.enumerated() {
                var lastBottom = -Double.infinity
                for index in 0..<count {
                    guard let value = item.values[index], let top = item.tops[index] else { continue }
                    let xTop = x(top)
                    let center = barCenter(order, index)
                    guard center - labelMetrics.height / 2 >= lastBottom else { continue }
                    let label = ChartNumberText.dataLabel(value)
                    let textWidth = engine.width(label, labelFont)
                    if stacking != .none, let bases = item.bases {
                        let xBase = x(bases[index])
                        guard abs(xTop - xBase) >= textWidth + 4 * style.scale, barHeight >= labelMetrics.height else { continue }
                        scene.text(ChartText(string: label, font: labelFont, color: labelColor(on: item.color), x: (xTop + xBase) / 2,
                                             y: center + labelMetrics.middle, anchor: .middle))
                    } else {
                        // Past the bar's end; inside it when that would run into the category labels at the left or
                        // past the plot's right side, and the bar is long enough to hold it.
                        let positive = top >= valueScale.baseline
                        let room = positive ? frame.right + 8 * style.scale - xTop : xTop - minX
                        let inside = textWidth + 4 * style.scale > room && abs(xTop - x(valueScale.baseline)) >= textWidth + 8 * style.scale
                        let outward = positive != inside
                        scene.text(ChartText(string: label, font: labelFont, color: inside ? labelColor(on: item.color) : style.dataLabelColor,
                                             x: xTop + (outward ? 4 : -4) * style.scale, y: center + labelMetrics.middle,
                                             anchor: outward ? .start : .end))
                    }
                    lastBottom = center + labelMetrics.height / 2
                }
            }
        }

        // Category labels at the left, thinned when the bars are too thin for them.
        let every = slot >= metrics.height + 2 ? 1 : Int(((metrics.height + 2) / slot).rounded(.up))
        for index in stride(from: 0, to: count, by: Swift.max(1, every)) {
            let label = engine.truncated(rows.labels[index], font, maxWidth: labelWidth)
            scene.text(ChartText(string: label, font: font, color: style.verticalLabelColor, x: minX - gap,
                                 y: minY + (Double(index) + 0.5) * slot + metrics.middle, anchor: .end))
        }
        // Value labels under the plot.
        for (index, tick) in valueScale.ticks.enumerated() {
            let position = x(tick)
            guard position >= minX - 0.5, position <= maxX + 0.5 else { continue }
            emitCenteredLabel(tickLabels[index], x: position, baseline: maxY + gap + metrics.ascent)
        }
        return plot
    }
}
