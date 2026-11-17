import CoreGraphics
import Foundation

/// Pie and doughnut charts: the labels are the slices and the first series their sizes.
///
/// Slices start at 12 o'clock and run clockwise in row order, colored from the palette, with thin borders in the
/// background color between them. Zero, negative and empty values get no slice. Slices under
/// half a degree (1/720 of the pie) are combined into a gray "Other" slice at the end. Slices are labeled with their
/// share in white, inside the slice and only where the label fits.
extension ChartComposer {
    /// Slices smaller than this share of the pie go into "Other".
    static let sliceVisibilityThreshold = 1.0 / 720
    static let otherSliceColor = ChartColor(hex: 0xCCCCCC)
    /// The biggest doughnut hole, as a fraction of the radius, so a ring always shows.
    static let largestPieHole = 0.9

    struct PieSlice {
        var label: String
        var value: Double
        var color: ChartColor
    }

    mutating func composePie(_ titles: ChartTitleBlock) {
        let values = rows.series.first?.values ?? []
        let count = Swift.min(rows.count, values.count)
        var total = 0.0
        for index in 0..<count { if let value = values[index], value > 0 { total += value } }
        guard total > 0, total.isFinite else {
            emitEmpty(titles)
            return
        }
        var slices: [PieSlice] = []
        var other = 0.0
        for index in 0..<count {
            guard let value = values[index], value > 0 else { continue }
            if value / total < ChartComposer.sliceVisibilityThreshold {
                other += value
            } else {
                slices.append(PieSlice(label: rows.labels[index], value: value, color: ChartColor(chart.color(ofSlice: index))))
            }
        }
        if other > 0 { slices.append(PieSlice(label: "Other", value: other, color: ChartComposer.otherSliceColor)) }

        var frame = ChartFrame(left: style.padding, top: titles.bottom, right: width - style.padding, bottom: height - style.padding)
        let entries = slices.map { ChartLegendEntry(text: $0.label, color: $0.color) }
        let legend = reserveLegend(entries, placement: legendPlacement(entryCount: entries.count, pie: true), frame: &frame)

        let radius = Swift.max(2, Swift.min(frame.width, frame.height) / 2)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let cx = Double(center.x), cy = Double(center.y)
        let holeFraction = chart.pieHole.isFinite ? Swift.min(Swift.max(chart.pieHole, 0), ChartComposer.largestPieHole) : 0
        let hole = chart.kind == .donut ? radius * holeFraction : 0
        let font = style.sliceFont
        let metrics = engine.metrics(font)
        // One fill per slice, and borders as thin quadrilaterals on top: one path for many slices would slow Core
        // Graphics down where their edges meet at the center.
        var borders: [CGPath] = []
        var labels: [ChartText] = []
        var angle = -Double.pi / 2
        let halfBorder = 0.75 * style.scale
        for slice in slices {
            let sweep = slice.value / total * 2 * .pi
            scene.fill(ChartComposer.wedge(center: center, radius: radius, hole: hole, start: angle, end: angle + sweep), slice.color)
            if slices.count > 1 {
                let (dx, dy) = (cos(angle), sin(angle))
                let (nx, ny) = (-dy * halfBorder, dx * halfBorder)
                let inner = CGPoint(x: cx + dx * hole, y: cy + dy * hole), outer = CGPoint(x: cx + dx * (radius + 0.5), y: cy + dy * (radius + 0.5))
                let border = CGMutablePath()
                border.addLines(between: [CGPoint(x: inner.x + nx, y: inner.y + ny), CGPoint(x: outer.x + nx, y: outer.y + ny),
                                          CGPoint(x: outer.x - nx, y: outer.y - ny), CGPoint(x: inner.x - nx, y: inner.y - ny)])
                border.closeSubpath()
                borders.append(border)
            }
            let text = ChartNumberText.percent(slice.value / total)
            let middle = angle + sweep / 2
            let distance = slices.count == 1 && hole == 0 ? 0 : (hole > 0 ? (hole + radius) / 2 : radius * 0.62)
            let point = CGPoint(x: cx + cos(middle) * distance, y: cy + sin(middle) * distance)
            let textWidth = engine.width(text, font)
            if ChartComposer.box(width: textWidth + 2, height: metrics.ascent * 0.8 + 2, at: point, fitsIn: center,
                                 radius: radius, hole: hole, start: angle, end: angle + sweep) {
                labels.append(ChartText(string: text, font: font, color: style.sliceTextColor,
                                        x: Double(point.x), y: Double(point.y) + metrics.middle, anchor: .middle))
            }
            angle += sweep
        }
        for border in borders { scene.fill(border, style.background) }
        for label in labels { scene.text(label) }

        let pieBounds = CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius)
        if let legend {
            let across = legend.placement == .top || legend.placement == .bottom
            emitLegend(legend, plot: across ? CGRect(x: frame.left, y: frame.top, width: frame.width, height: frame.height) : pieBounds, centered: true)
        }
        emitTitle(titles, x: style.padding)
    }

    /// A slice from `start` to `end` (radians, clockwise from 3 o'clock as the y axis points down); a ring segment
    /// when `hole` is above zero.
    static func wedge(center: CGPoint, radius: Double, hole: Double, start: Double, end: Double) -> CGPath {
        let path = CGMutablePath()
        let full = end - start >= 2 * .pi - 1e-9
        let r = CGFloat(radius), h = CGFloat(hole)
        if full {
            path.move(to: CGPoint(x: center.x + r, y: center.y))
            path.addArc(center: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            path.closeSubpath()
            if hole > 0 {
                // The inner circle runs the other way, so it cuts a hole.
                path.move(to: CGPoint(x: center.x + h, y: center.y))
                path.addArc(center: center, radius: h, startAngle: 0, endAngle: -2 * .pi, clockwise: true)
                path.closeSubpath()
            }
            return path
        }
        if hole > 0 {
            path.addArc(center: center, radius: r, startAngle: CGFloat(start), endAngle: CGFloat(end), clockwise: false)
            path.addArc(center: center, radius: h, startAngle: CGFloat(end), endAngle: CGFloat(start), clockwise: true)
        } else {
            path.move(to: center)
            path.addArc(center: center, radius: r, startAngle: CGFloat(start), endAngle: CGFloat(end), clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    /// Whether a box centered at `point` lies inside a slice: its corners within the ring and the slice's angles.
    static func box(width: Double, height: Double, at point: CGPoint, fitsIn center: CGPoint, radius: Double, hole: Double,
                    start: Double, end: Double) -> Bool {
        let sweep = end - start
        for (dx, dy) in [(-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)] {
            let x = Double(point.x) + dx * width - Double(center.x)
            let y = Double(point.y) + dy * height - Double(center.y)
            let distance = (x * x + y * y).squareRoot()
            if distance > radius - 2 || distance < hole + 2 { return false }
            if sweep < 2 * .pi - 1e-9 {
                var angle = atan2(y, x)
                while angle < start { angle += 2 * .pi }
                while angle >= start + 2 * .pi { angle -= 2 * .pi }
                if angle > end { return false }
            }
        }
        return true
    }
}
