import Foundation

/// Reads DrawingML chart parts into charts. The numbers come from the part's caches (what PowerPoint
/// shows before it opens the workbook), and from the embedded workbook where a cache is missing. PowerPoint's other
/// chart types become the nearest supported kind with the data kept, and are reported as approximate, since saving them
/// would change them: 3D charts are drawn flat, a pie of pie as one pie, and kinds without a reasonable counterpart
/// (radar, stock, bubble and surface charts, stacked lines, combinations of kinds) as the nearest kind.
struct PPTXChartReader {
    var colors: PPTXColorReader
    /// The theme's colors, for series colors given as theme colors (the model keeps chart colors as RGB).
    var scheme: ColorScheme
    /// The chart's embedded workbook, opened when first needed.
    var workbook: () -> PPTXWorkbookReader?
    /// Points left out because they lie past what a chart is read with.
    private let losses = Losses()

    private final class Losses {
        var points = 0
    }

    /// The most points a chart is read with, over all its series once they're as long as the labels: far more than any
    /// real chart, few enough that a damaged part can't claim memory without end.
    static let maximumPoints = 1_000_000
    /// How many points a cache may claim past its last one (`ptCount` beyond the points it has): trailing gaps cost
    /// memory without being in the file.
    static let maximumTrailingGap = 1024

    struct Result {
        var chart: Chart?
        /// Something was drawn differently from PowerPoint, or left out.
        var isApproximate = false
    }

    private enum Family: Equatable {
        case column, bar, line, area, pie, doughnut, scatter
    }

    private struct Series {
        var order: Int
        var position: Int
        var name: String
        var labels: [String]?
        var labelReference: String?
        var values: [Double?]
        var color: RGBColor?
        var smooth: Bool
        var showsLabels: Bool?
    }

    func read(_ root: XNode) -> Result {
        guard root.name == "chartSpace", let chartNode = root.child("chart"), let plotArea = chartNode.child("plotArea") else {
            return Result(chart: nil, isApproximate: true)
        }
        var approximate = false
        losses.points = 0
        // Dates count from 1 January 1904 in charts made on old Macs.
        let date1904 = root.child("date1904").map { PPTXValue.bool($0["val"]) ?? true } ?? false
        var axes: [String: XNode] = [:]
        for node in plotArea.children where ["catAx", "valAx", "dateAx", "serAx"].contains(node.name) {
            if let id = node.child("axId")?["val"], axes[id] == nil { axes[id] = node }
        }

        var groups: [(node: XNode, family: Family)] = []
        for node in plotArea.children {
            let family: Family
            switch node.name {
            case "barChart", "bar3DChart": family = node.child("barDir")?["val"] == "bar" ? .bar : .column
            case "lineChart", "line3DChart": family = .line
            case "areaChart", "area3DChart": family = .area
            case "pieChart", "pie3DChart", "ofPieChart": family = .pie
            case "doughnutChart": family = .doughnut
            case "scatterChart": family = .scatter
            case "radarChart", "stockChart", "surfaceChart", "surface3DChart":
                family = .line
                approximate = true
            case "bubbleChart":
                family = .scatter
                approximate = true
            default:
                continue
            }
            // 3D charts and pie of pie aren't supported.
            if node.name.hasSuffix("3DChart") || node.name == "ofPieChart" { approximate = true }
            groups.append((node, family))
        }
        guard let primary = groups.first else { return Result(chart: nil, isApproximate: true) }
        // A combination of kinds is drawn as its first kind.
        if groups.contains(where: { $0.family != primary.family }) { approximate = true }

        var series: [Series] = []
        var groupLabels = false
        var budget = Self.maximumPoints
        for (index, group) in groups.enumerated() {
            for node in group.node.children("ser") {
                guard budget > 0 else {
                    approximate = true
                    break
                }
                let item = readSeries(node, family: group.family, position: series.count, limit: min(budget, PPTXChartSheet.maximumRows),
                                      date1904: date1904)
                budget -= max(1, item.values.count, item.labels?.count ?? 0)
                series.append(item)
            }
            if index == 0, let shown = Self.labelsShown(group.node.child("dLbls")) { groupLabels = shown }
        }
        series.sort { ($0.order, $0.position) < ($1.order, $1.position) }
        if losses.points > 0 { approximate = true }
        // Every series is as long as the labels once drawn or saved, so their number is bounded by that length too.
        let rows = series.map { max($0.values.count, $0.labels?.count ?? 0) }.max() ?? 0
        let allowed = max(1, Self.maximumPoints / max(1, rows))
        if series.count > allowed {
            series = Array(series.prefix(allowed))
            approximate = true
        }

        let grouping = primary.node.child("grouping")?["val"] ?? "standard"
        let kind: ChartKind
        switch primary.family {
        case .column: kind = grouping == "stacked" ? .stackedColumn : grouping == "percentStacked" ? .percentColumn : .column
        case .bar: kind = grouping == "stacked" ? .stackedBar : grouping == "percentStacked" ? .percentBar : .bar
        case .area: kind = grouping == "stacked" ? .stackedArea : grouping == "percentStacked" ? .percentArea : .area
        case .line:
            // Stacked lines have no counterpart.
            if grouping == "stacked" || grouping == "percentStacked" { approximate = true }
            kind = !series.isEmpty && series.allSatisfy(\.smooth) ? .smoothLine : .line
        case .pie: kind = .pie
        case .doughnut: kind = .donut
        case .scatter: kind = .scatter
        }

        // The labels: the first series' that has them, else numbers 1, 2, 3 ….
        let labelSource = series.first { $0.labels != nil }
        var data = ChartData(labels: labelSource?.labels ?? [], series: series.enumerated().map { index, item in
            // Colors that are just the palette's stay automatic.
            let color = item.color == Chart.palette[index % Chart.palette.count] ? nil : item.color
            return ChartSeries(name: item.name, values: item.values, color: color)
        })
        if data.labels.isEmpty, data.rowCount > 0 { data.labels = (1...data.rowCount).map(String.init) }
        if let reference = labelSource?.labelReference { data.labelHeading = heading(above: reference) ?? "" }

        var chart = Chart(kind: kind, data: data)
        chart.title = title(chartNode, series: series)
        chart.legend = Self.legend(chartNode.child("legend"))
        chart.showsDataLabels = groupLabels || (!series.isEmpty && series.allSatisfy { $0.showsLabels == true })

        // The primary group's axes: bar charts lay their categories vertically; scatter charts have two value axes.
        let groupAxes = primary.node.children("axId").compactMap { $0["val"] }.compactMap { axes[$0] }
        let categoryAxis = groupAxes.first { $0.name == "catAx" || $0.name == "dateAx" }
        let valueAxes = groupAxes.filter { $0.name == "valAx" }
        var valueAxis: XNode?, horizontal: XNode?, vertical: XNode?
        switch primary.family {
        case .scatter:
            horizontal = valueAxes.first { ["b", "t"].contains($0.child("axPos")?["val"] ?? "") } ?? valueAxes.first
            vertical = valueAxes.first { $0 !== horizontal }
            valueAxis = vertical
        case .bar:
            valueAxis = valueAxes.first
            horizontal = valueAxis
            vertical = categoryAxis
        default:
            valueAxis = valueAxes.first
            horizontal = categoryAxis
            vertical = valueAxis
        }
        chart.horizontalAxisTitle = horizontal?.child("title").map { Self.text(of: $0) } ?? ""
        chart.verticalAxisTitle = vertical?.child("title").map { Self.text(of: $0) } ?? ""
        if let axis = valueAxis {
            let scaling = axis.child("scaling")
            chart.verticalMinimum = PPTXValue.double(scaling?.child("min")?["val"])
            chart.verticalMaximum = PPTXValue.double(scaling?.child("max")?["val"])
            chart.showsGridlines = axis.child("majorGridlines") != nil
        } else if !kind.isPie {
            chart.showsGridlines = false
        }
        if kind == .donut, let hole = PPTXValue.double(primary.node.child("holeSize")?["val"]?.replacingOccurrences(of: "%", with: "")) {
            chart.pieHole = min(max(hole / 100, 0.01), 0.9)
        }
        if let fill = root.child("spPr")?.child("solidFill"), let color = colors.color(in: fill)?.resolved(scheme).rgb, color != .white {
            chart.backgroundColor = color
        }
        if let font = root.child("txPr")?.firstDescendant("latin")?["typeface"], !font.isEmpty, !font.hasPrefix("+") {
            chart.fontFamily = font
        }
        return Result(chart: chart, isApproximate: approximate)
    }

    // MARK: Series

    /// One series, its caches no longer than `limit` points.
    private func readSeries(_ node: XNode, family: Family, position: Int, limit: Int, date1904: Bool) -> Series {
        let order = PPTXValue.int(node.child("order")?["val"]) ?? PPTXValue.int(node.child("idx")?["val"]) ?? position
        var name = ""
        if let tx = node.child("tx") {
            if let reference = tx.child("strRef") {
                // A name is one cell: the first of its reference.
                if let cached = strings(reference.child("strCache"), limit: 1) {
                    name = cached.first ?? ""
                } else if let formula = reference.child("f")?.text, let cell = workbookValues(formula, limit: 1, isName: true)?.first {
                    name = cell?.text ?? ""
                }
            } else if let value = tx.child("v") {
                name = PPTXWorkbook.unescaped(value.text)
            }
        }
        var labels: [String]?
        var labelReference: String?
        if let source = node.child("cat") ?? node.child("xVal") {
            (labels, labelReference) = labelValues(source, limit: limit, date1904: date1904)
        }
        var values: [Double?] = []
        if let source = node.child("val") ?? node.child("yVal") {
            if let reference = source.child("numRef") {
                values = numbers(reference.child("numCache"), limit: limit)?.values
                    ?? reference.child("f").flatMap { workbookValues($0.text, limit: limit)?.map { $0?.number } } ?? []
            } else if let literal = source.child("numLit") {
                values = numbers(literal, limit: limit)?.values ?? []
            }
        }
        let shape = node.child("spPr")
        var color: ColorRef?
        switch family {
        case .column, .bar, .area, .pie, .doughnut: color = colors.color(in: shape?.child("solidFill"))
        case .line: color = colors.color(in: shape?.child("ln")?.child("solidFill"))
        case .scatter:
            color = colors.color(in: node.child("marker")?.child("spPr")?.child("solidFill")) ?? colors.color(in: shape?.child("ln")?.child("solidFill"))
        }
        var rgb = color.map { $0.withAlpha(nil).resolved(scheme).rgb }
        if rgb == nil, family != .pie, family != .doughnut {
            // PowerPoint's automatic colors, by the series' index: the theme's accents, then darker and lighter versions.
            rgb = Self.automaticColor(PPTXValue.int(node.child("idx")?["val"]) ?? position, scheme: scheme)
        }
        let smooth = node.child("smooth").map { PPTXValue.bool($0["val"]) ?? true } ?? false
        return Series(order: order, position: position, name: name, labels: labels, labelReference: labelReference, values: values,
                      color: rgb, smooth: smooth, showsLabels: Self.labelsShown(node.child("dLbls")))
    }

    /// PowerPoint's colors for series without their own: accent 1 to 6, then the six again darker, then lighter.
    static func automaticColor(_ index: Int, scheme: ColorScheme) -> RGBColor {
        let accents: [ThemeColorSlot] = [.accent1, .accent2, .accent3, .accent4, .accent5, .accent6]
        let variations: [(lumMod: Double?, lumOff: Double?)] = [(nil, nil), (0.6, nil), (0.8, 0.2), (0.8, nil), (0.6, 0.4), (0.5, nil)]
        let index = max(0, index)
        let variation = variations[(index / accents.count) % variations.count]
        return ColorRef(.theme(accents[index % accents.count]), lumMod: variation.lumMod, lumOff: variation.lumOff).resolved(scheme).rgb
    }

    /// Labels from `cat` or `xVal`: cached text, cached numbers in their format, or several levels of labels (the
    /// innermost is kept); the workbook when nothing is cached.
    private func labelValues(_ source: XNode, limit: Int, date1904: Bool) -> ([String]?, String?) {
        if let reference = source.child("strRef") {
            let formula = reference.child("f")?.text
            let cached = strings(reference.child("strCache"), limit: limit) ?? formula.flatMap { workbookValues($0, limit: limit)?.map { $0?.text ?? "" } }
            return (cached, formula)
        }
        if let reference = source.child("numRef") {
            let formula = reference.child("f")?.text
            if let cache = numbers(reference.child("numCache"), limit: limit) {
                return (cache.values.map { $0.map { PPTXChartNumber.formatted($0, format: cache.format, date1904: date1904) } ?? "" }, formula)
            }
            return (formula.flatMap { workbookValues($0, limit: limit)?.map { $0?.text ?? "" } }, formula)
        }
        if let reference = source.child("multiLvlStrRef") {
            let level = reference.child("multiLvlStrCache")?.child("lvl")
            return (level.flatMap { strings($0, count: reference.child("multiLvlStrCache")?.child("ptCount"), limit: limit) }, reference.child("f")?.text)
        }
        if let literal = source.child("strLit") { return (strings(literal, limit: limit), nil) }
        if let literal = source.child("numLit"), let cache = numbers(literal, limit: limit) {
            return (cache.values.map { $0.map { PPTXChartNumber.formatted($0, format: cache.format, date1904: date1904) } ?? "" }, nil)
        }
        return (nil, nil)
    }

    /// A string cache's points by index; nil when there's no cache. Points past `limit` are left out, and counted.
    private func strings(_ cache: XNode?, count: XNode? = nil, limit: Int) -> [String]? {
        guard let cache else { return nil }
        let points = cache.children("pt").compactMap { point -> (Int, String)? in
            guard let index = PPTXValue.int(point["idx"]), index >= 0 else { return nil }
            guard index < limit else {
                losses.points += 1
                return nil
            }
            return (index, PPTXWorkbook.unescaped(point.child("v")?.text ?? ""))
        }
        let length = Self.length(declared: PPTXValue.int((count ?? cache.child("ptCount"))?["val"]), indexes: points.map(\.0), limit: limit)
        var result = Array(repeating: "", count: length)
        for (index, value) in points where index < length { result[index] = value }
        return result
    }

    /// A number cache's points by index (gaps are nil) and its format; nil when there's no cache.
    private func numbers(_ cache: XNode?, limit: Int) -> (values: [Double?], format: String)? {
        guard let cache else { return nil }
        let points = cache.children("pt").compactMap { point -> (Int, Double)? in
            guard let index = PPTXValue.int(point["idx"]), index >= 0, let value = PPTXValue.double(point.child("v")?.text) else { return nil }
            guard index < limit else {
                losses.points += 1
                return nil
            }
            return (index, value)
        }
        let length = Self.length(declared: PPTXValue.int(cache.child("ptCount")?["val"]), indexes: points.map(\.0), limit: limit)
        var result = [Double?](repeating: nil, count: length)
        for (index, value) in points where index < length { result[index] = value }
        return (result, cache.child("formatCode")?.text ?? "General")
    }

    /// A cache's length: its point count, grown to take in every point (all of them below `limit`), with no more than
    /// a bounded gap after the last.
    private static func length(declared: Int?, indexes: [Int], limit: Int) -> Int {
        let end = (indexes.max() ?? -1) + 1
        return max(0, min(max(declared ?? 0, end), end + maximumTrailingGap, limit))
    }

    /// The workbook's cells a reference names, at most `limit` of them; a name is only ever its reference's first cell.
    private func workbookValues(_ formula: String, limit: Int, isName: Bool = false) -> [PPTXCellValue?]? {
        guard let values = workbook()?.values(formula, limit: max(0, limit)) else { return nil }
        if !isName, let reference = PPTXCellReference(formula), reference.count > limit { losses.points += 1 }
        return values
    }

    /// The label column's heading: the cell above the labels (or left of them, for labels along a row).
    private func heading(above formula: String) -> String? {
        guard let reference = PPTXCellReference(formula), let workbook = workbook() else { return nil }
        let isColumn = reference.first.column == reference.last.column
        let address = isColumn ? PPTXCellAddress(row: reference.first.row - 1, column: reference.first.column)
            : PPTXCellAddress(row: reference.first.row, column: reference.first.column - 1)
        guard address.row >= 0, address.column >= 0 else { return nil }
        return workbook.value(sheet: reference.sheet, at: address)?.text
    }

    // MARK: Titles, legend, labels

    /// The chart's title, or PowerPoint's automatic one: a lone series' name, unless the title was deleted.
    private func title(_ chart: XNode, series: [Series]) -> String {
        let deleted = chart.child("autoTitleDeleted").map { PPTXValue.bool($0["val"]) ?? true } ?? false
        if let title = chart.child("title") {
            if title.child("tx") != nil { return Self.text(of: title) }
            return series.count == 1 ? series[0].name : "Chart Title"
        }
        return !deleted && series.count == 1 ? series[0].name : ""
    }

    /// A title's text: rich text paragraphs, one per line, or the cached text of a title taken from a cell.
    static func text(of title: XNode) -> String {
        guard let text = title.child("tx") else { return "" }
        if let rich = text.child("rich") {
            return rich.children("p").map { paragraph in
                paragraph.children.map { run -> String in
                    switch run.name {
                    case "r", "fld": run.child("t")?.text ?? ""
                    case "br": "\n"
                    default: ""
                    }
                }.joined()
            }.joined(separator: "\n")
        }
        return text.child("strRef")?.child("strCache")?.child("pt")?.child("v")?.text ?? ""
    }

    private static func legend(_ node: XNode?) -> ChartLegendPosition {
        guard let node else { return .none }
        switch node.child("legendPos")?["val"] {
        case nil: return .auto
        case "t": return .top
        case "b": return .bottom
        case "l": return .left
        default: return .right
        }
    }

    /// Whether data labels show values: nil when the element isn't there.
    static func labelsShown(_ node: XNode?) -> Bool? {
        guard let node else { return nil }
        func flag(_ name: String) -> Bool { node.child(name).map { PPTXValue.bool($0["val"]) ?? true } ?? false }
        if flag("delete") { return false }
        return flag("showVal") || flag("showPercent") || flag("showCatName")
    }
}

extension PPTXChartNumber {
    /// A cached number shown in its Excel format: dates and times for date formats, percentages, fixed decimals, else
    /// as is. `date1904` counts dates from 1904, as charts made on old Macs do.
    static func formatted(_ value: Double, format: String, date1904: Bool = false) -> String {
        let code = format.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        // Quoted text, colors and locales don't change the number.
        let plain = code.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
        let lower = plain.lowercased()
        guard !plain.isEmpty, lower != "general", lower != "@" else { return string(value) }
        let isNumeric = lower.contains("0") || lower.contains("#")
        if lower.contains(where: { "ydhs".contains($0) }) || (lower.contains("m") && !isNumeric) {
            return date(value, format: plain, date1904: date1904) ?? string(value)
        }
        let decimals = plain.split(separator: ".").dropFirst().first.map { $0.prefix { $0 == "0" || $0 == "#" }.count } ?? 0
        let percent = plain.contains("%")
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        // Excel rounds halves away from zero, which is what half up means to NumberFormatter.
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = plain.contains(",")
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        let shown = formatter.string(from: NSNumber(value: percent ? value * 100 : value)) ?? string(value)
        return percent ? shown + "%" : shown
    }

    /// An Excel date serial (days since 30 December 1899, or since 1 January 1904) in a date and time format's
    /// pattern. As in Excel, `m` beside an hour or a second is minutes, and hours run to 12 when there's an AM/PM.
    private static func date(_ serial: Double, format: String, date1904: Bool) -> String? {
        // Excel's dates run from 1900 (or 1904) to the end of 9999.
        guard serial.isFinite, serial >= 0, serial < 2_958_466 else { return nil }
        enum Token {
            case field(Character, Int)
            case meridiem
            case literal(String)
        }
        var tokens: [Token] = []
        var index = format.startIndex
        while index < format.endIndex {
            let rest = format[index...].lowercased()
            if rest.hasPrefix("am/pm") || rest.hasPrefix("a/p") {
                tokens.append(.meridiem)
                index = format.index(index, offsetBy: rest.hasPrefix("am/pm") ? 5 : 3)
                continue
            }
            let character = Character(format[index].lowercased())
            var next = format.index(after: index)
            if "ymdhs".contains(character) {
                var count = 1
                while next < format.endIndex, Character(format[next].lowercased()) == character {
                    count += 1
                    next = format.index(after: next)
                }
                tokens.append(.field(character, count))
            } else if "/-:., ".contains(character) {
                tokens.append(.literal(String(format[index])))
            } else if character == "\\", next < format.endIndex {
                // An escaped character is shown as it is.
                tokens.append(.literal(String(format[next])))
                next = format.index(after: next)
            }
            index = next
        }
        let hasMeridiem = tokens.contains { if case .meridiem = $0 { return true } else { return false } }
        func field(at position: Int, step: Int) -> Character? {
            var position = position + step
            while tokens.indices.contains(position) {
                if case .field(let kind, _) = tokens[position] { return kind }
                position += step
            }
            return nil
        }
        var pattern = ""
        for (position, token) in tokens.enumerated() {
            switch token {
            case .meridiem:
                pattern += "a"
            case .literal(let text):
                pattern += text.contains(where: \.isLetter) ? "'\(text)'" : text
            case .field(let kind, let count):
                switch kind {
                case "y": pattern += count <= 2 ? "yy" : "yyyy"
                case "m" where field(at: position, step: -1) == "h" || field(at: position, step: 1) == "s":
                    pattern += count == 1 ? "m" : "mm"
                case "m": pattern += count == 1 ? "M" : count == 2 ? "MM" : count == 3 ? "MMM" : count == 4 ? "MMMM" : "MMMMM"
                case "d": pattern += count == 1 ? "d" : count == 2 ? "dd" : count == 3 ? "EEE" : "EEEE"
                case "h": pattern += String(repeating: hasMeridiem ? "h" : "H", count: min(count, 2))
                default: pattern += count == 1 ? "s" : "ss"
                }
            }
        }
        guard !pattern.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        // Excel counts a 29 February 1900 that never was, so its serials before March 1900 are a day ahead.
        let epoch: TimeInterval = date1904 ? -2_082_844_800 : serial < 60 ? -2_209_075_200 : -2_209_161_600
        // To the nearest second, as Excel shows times.
        let seconds = (serial * 86_400).rounded()
        return formatter.string(from: Date(timeIntervalSince1970: epoch + seconds))
    }
}
