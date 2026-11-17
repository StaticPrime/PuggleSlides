import AppKit
import PuggleSlidesKit

extension PresentationController {
    // MARK: Transitions

    /// The current slide's transition, as the Motion panel shows it.
    var currentTransition: SlideTransition {
        currentSlide?.transition ?? SlideTransition(kind: .none)
    }

    /// Sets the transition of the slides selected in the filmstrip.
    func setTransition(_ transition: SlideTransition) {
        let ids = selectedSlideIDs
        perform("Transition", update: [.slides, .content]) { presentation in
            presentation.setTransition(transition, slideIDs: ids)
        }
    }

    /// Motion ▸ Apply to all slides.
    func applyTransitionToAllSlides() {
        let transition = currentTransition
        perform("Apply Transition to All Slides", update: [.slides, .content]) { presentation in
            presentation.setTransition(transition, slideIDs: Set(presentation.slides.map(\.id)))
        }
    }

    // MARK: Animations

    var currentAnimations: [SlideAnimation] { currentSlide?.animations ?? [] }

    /// Insert ▸ Animation: adds "Appear (On click)" for the selected object.
    @discardableResult
    func addAnimation(for elementID: UUID? = nil) -> UUID? {
        guard let index = currentSlideIndex, let target = elementID ?? selectedElementIDs.first,
              presentation.slides[index].element(id: target) != nil else { return nil }
        let animation = SlideAnimation(elementID: target)
        perform("Add Animation", update: [.slides, .content]) { presentation in
            presentation.slides[index].animations.append(animation)
        }
        return animation.id
    }

    func updateAnimation(_ id: UUID, actionName: String = "Change Animation", _ change: (inout SlideAnimation) -> Void) {
        guard let index = currentSlideIndex, let position = presentation.slides[index].animations.firstIndex(where: { $0.id == id }) else { return }
        var animation = presentation.slides[index].animations[position]
        change(&animation)
        perform(actionName, update: [.slides]) { presentation in
            presentation.slides[index].animations[position] = animation
        }
    }

    func deleteAnimation(_ id: UUID) {
        guard let index = currentSlideIndex else { return }
        perform("Delete Animation", update: [.slides, .content]) { presentation in
            presentation.slides[index].animations.removeAll { $0.id == id }
        }
    }

    /// Drag to reorder in the Motion panel.
    func moveAnimation(_ id: UUID, to destination: Int) {
        guard let index = currentSlideIndex, let source = presentation.slides[index].animations.firstIndex(where: { $0.id == id }) else { return }
        perform("Move Animation", update: [.slides]) { presentation in
            var animations = presentation.slides[index].animations
            let animation = animations.remove(at: source)
            animations.insert(animation, at: max(0, min(animations.count, destination)))
            presentation.slides[index].animations = animations
        }
    }

    /// A slide with a transition or animations shows a motion mark in the filmstrip.
    func hasMotion(_ slide: Slide) -> Bool {
        (slide.transition.map { $0.kind != .none } ?? false) || !slide.animations.isEmpty
    }

    /// A short name for an element in the Motion panel: its text, or its kind.
    func displayName(of elementID: UUID) -> String {
        guard let element = currentSlide?.element(id: elementID) else { return "Missing object" }
        if let text = element.shape?.text?.plainText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let line = text.components(separatedBy: .newlines).first ?? text
            return line.count > 28 ? String(line.prefix(27)) + "…" : line
        }
        if element.picture != nil { return "Image" }
        if element.children != nil { return "Group" }
        if element.isLine { return "Line" }
        if let preset = element.shape?.geometry.presetName, let info = PresetGeometry.info(named: preset) { return info.title }
        return element.shape?.isTextBox == true ? "Text box" : "Shape"
    }
}
