import Foundation

extension ODPDocumentReader {
    /// The chart an embedded object holds, from the object's folder (`xlink:href="./Object 1"`) or a document written
    /// inside the `draw:object`. Nil when the object isn't a chart, or its numbers can't be found; what a chart has that
    /// the model can't keep leaves a warning.
    func chart(_ object: ODFNode) -> Chart? {
        var root = object.child("office:document")
        if root == nil, let href = object["xlink:href"] {
            var path = href.trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("./") { path.removeFirst(2) }
            if path.contains("%"), let decoded = path.removingPercentEncoding { path = decoded }
            while path.hasSuffix("/") { path.removeLast() }
            guard !path.isEmpty, !path.contains("://") else { return nil }
            root = try? xml(path + "/content.xml")
        }
        guard let root, let result = ODPChartReader.read(root) else { return nil }
        warnings.formUnion(result.warnings)
        return result.chart
    }
}

/// Reads an embedded OpenDocument chart (LibreOffice's, PuggleSlides' or another app's) into a chart: its kind from the chart
/// class and plot area, its numbers from the local table the series point into, and its titles, legend, gridlines, data
/// labels, font, background, axis range and series colors from their styles. LibreOffice's other chart classes become the
/// nearest supported kind with a warning, as do 3D charts, combined chart types, secondary axes, trend lines and error
/// bars. Adapted from PuggleSheets' ODS chart reader.
enum ODPChartReader {
    struct Result {
        var chart: Chart
        var warnings: Set<ImportWarning>
    }

    /// A cell of the local table: what it shows, and its number if it has one.
    struct Cell {
        var text: String
        var value: Double?
    }

    /// A block of the local table, zero-based and inclusive.
    struct Range: Equatable {
        var firstRow: Int
        var firstColumn: Int
        var lastRow: Int
        var lastColumn: Int
    }

    /// Damaged repeat counts can't make the table bigger than this.
    static let maxRows = 10_000
    static let maxColumns = 256
    static let maxCells = 200_000

    static func read(_ root: ODFNode) -> Result? {
        guard let chart = root.child("office:body")?.child("office:chart")?.child("chart:chart"), let plotArea = chart.child("chart:plot-area") else {
            return nil
        }
        var reader = Reader(root: root, chart: chart)
        return reader.read(plotArea)
    }

    // MARK: Addresses

    /// Splits `text` at `separator`, except inside quoted table names.
    static func split(_ text: Substring, at separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var start = text.startIndex
        var quoted = false
        for index in text.indices {
            let character = text[index]
            if character == "'" {
                quoted.toggle()
            } else if character == separator, !quoted {
                if start < index { parts.append(text[start..<index]) }
                start = text.index(after: index)
            }
        }
        if start < text.endIndex { parts.append(text[start...]) }
        return parts
    }

    /// "local-table.$B$2", "'local-table'.B2" or ".$B$2" as a zero-based row and column; the table's name is ignored, as an
    /// object's chart only reads its own table.
    static func cell(_ text: Substring) -> (row: Int, column: Int)? {
        var reference = text
        var quoted = false
        for index in text.indices {
            if text[index] == "'" { quoted.toggle() } else if text[index] == ".", !quoted { reference = text[text.index(after: index)...] }
        }
        var column = 0, letters = 0
        var digits = ""
        for character in reference where character != "$" {
            if let ascii = character.asciiValue, character.isLetter, digits.isEmpty {
                let value = Int(ascii) - (character.isUppercase ? 65 : 97)
                guard (0..<26).contains(value), letters < 4 else { return nil }
                column = column * 26 + value + 1
                letters += 1
            } else if character.isASCII, character.isNumber, digits.count < 8 {
                digits.append(character)
            } else {
                return nil
            }
        }
        guard letters > 0, let row = Int(digits), row >= 1 else { return nil }
        return (row - 1, column - 1)
    }

    /// A space-separated list of cell ranges.
    static func ranges(_ text: String?) -> [Range] {
        guard let text else { return [] }
        var result: [Range] = []
        for item in split(Substring(text), at: " ").prefix(64) {
            let ends = split(item, at: ":")
            guard let first = ends.first, let start = cell(first) else { continue }
            let end = ends.count > 1 ? cell(ends[1]) ?? start : start
            result.append(Range(firstRow: min(start.row, end.row), firstColumn: min(start.column, end.column),
                                lastRow: max(start.row, end.row), lastColumn: max(start.column, end.column)))
        }
        return result
    }

    // MARK: Text

    /// A paragraph's text with ODF's white-space rules: runs of spaces, tabs and line ends are one space, none at the
    /// start; `text:s` adds spaces, `text:tab` a tab and `text:line-break` a new line.
    static func paragraphText(_ paragraph: ODFNode) -> String {
        var result = ""
        var lastWasSpace = true
        func walk(_ node: ODFNode, depth: Int) {
            guard depth < 16 else { return }
            for child in node.children {
                if child.isText {
                    for character in child.text {
                        if character == " " || character == "\t" || character == "\n" || character == "\r" || character == "\r\n" {
                            if lastWasSpace { continue }
                            result.append(" ")
                            lastWasSpace = true
                        } else {
                            result.append(character)
                            lastWasSpace = false
                        }
                    }
                    continue
                }
                switch child.name {
                case "text:s":
                    result += String(repeating: " ", count: min(max(ODFValue.int(child["text:c"]) ?? 1, 1), 1000))
                    lastWasSpace = false
                case "text:tab":
                    result += "\t"
                    lastWasSpace = false
                case "text:line-break":
                    result += "\n"
                    lastWasSpace = true
                default:
                    walk(child, depth: depth + 1)
                }
            }
        }
        walk(paragraph, depth: 0)
        return result
    }

    /// The paragraphs of a title or cell, one per line.
    static func text(_ node: ODFNode?) -> String {
        guard let node else { return "" }
        return node.elements.filter { $0.name == "text:p" || $0.name == "text:h" }.map(paragraphText).joined(separator: "\n")
    }

    /// The local table's cells, row by row: header rows first, repeated rows and cells written out.
    static func grid(_ table: ODFNode?) -> [[Cell]] {
        guard let table else { return [] }
        var rows: [[Cell]] = []
        var total = 0
        func collect(_ node: ODFNode, depth: Int) {
            guard depth < 8 else { return }
            for child in node.elements {
                switch child.name {
                case "table:table-row":
                    var cells: [Cell] = []
                    for item in child.elements where item.name == "table:table-cell" || item.name == "table:covered-table-cell" {
                        let repeated = min(max(ODFValue.int(item["table:number-columns-repeated"]) ?? 1, 1), maxColumns - cells.count)
                        guard repeated > 0 else { break }
                        let cell = Self.cell(item)
                        cells += Array(repeating: cell, count: repeated)
                    }
                    let repeated = min(max(ODFValue.int(child["table:number-rows-repeated"]) ?? 1, 1), maxRows - rows.count,
                                       cells.isEmpty ? maxRows : (maxCells - total) / cells.count)
                    guard repeated > 0 else { return }
                    rows += Array(repeating: cells, count: repeated)
                    total += repeated * cells.count
                case "table:table-rows", "table:table-header-rows", "table:table-row-group":
                    collect(child, depth: depth + 1)
                default:
                    continue
                }
            }
        }
        collect(table, depth: 0)
        return rows
    }

    /// A cell's text and number. Numbers come from `office:value`; a cell that states no type is a number if its text is one.
    static func cell(_ node: ODFNode) -> Cell {
        let text = Self.text(node)
        var value: Double?
        switch node["office:value-type"] {
        case "float", "percentage", "currency":
            value = ODFValue.double(node["office:value"])
        case nil:
            value = ODFValue.double(text)
        default:
            value = nil
        }
        return Cell(text: text, value: value)
    }

    // MARK: Reading

    private struct Reader {
        let root: ODFNode
        let chart: ODFNode
        var styles: [String: ODFNode] = [:]
        var fonts: [String: String] = [:]
        var grid: [[Cell]] = []
        var warnings = Set<ImportWarning>()

        init(root: ODFNode, chart: ODFNode) {
            self.root = root
            self.chart = chart
            for style in root.child("office:automatic-styles")?.children("style:style") ?? [] {
                if let name = style["style:name"] { styles[name] = style }
            }
            for face in root.child("office:font-face-decls")?.children("style:font-face") ?? [] {
                if let name = face["style:name"] { fonts[name] = face["svg:font-family"].flatMap(ODFTextProperties.firstFamily) ?? name }
            }
            grid = ODPChartReader.grid(chart.child("table:table"))
        }

        func property(_ node: ODFNode?, _ element: String, _ attribute: String) -> String? {
            guard let name = node?["chart:style-name"], let style = styles[name] else { return nil }
            return style.child(element)?[attribute]
        }

        func chartProperty(_ node: ODFNode?, _ attribute: String) -> String? { property(node, "style:chart-properties", attribute) }

        func graphicProperty(_ node: ODFNode?, _ attribute: String) -> String? { property(node, "style:graphic-properties", attribute) }

        func fontFamily(_ node: ODFNode?) -> String? {
            guard let name = node?["chart:style-name"], let text = styles[name]?.child("style:text-properties") else { return nil }
            if let face = text["style:font-name"], !face.isEmpty { return fonts[face] ?? face }
            return text["fo:font-family"].flatMap(ODFTextProperties.firstFamily)
        }

        /// The cells of a list of ranges, row by row, as far as the table goes.
        func cells(_ ranges: [Range]) -> [Cell?] {
            var result: [Cell?] = []
            for range in ranges {
                let lastRow = min(range.lastRow, grid.count - 1)
                guard range.firstRow <= lastRow else { continue }
                for row in range.firstRow...lastRow {
                    let lastColumn = min(range.lastColumn, ODPChartReader.maxColumns - 1)
                    guard range.firstColumn <= lastColumn, result.count < ODPChartReader.maxCells else { break }
                    for column in range.firstColumn...lastColumn {
                        result.append(column < grid[row].count ? grid[row][column] : nil)
                    }
                }
            }
            return result
        }

        func label(_ cell: Cell?) -> String {
            guard let cell else { return "" }
            if !cell.text.isEmpty { return cell.text }
            return cell.value.map { ODPChartWriter.number($0) } ?? ""
        }

        /// The heading over a column of labels (or before a row of them).
        func heading(_ ranges: [Range]) -> String {
            guard let range = ranges.first else { return "" }
            if range.firstColumn == range.lastColumn, range.firstRow > 0 {
                return label(cells([Range(firstRow: range.firstRow - 1, firstColumn: range.firstColumn, lastRow: range.firstRow - 1, lastColumn: range.firstColumn)]).first ?? nil)
            }
            if range.firstRow == range.lastRow, range.firstColumn > 0 {
                return label(cells([Range(firstRow: range.firstRow, firstColumn: range.firstColumn - 1, lastRow: range.firstRow, lastColumn: range.firstColumn - 1)]).first ?? nil)
            }
            return ""
        }

        static func localName(_ qualified: String?) -> String {
            guard let qualified else { return "" }
            return qualified.split(separator: ":").last.map(String.init) ?? qualified
        }

        mutating func read(_ plotArea: ODFNode) -> Result? {
            // Without its own table, the chart's numbers are somewhere this file doesn't hold.
            guard !grid.isEmpty else { return nil }
            func plot(_ attribute: String) -> String? { chartProperty(plotArea, attribute) }
            let chartClass = Self.localName(chart["chart:class"])
            let stacked = plot("chart:stacked") == "true", percent = plot("chart:percentage") == "true"
            let kind = self.kind(chartClass, vertical: plot("chart:vertical") == "true", stacked: stacked, percent: percent,
                                 interpolation: plot("chart:interpolation"))
            if plot("chart:three-dimensional") == "true" { warnings.insert(.charts) }

            let axes = plotArea.children("chart:axis")
            let xAxis = axes.first { $0["chart:dimension"] == "x" && $0["chart:name"] != "secondary-x" }
            let yAxis = axes.first { $0["chart:dimension"] == "y" && !($0["chart:name"] ?? "").hasPrefix("secondary") }
            if axes.contains(where: { $0["chart:dimension"] == "z" || ($0["chart:name"] ?? "").hasPrefix("secondary") }) { warnings.insert(.charts) }
            if plotArea.elements.contains(where: { ["chart:stock-gain-marker", "chart:stock-loss-marker", "chart:stock-range-line"].contains($0.name) }) {
                warnings.insert(.charts)
            }

            // Series and the cells they point into.
            var seriesNodes = plotArea.children("chart:series")
            let expectedClass = chartClass == "ring" ? "circle" : chartClass
            for node in seriesNodes {
                if let own = node["chart:class"], Self.localName(own) != expectedClass, Self.localName(own) != chartClass { warnings.insert(.charts) }
                if let axis = node["chart:attached-axis"], axis.hasPrefix("secondary") { warnings.insert(.charts) }
                if node.elements.contains(where: { ["chart:regression-curve", "chart:error-indicator", "chart:mean-value"].contains($0.name) }) {
                    warnings.insert(.charts)
                }
            }
            if kind.isPie, seriesNodes.count > 1 {
                // LibreOffice draws a pie's further series as rings; pies here show the first.
                warnings.insert(.charts)
                seriesNodes = [seriesNodes[0]]
            }
            var series: [ChartSeries] = []
            // A chart whose numbers belong to the document around it (`xlink:href=".."`, as a spreadsheet's charts are) points
            // at that document's cells; LibreOffice still writes the numbers into the chart's own table, which is read instead.
            let ownData = chart["xlink:href"] != ".."
            var categories = ownData ? ODPChartReader.ranges(xAxis?.child("chart:categories")?["table:cell-range-address"]) : []
            if ownData, seriesNodes.contains(where: { $0["chart:values-cell-range-address"] != nil }) {
                for node in seriesNodes {
                    let values = cells(ODPChartReader.ranges(node["chart:values-cell-range-address"])).map { $0?.value }
                    let name = label(cells(ODPChartReader.ranges(node["chart:label-cell-address"])).first ?? nil)
                    series.append(ChartSeries(name: name, values: values, color: color(of: node, index: series.count, kind: kind)))
                }
            } else {
                // No series say where their numbers are: they're the plot area's block (or the whole table), a series per
                // column (or row).
                let derived = deriveSeries(plotArea, wholeTable: !ownData)
                series = derived.series
                for (index, node) in seriesNodes.enumerated() where index < series.count { series[index].color = color(of: node, index: index, kind: kind) }
                if categories.isEmpty { categories = derived.categories }
            }
            if kind.isPie { series = Array(series.prefix(1)) }

            // Labels: a scatter chart's x values come from its first series' domain.
            var labelRanges = categories
            if ownData, kind == .scatter, let domain = seriesNodes.first?.child("chart:domain")?["table:cell-range-address"] {
                labelRanges = ODPChartReader.ranges(domain)
            }
            let labels = cells(labelRanges).map(label)
            let data = ChartData(labelHeading: heading(labelRanges), labels: labels, series: series)

            // Titles: horizontal bars have their categories up the side. Charts have no subtitle; it stays as the
            // title's last line rather than going.
            let xTitle = ODPChartReader.text(xAxis?.child("chart:title")), yTitle = ODPChartReader.text(yAxis?.child("chart:title"))
            let title = [ODPChartReader.text(chart.child("chart:title")), ODPChartReader.text(chart.child("chart:subtitle"))]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            var result = Chart(kind: kind, data: data, title: title, horizontalAxisTitle: kind.isBar ? yTitle : xTitle,
                               verticalAxisTitle: kind.isBar ? xTitle : yTitle)
            if let legend = chart.child("chart:legend") {
                switch legend["chart:legend-position"] {
                case nil: result.legend = .auto
                case "start"?: result.legend = .left
                case "top"?, "top-start"?, "top-end"?: result.legend = .top
                case "bottom"?, "bottom-start"?, "bottom-end"?: result.legend = .bottom
                default: result.legend = .right
                }
            } else {
                result.legend = ChartLegendPosition.none
            }
            result.showsGridlines = yAxis?.children("chart:grid").contains { ($0["chart:class"] ?? "major") == "major" } ?? false
            result.showsDataLabels = seriesNodes.contains { node in
                let number = chartProperty(node, "chart:data-label-number")
                return ["value", "percentage", "value-and-percentage"].contains(number ?? "") || chartProperty(node, "chart:data-label-text") == "true"
            }
            if kind == .donut, let hole = ODFValue.percent(plot("chart:hole-size")) { result.pieHole = min(max(hole, 0), 0.95) }
            if let yAxis {
                result.verticalMinimum = ODFValue.double(chartProperty(yAxis, "chart:minimum"))
                result.verticalMaximum = ODFValue.double(chartProperty(yAxis, "chart:maximum"))
            }
            let fill = graphicProperty(chart, "draw:fill")
            if fill != "none", let background = ODFValue.color(graphicProperty(chart, "draw:fill-color")), background != .white {
                result.backgroundColor = background
            }
            let textNodes: [ODFNode?] = [chart, chart.child("chart:title"), chart.child("chart:legend"), xAxis, yAxis] + seriesNodes.map { Optional($0) }
            for node in textNodes {
                if let family = fontFamily(node) {
                    result.fontFamily = family
                    break
                }
            }
            return Result(chart: result, warnings: warnings)
        }

        /// The kind for a chart class; classes without one become the nearest, with a warning.
        mutating func kind(_ chartClass: String, vertical: Bool, stacked: Bool, percent: Bool, interpolation: String?) -> ChartKind {
            switch chartClass {
            case "bar":
                if vertical { return percent ? .percentBar : stacked ? .stackedBar : .bar }
                return percent ? .percentColumn : stacked ? .stackedColumn : .column
            case "line":
                if stacked || percent { warnings.insert(.charts) }
                switch interpolation {
                case "cubic-spline", "b-spline": return .smoothLine
                case nil, "none": return .line
                default:
                    warnings.insert(.charts)
                    return .line
                }
            case "area":
                return percent ? .percentArea : stacked ? .stackedArea : .area
            case "circle": return .pie
            case "ring": return .donut
            case "scatter": return .scatter
            case "bubble":
                warnings.insert(.charts)
                return .scatter
            case "radar", "stock":
                warnings.insert(.charts)
                return .line
            case "filled-radar":
                warnings.insert(.charts)
                return .area
            default:
                warnings.insert(.charts)
                return .column
            }
        }

        /// A series' own color, or nil when it's the palette's color for its place anyway. Lines take their stroke color,
        /// everything else its fill.
        func color(of node: ODFNode, index: Int, kind: ChartKind) -> RGBColor? {
            let fill = ODFValue.color(graphicProperty(node, "draw:fill-color")), stroke = ODFValue.color(graphicProperty(node, "svg:stroke-color"))
            let isLine = kind == .line || kind == .smoothLine
            guard let color = isLine ? stroke ?? fill : fill ?? stroke else { return nil }
            return color == Chart.palette[index % Chart.palette.count] ? nil : color
        }

        /// Series from the plot area's block (or the whole table) when no series says where its numbers are: a series per
        /// column below the names in the first row, the labels in the first column (or the other way round for rows). A
        /// copy of another document's numbers has its names and labels around it, as LibreOffice writes the copy.
        func deriveSeries(_ plotArea: ODFNode, wholeTable: Bool) -> (series: [ChartSeries], categories: [Range]) {
            let width = grid.map(\.count).max() ?? 0
            guard width > 0 else { return ([], []) }
            let whole = Range(firstRow: 0, firstColumn: 0, lastRow: grid.count - 1, lastColumn: width - 1)
            let block = wholeTable ? whole : ODPChartReader.ranges(plotArea["table:cell-range-address"]).first ?? whole
            let labels = wholeTable ? "both" : plotArea["chart:data-source-has-labels"] ?? "none"
            let namesInFirstRow = labels == "row" || labels == "both", labelsInFirstColumn = labels == "column" || labels == "both"
            let byRows = chartProperty(plotArea, "chart:series-source") == "rows"
            let firstDataRow = block.firstRow + (namesInFirstRow ? 1 : 0), firstDataColumn = block.firstColumn + (labelsInFirstColumn ? 1 : 0)
            var series: [ChartSeries] = []
            let lastColumn = min(block.lastColumn, ODPChartReader.maxColumns - 1), lastRow = min(block.lastRow, grid.count - 1)
            if byRows {
                guard firstDataRow <= lastRow else { return ([], []) }
                for row in firstDataRow...lastRow where series.count < ODPChartReader.maxColumns {
                    let values = cells([Range(firstRow: row, firstColumn: firstDataColumn, lastRow: row, lastColumn: lastColumn)]).map { $0?.value }
                    let name = labelsInFirstColumn ? label(cells([Range(firstRow: row, firstColumn: block.firstColumn, lastRow: row, lastColumn: block.firstColumn)]).first ?? nil) : ""
                    series.append(ChartSeries(name: name, values: values))
                }
                let categories = namesInFirstRow ? [Range(firstRow: block.firstRow, firstColumn: firstDataColumn, lastRow: block.firstRow, lastColumn: lastColumn)] : []
                return (series, categories)
            }
            guard firstDataColumn <= lastColumn else { return ([], []) }
            for column in firstDataColumn...lastColumn {
                let values = cells([Range(firstRow: firstDataRow, firstColumn: column, lastRow: lastRow, lastColumn: column)]).map { $0?.value }
                let name = namesInFirstRow ? label(cells([Range(firstRow: block.firstRow, firstColumn: column, lastRow: block.firstRow, lastColumn: column)]).first ?? nil) : ""
                series.append(ChartSeries(name: name, values: values))
            }
            let categories = labelsInFirstColumn ? [Range(firstRow: firstDataRow, firstColumn: block.firstColumn, lastRow: lastRow, lastColumn: block.firstColumn)] : []
            return (series, categories)
        }
    }
}
