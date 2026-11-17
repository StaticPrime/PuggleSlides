import AppKit

/// Insert ▸ Table's grid: hover to choose columns and rows (up to 20 × 20), click to insert. The grid grows as the
/// pointer nears its edge.
final class TableGridPicker: NSView {
    private var columns = 1, rows = 1
    private var shownColumns = 5, shownRows = 5
    private let cell: CGFloat = 16, gap: CGFloat = 3, margin: CGFloat = 12, label: CGFloat = 24
    private let maximum = 20

    init() {
        super.init(frame: .zero)
        resize()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func resize() {
        setFrameSize(NSSize(width: margin * 2 + CGFloat(shownColumns) * (cell + gap) - gap,
                            height: margin * 2 + CGFloat(shownRows) * (cell + gap) - gap + label))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for row in 0..<shownRows {
            for column in 0..<shownColumns {
                let rect = NSRect(x: margin + CGFloat(column) * (cell + gap), y: margin + CGFloat(row) * (cell + gap), width: cell, height: cell)
                let chosen = row < rows && column < columns
                (chosen ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.textBackgroundColor).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                (chosen ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
            }
        }
        // The label reads columns × rows.
        let text = "\(columns) x \(rows)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - margin - size.height + 2), withAttributes: attributes)
    }

    private func choose(at event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = max(1, min(maximum, Int((point.x - margin) / (cell + gap)) + 1))
        let row = max(1, min(maximum, Int((point.y - margin) / (cell + gap)) + 1))
        guard column != columns || row != rows else { return }
        columns = column
        rows = row
        let grow = shownColumns != max(5, min(maximum, column + 1)) || shownRows != max(5, min(maximum, row + 1))
        shownColumns = max(5, min(maximum, column + 1))
        shownRows = max(5, min(maximum, row + 1))
        if grow { resize() } else { needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) { choose(at: event) }
    override func mouseDragged(with event: NSEvent) { choose(at: event) }

    override func mouseUp(with event: NSEvent) {
        choose(at: event)
        guard let item = enclosingMenuItem else { return }
        item.tag = rows * 100 + columns
        item.menu?.cancelTracking()
        NSApp.sendAction(#selector(SlideCommands.ppInsertTable(_:)), to: nil, from: item)
    }
}
