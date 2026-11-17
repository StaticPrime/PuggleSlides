import CoreGraphics
import Foundation
import Testing
@testable import PuggleSlidesKit

/// What an SVG holds, read with Foundation's XML parser: its elements, the root's attributes, the text of its
/// `<text>` elements and its ids.
private final class SVGReader: NSObject, XMLParserDelegate {
    var elements: [String] = []
    var rootAttributes: [String: String] = [:]
    var texts: [String] = []
    var ids: [String] = []
    var clipReferences: [String] = []
    private var text: String?

    /// Nil when `markup` isn't well-formed XML.
    static func read(_ markup: String) -> SVGReader? {
        let reader = SVGReader()
        let parser = XMLParser(data: Data(markup.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        return parser.parse() ? reader : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elements.isEmpty { rootAttributes = attributeDict }
        elements.append(elementName)
        if let id = attributeDict["id"] { ids.append(id) }
        if let clip = attributeDict["clip-path"] { clipReferences.append(clip) }
        if elementName == "text" { text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text?.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "text", let text {
            texts.append(text)
            self.text = nil
        }
    }
}

/// SVG output: well-formed for every chart, sized in points, with real text, escaped markup and clip ids that
/// survive several charts in one document.
@Suite struct ChartSVGTests {
    private static var busy: Chart {
        Chart(kind: .column, data: ChartFixtures.sales, title: "Sales by month", horizontalAxisTitle: "Month", verticalAxisTitle: "Amount",
              showsDataLabels: true)
    }

    @Test(arguments: ChartKind.allCases)
    func everyKindIsWellFormed(kind: ChartKind) throws {
        var busy = Self.busy
        busy.kind = kind
        var pinned = busy
        pinned.verticalMinimum = 100
        pinned.verticalMaximum = 200
        let charts = [Chart.sample(kind), busy, pinned, Chart(kind: kind, data: ChartData(), title: "Empty"),
                      Chart(kind: kind, data: ChartFixtures.wave(500), legend: .bottom)]
        for chart in charts {
            for size in [ChartFixtures.size, ChartFixtures.small, CGSize(width: 1, height: 1), .zero, CGSize(width: 333.25, height: 187.5)] {
                let svg = ChartRenderer.svg(chart, size: size)
                let reader = try #require(SVGReader.read(svg), "\(kind) at \(size) isn't well-formed")
                #expect(reader.elements.first == "svg")
                #expect(reader.rootAttributes["width"] == ChartScene.number(Double(size.width)))
                #expect(reader.rootAttributes["height"] == ChartScene.number(Double(size.height)))
                #expect(reader.rootAttributes["xmlns"] == "http://www.w3.org/2000/svg")
                // Every clip a group uses is defined.
                #expect(reader.clipReferences.allSatisfy { reference in reader.ids.contains { reference == "url(#\($0))" } })
                if size.width >= 100 {
                    #expect(reader.texts.count == ChartFixtures.texts(chart, size: size).count, "\(kind)")
                }
            }
        }
    }

    @Test func holdsTheTitleLabelsAndLegend() throws {
        let reader = try #require(SVGReader.read(ChartRenderer.svg(Self.busy, size: ChartFixtures.size)))
        for text in ["Sales by month", "Jan", "Dec", "Sales", "Costs", "Profit", "Month", "Amount", "230", "0", "250"] {
            #expect(reader.texts.contains(text), "\(text)")
        }
        let pie = try #require(SVGReader.read(ChartRenderer.svg(Chart.sample(.pie), size: ChartFixtures.size)))
        #expect(["Series 1", "Item 1", "Item 4", "40%", "15%"].allSatisfy(pie.texts.contains))
        let svg = ChartRenderer.svg(Self.busy, size: ChartFixtures.size)
        // Vertical axis titles turn to read upward; columns fill in the palette's colors.
        #expect(svg.contains(">Amount</text>") && svg.contains("rotate(-90"))
        #expect(svg.contains("fill=\"#4285F4\"") && svg.contains("fill=\"#EA4335\"") && svg.contains("fill=\"#FBBC04\""))
    }

    @Test func escapesMarkupAndDropsControlCharacters() throws {
        let title = "Sales & <Costs> \"2026\" 'Q1'\u{7}\u{1B}\u{FFFF}"
        let data = ChartData(labels: ["A&B", "<i>", "\"quoted\""], series: [ChartSeries(name: "</text><script>", values: [1, 2, 3]),
                                                                            ChartSeries(name: "x]]>y", values: [3, 2, 1])])
        for kind in [ChartKind.column, .pie, .bar] {
            let svg = ChartRenderer.svg(Chart(kind: kind, data: data, title: title), size: ChartFixtures.size)
            let reader = try #require(SVGReader.read(svg), "\(kind)")
            #expect(svg.contains(">Sales &amp; &lt;Costs&gt; &quot;2026&quot; 'Q1'</text>"))
            #expect(reader.texts.contains("Sales & <Costs> \"2026\" 'Q1'"))
            #expect(reader.texts.contains("A&B") && reader.texts.contains("<i>"))
            #expect(!svg.contains("<script>") && !svg.contains("<i>"))
        }
    }

    @Test func namesTheFontStack() throws {
        let plain = ChartRenderer.svg(Chart.sample(.column), size: ChartFixtures.size)
        #expect(plain.contains("font-family=\"Roboto, Arial, Helvetica, sans-serif\""))
        var chart = Chart.sample(.column)
        chart.fontFamily = "Times New Roman"
        #expect(ChartRenderer.svg(chart, size: ChartFixtures.size).contains("font-family=\"'Times New Roman', Roboto, Arial, Helvetica, sans-serif\""))
        chart.fontFamily = "Arial"
        #expect(ChartRenderer.svg(chart, size: ChartFixtures.size).contains("font-family=\"Arial, Roboto, Helvetica, sans-serif\""))
        chart.fontFamily = "Odd\"Name&Co"
        #expect(SVGReader.read(ChartRenderer.svg(chart, size: ChartFixtures.size)) != nil)
        // Text sizes are the layout's, in points.
        #expect(plain.contains("font-size=\"9\""))
    }

    @Test func isAnSVGElementSizedInPoints() {
        let svg = ChartRenderer.svg(Chart.sample(.line), size: ChartFixtures.size)
        #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"450\" height=\"278\" viewBox=\"0 0 450 278\">\n"))
        #expect(svg.hasSuffix("</svg>\n") && !svg.contains("<?xml"))
        // The background fills it: white, or the chart's color.
        #expect(svg.contains("<rect x=\"0\" y=\"0\" width=\"450\" height=\"278\" fill=\"#FFFFFF\"/>"))
        var colored = Chart.sample(.line)
        colored.backgroundColor = RGBColor(red: 0xFF, green: 0xF8, blue: 0xE1)
        #expect(ChartRenderer.svg(colored, size: CGSize(width: 300.5, height: 200)).contains("width=\"300.5\" height=\"200\" fill=\"#FFF8E1\""))
        // Sizes that make no sense give an empty picture, not broken markup.
        for size in [CGSize(width: -5, height: 10), CGSize(width: Double.nan, height: Double.infinity)] {
            let odd = ChartRenderer.svg(Chart.sample(.line), size: size)
            #expect(odd.contains("width=\"0\"") && SVGReader.read(odd) != nil)
        }
        #expect(SVGReader.read(ChartRenderer.svg(Chart.sample(.line), size: CGSize(width: 1e9, height: 1e9))) != nil)
    }

    @Test func groupsEmbedAtTheirRect() throws {
        let chart = Self.busy
        let group = ChartRenderer.svgGroup(chart, in: CGRect(x: 10, y: 20.5, width: 450, height: 278))
        #expect(group.hasPrefix("<g transform=\"translate(10 20.5)\">\n") && group.hasSuffix("</g>\n"))
        #expect(try #require(SVGReader.read(group)).elements.first == "g")
        // The same drawing as the standalone element.
        let svg = ChartRenderer.svg(chart, size: ChartFixtures.size)
        let inner = { (markup: String) in markup.split(separator: "\n").dropFirst().dropLast() }
        #expect(Array(inner(group)) == Array(inner(svg)))
    }

    @Test func clipIDsSurviveSeveralChartsInOneDocument() throws {
        func pinned(_ maximum: Double) -> Chart {
            Chart(kind: .line, data: ChartFixtures.sales, verticalMinimum: 50, verticalMaximum: maximum)
        }
        let first = ChartRenderer.svgGroup(pinned(150), in: CGRect(x: 0, y: 0, width: 450, height: 278))
        let second = ChartRenderer.svgGroup(pinned(200), in: CGRect(x: 0, y: 300, width: 450, height: 278))
        let again = ChartRenderer.svgGroup(pinned(150), in: CGRect(x: 0, y: 600, width: 450, height: 278))
        let document = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"450\" height=\"900\">\n" + first + second + "</svg>\n"
        let reader = try #require(SVGReader.read(document))
        // Different charts get different ids; the same chart gets the same one (its clip is the same rectangle).
        #expect(reader.ids.count == 2 && Set(reader.ids).count == 2)
        #expect(reader.clipReferences.allSatisfy { reference in reader.ids.contains { reference == "url(#\($0))" } })
        let id = try #require(SVGReader.read(first)?.ids.first)
        #expect(SVGReader.read(again)?.ids == [id] && id.hasPrefix("chart-clip-"))
        // Unpinned charts need no clips.
        #expect(!ChartRenderer.svg(Chart.sample(.line), size: ChartFixtures.size).contains("clipPath"))
    }
}
