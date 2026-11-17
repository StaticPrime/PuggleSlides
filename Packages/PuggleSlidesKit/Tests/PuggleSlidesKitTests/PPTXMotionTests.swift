import Foundation
import Testing
@testable import PuggleSlidesKit

/// Slide transitions and object animations, written as PowerPoint writes them and read back to the supported set.
struct PPTXMotionTests {
    typealias Package = PPTXTestPackage

    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        try PresentationIO.read(try PresentationIO.write(presentation, format: .pptx), format: .pptx)
    }

    /// A blank slide with a three-paragraph text box (the middle one empty), a filled rectangle with text, a picture,
    /// a group and a connector.
    static func stage() -> Presentation {
        var presentation = Presentation.makeDefault()
        let blank = presentation.themes[0].layout(kind: .blank)!
        var slide = presentation.makeSlide(layoutID: blank.id)
        let photo = presentation.addMedia(PPTXSamples.photo, contentType: "image/png")
        var points = TextBody(paragraphs: [TextParagraph("First"), TextParagraph(), TextParagraph("Third", level: 1)])
        points.properties.autofit = .resizeShape
        slide.elements = [
            PPTXSamples.shape("Points", SlideRect(x: 40, y: 40, width: 300, height: 120), Shape(fill: Fill.none, text: points, isTextBox: true)),
            PPTXSamples.shape("Box", SlideRect(x: 380, y: 40, width: 200, height: 100),
                              Shape(fill: .solid(ColorRef(theme: .accent1)), text: TextBody("Boxed"))),
            SlideElement(name: "Photo", placement: Placement(frame: SlideRect(x: 40, y: 200, width: 120, height: 90)), content: .picture(Picture(mediaID: photo))),
            PPTXGroupTransform.group([
                PPTXSamples.shape("A", SlideRect(x: 200, y: 200, width: 40, height: 40), Shape(fill: .solid(ColorRef(theme: .accent2)))),
                PPTXSamples.shape("B", SlideRect(x: 260, y: 220, width: 40, height: 40), Shape(fill: .solid(ColorRef(theme: .accent3)))),
            ], name: "Pair"),
            PPTXSamples.shape("Line", SlideRect(x: 400, y: 250, width: 150, height: 0),
                              Shape(geometry: .preset("straightConnector1", adjustments: [:]), outline: .solid(.black), isConnector: true)),
        ]
        presentation.slides = [slide]
        return presentation
    }

    // MARK: Round trips

    @Test(arguments: TransitionKind.allCases)
    func everyTransitionRoundTrips(_ kind: TransitionKind) throws {
        var presentation = Self.stage()
        presentation.slides[0].transition = SlideTransition(kind: kind, duration: 1.25)
        let second = presentation.duplicate(presentation.slides[0])
        presentation.slides.append(second)
        presentation.slides[1].transition = SlideTransition(kind: kind, duration: 0.3)
        let file = try Self.roundTrip(presentation)
        #expect(file.warnings.isEmpty)
        #expect(file.presentation.slides.map(\.transition) == [SlideTransition(kind: kind, duration: 1.25), SlideTransition(kind: kind, duration: 0.3)])
    }

    @Test func everyEffectAndStartRoundTrips() throws {
        var presentation = Self.stage()
        let ids = presentation.slides[0].elements.map(\.id)
        var animations: [SlideAnimation] = []
        for (index, effect) in AnimationEffect.allCases.enumerated() {
            for (offset, start) in AnimationStart.allCases.enumerated() {
                let number = index * 3 + offset
                let target = ids[number % ids.count]
                // By paragraph on the text box and the rectangle, every other time.
                let byParagraph = number % 5 < 2 && number % 2 == 0
                animations.append(SlideAnimation(elementID: target, effect: effect, start: start, duration: 0.25 * Double(number % 6 + 1),
                                                 delay: 0.125 * Double(number % 4), byParagraph: byParagraph))
            }
        }
        presentation.slides[0].animations = animations
        // A second slide that starts with an animation that doesn't wait for a click.
        var second = presentation.duplicate(presentation.slides[0])
        second.animations = [SlideAnimation(elementID: second.elements[1].id, effect: .zoomIn, start: .afterPrevious, duration: 1, delay: 0.5),
                             SlideAnimation(elementID: second.elements[0].id, effect: .flyInFromLeft, start: .withPrevious, byParagraph: true),
                             SlideAnimation(elementID: second.elements[2].id, effect: .spin, start: .onClick, duration: 2)]
        presentation.slides.append(second)

        let file = try Self.roundTrip(presentation)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(presentation, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        #expect(file.presentation.slides[0].animations.count == AnimationEffect.allCases.count * AnimationStart.allCases.count)
        // By-paragraph only means something for text.
        let read = file.presentation.slides[0]
        for animation in read.animations where animation.byParagraph {
            #expect(read.element(id: animation.elementID)?.shape?.text?.isEmpty == false)
        }
    }

    @Test func richDeckWithMotionRoundTrips() throws {
        let original = PPTXSamples.rich()
        #expect(original.slides.contains { !$0.animations.isEmpty } && original.slides.contains { $0.transition != nil })
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
    }

    // MARK: Writing

    static func slideXML(_ presentation: Presentation, slide: Int = 1) throws -> String {
        try #require(try Package.part("ppt/slides/slide\(slide).xml", of: try PPTXWriter.write(presentation)))
    }

    @Test func transitionsAreWrittenAsPowerPointWritesThem() throws {
        var presentation = Self.stage()
        presentation.slides[0].transition = SlideTransition(kind: .cube, duration: 0.8)
        var xml = try Self.slideXML(presentation)
        #expect(xml.contains("</p:clrMapOvr><mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\">"
            + "<mc:Choice xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" Requires=\"p14\">"
            + "<p:transition spd=\"med\" p14:dur=\"800\"><p14:prism/></p:transition></mc:Choice>"
            + "<mc:Fallback><p:transition spd=\"med\"><p:fade/></p:transition></mc:Fallback></mc:AlternateContent></p:sld>"))
        let expected: [(TransitionKind, Double, String, String)] = [
            (.slideFromRight, 0.5, "<p:transition spd=\"fast\" p14:dur=\"500\"><p:push dir=\"l\"/>", "<p:transition spd=\"fast\"><p:push dir=\"l\"/>"),
            (.slideFromLeft, 1, "<p:transition spd=\"slow\" p14:dur=\"1000\"><p:push dir=\"r\"/>", "<p:transition spd=\"slow\"><p:push dir=\"r\"/>"),
            (.flip, 0.75, "<p14:flip dir=\"r\"/>", "<p:transition spd=\"med\"><p:fade/>"),
            (.gallery, 2, "<p14:gallery dir=\"l\"/>", "<p:transition spd=\"slow\"><p:fade/>"),
            (.dissolve, 0.5, "<p:dissolve/>", "<p:transition spd=\"fast\"><p:dissolve/>"),
            (.none, 0.5, "<p:transition spd=\"fast\" p14:dur=\"500\"/>", "<mc:Fallback><p:transition spd=\"fast\"/>"),
        ]
        for (kind, duration, choice, fallback) in expected {
            presentation.slides[0].transition = SlideTransition(kind: kind, duration: duration)
            xml = try Self.slideXML(presentation)
            #expect(xml.contains(choice), "\(kind)")
            #expect(xml.contains(fallback), "\(kind)")
        }
    }

    @Test func timingTreesFollowPowerPointsLayout() throws {
        var presentation = Self.stage()
        let ids = presentation.slides[0].elements.map(\.id)
        presentation.slides[0].animations = [
            SlideAnimation(elementID: ids[1], effect: .fadeIn, start: .withPrevious, duration: 0.5),
            SlideAnimation(elementID: ids[2], effect: .flyInFromLeft, start: .afterPrevious, duration: 1, delay: 0.25),
            SlideAnimation(elementID: ids[3], effect: .appear, start: .afterPrevious),
            SlideAnimation(elementID: ids[1], effect: .zoomOut, start: .withPrevious, duration: 0.75),
            SlideAnimation(elementID: ids[0], effect: .fadeIn, start: .onClick, byParagraph: true),
            SlideAnimation(elementID: ids[1], effect: .spin, start: .onClick, duration: 2),
        ]
        let xml = try Self.slideXML(presentation)
        // The first group starts with the slide; the after-previous steps start where the one before ends:
        // 0.5 s, then 0.5 + 0.25 + 1 = 1.75 s (the instant appear adds nothing).
        #expect(xml.contains("<p:cond delay=\"indefinite\"/><p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>"))
        #expect(xml.matches(of: /<p:cTn id="\d+" fill="hold"><p:stCondLst><p:cond delay="(\d+)"\/><\/p:stCondLst>/).map { String($0.1) }
            == ["0", "500", "1750", "0", "0", "0"])
        // Effects carry their preset, build group (shapes only) and start.
        #expect(xml.contains("presetID=\"10\" presetClass=\"entr\" presetSubtype=\"0\" fill=\"hold\" grpId=\"0\" nodeType=\"withEffect\""))
        #expect(xml.contains("presetID=\"2\" presetClass=\"entr\" presetSubtype=\"8\" fill=\"hold\" nodeType=\"afterEffect\"><p:stCondLst><p:cond delay=\"250\"/>"))
        #expect(xml.contains("presetID=\"53\" presetClass=\"exit\" presetSubtype=\"32\" fill=\"hold\" grpId=\"1\" nodeType=\"withEffect\""))
        #expect(xml.contains("presetID=\"8\" presetClass=\"emph\" presetSubtype=\"0\" fill=\"hold\" grpId=\"2\" nodeType=\"clickEffect\""))
        #expect(xml.contains("<p:animRot by=\"21600000\"><p:cBhvr><p:cTn id=\"" ) && xml.contains("dur=\"2000\" fill=\"hold\"/><p:tgtEl><p:spTgt spid=\"3\"/>"))
        // By paragraph: one click per paragraph with text (paragraphs 0 and 2), each aimed at its paragraph.
        #expect(xml.contains("<p:spTgt spid=\"2\"><p:txEl><p:pRg st=\"0\" end=\"0\"/></p:txEl></p:spTgt>"))
        #expect(xml.contains("<p:spTgt spid=\"2\"><p:txEl><p:pRg st=\"2\" end=\"2\"/></p:txEl></p:spTgt>"))
        #expect(!xml.contains("<p:pRg st=\"1\""))
        #expect(xml.matches(of: /nodeType="clickEffect"/).count == 3)
        // Fades and fly-outs hide the element at their end; the fly animates both coordinates from off the slide.
        #expect(xml.contains("<p:animEffect transition=\"out\" filter=\"fade\"><p:cBhvr><p:cTn id=\""))
        #expect(xml.contains("<p:cond delay=\"749\"/></p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid=\"3\"/></p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName>"))
        #expect(xml.contains("<p:strVal val=\"0-#ppt_w/2\"/>"))
        // Builds: the rectangle (filled, so its background builds too) as a whole, the text box by paragraph
        // (two levels deep); nothing for the picture and the group.
        #expect(xml.contains("<p:bldLst><p:bldP spid=\"3\" grpId=\"0\" animBg=\"1\"/><p:bldP spid=\"3\" grpId=\"1\" animBg=\"1\"/>"
            + "<p:bldP spid=\"2\" grpId=\"0\" build=\"p\" bldLvl=\"2\"/><p:bldP spid=\"3\" grpId=\"2\" animBg=\"1\"/></p:bldLst>"))
        // cTn ids are unique.
        let ids2 = xml.matches(of: /<p:cTn id="(\d+)"/).map { Int($0.1)! }
        #expect(Set(ids2).count == ids2.count && ids2.first == 1)
    }

    @Test func animationsOfMissingElementsAreLeftOut() throws {
        var presentation = Self.stage()
        presentation.slides[0].animations = [SlideAnimation(elementID: UUID(), effect: .fadeIn),
                                             SlideAnimation(elementID: presentation.slides[0].elements[3].children![0].id, effect: .fadeIn)]
        let xml = try Self.slideXML(presentation)
        #expect(!xml.contains("<p:timing>"))
        #expect(try Self.roundTrip(presentation).presentation.slides[0].animations.isEmpty)
    }

    // MARK: Reading PowerPoint's files

    /// A timing tree in PowerPoint's layout, from a list of click groups of steps of effect nodes.
    static func timing(_ groups: [[[String]]], startsWithSlide: Bool = false, builds: String = "") -> String {
        var id = 2
        func next() -> Int { id += 1; return id }
        var xml = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst><p:seq concurrent=\"1\" "
            + "nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>"
        for (index, group) in groups.enumerated() {
            let begin = index == 0 && startsWithSlide ? "<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>" : ""
            xml += "<p:par><p:cTn id=\"\(next())\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/>\(begin)</p:stCondLst><p:childTnLst>"
            for (number, step) in group.enumerated() {
                xml += "<p:par><p:cTn id=\"\(next())\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(number * 1000)\"/></p:stCondLst><p:childTnLst>"
                xml += step.joined() + "</p:childTnLst></p:cTn></p:par>"
            }
            xml += "</p:childTnLst></p:cTn></p:par>"
        }
        return xml + "</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
            + "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq></p:childTnLst></p:cTn></p:par>"
            + "</p:tnLst>\(builds)</p:timing>"
    }

    /// One effect node: `behaviors` given as (element, attributes, duration, delay) and the target.
    static func effect(_ presetClass: String, _ id: Int, _ subtype: Int = 0, node: String, delay: Int = 0, group: Int? = nil,
                       spid: Int, paragraph: Int? = nil, behaviors: [String]) -> String {
        let target = "<p:spTgt spid=\"\(spid)\"" + (paragraph.map { "><p:txEl><p:pRg st=\"\($0)\" end=\"\($0)\"/></p:txEl></p:spTgt>" } ?? "/>")
        return "<p:par><p:cTn id=\"99\" presetID=\"\(id)\" presetClass=\"\(presetClass)\" presetSubtype=\"\(subtype)\" fill=\"hold\""
            + (group.map { " grpId=\"\($0)\"" } ?? "") + " nodeType=\"\(node)\"><p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst><p:childTnLst>"
            + behaviors.joined().replacingOccurrences(of: "{T}", with: target) + "</p:childTnLst></p:cTn></p:par>"
    }

    static func show(at delay: Int = 0, _ value: String = "visible") -> String {
        "<p:set><p:cBhvr><p:cTn id=\"99\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst></p:cTn><p:tgtEl>{T}</p:tgtEl>"
            + "<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"\(value)\"/></p:to></p:set>"
    }

    static func fade(_ duration: Int, _ transition: String = "in", filter: String = "fade") -> String {
        "<p:animEffect transition=\"\(transition)\" filter=\"\(filter)\"><p:cBhvr><p:cTn id=\"99\" dur=\"\(duration)\"/><p:tgtEl>{T}</p:tgtEl></p:cBhvr></p:animEffect>"
    }

    static func move(_ attribute: String, _ duration: Int) -> String {
        "<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr additive=\"base\"><p:cTn id=\"99\" dur=\"\(duration)\" fill=\"hold\"/><p:tgtEl>{T}</p:tgtEl>"
            + "<p:attrNameLst><p:attrName>\(attribute)</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst><p:tav tm=\"0\"><p:val><p:strVal val=\"#\(attribute)\"/>"
            + "</p:val></p:tav><p:tav tm=\"100000\"><p:val><p:strVal val=\"#\(attribute)\"/></p:val></p:tav></p:tavLst></p:anim>"
    }

    static let shapes = PPTXReadTests.sp(2, "Title", ph: "<p:ph type=\"title\"/>",
                                         text: PPTXReadTests.body("<a:p><a:r><a:t>One</a:t></a:r></a:p><a:p><a:r><a:t>Two</a:t></a:r></a:p>"))
        + PPTXReadTests.sp(3, "Box", properties: "<a:solidFill><a:srgbClr val=\"4472C4\"/></a:solidFill>",
                           text: PPTXReadTests.body("<a:p><a:r><a:t>Box</a:t></a:r></a:p>"))
        + PPTXReadTests.sp(4, "Plain", text: PPTXReadTests.body("<a:p><a:r><a:t>Plain</a:t></a:r></a:p>"))

    static func read(_ timing: String, transition: String = "") throws -> PresentationFile {
        var package = Package()
        package.slides = [Package.Slide(xml: Package.slide(shapes, after: transition + timing))]
        return try Package.read(try package.data())
    }

    @Test func readsPowerPointTimingTrees() throws {
        let timing = Self.timing([
            [[Self.effect("entr", 10, node: "clickEffect", group: 0, spid: 3, behaviors: [Self.show(), Self.fade(500)]),
              Self.effect("entr", 2, 8, node: "withEffect", delay: 250, spid: 4, behaviors: [Self.show(), Self.move("ppt_x", 750), Self.move("ppt_y", 750)])],
             [Self.effect("entr", 53, 528, node: "afterEffect", group: 0, spid: 2, behaviors: [Self.show(), Self.fade(1500)])]],
            [[Self.effect("entr", 1, node: "clickEffect", group: 1, spid: 2, paragraph: 0, behaviors: [Self.show()])]],
            [[Self.effect("entr", 1, node: "clickEffect", group: 1, spid: 2, paragraph: 1, behaviors: [Self.show()])]],
            [[Self.effect("emph", 8, node: "clickEffect", group: 1, spid: 3,
                          behaviors: ["<p:animRot by=\"21600000\"><p:cBhvr><p:cTn id=\"99\" dur=\"2000\" fill=\"hold\"/><p:tgtEl>{T}</p:tgtEl></p:cBhvr></p:animRot>"])],
             [Self.effect("exit", 2, 4, node: "afterEffect", spid: 4, behaviors: [Self.move("ppt_x", 400), Self.move("ppt_y", 400), Self.show(at: 399, "hidden")])]],
            // Unsupported effects, mapped to the nearest of the same kind.
            [[Self.effect("entr", 22, 1, node: "clickEffect", group: 2, spid: 3, behaviors: [Self.show(), Self.fade(500, filter: "wipe(up)")]),
              Self.effect("entr", 42, node: "withEffect", group: 2, spid: 4, behaviors: [Self.show(), Self.fade(1000)]),
              Self.effect("exit", 51, node: "withEffect", group: 3, spid: 3, behaviors: [Self.fade(770, "out"), Self.show(at: 769, "hidden")]),
              Self.effect("exit", 14, node: "withEffect", spid: 4, behaviors: [Self.fade(500, "out", filter: "randombar(horizontal)"), Self.show(at: 499, "hidden")])]],
        ], builds: "<p:bldLst><p:bldP spid=\"3\" grpId=\"0\" animBg=\"1\"/><p:bldP spid=\"2\" grpId=\"0\"/><p:bldP spid=\"2\" grpId=\"1\" build=\"p\"/></p:bldLst>")
        let file = try Self.read(timing)
        #expect(file.warnings.isEmpty)
        let slide = file.presentation.slides[0]
        let title = slide.elements[0].id, box = slide.elements[1].id, plain = slide.elements[2].id
        #expect(slide.animations.map(\.elementID) == [box, plain, title, title, box, plain, box, plain, box, plain])
        #expect(slide.animations.map(\.effect) == [.fadeIn, .flyInFromLeft, .zoomIn, .appear, .spin, .flyOutToBottom, .fadeIn, .flyInFromBottom, .zoomOut, .fadeOut])
        #expect(slide.animations.map(\.start) == [.onClick, .withPrevious, .afterPrevious, .onClick, .onClick, .afterPrevious, .onClick, .withPrevious,
                                                  .withPrevious, .withPrevious])
        #expect(slide.animations.map(\.duration) == [0.5, 0.75, 1.5, 0.5, 2, 0.4, 0.5, 1, 0.77, 0.5])
        #expect(slide.animations.map(\.delay) == [0, 0.25, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(slide.animations.map(\.byParagraph) == [false, false, false, true, false, false, false, false, false, false])
    }

    @Test func treesWithoutPresetsOrNodeTypesAreInferred() throws {
        // Some apps leave out presets and node types: the click group decides the start, the behaviors the effect.
        let bare = { (spid: Int, behaviors: [String]) -> String in
            "<p:par><p:cTn id=\"99\" fill=\"hold\"><p:childTnLst>" + behaviors.joined().replacingOccurrences(of: "{T}", with: "<p:spTgt spid=\"\(spid)\"/>")
                + "</p:childTnLst></p:cTn></p:par>"
        }
        let timing = Self.timing([[[bare(3, [Self.show(), Self.fade(600)]), bare(4, [Self.show()])], [bare(2, [Self.fade(300, "out"), Self.show(at: 299, "hidden")])]],
                                  [[bare(3, ["<p:animRot by=\"-21600000\"><p:cBhvr><p:cTn id=\"99\" dur=\"900\"/><p:tgtEl>{T}</p:tgtEl></p:cBhvr></p:animRot>"])]]],
                                 startsWithSlide: true)
        let file = try Self.read(timing)
        #expect(file.warnings.isEmpty)
        let animations = file.presentation.slides[0].animations
        #expect(animations.map(\.effect) == [.fadeIn, .appear, .fadeOut, .spin])
        #expect(animations.map(\.start) == [.withPrevious, .withPrevious, .afterPrevious, .onClick])
        #expect(animations.map(\.duration) == [0.6, 0.5, 0.3, 0.9])
    }

    @Test func motionThatCannotBeKeptWarns() throws {
        let supported = Self.effect("entr", 10, node: "clickEffect", group: 0, spid: 3, behaviors: [Self.show(), Self.fade(500)])
        let cases: [(String, String)] = [
            ("motion path", Self.effect("path", 1, node: "clickEffect", spid: 4,
                                        behaviors: ["<p:animMotion origin=\"layout\" path=\"M 0 0 L 0.25 0.25 E\" pathEditMode=\"relative\"><p:cBhvr>"
                                            + "<p:cTn id=\"99\" dur=\"2000\" fill=\"hold\"/><p:tgtEl>{T}</p:tgtEl></p:cBhvr></p:animMotion>"])),
            ("grow and shrink", Self.effect("emph", 6, node: "clickEffect", group: 1, spid: 3,
                                            behaviors: ["<p:animScale><p:cBhvr><p:cTn id=\"99\" dur=\"2000\" fill=\"hold\"/><p:tgtEl>{T}</p:tgtEl></p:cBhvr>"
                                                + "<p:by x=\"150000\" y=\"150000\"/></p:animScale>"])),
            ("missing shape", Self.effect("entr", 10, node: "clickEffect", spid: 42, behaviors: [Self.show(), Self.fade(500)])),
            ("one paragraph of two", Self.effect("entr", 10, node: "clickEffect", group: 2, spid: 2, paragraph: 1, behaviors: [Self.show(), Self.fade(500)])),
            ("by letter", Self.effect("entr", 10, node: "clickEffect", spid: 4,
                                      behaviors: ["<p:set><p:cBhvr><p:cTn id=\"99\" dur=\"1\"/><p:tgtEl><p:spTgt spid=\"4\"><p:txEl><p:charRg st=\"0\" end=\"3\"/>"
                                          + "</p:txEl></p:spTgt></p:tgtEl></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set>"])),
        ]
        for (name, unsupported) in cases {
            let file = try Self.read(Self.timing([[[supported]], [[unsupported]]]))
            #expect(file.warnings == [.animations], "\(name)")
            #expect(file.presentation.slides[0].animations.first?.effect == .fadeIn, "\(name)")
        }

        // A trigger (an effect that plays when a shape is clicked) can't be kept; the main sequence still is.
        let trigger = "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"50\" restart=\"whenNotActive\" fill=\"hold\" evtFilter=\"cancelBubble\" "
            + "nodeType=\"interactiveSeq\"><p:stCondLst><p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"4\"/></p:tgtEl></p:cond></p:stCondLst>"
            + "<p:childTnLst><p:par><p:cTn id=\"51\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
            + Self.effect("entr", 10, node: "clickEffect", spid: 3, behaviors: [Self.show(), Self.fade(500)])
            + "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn><p:nextCondLst><p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"4\"/></p:tgtEl>"
            + "</p:cond></p:nextCondLst></p:seq>"
        let withTrigger = Self.timing([[[supported]]]).replacingOccurrences(of: "</p:seq></p:childTnLst></p:cTn></p:par></p:tnLst>",
                                                                            with: "</p:seq>\(trigger)</p:childTnLst></p:cTn></p:par></p:tnLst>")
        let file = try Self.read(withTrigger)
        #expect(file.warnings == [.animations])
        #expect(file.presentation.slides[0].animations.count == 1)

        // Transition sounds and automatic advance can't be kept; the transition itself is.
        let advance = try Self.read("", transition: "<p:transition spd=\"med\" advTm=\"3000\"><p:wipe dir=\"r\"/></p:transition>")
        #expect(advance.warnings == [.transitions])
        #expect(advance.presentation.slides[0].transition == SlideTransition(kind: .slideFromLeft, duration: 0.75))
    }

    @Test func readsPowerPointTransitions() throws {
        let choice = { (transition: String, fallback: String) -> String in
            "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice xmlns:p14=\"" + PPTXTransitions.powerPoint2010
                + "\" Requires=\"p14\">\(transition)</mc:Choice><mc:Fallback>\(fallback)</mc:Fallback></mc:AlternateContent>"
        }
        let cases: [(String, SlideTransition?)] = [
            ("", nil),
            ("<p:transition><p:fade/></p:transition>", SlideTransition(kind: .fade, duration: 0.5)),
            ("<p:transition spd=\"slow\"><p:fade thruBlk=\"1\"/></p:transition>", SlideTransition(kind: .fade, duration: 1)),
            ("<p:transition spd=\"med\"><p:dissolve/></p:transition>", SlideTransition(kind: .dissolve, duration: 0.75)),
            ("<p:transition><p:randomBar dir=\"vert\"/></p:transition>", SlideTransition(kind: .dissolve)),
            ("<p:transition><p:push/></p:transition>", SlideTransition(kind: .slideFromRight)),
            ("<p:transition><p:push dir=\"r\"/></p:transition>", SlideTransition(kind: .slideFromLeft)),
            ("<p:transition><p:push dir=\"u\"/></p:transition>", SlideTransition(kind: .slideFromRight)),
            ("<p:transition><p:cover dir=\"rd\"/></p:transition>", SlideTransition(kind: .slideFromLeft)),
            ("<p:transition><p:pull dir=\"lu\"/></p:transition>", SlideTransition(kind: .slideFromRight)),
            ("<p:transition><p:cut/></p:transition>", SlideTransition(kind: .none)),
            ("<p:transition spd=\"slow\"/>", SlideTransition(kind: .none, duration: 1)),
            ("<p:transition><p:zoom/></p:transition>", SlideTransition(kind: .fade)),
            (choice("<p:transition spd=\"slow\" p14:dur=\"1250\"><p14:prism isInverted=\"1\"/></p:transition>",
                    "<p:transition spd=\"slow\"><p:fade/></p:transition>"), SlideTransition(kind: .cube, duration: 1.25)),
            (choice("<p:transition spd=\"med\" p14:dur=\"700\"><p:fade/></p:transition>", "<p:transition spd=\"med\"><p:fade/></p:transition>"),
             SlideTransition(kind: .fade, duration: 0.7)),
            (choice("<p:transition p14:dur=\"2000\"><p14:vortex dir=\"r\"/></p:transition>", "<p:transition><p:fade/></p:transition>"),
             SlideTransition(kind: .dissolve, duration: 2)),
            (choice("<p:transition p14:dur=\"1600\"><p14:conveyor dir=\"r\"/></p:transition>", "<p:transition><p:fade/></p:transition>"),
             SlideTransition(kind: .slideFromLeft, duration: 1.6)),
            (choice("<p:transition p14:dur=\"1000\"><p14:switch dir=\"l\"/></p:transition>", "<p:transition><p:fade/></p:transition>"),
             SlideTransition(kind: .flip, duration: 1)),
            // PowerPoint 2013 and 2016 transitions name their own namespace in the choice.
            ("<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice "
                + "xmlns:p15=\"http://schemas.microsoft.com/office/powerpoint/2012/main\" Requires=\"p15\"><p:transition spd=\"slow\" "
                + "xmlns:p14=\"\(PPTXTransitions.powerPoint2010)\" p14:dur=\"1500\"><p15:prstTrans prst=\"pageCurlDouble\"/></p:transition></mc:Choice>"
                + "<mc:Fallback><p:transition spd=\"slow\"><p:fade/></p:transition></mc:Fallback></mc:AlternateContent>", SlideTransition(kind: .flip, duration: 1.5)),
            ("<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice "
                + "xmlns:p159=\"http://schemas.microsoft.com/office/powerpoint/2015/09/main\" Requires=\"p159\"><p:transition spd=\"slow\" "
                + "xmlns:p14=\"\(PPTXTransitions.powerPoint2010)\" p14:dur=\"2000\"><p159:morph option=\"byObject\"/></p:transition></mc:Choice>"
                + "<mc:Fallback><p:transition spd=\"slow\"><p:fade/></p:transition></mc:Fallback></mc:AlternateContent>", SlideTransition(kind: .fade, duration: 2)),
        ]
        for (xml, expected) in cases {
            let file = try Self.read("", transition: xml)
            #expect(file.warnings.isEmpty, "\(xml)")
            #expect(file.presentation.slides[0].transition == expected, "\(xml)")
        }
    }

    @Test func layoutsWithAnimationsWarn() throws {
        var package = Package()
        let animated = Self.timing([[[Self.effect("entr", 10, node: "clickEffect", spid: 2, behaviors: [Self.show(), Self.fade(500)])]]])
        package.layouts = [Package.layout(type: "blank", name: "Blank", tree: "").replacingOccurrences(of: "</p:sldLayout>", with: animated + "</p:sldLayout>")]
        package.slides = [Package.Slide(xml: Package.slide(""))]
        #expect(try Package.read(try package.data()).warnings == [.animations])
    }
}
