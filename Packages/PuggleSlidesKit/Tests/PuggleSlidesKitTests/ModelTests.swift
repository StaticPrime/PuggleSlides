import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct ModelTests {
    @Test func newPresentationStartsWithATitleSlide() throws {
        let presentation = Presentation.makeDefault()
        #expect(presentation.slideSize == .widescreen)
        #expect(presentation.themes.count == 1)
        #expect(presentation.themes[0].name == "Simple Light")
        #expect(presentation.themes[0].layouts.count == 11)
        let slide = try #require(presentation.slides.first)
        #expect(presentation.layout(for: slide)?.kind == .title)
        #expect(slide.elements.map(\.placeholder?.type) == [.centeredTitle, .subtitle])
        #expect(slide.elements.allSatisfy { $0.placement == nil })
    }

    @Test func placeholdersInheritPositionAndTextStyle() throws {
        let presentation = Presentation.makeDefault()
        let slide = presentation.slides[0]
        let title = presentation.style(for: slide.elements[0], on: slide)
        #expect(title.category == .title)
        #expect(abs(title.placement.frame.x - 24.543) < 0.01)
        #expect(abs(title.placement.frame.width - 670.913) < 0.01)
        let level = title.levelStyle(0)
        #expect(level.character.fontSize == 52)
        #expect(level.paragraph.alignment == .center)
        #expect(title.theme.fonts.resolve(level.character.fontFamily ?? "") == "Arial")
        #expect(title.bodyProperties.anchor == .bottom)
        #expect(title.prompt == "Click to add title")

        let subtitle = presentation.style(for: slide.elements[1], on: slide)
        #expect(subtitle.levelStyle(0).character.fontSize == 28)
        #expect(subtitle.levelStyle(0).paragraph.bullet == Bullet.none)
        #expect(subtitle.prompt == "Click to add subtitle")
    }

    @Test func bodyPlaceholdersAreBulleted() throws {
        var presentation = Presentation.makeDefault()
        let layout = try #require(presentation.themes[0].layout(kind: .titleAndBody))
        var slide = presentation.makeSlide(layoutID: layout.id)
        slide.elements[1].shape?.text = TextBody(paragraphs: [TextParagraph("One"), TextParagraph("Two", level: 1)])
        presentation.slides.append(slide)
        let style = presentation.style(for: slide.elements[1], on: slide)
        let paragraphs = style.resolvedParagraphs()
        #expect(paragraphs.map(\.bullet?.text) == ["●", "○"])
        #expect(paragraphs[0].runs[0].style.fontSize == 18)
        #expect(paragraphs[1].runs[0].style.fontSize == 14)
        #expect(paragraphs[0].marginLeft == 36)
        #expect(paragraphs[0].indent == -27)
        #expect(paragraphs[0].runs[0].style.color.rgb == RGBColor(hex: "595959"))
    }

    @Test func numberedListsCountPerLevel() {
        let presentation = Presentation.makeDefault()
        let slide = presentation.slides[0]
        var element = slide.elements[1]
        let numbered = ParagraphStyle(bullet: .number(.arabicPeriod, startAt: 1))
        let lettered = ParagraphStyle(bullet: .number(.alphaLcParenR, startAt: 1))
        var paragraphs = [TextParagraph("a"), TextParagraph("b"), TextParagraph("c", level: 1), TextParagraph("d", level: 1),
                          TextParagraph("e"), TextParagraph("f", level: 1)]
        for index in paragraphs.indices { paragraphs[index].style = paragraphs[index].level == 0 ? numbered : lettered }
        element.shape?.text = TextBody(paragraphs: paragraphs)
        let resolved = presentation.style(for: element, on: slide).resolvedParagraphs()
        #expect(resolved.map(\.bullet?.text) == ["1.", "2.", "a)", "b)", "3.", "a)"])
    }

    @Test func numberingLabels() {
        #expect(AutoNumberScheme.romanUcPeriod.label(for: 14) == "XIV.")
        #expect(AutoNumberScheme.alphaUcParenBoth.label(for: 28) == "(BB)")
        #expect(AutoNumberScheme.arabicParenR.label(for: 3) == "3)")
    }

    @Test func applyingALayoutMovesTextIntoMatchingPlaceholders() throws {
        var presentation = Presentation.makeDefault()
        presentation.slides[0].elements[0].shape?.text = TextBody("Quarterly review")
        presentation.slides[0].elements[0].placement = Placement(frame: SlideRect(x: 10, y: 10, width: 100, height: 50))
        let layout = try #require(presentation.themes[0].layout(kind: .titleAndBody))
        presentation.applyLayout(layout.id, toSlideAt: 0)
        let slide = presentation.slides[0]
        #expect(slide.layoutID == layout.id)
        let types = slide.elements.compactMap(\.placeholder?.type)
        #expect(types.contains(.title) && types.contains(.body))
        let title = try #require(slide.elements.first { $0.placeholder?.type == .title })
        #expect(title.shape?.text?.plainText == "Quarterly review")
        #expect(title.placement == nil)
        // The empty subtitle becomes the body placeholder.
        #expect(slide.elements.count == 2)
    }

    @Test func changingTheThemeKeepsTextAndLayoutKinds() throws {
        var presentation = Presentation.makeDefault()
        presentation.slides[0].elements[0].shape?.text = TextBody("Hello")
        let dark = BuiltInThemes.simpleDark()
        presentation.applyTheme(dark)
        #expect(presentation.themes.map(\.id) == [dark.id])
        let slide = presentation.slides[0]
        #expect(presentation.layout(for: slide)?.kind == .title)
        let style = presentation.style(for: slide.elements[0], on: slide)
        #expect(style.resolvedParagraphs()[0].runs[0].style.color.rgb == .white)
        #expect(presentation.background(for: slide) == .solid(ColorRef(theme: .dark1)))
    }

    @Test func colorAdjustmentsFollowDrawingML() {
        let scheme = BuiltInThemes.simpleLight().colors
        let lighter = ColorRef(.theme(.accent1), lumMod: 0.4, lumOff: 0.6).resolved(scheme).rgb
        #expect(lighter.red > 0xB0 && lighter.blue > 0xE0)
        let shaded = ColorRef(RGBColor.white).withAlpha(0.5)
        #expect(shaded.resolved(scheme).alpha == 0.5)
        #expect(ColorRef(.rgb(.white), shade: 0.5).resolved(scheme).rgb == RGBColor(red: 128, green: 128, blue: 128))
    }

    @Test func placementTransformsRotateClockwise() {
        let placement = Placement(frame: SlideRect(x: 100, y: 100, width: 100, height: 50), rotation: 90)
        let topLeft = placement.slidePoint(fromShape: .zero)
        // A quarter turn clockwise moves the top-left corner to the top-right of the turned box.
        #expect(abs(topLeft.x - 175) < 0.001 && abs(topLeft.y - 75) < 0.001)
        let box = placement.boundingBox
        #expect(abs(box.width - 50) < 0.001 && abs(box.height - 100) < 0.001)
        #expect(Placement.normalized(-30) == 330)
    }

    @Test func slideNumbersCanBeSwitchedOn() {
        var presentation = Presentation.makeDefault()
        let id = presentation.slides[0].id
        presentation.setSlideNumbers(true, slideIDs: [id])
        let slide = presentation.slides[0]
        let number = slide.elements.first { $0.placeholder?.type == .slideNumber }
        #expect(number != nil)
        let style = presentation.style(for: number!, on: slide)
        #expect(style.resolvedParagraphs(slideNumber: 7).first?.text == "7")
        #expect(style.placement.frame.x > 600)
        presentation.setSlideNumbers(false, slideIDs: [id])
        #expect(!presentation.slides[0].elements.contains { $0.placeholder?.type == .slideNumber })
    }
}
