import CoreGraphics
import Foundation

/// Charts with axes: columns and bars (clustered, stacked, 100%), lines (straight or smooth), areas (plain, stacked,
/// 100%) and scatter charts.
///
/// Layout: value labels right-aligned left of the plot, category labels centered under their slots
/// (tilted 30° when text labels don't fit, thinned to every n-th when even that doesn't work), gridlines at the value
/// ticks and a dark line at zero. Scatter charts whose labels are all numbers get a continuous horizontal axis with
/// nice ticks and vertical gridlines; other charts give each label an equal slot. Runs of more than two points per
/// point of width are drawn from per-column envelopes, which look the same and stay fast with thousands of points.
extension ChartComposer {
    enum Mark { case column, line, area, scatter }
    enum Stacking { case none, stacked, percent }

    struct PlotSeries {
        var index: Int
        var name: String
        var color: ChartColor
        var mark: Mark
        var lineWidth: Double
        var pointSize: Double
        var smooth: Bool
        /// The values as given; data labels show these.
        var values: [Double?]
        /// Where each mark ends: the value, or the running total (a share for 100% charts) when stacked.
        var tops: [Double?]
        /// Where stacked marks start; nil when not stacked.
        var bases: [Double]?
    }

    static func stacking(of kind: ChartKind) -> Stacking {
        kind.isPercent ? .percent : (kind.isStacked ? .stacked : .none)
    }

    // MARK: Entry point

    mutating func composeCartesian(_ titles: ChartTitleBlock) {
        let stacking = ChartComposer.stacking(of: chart.kind)
        let series = plotSeries(stacking: stacking)
        var frame = ChartFrame(left: style.padding, top: titles.bottom, right: width - style.padding, bottom: height - style.padding)
        let entries = series.map { ChartLegendEntry(text: $0.name, color: $0.color) }
        let legend = reserveLegend(entries, placement: legendPlacement(entryCount: entries.count, pie: false), frame: &frame)

        let axisMetrics = engine.metrics(style.axisTitleFont)
        let horizontalTitle = ChartRows.oneLine(chart.horizontalAxisTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        let verticalTitle = ChartRows.oneLine(chart.verticalAxisTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        var horizontalTitleBaseline = 0.0
        var verticalTitleX = 0.0
        if !horizontalTitle.isEmpty {
            horizontalTitleBaseline = frame.bottom - axisMetrics.descent
            frame.bottom -= axisMetrics.height + style.labelGap
        }
        if !verticalTitle.isEmpty {
            verticalTitleX = frame.left + axisMetrics.ascent
            frame.left += axisMetrics.height + style.labelGap
        }
        // The top value label sticks out half a line above the plot.
        if titles.isEmpty, legend?.placement != .top {
            frame.top = Swift.max(frame.top, style.padding + engine.metrics(style.labelFont).height / 2)
        }

        let plot = chart.kind.isBar ? composeBars(series, stacking: stacking, frame: frame) : composeVertical(series, stacking: stacking, frame: frame)

        if !horizontalTitle.isEmpty {
            let text = engine.truncated(horizontalTitle, style.axisTitleFont, maxWidth: width - 2 * style.padding)
            let half = engine.width(text, style.axisTitleFont) / 2
            let x = Swift.min(Swift.max(Double(plot.midX), style.padding + half), width - style.padding - half)
            scene.text(ChartText(string: text, font: style.axisTitleFont, color: style.axisTitleColor, x: x, y: horizontalTitleBaseline, anchor: .middle))
        }
        if !verticalTitle.isEmpty {
            let text = engine.truncated(verticalTitle, style.axisTitleFont, maxWidth: Swift.max(Double(plot.height) + 40 * style.scale, height * 0.8))
            scene.text(ChartText(string: text, font: style.axisTitleFont, color: style.axisTitleColor,
                                 x: verticalTitleX, y: Double(plot.midY), anchor: .middle, angle: -90))
        }
        if let legend { emitLegend(legend, plot: plot, centered: legend.placement == .bottom) }
        emitTitle(titles, x: Double(plot.minX))
    }

    // MARK: Series

    func plotSeries(stacking: Stacking) -> [PlotSeries] {
        let mark: Mark
        switch chart.kind {
        case .line, .smoothLine: mark = .line
        case .area, .stackedArea, .percentArea: mark = .area
        case .scatter: mark = .scatter
        default: mark = .column
        }
        // 2 px lines and 7 px scatter points.
        let lineWidth = mark == .scatter ? 0 : 2 * style.scale
        let pointSize = mark == .scatter ? 7 * style.scale : 0
        var result = rows.series.enumerated().map { index, series in
            PlotSeries(index: index, name: series.name, color: series.color, mark: mark, lineWidth: lineWidth, pointSize: pointSize,
                       smooth: chart.kind == .smoothLine, values: series.values, tops: series.values, bases: nil)
        }
        if stacking != .none { stack(&result, percent: stacking == .percent) }
        return result
    }

    /// Stacks the series in order: columns and bars stack positive and negative values apart, areas keep one running
    /// total and treat gaps as zero. 100% charts stack shares of each label's total.
    func stack(_ series: inout [PlotSeries], percent: Bool) {
        let count = rows.count
        var positive = [Double](repeating: 0, count: count)
        var negative = [Double](repeating: 0, count: count)
        var totals = [Double](repeating: 0, count: count)
        if percent {
            for item in series {
                for index in 0..<count { if let value = item.values[index] { totals[index] += abs(value) } }
            }
        }
        for seriesIndex in series.indices {
            let areas = series[seriesIndex].mark == .area
            var bases = [Double](repeating: 0, count: count)
            var tops = [Double?](repeating: nil, count: count)
            for index in 0..<count {
                guard var value = series[seriesIndex].values[index] ?? (areas ? 0 : nil) else {
                    bases[index] = positive[index]
                    continue
                }
                if percent { value = totals[index] > 0 ? value / totals[index] : 0 }
                if areas || value >= 0 {
                    bases[index] = positive[index]
                    positive[index] += value
                    tops[index] = positive[index]
                } else {
                    bases[index] = negative[index]
                    negative[index] += value
                    tops[index] = negative[index]
                }
            }
            series[seriesIndex].bases = bases
            series[seriesIndex].tops = tops
        }
    }

    /// The values the value axis must show. Columns, bars and areas include zero; lines and scatter points include
    /// it when the data comes within its own spread of it.
    func valueRange(_ series: [PlotSeries], stacking: Stacking) -> (low: Double, high: Double)? {
        var low = Double.infinity, high = -Double.infinity
        var needsZero = stacking != .none
        for item in series {
            if item.mark == .column || item.mark == .area { needsZero = true }
            for index in 0..<rows.count {
                guard let top = item.tops[index] else { continue }
                low = Swift.min(low, top)
                high = Swift.max(high, top)
                if let bases = item.bases {
                    low = Swift.min(low, bases[index])
                    high = Swift.max(high, bases[index])
                }
            }
        }
        guard low <= high else { return nil }
        if needsZero {
            low = Swift.min(low, 0)
            high = Swift.max(high, 0)
        } else {
            let spread = high - low
            if low > 0, low <= spread { low = 0 } else if high < 0, -high <= spread { high = 0 }
        }
        return (low, high)
    }

    /// The value axis: 0–100% for 100% charts, otherwise nice ticks between the chart's minimum and maximum when
    /// it sets them.
    func valueScale(_ range: (low: Double, high: Double)?, intervals: Int, stacking: Stacking) -> ChartScale {
        if stacking == .percent {
            return ChartTicks.percent(hasNegative: (range?.low ?? 0) < -1e-12, hasPositive: (range?.high ?? 1) > 1e-12 || (range?.low ?? 0) >= 0)
        }
        let fixedLower = chart.verticalMinimum.flatMap { $0.isFinite ? ChartRows.clamped($0) : nil }
        let fixedUpper = chart.verticalMaximum.flatMap { $0.isFinite ? ChartRows.clamped($0) : nil }
        return ChartTicks.linear(lower: range?.low ?? 0, upper: range?.high ?? 1, intervals: intervals, fixedLower: fixedLower, fixedUpper: fixedUpper)
    }

    func valueLabels(_ scale: ChartScale, stacking: Stacking) -> [String] {
        if stacking == .percent { return scale.ticks.map(ChartNumberText.percentTick) }
        return ChartNumberText.tickLabels(scale.ticks, step: scale.step)
    }

    /// Whether marks may reach past the plot: the chart pins its value axis.
    var clipsToPlot: Bool { chart.verticalMinimum != nil || chart.verticalMaximum != nil }

    // MARK: Columns, lines, areas, scatter

    private mutating func composeVertical(_ series: [PlotSeries], stacking: Stacking, frame: ChartFrame) -> CGRect {
        let count = rows.count
        let labelFont = style.labelFont
        let metrics = engine.metrics(labelFont)
        let gap = style.labelGap
        let mode = xMode()
        let range = valueRange(series, stacking: stacking)

        let plotTop = frame.top
        var plotBottom = frame.bottom - (metrics.height + gap)
        var plotLeft = frame.left
        let plotRight = frame.right
        var scale = ChartTicks.linear(lower: 0, upper: 1, intervals: 5)
        var tickLabels: [String] = []
        var plan = XPlan()
        for pass in 0..<3 {
            let plotHeight = Swift.max(8, plotBottom - plotTop)
            let intervals = Swift.max(2, Swift.min(10, Int((plotHeight / (56 * style.gridScale)).rounded())))
            scale = valueScale(range, intervals: intervals, stacking: stacking)
            tickLabels = valueLabels(scale, stacking: stacking)
            let labelWidth = tickLabels.reduce(0) { Swift.max($0, engine.width($1, labelFont)) }
            plotLeft = frame.left + (labelWidth > 0 ? labelWidth + gap : 0)
            plan = planX(mode, plotWidth: Swift.max(1, plotRight - plotLeft), maxHeight: height * 0.3)
            let bottom = frame.bottom - (plan.height > 0 ? plan.height + gap : 0)
            let settled = abs(bottom - plotBottom) < 0.5
            plotBottom = bottom
            if settled || pass == 2 { break }
        }

        let plot = CGRect(x: plotLeft, y: plotTop, width: Swift.max(1, plotRight - plotLeft), height: Swift.max(1, plotBottom - plotTop))
        let minX = Double(plot.minX), maxX = Double(plot.maxX), minY = Double(plot.minY), maxY = Double(plot.maxY)
        let plotWidth = Double(plot.width), plotHeight = Double(plot.height)
        let valueScale = scale
        func y(_ value: Double) -> Double { maxY - valueScale.fraction(value) * plotHeight }
        let slot = plotWidth / Double(Swift.max(1, count))
        var continuous = false
        if case .continuous = mode { continuous = true }
        let xLower = plan.lower, xSpan = plan.upper - plan.lower == 0 ? 1 : plan.upper - plan.lower
        let labelValues = rows.labelValues
        func xOfValue(_ value: Double) -> Double { minX + (value - xLower) / xSpan * plotWidth }
        func x(_ index: Int) -> Double? {
            if continuous { return labelValues[index].map(xOfValue) }
            return minX + (Double(index) + 0.5) * slot
        }

        // Gridlines, at the value ticks (and the horizontal ticks of a continuous axis).
        let hairline = style.hairline
        if chart.showsGridlines {
            let path = CGMutablePath()
            for tick in valueScale.ticks {
                let position = y(tick)
                if position >= minY - 0.5, position <= maxY + 0.5 {
                    path.addRect(CGRect(x: minX, y: position - hairline / 2, width: plotWidth, height: hairline))
                }
            }
            if continuous {
                for tick in plan.ticks {
                    let position = xOfValue(tick)
                    if position >= minX - 0.5, position <= maxX + 0.5 {
                        path.addRect(CGRect(x: position - hairline / 2, y: minY, width: hairline, height: plotHeight))
                    }
                }
            }
            scene.fill(path, style.gridlineColor)
        }

        let clips = clipsToPlot
        if clips { scene.clip(plot.insetBy(dx: -12 * style.scale, dy: -1)) }

        // Areas under everything, then columns, the zero line, lines and points.
        let areas = series.filter { $0.mark == .area }.map { ($0, areaPaths($0, baseline: valueScale.baseline, x: x, y: y, plotWidth: plotWidth)) }
        for (item, paths) in areas { scene.fill(paths.fill, item.color.opacity(ChartStyle.areaOpacity)) }
        for (item, paths) in areas {
            scene.stroke(paths.line, item.color, width: item.lineWidth)
            scene.fill(paths.denseLine, item.color)
        }
        let columns = series.filter { $0.mark == .column }
        let groups = stacking == .none ? columns.count : 1
        let groupWidth = slot * ChartStyle.groupWidth
        let barWidth = Swift.max(groupWidth / Double(Swift.max(1, groups)), Swift.min(1, slot))
        func columnCenter(_ order: Int, _ index: Int) -> Double {
            let start = minX + (Double(index) + 0.5) * slot
            if stacking != .none || groups <= 1 { return start }
            return start - groupWidth / 2 + (Double(order) + 0.5) * barWidth
        }
        for (order, item) in columns.enumerated() {
            var rects = ChartRectBatch(decimate: slot < 1)
            for index in 0..<count {
                guard let top = item.tops[index] else { continue }
                let yTop = y(top), yBase = y(item.bases?[index] ?? valueScale.baseline)
                var left = columnCenter(order, index) - barWidth / 2
                var right = left + barWidth
                if barWidth >= 2 {
                    left = (left * 2).rounded() / 2
                    right = Swift.max(left + 0.5, (right * 2).rounded() / 2)
                }
                var rect = CGRect(x: left, y: Swift.min(yTop, yBase), width: right - left, height: abs(yTop - yBase))
                // Past a pinned end, columns stop at the plot's edge (the clip leaves room for line strokes).
                if clips { rect = rect.intersection(plot) }
                if !rect.isNull { rects.add(rect, bucket: left) }
            }
            scene.fill(rects.finish(), item.color)
        }
        if valueScale.lower <= 0, valueScale.upper >= 0 {
            scene.fill(CGRect(x: minX, y: y(0) - hairline / 2, width: plotWidth, height: hairline), style.baselineColor)
        }
        if continuous, plan.lower <= 0, plan.upper >= 0 {
            scene.fill(CGRect(x: xOfValue(0) - hairline / 2, y: minY, width: hairline, height: plotHeight), style.baselineColor)
        }
        for item in series where item.mark == .line || item.mark == .scatter {
            drawLine(item, x: x, y: y, plotWidth: plotWidth)
        }
        if clips { scene.endClip() }

        // Data labels.
        if chart.showsDataLabels {
            for item in series {
                let order = columns.firstIndex { $0.index == item.index } ?? 0
                emitVerticalDataLabels(item, baseline: valueScale.baseline, stacked: stacking != .none, barWidth: barWidth,
                                       x: { item.mark == .column ? columnCenter(order, $0) : x($0) }, y: y, plot: plot)
            }
        }

        // Value labels.
        for (index, tick) in valueScale.ticks.enumerated() {
            let position = y(tick)
            guard position >= minY - 0.5, position <= maxY + 0.5 else { continue }
            scene.text(ChartText(string: tickLabels[index], font: labelFont, color: style.verticalLabelColor,
                                 x: minX - gap, y: position + metrics.middle, anchor: .end))
        }

        // Horizontal axis labels.
        if continuous {
            for (index, tick) in plan.ticks.enumerated() where index < plan.labels.count {
                let position = xOfValue(tick)
                guard position >= minX - 1, position <= maxX + 1 else { continue }
                emitCenteredLabel(plan.labels[index], x: position, baseline: maxY + gap + metrics.ascent)
            }
        } else {
            emitCategoryLabels(plan, plotLeft: minX, slot: slot, top: maxY + gap)
        }
        return plot
    }
}
