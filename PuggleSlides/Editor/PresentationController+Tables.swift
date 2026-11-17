import AppKit
import PuggleSlidesKit

extension PresentationController {
    // MARK: Inserting

    /// Insert ▸ Table: a new table, selected with its first cell ready for typing.
    @discardableResult
    func insertTable(rows: Int, columns: Int) -> UUID? {
        guard currentSlideIndex != nil else { return nil }
        let element = presentation.makeTableElement(rows: rows, columns: columns)
        insert([element], actionName: "Insert Table")
        return element.id
    }

    /// Insert ▸ Chart: a chart of sample numbers to edit in the chart editor.
    @discardableResult
    func insertChart(_ kind: ChartKind) -> UUID? {
        guard currentSlideIndex != nil else { return nil }
        let element = presentation.makeChartElement(kind)
        insert([element], actionName: "Insert Chart")
        return element.id
    }

    /// Insert ▸ Word art: the typed text as word art, at its natural size, centered on the slide.
    @discardableResult
    func insertWordArt(_ text: String) -> UUID? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentSlideIndex != nil, let slide = currentSlide, !text.isEmpty else { return nil }
        let shape = Shape.wordArt(text)
        var element = SlideElement(name: nextElementName("Word Art"), placement: Placement(frame: SlideRect(x: 0, y: 0, width: 100, height: 100)),
                                   content: .shape(shape))
        let paragraphs = presentation.style(for: element, on: slide).resolvedParagraphs()
        var size = WordArt.naturalSize(paragraphs)
        // Big enough to read, and never wider than the slide.
        let slideSize = presentation.slideSize
        let scale = min(1, slideSize.width * 0.8 / size.width, slideSize.height * 0.5 / size.height)
        size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        element.placement = Placement(frame: SlideRect(x: ((slideSize.width - size.width) / 2).rounded(), y: ((slideSize.height - size.height) / 2).rounded(),
                                                       width: size.width, height: size.height))
        insert([element], actionName: "Insert Word Art")
        return element.id
    }

    /// New text for word art, in the style of its first letters; the frame keeps its size.
    func setWordArtText(_ id: UUID, to text: String) {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard !lines.joined().isEmpty else { return }
        editElements([id], "Edit Word Art") { element, _ in
            guard var shape = element.shape, shape.isWordArt, var body = shape.text else { return }
            let style = body.paragraphs.first?.runs.first?.style ?? body.paragraphs.first?.endStyle ?? CharacterStyle()
            body.paragraphs = lines.map { TextParagraph($0, style: style) }
            shape.text = body
            element.shape = shape
        }
    }

    // MARK: The selected table

    /// The one selected element, when it's a table.
    var selectedTableElement: SlideElement? {
        guard selectedElementIDs.count == 1, let element = selectedElements.first, element.table != nil else { return nil }
        return element
    }

    /// The selected cells, or the whole table.
    func tableRange(_ table: Table) -> TableCellRange {
        if let range = tableSelection, range.lastRow < table.rowCount, range.lastColumn < table.columnCount { return table.expanded(range) }
        return TableCellRange(firstRow: 0, firstColumn: 0, lastRow: max(0, table.rowCount - 1), lastColumn: max(0, table.columnCount - 1))
    }

    /// Makes a table element's frame match the table as drawn (rows grow with their text).
    func fitTableFrame(_ element: inout SlideElement, style: ElementStyle) {
        guard let table = element.table, var placement = element.placement else { return }
        let size = TableLayout(table, style: style).size
        placement.frame.width = size.width
        placement.frame.height = size.height
        element.placement = placement
    }

    /// Edits the selected table (or the table `id`) as one undo step; `change` gets the selected cells.
    func editTable(_ actionName: String, id: UUID? = nil, keepsSelection: Bool = true,
                   _ change: (inout Table, TableCellRange) -> TableCellRange?) {
        guard let slideIndex = currentSlideIndex, let id = id ?? selectedTableElement?.id,
              let element = currentSlide?.element(id: id), let table = element.table else { return }
        let range = tableRange(table)
        var newRange: TableCellRange?
        perform(actionName, selecting: [id]) { presentation in
            let slide = presentation.slides[slideIndex]
            guard let index = slide.elementIndex(id: id), var updated = slide.elements[index].table else { return }
            newRange = change(&updated, range)
            updated.normalize()
            var edited = slide.elements[index]
            edited.table = updated
            fitTableFrame(&edited, style: presentation.style(for: edited, on: slide))
            presentation.slides[slideIndex].elements[index] = edited
        }
        if keepsSelection { tableSelection = newRange }
        notify(.selection)
    }

    func insertTableRows(below: Bool) {
        editTable(below ? "Insert Row Below" : "Insert Row Above") { table, range in
            let count = range.lastRow - range.firstRow + 1
            table.insertRows(at: below ? range.lastRow + 1 : range.firstRow, count: count)
            let first = below ? range.lastRow + 1 : range.firstRow
            return TableCellRange(firstRow: first, firstColumn: 0, lastRow: first + count - 1, lastColumn: table.columnCount - 1)
        }
    }

    func insertTableColumns(right: Bool) {
        editTable(right ? "Insert Column Right" : "Insert Column Left") { table, range in
            let count = range.lastColumn - range.firstColumn + 1
            table.insertColumns(at: right ? range.lastColumn + 1 : range.firstColumn, count: count)
            let first = right ? range.lastColumn + 1 : range.firstColumn
            return TableCellRange(firstRow: 0, firstColumn: first, lastRow: table.rowCount - 1, lastColumn: first + count - 1)
        }
    }

    /// Delete row: deleting every row deletes the table.
    func deleteTableRows() {
        guard let element = selectedTableElement, let table = element.table else { return }
        let range = tableRange(table)
        if range.firstRow == 0 && range.lastRow == table.rowCount - 1 { return deleteSelectedElements() }
        editTable("Delete Row") { table, range in
            table.deleteRows(range.rows)
            return nil
        }
    }

    func deleteTableColumns() {
        guard let element = selectedTableElement, let table = element.table else { return }
        let range = tableRange(table)
        if range.firstColumn == 0 && range.lastColumn == table.columnCount - 1 { return deleteSelectedElements() }
        editTable("Delete Column") { table, range in
            table.deleteColumns(range.columns)
            return nil
        }
    }

    func distributeTableRows() {
        editTable("Distribute Rows") { table, range in
            table.distributeRows(range.rowCount > 1 ? range.rows : nil)
            return tableSelection
        }
    }

    func distributeTableColumns() {
        editTable("Distribute Columns") { table, range in
            table.distributeColumns(range.columnCount > 1 ? range.columns : nil)
            return tableSelection
        }
    }

    var canMergeTableCells: Bool {
        guard let table = selectedTableElement?.table, let range = tableSelection.map(table.expanded) else { return false }
        return !range.isSingleCell
    }

    var canUnmergeTableCells: Bool {
        guard let table = selectedTableElement?.table else { return false }
        return table.hasMergedCells(in: tableRange(table))
    }

    func mergeTableCells() {
        guard canMergeTableCells else { return }
        editTable("Merge Cells") { table, range in
            table.merge(range)
            return TableCellRange(row: range.firstRow, column: range.firstColumn)
        }
    }

    func unmergeTableCells() {
        editTable("Unmerge Cells") { table, range in
            table.unmerge(range)
            return range
        }
    }

    // MARK: Cell formatting

    func setTableFill(_ fill: Fill) {
        editTable("Fill Color") { table, range in
            table.setFill(fill, in: range)
            return tableSelection
        }
    }

    /// Changes the chosen borders of the selected cells, starting from what they show now; hidden borders come back
    /// as thin black lines when their weight or dash changes.
    func editTableBorders(_ actionName: String, showsHidden: Bool = true, _ change: @escaping (inout Outline) -> Void) {
        let position = tableBorderPosition
        editTable(actionName) { table, range in
            table.updateBorders(position, in: range) { border in
                guard var outline = border ?? (showsHidden ? Table.defaultBorder : nil) else { return }
                if outline.width <= 0 { outline.width = 0.75 }
                change(&outline)
                border = outline.fill.isNone ? nil : outline
            }
            return tableSelection
        }
    }

    func setTableCellAnchor(_ anchor: VerticalAnchor) {
        editTable("Vertical Align") { table, range in
            for row in range.rows {
                for column in range.columns { table.cells[row][column].anchor = anchor }
            }
            return tableSelection
        }
    }

    /// The selected cells' fill and border, for the toolbar.
    func tableSummary(_ table: Table, theme: SlideTheme) -> ShapeSummary {
        let range = tableRange(table)
        let fills = range.rows.flatMap { row in range.columns.map { table.cells[row][$0].fill } }
        let borders = table.borderSlots(tableBorderPosition, in: range).map { slot in
            slot.horizontal ? table.horizontalBorders[slot.row][slot.column] : table.verticalBorders[slot.row][slot.column]
        }
        func hex(_ fill: Fill?) -> String? {
            guard case .solid(let color)? = fill else { return nil }
            return color.resolved(theme.colors).rgb.hex
        }
        let firstBorder = borders.first ?? nil
        let sameBorders = borders.allSatisfy { $0 == firstBorder }
        return ShapeSummary(fillHex: fills.allSatisfy { $0 == fills.first } ? hex(fills.first) : nil,
                            borderHex: sameBorders ? hex(firstBorder?.fill) : nil,
                            borderWidth: sameBorders ? firstBorder?.width : nil, dash: sameBorders ? firstBorder?.dash : nil)
    }
}

extension TableCellRange {
    var rowCount: Int { lastRow - firstRow + 1 }
    var columnCount: Int { lastColumn - firstColumn + 1 }
}
