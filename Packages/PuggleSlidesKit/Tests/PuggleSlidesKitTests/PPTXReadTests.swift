import Foundation
import Testing
@testable import PuggleSlidesKit

/// Reading hand-built packages laid out like PowerPoint's, other apps' exports and strict Open XML files.
struct PPTXReadTests {
    typealias Package = PPTXTestPackage

    static func sp(_ id: Int, _ name: String, ph: String? = nil, xfrm: String? = "<a:xfrm><a:off x=\"1270000\" y=\"635000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></a:xfrm>",
                   geometry: String = "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>", properties: String = "", style: String = "",
                   text: String? = nil, textBox: Bool = false, extra: String = "") -> String {
        let nvPr = ph.map { "<p:nvPr>\($0)</p:nvPr>" } ?? "<p:nvPr/>"
        let body = text.map { "<p:txBody>\($0)</p:txBody>" } ?? ""
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"\(extra)/><p:cNvSpPr\(textBox ? " txBox=\"1\"" : "")/>\(nvPr)</p:nvSpPr>"
            + "<p:spPr>\(xfrm ?? "")\(geometry)\(properties)</p:spPr>\(style)\(body)</p:sp>"
    }

    static func body(_ paragraphs: String, bodyPr: String = "<a:bodyPr/>", listStyle: String = "<a:lstStyle/>") -> String {
        bodyPr + listStyle + paragraphs
    }

    static func read(_ package: Package) throws -> PresentationFile {
        try Package.read(try package.data())
    }

    // MARK: PowerPoint

    /// Shapes as PowerPoint makes them: formatting from the theme through p:style.
    static func powerPointPackage() -> Package {
        var package = Package()
        let style = "<p:style><a:lnRef idx=\"2\"><a:schemeClr val=\"accent1\"><a:shade val=\"50000\"/></a:schemeClr></a:lnRef>"
            + "<a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef>"
            + "<a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>"
        let overridden = "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:lnRef><a:fillRef idx=\"3\"><a:schemeClr val=\"accent2\"/></a:fillRef>"
            + "<a:effectRef idx=\"0\"><a:schemeClr val=\"accent2\"/></a:effectRef><a:fontRef idx=\"major\"><a:schemeClr val=\"dk1\"/></a:fontRef></p:style>"
        let connector = "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"6\" name=\"Straight Arrow Connector 5\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>"
            + "<a:xfrm flipV=\"1\"><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm><a:prstGeom prst=\"straightConnector1\"><a:avLst/></a:prstGeom>"
            + "<a:ln><a:tailEnd type=\"triangle\"/></a:ln></p:spPr><p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef>"
            + "<a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef>"
            + "<a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style></p:cxnSp>"
        package.slides = [Package.Slide(xml: Package.slide(
            Self.sp(4, "Rectangle 3", style: style, text: Self.body("<a:p><a:pPr algn=\"ctr\"/><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>Blue box</a:t></a:r></a:p>",
                                                                   bodyPr: "<a:bodyPr rtlCol=\"0\" anchor=\"ctr\"/>"))
                + Self.sp(5, "Red", properties: "<a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill><a:ln w=\"12700\"/>", style: overridden)
                + connector))]
        return package
    }

    @Test func powerPointStyleReferencesBecomeExplicitFormatting() throws {
        let presentation = try Self.read(Self.powerPointPackage()).presentation
        let slide = presentation.slides[0]
        let box = try #require(slide.elements[0].shape)
        #expect(box.fill == .solid(ColorRef(theme: .accent1)))
        #expect(box.outline == Outline(fill: .solid(ColorRef(.theme(.accent1), shade: 0.5)), width: 2))
        #expect(box.text?.listStyle[0].character.color == ColorRef(theme: .light1))
        #expect(box.text?.listStyle[8].character.fontFamily == "+mn-lt")
        let resolved = presentation.style(for: slide.elements[0], on: slide).resolvedParagraphs()
        #expect(resolved[0].runs[0].style.color.rgb == .white)
        #expect(resolved[0].runs[0].style.fontFamily == "Calibri")
        #expect(resolved[0].alignment == .center)

        // spPr wins over the style, property by property: the line keeps the style's color at its own width.
        let red = try #require(slide.elements[1].shape)
        #expect(red.fill == .solid(ColorRef(RGBColor(red: 255, green: 0, blue: 0))))
        #expect(red.outline == Outline(fill: .solid(ColorRef(.theme(.accent2), shade: 0.95)), width: 1))

        let line = try #require(slide.elements[2].shape)
        #expect(line.isConnector)
        #expect(line.fill == nil)
        #expect(line.outline == Outline(fill: .solid(ColorRef(.theme(.accent1), shade: 0.95)), width: 0.75, tail: .fillArrow))
        #expect(slide.elements[2].placement?.flipVertical == true)
        #expect(slide.elements[2].name == "Straight Arrow Connector 5")
    }

    @Test func placeholdersWithoutPositionOrTypeInherit() throws {
        var package = Package()
        package.masterTree = Self.sp(2, "Title Placeholder 1", ph: "<p:ph type=\"title\"/>", text: Self.body("<a:p/>"))
            + Self.sp(3, "Text Placeholder 2", ph: "<p:ph type=\"body\" idx=\"1\"/>", geometry: "<a:prstGeom prst=\"roundRect\"><a:avLst/></a:prstGeom>",
                      text: Self.body("<a:p/>"))
        package.textStyles = "<p:titleStyle><a:lvl1pPr algn=\"ctr\"><a:defRPr sz=\"4400\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill>"
            + "<a:latin typeface=\"+mj-lt\"/></a:defRPr></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr marL=\"342900\" indent=\"-342900\">"
            + "<a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/><a:defRPr sz=\"3200\"/></a:lvl1pPr></p:bodyStyle><p:otherStyle/>"
        package.layouts = [Package.layout(type: "obj", name: "Title and Content", tree:
            Self.sp(2, "Title 1", ph: "<p:ph type=\"title\"/>", xfrm: nil, geometry: "", text: Self.body("<a:p/>"))
                + Self.sp(3, "Content Placeholder 2", ph: "<p:ph idx=\"1\"/>", xfrm: nil, geometry: "", text: Self.body("<a:p/>")))]
        package.slides = [Package.Slide(xml: Package.slide(
            Self.sp(2, "Title 1", ph: "<p:ph type=\"title\"/>", xfrm: nil, geometry: "", text: Self.body("<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>Agenda</a:t></a:r></a:p>"))
                + Self.sp(3, "Content Placeholder 2", ph: "<p:ph idx=\"1\"/>", xfrm: nil, geometry: "",
                          text: Self.body("<a:p><a:r><a:t>One</a:t></a:r></a:p><a:p><a:pPr lvl=\"1\"/><a:r><a:t>Two</a:t></a:r></a:p>"))))]
        let presentation = try Self.read(package).presentation
        let layout = try #require(presentation.themes.first?.layouts.first)
        #expect(layout.kind == .titleAndBody)
        #expect(layout.name == "Title and Content")
        #expect(layout.elements.map(\.placeholder) == [PlaceholderRef(type: .title), PlaceholderRef(type: .object, index: 1)])
        #expect(layout.elements.allSatisfy { $0.placement == nil })
        // Geometry left out inherits too: the body placeholder is the master's rounded rectangle.
        #expect(layout.elements[1].shape?.geometry == .preset("roundRect", adjustments: [:]))

        let slide = presentation.slides[0]
        #expect(slide.elements.map(\.placeholder?.type) == [.title, .object])
        #expect(slide.elements.allSatisfy { $0.placement == nil })
        #expect(slide.elements[1].shape?.text?.paragraphs.map(\.level) == [0, 1])
        // Nothing is flattened: the slide's text has no formatting of its own.
        #expect(slide.elements[0].shape?.text?.listStyle.isEmpty == true)
        #expect(slide.elements[0].shape?.text?.paragraphs[0].runs[0].style == .empty)
        let title = presentation.style(for: slide.elements[0], on: slide)
        #expect(title.placement.frame == SlideRect(x: 100, y: 50, width: 200, height: 100))
        #expect(title.resolvedParagraphs()[0].runs[0].style.fontSize == 44)
        #expect(title.resolvedParagraphs()[0].alignment == .center)
        let content = presentation.style(for: slide.elements[1], on: slide).resolvedParagraphs()
        #expect(content[0].bullet?.text == "•")
        #expect(content[0].marginLeft == 27)
    }

    @Test func groupsMapTheirChildrenToSlideCoordinates() throws {
        func box(_ id: Int, _ x: Int, _ y: Int, _ width: Int, _ height: Int, rotation: Int = 0) -> String {
            Self.sp(id, "Box \(id)", xfrm: "<a:xfrm\(rotation == 0 ? "" : " rot=\"\(rotation)\"")><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm>",
                    properties: "<a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill>")
        }
        // Child space 0–100 × 0–50 pt shown at 100,100 at twice the size.
        let scaled = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"10\" name=\"Scaled\" descr=\"Two boxes\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm>"
            + "<a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"1270000\" cy=\"635000\"/></a:xfrm>"
            + "<a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></p:grpSpPr>"
            + box(11, 127000, 127000, 254000, 127000)
            + Self.sp(12, "Inherits group fill", xfrm: "<a:xfrm><a:off x=\"635000\" y=\"0\"/><a:ext cx=\"635000\" cy=\"635000\"/></a:xfrm>", properties: "<a:grpFill/>")
            + "</p:grpSp>"
        // Turned a quarter turn clockwise about its center (200, 400): a child at its left edge ends up at the top.
        let turned = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"20\" name=\"Turned\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm rot=\"5400000\">"
            + "<a:off x=\"1270000\" y=\"4445000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/><a:chOff x=\"1270000\" y=\"4445000\"/><a:chExt cx=\"2540000\" cy=\"1270000\"/></a:xfrm></p:grpSpPr>"
            + box(21, 1270000, 4445000, 635000, 1270000, rotation: 600000)
            + "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"22\" name=\"Inner\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm flipH=\"1\">"
            + "<a:off x=\"3175000\" y=\"4445000\"/><a:ext cx=\"635000\" cy=\"635000\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"635000\" cy=\"635000\"/></a:xfrm></p:grpSpPr>"
            + box(23, 0, 0, 317500, 635000) + "</p:grpSp></p:grpSp>"
        var package = Package()
        package.slides = [Package.Slide(xml: Package.slide(scaled + turned))]
        let slide = try Self.read(package).presentation.slides[0]
        #expect(slide.elements.count == 2)

        let group = try #require(slide.elements[0].children)
        #expect(slide.elements[0].name == "Scaled")
        #expect(slide.elements[0].altDescription == "Two boxes")
        #expect(group[0].placement?.frame == SlideRect(x: 120, y: 120, width: 40, height: 20))
        #expect(group[1].placement?.frame == SlideRect(x: 200, y: 100, width: 100, height: 100))
        #expect(group[1].shape?.fill == .solid(ColorRef(RGBColor(red: 255, green: 0, blue: 0))))
        #expect(slide.elements[0].placement?.frame == SlideRect(x: 120, y: 100, width: 180, height: 100))

        let turnedChildren = try #require(slide.elements[1].children)
        let first = try #require(turnedChildren[0].placement)
        // The child's center (125, 400) turns about (200, 400) to (200, 325); its own 10° adds to the group's 90°.
        #expect(abs(first.frame.midX - 200) < 1e-6 && abs(first.frame.midY - 325) < 1e-6)
        #expect(abs(first.rotation - 100) < 1e-9)
        #expect(first.frame.width == 50 && first.frame.height == 100)
        // The flipped inner group flips its child within it, then the outer turn moves and turns it.
        let inner = try #require(turnedChildren[1].children?.first?.placement)
        #expect(inner.flipHorizontal)
        #expect(abs(inner.frame.midX - 225) < 1e-6 && abs(inner.frame.midY - 487.5) < 1e-6)
        #expect(abs(inner.rotation - 90) < 1e-9)
    }

    @Test func customGeometryEvaluatesGuides() throws {
        let geometry = "<a:custGeom><a:avLst><a:gd name=\"adj\" fmla=\"val 25000\"/></a:avLst><a:gdLst><a:gd name=\"inset\" fmla=\"*/ ss adj 100000\"/>"
            + "<a:gd name=\"right\" fmla=\"+- r 0 inset\"/><a:gd name=\"bottom\" fmla=\"+- b 0 inset\"/><a:gd name=\"half\" fmla=\"+/ l r 2\"/>"
            + "<a:gd name=\"angle\" fmla=\"at2 1 1\"/><a:gd name=\"pinned\" fmla=\"pin 0 inset 100\"/><a:gd name=\"bad\" fmla=\"*/ w 1 0\"/></a:gdLst>"
            + "<a:ahLst/><a:cxnLst/><a:rect l=\"inset\" t=\"inset\" r=\"right\" b=\"bottom\"/><a:pathLst>"
            + "<a:path><a:moveTo><a:pt x=\"half\" y=\"t\"/></a:moveTo><a:lnTo><a:pt x=\"r\" y=\"b\"/></a:lnTo><a:lnTo><a:pt x=\"bad\" y=\"b\"/></a:lnTo>"
            + "<a:arcTo wR=\"inset\" hR=\"inset\" stAng=\"angle\" swAng=\"cd4\"/><a:close/></a:path>"
            + "<a:path w=\"200\" h=\"100\" fill=\"none\" stroke=\"0\"><a:moveTo><a:pt x=\"0\" y=\"50\"/></a:moveTo>"
            + "<a:quadBezTo><a:pt x=\"100\" y=\"0\"/><a:pt x=\"200\" y=\"50\"/></a:quadBezTo>"
            + "<a:cubicBezTo><a:pt x=\"150\" y=\"100\"/><a:pt x=\"50\" y=\"100\"/><a:pt x=\"0\" y=\"50\"/></a:cubicBezTo></a:path></a:pathLst></a:custGeom>"
        var package = Package()
        package.slides = [Package.Slide(xml: Package.slide(Self.sp(2, "Freeform 1", geometry: geometry)))]
        let shape = try #require(try Self.read(package).presentation.slides[0].elements[0].shape)
        guard case .custom(let custom) = shape.geometry else {
            Issue.record("expected a custom geometry")
            return
        }
        // The frame is 200 × 100 pt, so the inset (25% of the short side) is 25 pt, kept in points.
        #expect(custom.paths.count == 2)
        #expect(custom.paths[0].width == 0 && custom.paths[0].height == 0)
        #expect(custom.paths[0].commands == [.move(SlidePoint(x: 100, y: 0)), .line(SlidePoint(x: 200, y: 100)), .line(SlidePoint(x: 0, y: 100)),
                                              .arc(widthRadius: 25, heightRadius: 25, startAngle: 45, sweepAngle: 90), .close])
        #expect(custom.paths[1] == CustomPath(width: 200, height: 100, fill: PathFillMode.none, stroke: false, commands: [
            .move(SlidePoint(x: 0, y: 50)), .quadratic(control: SlidePoint(x: 100, y: 0), end: SlidePoint(x: 200, y: 50)),
            .cubic(control1: SlidePoint(x: 150, y: 100), control2: SlidePoint(x: 50, y: 100), end: SlidePoint(x: 0, y: 50)),
        ]))
        #expect(custom.textRect == TextInsetFractions(left: 0.125, top: 0.25, right: 0.125, bottom: 0.25))
    }

    @Test func picturesKeepCropMaskAndOutline() throws {
        let photo = PPTXTestImage.png(width: 2, height: 2) { _, _ in (10, 20, 30) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0, count: 60))
        func picture(_ id: Int, _ relationship: String, extra: String = "", spPr: String = "") -> String {
            "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\" descr=\"A photo\" title=\"Photo\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr>"
                + "<p:nvPr/></p:nvPicPr><p:blipFill><a:blip \(relationship)/>\(extra)<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>"
                + "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"1270000\"/></a:xfrm>\(spPr)</p:spPr></p:pic>"
        }
        var package = Package()
        package.media = ["ppt/media/image1.png": photo, "ppt/media/image2.png": photo, "ppt/media/image3.png": jpeg]
        package.slides = [Package.Slide(xml: Package.slide(
            picture(2, "r:embed=\"rId3\"", extra: "<a:srcRect l=\"10000\" t=\"5000\" r=\"20000\" b=\"-2500\"/>",
                    spPr: "<a:prstGeom prst=\"ellipse\"><a:avLst/></a:prstGeom><a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill></a:ln>")
                + picture(3, "r:embed=\"rId4\"")
                + picture(4, "r:embed=\"rId5\"")
                + picture(5, "r:link=\"rId6\"")
                + picture(6, "r:embed=\"rId99\"")
                + Self.sp(7, "Tiled", properties: "<a:blipFill><a:blip r:embed=\"rId3\"/><a:tile tx=\"0\" ty=\"0\" sx=\"100000\" sy=\"100000\"/></a:blipFill>")),
            relationships: [Package.Relationship("rId3", "image", "../media/image1.png"), Package.Relationship("rId4", "image", "../media/image2.png"),
                            Package.Relationship("rId5", "image", "/ppt/media/image3.png"),
                            Package.Relationship("rId6", "image", "https://example.com/photo.png", external: true)])]
        let file = try Self.read(package)
        let elements = file.presentation.slides[0].elements
        #expect(elements.count == 4)
        let first = try #require(elements[0].picture)
        #expect(first.crop == ImageCrop(left: 0.1, top: 0.05, right: 0.2, bottom: -0.025))
        #expect(first.geometry == .preset("ellipse", adjustments: [:]))
        #expect(first.outline == .solid(ColorRef(theme: .accent1), width: 3))
        #expect(elements[0].altTitle == "Photo" && elements[0].altDescription == "A photo")
        // The same bytes in two parts are stored once; JPEG bytes are known by their signature.
        #expect(elements[1].picture?.mediaID == first.mediaID)
        #expect(file.presentation.media.count == 2)
        #expect(file.presentation.media[first.mediaID]?.contentType == "image/png")
        #expect(file.presentation.media[try #require(elements[2].picture?.mediaID)]?.contentType == "image/jpeg")
        #expect(elements[3].shape?.fill == .picture(PictureFill(mediaID: first.mediaID, stretches: false)))
        // Linked and missing pictures can't be shown.
        #expect(file.warnings == [.otherContent])
    }

    // MARK: Exported from other apps

    /// Another app's export: a color map that swaps bg2/tx2, layouts named by identifier, a default text style
    /// with defPPr, bullet sizes in points, and text boxes for placeholders.
    static func exportedPackage() -> Package {
        var package = Package()
        package.colorMap = "bg1=\"lt1\" tx1=\"dk1\" bg2=\"dk2\" tx2=\"lt2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" "
            + "accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\""
        package.theme = Package.theme(name: "Simple Light", major: "Arial", minor: "Arial")
        package.defaultTextStyle = "<a:defPPr marR=\"0\" lvl=\"0\" algn=\"l\" rtl=\"0\"><a:lnSpc><a:spcPct val=\"100000\"/></a:lnSpc><a:spcBef><a:spcPts val=\"0\"/>"
            + "</a:spcBef><a:spcAft><a:spcPts val=\"0\"/></a:spcAft><a:buNone/></a:defPPr><a:lvl1pPr marR=\"0\" lvl=\"0\" algn=\"l\" rtl=\"0\"><a:defRPr sz=\"1400\" b=\"0\" "
            + "i=\"0\" u=\"none\" strike=\"noStrike\" cap=\"none\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:latin typeface=\"Arial\"/></a:defRPr></a:lvl1pPr>"
        package.textStyles = "<p:titleStyle/><p:bodyStyle><a:lvl1pPr marL=\"457200\" lvl=\"0\" indent=\"-342900\"><a:spcBef><a:spcPts val=\"0\"/></a:spcBef>"
            + "<a:buClr><a:schemeClr val=\"dk2\"/></a:buClr><a:buSzPts val=\"1800\"/><a:buChar char=\"●\"/><a:defRPr sz=\"1800\"><a:solidFill><a:schemeClr val=\"tx2\"/>"
            + "</a:solidFill></a:defRPr></a:lvl1pPr></p:bodyStyle><p:otherStyle/>"
        package.masterTree = Self.sp(2, "Shape;6;p1", ph: "<p:ph type=\"body\" idx=\"1\"/>", text: Self.body("<a:p/>"), textBox: true)
        package.layouts = [
            Package.layout(type: "title", name: "TITLE", tree: Self.sp(9, "Shape;9;p2", ph: "<p:ph type=\"ctrTitle\"/>", text: Self.body("<a:p/>"), textBox: true),
                           attributes: " matchingName=\"Title slide\""),
            Package.layout(type: nil, name: "MAIN_POINT", tree: "", attributes: " matchingName=\"Main point\""),
            Package.layout(type: "blank", name: "BLANK", tree: "", attributes: " matchingName=\"Blank\""),
        ]
        package.slides = [Package.Slide(xml: Package.slide(
            Self.sp(54, "Shape;54;p13", ph: "<p:ph type=\"ctrTitle\"/>", text: Self.body(
                "<a:p><a:pPr marL=\"0\" lvl=\"0\" indent=\"0\" algn=\"ctr\" rtl=\"0\"><a:spcBef><a:spcPts val=\"0\"/></a:spcBef><a:spcAft><a:spcPts val=\"0\"/></a:spcAft>"
                    + "<a:buNone/></a:pPr><a:r><a:rPr lang=\"en\"><a:solidFill><a:schemeClr val=\"tx2\"/></a:solidFill></a:rPr><a:t>Hello</a:t></a:r>"
                    + "<a:endParaRPr><a:solidFill><a:schemeClr val=\"bg2\"/></a:solidFill></a:endParaRPr></a:p>",
                bodyPr: "<a:bodyPr spcFirstLastPara=\"1\" wrap=\"square\" lIns=\"91425\" tIns=\"91425\" rIns=\"91425\" bIns=\"91425\" anchor=\"b\" anchorCtr=\"0\"><a:noAutofit/></a:bodyPr>"),
                textBox: true)),
            notes: Package.notes("<a:p><a:pPr marL=\"0\" lvl=\"0\" indent=\"0\" algn=\"l\" rtl=\"0\"><a:spcBef><a:spcPts val=\"0\"/></a:spcBef><a:spcAft><a:spcPts val=\"0\"/>"
                + "</a:spcAft><a:buNone/></a:pPr><a:r><a:rPr lang=\"en\"/><a:t>Say hello</a:t></a:r><a:endParaRPr/></a:p>")), Package.Slide(xml: Package.slide(""), layout: 1)]
        return package
    }

    @Test func exportedPackagesRead() throws {
        let presentation = try Self.read(Self.exportedPackage()).presentation
        let theme = presentation.themes[0]
        #expect(theme.name == "Simple Light")
        #expect(theme.fonts.major == "Arial")
        #expect(theme.layouts.map(\.kind) == [.title, .mainPoint, .blank])
        #expect(theme.layouts.map(\.name) == ["Title slide", "Main point", "Blank"])
        #expect(theme.layouts[1].kind.fileType == "cust")

        // This color map sends tx2 to lt2 and bg2 to dk2; the model's standard map needs them stated as such.
        #expect(theme.bodyStyle[0].character.color == ColorRef(theme: .light2))
        #expect(theme.bodyStyle[0].paragraph.bulletColor == ColorRef(theme: .dark2))
        #expect(theme.bodyStyle[0].paragraph.bulletSize == 1)
        let slide = presentation.slides[0]
        let title = try #require(slide.elements[0].shape)
        #expect(title.isTextBox)
        #expect(title.text?.paragraphs[0].runs[0].style.color == ColorRef(theme: .light2))
        #expect(title.text?.paragraphs[0].endStyle.color == ColorRef(theme: .dark2))
        #expect(title.text?.properties == TextBodyProperties(anchor: .bottom, insets: TextInsets(all: 91425.0 / 12700), autofit: Autofit.none, wraps: true))
        #expect(title.text?.paragraphs[0].style == ParagraphStyle(alignment: .center, spaceBefore: 0, spaceAfter: 0, marginLeft: 0, indent: 0, bullet: Bullet.none))
        #expect(slide.notes.plainText == "Say hello")

        // defPPr is the base of every level of the default text style.
        let defaults = presentation.defaultTextStyle
        #expect(defaults[0].paragraph.lineSpacing == 1)
        #expect(defaults[0].character.fontSize == 14)
        #expect(defaults[5].paragraph.bullet == Bullet.none)
        #expect(defaults[5].character.fontSize == nil)
    }

    // MARK: Color maps

    @Test func darkMasterColorMapsAreRemapped() throws {
        var package = Package()
        package.colorMap = "bg1=\"dk1\" tx1=\"lt1\" bg2=\"dk2\" tx2=\"lt2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" "
            + "accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\""
        package.textStyles = "<p:titleStyle><a:lvl1pPr><a:defRPr><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:defRPr></a:lvl1pPr></p:titleStyle>"
        package.slides = [Package.Slide(xml: Package.slide(Self.sp(2, "Box", properties: "<a:solidFill><a:schemeClr val=\"bg2\"><a:lumMod val=\"75000\"/></a:schemeClr></a:solidFill>")))]
        let presentation = try Self.read(package).presentation
        let theme = presentation.themes[0]
        #expect(theme.background == .solid(ColorRef(theme: .dark1)))
        #expect(theme.titleStyle[0].character.color == ColorRef(theme: .light1))
        #expect(presentation.slides[0].elements[0].shape?.fill == .solid(ColorRef(.theme(.dark2), lumMod: 0.75)))
    }

    /// A dark title layout that overrides the color map, and a slide that follows it.
    static func colorMapOverridePackage() -> Package {
        let dark = "<p:clrMapOvr><a:overrideClrMapping bg1=\"dk1\" tx1=\"lt1\" bg2=\"dk2\" tx2=\"lt2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" "
            + "accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/></p:clrMapOvr>"
        var package = Package()
        package.masterTree = Self.sp(2, "Title", ph: "<p:ph type=\"title\"/>", text: Self.body("<a:p/>"))
        package.textStyles = "<p:titleStyle><a:lvl1pPr><a:defRPr sz=\"4000\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:defRPr></a:lvl1pPr></p:titleStyle>"
        package.layouts = [
            Package.layout(type: "title", name: "Dark title", tree: Self.sp(2, "Title", ph: "<p:ph type=\"title\"/>", xfrm: nil, geometry: "", text: Self.body("<a:p/>"))
                + Self.sp(3, "Stripe", properties: "<a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill>"),
                background: "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>", colorMapOverride: dark),
            Package.layout(type: "blank", name: "Blank", tree: ""),
        ]
        let title = Self.sp(2, "Title", ph: "<p:ph type=\"title\"/>", xfrm: nil, geometry: "", text: Self.body("<a:p><a:r><a:t>Welcome</a:t></a:r></a:p>"))
        let overridden = Package.slide(title).replacingOccurrences(of: "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>", with: dark)
        package.defaultTextStyle = "<a:lvl1pPr><a:defRPr><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:defRPr></a:lvl1pPr>"
        let note = Self.sp(4, "Note", text: Self.body("<a:p><a:r><a:t>x</a:t></a:r></a:p>"))
        // A slide that turns dark on a layout that doesn't.
        let darkSlide = Package.slide(note).replacingOccurrences(of: "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>", with: dark)
        package.slides = [Package.Slide(xml: overridden), Package.Slide(xml: Package.slide(note), layout: 1), Package.Slide(xml: darkSlide, layout: 1)]
        return package
    }

    @Test func colorMapOverridesFixInheritedColors() throws {
        let presentation = try Self.read(Self.colorMapOverridePackage()).presentation
        let layout = presentation.themes[0].layouts[0]
        // The layout's own content is read with its map.
        #expect(layout.background == .solid(ColorRef(theme: .dark1)))
        #expect(layout.elements[1].shape?.fill == .solid(ColorRef(theme: .light1)))
        // The master's title color, inherited across the override, is set where the map changes.
        #expect(layout.elements[0].shape?.text?.listStyle[0].character.color == ColorRef(theme: .light1))
        let slide = presentation.slides[0]
        let style = presentation.style(for: slide.elements[0], on: slide)
        #expect(style.resolvedParagraphs()[0].runs[0].style.color.rgb == .white)
        #expect(style.resolvedParagraphs()[0].runs[0].style.fontSize == 40)
        #expect(presentation.background(for: slide) == .solid(ColorRef(theme: .dark1)))
        // Slides under the master's own map are left alone.
        #expect(presentation.slides[1].elements[0].shape?.text?.listStyle.isEmpty == true)
        #expect(presentation.background(for: presentation.slides[1]) == .solid(ColorRef(theme: .light1)))
        // A slide's own override reaches what it inherits from the master: the background and default text color.
        let dark = presentation.slides[2]
        #expect(dark.background == .solid(ColorRef(theme: .dark1)))
        #expect(dark.elements[0].shape?.text?.listStyle[0].character.color == ColorRef(theme: .light1))
        #expect(presentation.style(for: dark.elements[0], on: dark).resolvedParagraphs()[0].runs[0].style.color.rgb == .white)
    }

    // MARK: Packages

    @Test func strictPackagesWithAbsoluteTargetsRead() throws {
        var package = Package()
        package.flavor = .strict
        package.absoluteTargets = true
        package.title = "Strict deck"
        package.slides = [Package.Slide(xml: Package.slide(
            Self.sp(2, "Box", xfrm: "<a:xfrm><a:off x=\"1in\" y=\"72pt\"/><a:ext cx=\"914400\" cy=\"6pc\"/></a:xfrm>",
                    properties: "<a:solidFill><a:schemeClr val=\"accent1\"><a:lumMod val=\"75%\"/><a:alpha val=\"50%\"/></a:schemeClr></a:solidFill>",
                    text: Self.body("<a:p><a:r><a:rPr sz=\"2400\"/><a:t>Strict</a:t></a:r></a:p>", bodyPr: "<a:bodyPr><a:normAutofit fontScale=\"62.5%\"/></a:bodyPr>"))))]
        let file = try Self.read(package)
        let presentation = file.presentation
        #expect(presentation.title == "Strict deck")
        #expect(presentation.slideSize == .widescreen)
        let element = presentation.slides[0].elements[0]
        #expect(element.placement?.frame == SlideRect(x: 72, y: 72, width: 72, height: 72))
        #expect(element.shape?.fill == .solid(ColorRef(.theme(.accent1), lumMod: 0.75, alpha: 0.5)))
        #expect(element.shape?.text?.properties.fontScale == 0.625)
        #expect(presentation.themes[0].colors[.accent1] == RGBColor(hex: "4472C4"))
        #expect(file.warnings.isEmpty)
    }

    @Test func textPropertiesRead() throws {
        var package = Package()
        let paragraphs = "<a:p><a:pPr lvl=\"2\" marL=\"914400\" indent=\"-228600\" algn=\"just\"><a:lnSpc><a:spcPts val=\"3600\"/></a:lnSpc><a:spcBef>"
            + "<a:spcPct val=\"50000\"/></a:spcBef><a:spcAft><a:spcPts val=\"1200\"/></a:spcAft><a:buClrTx/><a:buSzPts val=\"1200\"/><a:buFont typeface=\"Wingdings\"/>"
            + "<a:buAutoNum type=\"arabicDbPeriod\" startAt=\"4\"/></a:pPr><a:r><a:rPr sz=\"2400\" u=\"dbl\" strike=\"dblStrike\" baseline=\"-25000\">"
            + "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"00FF00\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst></a:gradFill>"
            + "<a:highlight><a:srgbClr val=\"FFFF00\"/></a:highlight><a:latin typeface=\"+mj-lt\"/><a:hlinkClick r:id=\"rId3\"/></a:rPr><a:t>Linked</a:t></a:r>"
            + "<a:br><a:rPr sz=\"2400\" u=\"dbl\" strike=\"dblStrike\" baseline=\"-25000\"><a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"00FF00\"/></a:gs>"
            + "</a:gsLst></a:gradFill><a:highlight><a:srgbClr val=\"FFFF00\"/></a:highlight><a:latin typeface=\"+mj-lt\"/><a:hlinkClick r:id=\"rId3\"/></a:rPr></a:br>"
            + "<a:r><a:rPr><a:hlinkClick r:id=\"rId4\" action=\"ppaction://hlinksldjump\"/></a:rPr><a:t>to slide 2</a:t></a:r>"
            + "<a:r><a:rPr><a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=nextslide\"/></a:rPr><a:t> next</a:t></a:r>"
            + "<a:fld id=\"{1}\" type=\"datetime1\"><a:rPr lang=\"en-US\"/><a:t>11/16/26</a:t></a:fld><a:r><a:t>line\nfeed</a:t></a:r>"
            + "<a:endParaRPr sz=\"1000\"/></a:p>"
            + "<a:p><a:pPr><a:buChar char=\"\"/></a:pPr></a:p><a:p><a:pPr><a:buBlip><a:blip r:embed=\"rId9\"/></a:buBlip></a:pPr></a:p>"
        let bodyPr = "<a:bodyPr wrap=\"none\" lIns=\"0\" anchor=\"ctr\"><a:normAutofit fontScale=\"92500\" lnSpcReduction=\"10000\"/></a:bodyPr>"
        let listStyle = "<a:lstStyle><a:lvl3pPr><a:buSzPct val=\"75000\"/><a:defRPr sz=\"1600\" b=\"1\"/></a:lvl3pPr></a:lstStyle>"
        package.slides = [
            Package.Slide(xml: Package.slide(Self.sp(2, "Text", text: Self.body(paragraphs, bodyPr: bodyPr, listStyle: listStyle))),
                          relationships: [Package.Relationship("rId3", "hyperlink", "https://example.com/?q=a b", external: true),
                                          Package.Relationship("rId4", "slide", "slide2.xml")]),
            Package.Slide(xml: Package.slide("")),
        ]
        let presentation = try Self.read(package).presentation
        let text = try #require(presentation.slides[0].elements[0].shape?.text)
        #expect(text.properties == TextBodyProperties(anchor: .middle, insets: TextInsets(left: 0, top: 3.6, right: 7.2, bottom: 3.6),
                                                      autofit: .shrinkOnOverflow, fontScale: 0.925, lineSpacingReduction: 0.1, wraps: false))
        #expect(text.listStyle[2] == LevelStyle(paragraph: ParagraphStyle(bulletSize: 0.75), character: CharacterStyle(fontSize: 16, bold: true)))
        let paragraph = text.paragraphs[0]
        #expect(paragraph.level == 2)
        #expect(paragraph.style == ParagraphStyle(alignment: .justified, lineSpacing: 36.0 / (1.2 * 24), spaceBefore: 0.5 * 1.2 * 24, spaceAfter: 12,
                                                  marginLeft: 72, indent: -18, bullet: .number(.arabicPeriod, startAt: 4), bulletFont: "Wingdings",
                                                  bulletSize: 0.5))
        let linked = CharacterStyle(fontFamily: "+mj-lt", fontSize: 24, underline: true, strikethrough: true, color: ColorRef(RGBColor(red: 0, green: 255, blue: 0)),
                                    highlight: ColorRef(RGBColor(red: 255, green: 255, blue: 0)), baseline: .subscript, link: .url("https://example.com/?q=a b"))
        #expect(paragraph.runs == [
            TextRun("Linked\u{2028}", style: linked),
            TextRun("to slide 2", style: CharacterStyle(link: .slide(presentation.slides[1].id))),
            TextRun(" next"),
            TextRun("11/16/26", field: .dateTime("datetime1")),
            TextRun("line\u{2028}feed"),
        ])
        #expect(paragraph.endStyle == CharacterStyle(fontSize: 10))
        #expect(text.paragraphs[1].style.bullet == Bullet.none)
        #expect(text.paragraphs[2].style.bullet == .character("•"))
    }

    // MARK: Warnings

    @Test func unsupportedContentLeavesWarnings() throws {
        func frame(_ uri: String, _ content: String) -> String {
            "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"9\" name=\"Frame\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"0\" y=\"0\"/>"
                + "<a:ext cx=\"100\" cy=\"100\"/></p:xfrm><a:graphic><a:graphicData uri=\"\(uri)\">\(content)</a:graphicData></a:graphic></p:graphicFrame>"
        }
        let table = frame("http://schemas.openxmlformats.org/drawingml/2006/table", "<a:tbl><a:tblGrid/></a:tbl>")
        let chart = frame("http://schemas.openxmlformats.org/drawingml/2006/chart", "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId9\"/>")
        let diagram = frame("http://schemas.openxmlformats.org/drawingml/2006/diagram", "<dgm:relIds xmlns:dgm=\"http://schemas.openxmlformats.org/drawingml/2006/diagram\"/>")
        let ole = frame("http://schemas.openxmlformats.org/presentationml/2006/ole", "<p:oleObj/>")
        // Motion that can't be kept: a transition with a sound, and a motion path.
        let sound = "<p:sndAc><p:stSnd><p:snd r:embed=\"rId9\" name=\"applause.wav\"/></p:stSnd></p:sndAc>"
        let transition = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"p14\">"
            + "<p:transition spd=\"slow\"><p:fade/>\(sound)</p:transition></mc:Choice><mc:Fallback><p:transition spd=\"slow\"><p:fade/>\(sound)</p:transition>"
            + "</mc:Fallback></mc:AlternateContent>"
        let animation = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" nodeType=\"tmRoot\"><p:childTnLst><p:seq><p:cTn id=\"2\" "
            + "nodeType=\"mainSeq\"><p:childTnLst><p:par><p:cTn id=\"3\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst><p:childTnLst><p:par>"
            + "<p:cTn id=\"4\" presetID=\"1\" presetClass=\"path\" nodeType=\"clickEffect\"><p:childTnLst><p:animMotion path=\"M 0 0 L 0.25 0.25 E\">"
            + "<p:cBhvr><p:cTn id=\"5\" dur=\"2000\"/><p:tgtEl><p:spTgt spid=\"5\"/></p:tgtEl></p:cBhvr></p:animMotion></p:childTnLst></p:cTn></p:par>"
            + "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
        let emptyTiming = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"/></p:par></p:tnLst></p:timing>"
        let video = "<p:pic><p:nvPicPr><p:cNvPr id=\"5\" name=\"Movie\"/><p:cNvPicPr/><p:nvPr><a:videoFile r:link=\"rId7\"/></p:nvPr></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"rId3\"/></p:blipFill><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm></p:spPr></p:pic>"
        let audio = "<p:pic><p:nvPicPr><p:cNvPr id=\"6\" name=\"Sound\"/><p:cNvPicPr/><p:nvPr><p:extLst><p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}\">"
            + "<p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"rId8\"/></p:ext></p:extLst></p:nvPr></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"rId3\"/></p:blipFill><p:spPr/></p:pic>"
        let ink = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"p14\">"
            + "<p14:contentPart xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:id=\"rId9\"/></mc:Choice><mc:Fallback>"
            + "<p:pic><p:nvPicPr><p:cNvPr id=\"7\" name=\"Ink\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId3\"/></p:blipFill>"
            + "<p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm></p:spPr></p:pic></mc:Fallback></mc:AlternateContent>"
        let equation = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"a14\">"
            + Self.sp(8, "Equation", text: Self.body("<a:p><a14:m xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\"/></a:p>"))
            + "</mc:Choice><mc:Fallback>" + Self.sp(8, "Equation picture", properties: "<a:blipFill><a:blip r:embed=\"rId3\"/><a:stretch/></a:blipFill>")
            + "</mc:Fallback></mc:AlternateContent>"
        let image = PPTXTestImage.png(width: 1, height: 1) { _, _ in (0, 0, 0) }
        var package = Package()
        package.media = ["ppt/media/image1.png": image]
        let relationships = [Package.Relationship("rId3", "image", "../media/image1.png"),
                             Package.Relationship("rId7", "video", "movie.mp4", external: true), Package.Relationship("rId8", "media", "../media/sound.mp3"),
                             Package.Relationship("rId9", "comments", "../comments/comment1.xml")]
        package.slides = [
            Package.Slide(xml: Package.slide(table + chart + video + audio + ink + equation, after: transition + animation), relationships: relationships),
            Package.Slide(xml: Package.slide(diagram + ole, after: emptyTiming)),
        ]
        let file = try Self.read(package)
        #expect(file.warnings == [.tables, .charts, .diagrams, .embeddedObjects, .transitions, .animations, .video, .audio, .ink, .comments])
        // Poster frames, ink drawn as a picture and equations' pictures are kept.
        #expect(file.presentation.slides[0].elements.map(\.name) == ["Movie", "Sound", "Ink", "Equation picture"])
        #expect(file.presentation.slides[1].elements.isEmpty)

        var quiet = Package()
        quiet.slides = [Package.Slide(xml: Package.slide("", after: emptyTiming))]
        #expect(try Self.read(quiet).warnings.isEmpty)

        // A slide zoom keeps its picture; a newer chart's "can't show this chart" stand-in goes. Links on whole shapes warn.
        let zoom = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"pslz\">"
            + frame("http://schemas.microsoft.com/office/powerpoint/2016/slidezoom", "<pslz:sldZm xmlns:pslz=\"urn:pslz\"/>") + "</mc:Choice><mc:Fallback>"
            + "<p:pic><p:nvPicPr><p:cNvPr id=\"7\" name=\"Slide Zoom\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId3\"/></p:blipFill>"
            + "<p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm></p:spPr></p:pic></mc:Fallback></mc:AlternateContent>"
        let newChart = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"cx1\">"
            + frame("http://schemas.microsoft.com/office/drawing/2014/chartex", "<cx:chart xmlns:cx=\"urn:cx\"/>") + "</mc:Choice><mc:Fallback>"
            + Self.sp(8, "Chart stand-in", text: Self.body("<a:p><a:r><a:t>This chart isn't available</a:t></a:r></a:p>")) + "</mc:Fallback></mc:AlternateContent>"
        let linkedShape = "<p:sp><p:nvSpPr><p:cNvPr id=\"9\" name=\"Button\"><a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=nextslide\"/>"
            + "</p:cNvPr><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm></p:spPr></p:sp>"
        var modern = Package()
        modern.media = ["ppt/media/image1.png": image]
        modern.slides = [Package.Slide(xml: Package.slide(zoom + newChart + linkedShape), relationships: [Package.Relationship("rId3", "image", "../media/image1.png")])]
        let modernFile = try Self.read(modern)
        #expect(modernFile.presentation.slides[0].elements.map(\.name) == ["Slide Zoom", "Button"])
        #expect(modernFile.warnings == [.otherContent, .charts])
    }

    @Test func damagedStructureIsSurvivable() throws {
        // A slide whose layout is missing uses the first layout; a slide part that's gone is skipped; hidden shapes go.
        var package = Package()
        package.layouts = [Package.layout(type: "title", name: "Title Slide", tree: ""), Package.layout(type: "blank", name: "Blank", tree: "")]
        package.slides = [Package.Slide(xml: Package.slide(Self.sp(2, "Hidden", extra: " hidden=\"1\"") + Self.sp(3, "Shown")), layout: 1),
                          Package.Slide(xml: Package.slide(""))]
        var parts = try PPTXTestPackage.parts(of: try package.data())
        parts["ppt/slides/_rels/slide1.xml.rels"] = nil
        parts["ppt/slides/slide2.xml"] = nil
        let file = try Package.read(try PPTXTestPackage.zip(parts))
        #expect(file.presentation.slides.count == 1)
        #expect(file.presentation.layout(for: file.presentation.slides[0])?.name == "Title Slide")
        #expect(file.presentation.slides[0].elements.map(\.name) == ["Shown"])
        #expect(file.warnings == [.otherContent])
    }

    // MARK: Errors

    static func message(_ data: Data) -> String? {
        do {
            _ = try PresentationIO.read(data, format: .pptx)
            return nil
        } catch let error as PresentationIOError {
            return error.errorDescription
        } catch {
            return "unexpected \(error)"
        }
    }

    @Test func unreadableFilesGetFriendlyMessages() throws {
        #expect(Self.message(Data()) == PPTXMessages.notAPresentation)
        #expect(Self.message(Data("Just some text that is long enough to look at.".utf8)) == PPTXMessages.notAPresentation)
        #expect(Self.message(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + Array(repeating: 0, count: 600))) == PPTXMessages.legacyOrEncrypted)
        let word = try PPTXTestPackage.zip(["word/document.xml": Data("<w:document xmlns:w=\"urn:w\"/>".utf8),
                                            "_rels/.rels": Data(("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" "
                                                + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>").utf8)])
        #expect(Self.message(word) == PPTXMessages.notAPresentation)

        let good = try Package().data()
        var parts = try PPTXTestPackage.parts(of: good)
        parts["ppt/presentation.xml"] = Data("<p:presentation xmlns:p=\"urn:p\"><p:sldIdLst>".utf8)
        #expect(Self.message(try PPTXTestPackage.zip(parts)) == PPTXMessages.damaged)

        parts = try PPTXTestPackage.parts(of: good)
        parts["ppt/slideMasters/slideMaster1.xml"] = Data((Package.declaration + "<!DOCTYPE x [<!ENTITY a \"aaaa\">]><p:sldMaster xmlns:p=\"urn:p\">&a;</p:sldMaster>").utf8)
        #expect(Self.message(try PPTXTestPackage.zip(parts)) == PPTXMessages.damaged)

        // A part that would expand past the size limit is refused before it's expanded.
        parts = try PPTXTestPackage.parts(of: good)
        parts["ppt/slideMasters/slideMaster1.xml"] = Data(count: PPTXPackageReader.maxXMLPartSize + 1)
        #expect(Self.message(try PPTXTestPackage.zip(parts)) == PPTXMessages.tooLarge)
    }

    @Test func packagesWithoutMastersGetADefaultTheme() throws {
        var parts = try PPTXTestPackage.parts(of: try Package().data())
        parts["ppt/presentation.xml"] = Data((Package.declaration + "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">"
            + "<p:sldSz cx=\"9144000\" cy=\"6858000\"/></p:presentation>").utf8)
        parts["ppt/_rels/presentation.xml.rels"] = nil
        let file = try Package.read(try PPTXTestPackage.zip(parts))
        #expect(file.presentation.themes.count == 1)
        #expect(file.presentation.slideSize == .standard)
        #expect(file.warnings == [.otherContent])
    }
}
