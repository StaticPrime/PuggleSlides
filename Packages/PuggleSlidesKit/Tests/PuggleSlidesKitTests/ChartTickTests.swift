import Foundation
import Testing
@testable import PuggleSlidesKit

/// Axis ticks and the text of tick, data and slice labels.
@Suite struct ChartTickTests {
    @Test func niceSteps() {
        #expect(ChartTicks.niceStep(atLeast: 0.3) == 0.5)
        #expect(ChartTicks.niceStep(atLeast: 46) == 50)
        #expect(ChartTicks.niceStep(atLeast: 1) == 1)
        #expect(ChartTicks.niceStep(atLeast: 2.2) == 2.5)
        #expect(ChartTicks.niceStep(atLeast: 7) == 10)
        #expect(ChartTicks.niceStep(atLeast: 0.0012) == 0.002)
        #expect(ChartTicks.niceStep(atLeast: 1_200_000) == 2_000_000)
        #expect(ChartTicks.niceStep(atLeast: 0) == 1 && ChartTicks.niceStep(atLeast: .nan) == 1)
        #expect(ChartTicks.previousNiceStep(5) == 2.5 && ChartTicks.previousNiceStep(2.5) == 2)
        #expect(ChartTicks.previousNiceStep(2) == 1 && ChartTicks.previousNiceStep(1) == 0.5)
    }

    @Test func linearScales() {
        let sales = ChartTicks.linear(lower: 0, upper: 230, intervals: 5)
        #expect(sales.lower == 0 && sales.upper == 250 && sales.step == 50)
        #expect(sales.ticks == [0, 50, 100, 150, 200, 250])

        // The step below the even split wins when it comes closer to the wanted count.
        let four = ChartTicks.linear(lower: 0, upper: 230, intervals: 4)
        #expect(four.step == 50 && four.upper == 250)

        let mixed = ChartTicks.linear(lower: -65, upper: 92, intervals: 4)
        #expect(mixed.ticks == [-100, -50, 0, 50, 100])

        let fractions = ChartTicks.linear(lower: 0, upper: 0.9, intervals: 4)
        #expect(fractions.ticks == [0, 0.25, 0.5, 0.75, 1])

        let tenths = ChartTicks.linear(lower: 0.1, upper: 0.7, intervals: 6)
        #expect(tenths.ticks == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7])

        // All zero, and a single value.
        #expect(ChartTicks.linear(lower: 0, upper: 0, intervals: 5).ticks == [0, 0.2, 0.4, 0.6, 0.8, 1])
        let single = ChartTicks.linear(lower: 42, upper: 42, intervals: 5)
        #expect(single.lower < 42 && single.upper > 42)

        // A pinned minimum and maximum: ticks are the step's multiples between them.
        let pinned = ChartTicks.linear(lower: 0, upper: 230, intervals: 5, fixedLower: 100, fixedUpper: 200)
        #expect(pinned.lower == 100 && pinned.upper == 200)
        #expect(pinned.ticks == [100, 120, 140, 160, 180, 200])
        let pinnedLow = ChartTicks.linear(lower: 0, upper: 230, intervals: 5, fixedLower: -30)
        #expect(pinnedLow.lower == -30 && pinnedLow.ticks.first == 0 && pinnedLow.upper == 250)
        // Ends the wrong way round are swapped, equal ones leave the maximum to the data, and non-finite data falls
        // back to 0...1.
        let swapped = ChartTicks.linear(lower: 0, upper: 10, intervals: 5, fixedLower: 200, fixedUpper: 100)
        #expect(swapped.lower == 100 && swapped.upper == 200 && swapped.ticks.count >= 3)
        let equal = ChartTicks.linear(lower: 0, upper: 10, intervals: 5, fixedLower: 100, fixedUpper: 100)
        #expect(equal.lower == 100 && equal.upper > 100 && equal.ticks.count >= 2)
        #expect(ChartTicks.linear(lower: .nan, upper: .infinity, intervals: 5).ticks == [0, 0.2, 0.4, 0.6, 0.8, 1])
        #expect(ChartTicks.linear(lower: 0, upper: 10, intervals: 5, fixedLower: .nan, fixedUpper: .infinity).upper == 10)
    }

    @Test func theSampleChartGetsNiceTicks() {
        // Insert ▸ Chart's numbers (up to 30) at its size: every 5; at a fifth of a slide, every 10.
        let large = ChartFixtures.texts(Chart.sample(.column)).map(\.string)
        #expect(["0", "5", "10", "15", "20", "25", "30"].allSatisfy(large.contains))
        #expect(!large.contains("35"))
        let small = ChartFixtures.texts(Chart.sample(.column), size: ChartFixtures.small).map(\.string)
        #expect(["0", "10", "20", "30"].allSatisfy(small.contains) && !small.contains("5") && !small.contains("40"))
        // Bars put the same ticks along the bottom.
        let bars = ChartFixtures.texts(Chart.sample(.bar), size: ChartFixtures.small).map(\.string)
        #expect(["0", "10", "20", "30"].allSatisfy(bars.contains) && !bars.contains("40"))
    }

    @Test func tinyAndHugeStepsKeepTheirTicksApart() {
        let tiny = ChartTicks.linear(lower: 0, upper: 3e-7, intervals: 3)
        #expect(tiny.ticks.count >= 3 && Set(tiny.ticks).count == tiny.ticks.count)
        #expect(tiny.ticks.allSatisfy { $0 >= 0 && $0 <= 3.5e-7 })
        let tinier = ChartTicks.linear(lower: 1e-300, upper: 5e-300, intervals: 4)
        #expect(tinier.ticks.count >= 3 && Set(tinier.ticks).count == tinier.ticks.count)
        let huge = ChartTicks.linear(lower: -1e300, upper: 1e300, intervals: 4)
        #expect(huge.ticks.count == 5 && zip(huge.ticks, [-1e300, -5e299, 0, 5e299, 1e300]).allSatisfy { abs($0 - $1) <= abs($1) * 1e-12 })
        #expect(ChartTicks.decimals(of: 0.25) == 2 && ChartTicks.decimals(of: 50) == 0 && ChartTicks.decimals(of: 5e-7) == 7)
        #expect(ChartTicks.decimals(of: 2e-13) == ChartTicks.maximumDecimals)
    }

    @Test func scaleFractions() {
        let scale = ChartTicks.linear(lower: 0, upper: 230, intervals: 5)
        #expect(scale.fraction(125) == 0.5)
        #expect(scale.baseline == 0)
        let negative = ChartTicks.linear(lower: -80, upper: -20, intervals: 3)
        #expect(negative.baseline == negative.upper)
        let positive = ChartTicks.linear(lower: 100, upper: 200, intervals: 5, fixedLower: 100, fixedUpper: 200)
        #expect(positive.baseline == 100)
    }

    @Test func percentAxes() {
        #expect(ChartTicks.percent(hasNegative: false, hasPositive: true).ticks == [0, 0.25, 0.5, 0.75, 1])
        #expect(ChartTicks.percent(hasNegative: true, hasPositive: true).ticks == [-1, -0.5, 0, 0.5, 1])
        #expect(ChartTicks.percent(hasNegative: true, hasPositive: false).ticks == [-1, -0.75, -0.5, -0.25, 0])
        #expect([0, 0.25, 1, -0.5].map(ChartNumberText.percentTick) == ["0%", "25%", "100%", "-50%"])
    }

    @Test func tickLabels() {
        // As many decimals as the step needs, thousands grouped.
        #expect(ChartNumberText.tickLabels([0, 0.25, 0.5], step: 0.25) == ["0.00", "0.25", "0.50"])
        #expect(ChartNumberText.tickLabels([0, 2500, 5000], step: 2500) == ["0", "2,500", "5,000"])
        #expect(ChartNumberText.tickLabels([-7500, 0], step: 2500) == ["-7,500", "0"])
        #expect(ChartNumberText.tickLabels([2000, 2005], step: 5, grouping: false) == ["2000", "2005"])
        // Big numbers are shortened.
        #expect(ChartNumberText.tickLabels([0, 10_000, 20_000], step: 10_000) == ["0", "10K", "20K"])
        #expect(ChartNumberText.tickLabels([0, 1_500_000, 3_000_000], step: 1_500_000) == ["0", "1.5M", "3M"])
        #expect(ChartNumberText.tickLabels([-2_000_000_000, 0], step: 1_000_000_000) == ["-2B", "0"])
        // Too big or too fine for that: scientific notation.
        #expect(ChartNumberText.tickLabels([0, 5e16, 1e17], step: 5e16) == ["0", "5E+16", "1E+17"])
        #expect(ChartNumberText.tickLabels([0, 2e-12, 4e-12], step: 2e-12) == ["0", "2E-12", "4E-12"])
    }

    @Test func compactAndScientificNumbers() {
        #expect(ChartNumberText.compact(999_999) == "1M")
        #expect(ChartNumberText.compact(1_250_000) == "1.25M")
        #expect(ChartNumberText.compact(12_500) == "12.5K")
        #expect(ChartNumberText.compact(-3e12) == "-3T")
        #expect(ChartNumberText.compact(0.5) == "0.5")
        #expect(ChartNumberText.scientific(1e300) == "1E+300")
        #expect(ChartNumberText.scientific(-2.5e16) == "-2.5E+16")
        #expect(ChartNumberText.scientific(9.999e15) == "1E+16")
        #expect(ChartNumberText.scientific(1.5e-7) == "1.5E-07")
        #expect(ChartNumberText.scientific(5e-324).hasSuffix("E-324"))
        #expect(ChartNumberText.scientific(.greatestFiniteMagnitude) == "1.8E+308")
    }

    @Test func dataAndSliceLabels() {
        // Data labels show the value in the automatic format.
        #expect(ChartNumberText.dataLabel(1234.5) == "1234.5")
        #expect(ChartNumberText.dataLabel(0.125) == "0.125")
        #expect(ChartNumberText.dataLabel(-3) == "-3")
        #expect(ChartNumberText.dataLabel(0.1 + 0.2) == "0.3")
        #expect(ChartNumberText.dataLabel(1.0 / 3) == "0.3333333333")
        #expect(ChartNumberText.dataLabel(1_250_000) == "1250000")
        #expect(ChartNumberText.dataLabel(2.5e16) == "2.5E+16")
        #expect(ChartNumberText.dataLabel(-0.0) == "0")
        #expect(ChartNumberText.dataLabel(.nan) == "")
        // Slices show their share.
        #expect(ChartNumberText.percent(0.364) == "36.4%")
        #expect(ChartNumberText.percent(0.25) == "25%")
        #expect(ChartNumberText.percent(1) == "100%")
        #expect(ChartNumberText.percent(0.0004) == "0%")
    }

    @Test func numbersAreTheSameInEveryLocale() {
        // String(format:) without a locale always writes a point; grouping is always a comma.
        #expect(ChartNumberText.fixed(1234567.891, decimals: 2, grouping: true) == "1,234,567.89")
        #expect(ChartNumberText.fixed(-0.001, decimals: 2, grouping: true) == "0.00")
        #expect(ChartNumberText.fixed(999, decimals: 0, grouping: true) == "999")
    }
}
