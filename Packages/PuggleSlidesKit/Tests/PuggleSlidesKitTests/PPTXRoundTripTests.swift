import Foundation
import Testing
@testable import PuggleSlidesKit

/// Writing a presentation and reading it back gives the same model, ids aside.
struct PPTXRoundTripTests {
    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        let data = try PresentationIO.write(presentation, format: .pptx)
        return try PresentationIO.read(data, format: .pptx)
    }

    @Test func richPresentationRoundTrips() throws {
        let original = PPTXSamples.rich()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")

        // Spot checks on what the canonical comparison renames.
        let read = file.presentation
        #expect(read.media.count == 2)
        #expect(read.slides.count == 6)
        #expect(read.slides[3].isSkipped)
        let link = read.slides[1].elements[1].shape?.text?.paragraphs[5].runs[3].style.link
        #expect(link == .slide(read.slides[3].id))
        #expect(read.layout(for: read.slides[4])?.name == "Title and body")
        #expect(read.theme(for: read.slides[4]).name == "Harbor")
        #expect(read.layout(for: read.slides[5])?.name == "Photo backdrop")
    }

    @Test func defaultPresentationRoundTrips() throws {
        var original = Presentation.makeDefault()
        original.slides[0].elements[0].shape?.text = TextBody("Hello")
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        // Inheritance survives: the title still takes the layout's place and the theme's size.
        let slide = file.presentation.slides[0]
        #expect(slide.elements.allSatisfy { $0.placement == nil })
        let style = file.presentation.style(for: slide.elements[0], on: slide)
        #expect(style.levelStyle(0).character.fontSize == 52)
        #expect(abs(style.placement.frame.x - 24.543) < 0.01)
    }

    @Test(arguments: BuiltInThemes.designs.map(\.name))
    func builtInThemeRoundTrips(_ name: String) throws {
        let design = try #require(BuiltInThemes.designs.first { $0.name == name })
        let original = PPTXSamples.themeShowcase(design)
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        #expect(file.presentation.themes[0].layouts.map(\.kind) == original.themes[0].layouts.map(\.kind))
    }

    @Test func everyThemeInOneDeckRoundTrips() throws {
        let original = PPTXSamples.allThemes()
        let file = try Self.roundTrip(original)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        #expect(file.presentation.themes.map(\.name) == BuiltInThemes.designs.map(\.name))
    }

    @Test func whitespaceRunsAndUnusualTextSurvive() throws {
        var presentation = Presentation.makeDefault()
        let runs = [TextRun("Bold", style: CharacterStyle(bold: true)), TextRun(" "), TextRun("\t", style: CharacterStyle(italic: true)),
                    TextRun("  two  spaces  ", style: CharacterStyle(underline: true)), TextRun("é 漢字 🐶 \u{2029}", style: CharacterStyle(fontSize: 30))]
        presentation.slides[0].elements[0].shape?.text = TextBody(paragraphs: [TextParagraph(runs: runs), TextParagraph(runs: [TextRun("   ")])])
        let read = try Self.roundTrip(presentation).presentation
        #expect(read.slides[0].elements[0].shape?.text?.paragraphs.map(\.runs) == [runs, [TextRun("   ")]])
    }

    @Test func writingIsStable() throws {
        // Reading and writing again gives the same model a second time.
        let first = try Self.roundTrip(PPTXSamples.rich()).presentation
        let second = try Self.roundTrip(first).presentation
        let difference = PPTXCanonical.difference(first, second)
        #expect(difference == nil, "\(difference ?? "")")
    }

    @Test func emptyAndDegeneratePresentationsStillWrite() throws {
        // No themes, a theme without layouts, a slide on a missing layout, a picture whose image is gone.
        var presentation = Presentation(themes: [])
        presentation.slides = [Slide(layoutID: UUID(), elements: [
            SlideElement(name: "Lost", placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: "gone"))),
            SlideElement(name: "Empty group", placement: Placement(frame: .zero), content: .group([])),
            SlideElement(name: "Group of lost pictures", placement: Placement(frame: .zero), content: .group([
                SlideElement(placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: "gone"))),
            ])),
        ])]
        let file = try Self.roundTrip(presentation)
        #expect(file.presentation.themes.count == 1)
        #expect(file.presentation.slides.count == 1)
        #expect(file.presentation.layout(for: file.presentation.slides[0]) != nil)
        #expect(file.presentation.slides[0].elements.isEmpty)

        // The same theme twice (duplicate ids) still makes a sound package, with each master's own layouts.
        var twice = Presentation.makeDefault()
        twice.themes.append(twice.themes[0])
        twice.slides.append(twice.duplicate(twice.slides[0]))
        twice.slides.append(twice.slides[0])
        let parts = try PPTXTestPackage.parts(of: try PPTXWriter.write(twice))
        #expect(parts.keys.filter { $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }.count == 22)
        let doubled = try PPTXTestPackage.read(try PPTXWriter.write(twice)).presentation
        #expect(doubled.themes.map(\.layouts.count) == [11, 11])
        #expect(doubled.slides.count == 3)
        #expect(Set(doubled.themes.flatMap(\.layouts).map(\.id)).count == 22)

        var bare = Presentation(themes: [Theme(name: "Bare", colors: ColorScheme(name: "Bare", colors: [:]), fonts: FontScheme(name: "", major: "", minor: ""),
                                                background: .none)])
        bare.slides = []
        let read = try Self.roundTrip(bare).presentation
        #expect(read.themes[0].layouts.count == 1)
        #expect(read.slides.isEmpty)
    }
}
