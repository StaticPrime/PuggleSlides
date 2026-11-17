import Foundation

/// Writes tables as PowerPoint stores them: a graphic frame holding `a:tbl`, with every cell's look stated in its
/// own `tcPr` and no table style, so the table looks the same in every app whatever styles it knows.
extension PPTXPartWriter {
    mutating func table(_ element: SlideElement, _ table: Table) {
        var table = table
        table.normalize()
        guard table.rowCount > 0, table.columnCount > 0 else { return }
        let heights = rowHeights(of: table, element: element)
        xml.raw("<p:graphicFrame><p:nvGraphicFramePr>")
        nonVisualProperties(element, fallbackName: "Table", kind: .graphicFrame)
        xml.raw("<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr>")
        applicationProperties(element.placeholder)
        xml.raw("</p:nvGraphicFramePr>")
        // The frame is the table's own size: PowerPoint lays tables out from their columns and rows.
        var placement = element.placement ?? Placement(frame: .zero)
        placement.frame = SlideRect(x: placement.frame.minX, y: placement.frame.minY, width: table.width, height: heights.reduce(0, +))
        transform(placement, tag: "p:xfrm")
        // No style and no style options: nothing but what the cells state.
        xml.raw("<a:graphic><a:graphicData uri=\"\(PPTXNamespace.table)\"><a:tbl><a:tblPr/><a:tblGrid>")
        for width in table.columnWidths { xml.raw("<a:gridCol w=\"\(Self.length(width))\"/>") }
        xml.raw("</a:tblGrid>")
        let anchors = Self.anchors(of: table)
        for row in 0..<table.rowCount {
            xml.raw("<a:tr h=\"\(Self.length(heights[row]))\">")
            for column in 0..<table.columnCount { cell(of: table, row: row, column: column, anchor: anchors[row][column]) }
            xml.raw("</a:tr>")
        }
        xml.raw("</a:tbl></a:graphicData></a:graphic></p:graphicFrame>")
    }

    /// The rows' heights: each row as tall as its text needs where that's more than its minimum, when the
    /// text can be measured; the minimum heights otherwise.
    private func rowHeights(of table: Table, element: SlideElement) -> [Double] {
        let minimum = table.rowHeights.map { $0.isFinite ? max(0, $0) : 0 }
        guard let measure = measureRows else { return minimum }
        let needed = measure(table, element)
        guard needed.count == minimum.count else { return minimum }
        return zip(minimum, needed).map { max($0, $1.isFinite ? $1 : 0) }
    }

    /// The merged cell each grid position belongs to (itself, when it isn't merged), worked out once: looking each
    /// covered cell's up by searching back would take time growing with the square of the table's size.
    static func anchors(of table: Table) -> [[(row: Int, column: Int)]] {
        var result = (0..<table.rowCount).map { row in (0..<table.columnCount).map { (row: row, column: $0) } }
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            guard cell.rowSpan > 1 || cell.columnSpan > 1 else { continue }
            for r in row..<min(table.rowCount, row + cell.rowSpan) {
                for c in column..<min(table.columnCount, column + cell.columnSpan) { result[r][c] = (row, column) }
            }
        }
        return result
    }

    /// One `a:tc`. Merged cells are written as PowerPoint writes them: the top-left cell spans, the cells to its right
    /// are `hMerge` (repeating its row span), the cells below are `vMerge` (repeating its column span), the rest both.
    private mutating func cell(of table: Table, row: Int, column: Int, anchor: (row: Int, column: Int)) {
        let cell = table.cells[row][column]
        xml.raw("<a:tc")
        if cell.isCovered {
            let origin = table.cells[anchor.row][anchor.column]
            if row == anchor.row, origin.rowSpan > 1 { xml.attribute("rowSpan", origin.rowSpan) }
            if column == anchor.column, origin.columnSpan > 1 { xml.attribute("gridSpan", origin.columnSpan) }
            if column > anchor.column { xml.raw(" hMerge=\"1\"") }
            if row > anchor.row { xml.raw(" vMerge=\"1\"") }
        } else {
            if cell.rowSpan > 1 { xml.attribute("rowSpan", cell.rowSpan) }
            if cell.columnSpan > 1 { xml.attribute("gridSpan", cell.columnSpan) }
        }
        xml.raw(">")
        textBody(cell.text, tag: "a:txBody")
        cellProperties(of: table, row: row, column: column)
        xml.raw("</a:tc>")
    }

    /// `tcPr`: margins that differ from DrawingML's defaults, the text's anchor, the four borders and the fill.
    /// Borders are shared by neighboring cells, so both cells beside an edge carry it; a merged cell's right and bottom
    /// borders are its block's, which PowerPoint draws from it.
    private mutating func cellProperties(of table: Table, row: Int, column: Int) {
        let cell = table.cells[row][column]
        xml.raw("<a:tcPr")
        let defaults = TableCell.defaultInsets
        let range = -2_147_483_648...2_147_483_647
        for (name, value, standard) in [("marL", cell.insets.left, defaults.left), ("marR", cell.insets.right, defaults.right),
                                        ("marT", cell.insets.top, defaults.top), ("marB", cell.insets.bottom, defaults.bottom)] {
            let written = PPTXValue.clamped(value * EMU.perPoint, range)
            if written != PPTXValue.clamped(standard * EMU.perPoint, range) { xml.attribute(name, written) }
        }
        switch cell.anchor {
        case .top: break
        case .middle: xml.raw(" anchor=\"ctr\"")
        case .bottom: xml.raw(" anchor=\"b\"")
        }
        xml.raw(">")
        let right = cell.isCovered ? column + 1 : column + cell.columnSpan
        let bottom = cell.isCovered ? row + 1 : row + cell.rowSpan
        border("a:lnL", table.verticalBorders[row][column])
        border("a:lnR", table.verticalBorders[row][min(right, table.columnCount)])
        border("a:lnT", table.horizontalBorders[row][column])
        border("a:lnB", table.horizontalBorders[min(bottom, table.rowCount)][column])
        fill(cell.fill)
        xml.raw("</a:tcPr>")
    }

    /// A cell border; no line is stated as one without fill, so no table style can draw one there.
    private mutating func border(_ tag: String, _ outline: Outline?) {
        guard let outline, outline.isVisible, outline.fill.mediaID == nil else {
            xml.raw("<\(tag)><a:noFill/></\(tag)>")
            return
        }
        var plain = outline
        plain.head = .none
        plain.tail = .none
        line(plain, tag: tag)
    }
}
