import Foundation
import Testing
@testable import PuggleSlidesKit

/// The structure of written packages: what PowerPoint needs to open them without repairs.
struct PPTXWriteTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func parts(_ presentation: Presentation) throws -> [String: Data] {
        try PPTXTestPackage.parts(of: try PPTXWriter.write(presentation, date: date))
    }

    static func tree(_ data: Data?) throws -> XNode {
        try XMLTree.parse(try #require(data))
    }

    @Test func packageHasEveryPartOfficeExpects() throws {
        let presentation = PPTXSamples.rich()
        let parts = try Self.parts(presentation)
        let expected = ["[Content_Types].xml", "_rels/.rels", "docProps/core.xml", "docProps/app.xml", "ppt/presentation.xml",
                        "ppt/_rels/presentation.xml.rels", "ppt/presProps.xml", "ppt/viewProps.xml", "ppt/tableStyles.xml",
                        "ppt/slideMasters/slideMaster1.xml", "ppt/slideMasters/slideMaster2.xml", "ppt/theme/theme1.xml", "ppt/theme/theme2.xml",
                        "ppt/theme/theme3.xml", "ppt/notesMasters/notesMaster1.xml", "ppt/notesMasters/_rels/notesMaster1.xml.rels",
                        "ppt/slides/slide1.xml", "ppt/slides/slide6.xml", "ppt/slideLayouts/slideLayout23.xml", "ppt/media/image1.png", "ppt/media/image2.png"]
        for path in expected { #expect(parts[path] != nil, "\(path)") }
        #expect(parts["ppt/slideLayouts/slideLayout24.xml"] == nil)
        // Notes slides only for slides with notes: 2, 4 and 5.
        #expect(parts.keys.filter { $0.hasPrefix("ppt/notesSlides/notesSlide") }.count == 3)

        // Every part is well-formed and has a content type.
        let types = try Self.tree(parts["[Content_Types].xml"])
        let defaults = Dictionary(uniqueKeysWithValues: types.children("Default").map { ($0["Extension"]!, $0["ContentType"]!) })
        let overrides = Set(types.children("Override").map { $0["PartName"]! })
        #expect(defaults == ["rels": PPTXContentType.relationships, "xml": PPTXContentType.xml, "png": "image/png", "xlsx": PPTXContentType.workbook])
        for (path, data) in parts where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
            #expect(XMLParser(data: data).parse(), "\(path)")
            if path.hasSuffix(".xml"), path != "[Content_Types].xml" { #expect(overrides.contains("/" + path), "\(path)") }
        }

        // Relationships point at parts that exist, and every id a part uses is one of its relationships.
        for (path, data) in parts where path.hasSuffix(".rels") {
            let source = path == "_rels/.rels" ? "" : path.replacingOccurrences(of: "_rels/", with: "").replacingOccurrences(of: ".rels", with: "")
            let relationships = try PPTXPackage.relationships(data, of: source)
            #expect(Set(relationships.all.map(\.id)).count == relationships.all.count)
            for relationship in relationships.all where !relationship.isExternal {
                #expect(parts[relationship.target] != nil, "\(path) → \(relationship.target)")
            }
            guard let part = parts[source] else { continue }
            let text = String(decoding: part, as: UTF8.self)
            for id in text.matches(of: /r:(?:id|embed|link)="(rId\d+)"/).map({ String($0.1) }) {
                #expect(relationships[id] != nil, "\(source) uses \(id)")
            }
        }
    }

    @Test func idsFollowPowerPointsRules() throws {
        let parts = try Self.parts(PPTXSamples.rich())
        let presentation = try Self.tree(parts["ppt/presentation.xml"])
        let masterCount = presentation.child("sldMasterIdLst")!.children.count
        #expect(presentation.child("sldIdLst")!.children.count == 6)
        #expect(presentation.child("notesMasterIdLst")?.child("notesMasterId") != nil)
        #expect(presentation.child("sldSz")?.attributes == ["cx": "9144000", "cy": "5143500"])
        #expect(presentation.child("notesSz")?.attributes == ["cx": "6858000", "cy": "9144000"])
        // XNode keeps r:id over id, so slide ids are checked in the text.
        let text = String(decoding: parts["ppt/presentation.xml"]!, as: UTF8.self)
        let slideIDs = text.matches(of: /<p:sldId id="(\d+)"/).map { Int($0.1)! }
        #expect(slideIDs == Array(256..<262))
        let declaredMasters = text.matches(of: /<p:sldMasterId id="(\d+)"/).map { Int($0.1)! }
        // The first master's 12 layouts take the ids after it.
        #expect(declaredMasters == [2_147_483_648, 2_147_483_661])
        #expect(masterCount == 2)
        var layoutIDs: [Int] = []
        for number in 1...2 {
            let master = String(decoding: parts["ppt/slideMasters/slideMaster\(number).xml"]!, as: UTF8.self)
            layoutIDs += master.matches(of: /<p:sldLayoutId id="(\d+)"/).map { Int($0.1)! }
        }
        let allIDs = declaredMasters + layoutIDs
        #expect(Set(allIDs).count == allIDs.count)
        #expect(allIDs.allSatisfy { $0 >= 2_147_483_648 })

        // Shape ids are unique within each part and start at 2.
        for (path, data) in parts where path.hasPrefix("ppt/slides/slide") || path.hasPrefix("ppt/slideLayouts/slideLayout")
            || path.hasPrefix("ppt/slideMasters/slideMaster") || path.hasPrefix("ppt/notes") {
            guard path.hasSuffix(".xml") else { continue }
            let ids = try Self.tree(data).descendants("cNvPr").compactMap { Int($0["id"] ?? "") }
            #expect(ids.first == 1, "\(path)")
            #expect(Set(ids).count == ids.count, "\(path)")
            #expect(ids.dropFirst().allSatisfy { $0 >= 2 }, "\(path)")
        }
    }

    @Test func documentPropertiesNameOnlyPuggleSlides() throws {
        let parts = try Self.parts(PPTXSamples.rich())
        let core = String(decoding: parts["docProps/core.xml"]!, as: UTF8.self)
        #expect(core.contains("<dc:title>Quarterly Review &amp; &lt;Plans&gt; \"2026\"</dc:title>"))
        #expect(core.contains("<dc:creator>PuggleSlides</dc:creator>"))
        #expect(core.contains("<cp:lastModifiedBy>PuggleSlides</cp:lastModifiedBy>"))
        #expect(core.contains("2027-01-15T08:00:00Z"))
        let app = String(decoding: parts["docProps/app.xml"]!, as: UTF8.self)
        #expect(app.contains("<Application>PuggleSlides</Application>"))
        #expect(app.contains("<Slides>6</Slides>"))
        #expect(app.contains("<Notes>3</Notes>"))
        #expect(app.contains("<HiddenSlides>1</HiddenSlides>"))
    }

    @Test func slidesStateOnlyWhatTheModelSets() throws {
        let parts = try Self.parts(PPTXSamples.rich())
        let title = String(decoding: parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        // Placeholders that inherit their place have no xfrm and an empty spPr.
        #expect(title.contains("<p:nvPr><p:ph type=\"ctrTitle\"/></p:nvPr></p:nvSpPr><p:spPr/>"))
        #expect(title.contains("<p:ph type=\"subTitle\" idx=\"1\"/>"))
        // The only transform is the shape tree's own.
        #expect(title.components(separatedBy: "<a:xfrm").count == 2)
        #expect(!title.contains("<p:bg>"))
        let skipped = String(decoding: parts["ppt/slides/slide4.xml"]!, as: UTF8.self)
        #expect(skipped.contains("<p:sld xmlns:a="))
        #expect(skipped.contains(" show=\"0\""))
        let body = String(decoding: parts["ppt/slides/slide2.xml"]!, as: UTF8.self)
        #expect(body.contains("<a:hlinkClick r:id=\"rId3\"/>"))
        #expect(body.contains("action=\"ppaction://hlinksldjump\""))
        #expect(body.contains("<a:br><a:rPr sz=\"2050\"><a:latin typeface=\"Georgia\"/></a:rPr></a:br>"))
        let relationships = String(decoding: parts["ppt/slides/_rels/slide2.xml.rels"]!, as: UTF8.self)
        #expect(relationships.contains("Target=\"https://example.com/a?b=1&amp;c=2\" TargetMode=\"External\""))
        #expect(relationships.contains("Target=\"slide4.xml\""))
        #expect(relationships.contains("Target=\"../slideLayouts/slideLayout3.xml\""))
        #expect(relationships.contains("Target=\"../notesSlides/notesSlide1.xml\""))
        // Slide numbers show the slide's own number.
        let numbered = String(decoding: parts["ppt/slides/slide5.xml"]!, as: UTF8.self)
        #expect(numbered.contains("type=\"slidenum\"><a:t>5</a:t></a:fld>"))
        let layout = String(decoding: parts["ppt/slideLayouts/slideLayout1.xml"]!, as: UTF8.self)
        #expect(layout.contains("type=\"title\" preserve=\"1\"><p:cSld name=\"Title slide\">"))
        #expect(layout.contains("<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"))
        let custom = String(decoding: parts["ppt/slideLayouts/slideLayout12.xml"]!, as: UTF8.self)
        #expect(custom.contains(" showMasterSp=\"0\" type=\"cust\""))
        let master = String(decoding: parts["ppt/slideMasters/slideMaster1.xml"]!, as: UTF8.self)
        #expect(master.contains("<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\""))
        let theme = String(decoding: parts["ppt/theme/theme1.xml"]!, as: UTF8.self)
        #expect(theme.contains("<a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"))
        let format = try Self.tree(parts["ppt/theme/theme1.xml"]).firstDescendant("fmtScheme")
        #expect(format?.child("fillStyleLst")?.children.count == 3)
        #expect(format?.child("lnStyleLst")?.children.count == 3)
        #expect(format?.child("effectStyleLst")?.children.count == 3)
        #expect(format?.child("bgFillStyleLst")?.children.count == 3)
        #expect(String(decoding: parts["ppt/tableStyles.xml"]!, as: UTF8.self).contains("def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\""))
    }

    /// Child order in the XSD sequences PowerPoint is strict about.
    static let sequences: [String: [String]] = [
        "spPr": ["xfrm", "custGeom", "prstGeom", "noFill", "solidFill", "gradFill", "blipFill", "pattFill", "grpFill", "ln", "effectLst"],
        "ln": ["noFill", "solidFill", "gradFill", "pattFill", "prstDash", "custDash", "round", "bevel", "miter", "headEnd", "tailEnd"],
        "pPr": ["lnSpc", "spcBef", "spcAft", "buClrTx", "buClr", "buSzTx", "buSzPct", "buSzPts", "buFontTx", "buFont", "buNone", "buAutoNum", "buChar", "buBlip",
                "tabLst", "defRPr"],
        "rPr": ["ln", "noFill", "solidFill", "gradFill", "effectLst", "highlight", "uLnTx", "uLn", "uFillTx", "uFill", "latin", "ea", "cs", "sym", "hlinkClick"],
        "txBody": ["bodyPr", "lstStyle", "p"],
        "p": ["pPr", "r", "br", "fld", "endParaRPr"],
        "cSld": ["bg", "spTree"],
        "sp": ["nvSpPr", "spPr", "style", "txBody"],
        "pic": ["nvPicPr", "blipFill", "spPr"],
        "blipFill": ["blip", "srcRect", "tile", "stretch"],
        "grpSp": ["nvGrpSpPr", "grpSpPr"],
        "custGeom": ["avLst", "gdLst", "ahLst", "cxnLst", "rect", "pathLst"],
        "sldMaster": ["cSld", "clrMap", "sldLayoutIdLst", "txStyles"],
        "presentation": ["sldMasterIdLst", "notesMasterIdLst", "sldIdLst", "sldSz", "notesSz", "defaultTextStyle", "extLst"],
        // Tables, word art and charts.
        "graphicFrame": ["nvGraphicFramePr", "xfrm", "graphic", "extLst"],
        "tbl": ["tblPr", "tblGrid", "tr"],
        "tc": ["txBody", "tcPr", "extLst"],
        "tcPr": ["lnL", "lnR", "lnT", "lnB", "lnTlToBr", "lnBlToTr", "cell3D", "noFill", "solidFill", "gradFill", "blipFill", "pattFill", "grpFill",
                 "headers", "extLst"],
        "bodyPr": ["prstTxWarp", "noAutofit", "normAutofit", "spAutoFit", "scene3d", "sp3d", "flatTx", "extLst"],
        "chartSpace": ["date1904", "lang", "roundedCorners", "style", "clrMapOvr", "pivotSource", "protection", "chart", "spPr", "txPr", "externalData",
                       "printSettings", "userShapes", "extLst"],
        "chart": ["title", "autoTitleDeleted", "pivotFmts", "view3D", "floor", "sideWall", "backWall", "plotArea", "legend", "plotVisOnly", "dispBlanksAs",
                  "showDLblsOverMax", "extLst"],
        "ser": ["idx", "order", "tx", "spPr", "invertIfNegative", "pictureOptions", "marker", "explosion", "dPt", "dLbls", "trendline", "errBars", "cat",
                "val", "xVal", "yVal", "smooth", "shape", "extLst"],
        "dPt": ["idx", "invertIfNegative", "marker", "bubble3D", "explosion", "spPr", "pictureOptions", "extLst"],
        "dLbls": ["dLbl", "delete", "numFmt", "spPr", "txPr", "dLblPos", "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent",
                  "showBubbleSize", "separator", "showLeaderLines", "leaderLines", "extLst"],
        "catAx": ["axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines", "title", "numFmt", "majorTickMark", "minorTickMark",
                  "tickLblPos", "spPr", "txPr", "crossAx", "crosses", "crossesAt", "auto", "lblAlgn", "lblOffset", "tickLblSkip", "tickMarkSkip",
                  "noMultiLvlLbl", "extLst"],
        "valAx": ["axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines", "title", "numFmt", "majorTickMark", "minorTickMark",
                  "tickLblPos", "spPr", "txPr", "crossAx", "crosses", "crossesAt", "crossBetween", "majorUnit", "minorUnit", "dispUnits", "extLst"],
        "scaling": ["logBase", "orientation", "max", "min", "extLst"],
        "legend": ["legendPos", "legendEntry", "layout", "overlay", "spPr", "txPr", "extLst"],
        "numCache": ["formatCode", "ptCount", "pt", "extLst"],
        "strCache": ["ptCount", "pt", "extLst"],
    ]

    static func checkOrder(_ node: XNode, path: String) -> [String] {
        var problems: [String] = []
        let key = ["defRPr", "endParaRPr"].contains(node.name) ? "rPr" : node.name.hasPrefix("lvl") && node.name.hasSuffix("pPr") ? "pPr" : node.name
        if let sequence = sequences[key] {
            // Runs, breaks and fields mix freely; other children follow the sequence.
            let ranks = node.children.compactMap { child in sequence.firstIndex(of: child.name).map { ["r", "br", "fld"].contains(child.name) ? sequence.firstIndex(of: "r")! : $0 } }
            if ranks != ranks.sorted() { problems.append("\(path): \(node.name) has \(node.children.map(\.name))") }
        }
        for child in node.children { problems += checkOrder(child, path: path) }
        return problems
    }

    @Test func childElementsFollowTheSchemaOrder() throws {
        var problems: [String] = []
        for presentation in [PPTXSamples.rich(), PPTXSamples.objects()] {
            let parts = try Self.parts(presentation)
            #expect(parts.keys.contains { $0.hasPrefix("ppt/charts/chart") })
            for (path, data) in parts where path.hasPrefix("ppt/") && path.hasSuffix(".xml") {
                problems += Self.checkOrder(try Self.tree(data), path: path)
            }
        }
        #expect(problems.isEmpty, "\(problems.prefix(5))")
    }

    @Test func outOfRangeValuesAreClampedToWhatTheSchemaAllows() throws {
        var presentation = Presentation.makeDefault()
        var paragraph = TextParagraph(runs: [TextRun("Big\u{0}\u{1F}\u{FFFE} <&> text\r\nmore", style: CharacterStyle(fontFamily: "", fontSize: 10_000, link: .url("https://example.com/a b/ü?x=%zz")))])
        paragraph.style = ParagraphStyle(lineSpacing: 1e9, spaceBefore: -5, marginLeft: 1e12, indent: -1e12, bullet: .number(.arabicPeriod, startAt: 0),
                                         bulletSize: 10)
        let element = SlideElement(name: "", placement: Placement(frame: SlideRect(x: .infinity, y: -1e30, width: -50, height: .nan), rotation: .nan),
                                   content: .shape(Shape(geometry: .preset("notAShape", adjustments: ["adj": 1e20, "bad name": 5]),
                                                         outline: Outline(fill: .picture(PictureFill(mediaID: "nothing")), width: 1e9),
                                                         text: TextBody(paragraphs: [paragraph], properties: TextBodyProperties(autofit: .shrinkOnOverflow, fontScale: 0)))))
        presentation.slides[0].elements.append(element)
        presentation.slideSize = SlideSize(width: 1e9, height: 1)
        let parts = try Self.parts(presentation)
        let slide = String(decoding: parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        #expect(XMLParser(data: parts["ppt/slides/slide1.xml"]!).parse())
        #expect(slide.contains("<a:t>Big &lt;&amp;&gt; text</a:t></a:r><a:br>"))
        #expect(slide.contains("sz=\"400000\""))
        #expect(slide.contains("<a:lnSpc><a:spcPct val=\"13200000\"/></a:lnSpc><a:spcBef><a:spcPts val=\"0\"/></a:spcBef>"))
        #expect(slide.contains("marL=\"51206400\""))
        #expect(slide.contains("indent=\"-51206400\""))
        #expect(slide.contains("<a:buSzPct val=\"400000\"/>"))
        #expect(slide.contains("<a:buAutoNum type=\"arabicPeriod\"/>"))
        #expect(slide.contains("<a:normAutofit fontScale=\"1000\"/>"))
        #expect(slide.contains("prst=\"rect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 2000000000\"/></a:avLst>"))
        #expect(slide.contains("<a:ln w=\"20116800\"><a:noFill/></a:ln>"))
        #expect(slide.contains("<a:ext cx=\"635000\" cy=\"0\"/>"))
        #expect(!slide.contains("latin"))
        let relationships = String(decoding: parts["ppt/slides/_rels/slide1.xml.rels"]!, as: UTF8.self)
        #expect(relationships.contains("Target=\"https://example.com/a%20b/%C3%BC?x=%25zz\""))
        let presentationPart = String(decoding: parts["ppt/presentation.xml"]!, as: UTF8.self)
        #expect(presentationPart.contains("<p:sldSz cx=\"51206400\" cy=\"914400\"/>"))
        // And it still reads.
        #expect(try PPTXTestPackage.read(try PPTXWriter.write(presentation)).presentation.slides.count == 1)
    }

    @Test func mediaIsWrittenOncePerImageUsed() throws {
        var presentation = Presentation.makeDefault()
        let used = presentation.addMedia(PPTXSamples.photo, contentType: "image/png")
        let svg = presentation.addMedia(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8), contentType: "image/svg+xml")
        let unknown = presentation.addMedia(Data([1, 2, 3, 4]), contentType: "image/heic")
        _ = presentation.addMedia(PPTXSamples.texture, contentType: "image/png")
        let picture = { (id: MediaID) in SlideElement(placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: id))) }
        presentation.slides[0].elements += [picture(used), picture(used), picture(svg), picture(unknown)]
        presentation.slides[0].background = .picture(PictureFill(mediaID: used))
        let parts = try Self.parts(presentation)
        #expect(parts.keys.filter { $0.hasPrefix("ppt/media/") }.sorted() == ["ppt/media/image1.png", "ppt/media/image2.svg", "ppt/media/image3.bin"])
        let types = String(decoding: parts["[Content_Types].xml"]!, as: UTF8.self)
        #expect(types.contains("<Default Extension=\"svg\" ContentType=\"image/svg+xml\"/>"))
        #expect(types.contains("<Override PartName=\"/ppt/media/image3.bin\" ContentType=\"image/heic\"/>"))
        let relationships = String(decoding: parts["ppt/slides/_rels/slide1.xml.rels"]!, as: UTF8.self)
        #expect(relationships.matches(of: /media\/image1\.png/).count == 1)
        let read = try PPTXTestPackage.read(try PPTXWriter.write(presentation)).presentation
        #expect(read.media.count == 3)
        #expect(Set(read.media.values.map(\.contentType)) == ["image/png", "image/svg+xml", "image/heic"])
    }
}
