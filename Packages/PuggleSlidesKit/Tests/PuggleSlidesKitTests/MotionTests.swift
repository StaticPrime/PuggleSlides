import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct MotionTests {
    private func sample() -> Presentation {
        var presentation = Presentation.makeDefault()
        presentation.slides[0].elements[0].shape?.text = TextBody("Title")
        presentation.slides[0].elements[1].shape?.text = TextBody("Line one\nLine two")
        let ids = presentation.slides[0].elements.map(\.id)
        presentation.slides[0].animations = [
            SlideAnimation(elementID: ids[0], effect: .fadeIn),
            SlideAnimation(elementID: ids[1], effect: .flyInFromLeft, start: .afterPrevious, duration: 1, byParagraph: true),
        ]
        presentation.slides[0].transition = SlideTransition(kind: .cube, duration: 0.8)
        return presentation
    }

    @Test func duplicatedSlidesKeepTheirAnimationsOnTheCopies() {
        let presentation = sample()
        let copy = presentation.duplicate(presentation.slides[0])
        #expect(copy.animations.count == 2)
        #expect(copy.animations.map(\.elementID) == copy.elements.prefix(2).map(\.id))
        #expect(Set(copy.animations.map(\.id)).isDisjoint(with: presentation.slides[0].animations.map(\.id)))
        #expect(copy.animations.map(\.effect) == [.fadeIn, .flyInFromLeft])
        #expect(copy.transition == SlideTransition(kind: .cube, duration: 0.8))
    }

    @Test func animationsOfDeletedElementsGoAway() {
        var slide = sample().slides[0]
        slide.elements.removeFirst()
        slide.pruneAnimations()
        #expect(slide.animations.map(\.effect) == [.flyInFromLeft])
    }

    @Test func transitionNoneClearsTheTransition() {
        var presentation = sample()
        let ids = Set(presentation.slides.map(\.id))
        presentation.setTransition(SlideTransition(kind: .fade), slideIDs: ids)
        #expect(presentation.slides[0].transition?.kind == .fade)
        presentation.setTransition(SlideTransition(kind: .none), slideIDs: ids)
        #expect(presentation.slides[0].transition == nil)
    }

    @Test func plainTextListsEachSlidesTextTitleFirst() {
        var presentation = sample()
        presentation.slides[0].elements.reverse()
        var second = presentation.makeSlide(layoutID: presentation.themes[0].layout(kind: .titleAndBody)!.id)
        second.elements[0].shape?.text = TextBody("Second")
        presentation.slides.append(second)
        #expect(presentation.plainText == "Title\nLine one\nLine two\n\nSecond\n")
    }

    @Test func slidesFromBeforeMotionStillDecode() throws {
        let slide = sample().slides[0]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(slide)) as! [String: Any]
        json.removeValue(forKey: "animations")
        json.removeValue(forKey: "transition")
        let decoded = try JSONDecoder().decode(Slide.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.animations.isEmpty && decoded.transition == nil && decoded.elements == slide.elements)
    }

    @Test func effectsKnowWhetherTheyEnterOrLeave() {
        #expect(AnimationEffect.fadeIn.isEntrance && !AnimationEffect.fadeIn.isExit)
        #expect(AnimationEffect.zoomOut.isExit && !AnimationEffect.zoomOut.isEntrance)
        #expect(!AnimationEffect.spin.isEntrance && !AnimationEffect.spin.isExit)
        #expect(TransitionKind.allCases.map(\.title).contains("Slide from right"))
    }
}
