import Foundation
import Testing
@testable import PuggleSlidesKit

/// Tables, charts, word art, picture adjustments and guides: written as LibreOffice Impress writes them and read back
/// showing the same.
struct ODPObjectTests {
    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        try PresentationIO.read(try PresentationIO.write(presentation, format: .odp), format: .odp)
    }

    static func parts(_ presentation: Presentation) throws -> [String: Data] {
        try ODPTestPackage.parts(of: try ODPWriter.write(presentation))
    }

    @Test func objectsRoundTrip() throws {
        let original = ODPSamples.objects()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = ODPRendering.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")

        let read = file.presentation
        #expect(read.slides.count == original.slides.count)
        #expect(read.slides[0].elements.map(\.name) == ["Plain table", "Designed table"])
        #expect(read.slides[0].elements[0].altTitle == "Plain" && read.slides[0].elements[0].altDescription == "A new table")
        #expect(read.slides[1].elements[0].altDescription == "Sales by month")
        // New tables keep their text size as the cells' own list style.
        let plain = try #require(read.slides[0].elements[0].table)
        #expect(plain.cells[0][0].text.listStyle[0].character.fontSize == 14)
        #expect(plain.horizontalBorders.joined().allSatisfy { $0 == Table.defaultBorder })
        // Charts keep their numbers, gaps included, and their kinds.
        let charts = (read.slides[1].elements + read.slides[2].elements).compactMap(\.chart)
        #expect(charts.map(\.kind) == ChartKind.allCases)
        #expect(charts[0].data.series[2].values == [5, nil, -3.5, 1e-3])
        #expect(charts[0].data.labelHeading == "Month" && charts[1].data.labelHeading == "")
        #expect(charts[13].data.labels == ["1", "2.5", "4", "7.25"])
        // Word art, picture adjustments, guides and animations of tables and charts.
        #expect(read.slides[3].elements.prefix(2).allSatisfy { $0.isWordArt })
        #expect(read.slides[3].elements.compactMap(\.picture).map(\.adjustments) == original.slides[3].elements.compactMap(\.picture).map(\.adjustments))
        #expect(read.guides.map(\.position) == [360, 180, 36])
        #expect(read.slides[0].animations.map(\.effect) == [.fadeIn, .flyInFromLeft])
        #expect(read.slides[0].animations.map(\.elementID) == read.slides[0].elements.map(\.id))
        #expect(read.slides[1].animations.map(\.elementID) == [read.slides[1].elements[0].id, read.slides[1].elements[3].id])
        // The layout's own table and chart are on its master page.
        let report = try #require(read.layout(for: read.slides[4]))
        #expect(report.elements.compactMap(\.table).count == 1 && report.elements.compactMap(\.chart).count == 1)
    }

    @Test func objectsStayTheSameWrittenAgain() throws {
        let first = try Self.roundTrip(ODPSamples.objects()).presentation
        let second = try Self.roundTrip(first).presentation
        let difference = ODPRendering.difference(first, second)
        #expect(difference == nil, "\(difference ?? "")")
        let third = try Self.roundTrip(second).presentation
        #expect(ODPModel.difference(second, third) == nil, "\(ODPModel.difference(second, third) ?? "")")
    }

    @Test func tablesAreWrittenAsLibreOfficeWritesThem() throws {
        let parts = try Self.parts(ODPSamples.objects())
        let content = try ODFXML.parse(try #require(parts["content.xml"]))
        let tables = ODPWriteTests.descendants(content, "table:table")
        #expect(tables.count == 2)
        let designed = tables[1]
        #expect(designed.children("table:table-column").count == 4)
        let rows = designed.children("table:table-row")
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0.elements.count == 4 })
        // The header spans two columns and covers the cell beside it; the merged block spans two rows and columns.
        #expect(rows[0].elements[0]["table:number-columns-spanned"] == "2" && rows[0].elements[1].name == "table:covered-table-cell")
        #expect(rows[2].elements[2]["table:number-rows-spanned"] == "2" && rows[2].elements[2]["table:number-columns-spanned"] == "2")
        #expect(rows[3].elements[2].name == "table:covered-table-cell" && rows[3].elements[3].name == "table:covered-table-cell")
        // Cell styles state the cell's look in table cell properties: fill, borders, alignment and padding.
        let automatic = try #require(content.child("office:automatic-styles"))
        func style(_ node: ODFNode) -> ODFNode? {
            automatic.children("style:style").first { $0["style:name"] == node["table:style-name"] }
        }
        let header = try #require(style(rows[0].elements[0])?.child("style:table-cell-properties"))
        #expect(header["fo:background-color"] == "#4285f4")
        #expect(header["fo:border-bottom"] == "2.25pt solid #cc0000")
        #expect(header["style:vertical-align"] == "top")
        #expect(header["fo:padding-left"] == "7.2pt")
        let bottomCell = try #require(style(rows[1].elements[0])?.child("style:table-cell-properties"))
        let dark2 = ODFFormat.color(BuiltInThemes.simpleLight().colors[.dark2])
        #expect(bottomCell["style:vertical-align"] == "bottom" && bottomCell["fo:padding-bottom"] == "0pt")
        #expect(bottomCell["fo:border-left"] == "1.5pt dotted \(dark2)" && bottomCell["fo:border-right"] == "1.5pt fine-dashed \(dark2)")
        #expect(style(rows[1].elements[1])?.child("style:table-cell-properties")?["fo:border-right"] == "1.5pt dashed \(dark2)")
        #expect(style(rows[1].elements[2])?.child("style:table-cell-properties")?["fo:border-right"] == "1.5pt dash-dot \(dark2)")
        #expect(style(rows[1].elements[3])?.child("style:table-cell-properties")?["fo:border-right"] == "1.5pt dash-dot-dot \(dark2)")
        let picture = try #require(style(rows[1].elements[2])?.child("style:table-cell-properties"))
        #expect(picture["fo:background-color"] == "transparent")
        #expect(picture.child("style:background-image")?["style:repeat"] == "repeat")
        #expect(picture.child("style:background-image")?["xlink:href"]?.hasPrefix("Pictures/") == true)
        #expect(style(rows[4].elements[1])?.child("style:table-cell-properties")?["fo:border-left"] == "none")
        // Each cell's text starts from the formatting its style gives: a new table's cells at 14 points, so their text
        // needs no spans of its own.
        let plainRows = ODPWriteTests.descendants(tables[0], "table:table-row")
        #expect(style(plainRows[0].elements[0])?.child("style:text-properties")?["fo:font-size"] == "14pt")
        #expect(plainRows[1].elements[2].child("text:p")?.textContent == "Typed")
        #expect(rows[4].elements[1].child("text:p")?.textContent == "R5C2")
        // Columns and rows have their sizes.
        func size(_ node: ODFNode, _ element: String, _ attribute: String) -> String? {
            automatic.children("style:style").first { $0["style:name"] == node["table:style-name"] }?.child(element)?[attribute]
        }
        #expect(designed.children("table:table-column").map { size($0, "style:table-column-properties", "style:column-width") } == ["120.5pt", "80pt", "100pt", "99.5pt"])
        #expect(rows.map { size($0, "style:table-row-properties", "style:row-height") } == ["30pt", "24.25pt", "40pt", "40pt", "20pt"])
        // The table's frame is rotated about its center and names its table nothing else.
        let frame = try #require(ODPWriteTests.descendants(content, "draw:frame").first { $0["draw:name"] == "Designed table" })
        #expect(frame["draw:transform"]?.hasPrefix("rotate (") == true)
        #expect(frame.elements.first?.name == "table:table")
    }

    @Test func chartsAreEmbeddedObjects() throws {
        let parts = try Self.parts(ODPSamples.objects())
        let manifest = try ODFXML.parse(try #require(parts["META-INF/manifest.xml"]))
        var listed: [String: String] = [:]
        for entry in manifest.children("manifest:file-entry") { listed[entry["manifest:full-path"] ?? ""] = entry["manifest:media-type"] }
        // Fourteen slide charts and the layout's own.
        for number in 1...15 {
            #expect(listed["Object \(number)/"] == "application/vnd.oasis.opendocument.chart")
            for part in ["content.xml", "styles.xml", "meta.xml"] {
                #expect(listed["Object \(number)/\(part)"] == "text/xml")
                #expect(parts["Object \(number)/\(part)"] != nil)
            }
        }
        #expect(listed["settings.xml"] == "text/xml")
        let content = try ODFXML.parse(try #require(parts["content.xml"]))
        let objects = ODPWriteTests.descendants(content, "draw:object").compactMap { $0["xlink:href"] }
        #expect(objects.count == 14 && objects.allSatisfy { $0.hasPrefix("./Object ") })

        // A column chart's object (the layout's master page came first): the class, its local table, and series pointing
        // into it.
        #expect(objects.first == "./Object 2")
        let chartContent = try ODFXML.parse(try #require(parts["Object 2/content.xml"]))
        let chart = try #require(chartContent.child("office:body")?.child("office:chart")?.child("chart:chart"))
        #expect(chart["chart:class"] == "chart:bar" && chart["xlink:href"] == ".")
        let plotArea = try #require(chart.child("chart:plot-area"))
        #expect(plotArea["table:cell-range-address"] == "local-table.$A$1:.$D$5")
        let series = plotArea.children("chart:series")
        #expect(series.map { $0["chart:values-cell-range-address"] ?? "" } == ["local-table.$B$2:.$B$5", "local-table.$C$2:.$C$5", "local-table.$D$2:.$D$5"])
        #expect(series.map { $0["chart:label-cell-address"] ?? "" } == ["local-table.$B$1", "local-table.$C$1", "local-table.$D$1"])
        let categories = plotArea.children("chart:axis").first { $0["chart:dimension"] == "x" }?.child("chart:categories")
        #expect(categories?["table:cell-range-address"] == "local-table.$A$2:.$A$5")
        let table = try #require(chart.child("table:table"))
        #expect(table["table:name"] == "local-table")
        let rows = ODPWriteTests.descendants(table, "table:table-row")
        #expect(rows.count == 5)
        #expect(rows[2].elements.last?["office:value"] == "NaN")
        // A pie colors each slice; a doughnut has a hole.
        let donut = try ODFXML.parse(try #require(parts["Object 14/content.xml"]))
        let ring = try #require(donut.child("office:body")?.child("office:chart")?.child("chart:chart"))
        #expect(ring["chart:class"] == "chart:ring")
        #expect(ODPWriteTests.descendants(ring, "chart:data-point").count == 4)
        let styles = donut.child("office:automatic-styles")?.children("style:style") ?? []
        #expect(styles.contains { $0.child("style:chart-properties")?["chart:hole-size"] == "60%" })
    }

    @Test func wordArtIsFontwork() throws {
        let parts = try Self.parts(ODPSamples.objects())
        let content = try ODFXML.parse(try #require(parts["content.xml"]))
        let shape = try #require(ODPWriteTests.descendants(content, "draw:custom-shape").first { $0["draw:name"] == "Word art" })
        let geometry = try #require(shape.child("draw:enhanced-geometry"))
        #expect(geometry["draw:type"] == "fontwork-plain-text")
        #expect(geometry["draw:text-path"] == "true" && geometry["draw:text-path-mode"] == "shape" && geometry["draw:text-path-scale"] == "shape")
        #expect(shape.children("text:p").map(\.textContent) == ["Hello", "World"])
        // The letters are painted with the shape's fill and line.
        let automatic = try #require(content.child("office:automatic-styles"))
        let graphic = automatic.children("style:style").first { $0["style:name"] == shape["draw:style-name"] }?.child("style:graphic-properties")
        #expect(graphic?["draw:fill"] == "solid" && graphic?["draw:fill-color"] == "#cccccc")
        #expect(graphic?["draw:stroke"] == "solid" && graphic?["svg:stroke-color"] == "#000000")
    }

    @Test func pictureAdjustmentsAreImageProperties() throws {
        let parts = try Self.parts(ODPSamples.objects())
        let content = try ODFXML.parse(try #require(parts["content.xml"]))
        let automatic = try #require(content.child("office:automatic-styles"))
        func graphic(_ name: String) -> ODFNode? {
            let frame = ODPWriteTests.descendants(content, "draw:frame").first { $0["draw:name"] == name }
            return automatic.children("style:style").first { $0["style:name"] == frame?["draw:style-name"] }?.child("style:graphic-properties")
        }
        #expect(graphic("Faded")?["draw:image-opacity"] == "75%")
        #expect(graphic("Brighter")?["draw:luminance"] == "30%" && graphic("Brighter")?["draw:contrast"] == "-20%")
        #expect(graphic("Gray")?["draw:color-mode"] == "greyscale" && graphic("Gray")?["draw:color-inversion"] == nil)
        #expect(graphic("Negative")?["draw:color-mode"] == "greyscale" && graphic("Negative")?["draw:color-inversion"] == "true")
        #expect(graphic("Untouched")?["draw:color-mode"] == nil && graphic("Untouched")?["draw:image-opacity"] == nil)
    }

    /// What OpenDocument can't hold of tables, charts, pictures, word art and guides comes back as the nearest thing it can.
    @Test func featuresOutsideODFDegradeToTheNearest() throws {
        var presentation = Presentation.makeDefault()
        let photo = presentation.addMedia(ODPSamples.photo, contentType: "image/png")
        var slide = presentation.makeSlide(layoutID: presentation.themes[0].layout(kind: .blank)!.id)
        var table = Table.make(rows: 1, columns: 3, width: 300)
        table.cells[0][0].fill = .gradient(GradientFill(kind: .linear(angle: 0), stops: [GradientStop(position: 0, color: .white),
                                                                                          GradientStop(position: 1, color: .black)]))
        table.cells[0][1].fill = .solid(ColorRef(RGBColor(red: 200, green: 0, blue: 0), alpha: 0.5))
        table.cells[0][2].fill = .solid(ColorRef(RGBColor.white, alpha: 0))
        table.horizontalBorders[0][0] = Outline(fill: .solid(ColorRef(RGBColor.black, alpha: 0.5)), width: 1, head: .fillArrow)
        table.horizontalBorders[0][1] = Outline(fill: .gradient(GradientFill(kind: .radial, stops: [GradientStop(position: 0, color: ColorRef(theme: .accent1))])),
                                                width: 3)
        var pie = Chart.sample(.pie)
        pie.data.series.append(ChartSeries(name: "Hidden", values: [1, 2, 3, 4]))
        var column = Chart.sample(.column)
        column.data.series[0].color = Chart.palette[0]
        var oval = Shape.wordArt("Oval")
        oval.geometry = .preset("ellipse", adjustments: [:])
        func picture(_ recolor: ImageRecolor?, geometry: ShapeGeometry = .rectangle, transparency: Double = 0) -> SlideElement {
            SlideElement(placement: Placement(frame: SlideRect(x: 0, y: 0, width: 50, height: 50)),
                         content: .picture(Picture(mediaID: photo, geometry: geometry, adjustments: ImageAdjustments(transparency: transparency, recolor: recolor))))
        }
        slide.elements = [
            SlideElement(placement: Placement(frame: SlideRect(x: 10, y: 10, width: 300, height: 30)), content: .table(table)),
            SlideElement(placement: Placement(frame: SlideRect(x: 10, y: 50, width: 200, height: 150), flipHorizontal: true), content: .chart(pie)),
            SlideElement(placement: Placement(frame: SlideRect(x: 220, y: 50, width: 200, height: 150)), content: .chart(column)),
            SlideElement(placement: Placement(frame: SlideRect(x: 10, y: 210, width: 200, height: 60)), content: .shape(oval)),
            picture(.sepia), picture(.light(.accent1)), picture(.dark(.accent2)), picture(.duotone(.black, ColorRef(theme: .accent3))),
            picture(.negative, geometry: .preset("ellipse", adjustments: [:]), transparency: 0.5),
        ]
        presentation.slides = [slide]
        presentation.guides = [Guide(orientation: .horizontal, position: 100.5, color: RGBColor(red: 255, green: 0, blue: 255))]
        let file = try Self.roundTrip(presentation)
        #expect(file.warnings.isEmpty)
        let read = file.presentation.slides[0].elements
        // Cells have no gradients or transparency: a gradient is its middle color, a color loses its transparency, and a
        // clear color is no fill. Borders are colors without transparency or arrowheads.
        let cells = try #require(read[0].table).cells[0]
        #expect(cells.map(\.fill) == [.solid(ColorRef(RGBColor(red: 128, green: 128, blue: 128))), .solid(ColorRef(RGBColor(red: 200, green: 0, blue: 0))), Fill.none])
        let borders = try #require(read[0].table).horizontalBorders[0]
        #expect(borders[0] == Outline(fill: .solid(.black), width: 1))
        #expect(borders[1] == Outline(fill: .solid(ColorRef(RGBColor(hex: "4285F4")!)), width: 3))
        // A pie keeps the series it shows; charts don't flip; a series' color that's the palette's anyway stays automatic.
        #expect(read[1].chart?.data.series.map(\.name) == ["Series 1"])
        #expect(read[1].placement?.flipHorizontal == false)
        #expect(read[2].chart?.data.series[0].color == nil)
        // Word art's letters fill its frame whatever its shape.
        #expect(read[3].shape?.geometry == .rectangle && read[3].isWordArt)
        // ODF's only recolors are grayscale and inverted: tints are grayscale. A masked picture is a shape filled with the
        // picture, which keeps none of its adjustments.
        #expect(read.dropFirst(4).prefix(4).map { $0.picture?.adjustments.recolor } == [.grayscale, .grayscale, .grayscale, .grayscale])
        #expect(read[8].shape?.fill?.mediaID != nil)
        // Guides have no colors, and sit to the hundredth of a millimeter.
        let guide = try #require(file.presentation.guides.first)
        #expect(guide.color == nil && abs(guide.position - 100.5) < 0.015 && guide.orientation == .horizontal)
    }

    @Test func guidesAreLibreOfficeSnapLines() throws {
        let parts = try Self.parts(ODPSamples.objects())
        let settings = try #require(parts["settings.xml"].map { String(decoding: $0, as: UTF8.self) })
        #expect(settings.contains("<config:config-item config:name=\"SnapLinesDrawing\" config:type=\"string\">V12700H6350V1270</config:config-item>"))
        // No guides, no settings.
        #expect(try Self.parts(Presentation.makeDefault())["settings.xml"] == nil)
        #expect(ODPSettings.guides(snapLines: "V100H-50P1,2V+7") .map(\.orientation) == [.vertical, .horizontal, .vertical])
        #expect(ODPSettings.guides(snapLines: "V100Hx").count == 1)
        #expect(ODPSettings.guides(snapLines: "").isEmpty)
    }
}
