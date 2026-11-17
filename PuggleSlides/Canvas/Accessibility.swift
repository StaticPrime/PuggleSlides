import AppKit
import PuggleSlidesKit

/// What VoiceOver says about slides and the objects on them.
enum SlideAccessibility {
    /// A slide's title placeholder text, on one line.
    static func title(of slide: Slide) -> String {
        let text = slide.elements.first { $0.placeholder?.type.isTitle == true }?.shape?.text?.plainText ?? ""
        return text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// "Slide 3 of 12, Highlights, skipped, 2 comments".
    static func label(of slide: Slide, index: Int, count: Int) -> String {
        var parts = ["Slide \(index + 1) of \(count)"]
        let title = title(of: slide)
        if !title.isEmpty { parts.append(title) }
        if slide.isSkipped { parts.append("skipped") }
        let comments = slide.comments.filter { !$0.isResolved }.count
        if comments > 0 { parts.append(comments == 1 ? "1 comment" : "\(comments) comments") }
        return parts.joined(separator: ", ")
    }

    /// What a slide says, read aloud as it's presented: "Slide 3 of 12. Highlights. Walks are up…", with pictures' alt text.
    static func spokenText(of slide: Slide, index: Int, count: Int) -> String {
        var parts = ["Slide \(index + 1) of \(count)"]
        func visit(_ elements: [SlideElement]) {
            for element in elements {
                if case .group(let children) = element.content {
                    visit(children)
                    continue
                }
                let info = describe(element)
                if let value = info.value, !value.isEmpty {
                    parts.append(value.replacingOccurrences(of: "\n", with: ". "))
                } else if info.role == .image, element.altTitle != nil || element.altDescription != nil {
                    parts.append(info.label)
                }
            }
        }
        visit(slide.elements)
        return parts.joined(separator: ". ")
    }

    struct Description {
        var role: NSAccessibility.Role
        var roleDescription: String
        var label: String
        var value: String?
    }

    /// An object as VoiceOver reads it: its alt text when it has some, else its text or what it is.
    static func describe(_ element: SlideElement) -> Description {
        let alt = [element.altTitle, element.altDescription].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        func named(_ fallback: String) -> String { !alt.isEmpty ? alt : element.name.isEmpty ? fallback : element.name }
        switch element.content {
        case .picture:
            return Description(role: .image, roleDescription: "image", label: named("Image"))
        case .chart(let chart):
            return Description(role: .image, roleDescription: "chart", label: !alt.isEmpty ? alt : chart.title.isEmpty ? "Chart" : chart.title)
        case .table(let table):
            return Description(role: .group, roleDescription: "table",
                               label: !alt.isEmpty ? alt : "\(table.rowCount) rows, \(table.columnCount) columns", value: table.plainText)
        case .group(let children):
            return Description(role: .group, roleDescription: "group", label: !alt.isEmpty ? alt : "\(children.count) objects")
        case .media(let clip):
            return Description(role: .image, roleDescription: clip.isVideo ? "video" : "audio", label: named(clip.isVideo ? "Video" : "Audio"))
        case .shape(let shape):
            if element.isLine { return Description(role: .image, roleDescription: "line", label: named("Line")) }
            let kind = element.isWordArt ? "word art" : element.placeholder != nil ? "placeholder" : shape.isTextBox ? "text box" : "shape"
            let text = shape.text?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { return Description(role: .image, roleDescription: kind, label: named(kind.capitalized)) }
            return Description(role: .staticText, roleDescription: kind, label: alt.isEmpty ? element.name : alt, value: text)
        }
    }
}

/// One object on the canvas for VoiceOver: placed where it's drawn, and selected by pressing it. AppKit only asks on
/// the main thread, where the canvas lives; each answer reads the canvas there.
nonisolated final class SlideObjectAccessibility: NSAccessibilityElement {
    let elementID: UUID
    private weak var canvas: SlideEditingView?

    init(elementID: UUID, canvas: SlideEditingView) {
        self.elementID = elementID
        self.canvas = canvas
        super.init()
    }

    private func read<T>(_ body: @MainActor (SlideEditingView, UUID, SlideAccessibility.Description?) -> T?) -> T? {
        let canvas = canvas, id = elementID
        nonisolated(unsafe) var result: T?
        MainActor.assumeIsolated {
            guard let canvas else { return }
            result = body(canvas, id, canvas.controller.currentSlide?.element(id: id).map(SlideAccessibility.describe))
        }
        return result
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityParent() -> Any? { read { canvas, _, _ in canvas } }
    override func accessibilityRole() -> NSAccessibility.Role? { read { $2?.role } }
    override func accessibilityRoleDescription() -> String? { read { $2?.roleDescription } }
    override func accessibilityLabel() -> String? { read { $2?.label } }
    override func accessibilityValue() -> Any? { read { $2?.value } }
    override func accessibilityFrame() -> NSRect { read { canvas, id, _ in canvas.screenFrame(ofElement: id) } ?? .zero }
    override func isAccessibilitySelected() -> Bool { read { canvas, id, _ in canvas.controller.selectedElementIDs.contains(id) } ?? false }

    override func accessibilityPerformPress() -> Bool {
        read { canvas, id, _ in
            canvas.controller.selectElements([id])
            return true
        } ?? false
    }
}

/// One slide in the filmstrip or grid view for VoiceOver; like the canvas's elements, read on the main thread.
nonisolated final class SlideThumbnailAccessibility: NSAccessibilityElement {
    let slideID: UUID
    private weak var filmstrip: FilmstripView?

    init(slideID: UUID, filmstrip: FilmstripView) {
        self.slideID = slideID
        self.filmstrip = filmstrip
        super.init()
    }

    private func read<T>(_ body: @MainActor (FilmstripView, UUID, Int) -> T?) -> T? {
        let filmstrip = filmstrip, id = slideID
        nonisolated(unsafe) var result: T?
        MainActor.assumeIsolated {
            guard let filmstrip, let index = filmstrip.controller.presentation.slideIndex(id: id) else { return }
            result = body(filmstrip, id, index)
        }
        return result
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityParent() -> Any? { read { filmstrip, _, _ in filmstrip } }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityRoleDescription() -> String? { "slide" }

    override func accessibilityLabel() -> String? {
        read { filmstrip, _, index in
            let slides = filmstrip.controller.presentation.slides
            return SlideAccessibility.label(of: slides[index], index: index, count: slides.count)
        }
    }

    override func accessibilityFrame() -> NSRect {
        read { filmstrip, _, index in
            filmstrip.window.map { $0.convertToScreen(filmstrip.convert(filmstrip.thumbnailRect(at: index), to: nil)) }
        } ?? .zero
    }

    override func isAccessibilitySelected() -> Bool {
        read { filmstrip, id, _ in filmstrip.controller.selectedSlideIDs.contains(id) } ?? false
    }

    override func accessibilityPerformPress() -> Bool {
        read { filmstrip, id, _ in
            filmstrip.controller.selectSlide(id)
            return true
        } ?? false
    }
}

extension SlideEditingView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityRoleDescription() -> String? { "slide" }

    override func accessibilityLabel() -> String? {
        guard let slide = controller.currentSlide, let index = controller.currentSlideIndex else { return "No slides" }
        return SlideAccessibility.label(of: slide, index: index, count: controller.presentation.slides.count)
    }

    /// The slide's objects back to front, the order Tab moves through them. The same object stays the same element,
    /// so VoiceOver keeps its place.
    override func accessibilityChildren() -> [Any]? {
        let ids = controller.currentSlide?.elements.map(\.id) ?? []
        let kept = Set(ids)
        accessibilityObjects = accessibilityObjects.filter { kept.contains($0.key) }
        return ids.map { id in
            if let object = accessibilityObjects[id] { return object }
            let object = SlideObjectAccessibility(elementID: id, canvas: self)
            accessibilityObjects[id] = object
            return object
        }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        accessibilityChildren()?.filter { ($0 as? SlideObjectAccessibility)?.isAccessibilitySelected() == true }
    }

    /// An object's frame on screen: the bounds of its frame as placed, turned and flipped.
    func screenFrame(ofElement id: UUID) -> NSRect {
        guard let element = controller.currentSlide?.element(id: id), let window else { return .zero }
        let placement = controller.placement(of: element)
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let slideRect = CGRect(origin: .zero, size: size).applying(placement.transform)
        return window.convertToScreen(convert(slideRect.offsetBy(dx: margin, dy: margin), to: nil))
    }
}

extension SlideStageView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityRoleDescription() -> String? { "slideshow" }

    override func accessibilityLabel() -> String? {
        guard let controller else { return nil }
        return SlideAccessibility.spokenText(of: controller.currentSlide, index: controller.currentSlideIndex,
                                             count: controller.presentation.slides.count)
    }
}

extension FilmstripView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { isGrid ? "Grid view" : "Filmstrip" }

    override func accessibilityChildren() -> [Any]? {
        let ids = controller.presentation.slides.map(\.id)
        let kept = Set(ids)
        accessibilityThumbnails = accessibilityThumbnails.filter { kept.contains($0.key) }
        return ids.map { id in
            if let thumbnail = accessibilityThumbnails[id] { return thumbnail }
            let thumbnail = SlideThumbnailAccessibility(slideID: id, filmstrip: self)
            accessibilityThumbnails[id] = thumbnail
            return thumbnail
        }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        accessibilityChildren()?.filter { ($0 as? SlideThumbnailAccessibility)?.isAccessibilitySelected() == true }
    }
}
