import AppKit
import UniformTypeIdentifiers
import PuggleSlidesKit

/// A grab point on the selection.
enum Handle: Equatable {
    /// A resize handle: `u` and `v` are 0, 1 or 2 for the left/center/right and top/middle/bottom positions.
    case resize(u: Int, v: Int)
    case rotate
    case lineStart, lineEnd
    case adjust(String)
}

/// What a mouse drag on the canvas is doing.
enum DragState {
    case pending(start: SlidePoint, elementID: UUID?, editOnRelease: Bool)
    case moving(start: SlidePoint, original: [UUID: Placement])
    case resizing(u: Int, v: Int, original: [UUID: Placement], box: SlideRect)
    case rotating(center: SlidePoint, startAngle: Double, original: Placement, elementID: UUID)
    case adjusting(name: String, element: SlideElement, placement: Placement)
    case movingLineEnd(head: Bool, fixed: SlidePoint, elementID: UUID)
    case marquee(start: SlidePoint, additive: Bool, original: [UUID])
    case creating(tool: CanvasTool, start: SlidePoint)
    /// Selecting a block of table cells from the cell where the drag began.
    case tableCells(elementID: UUID, startRow: Int, startColumn: Int)
    /// Moving a table's column border (or row border) number `index`.
    case tableBorder(elementID: UUID, horizontal: Bool, index: Int, original: Table)
    /// Moving a crop edge or corner, as a resize handle's `u` and `v`.
    case cropping(u: Int, v: Int)
    /// Moving a guide.
    case guide(id: UUID)
}

/// A picture being cropped on the canvas, in the picture's own space (its frame from 0, 0 before cropping began).
struct CropSession {
    let elementID: UUID
    let original: Placement
    /// The whole image, uncropped, in that space.
    let full: CGRect
    /// The part that will show.
    var visible: CGRect
}

/// A line drawn while an object snaps to it: across the slide, from `from` to `to`.
struct SnapLine: Equatable {
    var from: CGPoint
    var to: CGPoint
    var color: NSColor = Theme.snapLine
}

/// The slide being edited: draws it with the selection on top and turns mouse and keyboard input into edits.
final class SlideEditingView: NSView {
    let controller: PresentationController
    /// Gray space around the slide, in slide points.
    let margin: CGFloat = 20
    var hoveredElementID: UUID? {
        didSet { if hoveredElementID != oldValue { needsDisplay = true } }
    }
    var marquee: CGRect?
    var creationPreview: (tool: CanvasTool, start: SlidePoint, end: SlidePoint)?
    var drag: DragState?
    var editor: SlideTextEditor?
    /// The picture being cropped, if any.
    var cropping: CropSession?
    /// Alignment lines to show while dragging.
    var snapLines: [SnapLine] = []
    /// VoiceOver's elements for the slide's objects, kept so each object stays the same element.
    var accessibilityObjects: [UUID: SlideObjectAccessibility] = [:]
    /// Edit ▸ Find and replace: the matches on this slide, and the one being looked at.
    var findMatches: [TextMatch] = [] { didSet { if findMatches != oldValue { needsDisplay = true } } }
    var currentFindMatch: TextMatch? { didSet { if currentFindMatch != oldValue { needsDisplay = true } } }
    /// The context menu for a point and the element under it.
    var menuProvider: ((SlideElement?) -> NSMenu?)?
    /// Called after an insert tool has been used once, so the toolbar goes back to Select.
    var onToolFinished: (() -> Void)?
    /// Called when text editing starts, ends, or its selection changes.
    var onEditingChange: (() -> Void)?
    /// Paint format: called with the element clicked; returns true when it took the click.
    var onPaintFormat: ((SlideElement) -> Bool)?
    /// A double-click on word art: edit its text.
    var onEditWordArt: ((UUID) -> Void)?
    /// A double-click on a chart: open the chart editor.
    var onEditChart: (() -> Void)?
    /// A double-click on a video or sound (or a click on a selected video's play button) plays it in place.
    var onPlayMedia: ((UUID) -> Void)?
    /// Movie and sound files dropped on the slide, to insert where they were dropped.
    var onDropMedia: (([URL], SlidePoint) -> Void)?
    var tool: CanvasTool = .select {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    private var trackingArea: NSTrackingArea?

    init(controller: PresentationController) {
        self.controller = controller
        super.init(frame: .zero)
        reloadSize()
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    // MARK: Dropping images

    private func droppedImages(_ info: NSDraggingInfo) -> [Data] {
        let pasteboard = info.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter { !Self.isMedia($0) }.compactMap { try? Data(contentsOf: $0) }
                .filter { MediaItem.contentType(sniffing: $0)?.hasPrefix("image/") == true }
            if !images.isEmpty { return images }
        }
        if let data = pasteboard.data(forType: .png) { return [data] }
        if let data = pasteboard.data(forType: .tiff), let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            return [png]
        }
        return []
    }

    /// Movie and sound files being dropped.
    private func droppedMedia(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(Self.isMedia)
    }

    static func isMedia(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) == true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller.currentSlide != nil && (!droppedMedia(sender).isEmpty || !droppedImages(sender).isEmpty) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = slidePoint(convert(sender.draggingLocation, from: nil))
        let media = droppedMedia(sender)
        if !media.isEmpty, let onDropMedia {
            onDropMedia(media, point)
            return true
        }
        var inserted = false
        for (index, data) in droppedImages(sender).enumerated() {
            inserted = controller.insertImage(data: data, at: SlidePoint(x: point.x + Double(index) * 18, y: point.y + Double(index) * 18)) || inserted
        }
        if inserted { window?.makeFirstResponder(self) }
        return inserted
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Screen points per slide point.
    var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    /// A length of `pixels` on screen, in slide points.
    func screen(_ pixels: CGFloat) -> CGFloat { pixels / max(magnification, 0.01) }

    var slideSize: SlideSize { controller.presentation.slideSize }
    var slideRect: CGRect { CGRect(x: margin, y: margin, width: slideSize.width, height: slideSize.height) }

    func reloadSize() {
        let size = NSSize(width: slideSize.width + margin * 2, height: slideSize.height + margin * 2)
        if frame.size != size { setFrameSize(size) }
    }

    func slidePoint(_ point: CGPoint) -> SlidePoint { SlidePoint(x: point.x - margin, y: point.y - margin) }
    func viewPoint(_ point: SlidePoint) -> CGPoint { CGPoint(x: point.x + margin, y: point.y + margin) }

    func zoomDidChange() {
        needsDisplay = true
        editor?.layout()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = slideRect
        guard let slide = controller.currentSlide else {
            drawEmptyPresentation(in: rect)
            return
        }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: screen(1)), blur: screen(3), color: NSColor.black.withAlphaComponent(0.18).cgColor)
        context.setFillColor(CGColor.white)
        context.fill(rect)
        context.restoreGState()
        // The theme builder's pages show the slide number field as it is, not a number.
        let number: Int? = controller.isThemeBuilderOpen ? nil : (controller.currentSlideIndex ?? 0) + 1
        let editedCell = editor.flatMap { editor in editor.cell.map { TableCellRef(elementID: editor.elementID, row: $0.row, column: $0.column) } }
        SlideRenderer.draw(slide, of: controller.presentation, in: rect,
                           options: SlideRenderer.Options(showsPrompts: true, hiddenTextElementID: editedCell == nil ? editor?.elementID : nil,
                                                          hiddenTableCell: editedCell, slideNumber: number, showsPlayButtons: true))
        context.saveGState()
        context.translateBy(x: margin, y: margin)
        drawPlaceholderOutlines(slide)
        drawFindHighlights(slide)
        drawGuides()
        drawHover(slide)
        if cropping != nil {
            drawCropping()
        } else {
            drawTableSelection()
            drawSelection(slide)
        }
        drawSnapLines()
        drawMarqueeAndPreview()
        context.restoreGState()
    }

    private func drawEmptyPresentation(in rect: CGRect) {
        NSColor.white.setFill()
        rect.fill()
        Theme.slideBorder.setStroke()
        NSBezierPath(rect: rect).stroke()
        let text = "Click to add slide" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: Theme.promptText]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    /// The four corners of an element's (rotated) frame in slide space.
    func corners(of placement: Placement) -> [CGPoint] {
        let frame = placement.frame
        let upright = Placement(frame: frame, rotation: placement.rotation)
        let w = abs(frame.width), h = abs(frame.height)
        return [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)].map { $0.applying(upright.transform) }
    }

    private func outlinePath(_ placement: Placement) -> NSBezierPath {
        let points = corners(of: placement)
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        return path
    }

    private func drawPlaceholderOutlines(_ slide: Slide) {
        for element in slide.elements where element.placeholder != nil && element.id != editor?.elementID {
            guard element.shape?.text?.isEmpty ?? true, !controller.selectedElementIDs.contains(element.id) else { continue }
            let style = controller.presentation.style(for: element, on: slide)
            guard !style.outline.isVisible, style.fill.isNone else { continue }
            let path = outlinePath(style.placement)
            path.lineWidth = screen(1)
            path.setLineDash([screen(4), screen(3)], count: 2, phase: 0)
            Theme.placeholderOutline.setStroke()
            path.stroke()
        }
    }

    private func drawHover(_ slide: Slide) {
        guard let id = hoveredElementID, !controller.selectedElementIDs.contains(id), drag == nil,
              let element = slide.element(id: id) else { return }
        let placement = controller.placement(of: element)
        let path = element.isLine ? linePath(element, placement: placement) : outlinePath(placement)
        path.lineWidth = screen(1)
        Theme.selection.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }

    /// A line element's own path in slide space, for hovering and selecting.
    private func linePath(_ element: SlideElement, placement: Placement) -> NSBezierPath {
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let parts = PresetGeometry.paths(for: element.shape?.geometry ?? .line, in: CGRect(origin: .zero, size: size))
        let path = CGMutablePath()
        for part in parts { path.addPath(part.path, transform: placement.transform) }
        return NSBezierPath(cgPath: path)
    }

    private func drawSelection(_ slide: Slide) {
        let selected = controller.selectedElements
        guard !selected.isEmpty else { return }
        Theme.selection.setStroke()
        for element in selected {
            let placement = controller.placement(of: element)
            let path = element.isLine ? linePath(element, placement: placement) : outlinePath(placement)
            path.lineWidth = screen(element.isLine ? 1.5 : 1)
            if element.isLine { Theme.selection.withAlphaComponent(0.5).setStroke() } else { Theme.selection.setStroke() }
            path.stroke()
        }
        for (handle, point) in handles() { drawHandle(handle, at: point) }
    }

    private func drawHandle(_ handle: Handle, at point: CGPoint) {
        let size = screen(8)
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        switch handle {
        case .rotate:
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: -screen(1), dy: -screen(1)))
            NSColor.white.setFill()
            path.fill()
            Theme.selection.setStroke()
            path.lineWidth = screen(1.5)
            path.stroke()
        case .adjust:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: point.x, y: rect.minY - screen(1)))
            path.line(to: CGPoint(x: rect.maxX + screen(1), y: point.y))
            path.line(to: CGPoint(x: point.x, y: rect.maxY + screen(1)))
            path.line(to: CGPoint(x: rect.minX - screen(1), y: point.y))
            path.close()
            Theme.adjustHandle.setFill()
            path.fill()
            NSColor(white: 0.25, alpha: 1).setStroke()
            path.lineWidth = screen(1)
            path.stroke()
        default:
            let path = NSBezierPath(rect: rect)
            NSColor.white.setFill()
            path.fill()
            Theme.selection.setStroke()
            path.lineWidth = screen(1)
            path.stroke()
        }
    }

    private func drawMarqueeAndPreview() {
        if let marquee {
            Theme.selection.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: marquee).fill()
            Theme.selection.setStroke()
            let path = NSBezierPath(rect: marquee)
            path.lineWidth = screen(1)
            path.stroke()
        }
        if let preview = creationPreview {
            Theme.selection.setStroke()
            let path: NSBezierPath
            switch preview.tool {
            case .line:
                path = NSBezierPath()
                path.move(to: preview.start.cgPoint)
                path.line(to: preview.end.cgPoint)
            default:
                path = NSBezierPath(rect: CGRect(x: min(preview.start.x, preview.end.x), y: min(preview.start.y, preview.end.y),
                                                 width: abs(preview.end.x - preview.start.x), height: abs(preview.end.y - preview.start.y)))
            }
            path.lineWidth = screen(1)
            path.stroke()
        }
    }

    // MARK: Handles

    /// The selection's handles, in slide space.
    func handles() -> [(Handle, CGPoint)] {
        let selected = controller.selectedElements
        guard !selected.isEmpty, drag.map({ if case .moving = $0 { return false } else { return true } }) ?? true else { return [] }
        if selected.count == 1, let element = selected.first {
            let placement = controller.placement(of: element)
            if element.isLine {
                let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
                let parts = PresetGeometry.paths(for: element.shape?.geometry ?? .line, in: CGRect(origin: .zero, size: size))
                guard let path = parts.last?.path else { return [] }
                let ends = SlideRenderer.EndPoints(path)
                var result: [(Handle, CGPoint)] = []
                if let head = ends.head { result.append((.lineStart, head.point.applying(placement.transform))) }
                if let tail = ends.tail { result.append((.lineEnd, tail.point.applying(placement.transform))) }
                return result
            }
            let frame = placement.frame
            let w = abs(frame.width), h = abs(frame.height)
            let upright = Placement(frame: frame, rotation: placement.rotation).transform
            var result: [(Handle, CGPoint)] = []
            for v in 0...2 {
                for u in 0...2 where !(u == 1 && v == 1) {
                    result.append((.resize(u: u, v: v), CGPoint(x: w * CGFloat(u) / 2, y: h * CGFloat(v) / 2).applying(upright)))
                }
            }
            // Tables don't turn.
            if element.table == nil { result.append((.rotate, CGPoint(x: w / 2, y: -screen(22)).applying(upright))) }
            if case .shape(let shape) = element.content {
                for handle in PresetGeometry.handles(for: shape.geometry, in: CGRect(x: 0, y: 0, width: w, height: h)) {
                    result.append((.adjust(handle.name), handle.position.applying(placement.transform)))
                }
            }
            return result
        }
        let box = selectionBox()
        var result: [(Handle, CGPoint)] = []
        for v in 0...2 {
            for u in 0...2 where !(u == 1 && v == 1) {
                result.append((.resize(u: u, v: v), CGPoint(x: box.minX + box.width * Double(u) / 2, y: box.minY + box.height * Double(v) / 2)))
            }
        }
        return result
    }

    /// The upright box around everything selected.
    func selectionBox() -> SlideRect {
        let boxes = controller.selectedElements.map { controller.placement(of: $0).boundingBox }
        guard let first = boxes.first else { return .zero }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    func handle(at point: SlidePoint) -> Handle? {
        let radius = screen(6)
        // Adjust handles first: they often sit on top of resize handles.
        let all = handles().sorted { a, _ in if case .adjust = a.0 { return true } else { return false } }
        for (handle, position) in all where hypot(position.x - point.x, position.y - point.y) <= radius {
            return handle
        }
        return nil
    }

    // MARK: Hit testing

    /// The topmost element at a slide point.
    func element(at point: SlidePoint) -> SlideElement? {
        guard let slide = controller.currentSlide else { return nil }
        for element in slide.elements.reversed() where hits(element, point, slide: slide) {
            return element
        }
        return nil
    }

    private func hits(_ element: SlideElement, _ point: SlidePoint, slide: Slide) -> Bool {
        let tolerance = screen(4)
        let style = controller.presentation.style(for: element, on: slide)
        let placement = style.placement
        let local = placement.shapePoint(fromSlide: point).cgPoint
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let bounds = CGRect(origin: .zero, size: size)
        switch element.content {
        case .group(let children):
            return children.contains { child in
                let childStyle = ElementStyle(element: child, parents: [], theme: style.theme, defaultTextStyle: style.defaultTextStyle)
                return childStyle.placement.boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
        case .picture, .table, .chart, .media:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .shape(let shape) where shape.isWordArt:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .shape(let shape):
            let parts = PresetGeometry.paths(for: shape.geometry, in: bounds)
            if element.isLine {
                let width = max(CGFloat(style.outline.width), tolerance * 2)
                return parts.contains { $0.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4).contains(local) }
            }
            guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local) else { return false }
            if shape.text != nil || shape.isTextBox || element.placeholder != nil { return true }
            if !style.fill.isNone { return parts.contains { $0.path.contains(local, using: .evenOdd) } || parts.isEmpty }
            let width = max(CGFloat(style.outline.width), tolerance * 2)
            return parts.contains { $0.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4).contains(local) }
        }
    }

    /// Elements wholly inside a slide rectangle, for marquee selection.
    func elements(inside rect: SlideRect) -> [UUID] {
        guard let slide = controller.currentSlide else { return [] }
        return slide.elements.filter { element in
            let box = controller.placement(of: element).boundingBox
            return box.minX >= rect.minX && box.maxX <= rect.maxX && box.minY >= rect.minY && box.maxY <= rect.maxY
        }.map(\.id)
    }
}
