import AppKit
import PuggleSlidesKit

/// Tables, cropping, guides and snapping on the canvas.
extension SlideEditingView {
    // MARK: Tables

    /// A table's layout and its placement as drawn (rows grown to fit their text).
    func tableGeometry(_ element: SlideElement) -> (layout: TableLayout, placement: Placement)? {
        guard let table = element.table, let slide = controller.currentSlide else { return nil }
        let style = controller.presentation.style(for: element, on: slide)
        let layout = TableLayout(table, style: style)
        let frame = style.placement.frame
        return (layout, Placement(frame: SlideRect(x: frame.x, y: frame.y, width: layout.size.width, height: layout.size.height),
                                  rotation: style.placement.rotation))
    }

    /// A click on a table goes into the clicked cell's text, onto an inner border to resize it, or extends the cell
    /// selection with Shift. Near the table's outside edge it moves the table, like any object: returns false then.
    func tableMouseDown(_ element: SlideElement, at point: SlidePoint, event: NSEvent) -> Bool {
        guard let table = element.table, let (layout, placement) = tableGeometry(element) else { return false }
        let local = placement.shapePoint(fromSlide: point).cgPoint
        let tolerance = screen(4)
        let size = layout.size
        if local.x < tolerance || local.y < tolerance || local.x > size.width - tolerance || local.y > size.height - tolerance { return false }
        let isSelected = controller.selectedElementIDs == [element.id]
        if isSelected, let border = layout.border(near: local, tolerance: tolerance),
           border.horizontal ? border.index < table.rowCount : border.index < table.columnCount {
            if editor != nil { endEditing() }
            controller.beginInteractive()
            drag = .tableBorder(elementID: element.id, horizontal: border.horizontal, index: border.index, original: table)
            return true
        }
        guard let cell = layout.cell(at: local) else { return false }
        if event.modifierFlags.contains(.shift), isSelected, let current = controller.tableSelection {
            if editor != nil { endEditing() }
            controller.selectElements([element.id])
            controller.tableSelection = table.expanded(TableCellRange(firstRow: current.firstRow, firstColumn: current.firstColumn,
                                                                      lastRow: cell.row, lastColumn: cell.column))
            needsDisplay = true
            onEditingChange?()
            return true
        }
        beginEditingCell(element.id, row: cell.row, column: cell.column, at: point)
        drag = .tableCells(elementID: element.id, startRow: cell.row, startColumn: cell.column)
        return true
    }

    func tableDragged(_ drag: DragState, to point: SlidePoint) {
        switch drag {
        case .tableCells(let id, let startRow, let startColumn):
            guard let element = controller.currentSlide?.element(id: id), let table = element.table,
                  let (layout, placement) = tableGeometry(element) else { return }
            let position = layout.gridPosition(at: placement.shapePoint(fromSlide: point).cgPoint)
            let range = table.expanded(TableCellRange(firstRow: startRow, firstColumn: startColumn, lastRow: position.row, lastColumn: position.column))
            // Still inside the first cell: the click stays a click into its text.
            guard !range.isSingleCell || editor == nil else { return }
            if editor != nil { endEditing() }
            controller.selectElements([id])
            if controller.tableSelection != range {
                controller.tableSelection = range
                onEditingChange?()
            }
            needsDisplay = true
        case .tableBorder(let id, let horizontal, let index, let original):
            guard let element = controller.currentSlide?.element(id: id), let slide = controller.currentSlide else { return }
            var probe = element
            probe.table = original
            guard let (layout, placement) = tableGeometry(probe) else { return }
            let local = placement.shapePoint(fromSlide: point).cgPoint
            var table = original
            let minimum = screen(8)
            if horizontal {
                // A row's border sets its height (rows can't be shorter than their text).
                let top = layout.rowY[index - 1]
                table.rowHeights[index - 1] = Double(max(minimum, local.y - top))
            } else {
                // A border between columns trades width between them, keeping the table's width.
                let left = layout.columnX[index - 1], right = layout.columnX[index + 1]
                let x = min(max(local.x, left + minimum), right - minimum)
                table.columnWidths[index - 1] = Double(x - left)
                table.columnWidths[index] = Double(right - x)
            }
            controller.updateInteractive { presentation in
                guard let slideIndex = self.controller.currentSlideIndex, let elementIndex = presentation.slides[slideIndex].elementIndex(id: id) else { return }
                var edited = presentation.slides[slideIndex].elements[elementIndex]
                edited.table = table
                self.controller.fitTableFrame(&edited, style: presentation.style(for: edited, on: slide))
                presentation.slides[slideIndex].elements[elementIndex] = edited
            }
        default:
            break
        }
    }

    /// The selected cells, tinted, when more than the cell being typed in is selected.
    func drawTableSelection() {
        guard let element = controller.selectedTableElement, let table = element.table, let range = controller.tableSelection,
              editor == nil || !range.isSingleCell, let (layout, placement) = tableGeometry(element) else { return }
        guard range.lastRow < table.rowCount, range.lastColumn < table.columnCount else { return }
        var transform = placement.transform
        let path = NSBezierPath(cgPath: CGPath(rect: layout.rect(of: range), transform: &transform))
        Theme.cellSelection.setFill()
        path.fill()
        Theme.selection.setStroke()
        path.lineWidth = screen(1.5)
        path.stroke()
    }

    // MARK: Cropping

    /// Crop image (or a double-click on a picture): black crop marks on the picture's edges and corners.
    func beginCropping(_ id: UUID) {
        guard let element = controller.currentSlide?.element(id: id), let picture = element.picture else { return }
        if editor != nil { endEditing() }
        endCropping(commit: true)
        controller.selectElements([id])
        let placement = controller.placement(of: element)
        let width = abs(placement.frame.width), height = abs(placement.frame.height)
        let crop = picture.crop
        let fullWidth = width / max(0.01, 1 - crop.left - crop.right), fullHeight = height / max(0.01, 1 - crop.top - crop.bottom)
        controller.beginInteractive()
        cropping = CropSession(elementID: id, original: placement,
                               full: CGRect(x: -crop.left * fullWidth, y: -crop.top * fullHeight, width: fullWidth, height: fullHeight),
                               visible: CGRect(x: 0, y: 0, width: width, height: height))
        window?.makeFirstResponder(self)
        needsDisplay = true
        onEditingChange?()
    }

    /// Return or a click elsewhere keeps the crop; Esc puts it back.
    func endCropping(commit: Bool) {
        guard cropping != nil else { return }
        cropping = nil
        if commit { controller.endInteractive(actionName: "Crop Image") } else { controller.cancelInteractive() }
        needsDisplay = true
        onEditingChange?()
    }

    private func applyCrop(_ session: CropSession) {
        let full = session.full, visible = session.visible
        let crop = ImageCrop(left: (visible.minX - full.minX) / full.width, top: (visible.minY - full.minY) / full.height,
                             right: (full.maxX - visible.maxX) / full.width, bottom: (full.maxY - visible.maxY) / full.height)
        let center = CGPoint(x: visible.midX, y: visible.midY).applying(session.original.transform)
        var placement = session.original
        placement.frame = SlideRect(x: center.x - visible.width / 2, y: center.y - visible.height / 2, width: visible.width, height: visible.height)
        let id = session.elementID
        controller.updateInteractive { presentation in
            guard let slideIndex = self.controller.currentSlideIndex, let index = presentation.slides[slideIndex].elementIndex(id: id),
                  var picture = presentation.slides[slideIndex].elements[index].picture else { return }
            picture.crop = crop
            presentation.slides[slideIndex].elements[index].picture = picture
            presentation.slides[slideIndex].elements[index].placement = placement
        }
    }

    /// Where the crop marks are, in slide space.
    func cropHandles() -> [(u: Int, v: Int, point: CGPoint)] {
        guard let session = cropping else { return [] }
        let visible = session.visible
        var result: [(Int, Int, CGPoint)] = []
        for v in 0...2 {
            for u in 0...2 where !(u == 1 && v == 1) {
                let local = CGPoint(x: visible.minX + visible.width * CGFloat(u) / 2, y: visible.minY + visible.height * CGFloat(v) / 2)
                result.append((u, v, local.applying(session.original.transform)))
            }
        }
        return result
    }

    /// A click while cropping: on a crop mark it moves that edge; inside the picture it's ignored; elsewhere it ends
    /// cropping (and returns false so the click does what it would anyway).
    func cropMouseDown(at point: SlidePoint) -> Bool {
        guard let session = cropping else { return false }
        let tolerance = screen(7)
        if let handle = cropHandles().first(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= tolerance }) {
            drag = .cropping(u: handle.u, v: handle.v)
            return true
        }
        let local = session.original.shapePoint(fromSlide: point).cgPoint
        if session.visible.contains(local) { return true }
        endCropping(commit: true)
        return false
    }

    func cropDragged(u: Int, v: Int, to point: SlidePoint) {
        guard var session = cropping else { return }
        let local = session.original.shapePoint(fromSlide: point).cgPoint
        let full = session.full, minimum = screen(8)
        var visible = session.visible
        if u == 0 {
            let left = min(max(local.x, full.minX), visible.maxX - minimum)
            visible = CGRect(x: left, y: visible.minY, width: visible.maxX - left, height: visible.height)
        }
        if u == 2 { visible.size.width = min(max(local.x, visible.minX + minimum), full.maxX) - visible.minX }
        if v == 0 {
            let top = min(max(local.y, full.minY), visible.maxY - minimum)
            visible = CGRect(x: visible.minX, y: top, width: visible.width, height: visible.maxY - top)
        }
        if v == 2 { visible.size.height = min(max(local.y, visible.minY + minimum), full.maxY) - visible.minY }
        session.visible = visible
        cropping = session
        applyCrop(session)
        needsDisplay = true
    }

    /// The whole picture faintly behind the crop window, the window's outline and black crop marks.
    func drawCropping() {
        guard let session = cropping, let slide = controller.currentSlide, let element = slide.element(id: session.elementID),
              let picture = element.picture, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.concatenate(session.original.transform)
        if let image = ImageCache.shared.image(picture.mediaID, in: controller.presentation) {
            let outside = CGMutablePath()
            outside.addRect(session.full)
            outside.addRect(session.visible)
            context.saveGState()
            context.addPath(outside)
            context.clip(using: .evenOdd)
            image.draw(in: session.full, from: .zero, operation: .sourceOver, fraction: 0.35, respectFlipped: true, hints: nil)
            context.restoreGState()
        }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(screen(1))
        context.stroke(session.visible)
        // L-shaped corner marks and short edge bars.
        let length = min(screen(14), session.visible.width / 3, session.visible.height / 3), thickness = screen(4)
        context.setFillColor(NSColor.black.cgColor)
        let r = session.visible
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            context.fill(CGRect(x: dx > 0 ? x : x - length, y: dy > 0 ? y : y - thickness, width: length, height: thickness))
            context.fill(CGRect(x: dx > 0 ? x : x - thickness, y: dy > 0 ? y : y - length, width: thickness, height: length))
        }
        context.fill(CGRect(x: r.midX - length / 2, y: r.minY, width: length, height: thickness))
        context.fill(CGRect(x: r.midX - length / 2, y: r.maxY - thickness, width: length, height: thickness))
        context.fill(CGRect(x: r.minX, y: r.midY - length / 2, width: thickness, height: length))
        context.fill(CGRect(x: r.maxX - thickness, y: r.midY - length / 2, width: thickness, height: length))
        context.restoreGState()
    }

    // MARK: Guides

    func drawGuides() {
        guard ViewPreferences.showsGuides, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = controller.presentation.slideSize
        for guide in controller.presentation.guides {
            let color = guide.color.map { NSColor(srgbRed: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1) }
                ?? Theme.customGuide
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(screen(1))
            if guide.orientation == .vertical {
                context.strokeLineSegments(between: [CGPoint(x: guide.position, y: 0), CGPoint(x: guide.position, y: size.height)])
            } else {
                context.strokeLineSegments(between: [CGPoint(x: 0, y: guide.position), CGPoint(x: size.width, y: guide.position)])
            }
        }
    }

    /// The guide under a point, when guides show.
    func guide(at point: SlidePoint) -> Guide? {
        guard ViewPreferences.showsGuides else { return nil }
        let tolerance = screen(3)
        let size = controller.presentation.slideSize
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        return controller.presentation.guides.last { guide in
            abs((guide.orientation == .vertical ? point.x : point.y) - guide.position) <= tolerance
        }
    }

    func guideDragged(_ id: UUID, to point: SlidePoint) {
        controller.updateInteractive { presentation in
            guard let index = presentation.guides.firstIndex(where: { $0.id == id }) else { return }
            let vertical = presentation.guides[index].orientation == .vertical
            presentation.guides[index].position = vertical ? point.x : point.y
        }
        needsDisplay = true
    }

    /// Dropping a guide off the slide deletes it.
    func guideDropped(_ id: UUID) {
        let size = controller.presentation.slideSize
        if let guide = controller.presentation.guides.first(where: { $0.id == id }),
           guide.position < 0 || guide.position > (guide.orientation == .vertical ? size.width : size.height) {
            controller.updateInteractive { presentation in presentation.guides.removeAll { $0.id == id } }
            controller.endInteractive(actionName: "Delete Guide")
        } else {
            controller.endInteractive(actionName: "Move Guide")
        }
    }

    @objc func deleteGuideFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        controller.deleteGuide(id)
        needsDisplay = true
    }

    // MARK: Snapping

    /// What objects snap to: the slide's edges and middle, guides that show, and other objects' edges and middles.
    private func snapTargets(excluding ids: Set<UUID>) -> (x: [Double], y: [Double]) {
        let size = controller.presentation.slideSize
        var targetsX = [0, size.width / 2, size.width], targetsY = [0, size.height / 2, size.height]
        for guide in controller.presentation.guides where ViewPreferences.showsGuides {
            if guide.orientation == .vertical { targetsX.append(guide.position) } else { targetsY.append(guide.position) }
        }
        for element in controller.currentSlide?.elements ?? [] where !ids.contains(element.id) {
            let box = controller.placement(of: element).boundingBox.cgRect
            targetsX += [box.minX, box.midX, box.maxX]
            targetsY += [box.minY, box.midY, box.maxY]
        }
        return (targetsX, targetsY)
    }

    /// The closest target to any of the edges, within snapping distance.
    private func best(_ edges: [Double], _ targets: [Double]) -> (delta: Double, line: Double)? {
        let threshold = Double(screen(6))
        var result: (Double, Double)?
        for edge in edges {
            for target in targets where abs(target - edge) <= threshold && abs(target - edge) < abs(result?.0 ?? .infinity) {
                result = (target - edge, target)
            }
        }
        return result
    }

    /// While resizing one upright object, the edges being dragged snap to the same targets as a move.
    func snappedResize(_ placement: Placement, u: Int, v: Int, id: UUID) -> Placement {
        snapLines = []
        guard ViewPreferences.snapsToGuides, placement.rotation == 0 else { return placement }
        let targets = snapTargets(excluding: [id])
        let size = controller.presentation.slideSize
        var frame = placement.frame.standardized
        if u != 1, let snap = best([u == 0 ? frame.minX : frame.maxX], targets.x) {
            if u == 0 { frame = SlideRect(x: snap.line, y: frame.y, width: frame.maxX - snap.line, height: frame.height) }
            else { frame.width = snap.line - frame.minX }
            snapLines.append(SnapLine(from: CGPoint(x: snap.line, y: 0), to: CGPoint(x: snap.line, y: size.height)))
        }
        if v != 1, let snap = best([v == 0 ? frame.minY : frame.maxY], targets.y) {
            if v == 0 { frame = SlideRect(x: frame.x, y: snap.line, width: frame.width, height: frame.maxY - snap.line) }
            else { frame.height = snap.line - frame.minY }
            snapLines.append(SnapLine(from: CGPoint(x: 0, y: snap.line), to: CGPoint(x: size.width, y: snap.line)))
        }
        guard frame.width > 1, frame.height > 1 else { return placement }
        var snapped = placement
        snapped.frame = frame
        return snapped
    }

    /// Moves a selection by an offset, snapped to the slide's edges and middle, other objects, guides and (when it's
    /// on) the grid, and remembers the lines it snapped to so they can be drawn.
    func snappedOffset(dx: Double, dy: Double, original: [UUID: Placement]) -> (dx: Double, dy: Double) {
        snapLines = []
        let snapsToGuides = ViewPreferences.snapsToGuides, snapsToGrid = ViewPreferences.snapsToGrid
        guard !original.isEmpty, snapsToGuides || snapsToGrid else { return (dx, dy) }
        let boxes = original.values.map(\.boundingBox)
        guard let first = boxes.first else { return (dx, dy) }
        let union = boxes.dropFirst().reduce(first.cgRect) { $0.union($1.cgRect) }
        let moved = union.offsetBy(dx: dx, dy: dy)
        let size = controller.presentation.slideSize
        var resultX = dx, resultY = dy
        var lineX: Double?, lineY: Double?
        if snapsToGuides {
            let (targetsX, targetsY) = snapTargets(excluding: Set(original.keys))
            if let snap = best([moved.minX, moved.midX, moved.maxX], targetsX) {
                resultX += snap.delta
                lineX = snap.line
            }
            if let snap = best([moved.minY, moved.midY, moved.maxY], targetsY) {
                resultY += snap.delta
                lineY = snap.line
            }
        }
        // The grid: an eighth of an inch.
        let grid = 9.0
        if snapsToGrid {
            if lineX == nil { resultX += (moved.minX / grid).rounded() * grid - moved.minX }
            if lineY == nil { resultY += (moved.minY / grid).rounded() * grid - moved.minY }
        }
        if let lineX { snapLines.append(SnapLine(from: CGPoint(x: lineX, y: 0), to: CGPoint(x: lineX, y: size.height))) }
        if let lineY { snapLines.append(SnapLine(from: CGPoint(x: 0, y: lineY), to: CGPoint(x: size.width, y: lineY))) }
        return (resultX, resultY)
    }

    func drawSnapLines() {
        guard !snapLines.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        for line in snapLines {
            context.setStrokeColor(line.color.cgColor)
            context.setLineWidth(screen(1))
            context.strokeLineSegments(between: [line.from, line.to])
        }
    }
}
