import CoreGraphics
import Foundation
import Testing
@testable import PuggleSlidesKit

/// How charts are laid out: legends, stacking, awkward data, sizes, fonts and pies.
@Suite struct ChartLayoutTests {
    private func strings(_ chart: Chart, size: CGSize = ChartFixtures.size) -> [String] {
        ChartFixtures.texts(chart, size: size).map(\.string)
    }

    private func text(_ string: String, in chart: Chart, size: CGSize = ChartFixtures.size) -> ChartText? {
        ChartFixtures.texts(chart, size: size).first { $0.string == string }
    }

    // MARK: Legends

    @Test func autoLegendPlacement() {
        func placement(_ kind: ChartKind, _ size: CGSize = ChartFixtures.size, entries: Int = 2) -> ChartLegendPlacement {
            ChartComposer(chart: Chart.sample(kind), size: size).legendPlacement(entryCount: entries, pie: kind.isPie)
        }
        // At the right for several series and for pies; none for one series, whose title and axes name it.
        #expect(placement(.column) == .right && placement(.line) == .right && placement(.pie, entries: 4) == .right)
        #expect(placement(.column, entries: 1) == .none && placement(.pie, entries: 1) == .right)
        #expect(placement(.column, entries: 0) == .none && placement(.pie, entries: 0) == .none)
        // Too narrow for the right: on top, or below a pie.
        #expect(placement(.column, ChartFixtures.small) == .top && placement(.bar, ChartFixtures.small) == .top)
        #expect(placement(.pie, ChartFixtures.small, entries: 4) == .bottom && placement(.donut, ChartFixtures.small, entries: 4) == .bottom)
        // A chosen position is kept.
        let expected: [ChartLegendPosition: ChartLegendPlacement] = [.top: .top, .bottom: .bottom, .left: .left, .right: .right, .none: .none]
        for (position, placement) in expected {
            var chart = Chart.sample(.column)
            chart.legend = position
            #expect(ChartComposer(chart: chart, size: ChartFixtures.small).legendPlacement(entryCount: 1, pie: false) == placement)
        }
    }

    @Test func legendsSitWhereTheyArePlaced() throws {
        let size = ChartFixtures.size
        for position in ChartLegendPosition.allCases {
            var chart = Chart.sample(.column)
            chart.legend = position
            let legend = text("Series 1", in: chart)
            switch position {
            case .auto, .right:
                let item = try #require(legend)
                #expect(item.x > size.width * 0.75 && item.y < size.height * 0.3, "\(position)")
            case .left:
                let item = try #require(legend)
                #expect(item.x < size.width * 0.25 && item.y < size.height * 0.3)
            case .top:
                let item = try #require(legend)
                #expect(item.y < size.height * 0.15)
            case .bottom:
                let item = try #require(legend)
                #expect(item.y > size.height * 0.85)
            case .none:
                #expect(legend == nil)
            }
            // Both series are named, in order, whenever there's a legend.
            let names = strings(chart).filter { $0.hasPrefix("Series") }
            #expect(names == (position == .none ? [] : ["Series 1", "Series 2"]), "\(position)")
        }
        // Pie legends name the slices; one series alone has no legend.
        #expect(["Item 1", "Item 2", "Item 3", "Item 4"].allSatisfy(strings(Chart.sample(.pie)).contains))
        let single = Chart(kind: .column, data: ChartData(labels: ["a", "b"], series: [ChartSeries(name: "Lonely", values: [1, 2])]))
        #expect(!strings(single).contains("Lonely"))
    }

    @Test func longLegendsEndWithAnEllipsis() {
        let many = ChartData(labels: ["a", "b"], series: (1...40).map { ChartSeries(name: "Series \($0)", values: [Double($0), 1]) })
        for position in [ChartLegendPosition.right, .top, .bottom] {
            let shown = strings(Chart(kind: .column, data: many, legend: position))
            #expect(shown.contains("…") && !shown.contains("Series 40"), "\(position)")
            #expect(shown.contains("Series 1"))
        }
    }

    // MARK: Stacking

    @Test func percentChartsReachOneHundredPercent() throws {
        for kind in [ChartKind.percentColumn, .percentBar, .percentArea] {
            let composer = ChartComposer(chart: Chart(kind: kind, data: ChartFixtures.sales), size: ChartFixtures.size)
            let series = composer.plotSeries(stacking: .percent)
            let last = try #require(series.last)
            #expect(last.tops.allSatisfy { abs(($0 ?? 0) - 1) < 1e-12 }, "\(kind)")
            // Each band is its value's share of the label's total: January's sales are 120 of 240.
            #expect(abs((series[0].tops[0] ?? 0) - 0.5) < 1e-12)
            #expect(abs((series[1].tops[0] ?? 0) - (series[1].bases?[0] ?? 0) - 80.0 / 240) < 1e-12)
            let labels = strings(Chart(kind: kind, data: ChartFixtures.sales))
            #expect(["0%", "25%", "50%", "75%", "100%"].allSatisfy(labels.contains), "\(kind)")
        }
        // Negative values stack downward, and the axis runs from -100% to 100%.
        let mixed = ChartData(labels: ["a", "b"], series: [ChartSeries(name: "Up", values: [30, 10]), ChartSeries(name: "Down", values: [-10, -10])])
        let series = ChartComposer(chart: Chart(kind: .percentColumn, data: mixed), size: ChartFixtures.size).plotSeries(stacking: .percent)
        #expect(series[0].tops == [0.75, 0.5] && series[1].tops == [-0.25, -0.5])
        #expect(["-100%", "-50%", "0%", "50%", "100%"].allSatisfy(strings(Chart(kind: .percentColumn, data: mixed)).contains))
    }

    @Test func stackedChartsAddUp() {
        let composer = ChartComposer(chart: Chart(kind: .stackedColumn, data: ChartFixtures.sales), size: ChartFixtures.size)
        let series = composer.plotSeries(stacking: .stacked)
        #expect(series[2].tops[0] == 240 && series[2].bases?[0] == 200 && series[1].bases?[0] == 120)
        // Gaps leave columns out but count as zero in areas.
        let gappy = ChartData(labels: ["a", "b"], series: [ChartSeries(name: "x", values: [nil, 2]), ChartSeries(name: "y", values: [3, 4])])
        let columns = ChartComposer(chart: Chart(kind: .stackedColumn, data: gappy), size: ChartFixtures.size).plotSeries(stacking: .stacked)
        #expect(columns[0].tops == [nil, 2] && columns[1].tops == [3, 6])
        let areas = ChartComposer(chart: Chart(kind: .stackedArea, data: gappy), size: ChartFixtures.size).plotSeries(stacking: .stacked)
        #expect(areas[0].tops == [0, 2] && areas[1].tops == [3, 6])
    }

    // MARK: Awkward data

    @Test func emptyChartsSayNoData() {
        let empties: [ChartData] = [
            ChartData(),
            ChartData(labels: ["a", "b"]),
            ChartData(labels: ["a"], series: [ChartSeries(name: "x", values: [nil])]),
            ChartData(labels: ["a", "b"], series: [ChartSeries(name: "x", values: [.nan, .infinity])]),
        ]
        for kind in ChartKind.allCases {
            for data in empties {
                let shown = strings(Chart(kind: kind, data: data, title: "Empty"))
                #expect(shown.contains("No data") && shown.contains("Empty"), "\(kind)")
            }
        }
        // Pies need something above zero.
        let flat = ChartData(labels: ["a", "b"], series: [ChartSeries(name: "x", values: [0, -3])])
        #expect(strings(Chart(kind: .donut, data: flat)).contains("No data"))
        #expect(!strings(Chart(kind: .column, data: flat)).contains("No data"))
    }

    @Test func awkwardDataLaysOut() throws {
        let datasets: [ChartData] = [
            ChartData(labels: ["only"], series: [ChartSeries(name: "One", values: [42])]),
            ChartData(labels: ["a", "b", "c"], series: [ChartSeries(name: "Zero", values: [0, 0, 0])]),
            ChartData(labels: ["a", "b", "c"], series: [ChartSeries(name: "Negative", values: [-5, -20, -1])]),
            ChartData(labels: ["a", "b", "c"], series: [ChartSeries(name: "Huge", values: [1e300, -1e300, .greatestFiniteMagnitude])]),
            ChartData(labels: ["a", "b", "c"], series: [ChartSeries(name: "Tiny", values: [1e-300, 5e-324, 3e-300])]),
            ChartData(labels: ["a", "b", "c", "d"], series: [ChartSeries(name: "Gaps", values: [1, nil, 3, .nan])]),
            ChartData(labels: ["a"], series: [ChartSeries(name: "Ragged", values: [1, 2, 3, 4]), ChartSeries(name: "Short", values: [])]),
            ChartData(labels: ["line\nbreak", "tab\there"], series: [ChartSeries(name: "Multi\nline", values: [1, 2])]),
            ChartFixtures.wave(3000, numeric: true),
        ]
        for data in datasets {
            for kind in ChartKind.allCases {
                let chart = Chart(kind: kind, data: data, title: "t", horizontalAxisTitle: "x", verticalAxisTitle: "y", showsDataLabels: true)
                let scene = ChartFixtures.scene(chart)
                #expect(!scene.items.isEmpty, "\(kind)")
                for item in scene.items {
                    switch item {
                    case .text(let text):
                        #expect(text.x.isFinite && text.y.isFinite && !text.string.contains("\n"), "\(kind)")
                        #expect(!text.string.lowercased().contains("nan") && !text.string.lowercased().contains("inf"), "\(kind): \(text.string)")
                    case .fill(let path, _), .stroke(let path, _, _):
                        let box = path.boundingBoxOfPath
                        #expect(box.minX.isFinite && box.minY.isFinite && box.maxX.isFinite && box.maxY.isFinite, "\(kind)")
                    case .dots(let points, _, _):
                        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(kind)")
                    case .clip, .endClip:
                        break
                    }
                }
            }
        }
        // Huge numbers are written in scientific notation.
        let huge = strings(Chart(kind: .column, data: datasets[3], showsDataLabels: true))
        #expect(huge.contains("1E+300") && huge.contains("-1E+300"))
    }

    @Test func gapsBreakLines() {
        let data = ChartData(labels: ["a", "b", "c", "d", "e"], series: [ChartSeries(name: "x", values: [1, 2, nil, 4, 5])])
        let composer = ChartComposer(chart: Chart(kind: .line, data: data), size: ChartFixtures.size)
        let runs = composer.runs(data.series[0].values, x: { Double($0) }, y: { $0 })
        #expect(runs.map(\.count) == [2, 2])
        // A point alone between gaps still shows, as a dot.
        let lone = ChartData(labels: ["a", "b", "c"], series: [ChartSeries(name: "x", values: [nil, 2, nil])])
        let dots = ChartFixtures.scene(Chart(kind: .line, data: lone)).items.filter { if case .dots = $0 { return true } else { return false } }
        #expect(dots.count == 1)
    }

    @Test func manyLabelsThinOutOrTilt() {
        // Two hundred text labels can't all show: every n-th does, tilted.
        let many = ChartFixtures.wave(200)
        let texts = ChartFixtures.texts(Chart(kind: .column, data: many))
        let labels = texts.filter { $0.string.hasPrefix("Item") }
        #expect(labels.count > 5 && labels.count < 100)
        #expect(labels.allSatisfy { $0.angle == ChartComposer.slantAngle })
        // Numbers don't tilt; they thin out like an axis.
        let numeric = ChartFixtures.texts(Chart(kind: .column, data: ChartFixtures.wave(200, numeric: true)))
        let numbers = numeric.filter { $0.y > ChartFixtures.size.height * 0.8 && Int($0.string) != nil }
        #expect(numbers.count > 5 && numbers.count < 60 && numbers.allSatisfy { $0.angle == 0 })
        // Bars thin their category labels too.
        let bars = ChartFixtures.texts(Chart(kind: .bar, data: many)).filter { $0.string.hasPrefix("Item") }
        #expect(bars.count > 5 && bars.count < 100)
    }

    @Test func dataLabelsAndGridlinesFollowTheirSwitches() {
        var chart = Chart.sample(.column)
        #expect(!strings(chart).contains("22"))
        chart.showsDataLabels = true
        #expect(["10", "22", "18", "30", "14", "12", "25", "21"].allSatisfy(strings(chart).contains))
        #expect(ChartRenderer.svg(chart, size: ChartFixtures.size).contains("fill=\"#CCCCCC\""))
        chart.showsGridlines = false
        #expect(!ChartRenderer.svg(chart, size: ChartFixtures.size).contains("fill=\"#CCCCCC\""))
        // The zero line stays.
        #expect(ChartRenderer.svg(chart, size: ChartFixtures.size).contains("fill=\"#333333\""))
    }

    @Test func pinnedAxesClipTheirMarks() throws {
        let chart = Chart(kind: .column, data: ChartFixtures.sales, verticalMinimum: 100, verticalMaximum: 200)
        let shown = strings(chart)
        #expect(["100", "120", "140", "160", "180", "200"].allSatisfy(shown.contains) && !shown.contains("0") && !shown.contains("250"))
        let scene = ChartFixtures.scene(chart)
        #expect(scene.items.contains { if case .clip = $0 { return true } else { return false } })
        // Columns stop at the plot: none reaches above the 200 line or below the 100 line (whose labels sit a little
        // below their lines).
        let colors = Chart.palette.prefix(3).map { ChartColor($0) }
        let columns = scene.items.compactMap { item -> CGRect? in
            guard case .fill(let path, let color) = item, colors.contains(color) else { return nil }
            let box = path.boundingBoxOfPath
            return box.width > 20 ? box : nil
        }
        let top = try #require(ChartFixtures.texts(chart).first { $0.string == "200" }).y
        let bottom = try #require(ChartFixtures.texts(chart).first { $0.string == "100" }).y
        // Profit never reaches 100, so at most its empty path is left.
        #expect(columns.count >= 2)
        #expect(columns.allSatisfy { $0.minY >= top - 5 && $0.maxY <= bottom })
        // Mins and maxes the wrong way round still give an axis.
        let swapped = strings(Chart(kind: .column, data: ChartFixtures.sales, verticalMinimum: 200, verticalMaximum: 100))
        #expect(swapped.contains("100") && swapped.contains("200"))
    }

    @Test func scatterChartsPlaceNumericLabelsAlongTheAxis() throws {
        let data = ChartData(labels: ["3", "1", "2.5", "10"], series: [ChartSeries(name: "y", values: [30, 10, 25, 100])])
        let scene = ChartFixtures.scene(Chart(kind: .scatter, data: data))
        let dots = scene.items.compactMap { item -> [CGPoint]? in
            if case .dots(let points, _, _) = item { return points }
            return nil
        }
        let points = try #require(dots.first)
        #expect(points.count == 4)
        // x follows the labels' values, not their order: 1 < 2.5 < 3 < 10, and evenly scaled.
        #expect(points[1].x < points[2].x && points[2].x < points[0].x && points[0].x < points[3].x)
        let unit = (points[3].x - points[1].x) / 9
        #expect(abs((points[0].x - points[1].x) - 2 * unit) < 0.01)
        #expect(["0", "2", "4", "6", "8", "10"].allSatisfy(scene.strings.contains))
        // Text labels put the points in slots instead.
        let words = ChartFixtures.scene(Chart.sample(.scatter)).strings
        #expect(["Item 1", "Item 4"].allSatisfy(words.contains))
    }

    @Test func labelsReadAsNumbers() {
        #expect(ChartRows.number("12") == 12 && ChartRows.number(" -3.5 ") == -3.5 && ChartRows.number("1e3") == 1000)
        #expect(ChartRows.number("1,250.5") == 1250.5 && ChartRows.number("-12,500") == -12500 && ChartRows.number("1,000,000") == 1_000_000)
        #expect(ChartRows.number("12,50") == nil && ChartRows.number("1,2345") == nil && ChartRows.number("1,250.5.1") == nil)
        #expect(ChartRows.number("Item 1") == nil && ChartRows.number("") == nil && ChartRows.number("   ") == nil)
        #expect(ChartRows.number("inf") == nil && ChartRows.number("nan") == nil && ChartRows.number("-infinity") == nil)
        #expect(ChartRows.number("1e999") == nil && ChartRows.number("1e301") == ChartRows.limit)
    }

    // MARK: Sizes and fonts

    @Test func textScalesWithTheChartWithinLimits() {
        let reference = ChartStyle(chart: Chart.sample(.column), size: ChartFixtures.size)
        // Insert ▸ Chart's size is the reference chart: 16 px title and 12 px labels at 0.75 point per pixel.
        #expect(reference.scale == 0.75 && reference.titleFont.size == 12 && reference.labelFont.size == 9 && reference.legendFont.size == 9)
        // Small charts keep readable text but shrink their gridline spacing further.
        let small = ChartStyle(chart: Chart.sample(.column), size: ChartFixtures.small)
        #expect(small.labelFont.size >= 7 && small.titleFont.size >= 9 && small.dataLabelFont.size >= 6.5)
        #expect(small.gridScale < small.scale)
        let tiny = ChartStyle(chart: Chart.sample(.column), size: CGSize(width: 20, height: 10))
        #expect(tiny.labelFont.size == small.labelFont.size)
        // A chart filling a slide grows its text a little; huge charts stop growing.
        let slide = ChartStyle(chart: Chart.sample(.column), size: CGSize(width: 720, height: 405))
        #expect(slide.labelFont.size > 9 && slide.labelFont.size <= 11.5 && slide.titleFont.size <= 15)
        let huge = ChartStyle(chart: Chart.sample(.column), size: CGSize(width: 10_000, height: 8_000))
        #expect(huge.labelFont.size <= 12.5 && huge.titleFont.size <= 16.5)
        // Lopsided sizes follow their shorter side.
        #expect(ChartStyle(chart: Chart.sample(.column), size: CGSize(width: 2000, height: 120)).labelFont.size == small.labelFont.size)
    }

    @Test func fontsFallBackToRobotoThenArial() {
        let engine = ChartTextEngine.shared
        let fallback = ChartTextEngine.isInstalled("Roboto") ? "Roboto" : (ChartTextEngine.isInstalled("Arial") ? "Arial" : "Helvetica")
        #expect(engine.family(for: nil) == fallback)
        #expect(engine.family(for: "  ") == fallback)
        #expect(engine.family(for: "No Such Font Family 9F2C") == fallback)
        if ChartTextEngine.isInstalled("Times New Roman") {
            #expect(engine.family(for: "Times New Roman") == "Times New Roman")
            // Typed in another case, the family is still found, under its own name.
            #expect(engine.family(for: "times NEW roman") == "Times New Roman")
            var chart = Chart.sample(.column)
            chart.fontFamily = "Times New Roman"
            #expect(ChartFixtures.texts(chart).allSatisfy { $0.font.family == "Times New Roman" })
        }
        #expect(ChartFixtures.texts(Chart.sample(.pie)).allSatisfy { $0.font.family == fallback })
    }

    @Test func darkBackgroundsGetLightText() {
        var chart = Chart.sample(.column)
        chart.backgroundColor = RGBColor(red: 0x20, green: 0x21, blue: 0x24)
        chart.title = "Dark"
        let texts = ChartFixtures.texts(chart)
        #expect(texts.allSatisfy { $0.color.luminance > 0.6 })
        #expect(ChartFixtures.scene(chart).background == ChartColor(RGBColor(red: 0x20, green: 0x21, blue: 0x24)))
        #expect(ChartFixtures.texts(Chart.sample(.column)).allSatisfy { $0.color.luminance < 0.3 })
    }

    @Test func titlesAreCutToFit() throws {
        let long = String(repeating: "A very long chart title ", count: 10)
        for kind in [ChartKind.column, .pie] {
            let chart = Chart(kind: kind, data: ChartFixtures.sales, title: long)
            let title = try #require(ChartFixtures.texts(chart, size: ChartFixtures.small).first { $0.string.hasPrefix("A very long") })
            #expect(title.string.hasSuffix("…") && title.string.count < long.count)
            #expect(title.x >= 0 && title.x + ChartTextEngine.shared.width(title.string, title.font) <= ChartFixtures.small.width)
        }
    }

    // MARK: Pies

    @Test func piesLabelSlicesWithTheirShare() {
        let shown = strings(Chart.sample(.pie))
        #expect(["40%", "25%", "20%", "15%", "Series 1"].allSatisfy(shown.contains))
        let svg = ChartRenderer.svg(Chart.sample(.pie), size: ChartFixtures.size)
        #expect(Chart.palette.prefix(4).allSatisfy { svg.contains("fill=\"#\($0.hex)\"") })
        // Slice labels are white.
        #expect(ChartFixtures.texts(Chart.sample(.pie)).filter { $0.string.hasSuffix("%") }.allSatisfy { $0.color == .white })
        // Only the first series counts; zero, negative and empty values get no slice.
        let mixed = ChartData(labels: ["a", "b", "c", "d"], series: [ChartSeries(name: "x", values: [3, 0, -2, 1]),
                                                                    ChartSeries(name: "ignored", values: [100, 100, 100, 100])])
        let labels = strings(Chart(kind: .pie, data: mixed))
        #expect(labels.contains("75%") && labels.contains("25%") && !labels.contains("b") && !labels.contains("c"))
    }

    @Test func tinySlicesBecomeOther() {
        let data = ChartData(labels: ["Big", "Crumb", "Speck"], series: [ChartSeries(name: "x", values: [10_000, 1, 2])])
        let labels = strings(Chart(kind: .pie, data: data))
        #expect(labels.contains("Big") && labels.contains("Other") && !labels.contains("Crumb"))
        #expect(ChartRenderer.svg(Chart(kind: .pie, data: data), size: ChartFixtures.size).contains("fill=\"#CCCCCC\""))
    }

    @Test func doughnutsHaveHoles() throws {
        for (kind, hole) in [(ChartKind.pie, 0.5), (.donut, 0.5), (.donut, 0), (.donut, 2), (.donut, .nan)] {
            var chart = Chart.sample(kind)
            chart.pieHole = hole
            chart.title = ""
            chart.legend = .none
            let context = try #require(ChartFixtures.flippedContext())
            ChartRenderer.draw(chart, in: CGRect(origin: .zero, size: ChartFixtures.size), context: context)
            let pixels = try #require(ChartPixels(context))
            // Near the middle (not on it, where the slices' white borders meet): white in a doughnut with a hole,
            // colored in a pie.
            let middle = pixels.pixel(pixels.width / 2 + 14, pixels.height / 2 + 14)
            let isWhite = middle.red == 255 && middle.green == 255 && middle.blue == 255
            #expect(isWhite == (kind == .donut && hole > 0 && hole.isFinite), "\(kind) \(hole)")
        }
    }

    @Test func seriesKeepTheirOwnColors() {
        var chart = Chart.sample(.line)
        chart.data.series[1].color = RGBColor(red: 0x12, green: 0x34, blue: 0x56)
        let svg = ChartRenderer.svg(chart, size: ChartFixtures.size)
        #expect(svg.contains("stroke=\"#123456\"") && svg.contains("stroke=\"#4285F4\"") && !svg.contains("stroke=\"#EA4335\""))
        // Areas fill with the series color at 30%.
        #expect(ChartRenderer.svg(Chart.sample(.area), size: ChartFixtures.size).contains("fill=\"#4285F4\" fill-opacity=\"0.3\""))
    }
}
