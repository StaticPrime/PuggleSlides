import Foundation

/// The text of axis ticks, data labels and pie slices, in an automatic number format.
///
/// Tick labels get as many decimals as the step needs ("0.25", "0.50"), with thousands separators ("2,500"). Once
/// the biggest tick reaches 10,000 they're shortened with K, M, B and T ("25K", "1.5M"), and numbers too big or too
/// finely stepped for that are written in scientific notation ("1E+300"). Data labels show the value itself.
/// Numbers are written the same way in every locale.
enum ChartNumberText {
    static let compactThreshold = 10_000.0
    /// Ticks at or above this, or stepped finer than `finestStep`, are written in scientific notation.
    static let scientificThreshold = 1e15
    static let finestStep = 1e-9

    /// Labels for `ticks`, which are `step` apart. `grouping` adds thousands separators.
    static func tickLabels(_ ticks: [Double], step: Double, grouping: Bool = true) -> [String] {
        let maxMagnitude = ticks.reduce(0) { Swift.max($0, abs($1)) }
        if maxMagnitude >= scientificThreshold || (step > 0 && step < finestStep) {
            return ticks.map { $0 == 0 ? "0" : scientific($0) }
        }
        if maxMagnitude >= compactThreshold { return ticks.map { compact($0) } }
        let decimals = step > 0 ? Swift.min(ChartTicks.decimals(of: step), 10) : 0
        return ticks.map { fixed($0, decimals: decimals, grouping: grouping) }
    }

    /// A data label: the value as a cell in Automatic format shows it, with up to 10 significant digits and no
    /// trailing zeros ("1234.5", "0.125", "-3"), in scientific notation when very big or very small ("2.5E+16").
    static func dataLabel(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= scientificThreshold || magnitude < finestStep { return scientific(value) }
        let decimals = Swift.min(15, Swift.max(0, 9 - Int(log10(magnitude).rounded(.down))))
        var text = fixed(value, decimals: decimals, grouping: false)
        if text.contains(".") {
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// A pie slice's share: "36.4%", "25%".
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "" }
        let tenths = (fraction * 1000).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 { return "\(Int(tenths / 10))%" }
        return "\(Int(tenths) / 10).\(abs(Int(tenths) % 10))%"
    }

    /// A tick of a 100% chart's axis: "0%", "25%", "-50%".
    static func percentTick(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "" }
        let percent = (fraction * 100).rounded()
        return "\(Int(percent == 0 ? 0 : percent))%"
    }

    /// `value` with `decimals` decimals, and thousands separators when `grouping`: "12,500.50".
    static func fixed(_ value: Double, decimals: Int, grouping: Bool) -> String {
        guard value.isFinite else { return "" }
        let digits = String(format: "%.\(Swift.max(0, Swift.min(20, decimals)))f", abs(value))
        var integer = Substring(digits), fraction = Substring("")
        if let dot = digits.firstIndex(of: ".") {
            integer = digits[..<dot]
            fraction = digits[dot...]
        }
        var grouped = String(integer)
        if grouping, integer.count > 3 {
            grouped = ""
            grouped.reserveCapacity(integer.count + integer.count / 3)
            for (offset, character) in integer.enumerated() {
                if offset > 0, (integer.count - offset) % 3 == 0 { grouped.append(",") }
                grouped.append(character)
            }
        }
        let isZero = digits.allSatisfy { $0 == "0" || $0 == "." }
        return (value < 0 && !isZero ? "-" : "") + grouped + fraction
    }

    /// "1.5M": the value in thousands (K), millions (M), billions (B) or trillions (T), with up to two decimals.
    static func compact(_ value: Double) -> String {
        let units: [(size: Double, symbol: String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K"), (1, "")]
        let magnitude = abs(value)
        var unit = units.count - 1
        for (index, candidate) in units.enumerated() where magnitude >= candidate.size * (1 - 1e-12) {
            unit = index
            break
        }
        var scaled = (magnitude / units[unit].size * 100).rounded() / 100
        // 999,999 rounds to 1000K: say 1M instead.
        if scaled >= 1000, unit > 0 {
            unit -= 1
            scaled = (magnitude / units[unit].size * 100).rounded() / 100
        }
        let digits = shortDecimal(scaled)
        let sign = value < 0 && digits != "0" ? "-" : ""
        return sign + digits + units[unit].symbol
    }

    /// "1.5E+15", "-2E-12": numbers too big or small to show in full, with up to two decimals.
    static func scientific(_ value: Double) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        var exponent = Int(log10(abs(value)).rounded(.down))
        // Divided in two steps so neither power of ten overflows or underflows near the ends of the range.
        var mantissa = value / pow(10, Double(exponent / 2)) / pow(10, Double(exponent - exponent / 2))
        if abs((mantissa * 100).rounded()) >= 1000 {
            mantissa /= 10
            exponent += 1
        } else if abs((mantissa * 100).rounded()) < 100 {
            mantissa *= 10
            exponent -= 1
        }
        let power = abs(exponent) < 10 ? "0\(abs(exponent))" : String(abs(exponent))
        return shortDecimal(mantissa) + "E" + (exponent < 0 ? "-" : "+") + power
    }

    /// Up to two decimals, trailing zeros dropped: "2.5", "10", "1.25".
    static func shortDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let hundredths = (value * 100).rounded()
        guard abs(hundredths) < 9e15 else { return String(format: "%.0f", value) }
        let whole = Int(hundredths) / 100
        let fraction = abs(Int(hundredths) % 100)
        let sign = hundredths < 0 && whole == 0 ? "-" : ""
        if fraction == 0 { return sign + String(whole) }
        return sign + (fraction % 10 == 0 ? "\(whole).\(fraction / 10)" : "\(whole).\(fraction < 10 ? "0" : "")\(fraction)")
    }
}
