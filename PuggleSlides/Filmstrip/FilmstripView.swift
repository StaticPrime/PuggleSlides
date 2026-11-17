import AppKit
import PuggleSlidesKit

/// The column of slide thumbnails on the left, or (in grid view) slides in rows filling the window.
final class FilmstripView: NSView {
    let controller: PresentationController
    static let width: CGFloat = 206
    /// View ▸ Grid view: rows of thumbnails with their numbers underneath.
    let isGrid: Bool
    private var numberColumn: CGFloat { isGrid ? 24 : 30 }
    /// Grid view's zoom slider sets this.
    var thumbnailWidth: CGFloat = 158 {
        didSet { if thumbnailWidth != oldValue { reload() } }
    }
    private var gap: CGFloat { isGrid ? 34 : 14 }
    private let topPadding: CGFloat = 14
    /// Grid view: a double-click opens the slide.
    var onOpenSlide: ((UUID) -> Void)?
    /// The menu for a right-click on a slide (nil index: below the last slide).
    var menuProvider: ((Int?) -> NSMenu?)?
    /// Called when the filmstrip takes keyboard focus or a slide is picked.
    var onActivate: (() -> Void)?
    private var thumbnails: [UUID: (slide: Slide, revision: Int, number: Int, image: NSImage)] = [:]
    /// VoiceOver's elements for the slides, kept so each slide stays the same element.
    var accessibilityThumbnails: [UUID: SlideThumbnailAccessibility] = [:]
    private var dragStart: CGPoint?
    private var dropIndex: Int? {
        didSet { if dropIndex != oldValue { needsDisplay = true } }
    }

    init(controller: PresentationController, isGrid: Bool = false) {
        self.controller = controller
        self.isGrid = isGrid
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        if isGrid { thumbnailWidth = 220 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onActivate?()
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    private var thumbnailHeight: CGFloat {
        let size = controller.presentation.slideSize
        return (thumbnailWidth * size.height / max(size.width, 1)).rounded()
    }

    private var rowHeight: CGFloat { thumbnailHeight + gap }
    private var columnWidth: CGFloat { thumbnailWidth + (isGrid ? 28 : 0) }

    /// Thumbnails per row: one in the filmstrip, as many as fit in grid view.
    var columns: Int {
        guard isGrid else { return 1 }
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        return max(1, Int((width - numberColumn * 2 + 28) / columnWidth))
    }

    /// Resizes to fit every slide and redraws.
    func reload() {
        let count = controller.presentation.slides.count
        let rows = (max(count, 1) + columns - 1) / columns
        let height = topPadding * 2 + CGFloat(rows) * rowHeight
        let visible = enclosingScrollView?.contentSize ?? NSSize(width: Self.width, height: height)
        setFrameSize(NSSize(width: isGrid ? visible.width : Self.width, height: max(height, visible.height)))
        let ids = Set(controller.presentation.slides.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        needsDisplay = true
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if isGrid { needsDisplay = true }
    }

    func thumbnailRect(at index: Int) -> CGRect {
        let column = index % columns, row = index / columns
        let used = CGFloat(columns) * columnWidth - (isGrid ? 28 : 0)
        let left = isGrid ? max(numberColumn, (bounds.width - used) / 2) : numberColumn
        return CGRect(x: left + CGFloat(column) * columnWidth, y: topPadding + CGFloat(row) * rowHeight,
                      width: thumbnailWidth, height: thumbnailHeight)
    }

    private func index(at point: CGPoint) -> Int? {
        let count = controller.presentation.slides.count
        guard count > 0 else { return nil }
        let row = Int((point.y - topPadding + gap / 2) / rowHeight)
        guard row >= 0 else { return nil }
        var column = 0
        if isGrid {
            let first = thumbnailRect(at: 0).minX
            column = Int((point.x - first + 14) / columnWidth)
            guard column >= 0, column < columns else { return nil }
        }
        let index = row * columns + column
        return index < count ? index : nil
    }

    /// Where a dragged slide would land: the gap nearest the point.
    private func dropPosition(at point: CGPoint) -> Int {
        let count = controller.presentation.slides.count
        guard isGrid else {
            let position = Int(((point.y - topPadding) / rowHeight).rounded())
            return max(0, min(count, position))
        }
        let row = max(0, Int((point.y - topPadding) / rowHeight))
        let first = thumbnailRect(at: 0).minX
        let column = max(0, min(columns, Int(((point.x - first) / columnWidth).rounded())))
        return max(0, min(count, row * columns + column))
    }

    func scrollToCurrent() {
        guard let index = controller.currentSlideIndex else { return }
        scrollToVisible(thumbnailRect(at: index).insetBy(dx: 0, dy: -gap))
    }

    private func image(for slide: Slide, number: Int) -> NSImage {
        let revision = controller.themeRevision
        if let cached = thumbnails[slide.id], cached.revision == revision, cached.number == number, cached.slide == slide {
            return cached.image
        }
        let image = SlideRenderer.image(of: slide, in: controller.presentation, size: CGSize(width: thumbnailWidth, height: thumbnailHeight),
                                        slideNumber: controller.isThemeBuilderOpen ? nil : number, scale: window?.backingScaleFactor ?? 2,
                                        showsPrompts: controller.isThemeBuilderOpen)
        thumbnails[slide.id] = (slide, revision, number, image)
        return image
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvas.setFill()
        dirtyRect.fill()
        let slides = controller.presentation.slides
        let focused = window?.firstResponder === self
        for (index, slide) in slides.enumerated() {
            let rect = thumbnailRect(at: index)
            guard rect.insetBy(dx: -6, dy: -6).intersects(dirtyRect) else { continue }
            let selected = controller.selectedSlideIDs.contains(slide.id)
            let current = slide.id == controller.currentSlideID
            let number = (controller.isThemeBuilderOpen ? "" : "\(index + 1)") as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: current ? .semibold : .regular),
                .foregroundColor: Theme.filmstripNumber,
            ]
            let size = number.size(withAttributes: attributes)
            if isGrid {
                number.draw(at: CGPoint(x: rect.minX, y: rect.maxY + 6), withAttributes: attributes)
                if controller.hasMotion(slide) { drawMotionMark(at: CGPoint(x: rect.minX + size.width + 6, y: rect.maxY + 10)) }
            } else {
                number.draw(at: CGPoint(x: numberColumn - 9 - size.width, y: rect.minY + 1), withAttributes: attributes)
                if controller.hasMotion(slide) { drawMotionMark(at: CGPoint(x: numberColumn - 16, y: rect.minY + 22)) }
            }
            // Thumbnails are drawn live while a slide is being dragged on the canvas, and cached otherwise.
            if current, controller.isInteractive {
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: rect).addClip()
                SlideRenderer.draw(slide, of: controller.presentation, in: rect, options: SlideRenderer.Options(slideNumber: index + 1))
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                image(for: slide, number: index + 1).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if selected {
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
                ring.lineWidth = 3
                (focused || current ? Theme.filmstripSelection : Theme.filmstripSelection.withAlphaComponent(0.55)).setStroke()
                ring.stroke()
            } else {
                Theme.slideBorder.setStroke()
                let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 1
                border.stroke()
            }
            if slide.isSkipped { drawSkippedBadge(in: rect) }
        }
        if let dropIndex {
            Theme.filmstripSelection.setFill()
            if isGrid {
                let after = dropIndex > 0 && (dropIndex == slides.count || dropIndex % columns == 0)
                let anchor = thumbnailRect(at: after ? dropIndex - 1 : dropIndex)
                let x = after ? anchor.maxX + 14 : anchor.minX - 14
                NSRect(x: x - 1.5, y: anchor.minY - 6, width: 3, height: anchor.height + 12).fill()
            } else {
                let y = dropIndex < slides.count ? thumbnailRect(at: dropIndex).minY - gap / 2 : thumbnailRect(at: max(0, slides.count - 1)).maxY + gap / 2
                NSRect(x: numberColumn - 6, y: y - 1.5, width: thumbnailWidth + 12, height: 3).fill()
            }
        }
    }

    /// Slides with transitions or animations are marked with three overlapping circles.
    private func drawMotionMark(at origin: CGPoint) {
        Theme.filmstripNumber.setStroke()
        for index in 0..<3 {
            let circle = NSBezierPath(ovalIn: CGRect(x: origin.x + CGFloat(index) * 3, y: origin.y, width: 6, height: 6))
            circle.lineWidth = 1
            circle.stroke()
        }
    }

    /// A skipped slide is marked with a crossed-out eye and dimmed.
    private func drawSkippedBadge(in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.45).setFill()
        rect.fill(using: .sourceOver)
        let badge = CGRect(x: rect.maxX - 26, y: rect.maxY - 22, width: 22, height: 18)
        NSColor(white: 0.2, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white]).applying(.init(pointSize: 11, weight: .medium))
        if let symbol = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Skipped")?.withSymbolConfiguration(configuration) {
            let size = symbol.size
            symbol.draw(in: CGRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        guard let index = index(at: point) else { return }
        let id = controller.presentation.slides[index].id
        if event.clickCount >= 2, isGrid {
            onOpenSlide?(id)
            return
        }
        let modifiers = event.modifierFlags
        if modifiers.contains(.shift) {
            controller.selectSlide(id, extend: true)
        } else if modifiers.contains(.command) {
            controller.selectSlide(id, toggle: true)
        } else if !controller.selectedSlideIDs.contains(id) {
            controller.selectSlide(id)
        } else if controller.currentSlideID != id {
            controller.selectSlides(controller.selectedSlideIDs, current: id)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let start = dragStart, hypot(point.x - start.x, point.y - start.y) > 5 else { return }
        autoscroll(with: event)
        dropIndex = dropPosition(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dropIndex = nil
        }
        if let dropIndex {
            controller.moveSlides(to: dropIndex)
            return
        }
        // A plain click on one of several selected slides keeps just that slide.
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.isDisjoint(with: [.shift, .command]), let index = index(at: point), controller.selectedSlideIDs.count > 1 {
            controller.selectSlide(controller.presentation.slides[index].id)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let index = index(at: point)
        if let index {
            let id = controller.presentation.slides[index].id
            if !controller.selectedSlideIDs.contains(id) { controller.selectSlide(id) }
        }
        return menuProvider?(index)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return super.keyDown(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let slides = controller.presentation.slides
        guard let current = controller.currentSlideIndex else { return super.keyDown(with: event) }
        switch Int(key.value) {
        case NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey,
             NSLeftArrowFunctionKey, NSRightArrowFunctionKey:
            var target = current
            switch Int(key.value) {
            case NSUpArrowFunctionKey: target = current - columns
            case NSDownArrowFunctionKey: target = current + columns
            case NSLeftArrowFunctionKey: target = current - 1
            case NSRightArrowFunctionKey: target = current + 1
            case NSHomeFunctionKey, NSPageUpFunctionKey: target = 0
            default: target = slides.count - 1
            }
            target = max(0, min(slides.count - 1, target))
            controller.selectSlide(slides[target].id, extend: modifiers.contains(.shift))
            scrollToCurrent()
        case 127, NSDeleteFunctionKey, 8:
            controller.deleteSlides()
        case 13, 3:
            if isGrid, let id = controller.currentSlideID { onOpenSlide?(id) } else { onActivate?() }
        default:
            super.keyDown(with: event)
        }
    }

    /// ⌘↑ and ⌘↓ move slides here (on the canvas they change the order of shapes).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), modifiers.isDisjoint(with: [.option, .control]) else { return false }
        switch Int(key.value) {
        case NSUpArrowFunctionKey:
            if modifiers.contains(.shift) { controller.moveSlidesToBeginning() } else { controller.moveSlidesUp() }
        case NSDownArrowFunctionKey:
            if modifiers.contains(.shift) { controller.moveSlidesToEnd() } else { controller.moveSlidesDown() }
        default:
            return false
        }
        scrollToCurrent()
        return true
    }

    override func selectAll(_ sender: Any?) {
        guard let current = controller.currentSlideID else { return }
        controller.selectSlides(Set(controller.presentation.slides.map(\.id)), current: current)
    }
}
