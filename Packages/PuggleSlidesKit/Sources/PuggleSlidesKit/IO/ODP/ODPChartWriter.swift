import Foundation

extension ODPContentWriter {
    /// A chart: a frame holding an embedded chart object (`draw:object` naming the object's folder), as LibreOffice
    /// Impress writes the charts it inserts. The object's parts are collected by the document and stored beside it.
    func chart(_ element: SlideElement, _ chart: Chart, page: Page, into xml: inout XMLWriter) {
        var placement = Self.standardized(page.style(element).placement)
        // Charts don't flip.
        placement.flipHorizontal = false
        placement.flipVertical = false
        let path = document.chartObject(chart, size: placement.frame.size)
        xml.raw("<draw:frame")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute("draw:style-name", page.styles.name(Self.objectFrameStyle(master: document.themeMasterName(page.themeIndex)), kind: "gr"))
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        Self.geometry(placement, into: &xml)
        xml.raw("><draw:object")
        xml.attribute("xlink:href", "./" + path)
        xml.raw(" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>")
        altText(element, into: &xml)
        xml.raw("</draw:frame>")
    }
}

/// A chart as an embedded OpenDocument chart object ("Object 1/content.xml" …), laid out as LibreOffice Impress writes a
/// chart that keeps its own numbers (`xlink:href="."`): the numbers sit in the chart's local table ("local-table"), the
/// labels down its first column under the label heading and a column per series under its name, and the categories,
/// series and their names point into it. Colors are each series' own or the palette's, and each pie slice's.
/// Adapted from PuggleSheets' ODS chart writer.
struct ODPChartWriter {
    let chart: Chart
    let size: SlideSize

    /// The chart line thickness and scatter point size, in points.
    static let lineWidth = 1.5
    static let pointSize = 5.25
    static let gridColor = "#cccccc"
    static let axisColor = "#b3b3b3"

    static let namespaces = " xmlns:office=\"\(ODFNamespace.office)\" xmlns:style=\"\(ODFNamespace.style)\" xmlns:text=\"\(ODFNamespace.text)\""
        + " xmlns:table=\"\(ODFNamespace.table)\" xmlns:draw=\"\(ODFNamespace.draw)\" xmlns:fo=\"\(ODFNamespace.fo)\" xmlns:xlink=\"\(ODFNamespace.xlink)\""
        + " xmlns:svg=\"\(ODFNamespace.svg)\" xmlns:chart=\"\(ODFNamespace.chart)\" office:version=\"1.3\""

    // MARK: Kinds

    static func chartClass(_ kind: ChartKind) -> String {
        switch kind {
        case .column, .stackedColumn, .percentColumn, .bar, .stackedBar, .percentBar: "chart:bar"
        case .line, .smoothLine: "chart:line"
        case .area, .stackedArea, .percentArea: "chart:area"
        case .pie: "chart:circle"
        case .donut: "chart:ring"
        case .scatter: "chart:scatter"
        }
    }

    /// What a series draws: LibreOffice's doughnuts are pies whose series are rings.
    private var seriesClass: String { chart.kind == .donut ? "chart:circle" : Self.chartClass(chart.kind) }

    // MARK: The local table

    /// "A", "B" … "Z", "AA" …: a column of the local table.
    static func column(_ index: Int) -> String {
        var index = max(index, 0)
        var result = ""
        repeat {
            result = String(UnicodeScalar(UInt8(65 + index % 26))) + result
            index = index / 26 - 1
        } while index >= 0
        return result
    }

    /// A cell or block of the local table; rows count from 1 as they're written.
    static func address(column: Int, row: Int, toColumn: Int? = nil, toRow: Int? = nil) -> String {
        var result = "local-table.$\(Self.column(column))$\(row)"
        if let toColumn, let toRow { result += ":.$\(Self.column(toColumn))$\(toRow)" }
        return result
    }

    /// A number as `office:value` writes it: whole numbers without a fraction, others in their shortest exact form.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "NaN" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    // MARK: Text

    /// Text inside a paragraph, following ODF's white-space rules: spaces beyond the first are `text:s`, tabs `text:tab`
    /// and line breaks `text:line-break`.
    static func paragraphText(_ string: String, into xml: inout XMLWriter) {
        var pending = ""
        var spaces = 0
        var previousIsSpace = true
        func flush() {
            if !pending.isEmpty {
                xml.text(pending)
                pending = ""
            }
            if spaces > 0 {
                xml.raw(spaces == 1 ? "<text:s/>" : "<text:s text:c=\"\(spaces)\"/>")
                spaces = 0
            }
        }
        for character in string {
            switch character {
            case " ":
                if previousIsSpace {
                    if !pending.isEmpty {
                        xml.text(pending)
                        pending = ""
                    }
                    spaces += 1
                } else {
                    pending.append(" ")
                }
                previousIsSpace = true
            case "\t":
                flush()
                xml.raw("<text:tab/>")
                previousIsSpace = false
            case "\n", "\r", "\r\n", "\u{2028}":
                flush()
                xml.raw("<text:line-break/>")
                previousIsSpace = true
            default:
                if spaces > 0 { flush() }
                pending.append(character)
                previousIsSpace = false
            }
        }
        flush()
    }

    // MARK: Styles

    /// The automatic chart styles of the object, "ch1", "ch2" …, written as they're asked for.
    private final class Styles {
        var xml = XMLWriter(fragmentCapacity: 4096)
        private var count = 0

        /// The name of a style with these properties; nil when it has none, so nothing is written.
        func add(chart: String = "", graphic: String = "", text: String = "") -> String? {
            guard !chart.isEmpty || !graphic.isEmpty || !text.isEmpty else { return nil }
            count += 1
            let name = "ch\(count)"
            xml.raw("<style:style style:name=\"\(name)\" style:family=\"chart\">")
            if !chart.isEmpty { xml.raw("<style:chart-properties\(chart)/>") }
            if !graphic.isEmpty { xml.raw("<style:graphic-properties\(graphic)/>") }
            if !text.isEmpty { xml.raw("<style:text-properties\(text)/>") }
            xml.raw("</style:style>")
            return name
        }
    }

    private static func styleAttribute(_ name: String?) -> String {
        name.map { " chart:style-name=\"\($0)\"" } ?? ""
    }

    private static func hex(_ color: RGBColor) -> String { ODFFormat.color(color) }

    /// The chart's font on its text; nothing when it uses the default.
    private var textProperties: String {
        guard let family = chart.fontFamily?.trimmingCharacters(in: .whitespaces), !family.isEmpty else { return "" }
        var writer = XMLWriter(fragmentCapacity: 64)
        writer.attribute("fo:font-family", family.contains(" ") || family.contains(",") ? "'\(family.replacingOccurrences(of: "'", with: ""))'" : family)
        return String(decoding: writer.bytes, as: UTF8.self)
    }

    // MARK: Content

    /// The numbers as written: every row padded to the same length; a pie keeps all its series in the table but shows
    /// its first.
    private var data: ChartData { chart.data.padded() }

    func content() -> Data {
        let styles = Styles()
        var body = XMLWriter(fragmentCapacity: 8192)
        let text = textProperties
        let data = self.data
        let background = " draw:stroke=\"none\" draw:fill=\"solid\" draw:fill-color=\"\(Self.hex(chart.backgroundColor ?? .white))\""
        let chartStyle = styles.add(graphic: background, text: text)
        let width = size.width.isFinite ? min(max(size.width, 1), 100_000) : 360
        let height = size.height.isFinite ? min(max(size.height, 1), 100_000) : 216
        body.raw("<chart:chart svg:width=\"\(ODFFormat.pt(width))\" svg:height=\"\(ODFFormat.pt(height))\" xlink:href=\".\" xlink:type=\"simple\"")
        body.raw(" chart:class=\"\(Self.chartClass(chart.kind))\"\(Self.styleAttribute(chartStyle))>")
        writeTitle(chart.title, style: styles.add(chart: " chart:auto-position=\"true\"", text: text), into: &body)
        writeLegend(styles: styles, text: text, into: &body)
        writePlotArea(data, styles: styles, text: text, into: &body)
        writeLocalTable(data, into: &body)
        body.raw("</chart:chart>")

        var xml = XMLWriter(reservingCapacity: body.bytes.count + styles.xml.bytes.count + 1024)
        xml.raw("<office:document-content\(Self.namespaces)><office:automatic-styles>")
        xml.append(styles.xml)
        xml.raw("</office:automatic-styles><office:body><office:chart>")
        xml.append(body)
        xml.raw("</office:chart></office:body></office:document-content>")
        return xml.data
    }

    /// A title is one paragraph; its lines are line breaks.
    private func writeTitle(_ title: String, style: String?, into xml: inout XMLWriter) {
        guard !title.isEmpty else { return }
        xml.raw("<chart:title\(Self.styleAttribute(style))><text:p>")
        Self.paragraphText(title, into: &xml)
        xml.raw("</text:p></chart:title>")
    }

    /// The legend, where the chart puts it. The automatic place states none, which LibreOffice takes as its default, the
    /// right.
    private func writeLegend(styles: Styles, text: String, into xml: inout XMLWriter) {
        let position: String?
        switch chart.legend {
        case .none: return
        case .auto: position = nil
        case .right: position = "end"
        case .left: position = "start"
        case .top: position = "top"
        case .bottom: position = "bottom"
        }
        let style = styles.add(chart: " chart:auto-position=\"true\"", graphic: " draw:stroke=\"none\" draw:fill=\"none\"", text: text)
        xml.raw("<chart:legend")
        if let position { xml.raw(" chart:legend-position=\"\(position)\"") }
        xml.raw(" style:legend-expansion=\"\(position == "top" || position == "bottom" ? "wide" : "high")\"\(Self.styleAttribute(style))/>")
    }

    private func writePlotArea(_ data: ChartData, styles: Styles, text: String, into xml: inout XMLWriter) {
        let kind = chart.kind
        let rows = data.rowCount
        var properties = " chart:auto-position=\"true\" chart:auto-size=\"true\" chart:treat-empty-cells=\"leave-gap\" chart:series-source=\"columns\""
            + " chart:right-angled-axes=\"true\""
        if kind.isStacked { properties += " chart:stacked=\"true\"" }
        if kind.isPercent { properties += " chart:percentage=\"true\"" }
        if kind.isBar { properties += " chart:vertical=\"true\"" }
        switch kind {
        case .smoothLine: properties += " chart:interpolation=\"cubic-spline\""
        case .scatter: properties += " chart:lines=\"false\""
        case .donut:
            let hole = chart.pieHole.isFinite ? min(max(chart.pieHole, 0), 0.95) : 0.5
            properties += " chart:hole-size=\"\(ODFFormat.percent(hole))\""
        default: break
        }
        let plotStyle = styles.add(chart: properties)
        xml.raw("<chart:plot-area\(Self.styleAttribute(plotStyle))")
        xml.attribute("table:cell-range-address", Self.address(column: 0, row: 1, toColumn: data.series.count, toRow: rows + 1))
        xml.raw(" chart:data-source-has-labels=\"\(kind == .scatter ? "row" : "both")\">")

        // Axes. Horizontal bars put the categories (x) up the side and the values (y) along the bottom.
        let categoryTitle = kind.isBar ? chart.verticalAxisTitle : chart.horizontalAxisTitle
        let valueTitle = kind.isBar ? chart.horizontalAxisTitle : chart.verticalAxisTitle
        let axisGraphic = " svg:stroke-color=\"\(Self.axisColor)\""
        let xStyle = styles.add(chart: " chart:display-label=\"true\"", graphic: axisGraphic, text: text)
        xml.raw("<chart:axis chart:dimension=\"x\" chart:name=\"primary-x\"\(Self.styleAttribute(xStyle))>")
        writeTitle(categoryTitle, style: styles.add(text: text), into: &xml)
        if kind != .scatter, rows > 0 {
            xml.raw("<chart:categories")
            xml.attribute("table:cell-range-address", Self.address(column: 0, row: 2, toColumn: 0, toRow: rows + 1))
            xml.raw("/>")
        }
        xml.raw("</chart:axis>")
        var yProperties = " chart:display-label=\"true\" chart:logarithmic=\"false\""
        if let minimum = chart.verticalMinimum, minimum.isFinite { yProperties += " chart:minimum=\"\(Self.number(minimum))\"" }
        if let maximum = chart.verticalMaximum, maximum.isFinite { yProperties += " chart:maximum=\"\(Self.number(maximum))\"" }
        let yStyle = styles.add(chart: yProperties, graphic: axisGraphic, text: text)
        xml.raw("<chart:axis chart:dimension=\"y\" chart:name=\"primary-y\"\(Self.styleAttribute(yStyle))>")
        writeTitle(valueTitle, style: styles.add(text: text), into: &xml)
        if chart.showsGridlines {
            xml.raw("<chart:grid\(Self.styleAttribute(styles.add(graphic: " svg:stroke-color=\"\(Self.gridColor)\""))) chart:class=\"major\"/>")
        }
        xml.raw("</chart:axis>")

        // Series. Pies show their first.
        for index in data.series.indices {
            if kind.isPie, index > 0 { break }
            writeSeries(index, rows: rows, styles: styles, text: text, into: &xml)
        }
        xml.raw("<chart:wall\(Self.styleAttribute(styles.add(graphic: " draw:stroke=\"none\" draw:fill=\"none\"")))/>")
        xml.raw("</chart:plot-area>")
    }

    private func writeSeries(_ index: Int, rows: Int, styles: Styles, text: String, into xml: inout XMLWriter) {
        let kind = chart.kind
        let color = Self.hex(chart.color(ofSeries: index))
        let line = ODFFormat.pt(Self.lineWidth)
        var properties = ""
        var graphic: String
        switch kind {
        case .column, .stackedColumn, .percentColumn, .bar, .stackedBar, .percentBar:
            graphic = " draw:stroke=\"none\" draw:fill=\"solid\" draw:fill-color=\"\(color)\""
        case .line, .smoothLine:
            graphic = " draw:stroke=\"solid\" svg:stroke-width=\"\(line)\" svg:stroke-color=\"\(color)\" draw:fill-color=\"\(color)\""
            properties += " chart:symbol-type=\"none\""
        case .area, .stackedArea, .percentArea:
            graphic = " draw:stroke=\"solid\" svg:stroke-width=\"\(line)\" svg:stroke-color=\"\(color)\" draw:fill=\"solid\" draw:fill-color=\"\(color)\""
                + " draw:opacity=\"30%\""
        case .scatter:
            let point = ODFFormat.pt(Self.pointSize)
            graphic = " draw:stroke=\"none\" svg:stroke-color=\"\(color)\" draw:fill=\"solid\" draw:fill-color=\"\(color)\""
            properties += " chart:symbol-type=\"named-symbol\" chart:symbol-name=\"circle\" chart:symbol-width=\"\(point)\" chart:symbol-height=\"\(point)\""
        case .pie, .donut:
            graphic = " draw:stroke=\"solid\" svg:stroke-color=\"#ffffff\" draw:fill=\"solid\" draw:fill-color=\"\(color)\""
        }
        if chart.showsDataLabels { properties += kind.isPie ? " chart:data-label-number=\"percentage\"" : " chart:data-label-number=\"value\"" }
        let style = styles.add(chart: properties, graphic: graphic, text: text)
        xml.raw("<chart:series\(Self.styleAttribute(style))")
        if rows > 0 { xml.attribute("chart:values-cell-range-address", Self.address(column: index + 1, row: 2, toColumn: index + 1, toRow: rows + 1)) }
        xml.attribute("chart:label-cell-address", Self.address(column: index + 1, row: 1))
        xml.raw(" chart:class=\"\(seriesClass)\">")
        // Scatter charts take their x values from the label column.
        if kind == .scatter, rows > 0 {
            xml.raw("<chart:domain")
            xml.attribute("table:cell-range-address", Self.address(column: 0, row: 2, toColumn: 0, toRow: rows + 1))
            xml.raw("/>")
        }
        // Each slice of a pie has its own color.
        if kind.isPie {
            for slice in 0..<rows {
                let style = styles.add(graphic: " draw:fill-color=\"\(Self.hex(chart.color(ofSlice: slice)))\"")
                xml.raw("<chart:data-point\(Self.styleAttribute(style))/>")
            }
        }
        xml.raw("</chart:series>")
    }

    /// The numbers in `table:table name="local-table"`, as LibreOffice includes them: the label heading and series
    /// names across the top, then a row per label. Gaps are NaN, as LibreOffice writes them; a scatter chart's x values
    /// are numbers that keep the text they were written as.
    private func writeLocalTable(_ data: ChartData, into xml: inout XMLWriter) {
        func stringCell(_ text: String, into xml: inout XMLWriter) {
            if text.isEmpty {
                xml.raw("<table:table-cell><text:p/></table:table-cell>")
                return
            }
            xml.raw("<table:table-cell office:value-type=\"string\"><text:p>")
            Self.paragraphText(text, into: &xml)
            xml.raw("</text:p></table:table-cell>")
        }
        func numberCell(_ value: Double?, text: String? = nil, into xml: inout XMLWriter) {
            let number = Self.number(value ?? .nan)
            xml.raw("<table:table-cell office:value-type=\"float\" office:value=\"\(number)\"><text:p>")
            Self.paragraphText(text ?? number, into: &xml)
            xml.raw("</text:p></table:table-cell>")
        }
        xml.raw("<table:table table:name=\"local-table\"><table:table-header-columns><table:table-column/></table:table-header-columns>")
        if !data.series.isEmpty { xml.raw("<table:table-columns><table:table-column table:number-columns-repeated=\"\(data.series.count)\"/></table:table-columns>") }
        xml.raw("<table:table-header-rows><table:table-row>")
        stringCell(data.labelHeading, into: &xml)
        for series in data.series { stringCell(series.name, into: &xml) }
        xml.raw("</table:table-row></table:table-header-rows>")
        if data.rowCount > 0 {
            xml.raw("<table:table-rows>")
            for row in 0..<data.rowCount {
                xml.raw("<table:table-row>")
                let label = row < data.labels.count ? data.labels[row] : ""
                if chart.kind == .scatter, let value = Double(label.trimmingCharacters(in: .whitespaces)), value.isFinite {
                    numberCell(value, text: label, into: &xml)
                } else {
                    stringCell(label, into: &xml)
                }
                for series in data.series {
                    let value = row < series.values.count ? series.values[row] : nil
                    numberCell(value.flatMap { $0.isFinite ? $0 : nil }, into: &xml)
                }
                xml.raw("</table:table-row>")
            }
            xml.raw("</table:table-rows>")
        }
        xml.raw("</table:table>")
    }

    // MARK: Other parts

    static var stylesPart: Data {
        var xml = XMLWriter()
        xml.raw("<office:document-styles\(namespaces)><office:styles/></office:document-styles>")
        return xml.data
    }

    /// PuggleSlides as the generator, never anyone's name.
    static var metaPart: Data {
        var xml = XMLWriter()
        xml.raw("<office:document-meta xmlns:office=\"\(ODFNamespace.office)\" xmlns:meta=\"\(ODFNamespace.meta)\" office:version=\"1.3\">")
        xml.raw("<office:meta><meta:generator>PuggleSlides</meta:generator></office:meta></office:document-meta>")
        return xml.data
    }
}
