import Foundation
import Testing
@testable import PuggleSlidesKit

/// Writing a presentation and reading it back shows the same slides: ids, element names and theme references aside
/// (theme colors come back as the colors they were, theme fonts as the fonts they named).
struct ODPRoundTripTests {
    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        let data = try PresentationIO.write(presentation, format: .odp)
        return try PresentationIO.read(data, format: .odp)
    }

    @Test func defaultPresentationRoundTrips() throws {
        var original = Presentation.makeDefault()
        original.slides[0].elements[0].shape?.text = TextBody("Hello")
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = ODPRendering.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")

        // The theme, its layouts and the slide's inheritance survive.
        let read = file.presentation
        #expect(read.themes.map(\.name) == ["Simple Light"])
        #expect(read.themes[0].fonts.major == "Arial")
        #expect(read.themes[0].layouts.map(\.kind) == original.themes[0].layouts.map(\.kind))
        #expect(read.themes[0].layouts.map(\.name) == original.themes[0].layouts.map(\.name))
        let slide = read.slides[0]
        #expect(read.layout(for: slide)?.kind == .title)
        #expect(slide.elements.map { $0.placeholder?.type } == [.centeredTitle, .subtitle])
        #expect(slide.elements.allSatisfy { $0.placement == nil })
        // What the layout gives its placeholders comes back to the layout, so the slide's text states nothing.
        let style = read.style(for: slide.elements[0], on: slide)
        #expect(style.levelStyle(0).character.fontSize == 52)
        #expect(style.levelStyle(0).paragraph.alignment == .center)
        #expect(slide.elements[0].shape?.text?.paragraphs[0].runs[0].style == CharacterStyle())
        #expect(abs(style.placement.frame.x - 24.543) < 0.01)
        // An empty placeholder keeps what typing in it gets.
        let subtitle = read.style(for: slide.elements[1], on: slide)
        #expect(subtitle.levelStyle(0).character.fontSize == 28)
    }

    @Test(arguments: BuiltInThemes.designs.map(\.name))
    func builtInThemeRoundTrips(_ name: String) throws {
        let design = try #require(BuiltInThemes.designs.first { $0.name == name })
        let original = ODPSamples.themeShowcase(design)
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = ODPRendering.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        // Every layout comes back by name and kind, with its own decorations.
        let theme = original.themes[0], read = file.presentation.themes[0]
        #expect(read.name == design.name)
        #expect(read.fonts.major == design.headingFont && read.fonts.minor == design.bodyFont)
        #expect(read.layouts.map(\.name) == theme.layouts.map(\.name))
        #expect(read.layouts.map(\.kind) == theme.layouts.map(\.kind))
        #expect(read.layouts.map { $0.elements.filter { $0.placeholder == nil }.count } == theme.layouts.map { $0.elements.filter { $0.placeholder == nil }.count })
        #expect(read.elements.filter { $0.placeholder == nil }.count == theme.elements.filter { $0.placeholder == nil }.count)
        // Slides keep their layouts and their placeholders' places.
        for (slide, readSlide) in zip(original.slides, file.presentation.slides) {
            #expect(file.presentation.layout(for: readSlide)?.name == original.layout(for: slide)?.name)
            #expect(readSlide.elements.map { $0.placeholder?.type } == slide.elements.map { $0.placeholder?.type })
            #expect(readSlide.elements.allSatisfy { $0.placement == nil })
        }
    }

    @Test func everyThemeInOneDeckRoundTrips() throws {
        let original = ODPSamples.allThemes()
        let file = try Self.roundTrip(original)
        let difference = ODPRendering.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        #expect(file.presentation.themes.map(\.name) == BuiltInThemes.designs.map(\.name))
    }

    @Test func richPresentationRoundTrips() throws {
        let original = ODPSamples.rich()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = ODPRendering.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")

        // Spot checks on what the rendering compares indirectly or leaves out.
        let read = file.presentation
        #expect(read.title == original.title)
        #expect(read.media.count == 2)
        #expect(read.slides.count == 7)
        #expect(read.slides[3].isSkipped)
        #expect(read.themes.map(\.name) == ["Simple Light", "Harbor"])
        let link = read.slides[1].elements[1].shape?.text?.paragraphs[7].runs[3].style.link
        #expect(link == .slide(read.slides[3].id))
        #expect(read.slides[2].elements.map(\.name) == original.slides[2].elements.map(\.name))
        #expect(read.slides[2].elements[0].altTitle == "A rectangle")
        #expect(read.slides[2].elements[0].altDescription == "An orange rectangle\nwith a blue border")
        let photoLayout = try #require(read.layout(for: read.slides[5]))
        #expect(photoLayout.name == "Photo backdrop")
        #expect(photoLayout.background?.mediaID != nil)
        #expect(read.layout(for: read.slides[6])?.elements.contains { $0.name == "Title block" } == true)
        #expect(read.slides.compactMap(\.transition).map(\.kind) == [.fade, .dissolve, .slideFromRight, .slideFromLeft, .flip, .cube, .gallery])
        #expect(read.slides.map { $0.notes.plainText } == original.slides.map { $0.notes.plainText })
    }

    @Test func everyTransitionEffectAndStartSurvives() throws {
        var presentation = Presentation.makeDefault()
        let layout = presentation.themes[0].layout(kind: .titleAndBody)!.id
        var slides: [Slide] = []
        for (index, kind) in TransitionKind.allCases.enumerated() {
            var slide = presentation.makeSlide(layoutID: layout)
            slide.elements[0].shape?.text = TextBody("Transition \(kind.title)")
            slide.elements[1].shape?.text = TextBody("One\nTwo\nThree")
            slide.transition = kind == .none ? nil : SlideTransition(kind: kind, duration: 0.25 + Double(index) * 0.5)
            slides.append(slide)
        }
        var effects = presentation.makeSlide(layoutID: layout)
        effects.elements[0].shape?.text = TextBody("Effects")
        effects.elements[1].shape?.text = TextBody("First\n\nThird")
        for (index, effect) in AnimationEffect.allCases.enumerated() {
            let start = AnimationStart.allCases[index % 3]
            let target = effects.elements[index % 2].id
            effects.animations.append(SlideAnimation(elementID: target, effect: effect, start: start, duration: 0.3 + Double(index) / 10,
                                                     delay: Double(index % 4) / 4, byParagraph: index % 2 == 1 && index % 3 == 0))
        }
        slides.append(effects)
        presentation.slides = slides
        let read = try Self.roundTrip(presentation).presentation
        for (slide, readSlide) in zip(presentation.slides, read.slides) {
            #expect(readSlide.transition?.kind == slide.transition?.kind)
            if let duration = slide.transition?.duration { #expect(abs((readSlide.transition?.duration ?? 0) - duration) < 0.001) }
        }
        let readEffects = read.slides.last!.animations
        #expect(readEffects.map(\.effect) == AnimationEffect.allCases)
        #expect(readEffects.map(\.start) == effects.animations.map(\.start))
        #expect(readEffects.map(\.byParagraph) == effects.animations.map(\.byParagraph))
        for (animation, readAnimation) in zip(effects.animations, readEffects) {
            #expect(abs(readAnimation.delay - animation.delay) < 0.001)
            if !animation.effect.isInstant { #expect(abs(readAnimation.duration - animation.duration) < 0.001) }
            let index = effects.elements.firstIndex { $0.id == animation.elementID }
            #expect(read.slides.last!.elements.firstIndex { $0.id == readAnimation.elementID } == index)
        }
    }

    @Test func writingIsStable() throws {
        // Reading and writing again shows the same slides a second time, and keeps the model the same.
        let first = try Self.roundTrip(ODPSamples.rich()).presentation
        let second = try Self.roundTrip(first).presentation
        let difference = ODPRendering.difference(first, second)
        #expect(difference == nil, "\(difference ?? "")")
        let third = try Self.roundTrip(second).presentation
        #expect(ODPModel.difference(second, third) == nil, "\(ODPModel.difference(second, third) ?? "")")
    }

    @Test func layoutsThatHideTheThemesDecorationsKeepThat() throws {
        var harbor = BuiltInThemes.make(BuiltInThemes.designs[3])
        let index = try #require(harbor.layouts.firstIndex { $0.kind == .titleOnly })
        harbor.layouts[index].showsThemeElements = false
        var presentation = Presentation(themes: [harbor], defaultTextStyle: BuiltInThemes.defaultTextStyle)
        presentation.slides = [presentation.makeSlide(layoutID: harbor.layouts[index].id), presentation.makeSlide(layoutID: harbor.layouts[0].id)]
        let read = try Self.roundTrip(presentation).presentation
        #expect(read.layout(for: read.slides[0])?.showsThemeElements == false)
        #expect(read.layout(for: read.slides[1])?.showsThemeElements == true)
        #expect(read.backdropElements(for: read.slides[0]).isEmpty)
        #expect(read.backdropElements(for: read.slides[1]).map(\.element.name) == ["Band", "Title block"])
        #expect(ODPRendering.difference(presentation, read) == nil)
    }

    @Test func applyLayoutAndChangeThemeWorkOnOpenedFiles() throws {
        var read = try Self.roundTrip(ODPSamples.rich()).presentation
        // Title slide to title and body: the title moves into the new layout's title, the subtitle into its body.
        let titleAndBody = try #require(read.themes[0].layout(kind: .titleAndBody))
        read.applyLayout(titleAndBody.id, toSlideAt: 0)
        #expect(read.slides[0].layoutID == titleAndBody.id)
        #expect(read.slides[0].elements.map { $0.placeholder?.type } == [.title, .body])
        #expect(read.slides[0].elements[0].shape?.text?.plainText == "Quarterly Review")
        #expect(read.slides[0].elements.allSatisfy { $0.placement == nil })

        read.applyTheme(BuiltInThemes.simpleDark())
        #expect(read.themes.map(\.name) == ["Simple Dark"])
        for slide in read.slides { #expect(read.layout(for: slide) != nil) }
        #expect(read.layout(for: read.slides[1])?.kind == .titleAndBody)
        #expect(read.slides[1].elements[0].shape?.text?.plainText == "Highlights")
    }

    @Test func whitespaceRunsAndUnusualTextSurvive() throws {
        var presentation = Presentation.makeDefault()
        let runs = [TextRun("Bold", style: CharacterStyle(bold: true)), TextRun(" "), TextRun("\t", style: CharacterStyle(italic: true)),
                    TextRun("  two  spaces  ", style: CharacterStyle(underline: true)), TextRun("é 漢字 🐶 \u{2029}", style: CharacterStyle(fontSize: 30)),
                    TextRun("a\u{2028}\u{2028} b <&> \"quotes\" 'apostrophes'", style: CharacterStyle(strikethrough: true))]
        presentation.slides[0].elements[0].shape?.text = TextBody(paragraphs: [TextParagraph(runs: runs), TextParagraph(runs: [TextRun("   ")]),
                                                                              TextParagraph(runs: [TextRun(" leading and trailing ")])])
        let read = try Self.roundTrip(presentation).presentation
        #expect(read.slides[0].elements[0].shape?.text?.paragraphs.map(\.runs) == [runs, [TextRun("   ")], [TextRun(" leading and trailing ")]])
        #expect(ODPRendering.difference(presentation, read) == nil)
    }

    /// What OpenDocument can't hold comes back as the nearest thing it can.
    @Test func featuresOutsideODFDegradeToTheNearest() throws {
        var presentation = Presentation.makeDefault()
        let photo = presentation.addMedia(ODPSamples.photo, contentType: "image/png")
        let layout = presentation.themes[0].layout(kind: .blank)!.id
        var slide = presentation.makeSlide(layoutID: layout)
        let gradient = GradientFill(kind: .linear(angle: 0), stops: [GradientStop(position: 0, color: .white), GradientStop(position: 0.3, color: ColorRef(theme: .accent1)),
                                                                     GradientStop(position: 1, color: .black)])
        var text = TextBody("Shrunk", properties: TextBodyProperties(autofit: .shrinkOnOverflow, fontScale: 0.5, lineSpacingReduction: 0.1))
        text.paragraphs[0].runs[0].style.color = ColorRef(RGBColor(red: 10, green: 20, blue: 30), alpha: 0.4)
        slide.elements = [
            ODPSamples.shape("Three stops", SlideRect(x: 10, y: 10, width: 100, height: 50), Shape(fill: .gradient(gradient), text: text)),
            SlideElement(name: "Masked and cropped", placement: Placement(frame: SlideRect(x: 120, y: 10, width: 80, height: 80)),
                         content: .picture(Picture(mediaID: photo, crop: ImageCrop(left: 0.2), geometry: .preset("ellipse", adjustments: [:])))),
            ODPSamples.shape("Four segment elbow", SlideRect(x: 220, y: 10, width: 80, height: 40),
                             Shape(geometry: .preset("bentConnector4", adjustments: ["adj1": 20000, "adj2": 80000]), outline: .solid(.black), isConnector: true)),
            ODPSamples.shape("Accent", SlideRect(x: 320, y: 10, width: 40, height: 40), Shape(fill: .solid(ColorRef(theme: .accent1)), text: TextBody("Heading",
                             style: CharacterStyle(fontFamily: "+mj-lt")))),
        ]
        presentation.slides = [slide]
        let file = try Self.roundTrip(presentation)
        #expect(file.warnings.isEmpty)
        let read = file.presentation.slides[0].elements
        // The gradient keeps its ends.
        guard case .gradient(let readGradient)? = read[0].shape?.fill else {
            Issue.record("expected a gradient")
            return
        }
        #expect(readGradient.stops.map(\.color) == [.white, .black])
        // Shrink-to-fit's scale is worked out again when the text is laid out; text keeps its color but not its transparency.
        #expect(read[0].shape?.text?.properties.autofit == .shrinkOnOverflow)
        #expect(read[0].shape?.text?.properties.fontScale == nil)
        #expect(read[0].shape?.text?.paragraphs[0].runs[0].style.color == ColorRef(RGBColor(red: 10, green: 20, blue: 30)))
        // A masked picture is its shape filled with the image, as LibreOffice keeps it; the crop goes.
        #expect(read[1].shape?.geometry.presetName == "ellipse")
        #expect(read[1].shape?.fill?.mediaID != nil)
        // Elbow connectors are LibreOffice's standard connector.
        #expect(read[2].shape?.geometry.presetName == "bentConnector3")
        #expect(read[2].shape?.isConnector == true)
        // Theme colors and fonts become what they were.
        #expect(read[3].shape?.fill == .solid(ColorRef(RGBColor(hex: "4285F4")!)))
        #expect(read[3].shape?.text?.paragraphs[0].runs[0].style.fontFamily == nil)
        #expect(file.presentation.style(for: read[3], on: file.presentation.slides[0]).levelStyle(0).character.fontFamily == "Arial")
    }

    @Test func emptyAndDegeneratePresentationsStillWrite() throws {
        // No themes, a slide on a missing layout, pictures whose image is gone, empty groups.
        var presentation = Presentation(themes: [])
        presentation.slides = [Slide(layoutID: UUID(), elements: [
            SlideElement(name: "Lost", placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: "gone"))),
            SlideElement(name: "Empty group", placement: Placement(frame: .zero), content: .group([])),
            SlideElement(name: "Group of lost pictures", placement: Placement(frame: .zero), content: .group([
                SlideElement(placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: "gone"))),
            ])),
            ODPSamples.shape("Zero size", .zero, Shape(geometry: .preset("star5", adjustments: [:]), fill: .solid(.black))),
            ODPSamples.shape("Negative size", SlideRect(x: 50, y: 50, width: -20, height: -10), Shape(fill: .picture(PictureFill(mediaID: "gone")))),
            ODPSamples.shape("Unknown preset", SlideRect(x: 0, y: 0, width: 20, height: 20), Shape(geometry: .preset("notAShape", adjustments: ["adj": .nan]))),
            ODPSamples.shape("Huge", SlideRect(x: 1e300, y: -1e300, width: .infinity, height: .nan), rotation: .nan, Shape(text: TextBody("x"))),
        ])]
        let file = try Self.roundTrip(presentation)
        #expect(file.presentation.themes.count == 1)
        #expect(file.presentation.slides.count == 1)
        #expect(file.presentation.layout(for: file.presentation.slides[0]) != nil)
        #expect(file.presentation.slides[0].elements.map(\.name) == ["Zero size", "Negative size", "Unknown preset", "Huge"])

        // The same theme twice (duplicate ids) still makes a sound file, each with its own master.
        var twice = Presentation.makeDefault()
        twice.themes.append(twice.themes[0])
        twice.slides.append(twice.duplicate(twice.slides[0]))
        let doubled = try Self.roundTrip(twice).presentation
        #expect(doubled.themes.map(\.name) == ["Simple Light", "Simple Light 2"])
        #expect(doubled.themes.map(\.layouts.count) == [11, 11])
        #expect(doubled.slides.count == 2)

        var bare = Presentation(themes: [Theme(name: "", colors: ColorScheme(name: "", colors: [:]), fonts: FontScheme(name: "", major: "", minor: ""),
                                               background: .none)])
        bare.slides = []
        let read = try Self.roundTrip(bare).presentation
        #expect(read.themes[0].layouts.count == 1)
        #expect(read.slides.isEmpty)
    }
}
