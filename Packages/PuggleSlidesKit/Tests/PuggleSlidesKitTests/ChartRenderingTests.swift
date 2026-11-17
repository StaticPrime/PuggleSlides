import CoreGraphics
import Foundation
import Testing
@testable import PuggleSlidesKit

/// Charts, contexts and pixels for the chart tests.
enum ChartFixtures {
    /// Insert ▸ Chart's size: a 600 × 371 pixel chart in points.
    static let size = CGSize(width: 450, height: 278)
    static let small = CGSize(width: 200, height: 120)

    /// Month | Sales | Costs | Profit for a year: a typical chart.
    static var sales: ChartData {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return ChartData(labelHeading: "Month", labels: months, series: [
            ChartSeries(name: "Sales", values: [120, 135, 160, 150, 180, 210, 230, 220, 190, 170, 160, 200]),
            ChartSeries(name: "Costs", values: [80, 90, 95, 100, 110, 120, 130, 128, 115, 105, 100, 120]),
            ChartSeries(name: "Profit", values: [40, 45, 65, 50, 70, 90, 100, 92, 75, 65, 60, 80]),
        ])
    }

    /// `count` rows of two wavy series labeled "Item 1", "Item 2", … (or 1, 2, … when `numeric`).
    static func wave(_ count: Int, numeric: Bool = false) -> ChartData {
        ChartData(labelHeading: "Item", labels: (0..<count).map { numeric ? String($0 + 1) : "Item \($0 + 1)" },
                  series: (0..<2).map { series in
                      ChartSeries(name: "Series \(series + 1)", values: (0..<count).map { index in
                          100 + 50 * sin(Double(index + series * 7) / 9) + Double((index * 31) % 17)
                      })
                  })
    }

    /// A transparent bitmap context of `size` points at `scale` pixels per point, with y growing downward like
    /// the app's flipped views.
    static func flippedContext(_ size: CGSize = size, scale: CGFloat = 2) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }

    /// The scene a chart lays out to.
    static func scene(_ chart: Chart, size: CGSize = size) -> ChartScene {
        ChartComposer.scene(for: chart, size: size)
    }

    /// The text items of a chart's scene.
    static func texts(_ chart: Chart, size: CGSize = size) -> [ChartText] {
        scene(chart, size: size).items.compactMap { item in
            if case .text(let text) = item { return text }
            return nil
        }
    }
}

/// A bitmap context's pixels, top row first.
struct ChartPixels {
    let width: Int
    let height: Int
    /// RGBA, premultiplied.
    let bytes: [UInt8]

    init?(_ context: CGContext) {
        guard let data = context.data else { return nil }
        width = context.width
        height = context.height
        let rowBytes = context.bytesPerRow
        let source = data.assumingMemoryBound(to: UInt8.self)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<(width * 4) { bytes[row * width * 4 + column] = source[row * rowBytes + column] }
        }
        self.bytes = bytes
    }

    func pixel(_ x: Int, _ y: Int) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let index = (y * width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }

    /// How many opaque pixels are close to `color`.
    func count(_ color: RGBColor, tolerance: Int = 12) -> Int {
        var count = 0
        var index = 0
        while index < bytes.count {
            if bytes[index + 3] == 255, abs(Int(bytes[index]) - Int(color.red)) <= tolerance,
               abs(Int(bytes[index + 1]) - Int(color.green)) <= tolerance, abs(Int(bytes[index + 2]) - Int(color.blue)) <= tolerance {
                count += 1
            }
            index += 4
        }
        return count
    }

    /// Per row in `rows`, how many pixels in `columns` are dark.
    func darkRows(_ rows: Range<Int>, _ columns: Range<Int>) -> [(row: Int, dark: Int, first: Int)] {
        var result: [(row: Int, dark: Int, first: Int)] = []
        for row in rows {
            var dark = 0, first = Int.max
            for column in columns where pixel(column, row).red < 100 && pixel(column, row).alpha > 200 {
                dark += 1
                first = min(first, column)
            }
            if dark > 0 { result.append((row, dark, first)) }
        }
        return result
    }
}

/// Drawing charts into contexts: every kind, the flipped coordinates the app uses, upright text, what's left alone,
/// threads and speed.
@Suite struct ChartRenderingTests {
    @Test(arguments: ChartKind.allCases)
    func everyKindDrawsSomething(kind: ChartKind) throws {
        for size in [ChartFixtures.size, ChartFixtures.small] {
            let context = try #require(ChartFixtures.flippedContext(size))
            ChartRenderer.draw(Chart.sample(kind), in: CGRect(origin: .zero, size: size), context: context)
            let pixels = try #require(ChartPixels(context))
            let total = pixels.width * pixels.height
            // The background covers the chart, and the chart isn't blank (thin lines and points cover only a few
            // percent of it).
            #expect(pixels.bytes.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 }, "\(kind) at \(size)")
            let white = pixels.count(.white, tolerance: 2)
            #expect(white < total * 98 / 100 && white > total / 4, "\(kind) at \(size): \(white) of \(total) white")
            // The first series (or slice) in the palette's blue, and dark gray text.
            #expect(pixels.count(Chart.palette[0]) > 150, "\(kind) at \(size)")
            #expect(pixels.count(RGBColor(red: 0x22, green: 0x22, blue: 0x22), tolerance: 40) > 50, "\(kind) at \(size)")
        }
    }

    @Test func busyChartsDrawEveryKindWithEveryOption() throws {
        for kind in ChartKind.allCases {
            let chart = Chart(kind: kind, data: ChartFixtures.sales, title: "Sales by month", horizontalAxisTitle: "Month",
                              verticalAxisTitle: "Amount", showsDataLabels: true)
            let context = try #require(ChartFixtures.flippedContext())
            ChartRenderer.draw(chart, in: CGRect(origin: .zero, size: ChartFixtures.size), context: context)
            let pixels = try #require(ChartPixels(context))
            for color in Chart.palette.prefix(kind.isPie ? 6 : 3) {
                #expect(pixels.count(color) > 100, "\(kind): \(color.hex)")
            }
        }
    }

    @Test func textIsUprightInAFlippedContext() throws {
        // A title "T": upright, the T's bar is its widest row and comes first.
        let context = try #require(ChartFixtures.flippedContext())
        ChartRenderer.draw(Chart(kind: .column, data: ChartData(), title: "T"), in: CGRect(origin: .zero, size: ChartFixtures.size), context: context)
        let rows = try #require(ChartPixels(context)).darkRows(0..<80, 0..<120)
        let first = try #require(rows.first), last = try #require(rows.last)
        // 12 pt of padding and a 12 pt title, at 2 pixels per point.
        #expect(first.row >= 20 && last.row < 60)
        #expect(first.dark > last.dark * 3)

        // An "L": its stem comes first and its foot, last and widest, runs right from the stem (not mirrored).
        let other = try #require(ChartFixtures.flippedContext())
        ChartRenderer.draw(Chart(kind: .column, data: ChartData(), title: "L"), in: CGRect(origin: .zero, size: ChartFixtures.size), context: other)
        let lRows = try #require(ChartPixels(other)).darkRows(0..<80, 0..<120)
        let top = try #require(lRows.first), foot = try #require(lRows.last)
        #expect(foot.dark > top.dark * 3)
        #expect(abs(foot.first - top.first) <= 1)
    }

    @Test func verticalAxisTitlesReadUpward() throws {
        // A vertical axis title "L", turned to read upward: its stem lies along the bottom and its
        // foot rises at the right, so the top-left quarter of its box is empty.
        var chart = Chart.sample(.column)
        chart.verticalAxisTitle = "L"
        let context = try #require(ChartFixtures.flippedContext())
        ChartRenderer.draw(chart, in: CGRect(origin: .zero, size: ChartFixtures.size), context: context)
        let pixels = try #require(ChartPixels(context))
        // The title sits left of the value labels, in the first 24 points.
        let rows = pixels.darkRows(0..<pixels.height, 0..<48)
        let top = try #require(rows.first?.row), bottom = try #require(rows.last?.row)
        let left = try #require(rows.map(\.first).min())
        let right = (0..<48).last { column in (top...bottom).contains { pixels.pixel(column, $0).red < 100 && pixels.pixel(column, $0).alpha > 200 } } ?? left
        let midX = (left + right + 1) / 2, midY = (top + bottom + 1) / 2
        #expect(bottom - top > 5 && right - left > 5)
        #expect(pixels.darkRows(top..<midY, left..<midX).isEmpty)
        #expect(!pixels.darkRows(top..<midY, midX..<(right + 1)).isEmpty)
        #expect(!pixels.darkRows(midY..<(bottom + 1), left..<midX).isEmpty)
    }

    @Test func drawingStaysInsideItsRect() throws {
        // Red all over, then charts in the middle: the red outside the rect is untouched.
        let rect = CGRect(x: 100, y: 50, width: 200, height: 120)
        for kind in ChartKind.allCases {
            let context = try #require(ChartFixtures.flippedContext())
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(origin: .zero, size: ChartFixtures.size))
            let chart = Chart(kind: kind, data: ChartFixtures.wave(60), title: "A long title that won't fit in such a small chart at all",
                              horizontalAxisTitle: "Horizontal", verticalAxisTitle: "Vertical", showsDataLabels: true)
            ChartRenderer.draw(chart, in: rect, context: context)
            let pixels = try #require(ChartPixels(context))
            let device = CGRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2)
            var changed = 0
            for y in 0..<pixels.height {
                for x in 0..<pixels.width where !device.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    let pixel = pixels.pixel(x, y)
                    if pixel.red != 255 || pixel.green != 0 || pixel.blue != 0 { changed += 1 }
                }
            }
            #expect(changed == 0, "\(kind)")
            #expect(pixels.pixel(Int(device.midX), Int(device.minY) + 2).green == 255, "\(kind): the background is white")
        }
    }

    @Test func theContextComesBackAsItWas() throws {
        let context = try #require(ChartFixtures.flippedContext())
        let matrix = CGAffineTransform(a: 2, b: 0, c: 0.5, d: 3, tx: 7, ty: 9)
        context.textMatrix = matrix
        let ctm = context.ctm
        ChartRenderer.draw(Chart.sample(.column), in: CGRect(x: 10, y: 10, width: 300, height: 200), context: context)
        #expect(context.textMatrix == matrix)
        #expect(context.ctm == ctm)
        // Nothing clipped or colored for what's drawn next.
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 400, y: 250, width: 20, height: 20))
        let pixels = try #require(ChartPixels(context))
        #expect(pixels.pixel(820, 510).green == 255 && pixels.pixel(820, 510).red == 0)
    }

    @Test func emptyAndNonFiniteRectsDrawNothing() throws {
        let rects = [CGRect.zero, CGRect(x: 0, y: 0, width: -50, height: 50), CGRect(x: 0, y: 0, width: 100, height: 0),
                     CGRect(x: 0, y: 0, width: Double.nan, height: 50), CGRect(x: 0, y: 0, width: 100, height: Double.infinity),
                     CGRect(x: Double.nan, y: 0, width: 100, height: 50), CGRect.null, CGRect.infinite]
        for rect in rects {
            let context = try #require(ChartFixtures.flippedContext(CGSize(width: 40, height: 30)))
            ChartRenderer.draw(Chart.sample(.column), in: rect, context: context)
            #expect(try #require(ChartPixels(context)).bytes.allSatisfy { $0 == 0 }, "\(rect)")
        }
    }

    @Test func tinyAndOddRectsDraw() throws {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 4, height: 4), CGSize(width: 12, height: 9), CGSize(width: 40, height: 30),
                     CGSize(width: 2000, height: 90), CGSize(width: 60, height: 900)] {
            for kind in ChartKind.allCases {
                let context = try #require(ChartFixtures.flippedContext(size, scale: 1))
                ChartRenderer.draw(Chart(kind: kind, data: ChartFixtures.sales, title: "Small", showsDataLabels: true),
                                   in: CGRect(origin: .zero, size: size), context: context)
                // The white background always shows.
                #expect(try #require(ChartPixels(context)).count(.white, tolerance: 2) > 0, "\(kind) at \(size)")
            }
        }
    }

    @Test func drawingIsSafeFromManyThreads() async {
        let total = await withTaskGroup(of: Int.self) { group in
            for task in 0..<8 {
                group.addTask {
                    var length = 0
                    for index in 0..<20 {
                        let kind = ChartKind.allCases[(index + task) % ChartKind.allCases.count]
                        let chart = Chart(kind: kind, data: ChartFixtures.wave(30 + index + task), title: "Task \(task)")
                        length += ChartRenderer.svg(chart, size: ChartFixtures.size).count
                        if let context = ChartFixtures.flippedContext(ChartFixtures.small, scale: 1) {
                            ChartRenderer.draw(chart, in: CGRect(origin: .zero, size: ChartFixtures.small), context: context)
                        }
                    }
                    return length
                }
            }
            var sum = 0
            for await length in group { sum += length }
            return sum
        }
        #expect(total > 0)
    }

    // MARK: Speed

    /// Slides redraw their charts as the canvas scrolls and thumbnails update. Limits are generous (several times
    /// the typical time); debug builds only catch disasters. Each check takes the fastest of several runs, so tests
    /// running in parallel can't make it fail.
    #if DEBUG
    static let allowance = 10.0
    #else
    static let allowance = 1.0
    #endif

    func fastestMilliseconds(_ runs: Int = 5, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var best = Double.infinity
        for _ in 0..<runs {
            let elapsed = clock.measure(body)
            best = min(best, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        return best
    }

    @Test func drawingIsQuick() throws {
        let context = try #require(ChartFixtures.flippedContext())
        let rect = CGRect(origin: .zero, size: ChartFixtures.size)
        // About 100 points: 50 rows of two series (a 50-slice pie).
        let typical = ChartFixtures.wave(50)
        for kind in ChartKind.allCases {
            let chart = Chart(kind: kind, data: typical, title: "Typical")
            let milliseconds = fastestMilliseconds { ChartRenderer.draw(chart, in: rect, context: context) }
            #expect(milliseconds < 8 * Self.allowance, "\(kind): \(milliseconds) ms")
        }
        // Ten thousand points stay quick: dense runs draw from per-column envelopes.
        var thousands = ChartFixtures.wave(10_000)
        thousands.series.removeLast()
        for kind in [ChartKind.column, .line, .area, .scatter, .bar] {
            var data = thousands
            if kind == .scatter {
                data = ChartFixtures.wave(10_000, numeric: true)
                data.series.removeLast()
            }
            let chart = Chart(kind: kind, data: data, title: "10,000 points")
            let milliseconds = fastestMilliseconds(3) { ChartRenderer.draw(chart, in: rect, context: context) }
            #expect(milliseconds < 60 * Self.allowance, "\(kind): \(milliseconds) ms")
        }
    }
}
