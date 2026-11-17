import AppKit
import PuggleSlidesKit

extension PresentationController {
    /// The layout for New slide: after a title slide, "Title and body"; otherwise the current slide's.
    var nextSlideLayoutID: UUID? {
        guard let slide = currentSlide else {
            let theme = presentation.themes.first
            return (theme?.layout(kind: .title) ?? theme?.layouts.first)?.id
        }
        let theme = presentation.theme(for: slide)
        if let layout = presentation.layout(for: slide), layout.kind != .title { return layout.id }
        return (theme.layout(kind: .titleAndBody) ?? theme.layouts.first)?.id
    }

    /// Slide ▸ New slide (⌃M): a slide after the current one.
    func newSlide(layoutID: UUID? = nil) {
        guard let layoutID = layoutID ?? nextSlideLayoutID else { return }
        let slide = presentation.makeSlide(layoutID: layoutID)
        let index = (currentSlideIndex ?? presentation.slides.count - 1) + 1
        perform("New Slide", update: [.slides, .content], showing: slide.id, selecting: []) { presentation in
            presentation.slides.insert(slide, at: min(index, presentation.slides.count))
        }
    }

    /// Slide ▸ Duplicate slide: copies go right after the last selected slide.
    func duplicateSlides() {
        let indexes = selectedSlideIndexes
        guard let last = indexes.last else { return }
        let copies = indexes.map { presentation.duplicate(presentation.slides[$0]) }
        perform(indexes.count == 1 ? "Duplicate Slide" : "Duplicate Slides", update: [.slides, .content], showing: copies.first?.id, selecting: []) { presentation in
            presentation.slides.insert(contentsOf: copies, at: last + 1)
        }
        if copies.count > 1, let first = copies.first { selectSlides(Set(copies.map(\.id)), current: first.id) }
    }

    /// Slide ▸ Delete slide: the next slide (or the one before) becomes current.
    func deleteSlides() {
        let indexes = selectedSlideIndexes
        guard let first = indexes.first else { return }
        let ids = Set(indexes.map { presentation.slides[$0].id })
        let remaining = presentation.slides.filter { !ids.contains($0.id) }
        let next = remaining.isEmpty ? nil : remaining[min(first, remaining.count - 1)].id
        perform(indexes.count == 1 ? "Delete Slide" : "Delete Slides", update: [.slides, .content], showing: next, selecting: []) { presentation in
            presentation.slides.removeAll { ids.contains($0.id) }
        }
    }

    /// Moves the selected slides, as a block, to sit before `destination` (an index in the full list).
    func moveSlides(to destination: Int) {
        let indexes = selectedSlideIndexes
        guard !indexes.isEmpty else { return }
        let ids = Set(indexes.map { presentation.slides[$0].id })
        let before = presentation.slides.prefix(max(0, min(destination, presentation.slides.count))).filter { !ids.contains($0.id) }.count
        var slides = presentation.slides
        let moving = slides.filter { ids.contains($0.id) }
        slides.removeAll { ids.contains($0.id) }
        slides.insert(contentsOf: moving, at: before)
        guard slides.map(\.id) != presentation.slides.map(\.id) else { return }
        perform(indexes.count == 1 ? "Move Slide" : "Move Slides", update: [.slides]) { presentation in
            presentation.slides = slides
        }
    }

    func moveSlidesUp() {
        guard let first = selectedSlideIndexes.first, first > 0 else { return }
        moveSlides(to: first - 1)
    }

    func moveSlidesDown() {
        guard let last = selectedSlideIndexes.last, last < presentation.slides.count - 1 else { return }
        moveSlides(to: last + 2)
    }

    func moveSlidesToBeginning() { moveSlides(to: 0) }
    func moveSlidesToEnd() { moveSlides(to: presentation.slides.count) }

    var canMoveSlidesUp: Bool { (selectedSlideIndexes.first ?? 0) > 0 }
    var canMoveSlidesDown: Bool { (selectedSlideIndexes.last ?? Int.max) < presentation.slides.count - 1 }

    /// The selected slides are all skipped.
    var selectedSlidesAreSkipped: Bool {
        let indexes = selectedSlideIndexes
        return !indexes.isEmpty && indexes.allSatisfy { presentation.slides[$0].isSkipped }
    }

    /// Slide ▸ Skip slide / Unskip slide.
    func toggleSkip() {
        let skip = !selectedSlidesAreSkipped
        let ids = selectedSlideIDs
        perform(skip ? "Skip Slide" : "Unskip Slide", update: [.slides]) { presentation in
            for index in presentation.slides.indices where ids.contains(presentation.slides[index].id) {
                presentation.slides[index].isSkipped = skip
            }
        }
    }

    /// Slide ▸ Apply layout, to every selected slide.
    func applyLayout(_ layoutID: UUID) {
        let ids = selectedSlideIDs
        perform("Apply Layout", selecting: []) { presentation in
            for index in presentation.slides.indices where ids.contains(presentation.slides[index].id) {
                presentation.applyLayout(layoutID, toSlideAt: index)
            }
        }
    }

    /// Slide ▸ Change background: `nil` resets to the theme's. `everywhere` sets it on every slide.
    func setBackground(_ fill: Fill?, everywhere: Bool = false) {
        let ids = everywhere ? Set(presentation.slides.map(\.id)) : selectedSlideIDs
        perform("Change Background") { presentation in
            for index in presentation.slides.indices where ids.contains(presentation.slides[index].id) {
                presentation.slides[index].background = fill
            }
        }
    }

    /// "Add to theme" in the background dialog: the theme's own background becomes `fill`, and slides follow it.
    func setThemeBackground(_ fill: Fill) {
        guard let slide = currentSlide, let location = presentation.layoutLocation(slide.layoutID) else { return }
        perform("Change Background", update: [.content, .theme]) { presentation in
            presentation.themes[location.theme].background = fill
            for index in presentation.themes[location.theme].layouts.indices {
                presentation.themes[location.theme].layouts[index].background = nil
            }
            for index in presentation.slides.indices
            where presentation.layoutLocation(presentation.slides[index].layoutID)?.theme == location.theme {
                presentation.slides[index].background = nil
            }
        }
    }

    /// The Themes panel: every slide moves to the new theme.
    func applyTheme(_ theme: SlideTheme) {
        perform("Change Theme", update: [.content, .theme], selecting: []) { presentation in
            presentation.applyTheme(theme)
        }
    }

    /// File ▸ Page setup: changes the slide size, scaling every element's position and size (and guides) to match.
    func setSlideSize(_ size: SlideSize) {
        guard size != presentation.slideSize, size.width > 0, size.height > 0 else { return }
        perform("Page Setup", update: [.content, .theme]) { presentation in presentation.changeSlideSize(to: size) }
    }

    /// Insert ▸ Slide numbers.
    func setSlideNumbers(_ shown: Bool, skipTitleSlides: Bool, onlySelected: Bool) {
        var ids = onlySelected ? selectedSlideIDs : Set(presentation.slides.map(\.id))
        if shown, skipTitleSlides {
            ids = ids.filter { id in
                guard let slide = presentation.slides.first(where: { $0.id == id }) else { return false }
                return presentation.layout(for: slide)?.kind != .title
            }
        }
        let all = onlySelected ? selectedSlideIDs : Set(presentation.slides.map(\.id))
        perform("Slide Numbers") { presentation in
            presentation.setSlideNumbers(false, slideIDs: all)
            if shown { presentation.setSlideNumbers(true, slideIDs: ids) }
        }
    }

    /// Commits speaker notes typed for a slide.
    func setNotes(_ notes: TextBody, slideID: UUID) {
        guard let index = presentation.slideIndex(id: slideID), presentation.slides[index].notes != notes else { return }
        let current = currentSlideID
        perform("Typing", update: [.notes], showing: current) { presentation in
            presentation.slides[index].notes = notes
        }
    }
}
