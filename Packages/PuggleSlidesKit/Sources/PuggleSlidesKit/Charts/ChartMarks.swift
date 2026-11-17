import CoreGraphics
import Foundation

/// Lines, areas and points, and the data labels of vertical charts.
extension ChartComposer {
    /// An area's translucent fill, the line on top to stroke, and (for dense runs) the line as shapes to fill.
    struct AreaPaths {
        var fill = CGMutablePath()
        var line = CGMutablePath()
        var denseLine = CGMutablePath()
    }

    /// Splits a series into runs of points between gaps.
    func runs(_ values: [Double?], x: (Int) -> Double?, y: (Double) -> Double) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for index in 0..<rows.count {
            if let value = values[index], let px = x(index) {
                current.append(CGPoint(x: px, y: y(value)))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// The paths of an area series. Unstacked areas fill down to `baseline` (zero, or the axis end nearest to it);
    /// stacked ones fill down to the series below.
    func areaPaths(_ item: PlotSeries, baseline: Double, x: (Int) -> Double?, y: (Double) -> Double, plotWidth: Double) -> AreaPaths {
        let paths = AreaPaths()
        if let bases = item.bases {
            // A band from the series below to this one's running total.
            var tops: [CGPoint] = [], bottoms: [CGPoint] = []
            tops.reserveCapacity(rows.count)
            bottoms.reserveCapacity(rows.count)
            for index in 0..<rows.count {
                guard let px = x(index), let top = item.tops[index] else { continue }
                tops.append(CGPoint(x: px, y: y(top)))
                bottoms.append(CGPoint(x: px, y: y(bases[index])))
            }
            guard !tops.isEmpty else { return paths }
            if ChartComposer.isDense(tops.count, width: plotWidth) {
                let upper = ChartComposer.envelopes(tops), lower = ChartComposer.envelopes(bottoms)
                paths.fill.addLines(between: upper.map { CGPoint(x: Double($0.column) + 0.5, y: $0.top) })
                for column in lower.reversed() { paths.fill.addLine(to: CGPoint(x: Double(column.column) + 0.5, y: column.bottom)) }
                paths.fill.closeSubpath()
                ChartComposer.addDenseLine(upper, width: item.lineWidth, to: paths.denseLine)
            } else {
                paths.fill.addLines(between: tops)
                for point in bottoms.reversed() { paths.fill.addLine(to: point) }
                paths.fill.closeSubpath()
                paths.line.addLines(between: tops)
            }
        } else {
            let base = y(baseline)
            for run in runs(item.tops, x: x, y: y) {
                guard let first = run.first, let last = run.last else { continue }
                if ChartComposer.isDense(run.count, width: plotWidth) {
                    let columns = ChartComposer.envelopes(run)
                    paths.fill.move(to: CGPoint(x: Double(columns[0].column) + 0.5, y: base))
                    for column in columns { paths.fill.addLine(to: CGPoint(x: Double(column.column) + 0.5, y: column.top)) }
                    paths.fill.addLine(to: CGPoint(x: Double(columns[columns.count - 1].column) + 0.5, y: base))
                    paths.fill.closeSubpath()
                    ChartComposer.addDenseLine(columns, width: item.lineWidth, to: paths.denseLine)
                } else {
                    paths.fill.move(to: CGPoint(x: first.x, y: base))
                    for point in run { paths.fill.addLine(to: point) }
                    paths.fill.addLine(to: CGPoint(x: last.x, y: base))
                    paths.fill.closeSubpath()
                    paths.line.addLines(between: run)
                }
            }
        }
        return paths
    }

    mutating func drawLine(_ item: PlotSeries, x: (Int) -> Double?, y: (Double) -> Double, plotWidth: Double) {
        let path = CGMutablePath()
        let denseLine = CGMutablePath()
        var points: [CGPoint] = []
        var lonePoints: [CGPoint] = []
        let pointRadius = item.pointSize / 2
        for run in runs(item.tops, x: x, y: y) {
            if item.lineWidth > 0 {
                if run.count == 1 {
                    // A lone point between gaps would be invisible as a line.
                    if pointRadius <= 0 { lonePoints.append(run[0]) }
                } else if ChartComposer.isDense(run.count, width: plotWidth) {
                    ChartComposer.addDenseLine(ChartComposer.envelopes(run), width: item.lineWidth, to: denseLine)
                } else if item.smooth, run.count > 2 {
                    ChartComposer.addSmoothCurve(run, to: path)
                } else {
                    path.addLines(between: run)
                }
            }
            if pointRadius > 0 { points.append(contentsOf: run) }
        }
        scene.stroke(path, item.color, width: item.lineWidth)
        scene.fill(denseLine, item.color)
        scene.dots(lonePoints, radius: Swift.max(2.5 * style.scale, item.lineWidth), item.color)
        scene.dots(points, radius: pointRadius, item.color)
    }

    /// One point-wide column of a dense run: its highest and lowest points, and where the run enters and leaves it.
    struct ColumnEnvelope {
        var column: Int
        var top: Double
        var bottom: Double
        var first: Double
        var last: Double
    }

    /// More than two points per point of width. Such runs draw from per-column envelopes: the same picture, without
    /// the thousands of overlapping segments that slow Core Graphics down.
    static func isDense(_ count: Int, width: Double) -> Bool { Double(count) > width * 2 + 8 }

    /// The envelope of each point-wide column a run of points (in x order) passes through.
    static func envelopes(_ points: [CGPoint]) -> [ColumnEnvelope] {
        var result: [ColumnEnvelope] = []
        guard let start = points.first else { return result }
        var current = ColumnEnvelope(column: Int(start.x.rounded(.down)), top: start.y, bottom: start.y, first: start.y, last: start.y)
        for point in points.dropFirst() {
            let column = Int(point.x.rounded(.down))
            if column != current.column {
                result.append(current)
                current = ColumnEnvelope(column: column, top: point.y, bottom: point.y, first: point.y, last: point.y)
            } else {
                current.top = Swift.min(current.top, point.y)
                current.bottom = Swift.max(current.bottom, point.y)
                current.last = point.y
            }
        }
        result.append(current)
        return result
    }

    /// A dense line as one band: along the columns' tops (and the steps in from the previous column) and back along
    /// their bottoms, widened by the line's thickness. A simple polygon without overlaps.
    static func addDenseLine(_ columns: [ColumnEnvelope], width lineWidth: Double, to path: CGMutablePath) {
        guard !columns.isEmpty, lineWidth > 0 else { return }
        let half = Swift.max(0.5, lineWidth / 2)
        var tops: [CGPoint] = [], bottoms: [CGPoint] = []
        tops.reserveCapacity(columns.count)
        bottoms.reserveCapacity(columns.count)
        var previousLast: Double?
        for column in columns {
            var top = column.top, bottom = column.bottom
            if let previousLast {
                top = Swift.min(top, previousLast)
                bottom = Swift.max(bottom, previousLast)
            }
            let x = Double(column.column) + 0.5
            tops.append(CGPoint(x: x, y: top - half))
            bottoms.append(CGPoint(x: x, y: bottom + half))
            previousLast = column.last
        }
        if tops.count == 1 {
            path.addRect(CGRect(x: tops[0].x - 0.5, y: tops[0].y, width: 1, height: bottoms[0].y - tops[0].y))
            return
        }
        path.addLines(between: tops)
        for point in bottoms.reversed() { path.addLine(to: point) }
        path.closeSubpath()
    }

    /// A smooth curve through the points (Catmull-Rom), for smooth lines.
    static func addSmoothCurve(_ points: [CGPoint], to path: CGMutablePath) {
        guard let start = points.first else { return }
        path.move(to: start)
        for index in 0..<(points.count - 1) {
            let p0 = points[Swift.max(0, index - 1)], p1 = points[index], p2 = points[index + 1], p3 = points[Swift.min(points.count - 1, index + 2)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }

    /// The text color that reads on a mark of `color`: white, or dark gray on light colors like yellow.
    func labelColor(on color: ChartColor) -> ChartColor {
        color.luminance > 0.7 ? ChartColor(hex: 0x222222) : style.sliceTextColor
    }

    /// Values above columns (below negative ones), centered in stacked segments when they fit, and above line and
    /// scatter points. Labels that would overlap the previous one are skipped.
    mutating func emitVerticalDataLabels(_ item: PlotSeries, baseline: Double, stacked: Bool, barWidth: Double,
                                         x: (Int) -> Double?, y: (Double) -> Double, plot: CGRect) {
        let font = style.dataLabelFont
        let metrics = engine.metrics(font)
        var lastRight = -Double.infinity
        for index in 0..<rows.count {
            guard let value = item.values[index], let top = item.tops[index], let px = x(index) else { continue }
            let yTop = y(top)
            let label = ChartNumberText.dataLabel(value)
            let labelWidth = engine.width(label, font)
            guard px - labelWidth / 2 >= lastRight + 2 * style.scale else { continue }
            var color = style.dataLabelColor
            var textBaseline: Double
            if item.mark == .column, stacked, let bases = item.bases {
                let yBase = y(bases[index])
                guard abs(yTop - yBase) >= metrics.height, labelWidth <= barWidth + 4 * style.scale else { continue }
                textBaseline = (yTop + yBase) / 2 + metrics.middle
                color = labelColor(on: item.color)
            } else if item.mark == .column, top >= baseline {
                textBaseline = yTop - 4 * style.scale - metrics.descent
            } else if item.mark == .column {
                textBaseline = yTop + 4 * style.scale + metrics.ascent
                // The category labels are below the plot: a label with no room under its column goes inside the
                // column's end instead, when the column is long enough to hold it.
                if textBaseline + metrics.descent > Double(plot.maxY), abs(yTop - y(baseline)) >= metrics.height + 8 * style.scale {
                    textBaseline = yTop - 4 * style.scale - metrics.descent
                    color = labelColor(on: item.color)
                }
            } else {
                textBaseline = yTop - Swift.max(4 * style.scale, item.pointSize / 2 + 3 * style.scale) - metrics.descent
            }
            textBaseline = Swift.min(Swift.max(textBaseline, Double(plot.minY) - metrics.descent), height - metrics.descent)
            scene.text(ChartText(string: label, font: font, color: color, x: px, y: textBaseline, anchor: .middle))
            lastRight = px + labelWidth / 2
        }
    }
}

/// Column or bar rectangles gathered into one path. With more than one per point of width, rectangles that start in
/// the same point are merged: the same picture, without thousands of overlapping shapes.
struct ChartRectBatch {
    let decimate: Bool
    let path = CGMutablePath()
    private var pending: CGRect?
    private var pendingBucket = Int.min

    init(decimate: Bool) {
        self.decimate = decimate
    }

    /// Adds `rect`, which starts at `bucket` along the category axis.
    mutating func add(_ rect: CGRect, bucket position: Double) {
        guard decimate else {
            path.addRect(rect)
            return
        }
        let bucket = Int(position.rounded(.down))
        if bucket == pendingBucket, let current = pending {
            pending = current.union(rect)
            return
        }
        if let current = pending { path.addRect(current) }
        pending = rect
        pendingBucket = bucket
    }

    func finish() -> CGPath {
        if let pending { path.addRect(pending) }
        return path
    }
}
