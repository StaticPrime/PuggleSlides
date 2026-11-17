import AppKit

/// Keeps the slide centered when it's smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if frame.width < rect.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if frame.height < rect.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}

/// The scrolling, zooming area around the slide being edited.
final class CanvasScrollView: NSScrollView {
    let editingView: SlideEditingView
    /// Called when a pinch changes the zoom.
    var onZoomGesture: (() -> Void)?
    private(set) var isFit = true

    init(editingView: SlideEditingView) {
        self.editingView = editingView
        super.init(frame: .zero)
        contentView = CenteringClipView()
        drawsBackground = true
        backgroundColor = Theme.canvas
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        minMagnification = Theme.minimumZoom * Theme.baseMagnification
        maxMagnification = Theme.maximumZoom * Theme.baseMagnification
        documentView = editingView
        NotificationCenter.default.addObserver(self, selector: #selector(didEndMagnify(_:)), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The zoom, where 1 is 100% (96 pixels per inch).
    var zoom: CGFloat { magnification / Theme.baseMagnification }

    /// The zoom that fits the whole slide, with its margin, in the visible area.
    var fitZoom: CGFloat {
        let size = editingView.frame.size
        let visible = contentView.frame.size
        guard size.width > 0, size.height > 0, visible.width > 0, visible.height > 0 else { return 1 }
        let magnification = min(visible.width / size.width, visible.height / size.height)
        return max(Theme.minimumZoom, min(Theme.maximumZoom, magnification / Theme.baseMagnification))
    }

    func setZoom(_ zoom: CGFloat?) {
        isFit = zoom == nil
        let level = zoom ?? fitZoom
        let magnification = min(max(level, Theme.minimumZoom), Theme.maximumZoom) * Theme.baseMagnification
        let center = NSPoint(x: documentVisibleRect.midX, y: documentVisibleRect.midY)
        setMagnification(magnification, centeredAt: center)
        editingView.zoomDidChange()
    }

    /// Re-fits after the window or panels change size.
    func refit() {
        if isFit { setZoom(nil) }
    }

    override func layout() {
        super.layout()
        refit()
    }

    @objc private func didEndMagnify(_ notification: Notification) {
        isFit = false
        editingView.zoomDidChange()
        onZoomGesture?()
    }
}
