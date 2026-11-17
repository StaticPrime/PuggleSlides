import AppKit
import PuggleSlidesKit

/// Where a table's rows, columns and cells fall, in the table's own space (top left at 0, 0), with rows grown to fit
/// their text. Drawing, clicking, editing and resizing all go through this.
@MainActor
struct TableLayout {
    /// Left edges of the columns, then the right edge of the last: `columnCount + 1` values from 0.
    let columnX: [CGFloat]
    /// Top edges of the rows, then the bottom of the last: `rowCount + 1` values from 0.
    let rowY: [CGFloat]
    /// Each row's height as drawn.
    var rowHeights: [CGFloat] { zip(rowY.dropFirst(), rowY).map { $0 - $1 } }
    var size: CGSize { CGSize(width: columnX.last ?? 0, height: rowY.last ?? 0) }

    /// A cell's resolved text, laid out for its width.
    struct CellText {
        let paragraphs: [ResolvedParagraph]
        let layout: TextLayout
    }

    private let texts: [[CellText?]]
    private let table: Table

    init(_ table: Table, style: ElementStyle, slideNumber: Int? = nil) {
        self.table = table
        var x: [CGFloat] = [0]
        for width in table.columnWidths { x.append(x[x.count - 1] + max(1, CGFloat(width))) }
        columnX = x
        var texts: [[CellText?]] = Array(repeating: Array(repeating: nil, count: table.columnCount), count: table.rowCount)
        var heights = table.rowHeights.map { max(1, CGFloat($0)) }
        // Rows grow to fit the text of their single-row cells first; merged cells then stretch their last row.
        var tall: [(row: Int, span: Int, needed: CGFloat)] = []
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            let width = x[min(table.columnCount, column + cell.columnSpan)] - x[column]
            let paragraphs = style.resolvedParagraphs(cell.text, slideNumber: slideNumber)
            let textWidth = max(1, width - CGFloat(cell.insets.left + cell.insets.right))
            let layout = TextLayout.make(paragraphs, width: textWidth, wraps: true)
            texts[row][column] = CellText(paragraphs: paragraphs, layout: layout)
            let needed = layout.usedHeight + CGFloat(cell.insets.top + cell.insets.bottom)
            if cell.rowSpan == 1 {
                heights[row] = max(heights[row], needed)
            } else {
                tall.append((row, cell.rowSpan, needed))
            }
        }
        for item in tall {
            let rows = item.row..<min(table.rowCount, item.row + item.span)
            let total = rows.map { heights[$0] }.reduce(0, +)
            if total < item.needed, let last = rows.last { heights[last] += item.needed - total }
        }
        var y: [CGFloat] = [0]
        for height in heights { y.append(y[y.count - 1] + height) }
        rowY = y
        self.texts = texts
    }

    /// The rectangle a visible cell (or merged cell) covers.
    func rect(row: Int, column: Int) -> CGRect {
        let (row, column) = table.anchor(row: row, column: column)
        let cell = table.cells[row][column]
        let right = min(table.columnCount, column + cell.columnSpan), bottom = min(table.rowCount, row + cell.rowSpan)
        return CGRect(x: columnX[column], y: rowY[row], width: columnX[right] - columnX[column], height: rowY[bottom] - rowY[row])
    }

    /// The rectangle a range of cells covers.
    func rect(of range: TableCellRange) -> CGRect {
        let range = table.expanded(range)
        return CGRect(x: columnX[range.firstColumn], y: rowY[range.firstRow], width: columnX[range.lastColumn + 1] - columnX[range.firstColumn],
                      height: rowY[range.lastRow + 1] - rowY[range.firstRow])
    }

    /// The cell under a point in table space, as the anchor of the cell that shows there.
    func cell(at point: CGPoint) -> (row: Int, column: Int)? {
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        let column = max(0, min(table.columnCount - 1, (columnX.lastIndex { $0 <= point.x } ?? 0)))
        let row = max(0, min(table.rowCount - 1, (rowY.lastIndex { $0 <= point.y } ?? 0)))
        return table.anchor(row: row, column: column)
    }

    /// The grid position under a point, ignoring merges (for selecting ranges).
    func gridPosition(at point: CGPoint) -> (row: Int, column: Int) {
        let column = max(0, min(table.columnCount - 1, (columnX.lastIndex { $0 <= point.x } ?? 0)))
        let row = max(0, min(table.rowCount - 1, (rowY.lastIndex { $0 <= point.y } ?? 0)))
        return (row, column)
    }

    /// The column border (1…columnCount, the right edge included) or row border near a point, for resizing.
    func border(near point: CGPoint, tolerance: CGFloat) -> (horizontal: Bool, index: Int)? {
        if point.y >= -tolerance, point.y <= size.height + tolerance,
           let index = columnX.indices.dropFirst().first(where: { abs(columnX[$0] - point.x) <= tolerance }) {
            return (false, index)
        }
        if point.x >= -tolerance, point.x <= size.width + tolerance,
           let index = rowY.indices.dropFirst().first(where: { abs(rowY[$0] - point.y) <= tolerance }) {
            return (true, index)
        }
        return nil
    }

    func text(row: Int, column: Int) -> CellText? {
        guard texts.indices.contains(row), texts[row].indices.contains(column) else { return nil }
        return texts[row][column]
    }

    /// Where a cell's text starts: inside its padding, moved down for middle and bottom alignment.
    func textOrigin(row: Int, column: Int) -> CGPoint {
        let cell = table.cells[row][column]
        let rect = rect(row: row, column: column)
        let area = rect.inset(by: cell.insets)
        let used = text(row: row, column: column)?.layout.usedHeight ?? 0
        let offset: CGFloat = switch cell.anchor {
        case .top: 0
        case .middle: max(0, (area.height - used) / 2)
        case .bottom: max(0, area.height - used)
        }
        return CGPoint(x: area.minX, y: area.minY + offset)
    }
}

extension CGRect {
    func inset(by insets: TextInsets) -> CGRect {
        CGRect(x: minX + insets.left, y: minY + insets.top, width: max(1, width - insets.left - insets.right),
               height: max(1, height - insets.top - insets.bottom))
    }
}

extension SlideRenderer {
    /// A table: cell fills, then text, then the borders on top.
    static func drawTable(_ table: Table, element: SlideElement, style: ElementStyle, presentation: Presentation, options: Options) {
        guard let context = NSGraphicsContext.current?.cgContext, table.rowCount > 0, table.columnCount > 0 else { return }
        let layout = TableLayout(table, style: style, slideNumber: options.slideNumber)
        context.saveGState()
        context.concatenate(Placement(frame: SlideRect(x: style.placement.frame.x, y: style.placement.frame.y, width: layout.size.width,
                                                       height: layout.size.height), rotation: style.placement.rotation).transform)
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            if !cell.fill.isNone {
                let rect = layout.rect(row: row, column: column)
                paint(cell.fill, path: CGPath(rect: rect, transform: nil), theme: style.theme, presentation: presentation, mode: .normal)
            }
        }
        for (row, column) in table.visibleCells {
            if let hidden = options.hiddenTableCell, hidden.elementID == element.id, hidden.row == row, hidden.column == column { continue }
            guard let text = layout.text(row: row, column: column), !text.paragraphs.allSatisfy(\.isEmpty) else { continue }
            context.saveGState()
            context.clip(to: layout.rect(row: row, column: column))
            text.layout.draw(at: layout.textOrigin(row: row, column: column), paragraphStates: nil)
            context.restoreGState()
        }
        drawTableBorders(table, layout: layout, theme: style.theme)
        context.restoreGState()
    }

    /// Each border segment that shows: not the lines through merged cells.
    static func tableBorderSegments(_ table: Table, layout: TableLayout) -> [(outline: Outline, from: CGPoint, to: CGPoint)] {
        var segments: [(Outline, CGPoint, CGPoint)] = []
        for row in 0...table.rowCount {
            for column in 0..<table.columnCount {
                guard let outline = table.horizontalBorders[row][column], outline.isVisible,
                      !table.isInsideMergedCell(horizontal: true, row: row, column: column) else { continue }
                segments.append((outline, CGPoint(x: layout.columnX[column], y: layout.rowY[row]), CGPoint(x: layout.columnX[column + 1], y: layout.rowY[row])))
            }
        }
        for row in 0..<table.rowCount {
            for column in 0...table.columnCount {
                guard let outline = table.verticalBorders[row][column], outline.isVisible,
                      !table.isInsideMergedCell(horizontal: false, row: row, column: column) else { continue }
                segments.append((outline, CGPoint(x: layout.columnX[column], y: layout.rowY[row]), CGPoint(x: layout.columnX[column], y: layout.rowY[row + 1])))
            }
        }
        return segments
    }

    private static func drawTableBorders(_ table: Table, layout: TableLayout, theme: SlideTheme) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for segment in tableBorderSegments(table, layout: layout) {
            guard case .solid(let color) = segment.outline.fill else { continue }
            let width = CGFloat(segment.outline.width)
            context.saveGState()
            context.setStrokeColor(color.resolved(theme.colors).cgColor)
            context.setLineWidth(width)
            // Square ends close the corners where lines meet.
            context.setLineCap(segment.outline.dash == .solid ? .square : .butt)
            if !segment.outline.dash.pattern.isEmpty {
                context.setLineDash(phase: 0, lengths: segment.outline.dash.pattern.map { CGFloat($0) * max(width, 0.75) })
            }
            context.move(to: segment.from)
            context.addLine(to: segment.to)
            context.strokePath()
            context.restoreGState()
        }
    }
}
