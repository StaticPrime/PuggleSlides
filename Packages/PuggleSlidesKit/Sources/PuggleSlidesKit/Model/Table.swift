import Foundation

/// One cell of a table. A merged cell spans `rowSpan` × `columnSpan` cells from its top left; the cells it covers keep
/// their place in the grid with `isCovered` set, as PowerPoint files store them.
public struct TableCell: Hashable, Codable, Sendable {
    public var text: TextBody
    /// `.none` shows what's behind the table.
    public var fill: Fill
    public var rowSpan: Int
    public var columnSpan: Int
    /// Hidden under a merged cell to its left or above it.
    public var isCovered: Bool
    /// Where the text sits in the cell.
    public var anchor: VerticalAnchor
    /// Space between the cell's edges and its text.
    public var insets: TextInsets

    /// DrawingML's default cell padding: 0.1 inch at the sides, 0.05 inch above and below.
    public static let defaultInsets = TextInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)

    public init(text: TextBody = TextBody(), fill: Fill = .none, rowSpan: Int = 1, columnSpan: Int = 1, isCovered: Bool = false,
                anchor: VerticalAnchor = .top, insets: TextInsets = TableCell.defaultInsets) {
        self.text = text
        self.fill = fill
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.isCovered = isCovered
        self.anchor = anchor
        self.insets = insets
    }

    /// A cell with the same look and no text or merging.
    func emptied() -> TableCell {
        var copy = self
        copy.text = TextBody(paragraphs: [TextParagraph(runs: [], style: text.paragraphs.first?.style ?? ParagraphStyle(),
                                                        endStyle: text.paragraphs.first?.runs.first?.style ?? text.paragraphs.first?.endStyle ?? CharacterStyle())],
                             properties: text.properties, listStyle: text.listStyle)
        copy.rowSpan = 1
        copy.columnSpan = 1
        copy.isCovered = false
        return copy
    }
}

/// A block of cells, from its top-left cell to its bottom-right one.
public struct TableCellRange: Hashable, Codable, Sendable {
    public var firstRow: Int
    public var firstColumn: Int
    public var lastRow: Int
    public var lastColumn: Int

    public init(firstRow: Int, firstColumn: Int, lastRow: Int, lastColumn: Int) {
        self.firstRow = min(firstRow, lastRow)
        self.firstColumn = min(firstColumn, lastColumn)
        self.lastRow = max(firstRow, lastRow)
        self.lastColumn = max(firstColumn, lastColumn)
    }

    public init(row: Int, column: Int) {
        self.init(firstRow: row, firstColumn: column, lastRow: row, lastColumn: column)
    }

    public var rows: ClosedRange<Int> { firstRow...lastRow }
    public var columns: ClosedRange<Int> { firstColumn...lastColumn }
    public var isSingleCell: Bool { firstRow == lastRow && firstColumn == lastColumn }

    public func contains(row: Int, column: Int) -> Bool { rows.contains(row) && columns.contains(column) }
}

/// Which borders of the selected cells a border change applies to (the border menu in the toolbar).
public enum TableBorderPosition: String, Codable, CaseIterable, Sendable {
    case all, inner, horizontal, vertical, outer, left, top, right, bottom

    public var title: String {
        switch self {
        case .all: "All borders"
        case .inner: "Inner borders"
        case .horizontal: "Horizontal borders"
        case .vertical: "Vertical borders"
        case .outer: "Outer borders"
        case .left: "Left border"
        case .top: "Top border"
        case .right: "Right border"
        case .bottom: "Bottom border"
        }
    }
}

/// A table: columns with widths, rows with minimum heights (rows grow to fit their text), cells, and borders.
///
/// Borders are shared by the cells on either side: `horizontalBorders[r][c]` is the line above
/// row `r` in column `c` (`r == rowCount` is the bottom edge), and `verticalBorders[r][c]` the line left of column `c`
/// in row `r` (`c == columnCount` is the right edge). Nil is no line.
public struct Table: Hashable, Codable, Sendable {
    public var columnWidths: [Double]
    public var rowHeights: [Double]
    public var cells: [[TableCell]]
    public var horizontalBorders: [[Outline?]]
    public var verticalBorders: [[Outline?]]

    public init(columnWidths: [Double], rowHeights: [Double], cells: [[TableCell]], horizontalBorders: [[Outline?]]? = nil,
                verticalBorders: [[Outline?]]? = nil) {
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.cells = cells
        let rows = rowHeights.count, columns = columnWidths.count
        self.horizontalBorders = horizontalBorders ?? Array(repeating: Array(repeating: nil, count: columns), count: rows + 1)
        self.verticalBorders = verticalBorders ?? Array(repeating: Array(repeating: nil, count: columns + 1), count: rows)
        normalize()
    }

    /// The largest table, in rows and in columns.
    public static let maximumSize = 20
    /// A new table's border: 1 pixel of black.
    public static let defaultBorder = Outline(fill: .solid(ColorRef(RGBColor(red: 0, green: 0, blue: 0))), width: 0.75)
    /// A new table's text size.
    public static let defaultFontSize = 14.0

    /// A new table: equal columns across `width`, rows just tall enough for a line of
    /// 14-point text, every border a thin black line and no fill.
    public static func make(rows: Int, columns: Int, width: Double) -> Table {
        let rows = max(1, min(maximumSize, rows)), columns = max(1, min(maximumSize, columns))
        var cell = TableCell()
        cell.text.listStyle[0] = LevelStyle(character: CharacterStyle(fontSize: defaultFontSize))
        let rowHeight = defaultFontSize * 1.2 + TableCell.defaultInsets.top + TableCell.defaultInsets.bottom
        return Table(columnWidths: Array(repeating: width / Double(columns), count: columns),
                     rowHeights: Array(repeating: rowHeight.rounded(), count: rows),
                     cells: Array(repeating: Array(repeating: cell, count: columns), count: rows),
                     horizontalBorders: Array(repeating: Array(repeating: defaultBorder, count: columns), count: rows + 1),
                     verticalBorders: Array(repeating: Array(repeating: defaultBorder, count: columns + 1), count: rows))
    }

    public var rowCount: Int { rowHeights.count }
    public var columnCount: Int { columnWidths.count }
    public var width: Double { columnWidths.reduce(0, +) }

    /// Makes the grids agree in size: missing cells and borders are added, extra ones dropped, spans clipped to the
    /// table, and covered flags set from the spans.
    public mutating func normalize() {
        let rows = rowHeights.count, columns = columnWidths.count
        cells = (0..<rows).map { row in
            (0..<columns).map { column in
                row < cells.count && column < cells[row].count ? cells[row][column] : TableCell()
            }
        }
        horizontalBorders = (0...rows).map { row in
            (0..<columns).map { column in row < horizontalBorders.count && column < horizontalBorders[row].count ? horizontalBorders[row][column] : nil }
        }
        verticalBorders = (0..<rows).map { row in
            (0...columns).map { column in row < verticalBorders.count && column < verticalBorders[row].count ? verticalBorders[row][column] : nil }
        }
        // Spans come from anchors; everything a span reaches is covered, everything else isn't.
        var covered = Array(repeating: Array(repeating: false, count: columns), count: rows)
        for row in 0..<rows {
            for column in 0..<columns where !covered[row][column] {
                var cell = cells[row][column]
                cell.isCovered = false
                cell.rowSpan = max(1, min(cell.rowSpan, rows - row))
                cell.columnSpan = max(1, min(cell.columnSpan, columns - column))
                // A span can't run into a cell another span already took.
                while cell.columnSpan > 1, (column..<column + cell.columnSpan).contains(where: { covered[row][$0] }) { cell.columnSpan -= 1 }
                cells[row][column] = cell
                for r in row..<row + cell.rowSpan {
                    for c in column..<column + cell.columnSpan where r != row || c != column {
                        covered[r][c] = true
                    }
                }
            }
        }
        for row in 0..<rows {
            for column in 0..<columns where covered[row][column] {
                cells[row][column].isCovered = true
                cells[row][column].rowSpan = 1
                cells[row][column].columnSpan = 1
            }
        }
    }

    // MARK: Cells

    /// The cell that shows at a grid position: the merged cell covering it, or the cell itself.
    public func anchor(row: Int, column: Int) -> (row: Int, column: Int) {
        guard cells.indices.contains(row), cells[row].indices.contains(column), cells[row][column].isCovered else { return (row, column) }
        for r in stride(from: row, through: 0, by: -1) {
            for c in stride(from: column, through: 0, by: -1) {
                let cell = cells[r][c]
                if !cell.isCovered, r + cell.rowSpan > row, c + cell.columnSpan > column { return (r, c) }
            }
        }
        return (row, column)
    }

    /// The anchors of the cells that show, in reading order.
    public var visibleCells: [(row: Int, column: Int)] {
        var result: [(Int, Int)] = []
        for row in 0..<rowCount {
            for column in 0..<columnCount where !cells[row][column].isCovered { result.append((row, column)) }
        }
        return result
    }

    /// A range grown to take in every merged cell it touches, as selecting across merged cells does.
    public func expanded(_ range: TableCellRange) -> TableCellRange {
        var result = range
        var changed = true
        while changed {
            changed = false
            for row in result.rows {
                for column in result.columns {
                    let (r, c) = anchor(row: row, column: column)
                    let cell = cells[r][c]
                    let grown = TableCellRange(firstRow: min(result.firstRow, r), firstColumn: min(result.firstColumn, c),
                                               lastRow: max(result.lastRow, r + cell.rowSpan - 1),
                                               lastColumn: max(result.lastColumn, c + cell.columnSpan - 1))
                    if grown != result {
                        result = grown
                        changed = true
                    }
                }
            }
        }
        return result
    }

    /// The text of every visible cell, row by row and tab separated.
    public var plainText: String {
        (0..<rowCount).map { row in
            (0..<columnCount).filter { !cells[row][$0].isCovered }.map { cells[row][$0].text.plainText }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    // MARK: Rows and columns

    /// Inserts rows before `index` (`rowCount` adds at the bottom), formatted like the row next to them. Merged cells
    /// that run across the insertion point grow to take in the new rows.
    public mutating func insertRows(at index: Int, count: Int = 1) {
        let index = max(0, min(rowCount, index)), count = max(0, min(count, Self.maximumSize * 4))
        guard count > 0, rowCount > 0 else { return }
        let model = index > 0 ? index - 1 : 0
        let templateCells = cells[model].map { $0.emptied() }
        let templateLine = horizontalBorders[index]
        let templateSides = verticalBorders[model]
        let height = rowHeights[model]
        for column in 0..<columnCount where index > 0 && index < rowCount {
            let (r, c) = anchor(row: index, column: column)
            if r < index, c == column { cells[r][c].rowSpan += count }
        }
        for offset in 0..<count {
            cells.insert(templateCells, at: index + offset)
            rowHeights.insert(height, at: index + offset)
            verticalBorders.insert(templateSides, at: index + offset)
            horizontalBorders.insert(templateLine, at: index + offset)
        }
        normalize()
    }

    /// Inserts columns before `index` (`columnCount` adds at the right), formatted like the column next to them.
    /// The table gets wider.
    public mutating func insertColumns(at index: Int, count: Int = 1) {
        let index = max(0, min(columnCount, index)), count = max(0, min(count, Self.maximumSize * 4))
        guard count > 0, columnCount > 0 else { return }
        let model = index > 0 ? index - 1 : 0
        let templateCells = (0..<rowCount).map { cells[$0][model].emptied() }
        let templateLines = (0..<rowCount).map { verticalBorders[$0][index] }
        let templateTops = (0...rowCount).map { horizontalBorders[$0][model] }
        let width = columnWidths[model]
        for row in 0..<rowCount where index > 0 && index < columnCount {
            let (r, c) = anchor(row: row, column: index)
            if c < index, r == row { cells[r][c].columnSpan += count }
        }
        for offset in 0..<count {
            columnWidths.insert(width, at: index + offset)
            for row in 0..<rowCount {
                cells[row].insert(templateCells[row], at: index + offset)
                verticalBorders[row].insert(templateLines[row], at: index + offset)
            }
            for row in 0...rowCount { horizontalBorders[row].insert(templateTops[row], at: index + offset) }
        }
        normalize()
    }

    /// Deletes rows. Merged cells lose the deleted rows; one whose top row goes moves its text to the first row left.
    public mutating func deleteRows(_ range: ClosedRange<Int>) {
        let range = max(0, range.lowerBound)...min(rowCount - 1, range.upperBound)
        guard !range.isEmpty, range.count < rowCount else { return }
        for row in 0..<rowCount {
            for column in 0..<columnCount where !cells[row][column].isCovered {
                let span = cells[row][column].rowSpan
                let last = row + span - 1
                guard span > 1 else { continue }
                let removed = (row...last).filter { range.contains($0) }.count
                if range.contains(row), last > range.upperBound {
                    // The merged cell's first row goes: it carries on from the row after the deleted ones.
                    var moved = cells[row][column]
                    moved.rowSpan = last - range.upperBound
                    moved.isCovered = false
                    cells[range.upperBound + 1][column] = moved
                } else if !range.contains(row) {
                    cells[row][column].rowSpan = span - removed
                }
            }
        }
        cells.removeSubrange(range)
        rowHeights.removeSubrange(range)
        verticalBorders.removeSubrange(range)
        // The line under the deleted rows stays as the line between what's left.
        horizontalBorders.removeSubrange(range)
        normalize()
    }

    public mutating func deleteColumns(_ range: ClosedRange<Int>) {
        let range = max(0, range.lowerBound)...min(columnCount - 1, range.upperBound)
        guard !range.isEmpty, range.count < columnCount else { return }
        for row in 0..<rowCount {
            for column in 0..<columnCount where !cells[row][column].isCovered {
                let span = cells[row][column].columnSpan
                let last = column + span - 1
                guard span > 1 else { continue }
                let removed = (column...last).filter { range.contains($0) }.count
                if range.contains(column), last > range.upperBound {
                    var moved = cells[row][column]
                    moved.columnSpan = last - range.upperBound
                    moved.isCovered = false
                    cells[row][range.upperBound + 1] = moved
                } else if !range.contains(column) {
                    cells[row][column].columnSpan = span - removed
                }
            }
        }
        columnWidths.removeSubrange(range)
        for row in 0..<rowCount {
            cells[row].removeSubrange(range)
            verticalBorders[row].removeSubrange(range)
        }
        for row in 0...rowCount { horizontalBorders[row].removeSubrange(range) }
        normalize()
    }

    /// Format ▸ Table ▸ Distribute rows: the rows share their total height equally.
    public mutating func distributeRows(_ range: ClosedRange<Int>? = nil) {
        let range = range ?? 0...(rowCount - 1)
        guard rowCount > 0 else { return }
        let rows = max(0, range.lowerBound)...min(rowCount - 1, range.upperBound)
        let total = rows.map { rowHeights[$0] }.reduce(0, +)
        for row in rows { rowHeights[row] = total / Double(rows.count) }
    }

    public mutating func distributeColumns(_ range: ClosedRange<Int>? = nil) {
        let range = range ?? 0...(columnCount - 1)
        guard columnCount > 0 else { return }
        let columns = max(0, range.lowerBound)...min(columnCount - 1, range.upperBound)
        let total = columns.map { columnWidths[$0] }.reduce(0, +)
        for column in columns { columnWidths[column] = total / Double(columns.count) }
    }

    // MARK: Merging

    /// Merges a block of cells into its top-left cell, keeping every cell's text as paragraphs.
    public mutating func merge(_ range: TableCellRange) {
        let range = expanded(range)
        guard !range.isSingleCell, range.lastRow < rowCount, range.lastColumn < columnCount else { return }
        var paragraphs: [TextParagraph] = []
        for row in range.rows {
            for column in range.columns where !cells[row][column].isCovered && !cells[row][column].text.isEmpty {
                paragraphs += cells[row][column].text.paragraphs
            }
        }
        var top = cells[range.firstRow][range.firstColumn]
        if !paragraphs.isEmpty { top.text.paragraphs = paragraphs }
        top.rowSpan = range.lastRow - range.firstRow + 1
        top.columnSpan = range.lastColumn - range.firstColumn + 1
        for row in range.rows {
            for column in range.columns {
                if row == range.firstRow && column == range.firstColumn {
                    cells[row][column] = top
                } else {
                    var covered = cells[row][column].emptied()
                    covered.isCovered = true
                    cells[row][column] = covered
                }
            }
        }
        normalize()
    }

    /// Unmerges every merged cell in a block; the text stays in the top-left cell.
    public mutating func unmerge(_ range: TableCellRange) {
        let range = expanded(range)
        for row in range.rows {
            for column in range.columns where !cells[row][column].isCovered {
                let cell = cells[row][column]
                guard cell.rowSpan > 1 || cell.columnSpan > 1 else { continue }
                for r in row..<row + cell.rowSpan {
                    for c in column..<column + cell.columnSpan where r != row || c != column {
                        var freed = cell.emptied()
                        freed.isCovered = false
                        cells[r][c] = freed
                    }
                }
                cells[row][column].rowSpan = 1
                cells[row][column].columnSpan = 1
            }
        }
        normalize()
    }

    public func hasMergedCells(in range: TableCellRange) -> Bool {
        let range = expanded(range)
        return range.rows.contains { row in
            range.columns.contains { column in
                let cell = cells[row][column]
                return !cell.isCovered && (cell.rowSpan > 1 || cell.columnSpan > 1)
            }
        }
    }

    // MARK: Formatting

    /// Sets the fill of every cell in a block.
    public mutating func setFill(_ fill: Fill, in range: TableCellRange) {
        let range = expanded(range)
        for row in range.rows {
            for column in range.columns { cells[row][column].fill = fill }
        }
    }

    /// The border lines of a block that a border position picks: each as (horizontal?, row, column) in the grids.
    public func borderSlots(_ position: TableBorderPosition, in range: TableCellRange) -> [(horizontal: Bool, row: Int, column: Int)] {
        let range = expanded(range)
        var slots: [(Bool, Int, Int)] = []
        let top = position == .all || position == .outer || position == .top
        let bottom = position == .all || position == .outer || position == .bottom
        let left = position == .all || position == .outer || position == .left
        let right = position == .all || position == .outer || position == .right
        let innerHorizontal = position == .all || position == .inner || position == .horizontal
        let innerVertical = position == .all || position == .inner || position == .vertical
        for column in range.columns {
            if top { slots.append((true, range.firstRow, column)) }
            if bottom { slots.append((true, range.lastRow + 1, column)) }
            if innerHorizontal {
                for row in range.rows.dropFirst() where !isInsideMergedCell(horizontal: true, row: row, column: column) {
                    slots.append((true, row, column))
                }
            }
        }
        for row in range.rows {
            if left { slots.append((false, row, range.firstColumn)) }
            if right { slots.append((false, row, range.lastColumn + 1)) }
            if innerVertical {
                for column in range.columns.dropFirst() where !isInsideMergedCell(horizontal: false, row: row, column: column) {
                    slots.append((false, row, column))
                }
            }
        }
        return slots
    }

    /// Whether a border line runs through the middle of a merged cell (and so isn't drawn).
    public func isInsideMergedCell(horizontal: Bool, row: Int, column: Int) -> Bool {
        if horizontal {
            guard row > 0, row < rowCount else { return false }
            return anchor(row: row, column: column) == anchor(row: row - 1, column: column)
        }
        guard column > 0, column < columnCount else { return false }
        return anchor(row: row, column: column) == anchor(row: row, column: column - 1)
    }

    /// Sets borders of a block; `change` edits each chosen border (nil is no line).
    public mutating func updateBorders(_ position: TableBorderPosition, in range: TableCellRange, _ change: (inout Outline?) -> Void) {
        for slot in borderSlots(position, in: range) {
            if slot.horizontal {
                change(&horizontalBorders[slot.row][slot.column])
            } else {
                change(&verticalBorders[slot.row][slot.column])
            }
        }
    }

    /// Scales the columns and minimum row heights, as dragging the table's handles does.
    public mutating func scale(width factorX: Double, height factorY: Double) {
        guard factorX.isFinite, factorY.isFinite, factorX > 0, factorY > 0 else { return }
        columnWidths = columnWidths.map { max(4, $0 * factorX) }
        rowHeights = rowHeights.map { max(4, $0 * factorY) }
    }

    /// Every text body in the table, for edits that reach all of them.
    public mutating func updateTexts(in range: TableCellRange? = nil, _ change: (inout TextBody) -> Void) {
        let range = range.map(expanded) ?? TableCellRange(firstRow: 0, firstColumn: 0, lastRow: rowCount - 1, lastColumn: columnCount - 1)
        guard rowCount > 0, columnCount > 0 else { return }
        for row in range.rows {
            for column in range.columns where !cells[row][column].isCovered { change(&cells[row][column].text) }
        }
    }
}
