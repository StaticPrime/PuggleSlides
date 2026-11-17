import AppKit
import PuggleSlidesKit

/// Edit ▸ Find and replace on the canvas.
extension SlideEditingView {
    /// Every match on the slide in yellow behind its text, the current one in orange.
    /// Matches inside groups mark nothing: their group is selected instead.
    func drawFindHighlights(_ slide: Slide) {
        guard !findMatches.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let number: Int? = controller.isThemeBuilderOpen ? nil : (controller.currentSlideIndex ?? 0) + 1
        context.saveGState()
        context.setBlendMode(.multiply)
        for match in findMatches where match.slideID == slide.id {
            let color = match == currentFindMatch ? NSColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1)
                : NSColor(srgbRed: 1, green: 0.93, blue: 0.35, alpha: 1)
            let range = NSRange(location: match.range.lowerBound, length: match.range.count)
            let rects: [CGRect]
            let transform: CGAffineTransform
            switch match.place {
            case .element(let path):
                guard path.count == 1, let element = slide.element(id: path[0]), editor?.elementID != element.id else { continue }
                (rects, transform) = SlideRenderer.textRects(of: controller.presentation.style(for: element, on: slide), range: range, slideNumber: number)
            case .cell(let path, let row, let column):
                guard path.count == 1, let element = slide.element(id: path[0]), let (layout, placement) = tableGeometry(element),
                      let text = layout.text(row: row, column: column) else { continue }
                if let editor, editor.elementID == element.id, editor.cell?.row == row, editor.cell?.column == column { continue }
                let origin = layout.textOrigin(row: row, column: column)
                rects = text.layout.rects(for: range).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                transform = placement.transform
            case .notes:
                continue
            }
            context.saveGState()
            context.concatenate(transform)
            context.setFillColor(color.cgColor)
            context.fill(rects.map { $0.insetBy(dx: -1, dy: 0) })
            context.restoreGState()
        }
        context.restoreGState()
    }
}
