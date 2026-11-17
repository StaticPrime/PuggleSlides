import Foundation
import Testing
@testable import PuggleSlidesKit

/// Reading tables, charts, Fontwork, picture adjustments and snap lines as LibreOffice Impress writes them.
struct ODPObjectReadTests {
    static func points(_ centimeters: Double) -> Double { centimeters * 72 / 2.54 }

    static func read(styles: String = "", shapes: String, parts: [(String, String)] = [], objects: [String] = [],
                     images: [String: Data] = [:]) throws -> PresentationFile {
        try PresentationIO.read(try ODPObjectFixture.package(styles: styles, shapes: shapes, parts: parts, objects: objects, images: images), format: .odp)
    }

    static func color(_ fill: Fill?) -> String? {
        guard case .solid(let color)? = fill else { return nil }
        return color.rgb?.hex
    }

    // MARK: Tables

    /// A table of LibreOffice's "default" design with banded rows, a row's own cell style, a merged cell and sizes.
    static let designStyles = """
        <style:style style:name="co1" style:family="table-column"><style:table-column-properties style:column-width="4cm" \
        style:use-optimal-column-width="false"/></style:style>
        <style:style style:name="co2" style:family="table-column"><style:table-column-properties style:column-width="6cm"/></style:style>
        <style:style style:name="ro1" style:family="table-row"><style:table-row-properties style:row-height="1.2cm"/></style:style>
        <style:style style:name="ro2" style:family="table-row"><style:table-row-properties style:min-row-height="2cm"/></style:style>
        <style:style style:name="ce1" style:family="table-cell"><style:graphic-properties draw:fill="solid" draw:fill-color="#ff0000"/></style:style>
        <style:style style:name="ce2" style:family="table-cell"><style:table-cell-properties fo:border-bottom="2pt solid #0000ff" \
        style:vertical-align="bottom"/></style:style>
        <style:style style:name="P1" style:family="paragraph"><style:paragraph-properties fo:text-align="center"/></style:style>
        <style:style style:name="T1" style:family="text"><style:text-properties fo:font-style="italic"/></style:style>
        """
    static let designShapes = """
        <draw:frame draw:name="Results" draw:style-name="gr1" draw:layer="layout" svg:width="14cm" svg:height="5.6cm" svg:x="2cm" svg:y="3cm" \
        draw:id="id1" xml:id="id1"><table:table table:template-name="default" table:use-first-row-styles="true" table:use-banding-rows-styles="true">\
        <table:table-column table:style-name="co1"/><table:table-column table:style-name="co2"/><table:table-column/>\
        <table:table-row table:style-name="ro1"><table:table-cell><text:p>Name</text:p></table:table-cell><table:table-cell><text:p>Score</text:p>\
        </table:table-cell><table:table-cell><text:p>Notes</text:p></table:table-cell></table:table-row>\
        <table:table-row table:style-name="ro1"><table:table-cell table:style-name="ce2"><text:p>Ada</text:p></table:table-cell><table:table-cell>\
        <text:p text:style-name="P1">9</text:p></table:table-cell><table:table-cell><text:p>Top <text:span text:style-name="T1">marks</text:span>\
        </text:p></table:table-cell></table:table-row>\
        <table:table-row table:style-name="ro1" table:default-cell-style-name="ce1"><table:table-cell><text:p>Bob</text:p></table:table-cell>\
        <table:table-cell><text:p>7</text:p></table:table-cell><table:table-cell/></table:table-row>\
        <table:table-row table:style-name="ro2"><table:table-cell table:number-columns-spanned="2"><text:p>Total</text:p></table:table-cell>\
        <table:covered-table-cell/><table:table-cell><text:p>16</text:p></table:table-cell></table:table-row>\
        </table:table><draw:image xlink:href="Pictures/TablePreview1.svm" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>\
        <svg:title>Scores</svg:title></draw:frame>
        """

    @Test func readsLibreOfficeTablesThroughTheirDesign() throws {
        let file = try Self.read(styles: Self.designStyles, shapes: Self.designShapes)
        #expect(file.warnings.isEmpty)
        let element = try #require(file.presentation.slides.first?.elements.first)
        #expect(element.name == "Results" && element.altTitle == "Scores")
        #expect(ODFCompare.same(try #require(element.placement?.frame), SlideRect(x: Self.points(2), y: Self.points(3), width: Self.points(14),
                                                                                 height: Self.points(5.6))))
        let table = try #require(element.table)
        #expect(table.rowCount == 4 && table.columnCount == 3)
        // The third column has no style: it takes the rest of the frame's width.
        #expect(zip(table.columnWidths, [4, 6, 4].map(Self.points)).allSatisfy { abs($0 - $1) < 0.001 })
        #expect(zip(table.rowHeights, [1.2, 1.2, 1.2, 2].map(Self.points)).allSatisfy { abs($0 - $1) < 0.001 })
        // The design: a gray header, then banded rows from the second on (LibreOffice counts rows from zero), the body's
        // gray between; a row's own default cell style fills it red.
        #expect(table.cells.map { $0.map { Self.color($0.fill) ?? "-" } } == [
            ["808080", "808080", "808080"], ["B3B3B3", "B3B3B3", "B3B3B3"], ["FF0000", "FF0000", "FF0000"], ["B3B3B3", "B3B3B3", "B3B3B3"],
        ])
        // The header's text is bold and white, as the cells' own text style.
        #expect(table.cells[0][0].text.listStyle[0].character == CharacterStyle(bold: true, color: .white))
        #expect(table.cells[0][0].text.paragraphs[0].runs == [TextRun("Name")])
        #expect(table.cells[1][2].text.paragraphs[0].runs == [TextRun("Top "), TextRun("marks", style: CharacterStyle(italic: true))])
        #expect(table.cells[1][1].text.paragraphs[0].style.alignment == .center)
        // Alignment and padding from the design, and a cell's own.
        #expect(table.cells[0][0].anchor == .middle && table.cells[1][0].anchor == .bottom)
        #expect(abs(table.cells[0][0].insets.left - Self.points(0.25)) < 0.001 && abs(table.cells[0][0].insets.top - Self.points(0.13)) < 0.001)
        // Merged cells.
        #expect(table.cells[3][0].columnSpan == 2 && table.cells[3][1].isCovered)
        #expect(table.cells[3][2].text.plainText == "16")
        // White lines everywhere, but the wider blue line under "Ada".
        let white = Outline(fill: .solid(ColorRef(RGBColor.white)), width: 0.51)
        #expect(table.horizontalBorders[2][0] == Outline(fill: .solid(ColorRef(RGBColor(red: 0, green: 0, blue: 255))), width: 2))
        #expect(table.horizontalBorders[0].allSatisfy { $0 == white } && table.verticalBorders[2].allSatisfy { $0 == white })
        #expect(table.horizontalBorders[2][1] == white)
        // What's read writes and reads back the same.
        let again = try PresentationIO.read(try PresentationIO.write(file.presentation, format: .odp), format: .odp)
        #expect(ODPRendering.difference(file.presentation, again.presentation) == nil, "\(ODPRendering.difference(file.presentation, again.presentation) ?? "")")
    }

    @Test func readsExplicitCellStylesAndRepeats() throws {
        let styles = """
            <style:style style:name="ce10" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffeedd" \
            fo:border="1pt dashed #333333" style:vertical-align="middle" fo:padding="2pt"/><style:text-properties fo:font-size="11pt"/></style:style>
            <style:style style:name="ce11" style:family="table-cell"><style:table-cell-properties fo:background-color="transparent" \
            fo:border-left="none" fo:border-top="0.5pt solid #000000"/></style:style>
            """
        let shapes = """
            <draw:frame draw:style-name="gr1" draw:layer="layout" svg:width="9cm" svg:height="2cm" svg:x="1cm" svg:y="1cm"><table:table>\
            <table:table-columns><table:table-column table:number-columns-repeated="3" table:default-cell-style-name="ce10"/></table:table-columns>\
            <table:table-rows><table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="2"><text:p>x</text:p>\
            </table:table-cell><table:table-cell table:style-name="ce11"/></table:table-row></table:table-rows></table:table></draw:frame>
            """
        let file = try Self.read(styles: styles, shapes: shapes)
        #expect(file.warnings.isEmpty)
        let table = try #require(file.presentation.slides.first?.elements.first?.table)
        #expect(table.rowCount == 2 && table.columnCount == 3)
        // No sizes stated: the frame is shared out.
        #expect(table.columnWidths.allSatisfy { abs($0 - Self.points(3)) < 0.001 } && table.rowHeights.allSatisfy { abs($0 - Self.points(1)) < 0.001 })
        let cell = table.cells[1][1]
        #expect(Self.color(cell.fill) == "FFEEDD" && cell.anchor == .middle && cell.insets == TextInsets(all: 2))
        #expect(cell.text.plainText == "x" && cell.text.listStyle[0].character.fontSize == 11)
        #expect(table.cells[0][2].fill == Fill.none)
        // A line beats "none" where neighbors disagree; nothing stated is no line.
        let dashed = Outline(fill: .solid(ColorRef(RGBColor(red: 0x33, green: 0x33, blue: 0x33))), width: 1, dash: .longDash)
        #expect(table.verticalBorders[0][2] == dashed)
        #expect(table.horizontalBorders[1][2] == Outline(fill: .solid(ColorRef(RGBColor.black)), width: 0.5))
        #expect(table.horizontalBorders[2][2] == nil && table.verticalBorders[1][3] == nil)
        #expect(table.horizontalBorders[2][0] == dashed)
    }

    @Test func damagedTablesNeverCrash() throws {
        // A table without cells can't be shown: it's left out with a warning.
        let empty = try Self.read(shapes: "<draw:frame svg:width=\"5cm\" svg:height=\"2cm\" svg:x=\"0cm\" svg:y=\"0cm\"><table:table/></draw:frame>")
        #expect(empty.warnings == [.tables] && empty.presentation.slides[0].elements.isEmpty)
        // Repeat counts far past any real table are cut down, with a warning.
        let huge = try Self.read(shapes: """
            <draw:frame svg:width="5cm" svg:height="2cm" svg:x="0cm" svg:y="0cm"><table:table><table:table-column table:number-columns-repeated="1000000"/>\
            <table:table-row table:number-rows-repeated="999999999"><table:table-cell table:number-columns-repeated="99999" table:number-rows-spanned="99"/>\
            </table:table-row></table:table></draw:frame>
            """)
        #expect(huge.warnings == [.tables])
        let table = try #require(huge.presentation.slides[0].elements.first?.table)
        #expect(table.columnCount == ODPElementReader.maxTableSide && table.rowCount * table.columnCount <= ODPElementReader.maxTableCells)
        // Spans past the table's edge stop at it; unknown styles are no style.
        let odd = try Self.read(shapes: """
            <draw:frame svg:width="5cm" svg:height="2cm" svg:x="0cm" svg:y="0cm"><table:table table:template-name="missing" \
            table:use-first-row-styles="true"><table:table-row table:style-name="nothing"><table:table-cell table:number-columns-spanned="9" \
            table:number-rows-spanned="-3" table:style-name="nothing"><text:p>wide</text:p></table:table-cell><table:table-cell/></table:table-row>\
            </table:table></draw:frame>
            """)
        let oddTable = try #require(odd.presentation.slides[0].elements.first?.table)
        #expect(oddTable.cells[0][0].columnSpan == 2 && oddTable.cells[0][0].rowSpan == 1 && oddTable.cells[0][1].isCovered)
        #expect(oddTable.horizontalBorders.joined().allSatisfy { $0 == nil })
        #expect(odd.warnings.isEmpty)
    }

    @Test func turnedTextAndDiagonalLinesInCellsAreWarnedAbout() throws {
        func warnings(_ properties: String) throws -> Set<ImportWarning> {
            let styles = "<style:style style:name=\"ce1\" style:family=\"table-cell\"><style:table-cell-properties \(properties)/></style:style>"
            let shapes = "<draw:frame svg:width=\"5cm\" svg:height=\"2cm\" svg:x=\"0cm\" svg:y=\"0cm\"><table:table><table:table-row>"
                + "<table:table-cell table:style-name=\"ce1\"><text:p>a</text:p></table:table-cell></table:table-row></table:table></draw:frame>"
            return try Self.read(styles: styles, shapes: shapes).warnings
        }
        #expect(try warnings("style:rotation-angle=\"90\"") == [.tables])
        #expect(try warnings("style:diagonal-tl-br=\"0.5pt solid #000000\"") == [.tables])
        #expect(try warnings("style:rotation-angle=\"0\" style:diagonal-bl-tr=\"none\"").isEmpty)
    }

    // MARK: Charts

    static func readChart(_ content: String, replacement: Bool = false, images: [String: Data] = [:]) throws -> (element: SlideElement?, warnings: Set<ImportWarning>) {
        let file = try Self.read(shapes: ODPObjectFixture.chartFrame("Chart", object: "Object 1", replacement: replacement),
                                 parts: [("Object 1/content.xml", content)], objects: ["Object 1"], images: images)
        return (file.presentation.slides.first?.elements.first, file.warnings)
    }

    @Test func readsLibreOfficeColumnCharts() throws {
        let parts = ODPObjectFixture.seriesAndAxes(seriesClass: "chart:bar", labels: true, xTitle: "Rows", yTitle: "Values")
        let styles = parts.styles + """
            <style:style style:name="ch2" style:family="chart"><style:chart-properties chart:auto-position="true"/>\
            <style:text-properties fo:font-size="13pt" style:font-name="Liberation Sans"/></style:style>
            <style:style style:name="ch3" style:family="chart"><style:graphic-properties draw:stroke="none" draw:fill="none"/></style:style>
            """
        let body = "<chart:title svg:x=\"6cm\" svg:y=\"0.2cm\" chart:style-name=\"ch2\"><text:p>Sales <text:s/>by row</text:p></chart:title>"
            + "<chart:subtitle><text:p>Third quarter</text:p></chart:subtitle><chart:legend chart:legend-position=\"end\" svg:x=\"13cm\" svg:y=\"4cm\" style:legend-expansion=\"high\" chart:style-name=\"ch3\"/>" + parts.body
        let read = try Self.readChart(ODPObjectFixture.chart(class: "chart:bar", styles: styles, body: body, header: ODPObjectFixture.defaultHeader,
                                                             rows: ODPObjectFixture.defaultRows))
        #expect(read.warnings.isEmpty)
        let element = try #require(read.element)
        #expect(element.name == "Chart" && abs((element.placement?.frame.width ?? 0) - Self.points(16)) < 0.001)
        let chart = try #require(element.chart)
        #expect(chart.kind == .column)
        #expect(chart.data.labels == ["Row 1", "Row 2", "Row 3", "Row 4"] && chart.data.labelHeading == "")
        #expect(chart.data.series.map(\.name) == ["Column 1", "Column 2", "Column 3"])
        #expect(chart.data.series[0].values == [9.1, 2.4, 3.1, 4.3] && chart.data.series[2].values == [4.54, 9.65, 3.7, 6.2])
        // LibreOffice's own series colors stay.
        #expect(chart.data.series.compactMap(\.color).map { "#" + $0.hex.lowercased() } == ODPObjectFixture.seriesColors)
        // Charts have no subtitle: it's the title's last line.
        #expect(chart.title == "Sales  by row\nThird quarter" && chart.horizontalAxisTitle == "Rows" && chart.verticalAxisTitle == "Values")
        #expect(chart.legend == .right && chart.showsGridlines && chart.showsDataLabels)
        #expect(chart.fontFamily == "Liberation Sans" && chart.backgroundColor == nil)
    }

    @Test(arguments: [
        ("chart:bar", "chart:vertical=\"true\"", "chart:bar", ChartKind.bar, false),
        ("chart:bar", "chart:stacked=\"true\"", "chart:bar", .stackedColumn, false),
        ("chart:bar", "chart:vertical=\"true\" chart:percentage=\"true\"", "chart:bar", .percentBar, false),
        ("chart:line", "", "chart:line", .line, false),
        ("chart:line", "chart:interpolation=\"cubic-spline\"", "chart:line", .smoothLine, false),
        ("chart:line", "chart:interpolation=\"step-start\"", "chart:line", .line, true),
        ("chart:line", "chart:stacked=\"true\"", "chart:line", .line, true),
        ("chart:area", "chart:percentage=\"true\"", "chart:area", .percentArea, false),
        ("chart:area", "chart:stacked=\"true\"", "chart:area", .stackedArea, false),
        ("chart:circle", "", "chart:circle", .pie, true),
        ("chart:radar", "", "chart:radar", .line, true),
        ("chart:filled-radar", "", "chart:filled-radar", .area, true),
        ("chart:bubble", "", "chart:bubble", .scatter, true),
        ("chart:stock", "", "chart:stock", .line, true),
        ("chart:gantt", "", "chart:gantt", .column, true),
        ("chart:bar", "chart:three-dimensional=\"true\"", "chart:bar", .column, true),
        ("chart:bar", "", "chart:line", .column, true),
    ])
    func mapsChartClassesToSupportedKinds(_ chartClass: String, _ plot: String, _ seriesClass: String, _ kind: ChartKind, _ warns: Bool) throws {
        let parts = ODPObjectFixture.seriesAndAxes(seriesClass: seriesClass)
        let read = try Self.readChart(ODPObjectFixture.chart(class: chartClass, plot: plot, styles: parts.styles, body: parts.body,
                                                             header: ODPObjectFixture.defaultHeader, rows: ODPObjectFixture.defaultRows))
        let chart = try #require(read.element?.chart)
        #expect(chart.kind == kind)
        #expect(read.warnings == (warns ? [.charts] : []))
        // A pie shows its first series; LibreOffice drew the others as rings.
        #expect(chart.data.series.count == (kind.isPie ? 1 : 3))
    }

    @Test func readsDoughnutsScatterChartsAndGaps() throws {
        // A doughnut: one series of slices, each colored by LibreOffice; pies here color their slices from the palette.
        let ringStyles = """
            <style:style style:name="ch10" style:family="chart"><style:graphic-properties draw:fill-color="#004586"/></style:style>
            <style:style style:name="ch11" style:family="chart"><style:graphic-properties draw:fill-color="#ff420e"/></style:style>
            """
        let ringBody = """
            <chart:plot-area chart:style-name="ch4" table:cell-range-address="local-table.$A$1:.$B$4" chart:data-source-has-labels="both">\
            <chart:axis chart:dimension="x" chart:name="primary-x"><chart:categories table:cell-range-address="local-table.$A$2:.$A$4"/></chart:axis>\
            <chart:axis chart:dimension="y" chart:name="primary-y"/><chart:series chart:style-name="ch10" \
            chart:values-cell-range-address="local-table.$B$2:.$B$4" chart:label-cell-address="local-table.$B$1" chart:class="chart:circle">\
            <chart:data-point chart:style-name="ch10"/><chart:data-point chart:style-name="ch11" chart:repeated="2"/></chart:series></chart:plot-area>
            """
        let ring = try Self.readChart(ODPObjectFixture.chart(class: "chart:ring", plot: "chart:hole-size=\"40%\"", styles: ringStyles, body: ringBody,
                                                             header: ["Fruit", "Count"], rows: [["Apples", "3"], ["Pears", "NaN"], ["Plums", "5"]]))
        #expect(ring.warnings.isEmpty)
        let donut = try #require(ring.element?.chart)
        #expect(donut.kind == .donut && abs(donut.pieHole - 0.4) < 0.0001)
        #expect(donut.data.labelHeading == "Fruit" && donut.data.labels == ["Apples", "Pears", "Plums"])
        #expect(donut.data.series.map(\.values) == [[3, nil, 5]] && donut.legend == ChartLegendPosition.none && !donut.showsGridlines)

        // A scatter chart: x values from its series' domain, kept as the text they show.
        let scatterBody = """
            <chart:legend style:legend-expansion="high"/><chart:plot-area chart:style-name="ch4" chart:data-source-has-labels="row">\
            <chart:axis chart:dimension="x" chart:name="primary-x"/><chart:axis chart:dimension="y" chart:name="primary-y"/>\
            <chart:series chart:values-cell-range-address="local-table.$B$2:.$B$4" chart:label-cell-address="local-table.$B$1" \
            chart:class="chart:scatter"><chart:domain table:cell-range-address="local-table.$A$2:.$A$4"/></chart:series></chart:plot-area>
            """
        let scatter = try Self.readChart(ODPObjectFixture.chart(class: "chart:scatter", plot: "chart:lines=\"false\"", body: scatterBody,
                                                                header: ["X", "Y"], rows: [["1.5", "2"], ["3", "4"], ["4.25", "1"]]))
        let points = try #require(scatter.element?.chart)
        #expect(points.kind == .scatter && points.data.labels == ["1.5", "3", "4.25"] && points.data.labelHeading == "X")
        #expect(points.data.series[0].values == [2, 4, 1] && points.legend == .auto)
    }

    @Test func readsChartsWhoseSeriesDontSayWhereTheirNumbersAre() throws {
        // Only the plot area's block, with names across the top and labels down the side.
        let body = """
            <chart:plot-area chart:style-name="ch4" table:cell-range-address="local-table.$A$1:.$C$3" chart:data-source-has-labels="both">\
            <chart:axis chart:dimension="x" chart:name="primary-x"/><chart:axis chart:dimension="y" chart:name="primary-y"/>\
            <chart:series/><chart:series/></chart:plot-area>
            """
        let read = try Self.readChart(ODPObjectFixture.chart(class: "chart:bar", body: body, header: ["", "A", "B"], rows: [["one", "1", "2"], ["two", "3", "4"]]))
        let chart = try #require(read.element?.chart)
        #expect(chart.data.series.map(\.name) == ["A", "B"] && chart.data.series.map(\.values) == [[1, 3], [2, 4]])
        #expect(chart.data.labels == ["one", "two"])
    }

    @Test func readsTheCopyOfAnotherDocumentsNumbers() throws {
        // A chart drawn from a spreadsheet's cells (`xlink:href=".."`) points at cells this file doesn't have; LibreOffice
        // writes a copy of the numbers into the chart's own table, names across the top and labels down the side.
        let body = """
            <chart:plot-area chart:style-name="ch4" table:cell-range-address="Sheet1.$A$5:Sheet1.$C$7" chart:data-source-has-labels="both">\
            <chart:axis chart:dimension="x" chart:name="primary-x"><chart:categories table:cell-range-address="Sheet1.$A$6:Sheet1.$A$7"/></chart:axis>\
            <chart:axis chart:dimension="y" chart:name="primary-y"/><chart:series chart:values-cell-range-address="Sheet1.$B$6:Sheet1.$B$7" \
            chart:label-cell-address="Sheet1.$B$5" chart:class="chart:bar"/><chart:series chart:values-cell-range-address="Sheet1.$C$6:Sheet1.$C$7" \
            chart:label-cell-address="Sheet1.$C$5" chart:class="chart:bar"/></chart:plot-area>
            """
        let content = ODPObjectFixture.chart(class: "chart:bar", body: body, header: ["", "A", "B"], rows: [["one", "1", "2"], ["two", "3", "4"]])
            .replacingOccurrences(of: "xlink:href=\".\"", with: "xlink:href=\"..\"")
        let chart = try #require(try Self.readChart(content).element?.chart)
        #expect(chart.data.series.map(\.name) == ["A", "B"] && chart.data.series.map(\.values) == [[1, 3], [2, 4]])
        #expect(chart.data.labels == ["one", "two"])
    }

    @Test func readsChartsWrittenInsideTheirFrame() throws {
        let content = ODPObjectFixture.chart(class: "chart:line", body: ODPObjectFixture.seriesAndAxes(seriesClass: "chart:line").body,
                                             header: ODPObjectFixture.defaultHeader, rows: ODPObjectFixture.defaultRows)
        let inner = content.components(separatedBy: "<office:automatic-styles>")[1].components(separatedBy: "</office:body>")[0]
        let shapes = """
            <draw:frame draw:name="Inline" svg:width="10cm" svg:height="6cm" svg:x="0cm" svg:y="0cm"><draw:object><office:document \
            office:mimetype="application/vnd.oasis.opendocument.chart" office:version="1.3"><office:automatic-styles>\(inner)</office:body>\
            </office:document></draw:object></draw:frame>
            """
        let file = try Self.read(shapes: shapes)
        #expect(file.warnings.isEmpty)
        #expect(file.presentation.slides[0].elements.first?.chart?.kind == .line)
        #expect(file.presentation.slides[0].elements.first?.chart?.data.series.count == 3)
    }

    @Test func unreadableChartsKeepTheirPicture() throws {
        // A chart object that isn't there, or isn't a chart, shows its replacement picture, with a warning.
        let photo = ODPLibreOfficeFixture.image
        let broken = try Self.readChart("<x/>", replacement: true, images: ["ObjectReplacements/Object 1": photo])
        #expect(broken.warnings == [.charts])
        #expect(broken.element?.picture != nil)
        // A chart that keeps its numbers somewhere else (a spreadsheet's cells) can't be read either.
        let external = ODPObjectFixture.chart(class: "chart:bar", body: ODPObjectFixture.seriesAndAxes(seriesClass: "chart:bar").body,
                                              header: [], rows: []).replacingOccurrences(of: "<table:table ", with: "<table:skipped ")
            .replacingOccurrences(of: "</table:table>", with: "</table:skipped>")
        let missing = try Self.readChart(external)
        #expect(missing.warnings == [.charts] && missing.element == nil)
    }

    // MARK: Word art, pictures and guides

    @Test func readsFontworkAsWordArt() throws {
        let styles = """
            <style:style style:name="gr10" style:family="graphic" style:parent-style-name="standard"><style:graphic-properties draw:fill="solid" \
            draw:fill-color="#3465a4" draw:stroke="solid" svg:stroke-color="#000000" svg:stroke-width="0.05cm"/></style:style>
            """
        func shape(_ name: String, _ geometry: String) -> String {
            "<draw:custom-shape draw:name=\"\(name)\" draw:style-name=\"gr10\" draw:layer=\"layout\" svg:width=\"10cm\" svg:height=\"3cm\" svg:x=\"1cm\" "
                + "svg:y=\"1cm\"><text:p>\(name)</text:p><draw:enhanced-geometry svg:viewBox=\"0 0 21600 21600\" \(geometry)/></draw:custom-shape>"
        }
        let shapes = shape("Wave", "draw:text-areas=\"0 0 21600 21600\" draw:text-path=\"true\" draw:text-path-mode=\"shape\" draw:text-path-scale=\"shape\" "
                           + "draw:type=\"fontwork-wave\" draw:modifiers=\"2809 10800\" draw:enhanced-path=\"M 0 0 C 7200 -2000 14400 2000 21600 0 N\"")
            + shape("Path", "draw:text-path=\"true\" draw:type=\"non-primitive\" draw:enhanced-path=\"M 0 0 L 21600 0 N\"")
            + shape("Off", "draw:text-path=\"false\" draw:type=\"fontwork-arch-up-curve\" draw:enhanced-path=\"M 0 0 L 21600 0 21600 21600 Z N\"")
        let file = try Self.read(styles: styles, shapes: shapes)
        #expect(file.warnings.isEmpty)
        let elements = file.presentation.slides[0].elements
        #expect(elements.map(\.isWordArt) == [true, true, false])
        let wave = try #require(elements[0].shape)
        #expect(wave.geometry == .rectangle && wave.text?.plainText == "Wave")
        #expect(wave.fill == .solid(ColorRef(RGBColor(red: 0x34, green: 0x65, blue: 0xA4))))
        #expect(wave.outline?.fill == .solid(.black) && abs((wave.outline?.width ?? 0) - Self.points(0.05)) < 0.001)
    }

    @Test func readsPictureAdjustments() throws {
        let styles = """
            <style:style style:name="gr20" style:family="graphic"><style:graphic-properties draw:image-opacity="60%" draw:luminance="-25%" \
            draw:contrast="40%" draw:color-mode="standard"/></style:style>
            <style:style style:name="gr21" style:family="graphic"><style:graphic-properties draw:color-mode="greyscale"/></style:style>
            <style:style style:name="gr22" style:family="graphic"><style:graphic-properties draw:color-mode="watermark"/></style:style>
            <style:style style:name="gr23" style:family="graphic"><style:graphic-properties draw:color-mode="mono"/></style:style>
            <style:style style:name="gr24" style:family="graphic"><style:graphic-properties draw:color-mode="greyscale" draw:color-inversion="true"/></style:style>
            <style:style style:name="gr25" style:family="graphic"><style:graphic-properties draw:luminance="250%" draw:contrast="-900%"/></style:style>
            """
        let shapes = (20...25).map { number in
            "<draw:frame draw:style-name=\"gr\(number)\" svg:width=\"2cm\" svg:height=\"1cm\" svg:x=\"0cm\" svg:y=\"0cm\"><draw:image "
                + "xlink:href=\"Pictures/photo.png\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/></draw:frame>"
        }.joined()
        let file = try Self.read(styles: styles, shapes: shapes, images: ["Pictures/photo.png": ODPLibreOfficeFixture.image])
        let adjustments = file.presentation.slides[0].elements.compactMap { $0.picture?.adjustments }
        #expect(adjustments == [
            ImageAdjustments(transparency: 0.4, brightness: -0.25, contrast: 0.4),
            ImageAdjustments(recolor: .grayscale),
            ImageAdjustments(brightness: 0.5, contrast: -0.7),
            ImageAdjustments(recolor: .grayscale),
            ImageAdjustments(recolor: .negative),
            ImageAdjustments(brightness: 1, contrast: -1),
        ])
    }

    @Test func readsSnapLinesAsGuides() throws {
        let settings = """
            <?xml version="1.0" encoding="UTF-8"?>
            <office:document-settings xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
            xmlns:config="urn:oasis:names:tc:opendocument:xmlns:config:1.0" xmlns:ooo="http://openoffice.org/2004/office" office:version="1.3">
            <office:settings><config:config-item-set config:name="ooo:view-settings">
            <config:config-item config:name="VisibleAreaTop" config:type="int">-1500</config:config-item>
            <config:config-item-map-indexed config:name="Views"><config:config-item-map-entry>
            <config:config-item config:name="ViewId" config:type="string">view1</config:config-item>
            <config:config-item config:name="GridIsVisible" config:type="boolean">false</config:config-item>
            <config:config-item config:name="SnapLinesDrawing" config:type="string">V12700H3810P1000,2000V-635</config:config-item>
            <config:config-item config:name="SnapLinesNotes" config:type="string"/>
            </config:config-item-map-entry></config:config-item-map-indexed></config:config-item-set>
            <config:config-item-set config:name="ooo:configuration-settings">
            <config:config-item config:name="IsPrintDrawing" config:type="boolean">true</config:config-item>
            </config:config-item-set></office:settings></office:document-settings>
            """
        let file = try Self.read(shapes: "", parts: [("settings.xml", settings)])
        let guides = file.presentation.guides
        #expect(guides.map(\.orientation) == [.vertical, .horizontal, .vertical])
        #expect(zip(guides.map(\.position), [360, 108, -18]).allSatisfy { abs($0 - $1) < 0.0001 })
        // Damaged settings are no guides.
        let damaged = try Self.read(shapes: "", parts: [("settings.xml", "<office:document-settings><unclosed>")])
        #expect(damaged.presentation.guides.isEmpty)
    }
}
