import CoreGraphics
import Foundation

/// The chart's numbers as the layout reads them: every series as long as the labels, labels and names on one line,
/// and only finite numbers no further from zero than `limit`, so sums, stacks and axis spans stay finite.
struct ChartRows {
    struct Series {
        var name: String
        var values: [Double?]
        var color: ChartColor
    }

    let count: Int
    let labels: [String]
    /// The labels read as numbers ("12", "-3.5", "1,250"), for scatter charts' horizontal axis; nil for text and
    /// blank labels.
    let labelValues: [Double?]
    let series: [Series]

    static let limit = 1e300

    init(_ chart: Chart) {
        let data = chart.data
        let count = data.rowCount
        self.count = count
        var labels = data.labels
        if labels.contains(where: ChartRows.hasLineBreak) { labels = labels.map(ChartRows.oneLine) }
        if labels.count < count { labels += [String](repeating: "", count: count - labels.count) }
        self.labels = labels
        labelValues = labels.map(ChartRows.number)
        series = data.series.enumerated().map { index, series in
            var values = series.values
            if values.count < count { values += [Double?](repeating: nil, count: count - values.count) }
            if values.contains(where: { $0.map { !$0.isFinite || abs($0) > ChartRows.limit } ?? false }) {
                values = values.map { $0.flatMap { $0.isFinite ? ChartRows.clamped($0) : nil } }
            }
            return Series(name: ChartRows.oneLine(series.name), values: values, color: ChartColor(chart.color(ofSeries: index)))
        }
    }

    var isEmpty: Bool { count == 0 || series.allSatisfy { $0.values.allSatisfy { $0 == nil } } }

    static func clamped(_ value: Double) -> Double { Swift.min(Swift.max(value, -limit), limit) }

    static func hasLineBreak(_ text: String) -> Bool { text.utf8.contains { $0 == 10 || $0 == 13 } }

    static func oneLine(_ text: String) -> String {
        guard hasLineBreak(text) else { return text }
        return text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// A label as a number: plain ("12", "-3.5", "1e6") or with thousands separators three digits apart ("1,250.5").
    static func number(_ label: String) -> Double? {
        // Most labels are words: turn them away before trimming and parsing.
        guard let first = label.utf8.first(where: { $0 != 0x20 && $0 != 0x09 }),
              (0x30...0x39).contains(first) || first == 0x2D || first == 0x2B || first == 0x2E else { return nil }
        let text = label.trimmingCharacters(in: .whitespaces)
        if let value = Double(text) { return value.isFinite ? clamped(value) : nil }
        guard text.contains(",") else { return nil }
        func isDigits(_ part: Substring) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (0x30...0x39).contains($0) } }
        var body = Substring(text)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        let parts = body.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count > 1, let head = parts.first, head.count <= 3, isDigits(head) else { return nil }
        for (index, part) in parts.enumerated().dropFirst() {
            let digits = part.prefix { $0 != "." }
            guard digits.count == 3, isDigits(digits) else { return nil }
            if digits.count < part.count {
                guard index == parts.count - 1, isDigits(part.dropFirst(4)) else { return nil }
            }
        }
        guard let value = Double(text.replacingOccurrences(of: ",", with: "")), value.isFinite else { return nil }
        return clamped(value)
    }
}

/// A rectangle being divided up: the space left for the plot as the title, legend and labels take theirs.
struct ChartFrame {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    var width: Double { Swift.max(0, right - left) }
    var height: Double { Swift.max(0, bottom - top) }
    var midX: Double { (left + right) / 2 }
    var midY: Double { (top + bottom) / 2 }
}

/// The title at the top left, measured before the rest is laid out.
struct ChartTitleBlock {
    var title = ""
    var baseline = 0.0
    /// Where the content below may start.
    var bottom = 0.0
    var isEmpty: Bool { title.isEmpty }
}

struct ChartLegendEntry {
    var text: String
    var color: ChartColor
}

/// Where a legend ends up once Auto is decided.
enum ChartLegendPlacement {
    case none, top, bottom, left, right
}

/// Legend entries placed in rows: one entry per row at the left or right, rows of entries above or below the plot.
struct ChartLegendLayout {
    struct Item {
        var text: String
        var color: ChartColor
        var x: Double
        var row: Int
        var marker: Bool
    }

    var placement: ChartLegendPlacement
    var items: [Item] = []
    var rowWidths: [Double] = []
    var width = 0.0
    var height = 0.0
    var rowPitch = 0.0
    /// Where the legend's box starts, when the frame decided it (side legends' x, top and bottom legends' y).
    var originX = 0.0
    var originY = 0.0
}

/// Turns a chart into a scene: the layout and the marks, before any drawing. Sizes are in points; sizes in
/// pixels are multiplied by `style.scale`.
struct ChartComposer {
    let chart: Chart
    let rows: ChartRows
    let style: ChartStyle
    let width: Double
    let height: Double
    let engine = ChartTextEngine.shared
    var scene: ChartScene

    static func scene(for chart: Chart, size: CGSize) -> ChartScene {
        var composer = ChartComposer(chart: chart, size: size)
        composer.compose()
        return composer.scene
    }

    init(chart: Chart, size: CGSize) {
        self.chart = chart
        rows = ChartRows(chart)
        style = ChartStyle(chart: chart, size: size)
        width = Double(size.width)
        height = Double(size.height)
        scene = ChartScene(size: size, background: style.background, svgFontFamily: style.svgFontFamily)
    }

    /// The longest side a chart is laid out at; bigger ones (no slide comes close) get only their background, so
    /// layout arithmetic stays in range.
    static let maximumSide = 100_000.0

    mutating func compose() {
        guard width >= 4, height >= 4, width <= ChartComposer.maximumSide, height <= ChartComposer.maximumSide else { return }
        let titles = titleBlock()
        if chart.kind.isPie {
            composePie(titles)
        } else if rows.isEmpty {
            emitEmpty(titles)
        } else {
            composeCartesian(titles)
        }
    }

    // MARK: Title

    func titleBlock() -> ChartTitleBlock {
        var block = ChartTitleBlock()
        block.title = ChartRows.oneLine(chart.title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !block.title.isEmpty else {
            block.bottom = style.padding
            return block
        }
        let metrics = engine.metrics(style.titleFont)
        block.baseline = style.padding + metrics.ascent
        block.bottom = style.padding + metrics.height + style.titleGap
        return block
    }

    /// Draws the title starting at `x` (the plot's left edge), moved left when it would run off the chart and cut
    /// short when even that isn't enough.
    mutating func emitTitle(_ block: ChartTitleBlock, x preferredX: Double) {
        guard !block.isEmpty else { return }
        let titleWidth = engine.width(block.title, style.titleFont)
        let x = Swift.max(style.padding, Swift.min(preferredX, width - style.padding - titleWidth))
        let text = engine.truncated(block.title, style.titleFont, maxWidth: width - style.padding - x)
        scene.text(ChartText(string: text, font: style.titleFont, color: style.titleColor, x: x, y: block.baseline))
    }

    // MARK: Empty charts

    /// An empty chart: the title, and a short gray message in the middle.
    mutating func emitEmpty(_ titles: ChartTitleBlock) {
        emitTitle(titles, x: style.padding)
        let metrics = engine.metrics(style.messageFont)
        let middle = (titles.bottom + height - style.padding) / 2
        scene.text(ChartText(string: "No data", font: style.messageFont, color: style.messageColor,
                             x: width / 2, y: middle + metrics.middle, anchor: .middle))
    }

    // MARK: Legends

    /// Where the legend goes. Auto: at the right for pie charts and for charts with several series, none for a
    /// single series (the title and axis titles name it). Charts too narrow for a legend at the right (360 of
    /// chart pixels) put it on top instead, or below for pie charts.
    func legendPlacement(entryCount: Int, pie: Bool) -> ChartLegendPlacement {
        guard entryCount > 0 else { return .none }
        switch chart.legend {
        case .none: return .none
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case .auto:
            if !pie, entryCount < 2 { return .none }
            if width < 360 * style.scale { return pie ? .bottom : .top }
            return .right
        }
    }

    /// Lays out the legend and takes its space from `frame`.
    mutating func reserveLegend(_ entries: [ChartLegendEntry], placement: ChartLegendPlacement, frame: inout ChartFrame) -> ChartLegendLayout? {
        guard !entries.isEmpty else { return nil }
        let gap = 16 * style.scale
        switch placement {
        case .none:
            return nil
        case .right, .left:
            let maxWidth = Swift.min(Swift.max(90 * style.scale, width * 0.3), frame.width * 0.45)
            var layout = verticalLegend(entries, maxWidth: maxWidth, maxHeight: frame.height)
            layout.placement = placement
            if placement == .right {
                frame.right -= layout.width + gap
                layout.originX = frame.right + gap
            } else {
                layout.originX = frame.left
                frame.left += layout.width + gap
            }
            return layout
        case .top:
            var layout = horizontalLegend(entries, maxWidth: frame.width, maxRows: 2)
            layout.placement = .top
            layout.originY = frame.top
            frame.top += layout.height + 12 * style.scale
            return layout
        case .bottom:
            var layout = horizontalLegend(entries, maxWidth: frame.width, maxRows: 2)
            layout.placement = .bottom
            frame.bottom -= layout.height
            layout.originY = frame.bottom
            frame.bottom -= 12 * style.scale
            return layout
        }
    }

    var markerSpace: Double { style.markerSize + 6 * style.scale }

    func verticalLegend(_ entries: [ChartLegendEntry], maxWidth: Double, maxHeight: Double) -> ChartLegendLayout {
        let font = style.legendFont
        let metrics = engine.metrics(font)
        let pitch = metrics.height + 8 * style.scale
        let fit = Swift.max(1, Int((maxHeight - metrics.height) / pitch) + 1)
        let overflow = entries.count > fit
        let shown = overflow ? Array(entries.prefix(Swift.max(0, fit - 1))) : entries
        var layout = ChartLegendLayout(placement: .right)
        layout.rowPitch = pitch
        var widest = 0.0
        for (row, entry) in shown.enumerated() {
            let text = engine.truncated(entry.text, font, maxWidth: Swift.max(0, maxWidth - markerSpace))
            widest = Swift.max(widest, engine.width(text, font))
            layout.items.append(.init(text: text, color: entry.color, x: 0, row: row, marker: true))
        }
        if overflow {
            layout.items.append(.init(text: "…", color: style.legendColor, x: markerSpace, row: shown.count, marker: false))
        }
        layout.width = markerSpace + widest
        layout.height = layout.items.isEmpty ? 0 : Double(layout.items.count - 1) * pitch + metrics.height
        layout.rowWidths = layout.items.map { _ in layout.width }
        return layout
    }

    func horizontalLegend(_ entries: [ChartLegendEntry], maxWidth: Double, maxRows: Int) -> ChartLegendLayout {
        let font = style.legendFont
        let metrics = engine.metrics(font)
        let pitch = metrics.height + 6 * style.scale
        let spacing = 16 * style.scale
        var layout = ChartLegendLayout(placement: .top)
        layout.rowPitch = pitch
        var x = 0.0, row = 0
        var rowWidths: [Double] = [0]
        for (index, entry) in entries.enumerated() {
            var text = entry.text
            var itemWidth = markerSpace + engine.width(text, font)
            if itemWidth > maxWidth {
                text = engine.truncated(text, font, maxWidth: Swift.max(0, maxWidth - markerSpace))
                itemWidth = markerSpace + engine.width(text, font)
            }
            if x > 0, x + itemWidth > maxWidth {
                if row + 1 >= maxRows {
                    // No more rows: end the last one with an ellipsis.
                    let ellipsisWidth = engine.width("…", font)
                    if x + ellipsisWidth > maxWidth, !layout.items.isEmpty, index > 0 {
                        layout.items.removeLast()
                        x = layout.items.last(where: { $0.row == row }).map { $0.x + markerSpace + engine.width($0.text, font) + spacing } ?? 0
                    }
                    layout.items.append(.init(text: "…", color: style.legendColor, x: x, row: row, marker: false))
                    rowWidths[row] = x + ellipsisWidth
                    break
                }
                row += 1
                x = 0
                rowWidths.append(0)
            }
            layout.items.append(.init(text: text, color: entry.color, x: x, row: row, marker: true))
            rowWidths[row] = x + itemWidth
            x += itemWidth + spacing
        }
        layout.rowWidths = rowWidths
        layout.width = rowWidths.max() ?? 0
        layout.height = Double(rowWidths.count - 1) * pitch + metrics.height
        return layout
    }

    /// Draws a legend with its box's top-left corner at (`x`, `y`); with `centerWidth`, each row is centered in that
    /// width instead.
    mutating func emitLegend(_ layout: ChartLegendLayout, x: Double, y: Double, centerWidth: Double? = nil) {
        let font = style.legendFont
        let metrics = engine.metrics(font)
        let radius = style.markerSize / 2
        for item in layout.items {
            var left = x + item.x
            if let centerWidth, item.row < layout.rowWidths.count {
                left += Swift.max(0, (centerWidth - layout.rowWidths[item.row]) / 2)
            }
            let baseline = y + Double(item.row) * layout.rowPitch + metrics.ascent
            if item.marker {
                let middle = baseline - metrics.middle
                scene.fill(CGPath(ellipseIn: CGRect(x: left, y: middle - radius, width: 2 * radius, height: 2 * radius), transform: nil), item.color)
                scene.text(ChartText(string: item.text, font: font, color: style.legendColor, x: left + markerSpace, y: baseline))
            } else {
                scene.text(ChartText(string: item.text, font: font, color: style.legendColor, x: left, y: baseline))
            }
        }
    }

    /// Draws a reserved legend next to `plot` (the plot area, or the pie's bounds).
    mutating func emitLegend(_ layout: ChartLegendLayout, plot: CGRect, centered: Bool) {
        switch layout.placement {
        case .none:
            break
        case .right, .left:
            emitLegend(layout, x: layout.originX, y: Double(plot.minY))
        case .top, .bottom:
            if centered {
                emitLegend(layout, x: Double(plot.minX), y: layout.originY, centerWidth: Double(plot.width))
            } else {
                let x = Swift.min(Double(plot.minX), Swift.max(style.padding, width - style.padding - layout.width))
                emitLegend(layout, x: x, y: layout.originY)
            }
        }
    }
}
