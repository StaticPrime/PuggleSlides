import Foundation

/// A chart as written: its part, the part's relationships, and the workbook PowerPoint edits the chart's data in.
struct PPTXChartParts {
    var chartPath: String
    var chart: Data
    var relationships: Data
    var workbookPath: String
    var workbook: Data
}

/// Writes a chart as a DrawingML chart part (`c:chartSpace`), drawn the way PuggleSlides draws it: series in the
/// palette's colors, each as references into an embedded workbook with caches of the values, so PowerPoint shows the
/// chart straight away and lets its data be edited.
enum PPTXChartWriter {
    static let categoryAxisID = 1001
    static let valueAxisID = 1002
    /// Chart lines and the lines between pie slices, in EMU (1.5 and 1 point).
    static let lineWidth = 19_050
    static let sliceLineWidth = 12_700
    /// Areas fill at 30% opacity, under a line of the series' color.
    static let areaOpacity = 30_000
    static let gridlineColor = "CCCCCC"
    static let axisLineColor = "BDBDBD"
    /// A line that doesn't show. A fully transparent line rather than one without fill: Quick Look and Keynote draw
    /// lines without fill in black.
    static let hiddenLine = "<a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"FFFFFF\"><a:alpha val=\"0\"/></a:srgbClr></a:solidFill></a:ln>"

    /// How a chart kind is drawn: one DrawingML chart group.
    enum Family {
        case bar, line, area, pie, doughnut, scatter

        init(_ kind: ChartKind) {
            switch kind {
            case .column, .stackedColumn, .percentColumn, .bar, .stackedBar, .percentBar: self = .bar
            case .line, .smoothLine: self = .line
            case .area, .stackedArea, .percentArea: self = .area
            case .pie: self = .pie
            case .donut: self = .doughnut
            case .scatter: self = .scatter
            }
        }
    }

    static func parts(_ chart: Chart, number: Int, date: Date) -> PPTXChartParts {
        let chartPath = "ppt/charts/chart\(number).xml"
        let workbookPath = "ppt/embeddings/Microsoft_Excel_Worksheet\(number).xlsx"
        let sheet = PPTXChartSheet(chart)
        var relationships = PPTXRelationshipsWriter()
        let workbook = relationships.add(type: PPTXRelationshipType.package, target: PPTXPackage.relativeTarget(from: chartPath, to: workbookPath))
        return PPTXChartParts(chartPath: chartPath, chart: chartPart(chart, sheet: sheet, workbookRelationship: workbook),
                              relationships: relationships.data(), workbookPath: workbookPath, workbook: PPTXWorkbook.write(sheet, date: date))
    }

    static func chartPart(_ chart: Chart, sheet: PPTXChartSheet, workbookRelationship: String) -> Data {
        var xml = XMLWriter(reservingCapacity: min(4096 + sheet.rowCount * (sheet.data.series.count + 1) * 96, 16 << 20))
        xml.raw("<c:chartSpace xmlns:c=\"\(PPTXNamespace.chart)\" xmlns:a=\"\(PPTXNamespace.drawing)\" xmlns:r=\"\(PPTXNamespace.relationships)\">")
        xml.raw("<c:date1904 val=\"0\"/><c:roundedCorners val=\"0\"/><c:chart>")
        if chart.title.isEmpty {
            xml.raw("<c:autoTitleDeleted val=\"1\"/>")
        } else {
            title(chart.title, size: 1400, rotated: false, into: &xml)
            xml.raw("<c:autoTitleDeleted val=\"0\"/>")
        }
        xml.raw("<c:plotArea><c:layout/>")
        group(chart, sheet: sheet, into: &xml)
        axes(chart, into: &xml)
        xml.raw("</c:plotArea>")
        legend(chart.legend, into: &xml)
        xml.raw("<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/></c:chart>")
        let background = chart.backgroundColor ?? .white
        xml.raw("<c:spPr><a:solidFill><a:srgbClr val=\"\(background.hex)\"/></a:solidFill>\(hiddenLine)</c:spPr>")
        if let font = chart.fontFamily, !font.isEmpty {
            xml.raw("<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr><a:latin")
            xml.attribute("typeface", font)
            xml.raw("/></a:defRPr></a:pPr><a:endParaRPr/></a:p></c:txPr>")
        }
        // The workbook is a copy of the data, not a link: PowerPoint shouldn't try to refresh it from elsewhere.
        xml.raw("<c:externalData r:id=\"\(workbookRelationship)\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>")
        return xml.data
    }

    // MARK: Groups

    private static func group(_ chart: Chart, sheet: PPTXChartSheet, into xml: inout XMLWriter) {
        let kind = chart.kind
        let family = Family(kind)
        let grouping = kind.isStacked ? "stacked" : kind.isPercent ? "percentStacked" : family == .bar ? "clustered" : "standard"
        switch family {
        case .bar: xml.raw("<c:barChart><c:barDir val=\"\(kind.isBar ? "bar" : "col")\"/><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>")
        case .line: xml.raw("<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>")
        case .area: xml.raw("<c:areaChart><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>")
        case .pie: xml.raw("<c:pieChart><c:varyColors val=\"1\"/>")
        case .doughnut: xml.raw("<c:doughnutChart><c:varyColors val=\"1\"/>")
        // Points only: the style says so for apps that go by it, and the series' hidden lines for those that don't.
        case .scatter: xml.raw("<c:scatterChart><c:scatterStyle val=\"marker\"/><c:varyColors val=\"0\"/>")
        }
        for index in sheet.data.series.indices {
            series(index, family: family, chart: chart, sheet: sheet, into: &xml)
        }
        if chart.showsDataLabels {
            xml.raw("<c:dLbls><c:showLegendKey val=\"0\"/><c:showVal val=\"1\"/><c:showCatName val=\"0\"/><c:showSerName val=\"0\"/>"
                + "<c:showPercent val=\"0\"/><c:showBubbleSize val=\"0\"/>")
            if family == .pie || family == .doughnut { xml.raw("<c:showLeaderLines val=\"1\"/>") }
            xml.raw("</c:dLbls>")
        }
        let axes = "<c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/>"
        switch family {
        case .bar:
            xml.raw("<c:gapWidth val=\"150\"/>")
            if grouping != "clustered" { xml.raw("<c:overlap val=\"100\"/>") }
            xml.raw(axes + "</c:barChart>")
        case .line: xml.raw("<c:marker val=\"1\"/>" + axes + "</c:lineChart>")
        case .area: xml.raw(axes + "</c:areaChart>")
        case .pie: xml.raw("<c:firstSliceAng val=\"0\"/></c:pieChart>")
        case .doughnut:
            let hole = PPTXValue.clamped(chart.pieHole * 100, 10...90, fallback: 50)
            xml.raw("<c:firstSliceAng val=\"0\"/><c:holeSize val=\"\(hole)\"/></c:doughnutChart>")
        case .scatter: xml.raw(axes + "</c:scatterChart>")
        }
    }

    // MARK: Series

    /// One `c:ser`, in its kind's schema order: idx, order, tx, spPr, then marker or slice colors, the labels and the
    /// values.
    private static func series(_ index: Int, family: Family, chart: Chart, sheet: PPTXChartSheet, into xml: inout XMLWriter) {
        let series = sheet.data.series[index]
        let color = chart.color(ofSeries: index).hex
        xml.raw("<c:ser><c:idx val=\"\(index)\"/><c:order val=\"\(index)\"/>")
        if !series.name.isEmpty {
            xml.raw("<c:tx>")
            stringReference(sheet.nameReference(index), values: [series.name], into: &xml)
            xml.raw("</c:tx>")
        }
        switch family {
        case .bar:
            xml.raw("<c:spPr><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill></c:spPr><c:invertIfNegative val=\"0\"/>")
        case .line:
            xml.raw("<c:spPr><a:ln w=\"\(lineWidth)\" cap=\"rnd\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:round/></a:ln></c:spPr>")
            xml.raw("<c:marker><c:symbol val=\"none\"/></c:marker>")
        case .area:
            xml.raw("<c:spPr><a:solidFill><a:srgbClr val=\"\(color)\"><a:alpha val=\"\(areaOpacity)\"/></a:srgbClr></a:solidFill>")
            xml.raw("<a:ln w=\"\(lineWidth)\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill></a:ln></c:spPr>")
        case .scatter:
            // Scatter charts are points only.
            xml.raw("<c:spPr>\(hiddenLine)</c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/>")
            xml.raw("<c:spPr><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"\(color)\"/>")
            xml.raw("</a:solidFill></a:ln></c:spPr></c:marker>")
        case .pie, .doughnut:
            // Pies color each slice from the palette, with white lines between them. A series color of its own
            // is kept on the series, under the slices' colors.
            if let own = series.color { xml.raw("<c:spPr><a:solidFill><a:srgbClr val=\"\(own.hex)\"/></a:solidFill></c:spPr>") }
            for slice in 0..<min(sheet.rowCount, 1024) {
                xml.raw("<c:dPt><c:idx val=\"\(slice)\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"\(chart.color(ofSlice: slice).hex)\"/>")
                xml.raw("</a:solidFill><a:ln w=\"\(sliceLineWidth)\"><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill></a:ln></c:spPr></c:dPt>")
            }
        }
        if let labels = sheet.labelReference {
            xml.raw(family == .scatter ? "<c:xVal>" : "<c:cat>")
            if sheet.numericLabels {
                numberReference(labels, values: sheet.data.labels.map { PPTXChartNumber.exactValue($0) }, into: &xml)
            } else {
                stringReference(labels, values: sheet.data.labels, into: &xml)
            }
            xml.raw(family == .scatter ? "</c:xVal>" : "</c:cat>")
        }
        if let values = sheet.valueReference(index) {
            xml.raw(family == .scatter ? "<c:yVal>" : "<c:val>")
            numberReference(values, values: series.values, into: &xml)
            xml.raw(family == .scatter ? "</c:yVal>" : "</c:val>")
        }
        if family == .line || family == .scatter { xml.raw("<c:smooth val=\"\(chart.kind == .smoothLine ? 1 : 0)\"/>") }
        xml.raw("</c:ser>")
    }

    /// Text cells by reference, with their current text cached as cells keep it (`_xHHHH_` spelled out); empty cells
    /// have no point.
    static func stringReference(_ formula: String, values: [String], into xml: inout XMLWriter) {
        xml.raw("<c:strRef><c:f>")
        xml.text(formula)
        xml.raw("</c:f><c:strCache><c:ptCount val=\"\(values.count)\"/>")
        for (index, value) in values.enumerated() where !value.isEmpty {
            xml.raw("<c:pt idx=\"\(index)\"><c:v>")
            xml.text(PPTXWorkbook.escaped(PPTXWorkbook.clipped(value)))
            xml.raw("</c:v></c:pt>")
        }
        xml.raw("</c:strCache></c:strRef>")
    }

    /// Number cells by reference, with their values cached; gaps have no point.
    static func numberReference(_ formula: String, values: [Double?], into xml: inout XMLWriter) {
        xml.raw("<c:numRef><c:f>")
        xml.text(formula)
        xml.raw("</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(values.count)\"/>")
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite else { continue }
            xml.raw("<c:pt idx=\"\(index)\"><c:v>\(PPTXChartNumber.string(value))</c:v></c:pt>")
        }
        xml.raw("</c:numCache></c:numRef>")
    }

    // MARK: Titles, axes and legend

    /// A title of one paragraph per line.
    static func title(_ text: String, size: Int?, rotated: Bool, into xml: inout XMLWriter) {
        let sizeAttribute = size.map { " sz=\"\($0)\"" } ?? ""
        xml.raw("<c:title><c:tx><c:rich>")
        xml.raw(rotated ? "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/>" : "<a:bodyPr/>")
        xml.raw("<a:lstStyle/>")
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for line in lines {
            xml.raw("<a:p><a:pPr><a:defRPr\(sizeAttribute) b=\"0\"/></a:pPr>")
            if line.isEmpty {
                xml.raw("<a:endParaRPr\(sizeAttribute) b=\"0\"/>")
            } else {
                xml.raw("<a:r><a:rPr\(sizeAttribute) b=\"0\"/><a:t>")
                xml.text(line)
                xml.raw("</a:t></a:r>")
            }
            xml.raw("</a:p>")
        }
        xml.raw("</c:rich></c:tx><c:overlay val=\"0\"/></c:title>")
    }

    /// Category and value axes (two value axes for scatter charts). Bar charts list their categories from the top,
    /// with the values along the bottom.
    private static func axes(_ chart: Chart, into xml: inout XMLWriter) {
        let kind = chart.kind
        guard !kind.isPie else { return }
        let isBar = kind.isBar
        if kind == .scatter {
            valueAxis(id: categoryAxisID, cross: valueAxisID, position: "b", title: chart.horizontalAxisTitle, rotated: false, chart: nil,
                      between: "midCat", into: &xml)
            valueAxis(id: valueAxisID, cross: categoryAxisID, position: "l", title: chart.verticalAxisTitle, rotated: true, chart: chart,
                      between: "midCat", into: &xml)
            return
        }
        xml.raw("<c:catAx><c:axId val=\"\(categoryAxisID)\"/><c:scaling><c:orientation val=\"\(isBar ? "maxMin" : "minMax")\"/></c:scaling>")
        xml.raw("<c:delete val=\"0\"/><c:axPos val=\"\(isBar ? "l" : "b")\"/>")
        let categoryTitle = isBar ? chart.verticalAxisTitle : chart.horizontalAxisTitle
        if !categoryTitle.isEmpty { title(categoryTitle, size: nil, rotated: isBar, into: &xml) }
        xml.raw("<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/>")
        xml.raw("<c:tickLblPos val=\"nextTo\"/><c:spPr><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"\(axisLineColor)\"/></a:solidFill></a:ln></c:spPr>")
        xml.raw("<c:crossAx val=\"\(valueAxisID)\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/>")
        xml.raw("<c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/></c:catAx>")
        valueAxis(id: valueAxisID, cross: categoryAxisID, position: isBar ? "b" : "l", title: isBar ? chart.horizontalAxisTitle : chart.verticalAxisTitle,
                  rotated: !isBar, chart: chart, between: "between", crossesAtMaximum: isBar, into: &xml)
    }

    /// A value axis; `chart` carries the range and gridlines of the main one (nil for a scatter chart's x axis).
    private static func valueAxis(id: Int, cross: Int, position: String, title text: String, rotated: Bool, chart: Chart?, between: String,
                                  crossesAtMaximum: Bool = false, into xml: inout XMLWriter) {
        xml.raw("<c:valAx><c:axId val=\"\(id)\"/><c:scaling><c:orientation val=\"minMax\"/>")
        if let maximum = chart?.verticalMaximum, maximum.isFinite { xml.raw("<c:max val=\"\(PPTXChartNumber.string(maximum))\"/>") }
        if let minimum = chart?.verticalMinimum, minimum.isFinite { xml.raw("<c:min val=\"\(PPTXChartNumber.string(minimum))\"/>") }
        xml.raw("</c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(position)\"/>")
        if chart?.showsGridlines == true {
            xml.raw("<c:majorGridlines><c:spPr><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"\(gridlineColor)\"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>")
        }
        if !text.isEmpty { title(text, size: nil, rotated: rotated, into: &xml) }
        let percent = chart?.kind.isPercent == true
        xml.raw(percent ? "<c:numFmt formatCode=\"0%\" sourceLinked=\"0\"/>" : "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>")
        xml.raw("<c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/><c:spPr>\(hiddenLine)</c:spPr>")
        xml.raw("<c:crossAx val=\"\(cross)\"/><c:crosses val=\"\(crossesAtMaximum ? "max" : "autoZero")\"/><c:crossBetween val=\"\(between)\"/></c:valAx>")
    }

    /// No legend for none; Auto leaves the position to the app (PowerPoint puts it on the right).
    private static func legend(_ position: ChartLegendPosition, into xml: inout XMLWriter) {
        let code: String
        switch position {
        case .none: return
        case .auto:
            xml.raw("<c:legend><c:overlay val=\"0\"/></c:legend>")
            return
        case .right: code = "r"
        case .top: code = "t"
        case .bottom: code = "b"
        case .left: code = "l"
        }
        xml.raw("<c:legend><c:legendPos val=\"\(code)\"/><c:overlay val=\"0\"/></c:legend>")
    }
}

extension PPTXPartWriter {
    /// A chart: a graphic frame referring to its chart part, which the package writer adds with its workbook.
    mutating func chart(_ element: SlideElement, _ chart: Chart) {
        let chartPath = state.addChart(chart)
        let relationship = relationship(type: PPTXRelationshipType.chart, to: chartPath)
        xml.raw("<p:graphicFrame><p:nvGraphicFramePr>")
        nonVisualProperties(element, fallbackName: "Chart", kind: .graphicFrame, build: .graphic)
        xml.raw("<p:cNvGraphicFramePr/>")
        applicationProperties(element.placeholder)
        xml.raw("</p:nvGraphicFramePr>")
        transform(element.placement ?? Placement(frame: .zero), tag: "p:xfrm")
        xml.raw("<a:graphic><a:graphicData uri=\"\(PPTXNamespace.chart)\"><c:chart xmlns:c=\"\(PPTXNamespace.chart)\" r:id=\"\(relationship)\"/>")
        xml.raw("</a:graphicData></a:graphic></p:graphicFrame>")
    }
}
