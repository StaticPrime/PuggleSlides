import Foundation
import Testing
@testable import PuggleSlidesKit

/// Builds .pptx packages by hand from XML strings, laid out like PowerPoint's and other apps' files.
struct PPTXTestPackage {
    enum Flavor {
        case transitional, strict

        var presentationML: String {
            self == .strict ? "http://purl.oclc.org/ooxml/presentationml/main" : "http://schemas.openxmlformats.org/presentationml/2006/main"
        }
        var drawingML: String {
            self == .strict ? "http://purl.oclc.org/ooxml/drawingml/main" : "http://schemas.openxmlformats.org/drawingml/2006/main"
        }
        var relationshipNamespace: String {
            self == .strict ? "http://purl.oclc.org/ooxml/officeDocument/relationships"
                : "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        }
        func relationshipType(_ name: String) -> String {
            if name.contains("://") { return name }
            return relationshipNamespace + "/" + name
        }
    }

    struct Relationship {
        var id: String
        var type: String
        var target: String
        var isExternal = false

        init(_ id: String, _ type: String, _ target: String, external: Bool = false) {
            self.id = id
            self.type = type
            self.target = target
            isExternal = external
        }
    }

    static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    var flavor = Flavor.transitional
    /// Write relationship targets as absolute part names ("/ppt/slides/slide1.xml").
    var absoluteTargets = false
    var slideSize = "<p:sldSz cx=\"9144000\" cy=\"5143500\"/>"
    var defaultTextStyle = ""
    var theme = PPTXTestPackage.theme()
    var masterTree = ""
    var masterBackground = "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"
    var colorMap = PPTXTestPackage.standardColorMap
    var textStyles = ""
    /// Each layout's full XML; "{TREE}" stands for an empty shape tree when given.
    var layouts: [String] = [PPTXTestPackage.layout(type: "blank", name: "Blank", tree: "")]
    var slides: [Slide] = []
    var media: [String: Data] = [:]
    var extraParts: [String: String] = [:]
    var title: String?
    /// `ppt/tableStyles.xml`'s `a:tblStyle` elements; nil leaves the part out.
    var tableStyles: String?
    /// The view properties part's XML ({NS} for the namespaces); nil leaves it out.
    var viewProperties: String?
    /// Markup at the end of the presentation part, such as an extension list.
    var presentationExtensions = ""
    /// More relationships of the presentation part, such as to comment authors.
    var presentationRelationships: [Relationship] = []

    struct Slide {
        var xml: String
        var layout = 0
        var notes: String?
        var relationships: [Relationship] = []
    }

    static let standardColorMap = "bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" "
        + "accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\""

    func namespaces() -> String {
        "xmlns:a=\"\(flavor.drawingML)\" xmlns:r=\"\(flavor.relationshipNamespace)\" xmlns:p=\"\(flavor.presentationML)\""
    }

    static func shapeTree(_ content: String) -> String {
        "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\(content)</p:spTree>"
    }

    static func layout(type: String?, name: String, tree: String, attributes: String = "", background: String = "", colorMapOverride: String = "") -> String {
        let typeAttribute = type.map { " type=\"\($0)\"" } ?? ""
        return "<p:sldLayout {NS}\(typeAttribute) preserve=\"1\"\(attributes)><p:cSld name=\"\(name)\">\(background)\(shapeTree(tree))</p:cSld>"
            + (colorMapOverride.isEmpty ? "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>" : colorMapOverride) + "</p:sldLayout>"
    }

    static func slide(_ tree: String, attributes: String = "", background: String = "", after: String = "") -> String {
        "<p:sld {NS}\(attributes)><p:cSld>\(background)\(shapeTree(tree))</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>\(after)</p:sld>"
    }

    static func notes(_ body: String) -> String {
        "<p:notes {NS}><p:cSld>" + shapeTree(
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>"
                + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr>"
                + "<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(body)</p:txBody></p:sp>") + "</p:cSld></p:notes>"
    }

    /// A theme part with Office-like colors, Calibri fonts and the 2007 format scheme.
    static func theme(name: String = "Office Theme", colors: String? = nil, major: String = "Calibri Light", minor: String = "Calibri") -> String {
        let scheme = colors ?? "<a:dk1><a:sysClr val=\"windowText\" lastClr=\"000000\"/></a:dk1><a:lt1><a:sysClr val=\"window\" lastClr=\"FFFFFF\"/></a:lt1>"
            + "<a:dk2><a:srgbClr val=\"44546A\"/></a:dk2><a:lt2><a:srgbClr val=\"E7E6E6\"/></a:lt2><a:accent1><a:srgbClr val=\"4472C4\"/></a:accent1>"
            + "<a:accent2><a:srgbClr val=\"ED7D31\"/></a:accent2><a:accent3><a:srgbClr val=\"A5A5A5\"/></a:accent3><a:accent4><a:srgbClr val=\"FFC000\"/></a:accent4>"
            + "<a:accent5><a:srgbClr val=\"5B9BD5\"/></a:accent5><a:accent6><a:srgbClr val=\"70AD47\"/></a:accent6><a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink>"
            + "<a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink>"
        return "<a:theme xmlns:a=\"{A}\" name=\"\(name)\"><a:themeElements><a:clrScheme name=\"Office\">\(scheme)</a:clrScheme>"
            + "<a:fontScheme name=\"Office\"><a:majorFont><a:latin typeface=\"\(major)\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont>"
            + "<a:minorFont><a:latin typeface=\"\(minor)\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"Office\"><a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:schemeClr val=\"phClr\"><a:tint val=\"50000\"/></a:schemeClr></a:gs>"
            + "<a:gs pos=\"100000\"><a:schemeClr val=\"phClr\"><a:tint val=\"15000\"/></a:schemeClr></a:gs></a:gsLst><a:lin ang=\"16200000\" scaled=\"1\"/></a:gradFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"><a:shade val=\"50000\"/></a:schemeClr></a:solidFill></a:fillStyleLst>"
            + "<a:lnStyleLst><a:ln w=\"9525\"><a:solidFill><a:schemeClr val=\"phClr\"><a:shade val=\"95000\"/></a:schemeClr></a:solidFill>"
            + "<a:prstDash val=\"solid\"/></a:ln><a:ln w=\"25400\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
            + "<a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>"
            + "<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"><a:tint val=\"95000\"/></a:schemeClr></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"><a:shade val=\"20000\"/></a:schemeClr></a:solidFill></a:bgFillStyleLst></a:fmtScheme>"
            + "</a:themeElements></a:theme>"
    }

    func expanded(_ xml: String) -> String {
        PPTXTestPackage.declaration + xml.replacingOccurrences(of: "{NS}", with: namespaces()).replacingOccurrences(of: "{A}", with: flavor.drawingML)
    }

    func target(_ path: String, from part: String) -> String {
        absoluteTargets ? "/" + path : PPTXPackage.relativeTarget(from: part, to: path)
    }

    func relationshipsPart(_ items: [Relationship]) -> Data {
        var text = PPTXTestPackage.declaration + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for item in items {
            text += "<Relationship Id=\"\(item.id)\" Type=\"\(flavor.relationshipType(item.type))\" Target=\"\(item.target)\""
                + (item.isExternal ? " TargetMode=\"External\"" : "") + "/>"
        }
        return Data((text + "</Relationships>").utf8)
    }

    func data() throws -> Data {
        var parts: [String: Data] = [:]
        var overrides: [(String, String)] = []
        let prefix = "application/vnd.openxmlformats-officedocument.presentationml."
        func add(_ path: String, _ xml: String, type: String?) {
            parts[path] = Data(expanded(xml).utf8)
            if let type { overrides.append(("/" + path, type)) }
        }
        add("ppt/theme/theme1.xml", theme, type: "application/vnd.openxmlformats-officedocument.theme+xml")
        let masterPath = "ppt/slideMasters/slideMaster1.xml"
        var masterRelationships: [Relationship] = []
        var layoutList = ""
        for (index, layout) in layouts.enumerated() {
            let path = "ppt/slideLayouts/slideLayout\(index + 1).xml"
            add(path, layout, type: prefix + "slideLayout+xml")
            parts[PPTXPackage.relationshipsPath(for: path)] = relationshipsPart([Relationship("rId1", "slideMaster", target(masterPath, from: path))])
            masterRelationships.append(Relationship("rId\(index + 1)", "slideLayout", target(path, from: masterPath)))
            layoutList += "<p:sldLayoutId id=\"\(2_147_483_649 + index)\" r:id=\"rId\(index + 1)\"/>"
        }
        masterRelationships.append(Relationship("rId100", "theme", target("ppt/theme/theme1.xml", from: masterPath)))
        let styles = textStyles.isEmpty ? "" : "<p:txStyles>\(textStyles)</p:txStyles>"
        add(masterPath, "<p:sldMaster {NS}><p:cSld>\(masterBackground)\(PPTXTestPackage.shapeTree(masterTree))</p:cSld><p:clrMap \(colorMap)/>"
            + "<p:sldLayoutIdLst>\(layoutList)</p:sldLayoutIdLst>\(styles)</p:sldMaster>", type: prefix + "slideMaster+xml")
        parts[PPTXPackage.relationshipsPath(for: masterPath)] = relationshipsPart(masterRelationships)

        var presentationRelationships = [Relationship("rId1", "slideMaster", target(masterPath, from: "ppt/presentation.xml"))]
        var slideList = ""
        for (index, slide) in slides.enumerated() {
            let path = "ppt/slides/slide\(index + 1).xml"
            add(path, slide.xml, type: prefix + "slide+xml")
            var relationships = [Relationship("rId1", "slideLayout", target("ppt/slideLayouts/slideLayout\(slide.layout + 1).xml", from: path))]
            if let notes = slide.notes {
                let notesPath = "ppt/notesSlides/notesSlide\(index + 1).xml"
                add(notesPath, notes, type: prefix + "notesSlide+xml")
                parts[PPTXPackage.relationshipsPath(for: notesPath)] = relationshipsPart([Relationship("rId1", "slide", target(path, from: notesPath))])
                relationships.append(Relationship("rId2", "notesSlide", target(notesPath, from: path)))
            }
            relationships += slide.relationships
            parts[PPTXPackage.relationshipsPath(for: path)] = relationshipsPart(relationships)
            presentationRelationships.append(Relationship("rId\(10 + index)", "slide", target(path, from: "ppt/presentation.xml")))
            slideList += "<p:sldId id=\"\(256 + index)\" r:id=\"rId\(10 + index)\"/>"
        }
        let slideIDs = slideList.isEmpty ? "" : "<p:sldIdLst>\(slideList)</p:sldIdLst>"
        let defaults = defaultTextStyle.isEmpty ? "" : "<p:defaultTextStyle>\(defaultTextStyle)</p:defaultTextStyle>"
        add("ppt/presentation.xml", "<p:presentation {NS}><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>"
            + "\(slideIDs)\(slideSize)<p:notesSz cx=\"6858000\" cy=\"9144000\"/>\(defaults)\(presentationExtensions)</p:presentation>",
            type: prefix + "presentation.main+xml")
        if let tableStyles {
            add("ppt/tableStyles.xml", "<a:tblStyleLst xmlns:a=\"{A}\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\">\(tableStyles)</a:tblStyleLst>",
                type: prefix + "tableStyles+xml")
            presentationRelationships.append(Relationship("rId98", "tableStyles", target("ppt/tableStyles.xml", from: "ppt/presentation.xml")))
        }
        if let viewProperties {
            add("ppt/viewProps.xml", viewProperties, type: prefix + "viewProps+xml")
            presentationRelationships.append(Relationship("rId97", "viewProps", target("ppt/viewProps.xml", from: "ppt/presentation.xml")))
        }
        parts["ppt/_rels/presentation.xml.rels"] = relationshipsPart(presentationRelationships + self.presentationRelationships)

        var rootRelationships = [Relationship("rId1", "officeDocument", absoluteTargets ? "/ppt/presentation.xml" : "ppt/presentation.xml")]
        if let title {
            parts["docProps/core.xml"] = Data((PPTXTestPackage.declaration + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
                + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(title)</dc:title></cp:coreProperties>").utf8)
            rootRelationships.append(Relationship("rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml"))
        }
        parts["_rels/.rels"] = relationshipsPart(rootRelationships)
        for (path, xml) in extraParts { parts[path] = Data(expanded(xml).utf8) }
        for (path, data) in media { parts[path] = data }
        var types = PPTXTestPackage.declaration + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/>"
        for (part, type) in overrides { types += "<Override PartName=\"\(part)\" ContentType=\"\(type)\"/>" }
        parts["[Content_Types].xml"] = Data((types + "</Types>").utf8)
        return try PPTXTestPackage.zip(parts)
    }

    static func zip(_ parts: [String: Data]) throws -> Data {
        var writer = ZipWriter(date: Date(timeIntervalSince1970: 1_700_000_000))
        for path in parts.keys.sorted(by: { ($0 == "[Content_Types].xml" ? "" : $0) < ($1 == "[Content_Types].xml" ? "" : $1) }) {
            try writer.add(path, parts[path]!)
        }
        return try writer.finish()
    }

    /// The text of one part of a package.
    static func part(_ path: String, of package: Data) throws -> String? {
        try ZipReader(data: package).read(path).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Every part of a package.
    static func parts(of package: Data) throws -> [String: Data] {
        let reader = try ZipReader(data: package)
        var result: [String: Data] = [:]
        for entry in reader.entries { result[entry.path] = try reader.read(entry) }
        return result
    }

    static func read(_ data: Data) throws -> PresentationFile {
        try PresentationIO.read(data, format: .pptx)
    }

    /// A graphic frame as PowerPoint writes one, holding `content` (a table, a chart reference …).
    static func graphicFrame(_ id: Int, _ name: String, x: Int = 0, y: Int = 0, cx: Int = 3_048_000, cy: Int = 1_524_000, uri: String,
                             content: String) -> String {
        "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>"
            + "<p:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></p:xfrm><a:graphic><a:graphicData uri=\"\(uri)\">"
            + "\(content)</a:graphicData></a:graphic></p:graphicFrame>"
    }

    static let tableURI = "http://schemas.openxmlformats.org/drawingml/2006/table"
    static let chartURI = "http://schemas.openxmlformats.org/drawingml/2006/chart"

    /// A chart's graphic frame, referring to the chart part by `relationship`.
    static func chartFrame(_ id: Int, _ name: String, relationship: String) -> String {
        graphicFrame(id, name, uri: chartURI, content: "<c:chart xmlns:c=\"\(chartURI)\" r:id=\"\(relationship)\"/>")
    }

    /// A chart part's XML around a plot area and whatever follows it in `c:chart`.
    static func chartSpace(_ plotArea: String, chart: String = "", after: String = "") -> String {
        "<c:chartSpace xmlns:c=\"\(chartURI)\" xmlns:a=\"{A}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
            + "<c:chart>\(chart)<c:plotArea><c:layout/>\(plotArea)</c:plotArea></c:chart>\(after)</c:chartSpace>"
    }

    /// The text of the parts of a package written for `presentation`.
    static func writtenParts(_ presentation: Presentation) throws -> [String: String] {
        try parts(of: try PresentationIO.write(presentation, format: .pptx)).mapValues { String(decoding: $0, as: UTF8.self) }
    }
}

/// Deterministic pseudo-random numbers for tests.
struct PPTXTestRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }

    mutating func below(_ bound: Int) -> Int {
        bound <= 0 ? 0 : Int(next() % UInt64(bound))
    }
}

/// Small images, made without image frameworks: PNGs with stored (uncompressed) deflate blocks.
enum PPTXTestImage {
    static func png(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typeBytes = Array(type.utf8)
            let crc = CRC32.checksum(Data(typeBytes + body))
            return bigEndian(UInt32(body.count)) + typeBytes + body + bigEndian(crc)
        }
        func bigEndian(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        var raw: [UInt8] = []
        for y in 0..<height {
            raw.append(0)
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                raw += [r, g, b]
            }
        }
        var zlib: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let length = min(65_535, raw.count - offset)
            let final: UInt8 = offset + length >= raw.count ? 1 : 0
            zlib += [final, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)]
            zlib += raw[offset..<(offset + length)]
            offset += length
        } while offset < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        zlib += bigEndian((b << 16) | a)
        var data: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        data += chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 2, 0, 0, 0])
        data += chunk("IDAT", zlib)
        data += chunk("IEND", [])
        return Data(data)
    }

    /// A diagonal two-color gradient.
    static func gradient(_ size: Int = 48, from: (Double, Double, Double), to: (Double, Double, Double)) -> Data {
        png(width: size, height: size) { x, y in
            let t = Double(x + y) / Double(2 * max(size - 1, 1))
            func channel(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, (a + (b - a) * t) * 255))) }
            return (channel(from.0, to.0), channel(from.1, to.1), channel(from.2, to.2))
        }
    }
}

/// Presentations with their ids made comparable: ids that can't survive a file (themes, layouts, slides,
/// elements, media, guides) are renumbered in reading order, frames are snapped to whole EMU (all a file can store),
/// custom paths are measured as fractions of their space (files keep them in the shape's EMU space), and
/// adjust values equal to a preset's defaults are dropped (files leave those out). Tables, charts, word art and
/// picture adjustments are brought to what a file keeps of them (see `table`, `chart`, `wordArt` and `adjustments`).
enum PPTXCanonical {
    static func snapped(_ points: Double) -> Double {
        (points * EMU.perPoint).rounded() / EMU.perPoint
    }

    /// Fractions as files store them: in thousandths of a percent.
    static func percent(_ value: Double) -> Double {
        (value * 100_000).rounded() / 100_000
    }

    static func insets(_ insets: TextInsets) -> TextInsets {
        TextInsets(left: snapped(insets.left), top: snapped(insets.top), right: snapped(insets.right), bottom: snapped(insets.bottom))
    }

    /// A border as a file keeps it: none when it doesn't show, at a whole EMU width, without line ends.
    static func border(_ outline: Outline?) -> Outline? {
        guard var outline, outline.isVisible, outline.fill.mediaID == nil else { return nil }
        outline.width = snapped(outline.width)
        outline.head = .none
        outline.tail = .none
        return outline
    }

    /// A table with its grids in step, sizes at whole EMU and borders as files keep them.
    static func table(_ table: Table, text: (TextBody) -> TextBody, fill: (Fill?) -> Fill?) -> Table {
        var table = table
        table.normalize()
        table.columnWidths = table.columnWidths.map(snapped)
        table.rowHeights = table.rowHeights.map(snapped)
        for row in table.cells.indices {
            for column in table.cells[row].indices {
                var cell = table.cells[row][column]
                cell.text = text(cell.text)
                cell.fill = fill(cell.fill) ?? cell.fill
                cell.insets = insets(cell.insets)
                table.cells[row][column] = cell
            }
        }
        table.horizontalBorders = table.horizontalBorders.map { $0.map(border) }
        table.verticalBorders = table.verticalBorders.map { $0.map(border) }
        return table
    }

    /// A chart as its part keeps it: series as long as the labels, palette colors automatic, a doughnut's hole in
    /// whole percents, and nothing a kind doesn't draw (axes of pies, holes of other kinds).
    static func chart(_ chart: Chart) -> Chart {
        var chart = chart
        chart.data = chart.data.padded()
        for index in chart.data.series.indices where chart.data.series[index].color == Chart.palette[index % Chart.palette.count] {
            chart.data.series[index].color = nil
        }
        chart.pieHole = chart.kind == .donut ? min(max((chart.pieHole * 100).rounded() / 100, 0.1), 0.9) : 0.5
        if chart.backgroundColor == .white { chart.backgroundColor = nil }
        if chart.fontFamily?.isEmpty == true { chart.fontFamily = nil }
        chart.title = chart.title.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if chart.kind.isPie {
            chart.horizontalAxisTitle = ""
            chart.verticalAxisTitle = ""
            chart.verticalMinimum = nil
            chart.verticalMaximum = nil
            chart.showsGridlines = true
        }
        return chart
    }

    /// Word art's letters are painted with the shape's fill, so the runs' own colors aren't kept, and its lines
    /// never wrap.
    static func wordArt(_ shape: Shape) -> Shape {
        guard shape.isWordArt, var text = shape.text else { return shape }
        var shape = shape
        text.properties.wraps = false
        text.paragraphs = text.paragraphs.map { paragraph in
            var paragraph = paragraph
            paragraph.runs = PPTXTextReader.merged(paragraph.runs.map { run in
                var run = run
                run.style.color = nil
                return run
            })
            paragraph.endStyle.color = nil
            return paragraph
        }
        shape.text = text
        return shape
    }

    /// Adjustments in thousandths of a percent, and duotones that are one of the recolors named as such.
    static func adjustments(_ adjustments: ImageAdjustments) -> ImageAdjustments {
        var adjustments = adjustments
        adjustments.transparency = percent(adjustments.transparency)
        adjustments.brightness = percent(adjustments.brightness)
        adjustments.contrast = percent(adjustments.contrast)
        if case .duotone(let dark, let light)? = adjustments.recolor { adjustments.recolor = PPTXPictureEffects.recolor(dark: dark, light: light) }
        return adjustments
    }

    static func geometry(_ geometry: ShapeGeometry, frame: SlideSize?) -> ShapeGeometry {
        switch geometry {
        case .preset(let name, let adjustments):
            let defaults = PPTXGeometry.defaultAdjustments[name] ?? [:]
            return .preset(name, adjustments: adjustments.filter { defaults[$0.key] != $0.value.rounded() })
        case .custom(var custom):
            custom.paths = custom.paths.map { path in
                let width = path.width > 0 ? path.width : (frame?.width ?? 0)
                let height = path.height > 0 ? path.height : (frame?.height ?? 0)
                func unit(_ value: Double, _ size: Double) -> Double { size > 0 ? (value / size * 1e6).rounded() / 1e6 : value }
                func point(_ point: SlidePoint) -> SlidePoint { SlidePoint(x: unit(point.x, width), y: unit(point.y, height)) }
                let commands: [PathCommand] = path.commands.map { command in
                    switch command {
                    case .move(let target): .move(point(target))
                    case .line(let target): .line(point(target))
                    case .quadratic(let control, let end): .quadratic(control: point(control), end: point(end))
                    case .cubic(let control1, let control2, let end): .cubic(control1: point(control1), control2: point(control2), end: point(end))
                    case .arc(let widthRadius, let heightRadius, let start, let sweep):
                        .arc(widthRadius: unit(widthRadius, width), heightRadius: unit(heightRadius, height), startAngle: start, sweepAngle: sweep)
                    case .close: .close
                    }
                }
                return CustomPath(width: 1, height: 1, fill: path.fill, stroke: path.stroke, commands: commands)
            }
            return .custom(custom)
        }
    }
    static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
    }

    static func canonical(_ presentation: Presentation) -> Presentation {
        var source = presentation
        source.removeUnusedMedia()
        var layoutIDs: [UUID: UUID] = [:], slideIDs: [UUID: UUID] = [:], mediaIDs: [MediaID: MediaID] = [:]
        var elementNumber = 100_000
        for theme in source.themes {
            for layout in theme.layouts { layoutIDs[layout.id] = uuid(1_000 + layoutIDs.count) }
        }
        for slide in source.slides { slideIDs[slide.id] = uuid(10_000 + slideIDs.count) }

        func media(_ id: MediaID) -> MediaID {
            if let known = mediaIDs[id] { return known }
            let new = "media-\(mediaIDs.count + 1)"
            mediaIDs[id] = new
            return new
        }
        func fill(_ fill: Fill?) -> Fill? {
            guard case .picture(var picture)? = fill else { return fill }
            picture.mediaID = media(picture.mediaID)
            return .picture(picture)
        }
        func character(_ style: CharacterStyle) -> CharacterStyle {
            var style = style
            if case .slide(let id)? = style.link { style.link = .slide(slideIDs[id] ?? id) }
            return style
        }
        func text(_ body: TextBody) -> TextBody {
            var body = body
            body.paragraphs = body.paragraphs.map { paragraph in
                var paragraph = paragraph
                paragraph.runs = paragraph.runs.map { run in
                    var run = run
                    run.style = character(run.style)
                    // A slide number's text is whatever was shown last; slides save their own number.
                    if run.field == .slideNumber { run.text = "‹#›" }
                    return run
                }
                paragraph.endStyle = character(paragraph.endStyle)
                return paragraph
            }
            var levels: [Int: LevelStyle] = [:]
            for (level, style) in body.listStyle.levels {
                levels[level] = LevelStyle(paragraph: style.paragraph, character: character(style.character))
            }
            body.listStyle = ListStyle(levels: levels)
            return body
        }
        /// Old element ids to new, for animations and comments.
        var elementIDs: [UUID: UUID] = [:]
        /// Comments as files keep them: without ids, edit dates or anchors to elements that are gone, dated to the
        /// second, placed to the hundredth of a point.
        var commentNumber = 600_000
        func comments(_ thread: CommentThread) -> CommentThread {
            var thread = thread
            thread.id = uuid(commentNumber)
            commentNumber += 1
            thread.elementID = thread.elementID.flatMap { elementIDs[$0] }
            thread.position = SlidePoint(x: (thread.position.x * 100).rounded() / 100, y: (thread.position.y * 100).rounded() / 100)
            thread.comments = thread.comments.map { comment in
                var comment = comment
                comment.id = uuid(commentNumber)
                commentNumber += 1
                comment.date = Date(timeIntervalSince1970: comment.date.timeIntervalSince1970.rounded(.down))
                comment.editedDate = nil
                comment.text = comment.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                return comment
            }
            return thread
        }
        func convert(_ element: SlideElement) -> SlideElement {
            var element = element
            let new = uuid(elementNumber)
            elementIDs[element.id] = new
            element.id = new
            elementNumber += 1
            if var placement = element.placement {
                let frame = placement.frame
                placement.frame = SlideRect(x: snapped(frame.x), y: snapped(frame.y), width: snapped(frame.width), height: snapped(frame.height))
                element.placement = placement
            }
            switch element.content {
            case .shape(var shape):
                shape.geometry = geometry(shape.geometry, frame: element.placement?.frame.size)
                shape.fill = fill(shape.fill)
                if var outline = shape.outline {
                    outline.fill = fill(outline.fill) ?? outline.fill
                    shape.outline = outline
                }
                shape.text = shape.text.map(text)
                element.content = .shape(wordArt(shape))
            case .picture(var picture):
                picture.mediaID = media(picture.mediaID)
                picture.geometry = geometry(picture.geometry, frame: element.placement?.frame.size)
                picture.adjustments = adjustments(picture.adjustments)
                element.content = .picture(picture)
            case .group(let children):
                element.content = .group(children.map(convert))
            case .table(let table):
                element.content = .table(Self.table(table, text: text, fill: fill))
            case .chart(let chart):
                element.content = .chart(Self.chart(chart))
            case .media(let clip):
                element.content = .media(Self.clip(clip, media: media))
            }
            return element
        }

        var result = source
        result.themes = source.themes.enumerated().map { index, theme in
            var theme = theme
            theme.id = uuid(index + 1)
            theme.background = fill(theme.background) ?? theme.background
            theme.elements = theme.elements.map(convert)
            theme.layouts = theme.layouts.map { layout in
                var layout = layout
                layout.id = layoutIDs[layout.id]!
                layout.background = fill(layout.background)
                layout.elements = layout.elements.map(convert)
                return layout
            }
            return theme
        }
        result.slides = source.slides.map { slide in
            var slide = slide
            slide.id = slideIDs[slide.id]!
            slide.layoutID = layoutIDs[slide.layoutID] ?? slide.layoutID
            slide.background = fill(slide.background)
            slide.elements = slide.elements.map(convert)
            slide.notes = text(slide.notes)
            // Animations follow their elements; instant effects have no duration a file can keep.
            slide.animations = slide.animations.map { animation in
                var animation = animation
                animation.id = uuid(900_000 + elementNumber)
                elementNumber += 1
                animation.elementID = elementIDs[animation.elementID] ?? animation.elementID
                if animation.effect.isInstant { animation.duration = SlideAnimation(elementID: animation.elementID).duration }
                return animation
            }
            slide.comments = slide.comments.map(comments)
            return slide
        }
        result.media = [:]
        for (old, new) in mediaIDs {
            guard var item = source.media[old] else { continue }
            // Movies and sounds are typed by their extension, as files type them.
            if item.isVideo || item.isAudio { item.contentType = PPTXMedia.contentType(forExtension: item.fileExtension) ?? item.contentType }
            result.media[new] = item
        }
        // Guides keep no id in a file, and their positions are in eighths of a point.
        result.guides = source.guides.enumerated().map { index, guide in
            Guide(id: uuid(800_000 + index), orientation: guide.orientation, position: (guide.position * 8).rounded() / 8, color: guide.color)
        }
        return result
    }

    /// A clip as files keep it: its media renamed, its trim to the millisecond (a start of zero is none), its volume to a
    /// ten-thousandth, and a video stopping on slide change, as videos do.
    static func clip(_ clip: MediaClip, media: (MediaID) -> MediaID) -> MediaClip {
        var clip = clip
        clip.mediaID = media(clip.mediaID)
        clip.posterID = clip.posterID.map(media)
        func milliseconds(_ seconds: Double?) -> Double? { seconds.flatMap { $0 > 0.0005 ? ($0 * 1000).rounded() / 1000 : nil } }
        clip.start = milliseconds(clip.start)
        clip.end = milliseconds(clip.end)
        clip.volume = (min(max(clip.volume, 0), 1) * 10_000).rounded() / 10_000
        if clip.kind == .video { clip.stopsOnSlideChange = true }
        return clip
    }

    /// Where two presentations first differ, for readable failures; nil when they're equal.
    static func difference(_ a: Presentation, _ b: Presentation) -> String? {
        let a = canonical(a), b = canonical(b)
        if a == b { return nil }
        func describe<T>(_ label: String, _ x: T, _ y: T) -> String { "\(label):\n  \(x)\n  \(y)" }
        if a.slideSize != b.slideSize { return describe("slide size", a.slideSize, b.slideSize) }
        if a.title != b.title { return describe("title", a.title as Any, b.title as Any) }
        if a.defaultTextStyle != b.defaultTextStyle { return describe("default text style", a.defaultTextStyle, b.defaultTextStyle) }
        if a.media != b.media { return describe("media", a.media.mapValues(\.contentType), b.media.mapValues(\.contentType)) }
        if a.guides != b.guides { return describe("guides", a.guides, b.guides) }
        if a.themes.count != b.themes.count { return describe("theme count", a.themes.count, b.themes.count) }
        for (x, y) in zip(a.themes, b.themes) where x != y {
            let label = "theme \(x.name)"
            if x.name != y.name { return describe(label + " name", x.name, y.name) }
            if x.colors != y.colors { return describe(label + " colors", x.colors, y.colors) }
            if x.fonts != y.fonts { return describe(label + " fonts", x.fonts, y.fonts) }
            if x.background != y.background { return describe(label + " background", x.background, y.background) }
            if x.titleStyle != y.titleStyle { return describe(label + " title style", x.titleStyle, y.titleStyle) }
            if x.bodyStyle != y.bodyStyle { return describe(label + " body style", x.bodyStyle, y.bodyStyle) }
            if x.otherStyle != y.otherStyle { return describe(label + " other style", x.otherStyle, y.otherStyle) }
            if let found = elements(label, x.elements, y.elements) { return found }
            if x.layouts.count != y.layouts.count { return describe(label + " layout count", x.layouts.count, y.layouts.count) }
            for (p, q) in zip(x.layouts, y.layouts) where p != q {
                let label = label + " layout \(p.name)"
                if p.name != q.name || p.kind != q.kind { return describe(label + " name/kind", "\(p.name) \(p.kind)", "\(q.name) \(q.kind)") }
                if p.background != q.background { return describe(label + " background", p.background as Any, q.background as Any) }
                if p.showsThemeElements != q.showsThemeElements { return describe(label + " shows theme", p.showsThemeElements, q.showsThemeElements) }
                if let found = elements(label, p.elements, q.elements) { return found }
            }
        }
        if a.slides.count != b.slides.count { return describe("slide count", a.slides.count, b.slides.count) }
        for (index, (x, y)) in zip(a.slides, b.slides).enumerated() where x != y {
            let label = "slide \(index + 1)"
            if x.layoutID != y.layoutID { return describe(label + " layout", x.layoutID, y.layoutID) }
            if x.background != y.background { return describe(label + " background", x.background as Any, y.background as Any) }
            if x.isSkipped != y.isSkipped { return describe(label + " skipped", x.isSkipped, y.isSkipped) }
            if x.notes != y.notes { return describe(label + " notes", x.notes, y.notes) }
            if x.transition != y.transition { return describe(label + " transition", x.transition as Any, y.transition as Any) }
            if x.animations.count != y.animations.count { return describe(label + " animation count", x.animations.count, y.animations.count) }
            for (number, (a, b)) in zip(x.animations, y.animations).enumerated() where a != b {
                return describe(label + " animation \(number)", a, b)
            }
            if let found = elements(label, x.elements, y.elements) { return found }
            if x.comments.count != y.comments.count { return describe(label + " comment thread count", x.comments.count, y.comments.count) }
            for (number, (a, b)) in zip(x.comments, y.comments).enumerated() where a != b {
                return describe(label + " comment thread \(number + 1)", a, b)
            }
        }
        return "differs somewhere"
    }

    private static func elements(_ label: String, _ x: [SlideElement], _ y: [SlideElement]) -> String? {
        func describe<T>(_ label: String, _ x: T, _ y: T) -> String { "\(label):\n  \(x)\n  \(y)" }
        if x.count != y.count { return describe(label + " element count", x.map(\.name), y.map(\.name)) }
        for (p, q) in zip(x, y) where p != q {
            let label = label + " element \"\(p.name)\""
            if p.name != q.name { return describe(label + " name", p.name, q.name) }
            if p.placement != q.placement { return describe(label + " placement", p.placement as Any, q.placement as Any) }
            if p.placeholder != q.placeholder { return describe(label + " placeholder", p.placeholder as Any, q.placeholder as Any) }
            if p.altTitle != q.altTitle || p.altDescription != q.altDescription {
                return describe(label + " alt text", "\(p.altTitle ?? "-") \(p.altDescription ?? "-")", "\(q.altTitle ?? "-") \(q.altDescription ?? "-")")
            }
            switch (p.content, q.content) {
            case (.group(let c1), .group(let c2)):
                if let found = elements(label, c1, c2) { return found }
            case (.table(let t1), .table(let t2)):
                if t1.columnWidths != t2.columnWidths || t1.rowHeights != t2.rowHeights {
                    return describe(label + " table size", "\(t1.columnWidths) \(t1.rowHeights)", "\(t2.columnWidths) \(t2.rowHeights)")
                }
                for (r, (row1, row2)) in zip(t1.cells, t2.cells).enumerated() {
                    for (c, (cell1, cell2)) in zip(row1, row2).enumerated() where cell1 != cell2 {
                        return describe(label + " cell \(r),\(c)", cell1, cell2)
                    }
                }
                if t1.horizontalBorders != t2.horizontalBorders { return describe(label + " horizontal borders", t1.horizontalBorders, t2.horizontalBorders) }
                return describe(label + " vertical borders", t1.verticalBorders, t2.verticalBorders)
            case (.chart(let c1), .chart(let c2)):
                if c1.data != c2.data { return describe(label + " chart data", c1.data, c2.data) }
                var x = c1, y = c2
                x.data = ChartData()
                y.data = ChartData()
                return describe(label + " chart", x, y)
            case (.shape(let s1), .shape(let s2)):
                if s1.geometry != s2.geometry { return describe(label + " geometry", s1.geometry, s2.geometry) }
                if s1.fill != s2.fill { return describe(label + " fill", s1.fill as Any, s2.fill as Any) }
                if s1.outline != s2.outline { return describe(label + " outline", s1.outline as Any, s2.outline as Any) }
                if s1.isTextBox != s2.isTextBox || s1.isConnector != s2.isConnector || s1.isWordArt != s2.isWordArt { return describe(label + " flags", s1, s2) }
                if let t1 = s1.text, let t2 = s2.text, t1 != t2 {
                    if t1.properties != t2.properties { return describe(label + " body properties", t1.properties, t2.properties) }
                    if t1.listStyle != t2.listStyle { return describe(label + " list style", t1.listStyle, t2.listStyle) }
                    for (i, (a, b)) in zip(t1.paragraphs, t2.paragraphs).enumerated() where a != b {
                        return describe(label + " paragraph \(i)", a, b)
                    }
                    return describe(label + " paragraph count", t1.paragraphs.count, t2.paragraphs.count)
                }
                return describe(label + " text", s1.text as Any, s2.text as Any)
            default:
                return describe(label + " content", p.content, q.content)
            }
        }
        return nil
    }
}
