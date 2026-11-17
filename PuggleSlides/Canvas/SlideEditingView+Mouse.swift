import AppKit
import PuggleSlidesKit

extension SlideEditingView {
    private var dragThreshold: CGFloat { screen(3) }

    override func mouseDown(with event: NSEvent) {
        let point = slidePoint(convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        if editor != nil { endEditing() }
        guard controller.currentSlide != nil else {
            if event.clickCount >= 1 { controller.newSlide() }
            return
        }
        if cropping != nil, cropMouseDown(at: point) { return }
        if tool.isInsertTool {
            drag = .creating(tool: tool, start: point)
            creationPreview = (tool, point, point)
            return
        }
        if let handle = handle(at: point) {
            beginHandleDrag(handle, at: point)
            return
        }
        let modifiers = event.modifierFlags
        let hit = element(at: point)
        if let hit, onPaintFormat?(hit) == true { return }
        if hit == nil, let guide = guide(at: point) {
            controller.beginInteractive()
            drag = .guide(id: guide.id)
            return
        }
        if let hit, hit.table != nil, !modifiers.contains(.command), tableMouseDown(hit, at: point, event: event) { return }
        // A selected video's play button plays it.
        if event.clickCount == 1, let hit, hit.media?.isVideo == true, controller.selectedElementIDs == [hit.id], playButtonContains(point, of: hit) {
            onPlayMedia?(hit.id)
            return
        }
        if event.clickCount >= 2, let hit {
            // Double-clicks: a picture's crop marks, word art's text, a chart's editor, a video or sound playing.
            if hit.picture != nil { return beginCropping(hit.id) }
            if hit.media != nil {
                controller.selectElements([hit.id])
                onPlayMedia?(hit.id)
                return
            }
            if hit.isWordArt {
                controller.selectElements([hit.id])
                onEditWordArt?(hit.id)
                return
            }
            if hit.chart != nil {
                controller.selectElements([hit.id])
                onEditChart?()
                return
            }
        }
        if event.clickCount >= 2, let hit, hit.shape != nil, !hit.isLine {
            controller.selectElements([hit.id])
            beginEditing(hit.id, at: point)
            return
        }
        guard let hit else {
            let additive = modifiers.contains(.shift) || modifiers.contains(.command)
            if !additive { controller.selectElements([]) }
            drag = .marquee(start: point, additive: additive, original: controller.selectedElementIDs)
            return
        }
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            var ids = controller.selectedElementIDs
            if let index = ids.firstIndex(of: hit.id) { ids.remove(at: index) } else { ids.append(hit.id) }
            controller.selectElements(ids)
            drag = .pending(start: point, elementID: hit.id, editOnRelease: false)
            return
        }
        let wasSelected = controller.selectedElementIDs.contains(hit.id)
        if !wasSelected { controller.selectElements([hit.id]) }
        // Text boxes and placeholders take a click straight into their text; other shapes on a second click.
        let isTextHolder = hit.shape?.isTextBox == true || hit.placeholder != nil
        let editOnRelease = hit.shape != nil && !hit.isLine && hit.children == nil && !hit.isWordArt
            && (isTextHolder || (wasSelected && controller.selectedElementIDs.count == 1))
        drag = .pending(start: point, elementID: hit.id, editOnRelease: editOnRelease)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = slidePoint(convert(event.locationInWindow, from: nil))
        autoscroll(with: event)
        guard let drag else { return }
        let modifiers = event.modifierFlags
        switch drag {
        case .pending(let start, _, _):
            guard hypot(point.x - start.x, point.y - start.y) > dragThreshold else { return }
            controller.beginInteractive()
            if modifiers.contains(.option) { duplicateForDrag() }
            self.drag = .moving(start: start, original: controller.selectedPlacements)
            mouseDragged(with: event)
        case .moving(let start, let original):
            var dx = point.x - start.x, dy = point.y - start.y
            if modifiers.contains(.shift) {
                if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
            }
            // Command turns snapping off for this move.
            if !modifiers.contains(.command) {
                let snapped = snappedOffset(dx: dx, dy: dy, original: original)
                dx = modifiers.contains(.shift) && dx == 0 ? 0 : snapped.dx
                dy = modifiers.contains(.shift) && dy == 0 ? 0 : snapped.dy
            } else {
                snapLines = []
            }
            let moved = original.mapValues { placement -> Placement in
                var placement = placement
                placement.frame = placement.frame.offsetBy(dx: dx, dy: dy)
                return placement
            }
            apply(moved)
        case .resizing(let u, let v, let original, let box):
            if original.count == 1, let (id, placement) = original.first {
                let resized = Self.resize(placement, u: u, v: v, to: point, keepAspect: modifiers.contains(.shift) && u != 1 && v != 1,
                                          fromCenter: modifiers.contains(.option))
                let free = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option)
                apply([id: free ? resized : snappedResize(resized, u: u, v: v, id: id)])
            } else {
                apply(Self.resize(original, box: box, u: u, v: v, to: point, keepAspect: modifiers.contains(.shift)))
            }
        case .rotating(let center, let startAngle, let original, let id):
            var angle = original.rotation + (atan2(point.y - center.y, point.x - center.x) * 180 / .pi - startAngle)
            if modifiers.contains(.shift) { angle = (angle / 15).rounded() * 15 }
            var placement = original
            placement.rotation = Placement.normalized(angle)
            apply([id: placement])
        case .adjusting(let name, let element, let placement):
            guard case .shape(var shape) = element.content else { return }
            let size = CGRect(x: 0, y: 0, width: abs(placement.frame.width), height: abs(placement.frame.height))
            let local = placement.shapePoint(fromSlide: point).cgPoint
            let adjustments = PresetGeometry.adjustments(for: shape.geometry, in: size, dragging: name, to: local)
            if case .preset(let preset, _) = shape.geometry { shape.geometry = .preset(preset, adjustments: adjustments) }
            let id = element.id
            controller.updateInteractive { presentation in
                guard let slideIndex = self.controller.currentSlideIndex,
                      let index = presentation.slides[slideIndex].elementIndex(id: id) else { return }
                presentation.slides[slideIndex].elements[index].shape = shape
            }
        case .movingLineEnd(let head, let fixed, let id):
            var end = point
            if modifiers.contains(.shift) { end = Self.snapAngle(from: fixed, to: point) }
            let start = head ? end : fixed, finish = head ? fixed : end
            let frame = SlideRect(x: min(start.x, finish.x), y: min(start.y, finish.y), width: abs(finish.x - start.x), height: abs(finish.y - start.y))
            apply([id: Placement(frame: frame, flipHorizontal: finish.x < start.x, flipVertical: finish.y < start.y)])
        case .marquee(let start, let additive, let original):
            let rect = SlideRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            marquee = rect.cgRect
            let inside = elements(inside: rect)
            controller.selectElements(additive ? original + inside.filter { !original.contains($0) } : inside)
            needsDisplay = true
        case .creating(let tool, let start):
            var end = point
            if modifiers.contains(.shift) {
                if case .line = tool {
                    end = Self.snapAngle(from: start, to: point)
                } else {
                    let side = max(abs(point.x - start.x), abs(point.y - start.y))
                    end = SlidePoint(x: start.x + (point.x < start.x ? -side : side), y: start.y + (point.y < start.y ? -side : side))
                }
            }
            creationPreview = (tool, start, end)
            needsDisplay = true
        case .tableCells, .tableBorder:
            tableDragged(drag, to: point)
        case .cropping(let u, let v):
            cropDragged(u: u, v: v, to: point)
        case .guide(let id):
            guideDragged(id, to: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = slidePoint(convert(event.locationInWindow, from: nil))
        defer {
            drag = nil
            marquee = nil
            creationPreview = nil
            snapLines = []
            needsDisplay = true
        }
        guard let drag else { return }
        switch drag {
        case .pending(_, let id, let editOnRelease):
            if editOnRelease, let id { beginEditing(id, at: point) }
        case .moving:
            controller.endInteractive(actionName: "Move")
        case .resizing:
            fitResizedText()
            controller.endInteractive(actionName: "Resize")
        case .rotating:
            controller.endInteractive(actionName: "Rotate")
        case .adjusting:
            controller.endInteractive(actionName: "Adjust Shape")
        case .movingLineEnd:
            controller.endInteractive(actionName: "Move")
        case .marquee:
            break
        case .creating(let tool, let start):
            create(tool, from: start, to: creationPreview?.end ?? point)
        case .tableCells, .cropping:
            break
        case .tableBorder(_, let horizontal, _, _):
            controller.endInteractive(actionName: horizontal ? "Resize Row" : "Resize Column")
        case .guide(let id):
            guideDropped(id)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = slidePoint(convert(event.locationInWindow, from: nil))
        hoveredElementID = tool == .select ? element(at: point)?.id : nil
        updateCursor(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredElementID = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = slidePoint(convert(event.locationInWindow, from: nil))
        if editor != nil, editor?.cell == nil, let menu = editor?.textView.menu(for: event) { return menu }
        let hit = element(at: point)
        if hit == nil, let guide = guide(at: point) {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Delete guide", action: #selector(deleteGuideFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = guide.id
            menu.addItem(item)
            return menu
        }
        if let hit, !controller.selectedElementIDs.contains(hit.id) { controller.selectElements([hit.id]) }
        if hit == nil { controller.selectElements([]) }
        return menuProvider?(hit)
    }

    override func magnify(with event: NSEvent) {
        enclosingScrollView?.magnify(with: event)
    }

    // MARK: Cursor

    private func updateCursor(at point: SlidePoint) {
        if tool.isInsertTool {
            NSCursor.crosshair.set()
        } else if let handle = handle(at: point) {
            switch handle {
            case .resize(let u, let v):
                if u == 1 { NSCursor.resizeUpDown.set() } else if v == 1 { NSCursor.resizeLeftRight.set() } else { NSCursor.crosshair.set() }
            case .rotate, .adjust, .lineStart, .lineEnd:
                NSCursor.pointingHand.set()
            }
        } else if element(at: point) == nil, let guide = guide(at: point) {
            (guide.orientation == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        } else if let element = element(at: point), element.table != nil {
            NSCursor.iBeam.set()
        } else if let element = element(at: point), element.shape?.isTextBox == true || element.placeholder != nil {
            NSCursor.iBeam.set()
        } else if element(at: point) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Dragging

    private func apply(_ placements: [UUID: Placement]) {
        controller.updateInteractive { presentation in
            guard let index = self.controller.currentSlideIndex else { return }
            PresentationController.apply(placements, to: &presentation.slides[index])
        }
    }

    private func beginHandleDrag(_ handle: Handle, at point: SlidePoint) {
        let selected = controller.selectedElements
        controller.beginInteractive()
        switch handle {
        case .resize(let u, let v):
            drag = .resizing(u: u, v: v, original: controller.selectedPlacements, box: selectionBox())
        case .rotate:
            guard let element = selected.first else { return }
            let placement = controller.placement(of: element)
            let center = placement.frame.center
            drag = .rotating(center: center, startAngle: atan2(point.y - center.y, point.x - center.x) * 180 / .pi,
                             original: placement, elementID: element.id)
        case .adjust(let name):
            guard let element = selected.first else { return }
            drag = .adjusting(name: name, element: element, placement: controller.placement(of: element))
        case .lineStart, .lineEnd:
            guard let element = selected.first else { return }
            let others = handles()
            let fixedHandle: Handle = handle == .lineStart ? .lineEnd : .lineStart
            guard let fixed = others.first(where: { $0.0 == fixedHandle })?.1 else { return }
            drag = .movingLineEnd(head: handle == .lineStart, fixed: SlidePoint(fixed), elementID: element.id)
        }
    }

    /// Option-drag: the drag moves copies, leaving the originals where they were.
    private func duplicateForDrag() {
        guard let slideIndex = controller.currentSlideIndex else { return }
        let slide = controller.presentation.slides[slideIndex]
        let copies = controller.selectedElements.map { element -> SlideElement in
            var copy = element.withNewIDs()
            copy.placement = controller.presentation.placement(of: element, on: slide)
            return copy
        }
        controller.updateInteractive { presentation in
            presentation.slides[slideIndex].elements.append(contentsOf: copies)
        }
        controller.selectElements(copies.map(\.id))
    }

    static func snapAngle(from start: SlidePoint, to point: SlidePoint) -> SlidePoint {
        let dx = point.x - start.x, dy = point.y - start.y
        let length = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return SlidePoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// Resizes one element by a handle, keeping the opposite handle where it is, even when rotated. Dragging past
    /// the opposite side flips the element.
    static func resize(_ placement: Placement, u: Int, v: Int, to point: SlidePoint, keepAspect: Bool, fromCenter: Bool) -> Placement {
        let frame = placement.frame
        let w = abs(frame.width), h = abs(frame.height)
        let radians = placement.rotation * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let upright = Placement(frame: frame, rotation: placement.rotation).transform
        let fu = Double(u) / 2, fv = Double(v) / 2
        let anchor = fromCenter ? CGPoint(x: w / 2, y: h / 2).applying(upright)
            : CGPoint(x: (1 - fu) * w, y: (1 - fv) * h).applying(upright)
        // The pointer, relative to the anchor, in the element's own (unrotated) directions.
        let px = point.x - anchor.x, py = point.y - anchor.y
        let dx = px * cosine + py * sine
        let dy = -px * sine + py * cosine
        let factor: Double = fromCenter ? 2 : 1
        var width = u == 1 ? w : (u == 2 ? dx : -dx) * factor
        var height = v == 1 ? h : (v == 2 ? dy : -dy) * factor
        if keepAspect, w > 0, h > 0 {
            let scale = max(abs(width) / w, abs(height) / h)
            width = (width < 0 ? -1 : 1) * w * scale
            height = (height < 0 ? -1 : 1) * h * scale
        }
        let flipH = width < 0, flipV = height < 0
        width = max(abs(width), 1)
        height = max(abs(height), 1)
        // The new center, offset from the anchor along the element's own axes. Edge handles keep the other
        // dimension centered on the anchor's line.
        let cx = fromCenter || u == 1 ? 0 : (u == 2 ? 1.0 : -1.0) * (flipH ? -1 : 1) * width / 2
        let cy = fromCenter || v == 1 ? 0 : (v == 2 ? 1.0 : -1.0) * (flipV ? -1 : 1) * height / 2
        let center = CGPoint(x: anchor.x + cx * cosine - cy * sine, y: anchor.y + cx * sine + cy * cosine)
        return Placement(frame: SlideRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                         rotation: placement.rotation, flipHorizontal: placement.flipHorizontal != flipH,
                         flipVertical: placement.flipVertical != flipV)
    }

    /// Resizes several elements together by the box around them, scaling positions from the opposite side.
    static func resize(_ placements: [UUID: Placement], box: SlideRect, u: Int, v: Int, to point: SlidePoint, keepAspect: Bool) -> [UUID: Placement] {
        let anchorX = u == 0 ? box.maxX : box.minX, anchorY = v == 0 ? box.maxY : box.minY
        var sx = 1.0, sy = 1.0
        if u != 1 { sx = max(0.02, (u == 2 ? point.x - anchorX : anchorX - point.x) / max(box.width, 1)) }
        if v != 1 { sy = max(0.02, (v == 2 ? point.y - anchorY : anchorY - point.y) / max(box.height, 1)) }
        if keepAspect, u != 1, v != 1 {
            sx = max(sx, sy)
            sy = sx
        }
        return placements.mapValues { placement in
            var result = placement
            let frame = placement.frame
            result.frame = SlideRect(x: anchorX + (frame.x - anchorX) * sx, y: anchorY + (frame.y - anchorY) * sy,
                                     width: frame.width * sx, height: frame.height * sy)
            return result
        }
    }

    /// After a resize, text boxes that fit their text grow or shrink to it, and shrinking text rescales.
    func fitResizedText() {
        guard let slideIndex = controller.currentSlideIndex else { return }
        let ids = controller.selectedElementIDs
        controller.updateInteractive { presentation in
            for id in ids {
                guard let index = presentation.slides[slideIndex].elementIndex(id: id) else { continue }
                TextFitting.fit(&presentation.slides[slideIndex].elements[index], on: presentation.slides[slideIndex], in: presentation)
            }
        }
    }

    // MARK: Creating

    private func create(_ tool: CanvasTool, from start: SlidePoint, to end: SlidePoint) {
        let dragged = hypot(end.x - start.x, end.y - start.y) > screen(4)
        let frame = SlideRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        switch tool {
        case .select:
            return
        case .textBox:
            let box = dragged ? SlideRect(x: frame.x, y: frame.y, width: max(frame.width, 20), height: max(frame.height, 20))
                : SlideRect(x: start.x, y: start.y, width: 216, height: 30)
            var element = controller.makeTextBox(frame: box)
            if let slide = controller.currentSlide {
                TextFitting.fit(&element, on: slide, in: controller.presentation)
            }
            controller.insert([element], actionName: "Insert Text Box")
            finishTool()
            beginEditing(element.id, at: nil, isNew: true)
        case .shape(let preset):
            let box = dragged ? frame : SlideRect(x: start.x - 36, y: start.y - 36, width: 72, height: 72)
            controller.insert([controller.makeShape(preset, frame: box)], actionName: "Insert Shape")
            finishTool()
        case .line(let kind):
            let finish = dragged ? end : SlidePoint(x: start.x + 72, y: start.y)
            controller.insert([controller.makeLine(kind, from: start, to: finish)], actionName: "Insert Line")
            finishTool()
        }
    }

    private func finishTool() {
        tool = .select
        onToolFinished?()
    }
}
