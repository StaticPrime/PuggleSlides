import Foundation
import Testing
@testable import PuggleSlidesKit

/// Reading files made by LibreOffice Impress and other apps.
struct ODPReadTests {
    static func readFixture() throws -> PresentationFile {
        try PresentationIO.read(try ODPLibreOfficeFixture.package(), format: .odp)
    }

    static func points(_ centimeters: Double) -> Double { centimeters * 72 / 2.54 }

    @Test func readsLibreOfficeMastersAsThemes() throws {
        let file = try Self.readFixture()
        #expect(file.warnings == [.tables, .charts, .video, .animations])
        let presentation = file.presentation
        // The comment on the third page is kept: about the page, without a place or a date.
        #expect(presentation.slides[2].comments.map { $0.comments.map(\.author) } == [["Someone"]])
        #expect(presentation.slides[2].comments.first?.first?.text == "A comment")
        #expect(presentation.slides[2].comments.first?.elementID == nil)
        #expect(presentation.title == "Made in Impress")
        #expect(abs(presentation.slideSize.width - Self.points(28)) < 0.01 && abs(presentation.slideSize.height - Self.points(15.75)) < 0.01)
        let theme = try #require(presentation.themes.first)
        #expect(presentation.themes.count == 1)
        #expect(theme.name == "Default")
        #expect(theme.colors[.accent1] == RGBColor(hex: "18A303"))
        #expect(theme.colors[.followedHyperlink] == RGBColor(hex: "551A8B"))
        #expect(theme.fonts.major == "Liberation Sans" && theme.fonts.minor == "Liberation Sans")
        #expect(theme.background == .solid(ColorRef(RGBColor(hex: "FFFFF0")!)))
        // The master's text styles: a centered 44 pt title, and outline levels with LibreOffice's bullets and indents.
        #expect(theme.titleStyle[0].character.fontSize == 44)
        #expect(theme.titleStyle[0].paragraph.alignment == .center)
        #expect(theme.bodyStyle[0].character.fontSize == 32)
        #expect(theme.bodyStyle[1].character.fontSize == 28)
        #expect(theme.bodyStyle[2].character.fontSize == 24)
        #expect(theme.bodyStyle[0].paragraph.bullet == .character("●"))
        #expect(theme.bodyStyle[1].paragraph.bullet == .character("–"))
        #expect(theme.bodyStyle[0].paragraph.bulletFont == "OpenSymbol")
        #expect(theme.bodyStyle[0].paragraph.bulletSize == 0.45)
        #expect(abs((theme.bodyStyle[0].paragraph.marginLeft ?? 0) - Self.points(1.2)) < 0.01)
        #expect(abs((theme.bodyStyle[0].paragraph.indent ?? 0) + Self.points(0.9)) < 0.01)
        #expect(theme.bodyStyle[0].paragraph.spaceBefore.map { abs($0 - Self.points(0.5)) < 0.01 } == true)
        #expect(theme.otherStyle[0].character.fontFamily == "Liberation Sans" && theme.otherStyle[0].character.fontSize == 18)
        // Decorations and placeholders of the master.
        #expect(theme.elements.map { $0.placeholder?.type } == [nil, .title, .body, .date, .footer, .slideNumber])
        #expect(theme.elements[0].name == "Stripe")
        #expect(theme.elements[0].shape?.fill == .solid(ColorRef(RGBColor(hex: "18A303")!)))
        #expect(theme.elements[1].shape?.text?.properties.anchor == .middle)
        // LibreOffice's basic layouts, plus one for a slide that hides the master's decorations.
        #expect(theme.layouts.map(\.kind) == [.title, .titleAndBody, .titleAndTwoColumns, .titleOnly, .blank, .custom])
        #expect(theme.layouts.last?.showsThemeElements == false)
        // Layouts take their placeholders' places from the slides that use them.
        let titleSlide = theme.layouts[0]
        #expect(titleSlide.elements.map { $0.placeholder?.type } == [.centeredTitle, .subtitle, .slideNumber])
        #expect(abs((titleSlide.elements[1].placement?.frame.y ?? 0) - Self.points(5.838)) < 0.01)
    }

    @Test func readsLibreOfficeSlides() throws {
        let presentation = try Self.readFixture().presentation
        #expect(presentation.slides.count == 4)
        let kinds = presentation.slides.map { presentation.layout(for: $0)?.kind }
        #expect(kinds == [.title, .titleAndBody, .blank, .custom])

        // 1. A title slide whose page shows the master's footer, date and slide number.
        let first = presentation.slides[0]
        #expect(first.elements.map { $0.placeholder?.type } == [.centeredTitle, .subtitle, .slideNumber, .footer, .date])
        #expect(first.elements.prefix(2).allSatisfy { $0.placement == nil })
        #expect(first.elements[0].shape?.text?.paragraphs[0].runs == [TextRun("Welcome to "), TextRun("LibreOffice", style: CharacterStyle(bold: true))])
        #expect(first.elements[1].shape?.text?.paragraphs[0].style == ParagraphStyle())
        #expect(first.elements[3].shape?.text?.plainText == "Company confidential")
        #expect(first.elements[2].shape?.text?.paragraphs[0].runs.first?.field == .slideNumber)
        #expect(first.transition == SlideTransition(kind: .fade, duration: 2))
        #expect(first.animations.map(\.effect) == [.appear])
        #expect(first.animations.first?.elementID == first.elements[0].id)
        // Notes keep LibreOffice's notes style (20 pt) on their text.
        #expect(first.notes.plainText == "Remember to smile.")
        #expect(first.notes.paragraphs[0].runs.map(\.style.bold) == [nil, true, nil])
        #expect(first.notes.paragraphs[0].runs.allSatisfy { $0.style.fontSize == 20 })

        // 2. Lists: levels, numbering, a paragraph without a bullet, links, spacing, tabs and line breaks.
        let lists = presentation.slides[1]
        let body = try #require(lists.elements[1].shape?.text)
        #expect(body.paragraphs.map(\.level) == [0, 1, 0, 0, 0, 1])
        #expect(body.paragraphs[0].text == "First point   spaced\ttab")
        #expect(body.paragraphs[0].style.bullet == nil)
        #expect(body.paragraphs[1].text == "Second level\u{2028}new line")
        #expect(body.paragraphs[1].runs[1].style == CharacterStyle(underline: true, color: ColorRef(RGBColor(hex: "C9211E")!)))
        #expect(body.paragraphs[2].style.bullet == Bullet.none)
        #expect(body.paragraphs[3].style.bullet == .number(.arabicPeriod, startAt: 1))
        #expect(body.paragraphs[5].style.bullet == .number(.alphaLcParenBoth, startAt: 2))
        #expect(body.paragraphs[5].runs[1].style == CharacterStyle(italic: true, baseline: .superscript))
        #expect(body.paragraphs[4].runs[1].style.link == .url("https://www.libreoffice.org/"))
        #expect(body.paragraphs[4].runs[3].style.link == .slide(presentation.slides[2].id))
        let resolved = presentation.style(for: lists.elements[1], on: lists).resolvedParagraphs()
        #expect(resolved.map { $0.bullet?.text } == ["●", "–", nil, "1.", "2.", "(b)"])
        #expect(lists.animations.count == 1)
        #expect(lists.animations.first?.effect == .fadeIn)
        #expect(lists.animations.first?.byParagraph == true)
        #expect(lists.notes.isEmpty)

        // 3. Hidden, pushed in from the left, and full of shapes.
        let shapes = presentation.slides[2]
        #expect(shapes.isSkipped)
        #expect(shapes.transition == SlideTransition(kind: .slideFromLeft, duration: 0.5))
        #expect(shapes.animations.map(\.effect) == [.flyInFromLeft, .spin, .flyOutToBottom])
        #expect(shapes.animations.map(\.start) == [.afterPrevious, .withPrevious, .withPrevious])
        #expect(shapes.animations.map(\.duration) == [1, 2, 0.75])
        #expect(shapes.animations[0].delay == 0.5)
        #expect(shapes.animations[1].elementID == shapes.elements.first { $0.name == "Pair" }?.id)

        // 4. A gradient background, a cube transition and the master's decorations hidden.
        let last = presentation.slides[3]
        guard case .gradient(let gradient)? = last.background, case .linear(let angle) = gradient.kind else {
            Issue.record("expected a linear gradient background")
            return
        }
        #expect(angle == 60)
        #expect(gradient.stops.map(\.color) == [ColorRef(RGBColor(hex: "FF0000")!), ColorRef(RGBColor(hex: "0000FF")!)])
        #expect(last.transition == SlideTransition(kind: .cube, duration: 1))
        #expect(presentation.backdropElements(for: last).isEmpty)
    }

    @Test func readsLibreOfficeShapes() throws {
        let slide = try Self.readFixture().presentation.slides[2]
        func element(_ name: String) throws -> SlideElement { try #require(slide.elements.first { $0.name == name }) }
        // LibreOffice's rounded rectangle draws as DrawingML's in a square; stretched, it's its own outline.
        #expect(try element("Rounded").shape?.geometry == .preset("roundRect", adjustments: [:]))
        guard case .custom(let pill)? = try element("Pill").shape?.geometry else {
            Issue.record("expected a custom outline")
            return
        }
        #expect(pill.paths.count == 1)
        let callout = try element("From PowerPoint")
        #expect(callout.shape?.geometry == .preset("wedgeRoundRectCallout", adjustments: ["adj1": -20833, "adj2": 62500, "adj3": 16667]))
        #expect(abs((callout.placement?.rotation ?? 0) - 330) < 0.001)
        let oval = try element("Oval")
        #expect(oval.shape?.geometry == .preset("ellipse", adjustments: [:]))
        #expect(oval.placement?.flipVertical == true)
        #expect(oval.shape?.fill?.mediaID != nil)
        guard case .custom(let freeform)? = try element("Freeform").shape?.geometry else {
            Issue.record("expected a custom outline")
            return
        }
        #expect(freeform.paths.map(\.fill) == [.normal, PathFillMode.none])
        #expect(freeform.textRect == TextInsetFractions(left: 0.1, top: 0.1, right: 0.1, bottom: 0.1))
        #expect(try element("Old rectangle").shape?.geometry == .preset("roundRect", adjustments: ["adj": 25000]))
        #expect(try element("Pie").shape?.geometry == .preset("pie", adjustments: ["adj1": 16_200_000, "adj2": 0]))
        if case .custom(let triangle)? = try element("Triangle").shape?.geometry {
            #expect(triangle.paths.first?.commands.count == 4)
        } else {
            Issue.record("expected a polygon")
        }
        let line = try element("Arrow line")
        #expect(line.shape?.geometry == .line)
        #expect(line.placement?.flipVertical == true)
        #expect(line.shape?.outline?.head == .fillCircle && line.shape?.outline?.tail == .fillArrow)
        #expect(line.shape?.outline?.dash == .longDash)
        let elbow = try element("Elbow")
        #expect(elbow.shape?.geometry.presetName == "bentConnector3" && elbow.shape?.isConnector == true)
        #expect(try element("Pair").children?.count == 2)
        let photo = try element("Photo")
        #expect(photo.picture?.crop == ImageCrop(left: 0.25))
        #expect(photo.placement?.flipHorizontal == true)
        #expect(photo.altTitle == "Photo" && photo.altDescription == "Red and blue")
        let box = try element("Text box")
        #expect(box.shape?.isTextBox == true)
        #expect(box.shape?.text?.properties.autofit == .resizeShape)
        #expect(box.shape?.outline?.isVisible == false)
        // An empty table, a chart object that isn't a chart, and videos can't be shown.
        #expect(!slide.elements.contains { ["Table", "Chart", "Movie"].contains($0.name) })
    }

    @Test func readsAnyNamespacePrefixes() throws {
        // The same file with other prefixes for the drawing, text and style namespaces.
        func renamed(_ xml: String) -> String {
            xml.replacingOccurrences(of: "xmlns:draw=", with: "xmlns:d=").replacingOccurrences(of: "<draw:", with: "<d:")
                .replacingOccurrences(of: "</draw:", with: "</d:").replacingOccurrences(of: " draw:", with: " d:")
                .replacingOccurrences(of: "xmlns:text=", with: "xmlns:t=").replacingOccurrences(of: "<text:", with: "<t:")
                .replacingOccurrences(of: "</text:", with: "</t:").replacingOccurrences(of: " text:", with: " t:")
        }
        let original = try Self.readFixture().presentation
        let data = try ODPLibreOfficeFixture.package(content: renamed(ODPLibreOfficeFixture.content), styles: renamed(ODPLibreOfficeFixture.styles))
        let renamedFile = try PresentationIO.read(data, format: .odp)
        #expect(renamedFile.presentation.slides.map(\.plainText) == original.slides.map(\.plainText))
        #expect(ODPRendering.difference(original, renamedFile.presentation) == nil)
    }

    @Test func mapsShapeTypesBothWays() {
        #expect(ODPGeometry.preset(type: "ooxml-star5", modifiers: "20000 105146 110557")?.adjustments == ["adj": 20000, "hf": 105146, "vf": 110557])
        #expect(ODPGeometry.preset(type: "ooxml-notAShape", modifiers: nil) == nil)
        #expect(ODPGeometry.preset(type: "flowchart-decision", modifiers: nil)?.name == "flowChartDecision")
        #expect(ODPGeometry.preset(type: "circle", modifiers: nil)?.name == "ellipse")
        #expect(ODPGeometry.preset(type: "mso-spt100", modifiers: nil) == nil)
        #expect(ODPGeometry.adjustNames("star7") == ["adj", "hf", "vf"])
        #expect(ODPGeometry.adjustNames("uturnArrow") == ["adj1", "adj2", "adj3", "adj4", "adj5"])
        #expect(ODPGeometry.shapeType("star5", adjustments: ["adj": 19098]).type == "star5")
        #expect(ODPGeometry.shapeType("pentagon", adjustments: ["hf": 105146, "vf": 110557]).type == "pentagon")
        #expect(ODPGeometry.shapeType("pie", adjustments: [:]) == ("ooxml-pie", "0 16200000"))
        // Every preset the engine draws gets a type that reads back as itself.
        for name in PresetGeometry.presetNames {
            let adjustments = PresetGeometry.defaultAdjustments(name).mapValues { $0 + 1 }
            let type = ODPGeometry.shapeType(name, adjustments: adjustments)
            let read = ODPGeometry.preset(type: type.type, modifiers: type.modifiers)
            #expect(read?.name == name, "\(name)")
            #expect(read?.adjustments == adjustments, "\(name)")
        }
    }

    @Test func mapsTransitionsAndEffectsToTheNearest() {
        #expect(ODPMotion.kind(type: "barWipe", subtype: "topToBottom", reverse: false) == .fade)
        #expect(ODPMotion.kind(type: "pushWipe", subtype: "fromRight", reverse: true) == .slideFromLeft)
        #expect(ODPMotion.kind(type: "slideWipe", subtype: "fromLeft", reverse: false) == .slideFromLeft)
        #expect(ODPMotion.kind(type: "miscShapeWipe", subtype: "bottomToTop", reverse: false) == .flip)
        #expect(ODPMotion.kind(type: "miscShapeWipe", subtype: "cornersIn", reverse: false) == .cube)
        #expect(ODPMotion.kind(legacyStyle: "move-from-left") == .slideFromLeft)
        #expect(ODPMotion.kind(legacyStyle: "uncover-to-left") == .slideFromRight)
        #expect(ODPMotion.kind(legacyStyle: "fade-from-top") == .fade)
        let none: [ODFNode] = []
        #expect(ODPMotion.effectKind(presetID: "ooo-entrance-ascend", presetClass: "entrance", subtype: "", leaves: none) == .flyInFromBottom)
        #expect(ODPMotion.effectKind(presetID: "ooo-entrance-fly-in", presetClass: "entrance", subtype: "from-top-left", leaves: none) == .flyInFromTop)
        #expect(ODPMotion.effectKind(presetID: "ooo-entrance-wheel", presetClass: "entrance", subtype: "", leaves: none) == .appear)
        #expect(ODPMotion.effectKind(presetID: "ooo-entrance-expand", presetClass: "entrance", subtype: "", leaves: none) == .zoomIn)
        #expect(ODPMotion.effectKind(presetID: "ooo-exit-fly-out", presetClass: "exit", subtype: "from-right", leaves: none) == .flyOutToRight)
        #expect(ODPMotion.effectKind(presetID: "ooo-exit-dissolve", presetClass: "exit", subtype: "", leaves: none) == .fadeOut)
        #expect(ODPMotion.effectKind(presetID: "ooo-emphasis-transparency", presetClass: "emphasis", subtype: "", leaves: none) == nil)
        // Without a preset, the nodes say what the effect is.
        let fly = ODFNode(name: "anim:animate", attributes: ["smil:attributeName": "x", "smil:values": "1+width/2;x"])
        #expect(ODPMotion.effectKind(presetID: "", presetClass: "", subtype: "", leaves: [fly]) == .flyInFromRight)
        let fade = ODFNode(name: "anim:transitionFilter", attributes: ["smil:type": "fade", "smil:mode": "out"])
        #expect(ODPMotion.effectKind(presetID: "", presetClass: "", subtype: "", leaves: [fade]) == .fadeOut)
    }

    @Test func readsOlderTransitionAttributes() throws {
        let content = ODPLibreOfficeFixture.content.replacingOccurrences(of: "smil:type=\"pushWipe\" smil:subtype=\"fromLeft\"",
                                                                         with: "presentation:transition-style=\"move-from-right\"")
        let presentation = try PresentationIO.read(try ODPLibreOfficeFixture.package(content: content), format: .odp).presentation
        #expect(presentation.slides[2].transition == SlideTransition(kind: .slideFromRight, duration: 0.5))
    }

    @Test func refusesOtherFilesWithFriendlyMessages() throws {
        func message(_ data: Data) -> String? {
            do {
                _ = try PresentationIO.read(data, format: .odp)
                return nil
            } catch let error as PresentationIOError {
                return error.errorDescription
            } catch {
                return "unexpected \(error)"
            }
        }
        #expect(message(Data("not a zip at all".utf8)) == ODPMessages.notAPresentation)
        #expect(message(Data()) == ODPMessages.notAPresentation)
        let pptx = try PPTXWriter.write(Presentation.makeDefault())
        #expect(message(pptx) == ODPMessages.notAPresentation)
        let text = try ODPTestPackage.zip([("content.xml", Data("<office:document-content xmlns:office=\"\(ODFNamespace.office)\"><office:body><office:text/></office:body></office:document-content>".utf8))],
                                          mimetype: "application/vnd.oasis.opendocument.text")
        #expect(message(text) == ODPMessages.otherDocument)
        let spreadsheet = try ODPTestPackage.zip([("content.xml", Data("<office:document-content xmlns:office=\"\(ODFNamespace.office)\"><office:body><office:spreadsheet/></office:body></office:document-content>".utf8))],
                                                 mimetype: nil)
        #expect(message(spreadsheet) == ODPMessages.otherDocument)
        let encrypted = try ODPTestPackage.zip([("content.xml", Data([0x13, 0x37])), ("META-INF/manifest.xml", Data("""
            <manifest:manifest xmlns:manifest="\(ODFNamespace.manifest)"><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml">\
            <manifest:encryption-data manifest:checksum-type="SHA1/1K" manifest:checksum="x"/></manifest:file-entry></manifest:manifest>
            """.utf8))])
        #expect(message(encrypted) == ODPMessages.encrypted)
        let broken = try ODPTestPackage.zip([("content.xml", Data("<office:document-content><unclosed>".utf8))])
        #expect(message(broken) == ODPMessages.damaged)
        let empty = try ODPTestPackage.zip([("styles.xml", Data("<x/>".utf8))])
        #expect(message(empty) == ODPMessages.notAPresentation)
        let entity = try ODPTestPackage.zip([("content.xml", Data("<!DOCTYPE x [<!ENTITY a \"aaaa\">]><x>&a;</x>".utf8))])
        #expect(message(entity) == ODPMessages.damaged)
    }

    @Test func readsAMinimalFileWithoutStyles() throws {
        // Only content.xml: no masters, no styles. A theme is made from defaults and the text keeps its look.
        let content = """
            <office:document-content xmlns:office="\(ODFNamespace.office)" xmlns:draw="\(ODFNamespace.draw)" xmlns:text="\(ODFNamespace.text)" \
            xmlns:svg="\(ODFNamespace.svg)" xmlns:presentation="\(ODFNamespace.presentation)"><office:body><office:presentation>\
            <draw:page draw:name="One"><draw:frame svg:x="1in" svg:y="1in" svg:width="4in" svg:height="1in"><draw:text-box><text:p>Hello</text:p>\
            </draw:text-box></draw:frame><draw:frame presentation:class="title" svg:x="1in" svg:y="0in" svg:width="4in" svg:height="1in"><draw:text-box>\
            <text:p>Title</text:p></draw:text-box></draw:frame></draw:page></office:presentation></office:body></office:document-content>
            """
        let file = try PresentationIO.read(try ODPTestPackage.zip([("content.xml", Data(content.utf8))]), format: .odp)
        let presentation = file.presentation
        #expect(presentation.themes.count == 1)
        #expect(presentation.slides.count == 1)
        #expect(presentation.slides[0].plainText == "Title\nHello")
        #expect(presentation.slides[0].elements[0].shape?.isTextBox == true)
        #expect(presentation.slides[0].elements[1].placeholder?.type == .title)
        // What's read can be written and read again.
        let again = try PresentationIO.read(try PresentationIO.write(presentation, format: .odp), format: .odp)
        #expect(ODPRendering.difference(presentation, again.presentation) == nil)
    }

    @Test func placeholdersWithoutAPlaceTakeTheirLayouts() throws {
        // Another app's slide whose title states no position: it sits where the layout's title does.
        let content = ODPLibreOfficeFixture.content.replacingOccurrences(
            of: "presentation:style-name=\"pr1\" draw:layer=\"layout\" svg:width=\"23.91cm\" svg:height=\"3.507cm\" svg:x=\"2.058cm\" svg:y=\"1.743cm\" presentation:class=\"title\" presentation:user-transformed=\"true\"><draw:text-box><text:p>Lists",
            with: "presentation:style-name=\"pr1\" draw:layer=\"layout\" presentation:class=\"title\"><draw:text-box><text:p>Lists")
        #expect(content != ODPLibreOfficeFixture.content)
        let presentation = try PresentationIO.read(try ODPLibreOfficeFixture.package(content: content), format: .odp).presentation
        let slide = presentation.slides[1]
        #expect(slide.elements[0].shape?.text?.plainText == "Lists")
        #expect(slide.elements[0].placement == nil)
        #expect(abs(presentation.placement(of: slide.elements[0], on: slide).frame.y - Self.points(1.743)) < 0.01)
    }
}
