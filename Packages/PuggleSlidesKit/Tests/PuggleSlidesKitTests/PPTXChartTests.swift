import Foundation
import Testing
@testable import PuggleSlidesKit

/// Charts: written as DrawingML chart parts with an embedded workbook, read back exactly; PowerPoint's charts read
/// into the nearest supported kind.
struct PPTXChartTests {
    typealias Package = PPTXTestPackage

    static func deck(_ charts: [Chart]) -> Presentation {
        PPTXTableTests.deck(charts.enumerated().map { index, chart in
            PPTXSamples.chart("Chart \(index + 1)", SlideRect(x: 40 + Double(index % 3) * 220, y: 40 + Double(index / 3) * 130, width: 200, height: 120), chart)
        })
    }

    // MARK: Writing

    @Test func everyKindAndOptionRoundTrips() throws {
        var charts: [Chart] = []
        for (index, kind) in ChartKind.allCases.enumerated() {
            var chart = PPTXSamples.salesChart(kind)
            chart.legend = ChartLegendPosition.allCases[index % ChartLegendPosition.allCases.count]
            chart.showsGridlines = index % 2 == 0
            chart.showsDataLabels = index % 3 == 0
            chart.title = index % 4 == 0 ? "" : "Line one\nline two"
            chart.horizontalAxisTitle = index % 5 == 0 ? "" : "Across"
            chart.verticalAxisTitle = index % 5 == 1 ? "" : "Up"
            chart.verticalMinimum = index % 2 == 0 ? -5.5 : nil
            chart.verticalMaximum = index % 3 == 0 ? 1e6 : nil
            chart.fontFamily = index % 2 == 0 ? "Avenir Next" : nil
            chart.backgroundColor = index % 4 == 1 ? RGBColor(red: 0x10, green: 0x20, blue: 0x30) : nil
            chart.pieHole = 0.25
            charts.append(chart)
        }
        // Unusual data: series of different lengths, no name, every value missing, odd text, labels that look like
        // numbers but aren't written as such, and nothing at all.
        var odd = Chart(kind: .scatter, data: ChartData(labelHeading: "x_x0041_ & <x>", labels: ["1", "02", "", "3.50", "1e5"], series: [
            ChartSeries(name: "", values: [1, nil, 3]), ChartSeries(name: "  spaced  ", values: [nil, nil]),
            ChartSeries(name: "Long", values: [0.1, -0.000001, 1e300, 123_456_789_012, 7], color: Chart.palette[2]),
        ]))
        odd.title = "Odd"
        charts.append(odd)
        charts.append(Chart(kind: .line, data: ChartData()))
        charts.append(Chart(kind: .pie, data: ChartData(labels: ["Only"], series: [ChartSeries(name: "One", values: [1])])))
        let original = Self.deck(charts)
        let file = try PPTXRoundTripTests.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        // Numbers that are spelled differently from how they'd be written stay text, even in a scatter chart.
        let read = file.presentation.slides[0].elements[ChartKind.allCases.count].chart
        #expect(read?.data.labels == ["1", "02", "", "3.50", "1e5"])
        #expect(read?.data.labelHeading == "x_x0041_ & <x>")
        #expect(read?.data.series[2].values == [0.1, -0.000001, 1e300, 123_456_789_012, 7])
    }

    @Test func chartPartsAreWrittenWithTheirWorkbooks() throws {
        let presentation = Self.deck([PPTXSamples.salesChart(.column), PPTXSamples.salesChart(.scatter)])
        let data = try PresentationIO.write(presentation, format: .pptx)
        let parts = try Package.parts(of: data)
        let text = parts.mapValues { String(decoding: $0, as: UTF8.self) }
        // Content types: charts by override, workbooks by extension.
        let types = try #require(text["[Content_Types].xml"])
        #expect(types.contains("<Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>"))
        #expect(types.contains("<Override PartName=\"/ppt/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"))
        #expect(types.contains("PartName=\"/ppt/charts/chart2.xml\""))
        // The slide refers to each chart; each chart to its workbook, as an embedded package.
        let slideRelationships = try #require(text["ppt/slides/_rels/slide1.xml.rels"])
        #expect(slideRelationships.contains("Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"../charts/chart1.xml\""))
        let chartRelationships = try #require(text["ppt/charts/_rels/chart1.xml.rels"])
        #expect(chartRelationships.contains("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" "
            + "Target=\"../embeddings/Microsoft_Excel_Worksheet1.xlsx\"/>"))
        #expect(parts["ppt/embeddings/Microsoft_Excel_Worksheet2.xlsx"] != nil)
        let slide = try #require(text["ppt/slides/slide1.xml"])
        #expect(slide.contains("<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"508000\" y=\"508000\"/><a:ext cx=\"2540000\" cy=\"1524000\"/></p:xfrm>"))
        #expect(slide.contains("<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart "
            + "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId2\"/></a:graphicData>"))

        // The chart: references into the workbook with caches of their values; a gap has no point.
        let chart = try #require(text["ppt/charts/chart1.xml"])
        #expect(chart.contains("<c:tx><c:strRef><c:f>Sheet1!$B$1</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>North</c:v></c:pt>"))
        #expect(chart.contains("<c:cat><c:strRef><c:f>Sheet1!$A$2:$A$5</c:f><c:strCache><c:ptCount val=\"4\"/><c:pt idx=\"0\"><c:v>Q1</c:v></c:pt>"))
        #expect(chart.contains("<c:pt idx=\"3\"><c:v>Q4 &amp; &lt;more&gt;</c:v></c:pt>"))
        #expect(chart.contains("<c:val><c:numRef><c:f>Sheet1!$B$2:$B$5</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"4\"/>"
            + "<c:pt idx=\"0\"><c:v>12</c:v></c:pt><c:pt idx=\"1\"><c:v>19.5</c:v></c:pt><c:pt idx=\"3\"><c:v>30</c:v></c:pt></c:numCache>"))
        #expect(chart.contains("<c:externalData r:id=\"rId1\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"))
        // A scatter chart's x values are numbers.
        let scatter = try #require(text["ppt/charts/chart2.xml"])
        #expect(scatter.contains("<c:xVal><c:numRef><c:f>Sheet1!$A$2:$A$5</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"4\"/>"
            + "<c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>2.5</c:v></c:pt>"))

        // The workbook is a sound spreadsheet holding the same data under its headings.
        let workbookData = try #require(parts["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"])
        let workbookParts = try Package.parts(of: workbookData).mapValues { String(decoding: $0, as: UTF8.self) }
        #expect(Set(workbookParts.keys) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
                                            "xl/worksheets/sheet1.xml", "xl/styles.xml", "xl/sharedStrings.xml"])
        #expect(workbookParts["xl/workbook.xml"]?.contains("<sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/>") == true)
        let sheet = try #require(workbookParts["xl/worksheets/sheet1.xml"])
        #expect(sheet.contains("<dimension ref=\"A1:C5\"/>"))
        #expect(sheet.contains("<row r=\"4\"><c r=\"A4\" t=\"s\"><v>5</v></c><c r=\"C4\"><v>14.25</v></c></row>"))
        let reader = try #require(PPTXWorkbookReader(workbookData))
        #expect(reader.value(sheet: "Sheet1", at: PPTXCellAddress(row: 0, column: 0)) == .text("Quarter"))
        #expect(reader.values("Sheet1!$C$1:$C$5")?.map { $0?.text } == ["South", "8", "11", "14.25", "9"])
        #expect(reader.values("'Sheet1'!B2:B5")?.map { $0?.number } == [12, 19.5, nil, 30])
        // Saving again gives the same workbook: it's stamped with the presentation's date, not the time it's written.
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try Package.parts(of: try PPTXWriter.write(presentation, date: date))
        let second = try Package.parts(of: try PPTXWriter.write(presentation, date: date))
        #expect(first["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"] == second["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"])
        #expect(first["ppt/charts/chart1.xml"] == second["ppt/charts/chart1.xml"])
    }

    @Test func kindsAreWrittenAsTheyAreDrawn() throws {
        func part(_ chart: Chart) throws -> String {
            try #require(try Package.writtenParts(Self.deck([chart]))["ppt/charts/chart1.xml"])
        }
        var stacked = PPTXSamples.salesChart(.stackedBar)
        stacked.legend = .auto
        stacked.fontFamily = "Georgia"
        let bar = try part(stacked)
        #expect(bar.contains("<c:barChart><c:barDir val=\"bar\"/><c:grouping val=\"stacked\"/><c:varyColors val=\"0\"/>"))
        #expect(bar.contains("<c:gapWidth val=\"150\"/><c:overlap val=\"100\"/><c:axId val=\"1001\"/><c:axId val=\"1002\"/></c:barChart>"))
        // Series in the palette's colors unless they have their own color.
        #expect(bar.contains("<c:spPr><a:solidFill><a:srgbClr val=\"4285F4\"/></a:solidFill></c:spPr><c:invertIfNegative val=\"0\"/>"))
        #expect(bar.contains("<a:srgbClr val=\"8844AA\"/>"))
        // Categories from the top, values along the bottom; Auto leaves the legend's place to the app.
        #expect(bar.contains("<c:catAx><c:axId val=\"1001\"/><c:scaling><c:orientation val=\"maxMin\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/>"))
        #expect(bar.contains("<c:crosses val=\"max\"/>"))
        #expect(bar.contains("<c:legend><c:overlay val=\"0\"/></c:legend>"))
        #expect(bar.contains("<a:latin typeface=\"Georgia\"/>"))
        #expect(try part(PPTXSamples.salesChart(.percentColumn)).contains("<c:numFmt formatCode=\"0%\" sourceLinked=\"0\"/>"))

        let column = try part(PPTXSamples.salesChart(.column))
        #expect(column.contains("<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"1400\" b=\"0\"/></a:pPr><a:r><a:rPr sz=\"1400\" b=\"0\"/>"
            + "<a:t>Sales</a:t></a:r></a:p><a:p>"))
        #expect(column.contains("<c:scaling><c:orientation val=\"minMax\"/><c:max val=\"40\"/><c:min val=\"0\"/></c:scaling>"))
        #expect(column.contains("<c:majorGridlines>"))
        #expect(column.contains("<c:dLbls><c:showLegendKey val=\"0\"/><c:showVal val=\"1\"/>"))
        #expect(column.contains("<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>"))
        #expect(column.contains("<a:bodyPr rot=\"-5400000\" vert=\"horz\"/><a:lstStyle/><a:p><a:pPr><a:defRPr b=\"0\"/></a:pPr><a:r><a:rPr b=\"0\"/><a:t>Units</a:t>"))

        var smoothChart = PPTXSamples.salesChart(.smoothLine)
        smoothChart.showsGridlines = false
        let smooth = try part(smoothChart)
        #expect(smooth.contains("<c:lineChart><c:grouping val=\"standard\"/>"))
        #expect(smooth.contains("<c:marker><c:symbol val=\"none\"/></c:marker>"))
        #expect(smooth.contains("<c:smooth val=\"1\"/></c:ser>"))
        #expect(!smooth.contains("<c:majorGridlines>"))
        let area = try part(PPTXSamples.salesChart(.percentArea))
        #expect(area.contains("<c:areaChart><c:grouping val=\"percentStacked\"/>"))
        #expect(area.contains("<a:srgbClr val=\"4285F4\"><a:alpha val=\"30000\"/></a:srgbClr>"))
        // Pies color each slice in the palette; a doughnut's hole is in whole percents.
        let donut = try part(PPTXSamples.salesChart(.donut))
        #expect(donut.contains("<c:doughnutChart><c:varyColors val=\"1\"/>"))
        #expect(donut.contains("<c:dPt><c:idx val=\"2\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"FBBC04\"/>"))
        #expect(donut.contains("<c:firstSliceAng val=\"0\"/><c:holeSize val=\"35\"/></c:doughnutChart>"))
        #expect(!donut.contains("<c:catAx>"))
        // Scatter charts are points only, against two value axes.
        let scatter = try part(PPTXSamples.salesChart(.scatter))
        #expect(scatter.contains("<c:scatterChart><c:scatterStyle val=\"marker\"/>"))
        #expect(scatter.contains("<c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/>"))
        #expect(scatter.components(separatedBy: "<c:valAx>").count == 3)
        #expect(scatter.contains("<c:crossBetween val=\"midCat\"/>"))
        var none = PPTXSamples.salesChart(.pie)
        none.legend = .none
        #expect(!(try part(none)).contains("<c:legend>"))
    }

    // MARK: Reading PowerPoint's charts

    /// A series as PowerPoint writes it: cached name, labels and values.
    static func series(_ index: Int, name: String?, labels: [String], values: [Double?], properties: String = "",
                       labelsAsNumbers: Bool = false, format: String = "General", smooth: Bool? = nil) -> String {
        let column = PPTXChartSheet.columnName(index + 1)
        var xml = "<c:ser><c:idx val=\"\(index)\"/><c:order val=\"\(index)\"/>"
        if let name {
            xml += "<c:tx><c:strRef><c:f>Sheet1!$\(column)$1</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(name)</c:v></c:pt></c:strCache></c:strRef></c:tx>"
        }
        xml += properties
        let points = labels.enumerated().map { "<c:pt idx=\"\($0)\"><c:v>\($1)</c:v></c:pt>" }.joined()
        xml += labelsAsNumbers
            ? "<c:cat><c:numRef><c:f>Sheet1!$A$2:$A$\(labels.count + 1)</c:f><c:numCache><c:formatCode>\(format)</c:formatCode><c:ptCount val=\"\(labels.count)\"/>\(points)</c:numCache></c:numRef></c:cat>"
            : "<c:cat><c:strRef><c:f>Sheet1!$A$2:$A$\(labels.count + 1)</c:f><c:strCache><c:ptCount val=\"\(labels.count)\"/>\(points)</c:strCache></c:strRef></c:cat>"
        let numbers = values.enumerated().compactMap { index, value in value.map { "<c:pt idx=\"\(index)\"><c:v>\($0)</c:v></c:pt>" } }.joined()
        xml += "<c:val><c:numRef><c:f>Sheet1!$\(column)$2:$\(column)$\(values.count + 1)</c:f><c:numCache><c:formatCode>General</c:formatCode>"
            + "<c:ptCount val=\"\(values.count)\"/>\(numbers)</c:numCache></c:numRef></c:val>"
        if let smooth { xml += "<c:smooth val=\"\(smooth ? 1 : 0)\"/>" }
        return xml + "</c:ser>"
    }

    static let axes = "<c:catAx><c:axId val=\"10\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/>"
        + "<c:crossAx val=\"20\"/></c:catAx><c:valAx><c:axId val=\"20\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/>"
        + "<c:axPos val=\"l\"/><c:majorGridlines/><c:crossAx val=\"10\"/></c:valAx>"
    static let axisIDs = "<c:axId val=\"10\"/><c:axId val=\"20\"/>"

    /// One slide with a chart frame per chart part; `workbooks` are embedded and linked from the chart of the same index.
    static func package(_ charts: [String], workbooks: [Int: Data] = [:]) -> Package {
        var package = Package()
        var relationships: [Package.Relationship] = []
        var frames = ""
        for (index, chart) in charts.enumerated() {
            let path = "ppt/charts/chart\(index + 1).xml"
            package.extraParts[path] = chart
            relationships.append(Package.Relationship("rId\(20 + index)", "chart", "../charts/chart\(index + 1).xml"))
            frames += Package.chartFrame(4 + index, "Chart \(index + 1)", relationship: "rId\(20 + index)")
            if let workbook = workbooks[index] {
                package.media["ppt/embeddings/Microsoft_Excel_Worksheet\(index + 1).xlsx"] = workbook
                package.extraParts["ppt/charts/_rels/chart\(index + 1).xml.rels"] = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                    + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" "
                    + "Target=\"../embeddings/Microsoft_Excel_Worksheet\(index + 1).xlsx\"/></Relationships>"
            }
        }
        package.slides = [Package.Slide(xml: Package.slide(frames), relationships: relationships)]
        return package
    }

    /// Charts as PowerPoint writes them: its new chart, a stacked bar chart, a line of dates, a doughnut, and formatted labels.
    static func powerPointChartsPackage() -> Package {
        let labels = ["Category 1", "Category 2", "Category 3"]
        // PowerPoint's new chart: a clustered column chart with its automatic title, theme colors and a legend below.
        let column = Package.chartSpace(
            "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>"
                + Self.series(0, name: "Series 1", labels: labels, values: [4.3, 2.5, 3.5], properties: "<c:spPr><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill></c:spPr>")
                + Self.series(1, name: "Series 2", labels: labels, values: [2.4, 4.4, 1.8])
                + "<c:gapWidth val=\"219\"/><c:overlap val=\"-27\"/>\(Self.axisIDs)</c:barChart>\(Self.axes)",
            chart: "<c:title><c:overlay val=\"0\"/></c:title><c:autoTitleDeleted val=\"0\"/>",
            after: "<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr><c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr><a:latin typeface=\"+mn-lt\"/>"
                + "</a:defRPr></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>")
            .replacingOccurrences(of: "</c:plotArea>", with: "</c:plotArea><c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>")
        // A stacked bar chart whose title was deleted.
        let bars = Package.chartSpace("<c:barChart><c:barDir val=\"bar\"/><c:grouping val=\"stacked\"/><c:varyColors val=\"0\"/>"
            + Self.series(0, name: "Only", labels: labels, values: [1, 2, 3]) + "<c:overlap val=\"100\"/>\(Self.axisIDs)</c:barChart>\(Self.axes)",
            chart: "<c:autoTitleDeleted val=\"1\"/>")
        // Dates along a line, in their format, with a line color of its own and smoothing on every series.
        let dates = Package.chartSpace("<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>"
            + Self.series(0, name: "Visits", labels: ["44927", "44958", "44986"], values: [10, nil, 30],
                          properties: "<c:spPr><a:ln w=\"28575\"><a:solidFill><a:srgbClr val=\"123456\"/></a:solidFill></a:ln></c:spPr>",
                          labelsAsNumbers: true, format: "m/d/yyyy", smooth: true)
            + "<c:marker val=\"1\"/>\(Self.axisIDs)</c:lineChart>\(Self.axes)",
            chart: "<c:title><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:t>Visits</a:t></a:r><a:br/><a:r><a:t>by day</a:t></a:r></a:p></c:rich></c:tx></c:title>")
        // A doughnut without a title takes its lone series' name, as PowerPoint shows it.
        let doughnut = Package.chartSpace("<c:doughnutChart><c:varyColors val=\"1\"/>" + Self.series(0, name: "Share", labels: ["A", "B"], values: [70, 30])
            + "<c:dLbls><c:showVal val=\"0\"/><c:showPercent val=\"1\"/></c:dLbls><c:firstSliceAng val=\"0\"/><c:holeSize val=\"75\"/></c:doughnutChart>")
            .replacingOccurrences(of: "</c:plotArea>", with: "</c:plotArea><c:legend><c:legendPos val=\"r\"/></c:legend>")
        // Percentages and grouped thousands in their formats.
        let percent = Package.chartSpace("<c:areaChart><c:grouping val=\"percentStacked\"/>"
            + Self.series(0, name: nil, labels: ["0.125", "0.5"], values: [1, 2], labelsAsNumbers: true, format: "0.0%")
            + Self.series(1, name: nil, labels: ["0.125", "0.5"], values: [3, 4], labelsAsNumbers: true, format: "0.0%")
            + "\(Self.axisIDs)</c:areaChart>\(Self.axes)")
        let thousands = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/>"
            + Self.series(0, name: "S", labels: ["1234.5", "2", "0.125"], values: [1, 2, 3], labelsAsNumbers: true, format: "#,##0.00")
            + "\(Self.axisIDs)</c:barChart>\(Self.axes)")
        return Self.package([column, bars, dates, doughnut, percent, thousands])
    }

    @Test func powerPointChartsRead() throws {
        let labels = ["Category 1", "Category 2", "Category 3"]
        let file = try PPTXReadTests.read(Self.powerPointChartsPackage())
        #expect(file.warnings.isEmpty)
        let charts = file.presentation.slides[0].elements.compactMap(\.chart)
        #expect(charts.count == 6)

        let first = charts[0]
        #expect(first.kind == .column)
        #expect(first.title == "Chart Title")
        #expect(first.data.labels == labels)
        #expect(first.data.series.map(\.name) == ["Series 1", "Series 2"])
        #expect(first.data.series[1].values == [2.4, 4.4, 1.8])
        // Theme colors as they show: accent 1 by hand, accent 2 automatically.
        #expect(first.data.series.map(\.color) == [RGBColor(hex: "4472C4"), RGBColor(hex: "ED7D31")])
        #expect(first.legend == .bottom && first.showsGridlines && !first.showsDataLabels)
        #expect(first.backgroundColor == nil && first.fontFamily == nil)

        #expect(charts[1].kind == .stackedBar && charts[1].title == "" && charts[1].legend == ChartLegendPosition.none)
        let line = charts[2]
        #expect(line.kind == .smoothLine)
        #expect(line.title == "Visits\nby day")
        #expect(line.data.labels == ["1/1/2023", "2/1/2023", "3/1/2023"])
        #expect(line.data.series[0].values == [10, nil, 30])
        #expect(line.data.series[0].color == RGBColor(hex: "123456"))
        let donut = charts[3]
        #expect(donut.kind == .donut && donut.title == "Share" && donut.pieHole == 0.75 && donut.showsDataLabels && donut.legend == .right)
        #expect(donut.data.series[0].color == nil)
        #expect(charts[4].kind == .percentArea)
        #expect(charts[4].data.labels == ["12.5%", "50.0%"])
        #expect(charts[4].data.series.map(\.name) == ["", ""])
        #expect(charts[5].data.labels == ["1,234.50", "2.00", "0.13"])
    }

    @Test func cachedNumbersShowAsExcelFormatsThem() throws {
        func shown(_ value: Double, _ format: String, date1904: Bool = false) -> String {
            PPTXChartNumber.formatted(value, format: format, date1904: date1904)
        }
        // Halves round away from zero, either side of it.
        #expect(shown(0.125, "0.00") == "0.13" && shown(-0.125, "0.00") == "-0.13" && shown(-2.5, "0") == "-3")
        #expect(shown(1234.5, "#,##0.00") == "1,234.50" && shown(0.125, "0.0%") == "12.5%" && shown(2, "[Blue]0.0") == "2.0")
        // m beside an hour or a second is minutes; hours run to 12 with AM/PM.
        #expect(shown(0.375, "h:mm") == "9:00")
        #expect(shown(0.8125, "h:mm AM/PM") == "7:30 PM")
        #expect(shown(0.5, "hh:mm:ss") == "12:00:00")
        #expect(shown(44927.5, "m/d/yyyy h:mm") == "1/1/2023 12:00")
        #expect(shown(44927, "dddd, mmmm d") == "Sunday, January 1")
        #expect(shown(44927, "mmm-yy") == "Jan-23")
        // Excel's serials before March 1900 count a 29 February that never was; old Mac charts count from 1904.
        #expect(shown(1, "m/d/yyyy") == "1/1/1900" && shown(59, "m/d/yyyy") == "2/28/1900" && shown(61, "m/d/yyyy") == "3/1/1900")
        #expect(shown(0, "yyyy-mm-dd", date1904: true) == "1904-01-01")
        #expect(shown(-1, "m/d/yyyy") == "-1" && shown(1e12, "m/d/yyyy") == "1000000000000")

        let dated = Package.chartSpace("<c:lineChart><c:grouping val=\"standard\"/>"
            + Self.series(0, name: "S", labels: ["0", "366"], values: [1, 2], labelsAsNumbers: true, format: "d mmm yyyy")
            + "\(Self.axisIDs)</c:lineChart>\(Self.axes)").replacingOccurrences(of: "<c:chart>", with: "<c:date1904 val=\"1\"/><c:chart>")
        let chart = try #require(try PPTXReadTests.read(Self.package([dated])).presentation.slides[0].elements.first?.chart)
        #expect(chart.data.labels == ["1 Jan 1904", "1 Jan 1905"])
    }

    @Test func cachedTextIsSpelledAsCellsSpellIt() throws {
        // SpreadsheetML spells characters as _xHHHH_, so text that looks like that is escaped in the caches too.
        let data = ChartData(labelHeading: "H", labels: ["_x0041_", "plain"], series: [ChartSeries(name: "a_x000D_b", values: [1, 2])])
        let presentation = Self.deck([Chart(kind: .column, data: data)])
        let part = try #require(try Package.writtenParts(presentation)["ppt/charts/chart1.xml"])
        #expect(part.contains("<c:v>_x005F_x0041_</c:v>") && part.contains("<c:v>a_x005F_x000D_b</c:v>"))
        let read = try #require(try PPTXRoundTripTests.roundTrip(presentation).presentation.slides[0].elements.first?.chart)
        #expect(read.data == data)
        // PowerPoint's own escapes read as the characters they stand for.
        let escaped = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/>"
            + Self.series(0, name: "Two_x000A_lines", labels: ["A_x0026_B"], values: [1]) + "\(Self.axisIDs)</c:barChart>\(Self.axes)")
        let chart = try #require(try PPTXReadTests.read(Self.package([escaped])).presentation.slides[0].elements.first?.chart)
        #expect(chart.data.series[0].name == "Two\nlines" && chart.data.labels == ["A&B"])
    }

    @Test func kindsWithoutACounterpartAreKeptApproximately() throws {
        let labels = ["A", "B"]
        let radar = Package.chartSpace("<c:radarChart><c:radarStyle val=\"marker\"/>" + Self.series(0, name: "Web", labels: labels, values: [1, 2])
            + "\(Self.axisIDs)</c:radarChart>\(Self.axes)")
        let combo = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" + Self.series(0, name: "Bars", labels: labels, values: [1, 2])
            + "\(Self.axisIDs)</c:barChart><c:lineChart><c:grouping val=\"standard\"/>" + Self.series(1, name: "Line", labels: labels, values: [3, 4])
            + "\(Self.axisIDs)</c:lineChart>\(Self.axes)")
        let bubble = Package.chartSpace("<c:bubbleChart><c:varyColors val=\"0\"/>" + Self.series(0, name: "Bubbles", labels: ["1", "2"], values: [5, 6])
            + "\(Self.axisIDs)</c:bubbleChart>\(Self.axes)")
        let file = try PPTXReadTests.read(Self.package([radar, combo, bubble]))
        #expect(file.warnings == [.charts])
        let charts = file.presentation.slides[0].elements.compactMap(\.chart)
        #expect(charts.map(\.kind) == [.line, .column, .scatter])
        // The data is all there.
        #expect(charts[1].data.series.map(\.name) == ["Bars", "Line"])
        #expect(charts[1].data.series[1].values == [3, 4])

        // A stacked line chart is drawn unstacked, which isn't what it shows.
        let stacked = Package.chartSpace("<c:lineChart><c:grouping val=\"stacked\"/>" + Self.series(0, name: "S", labels: labels, values: [1, 2])
            + "\(Self.axisIDs)</c:lineChart>\(Self.axes)")
        #expect(try PPTXReadTests.read(Self.package([stacked])).warnings == [.charts])

        // 3D charts are drawn flat and a pie of pie as one pie: the data is kept, the look isn't.
        let bars3D = Package.chartSpace("<c:bar3DChart><c:barDir val=\"bar\"/><c:grouping val=\"stacked\"/><c:varyColors val=\"0\"/>"
            + Self.series(0, name: "Only", labels: labels, values: [1, 2]) + "\(Self.axisIDs)</c:bar3DChart>\(Self.axes)")
        let pie3D = Package.chartSpace("<c:pie3DChart><c:varyColors val=\"1\"/>" + Self.series(0, name: "Share", labels: labels, values: [3, 1])
            + "</c:pie3DChart>")
        let pieOfPie = Package.chartSpace("<c:ofPieChart><c:ofPieType val=\"pie\"/><c:varyColors val=\"1\"/>"
            + Self.series(0, name: "Share", labels: labels, values: [3, 1]) + "<c:gapWidth val=\"100\"/><c:secondPieSize val=\"75\"/></c:ofPieChart>")
        let flattened: [(part: String, kind: ChartKind, values: [Double?])] = [(bars3D, .stackedBar, [1, 2]), (pie3D, .pie, [3, 1]), (pieOfPie, .pie, [3, 1])]
        for (part, kind, values) in flattened {
            let file = try PPTXReadTests.read(Self.package([part]))
            #expect(file.warnings == [.charts])
            let chart = try #require(file.presentation.slides[0].elements.first?.chart)
            #expect(chart.kind == kind && chart.data.series[0].values == values)
        }
    }

    @Test func chartsWithoutCachesReadTheirWorkbook() throws {
        let data = ChartData(labelHeading: "Month", labels: ["Jan", "Feb"], series: [ChartSeries(name: "Rain", values: [12.5, nil])])
        let workbook = PPTXWorkbook.write(PPTXChartSheet(Chart(kind: .column, data: data)), date: Date(timeIntervalSince1970: 0))
        let bare = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/>"
            + "<c:tx><c:strRef><c:f>Sheet1!$B$1</c:f></c:strRef></c:tx><c:cat><c:strRef><c:f>Sheet1!$A$2:$A$3</c:f></c:strRef></c:cat>"
            + "<c:val><c:numRef><c:f>Sheet1!$B$2:$B$3</c:f></c:numRef></c:val></c:ser>\(Self.axisIDs)</c:barChart>\(Self.axes)",
            chart: "<c:autoTitleDeleted val=\"1\"/>")
        let file = try PPTXReadTests.read(Self.package([bare], workbooks: [0: workbook]))
        #expect(file.warnings.isEmpty)
        let chart = try #require(file.presentation.slides[0].elements.first?.chart)
        #expect(chart.data.labelHeading == "Month")
        #expect(chart.data.labels == ["Jan", "Feb"])
        #expect(chart.data.series.map(\.name) == ["Rain"])
        #expect(chart.data.series[0].values == [12.5, nil])
    }

    @Test func chartsThatCannotBeReadWarn() throws {
        let good = Package.chartSpace("<c:pieChart><c:varyColors val=\"1\"/>" + Self.series(0, name: "P", labels: ["a"], values: [1]) + "</c:pieChart>")
        var package = Self.package([good, "<c:chartSpace xmlns:c=\"urn:c\"><c:chart>", "<c:chartSpace xmlns:c=\"urn:c\"><c:chart/></c:chartSpace>"])
        // A frame whose relationship is missing, and one to a part that isn't there.
        package.slides[0].xml = package.slides[0].xml.replacingOccurrences(of: "</p:spTree>", with:
            Package.chartFrame(30, "Unlinked", relationship: "rId99") + Package.chartFrame(31, "Gone", relationship: "rId98") + "</p:spTree>")
        package.slides[0].relationships.append(Package.Relationship("rId98", "chart", "../charts/missing.xml"))
        // A damaged workbook: the caches are enough.
        package.media["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"] = Data("not a zip".utf8)
        package.extraParts["ppt/charts/_rels/chart1.xml.rels"] = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" "
            + "Target=\"../embeddings/Microsoft_Excel_Worksheet1.xlsx\"/></Relationships>"
        let file = try PPTXReadTests.read(package)
        #expect(file.warnings == [.charts])
        #expect(file.presentation.slides[0].elements.map(\.name) == ["Chart 1"])
        #expect(file.presentation.slides[0].elements[0].chart?.data.labelHeading == "")
    }
}
