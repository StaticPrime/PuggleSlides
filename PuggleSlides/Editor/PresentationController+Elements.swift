import AppKit
import PuggleSlidesKit

enum OrderChange {
    case bringToFront, bringForward, sendBackward, sendToBack
}

enum AlignEdge {
    case left, center, right, top, middle, bottom
}

extension PresentationController {
    // MARK: New elements, with their defaults

    /// Lines and borders use the theme's second dark color, or its second light color on dark slides.
    var defaultLineColor: ColorRef {
        guard let slide = currentSlide else { return ColorRef(theme: .dark2) }
        let theme = presentation.theme(for: slide)
        let background: ResolvedColor = switch presentation.background(for: slide) {
        case .solid(let color): color.resolved(theme.colors)
        case .gradient(let gradient): gradient.stops.first?.color.resolved(theme.colors) ?? .white
        default: .white
        }
        return ColorRef(theme: background.luminance < 0.45 ? .light2 : .dark2)
    }

    func nextElementName(_ base: String) -> String {
        "\(base) \((currentSlide?.elements.count ?? 0) + 1)"
    }

    func makeTextBox(frame: SlideRect) -> SlideElement {
        let text = TextBody(properties: TextBodyProperties(anchor: .top, insets: .standard, autofit: .resizeShape, wraps: true))
        return SlideElement(name: nextElementName("TextBox"), placement: Placement(frame: frame),
                            content: .shape(Shape(geometry: .rectangle, text: text, isTextBox: true)))
    }

    func makeShape(_ preset: String, frame: SlideRect) -> SlideElement {
        var text = TextBody(properties: TextBodyProperties(anchor: .middle, insets: .standard, autofit: Autofit.none, wraps: true))
        text.listStyle[0] = LevelStyle(paragraph: ParagraphStyle(alignment: .center), character: CharacterStyle(fontSize: 14))
        // Arcs, brackets and braces are lines: they start without a fill.
        let lineLike: Set<String> = ["arc", "bracketPair", "bracePair", "leftBracket", "rightBracket", "leftBrace", "rightBrace"]
        let shape = Shape(geometry: .preset(preset, adjustments: PresetGeometry.defaultAdjustments(preset)),
                          fill: lineLike.contains(preset) ? Fill.none : .solid(ColorRef(theme: .accent1)),
                          outline: Outline(fill: .solid(defaultLineColor), width: 0.75), text: text)
        let title = PresetGeometry.info(named: preset)?.title ?? "Shape"
        return SlideElement(name: nextElementName(title), placement: Placement(frame: frame), content: .shape(shape))
    }

    /// A line from `start` to `end`: its frame spans the two points and flips record the direction.
    func makeLine(_ kind: LineKind, from start: SlidePoint, to end: SlidePoint) -> SlideElement {
        let frame = SlideRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let outline = Outline(fill: .solid(defaultLineColor), width: 1.5, tail: kind == .arrow ? .fillArrow : .none)
        let shape = Shape(geometry: .preset(kind.preset, adjustments: [:]), outline: outline, isConnector: true)
        return SlideElement(name: nextElementName(kind == .line ? "Straight Connector" : kind.title),
                            placement: Placement(frame: frame, flipHorizontal: end.x < start.x, flipVertical: end.y < start.y),
                            content: .shape(shape))
    }

    func makePicture(_ mediaID: MediaID, frame: SlideRect) -> SlideElement {
        SlideElement(name: nextElementName("Picture"), placement: Placement(frame: frame), content: .picture(Picture(mediaID: mediaID)))
    }

    /// Adds elements to the current slide, in front, and selects them.
    func insert(_ elements: [SlideElement], media: [MediaID: MediaItem] = [:], actionName: String) {
        guard let index = currentSlideIndex, !elements.isEmpty else { return }
        perform(actionName, selecting: elements.map(\.id)) { presentation in
            for (id, item) in media where presentation.media[id] == nil { presentation.media[id] = item }
            presentation.slides[index].elements.append(contentsOf: elements)
        }
    }

    /// Insert ▸ Image: placed in the middle of the slide at its own size, or smaller to fit.
    func insertImage(data original: Data, at center: SlidePoint? = nil) -> Bool {
        // TIFF and BMP pictures are kept as PNG, many times smaller.
        guard let (data, contentType) = MediaItem.storable(original), contentType.hasPrefix("image/"), let image = NSImage(data: data),
              image.size.width > 0 else { return false }
        let size = presentation.slideSize
        var width = Double(image.size.width), height = Double(image.size.height)
        let scale = min(1, size.width * 0.8 / width, size.height * 0.8 / height)
        width *= scale
        height *= scale
        let middle = center ?? SlidePoint(x: size.width / 2, y: size.height / 2)
        var probe = presentation
        let id = probe.addMedia(data, contentType: contentType)
        let element = makePicture(id, frame: SlideRect(x: middle.x - width / 2, y: middle.y - height / 2, width: width, height: height))
        insert([element], media: [id: probe.media[id]!], actionName: "Insert Image")
        return true
    }

    // MARK: Removing and copying

    func deleteSelectedElements() {
        let ids = Set(selectedElementIDs)
        guard let index = currentSlideIndex, !ids.isEmpty else { return }
        perform("Delete", selecting: []) { presentation in
            presentation.slides[index].elements.removeAll { ids.contains($0.id) }
        }
    }

    /// Edit ▸ Duplicate (⌘D) on the canvas: copies sit a little below and to the right.
    func duplicateSelectedElements() {
        guard let index = currentSlideIndex else { return }
        let slide = presentation.slides[index]
        let copies = selectedElements.map { element -> SlideElement in
            var copy = element.withNewIDs()
            var placement = presentation.placement(of: element, on: slide)
            placement.frame = placement.frame.offsetBy(dx: 9, dy: 9)
            copy.placement = placement
            copy.offsetChildren(dx: 9, dy: 9)
            return copy
        }
        guard !copies.isEmpty else { return }
        perform("Duplicate", selecting: copies.map(\.id)) { presentation in
            presentation.slides[index].elements.append(contentsOf: copies)
        }
    }

    // MARK: Placement

    /// Sets placements, giving inherited placeholders a position of their own.
    func setPlacements(_ placements: [UUID: Placement], actionName: String) {
        guard let index = currentSlideIndex, !placements.isEmpty else { return }
        perform(actionName) { presentation in
            Self.apply(placements, to: &presentation.slides[index])
        }
    }

    static func apply(_ placements: [UUID: Placement], to slide: inout Slide) {
        for elementIndex in slide.elements.indices {
            let id = slide.elements[elementIndex].id
            guard let placement = placements[id] else { continue }
            let old = slide.elements[elementIndex].placement
            slide.elements[elementIndex].placement = placement
            if let old, slide.elements[elementIndex].children != nil {
                slide.elements[elementIndex].transformChildren(from: old, to: placement)
            }
        }
    }

    /// Placements of the selected elements, after inheritance.
    var selectedPlacements: [UUID: Placement] {
        Dictionary(uniqueKeysWithValues: selectedElements.map { ($0.id, placement(of: $0)) })
    }

    func nudgeSelection(dx: Double, dy: Double) {
        let moved = selectedPlacements.mapValues { placement -> Placement in
            var placement = placement
            placement.frame = placement.frame.offsetBy(dx: dx, dy: dy)
            return placement
        }
        setPlacements(moved, actionName: "Move")
    }

    func rotateSelection(by degrees: Double) {
        let rotated = selectedPlacements.mapValues { placement -> Placement in
            var placement = placement
            placement.rotation = Placement.normalized(placement.rotation + degrees)
            return placement
        }
        setPlacements(rotated, actionName: "Rotate")
    }

    func flipSelection(horizontal: Bool) {
        let flipped = selectedPlacements.mapValues { placement -> Placement in
            var placement = placement
            if horizontal { placement.flipHorizontal.toggle() } else { placement.flipVertical.toggle() }
            placement.rotation = Placement.normalized(-placement.rotation)
            return placement
        }
        setPlacements(flipped, actionName: horizontal ? "Flip Horizontally" : "Flip Vertically")
    }

    /// Arrange ▸ Order.
    func changeOrder(_ change: OrderChange) {
        guard let index = currentSlideIndex else { return }
        let ids = Set(selectedElementIDs)
        guard !ids.isEmpty else { return }
        let name: String = switch change {
        case .bringToFront: "Bring to Front"
        case .bringForward: "Bring Forward"
        case .sendBackward: "Send Backward"
        case .sendToBack: "Send to Back"
        }
        perform(name) { presentation in
            var elements = presentation.slides[index].elements
            switch change {
            case .bringToFront:
                elements = elements.filter { !ids.contains($0.id) } + elements.filter { ids.contains($0.id) }
            case .sendToBack:
                elements = elements.filter { ids.contains($0.id) } + elements.filter { !ids.contains($0.id) }
            case .bringForward:
                for position in stride(from: elements.count - 2, through: 0, by: -1)
                where ids.contains(elements[position].id) && !ids.contains(elements[position + 1].id) {
                    elements.swapAt(position, position + 1)
                }
            case .sendBackward:
                for position in 1..<max(1, elements.count)
                where ids.contains(elements[position].id) && !ids.contains(elements[position - 1].id) {
                    elements.swapAt(position, position - 1)
                }
            }
            presentation.slides[index].elements = elements
        }
    }

    /// Arrange ▸ Align: one element aligns to the slide, several to the box around them.
    func align(_ edge: AlignEdge) {
        let placements = selectedPlacements
        guard !placements.isEmpty else { return }
        let boxes = placements.mapValues(\.boundingBox)
        let size = presentation.slideSize
        let target = placements.count == 1 ? SlideRect(x: 0, y: 0, width: size.width, height: size.height)
            : boxes.values.dropFirst().reduce(boxes.values.first!) { $0.union($1) }
        let aligned = placements.mapValues { placement -> Placement in
            let box = placement.boundingBox
            var dx = 0.0, dy = 0.0
            switch edge {
            case .left: dx = target.minX - box.minX
            case .center: dx = target.midX - box.midX
            case .right: dx = target.maxX - box.maxX
            case .top: dy = target.minY - box.minY
            case .middle: dy = target.midY - box.midY
            case .bottom: dy = target.maxY - box.maxY
            }
            var moved = placement
            moved.frame = placement.frame.offsetBy(dx: dx, dy: dy)
            return moved
        }
        setPlacements(aligned, actionName: "Align")
    }

    /// Arrange ▸ Distribute: equal gaps between three or more elements.
    func distribute(horizontally: Bool) {
        let placements = selectedPlacements
        guard placements.count >= 3 else { return }
        let sorted = placements.sorted { a, b in
            horizontally ? a.value.boundingBox.minX < b.value.boundingBox.minX : a.value.boundingBox.minY < b.value.boundingBox.minY
        }
        let boxes = sorted.map(\.value.boundingBox)
        let total = boxes.reduce(0) { $0 + (horizontally ? $1.width : $1.height) }
        let start = horizontally ? boxes.first!.minX : boxes.first!.minY
        let end = horizontally ? boxes.map(\.maxX).max()! : boxes.map(\.maxY).max()!
        let gap = (end - start - total) / Double(boxes.count - 1)
        var position = start
        var result: [UUID: Placement] = [:]
        for (id, placement) in sorted {
            let box = placement.boundingBox
            var moved = placement
            moved.frame = horizontally ? placement.frame.offsetBy(dx: position - box.minX, dy: 0) : placement.frame.offsetBy(dx: 0, dy: position - box.minY)
            result[id] = moved
            position += (horizontally ? box.width : box.height) + gap
        }
        setPlacements(result, actionName: "Distribute")
    }

    /// Arrange ▸ Center on page: the selection as a whole moves to the middle of the slide.
    func centerOnPage(horizontally: Bool) {
        let placements = selectedPlacements
        guard let first = placements.values.first else { return }
        let box = placements.values.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        let size = presentation.slideSize
        let dx = horizontally ? size.width / 2 - box.midX : 0
        let dy = horizontally ? 0 : size.height / 2 - box.midY
        setPlacements(placements.mapValues { placement in
            var moved = placement
            moved.frame = placement.frame.offsetBy(dx: dx, dy: dy)
            return moved
        }, actionName: "Center on Page")
    }

    // MARK: Groups

    var canGroup: Bool {
        selectedElements.count >= 2 && selectedElements.allSatisfy { $0.placeholder == nil }
    }

    var canUngroup: Bool { selectedElements.contains { $0.children != nil } }

    func groupSelection() {
        guard canGroup, let index = currentSlideIndex else { return }
        let slide = presentation.slides[index]
        let ids = Set(selectedElementIDs)
        let children = slide.elements.filter { ids.contains($0.id) }.map { element -> SlideElement in
            var child = element
            child.placement = presentation.placement(of: element, on: slide)
            return child
        }
        let box = children.dropFirst().reduce(children[0].placement!.boundingBox) { $0.union($1.placement!.boundingBox) }
        let group = SlideElement(name: nextElementName("Group"), placement: Placement(frame: box), content: .group(children))
        let position = slide.elements.lastIndex { ids.contains($0.id) } ?? slide.elements.count - 1
        perform("Group", selecting: [group.id]) { presentation in
            var elements = presentation.slides[index].elements
            elements.insert(group, at: position + 1)
            elements.removeAll { ids.contains($0.id) }
            presentation.slides[index].elements = elements
        }
    }

    func ungroupSelection() {
        guard let index = currentSlideIndex else { return }
        let ids = Set(selectedElementIDs)
        var released: [UUID] = []
        perform("Ungroup", selecting: nil) { presentation in
            var elements: [SlideElement] = []
            for element in presentation.slides[index].elements {
                if ids.contains(element.id), let children = element.children {
                    elements.append(contentsOf: children)
                    released.append(contentsOf: children.map(\.id))
                } else {
                    elements.append(element)
                }
            }
            presentation.slides[index].elements = elements
        }
        selectElements(released)
    }
}

extension SlideElement {
    /// Moves a group's children along with it.
    mutating func offsetChildren(dx: Double, dy: Double) {
        guard var children else { return }
        for index in children.indices {
            if var placement = children[index].placement {
                placement.frame = placement.frame.offsetBy(dx: dx, dy: dy)
                children[index].placement = placement
            }
            children[index].offsetChildren(dx: dx, dy: dy)
        }
        self.children = children
    }

    /// Keeps a group's children in the same relative spots when the group moves, resizes, rotates or flips.
    mutating func transformChildren(from old: Placement, to new: Placement) {
        guard var children else { return }
        let oldFrame = old.frame, newFrame = new.frame
        let sx = oldFrame.width == 0 ? 1 : newFrame.width / oldFrame.width
        let sy = oldFrame.height == 0 ? 1 : newFrame.height / oldFrame.height
        let rotation = new.rotation - old.rotation
        let flipH = old.flipHorizontal != new.flipHorizontal, flipV = old.flipVertical != new.flipVertical
        for index in children.indices {
            guard var placement = children[index].placement else { continue }
            let oldChildFrame = placement.frame
            // The child's center in the group's unrotated space, scaled and flipped into the new frame.
            let local = old.shapePoint(fromSlide: placement.frame.center)
            var x = local.x * sx, y = local.y * sy
            if flipH { x = newFrame.width - x }
            if flipV { y = newFrame.height - y }
            let center = new.slidePoint(fromShape: SlidePoint(x: x, y: y))
            let width = oldChildFrame.width * sx, height = oldChildFrame.height * sy
            placement.frame = SlideRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            placement.rotation = Placement.normalized(placement.rotation + rotation)
            if flipH { placement.flipHorizontal.toggle() }
            if flipV { placement.flipVertical.toggle() }
            let childOld = Placement(frame: oldChildFrame, rotation: children[index].placement!.rotation,
                                     flipHorizontal: children[index].placement!.flipHorizontal, flipVertical: children[index].placement!.flipVertical)
            children[index].placement = placement
            if children[index].children != nil { children[index].transformChildren(from: childOld, to: placement) }
        }
        self.children = children
    }
}
