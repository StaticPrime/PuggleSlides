import Foundation

extension PlaceholderType {
    /// The name PowerPoint gives a new placeholder of this type ("Title 1", "Text Placeholder 2").
    var defaultName: String {
        switch self {
        case .title, .centeredTitle: "Title"
        case .subtitle: "Subtitle"
        case .slideNumber: "Slide Number Placeholder"
        case .date: "Date Placeholder"
        case .footer: "Footer Placeholder"
        default: "Text Placeholder"
        }
    }
}

extension Presentation {
    /// A new slide with its layout's placeholders, empty. Footer placeholders
    /// (slide numbers, dates) stay off until they're switched on.
    public func makeSlide(layoutID: UUID) -> Slide {
        var slide = Slide(layoutID: layoutID)
        guard let layout = layout(id: layoutID) else { return slide }
        var number = 1
        for element in layout.elements {
            guard let ref = element.placeholder, !ref.type.isFooterKind else { continue }
            slide.elements.append(Self.emptyPlaceholder(ref, geometry: element.shape?.geometry, number: &number))
        }
        return slide
    }

    static func emptyPlaceholder(_ ref: PlaceholderRef, geometry: ShapeGeometry?, number: inout Int) -> SlideElement {
        defer { number += 1 }
        return SlideElement(name: "\(ref.type.defaultName) \(number)", placement: nil, placeholder: ref,
                            content: .shape(Shape(geometry: geometry ?? .rectangle, text: TextBody())))
    }

    /// A copy of a slide with new ids for it and its elements; its animations follow their elements, and its comments
    /// stay with the original.
    public func duplicate(_ slide: Slide) -> Slide {
        var copy = slide
        copy.id = UUID()
        copy.comments = []
        copy.elements = slide.elements.map { $0.withNewIDs() }
        let newIDs = Dictionary(uniqueKeysWithValues: zip(slide.elements.map(\.id), copy.elements.map(\.id)))
        copy.animations = slide.animations.compactMap { animation in
            guard let elementID = newIDs[animation.elementID] else { return nil }
            var moved = animation
            moved.id = UUID()
            moved.elementID = elementID
            return moved
        }
        return copy
    }

    /// Slide ▸ Transition ▸ Apply to all slides.
    public mutating func setTransition(_ transition: SlideTransition?, slideIDs: Set<UUID>) {
        let value = transition?.kind == TransitionKind.none ? nil : transition
        for index in slides.indices where slideIDs.contains(slides[index].id) {
            slides[index].transition = value
        }
    }

    /// Apply layout: text moves into the new layout's matching placeholders, which take the
    /// layout's positions; empty placeholders with no match go away; other elements stay as they are.
    public mutating func applyLayout(_ layoutID: UUID, toSlideAt index: Int) {
        guard slides.indices.contains(index), let layout = layout(id: layoutID) else { return }
        let slide = slides[index]
        let oldTheme = theme(for: slide)
        var remaining = slide.elements
        var adopted: [UUID: SlideElement] = [:]
        var added: [SlideElement] = []
        var number = slide.elements.count + 1

        func take(_ match: (SlideElement) -> Bool) -> SlideElement? {
            guard let position = remaining.firstIndex(where: { $0.placeholder != nil && match($0) }) else { return nil }
            return remaining.remove(at: position)
        }
        for target in layout.elements {
            guard let ref = target.placeholder else { continue }
            let found = take { $0.placeholder == ref }
                ?? take { $0.placeholder?.type == ref.type }
                ?? take { Self.compatible($0.placeholder!.type, ref.type) }
            if var element = found {
                element.placeholder = ref
                element.placement = nil
                adopted[element.id] = element
            } else if !ref.type.isFooterKind {
                added.append(Self.emptyPlaceholder(ref, geometry: target.shape?.geometry, number: &number))
            }
        }
        // Placeholders left over keep their text where it was, as ordinary text in a fixed spot.
        var result: [SlideElement] = added
        for element in slide.elements {
            if let moved = adopted[element.id] {
                result.append(moved)
            } else if remaining.contains(where: { $0.id == element.id }) {
                guard element.placeholder != nil else {
                    result.append(element)
                    continue
                }
                if element.shape?.text?.isEmpty ?? true { continue }
                result.append(detached(element, on: slide, theme: oldTheme))
            }
        }
        slides[index].layoutID = layoutID
        slides[index].elements = result
    }

    static func compatible(_ a: PlaceholderType, _ b: PlaceholderType) -> Bool {
        let titles: Set<PlaceholderType> = [.title, .centeredTitle]
        let bodies: Set<PlaceholderType> = [.body, .object, .subtitle]
        return (titles.contains(a) && titles.contains(b)) || (bodies.contains(a) && bodies.contains(b))
    }

    /// A placeholder turned into an ordinary text box with the position and formatting it had.
    public func detached(_ element: SlideElement, on slide: Slide, theme: Theme) -> SlideElement {
        let style = style(for: element, on: slide)
        var copy = element
        copy.placeholder = nil
        copy.placement = style.placement
        if var shape = copy.shape {
            shape.fill = style.fill
            shape.outline = style.outline
            if var text = shape.text {
                let properties = style.bodyProperties
                text.properties = TextBodyProperties(anchor: properties.anchor, insets: properties.insets, autofit: properties.autofit,
                                                     fontScale: text.properties.fontScale, lineSpacingReduction: text.properties.lineSpacingReduction,
                                                     wraps: properties.wraps)
                var listStyle = ListStyle()
                for level in Set(text.paragraphs.map(\.level)) { listStyle[level] = style.levelStyle(level) }
                text.listStyle = listStyle
                shape.text = text
            }
            shape.isTextBox = true
            copy.shape = shape
        }
        return copy
    }

    /// Change theme: every slide moves to the new theme's layout of the same kind (or name),
    /// keeping its text. Slides whose layout has no counterpart get "Title and body".
    public mutating func applyTheme(_ theme: Theme) {
        let oldSlides = slides
        let oldThemes = themes
        themes = [theme]
        for (index, slide) in oldSlides.enumerated() {
            let oldLayout = oldThemes.lazy.compactMap { $0.layout(id: slide.layoutID) }.first
            let target = oldLayout.flatMap { old in
                (old.kind == .custom ? nil : theme.layout(kind: old.kind))
                    ?? theme.layouts.first { $0.name.caseInsensitiveCompare(old.name) == .orderedSame }
            } ?? theme.layout(kind: .titleAndBody) ?? theme.layouts.first
            guard let target else { continue }
            slides[index].layoutID = target.id
            // Placeholders keep their inheritance; any whose kind the new layout lacks are detached in place.
            let restored = Presentation(slideSize: slideSize, themes: oldThemes, slides: [slide], media: [:], defaultTextStyle: defaultTextStyle)
            slides[index].elements = slide.elements.compactMap { element in
                guard let ref = element.placeholder else { return element }
                if target.placeholder(matching: ref) != nil || ref.type.isFooterKind { return element }
                if element.shape?.text?.isEmpty ?? true { return nil }
                return restored.detached(element, on: slide, theme: restored.theme(for: slide))
            }
        }
        removeUnusedMedia()
    }

    /// Insert ▸ Slide numbers: adds or removes the slide number on the given slides.
    public mutating func setSlideNumbers(_ shown: Bool, slideIDs: Set<UUID>) {
        for index in slides.indices where slideIDs.contains(slides[index].id) {
            let hasNumber = slides[index].elements.contains { $0.placeholder?.type == .slideNumber }
            if shown, !hasNumber {
                let ref = layout(for: slides[index])?.elements.first { $0.placeholder?.type == .slideNumber }?.placeholder
                    ?? PlaceholderRef(type: .slideNumber, index: 12)
                var paragraph = TextParagraph(runs: [TextRun("‹#›", field: .slideNumber)])
                paragraph.style.alignment = nil
                let element = SlideElement(name: "Slide Number \(slides[index].elements.count + 1)", placement: nil, placeholder: ref,
                                           content: .shape(Shape(text: TextBody(paragraphs: [paragraph]))))
                slides[index].elements.append(element)
            } else if !shown, hasNumber {
                slides[index].elements.removeAll { $0.placeholder?.type == .slideNumber }
            }
        }
    }
}
