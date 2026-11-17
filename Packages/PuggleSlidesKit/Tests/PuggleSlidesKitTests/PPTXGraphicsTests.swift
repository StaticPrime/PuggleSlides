import Foundation
import Testing
@testable import PuggleSlidesKit

/// Word art, picture adjustments, guides, and animations of tables and charts.
struct PPTXGraphicsTests {
    typealias Package = PPTXTestPackage

    // MARK: Word art

    @Test func wordArtIsWrittenWithPaintedLetters() throws {
        let art = PPTXSamples.shape("Word art", SlideRect(x: 10, y: 20, width: 300, height: 100), Shape.wordArt("Puggle\nArt", fontFamily: "Georgia"))
        let presentation = PPTXTableTests.deck([art])
        let slide = try #require(try Package.writtenParts(presentation)["ppt/slides/slide1.xml"])
        // The box has no fill or line; the letters carry the shape's outline and fill.
        #expect(slide.contains("<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln w=\"9525\"><a:noFill/></a:ln></p:spPr>"))
        #expect(slide.contains("<a:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" fromWordArt=\"1\" anchor=\"ctr\">"
            + "<a:prstTxWarp prst=\"textPlain\"><a:avLst/></a:prstTxWarp><a:noAutofit/></a:bodyPr>"))
        let paint = "<a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln><a:solidFill><a:srgbClr val=\"CCCCCC\"/></a:solidFill>"
        #expect(slide.contains("<a:r><a:rPr sz=\"7200\">\(paint)<a:latin typeface=\"Georgia\"/></a:rPr><a:t>Puggle</a:t></a:r>"))
        #expect(slide.contains("<a:endParaRPr sz=\"7200\">\(paint)<a:latin typeface=\"Georgia\"/></a:endParaRPr></a:p>"))
        let file = try PPTXRoundTripTests.roundTrip(presentation)
        #expect(file.warnings.isEmpty)
        #expect(file.presentation.slides[0].elements[0].shape == art.shape)

        // Without a fill or an outline, runs carry only what they have.
        var bare = Shape.wordArt("Bare")
        bare.fill = nil
        bare.outline = nil
        let plain = try #require(try Package.writtenParts(PPTXTableTests.deck([PPTXSamples.shape("Bare", SlideRect(x: 0, y: 0, width: 100, height: 50), bare)]))["ppt/slides/slide1.xml"])
        #expect(plain.contains("<a:r><a:rPr sz=\"7200\"><a:latin typeface=\"Arial\"/></a:rPr><a:t>Bare</a:t></a:r>"))
        let read = try PPTXRoundTripTests.roundTrip(PPTXTableTests.deck([PPTXSamples.shape("Bare", SlideRect(x: 0, y: 0, width: 100, height: 50), bare)]))
        #expect(read.presentation.slides[0].elements[0].shape == bare)
    }

    @Test func powerPointWordArtReads() throws {
        let gradient = "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst>"
            + "<a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill>"
        // Text PowerPoint warps into an arch: word art, painted with its first run's fill and outline.
        let arch = PPTXReadTests.sp(4, "TextBox 3", properties: "<a:solidFill><a:srgbClr val=\"FFFF00\"/></a:solidFill>", text: PPTXReadTests.body(
            "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"5400\" b=\"1\"><a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"accent2\"/></a:solidFill></a:ln>"
                + "\(gradient)</a:rPr><a:t>Arch</a:t></a:r><a:r><a:rPr lang=\"en-US\" sz=\"5400\" b=\"1\"><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill>"
                + "</a:rPr><a:t>ed</a:t></a:r></a:p>",
            bodyPr: "<a:bodyPr wrap=\"square\" rtlCol=\"0\"><a:prstTxWarp prst=\"textArchUp\"><a:avLst/></a:prstTxWarp><a:spAutoFit/></a:bodyPr>"),
            textBox: true)
        // PowerPoint's "no warp" is ordinary text.
        let unwarped = PPTXReadTests.sp(5, "Plain", text: PPTXReadTests.body("<a:p><a:r><a:rPr><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill></a:rPr><a:t>x</a:t></a:r></a:p>",
                                                                            bodyPr: "<a:bodyPr><a:prstTxWarp prst=\"textNoShape\"><a:avLst/></a:prstTxWarp></a:bodyPr>"))
        // Word art without runs of its own color takes the text color the shape's style gives it.
        let styled = PPTXReadTests.sp(6, "Styled", style: "<p:style><a:lnRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\">"
            + "<a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\">"
            + "<a:schemeClr val=\"accent6\"/></a:fontRef></p:style>",
            text: PPTXReadTests.body("<a:p><a:r><a:t>styled</a:t></a:r></a:p>", bodyPr: "<a:bodyPr fromWordArt=\"1\"/>"))
        // Warped text in the color it inherits (here the master's other text style): its letters take that color.
        let inherited = PPTXReadTests.sp(7, "Inherited", text: PPTXReadTests.body("<a:p><a:r><a:rPr sz=\"4000\"/><a:t>arch</a:t></a:r></a:p>",
            bodyPr: "<a:bodyPr><a:prstTxWarp prst=\"textArchUp\"><a:avLst/></a:prstTxWarp></a:bodyPr>"))
        var package = Package()
        package.textStyles = "<p:titleStyle/><p:bodyStyle/><p:otherStyle><a:lvl1pPr><a:defRPr><a:solidFill><a:schemeClr val=\"accent3\"/></a:solidFill>"
            + "</a:defRPr></a:lvl1pPr></p:otherStyle>"
        package.slides = [Package.Slide(xml: Package.slide(arch + unwarped + styled + inherited))]
        let file = try PPTXReadTests.read(package)
        #expect(file.warnings.isEmpty)
        let shapes = file.presentation.slides[0].elements.compactMap(\.shape)
        let word = shapes[0]
        #expect(word.isWordArt && word.isTextBox)
        #expect(word.fill == .gradient(GradientFill(kind: .linear(angle: 90), stops: [
            GradientStop(position: 0, color: ColorRef(RGBColor(red: 255, green: 0, blue: 0))), GradientStop(position: 1, color: ColorRef(RGBColor(red: 0, green: 0, blue: 255))),
        ])))
        #expect(word.outline == .solid(ColorRef(theme: .accent2), width: 1))
        // The runs' own colors don't show in word art, so they go, and runs alike in everything else join.
        #expect(word.text?.paragraphs[0].runs == [TextRun("Arched", style: CharacterStyle(fontSize: 54, bold: true))])
        #expect(!shapes[1].isWordArt)
        #expect(shapes[1].text?.paragraphs[0].runs[0].style.color == ColorRef(RGBColor(red: 0, green: 255, blue: 0)))
        #expect(shapes[2].isWordArt && shapes[2].fill == .solid(ColorRef(theme: .accent6)) && shapes[2].outline == nil)
        #expect(shapes[3].isWordArt && shapes[3].fill == .solid(ColorRef(theme: .accent3)) && shapes[3].outline == nil)
    }

    // MARK: Picture adjustments

    @Test func pictureAdjustmentsAreWrittenAsBlipEffects() throws {
        var presentation = Presentation.makeDefault()
        let photo = presentation.addMedia(PPTXSamples.photo, contentType: "image/png")
        let adjustments: [ImageAdjustments] = [
            ImageAdjustments(transparency: 0.25, brightness: 0.2, contrast: -0.1, recolor: .light(.accent1)),
            ImageAdjustments(recolor: .dark(.dark2)), ImageAdjustments(recolor: .grayscale), ImageAdjustments(recolor: .negative),
            ImageAdjustments(recolor: .sepia), ImageAdjustments(transparency: 0.333),
            ImageAdjustments(recolor: .duotone(ColorRef(.theme(.accent3), lumMod: 0.5), ColorRef(RGBColor(red: 1, green: 2, blue: 3), alpha: 0.5))),
            .none,
        ]
        let elements = adjustments.enumerated().map { index, adjustment in
            SlideElement(name: "Photo \(index)", placement: Placement(frame: SlideRect(x: Double(index) * 60, y: 0, width: 50, height: 50)),
                         content: .picture(Picture(mediaID: photo, adjustments: adjustment)))
        }
        var deck = PPTXTableTests.deck(elements)
        deck.media = presentation.media
        let slide = try #require(try Package.writtenParts(deck)["ppt/slides/slide1.xml"])
        let blips = slide.matches(of: /<a:blip r:embed="rId\d+"(\/>|>.*?<\/a:blip>)/).map { String($0.1) }
        #expect(blips == [
            "><a:lum bright=\"20000\" contrast=\"-10000\"/><a:duotone><a:schemeClr val=\"accent1\"/><a:srgbClr val=\"FFFFFF\"/></a:duotone>"
                + "<a:alphaModFix amt=\"75000\"/></a:blip>",
            "><a:duotone><a:srgbClr val=\"000000\"/><a:schemeClr val=\"dk2\"/></a:duotone></a:blip>",
            "><a:grayscl/></a:blip>",
            "><a:duotone><a:srgbClr val=\"FFFFFF\"/><a:srgbClr val=\"000000\"/></a:duotone></a:blip>",
            "><a:duotone><a:srgbClr val=\"3B2A17\"/><a:srgbClr val=\"F4E8D0\"/></a:duotone></a:blip>",
            "><a:alphaModFix amt=\"66700\"/></a:blip>",
            "><a:duotone><a:schemeClr val=\"accent3\"><a:lumMod val=\"50000\"/></a:schemeClr><a:srgbClr val=\"010203\"><a:alpha val=\"50000\"/></a:srgbClr>"
                + "</a:duotone></a:blip>",
            "/>",
        ])
        // Read back to exactly the same values.
        let read = try PPTXRoundTripTests.roundTrip(deck).presentation.slides[0].elements.compactMap(\.picture).map(\.adjustments)
        #expect(read == adjustments)
    }

    @Test func powerPointsPictureEffectsRead() throws {
        func picture(_ id: Int, _ effects: String) -> String {
            "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId3\">\(effects)"
                + "</a:blip><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm></p:spPr></p:pic>"
        }
        var package = Package()
        package.media = ["ppt/media/image1.png": PPTXSamples.photo]
        package.slides = [Package.Slide(xml: Package.slide(
            // PowerPoint's Accent 1 light: a duotone from a shade of the accent, kept as it is.
            picture(2, "<a:duotone><a:schemeClr val=\"accent1\"><a:shade val=\"45000\"/><a:satMod val=\"135000\"/></a:schemeClr><a:prstClr val=\"white\"/></a:duotone>")
                // Black to a mapped theme color is a dark recolor; strict percentages read too.
                + picture(3, "<a:alphaModFix amt=\"50%\"/><a:duotone><a:prstClr val=\"black\"/><a:schemeClr val=\"bg2\"/></a:duotone>")
                // Washout, grayscale, and effects with no counterpart.
                + picture(4, "<a:grayscl/><a:lum bright=\"70000\" contrast=\"-70000\"/><a:biLevel thresh=\"50000\"/><a:blur rad=\"10\"/>")
                + picture(5, "<a:duotone><a:prstClr val=\"black\"/></a:duotone><a:alphaModFix/>")),
            relationships: [Package.Relationship("rId3", "image", "../media/image1.png")])]
        let file = try PPTXReadTests.read(package)
        #expect(file.warnings.isEmpty)
        let read = file.presentation.slides[0].elements.compactMap(\.picture).map(\.adjustments)
        #expect(read == [
            ImageAdjustments(recolor: .duotone(ColorRef(.theme(.accent1), shade: 0.45), .white)),
            ImageAdjustments(transparency: 0.5, recolor: .dark(.light2)),
            ImageAdjustments(brightness: 0.7, contrast: -0.7, recolor: .grayscale),
            .none,
        ])
    }

    // MARK: Guides

    @Test func guidesAreWrittenAsPowerPointKeepsThem() throws {
        let parts = try Package.writtenParts(PPTXSamples.rich())
        let presentation = try #require(parts["ppt/presentation.xml"])
        #expect(presentation.contains("</p:defaultTextStyle><p:extLst><p:ext uri=\"{EFAFB233-063F-42B5-8137-9DF3F51BA10A}\">"
            + "<p15:sldGuideLst xmlns:p15=\"http://schemas.microsoft.com/office/powerpoint/2012/main\"><p15:guide id=\"1\" pos=\"2880\" userDrawn=\"1\"/>"
            + "<p15:guide id=\"2\" orient=\"horz\" pos=\"1620\" userDrawn=\"1\"/><p15:guide id=\"3\" pos=\"289\" userDrawn=\"1\"><p15:clr>"
            + "<a:srgbClr val=\"FF0066\"/></p15:clr></p15:guide></p15:sldGuideLst></p:ext></p:extLst></p:presentation>"))
        #expect(!(try #require(try Package.writtenParts(Presentation.makeDefault())["ppt/presentation.xml"])).contains("extLst"))
        let read = try PPTXRoundTripTests.roundTrip(PPTXSamples.rich()).presentation.guides
        #expect(read.map(\.orientation) == [.vertical, .horizontal, .vertical])
        #expect(read.map(\.position) == [360, 202.5, 36.125])
        #expect(read.map(\.color) == [nil, nil, RGBColor(red: 0xFF, green: 0, blue: 0x66)])
    }

    @Test func powerPointsGuidesRead() throws {
        let p15 = "xmlns:p15=\"http://schemas.microsoft.com/office/powerpoint/2012/main\""
        var package = Package()
        package.presentationExtensions = "<p:extLst><p:ext uri=\"{EFAFB233-063F-42B5-8137-9DF3F51BA10A}\"><p15:sldGuideLst \(p15)>"
            + "<p15:guide id=\"1\" orient=\"horz\" pos=\"2160\" userDrawn=\"1\"><p15:clr><a:srgbClr val=\"A4A3A4\"/></p15:clr></p15:guide>"
            + "<p15:guide id=\"2\" pos=\"2880\"><p15:clr><a:schemeClr val=\"accent2\"/></p15:clr></p15:guide><p15:guide id=\"3\" pos=\"-80\"/></p15:sldGuideLst></p:ext>"
            + "<p:ext uri=\"{2D200454-40CA-4A62-9FC3-DE9A4176ACB9}\"><p15:notesGuideLst \(p15)><p15:guide id=\"9\" pos=\"1\"/></p15:notesGuideLst></p:ext></p:extLst>"
        // PowerPoint 2013's guides win over the older ones in the view properties.
        package.viewProperties = "<p:viewPr {NS}><p:slideViewPr><p:cSldViewPr><p:cViewPr><p:scale><a:sx n=\"1\" d=\"1\"/><a:sy n=\"1\" d=\"1\"/></p:scale>"
            + "<p:origin x=\"0\" y=\"0\"/></p:cViewPr><p:guideLst><p:guide orient=\"horz\" pos=\"100\"/></p:guideLst></p:cSldViewPr></p:slideViewPr></p:viewPr>"
        let guides = try PPTXReadTests.read(package).presentation.guides
        #expect(guides.map(\.orientation) == [.horizontal, .vertical, .vertical])
        #expect(guides.map(\.position) == [270, 360, -10])
        #expect(guides.map(\.color) == [RGBColor(hex: "A4A3A4"), RGBColor(hex: "ED7D31"), nil])

        package.presentationExtensions = ""
        let older = try PPTXReadTests.read(package).presentation.guides
        #expect(older.map(\.orientation) == [.horizontal] && older.map(\.position) == [12.5] && older[0].color == nil)
    }

    // MARK: Animations

    @Test func tablesAndChartsAnimate() throws {
        var deck = PPTXTableTests.deck([
            PPTXSamples.table("Table", at: SlidePoint(x: 20, y: 20), PPTXSamples.smallTable()),
            PPTXSamples.chart("Chart", SlideRect(x: 200, y: 20, width: 300, height: 200), PPTXSamples.salesChart(.pie)),
            PPTXSamples.shape("Art", SlideRect(x: 20, y: 250, width: 200, height: 80), Shape.wordArt("Art")),
        ])
        let ids = deck.slides[0].elements.map(\.id)
        deck.slides[0].animations = [
            SlideAnimation(elementID: ids[0], effect: .fadeIn),
            SlideAnimation(elementID: ids[1], effect: .zoomIn, start: .afterPrevious),
            SlideAnimation(elementID: ids[1], effect: .spin, start: .onClick, duration: 2),
            SlideAnimation(elementID: ids[2], effect: .flyInFromRight, start: .withPrevious, byParagraph: true),
        ]
        let slide = try #require(try Package.writtenParts(deck)["ppt/slides/slide1.xml"])
        // Charts are built as one, with a group of their own per effect; tables, like pictures, need no build entry.
        #expect(slide.contains("<p:bldLst><p:bldGraphic spid=\"3\" grpId=\"0\"><p:bldAsOne/></p:bldGraphic><p:bldGraphic spid=\"3\" grpId=\"1\">"
            + "<p:bldAsOne/></p:bldGraphic><p:bldP spid=\"4\" grpId=\"0\" build=\"p\" animBg=\"1\"/></p:bldLst>"))
        #expect(slide.contains("<p:spTgt spid=\"2\"/>"))
        let file = try PPTXRoundTripTests.roundTrip(deck)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(deck, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
    }
}
