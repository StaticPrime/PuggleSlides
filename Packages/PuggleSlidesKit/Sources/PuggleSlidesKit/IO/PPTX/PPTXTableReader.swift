import Foundation

/// PowerPoint's table styles: the styles a package defines in `ppt/tableStyles.xml`, and definitions of the common
/// built-in ones, which PowerPoint often leaves out of the part because it knows them.
enum PPTXTableStyles {
    /// "Medium Style 2 – Accent 1", PowerPoint's default for new tables.
    static let defaultStyleID = "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"

    /// The Medium Style 2 family by id: the default style's look in each accent (and in Dark 1, plain Medium Style 2).
    static let mediumStyle2: [String: (name: String, color: String)] = [
        "{073A0DAA-6AF3-43AB-8588-CEC1D06C72B9}": ("Medium Style 2", "dk1"),
        "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}": ("Medium Style 2 - Accent 1", "accent1"),
        "{21E4AEA4-8DFA-4A89-87EB-49C32662AFE8}": ("Medium Style 2 - Accent 2", "accent2"),
        "{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}": ("Medium Style 2 - Accent 3", "accent3"),
        "{00A15C55-8517-42AA-B614-E9B94910E393}": ("Medium Style 2 - Accent 4", "accent4"),
        "{7DF18680-E054-41AD-8BC1-D1AEF772440D}": ("Medium Style 2 - Accent 5", "accent5"),
        "{93296810-A885-4BE3-A3E7-6D5BEEA58F35}": ("Medium Style 2 - Accent 6", "accent6"),
    ]
    static let noStyleNoGridID = "{2D5ABB26-0587-4C30-8999-92F81FD0307C}"
    static let noStyleTableGridID = "{5940675A-B579-460E-94D1-54222C63F5DA}"

    /// A built-in style's definition, as PowerPoint writes it into `tableStyles.xml`.
    static func builtIn(_ id: String) -> String? {
        let key = id.uppercased()
        let drawing = PPTXNamespace.drawing
        if let style = mediumStyle2[key] {
            func line(_ width: Int) -> String { "<a:ln w=\"\(width)\" cmpd=\"sng\"><a:solidFill><a:schemeClr val=\"lt1\"/></a:solidFill></a:ln>" }
            let thin = line(12_700), heavy = line(38_100)
            let text = { (bold: Bool, color: String) in
                "<a:tcTxStyle\(bold ? " b=\"on\"" : "")><a:fontRef idx=\"minor\"><a:prstClr val=\"black\"/></a:fontRef><a:schemeClr val=\"\(color)\"/></a:tcTxStyle>"
            }
            let solid = "<a:fill><a:solidFill><a:schemeClr val=\"\(style.color)\"/></a:solidFill></a:fill>"
            let band = "<a:fill><a:solidFill><a:schemeClr val=\"\(style.color)\"><a:tint val=\"40000\"/></a:schemeClr></a:solidFill></a:fill>"
            return "<a:tblStyle xmlns:a=\"\(drawing)\" styleId=\"\(key)\" styleName=\"\(style.name)\"><a:wholeTbl>\(text(false, "dk1"))<a:tcStyle><a:tcBdr>"
                + "<a:left>\(thin)</a:left><a:right>\(thin)</a:right><a:top>\(thin)</a:top><a:bottom>\(thin)</a:bottom>"
                + "<a:insideH>\(thin)</a:insideH><a:insideV>\(thin)</a:insideV></a:tcBdr><a:fill><a:solidFill><a:schemeClr val=\"\(style.color)\">"
                + "<a:tint val=\"20000\"/></a:schemeClr></a:solidFill></a:fill></a:tcStyle></a:wholeTbl>"
                + "<a:band1H><a:tcStyle><a:tcBdr/>\(band)</a:tcStyle></a:band1H><a:band2H><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2H>"
                + "<a:band1V><a:tcStyle><a:tcBdr/>\(band)</a:tcStyle></a:band1V><a:band2V><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2V>"
                + "<a:lastCol>\(text(true, "lt1"))<a:tcStyle><a:tcBdr/>\(solid)</a:tcStyle></a:lastCol>"
                + "<a:firstCol>\(text(true, "lt1"))<a:tcStyle><a:tcBdr/>\(solid)</a:tcStyle></a:firstCol>"
                + "<a:lastRow>\(text(true, "lt1"))<a:tcStyle><a:tcBdr><a:top>\(heavy)</a:top></a:tcBdr>\(solid)</a:tcStyle></a:lastRow>"
                + "<a:firstRow>\(text(true, "lt1"))<a:tcStyle><a:tcBdr><a:bottom>\(heavy)</a:bottom></a:tcBdr>\(solid)</a:tcStyle></a:firstRow></a:tblStyle>"
        }
        let grid: String
        switch key {
        case noStyleNoGridID: grid = "<a:ln><a:noFill/></a:ln>"
        case noStyleTableGridID: grid = "<a:ln w=\"12700\" cmpd=\"sng\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:ln>"
        default: return nil
        }
        let name = key == noStyleNoGridID ? "No Style, No Grid" : "No Style, Table Grid"
        let sides = ["left", "right", "top", "bottom", "insideH", "insideV"].map { "<a:\($0)>\(grid)</a:\($0)>" }.joined()
        return "<a:tblStyle xmlns:a=\"\(drawing)\" styleId=\"\(key)\" styleName=\"\(name)\"><a:wholeTbl><a:tcTxStyle><a:fontRef idx=\"minor\">"
            + "<a:scrgbClr r=\"0\" g=\"0\" b=\"0\"/></a:fontRef><a:schemeClr val=\"tx1\"/></a:tcTxStyle><a:tcStyle><a:tcBdr>\(sides)</a:tcBdr>"
            + "<a:fill><a:noFill/></a:fill></a:tcStyle></a:wholeTbl></a:tblStyle>"
    }
}

/// A line a table style or a cell states for one side of a cell: nothing, no line, or a line.
private enum PPTXEdgeLine {
    case unset
    case none
    case line(Outline)

    init(_ outline: Outline?) {
        if let outline, outline.isVisible { self = .line(outline) } else { self = .none }
    }

    var outline: Outline? {
        if case .line(let outline) = self { return outline }
        return nil
    }

    var isSet: Bool {
        if case .unset = self { return false }
        return true
    }
}

/// One side of a cell: its line, and how strong the line's source is.
private struct PPTXRankedLine {
    /// A merged cell's own line along its block's edge, and a cell's own line: stronger than any style part.
    static let mergedCell = 100
    static let cell = 200

    var line = PPTXEdgeLine.unset
    /// The style part's place in `PPTXTableStyleOptions.partNames`, or one of the ranks above; nothing set is -1.
    var rank = -1
}

/// What one part of a table style (the whole table, the header row, a band …) gives a cell.
private struct PPTXTableStylePart {
    var color: ColorRef?
    var bold: Bool?
    var italic: Bool?
    var fontFamily: String?
    var fill: Fill?
    /// By side: left, right, top, bottom, insideH, insideV.
    var borders: [String: PPTXEdgeLine] = [:]
}

extension PPTXPartContext {
    /// Tables bigger than any app makes (PowerPoint's limit is 75 × 75) are refused rather than built.
    static let maximumTableCells = 100_000

    /// A table from `a:tbl`. Its style, if any, is made explicit in the cells: their fills, borders and text color,
    /// boldness and font, so the table looks as it does in PowerPoint without the style.
    func table(_ node: XNode) -> Table? {
        let columnWidths = node.child("tblGrid")?.children("gridCol").map { max(0, PPTXValue.points($0["w"]) ?? 0) } ?? []
        let rows = node.children("tr")
        guard !columnWidths.isEmpty, !rows.isEmpty, columnWidths.count * rows.count <= Self.maximumTableCells else { return nil }
        let rowCount = rows.count, columnCount = columnWidths.count
        let fills = self.fills()
        let text = self.text

        var cells: [[TableCell]] = []
        var properties: [[XNode?]] = []
        for row in rows {
            var rowCells: [TableCell] = []
            var rowProperties: [XNode?] = []
            for tc in row.children("tc").prefix(columnCount) {
                var cell = TableCell()
                if let body = tc.child("txBody") { cell.text = text.body(body) }
                if PPTXValue.bool(tc["hMerge"]) == true || PPTXValue.bool(tc["vMerge"]) == true {
                    cell.isCovered = true
                } else {
                    cell.rowSpan = min(max(PPTXValue.int(tc["rowSpan"]) ?? 1, 1), rowCount)
                    cell.columnSpan = min(max(PPTXValue.int(tc["gridSpan"]) ?? 1, 1), columnCount)
                }
                let tcPr = tc.child("tcPr")
                let defaults = TableCell.defaultInsets
                cell.insets = TextInsets(left: PPTXValue.points(tcPr?["marL"]) ?? defaults.left, top: PPTXValue.points(tcPr?["marT"]) ?? defaults.top,
                                         right: PPTXValue.points(tcPr?["marR"]) ?? defaults.right,
                                         bottom: PPTXValue.points(tcPr?["marB"]) ?? defaults.bottom)
                switch tcPr?["anchor"] {
                case "ctr": cell.anchor = .middle
                case "b": cell.anchor = .bottom
                default: cell.anchor = .top
                }
                rowCells.append(cell)
                rowProperties.append(tcPr)
            }
            while rowCells.count < columnCount {
                rowCells.append(TableCell())
                rowProperties.append(nil)
            }
            cells.append(rowCells)
            properties.append(rowProperties)
        }
        // Spans stop at the first cell an earlier merge took, as the table evens them out: done here in one pass, so a
        // file claiming merges that overlap costs no more than its cells.
        var taken = Array(repeating: Array(repeating: false, count: columnCount), count: rowCount)
        for row in 0..<rowCount {
            for column in 0..<columnCount where !taken[row][column] {
                let cell = cells[row][column]
                let rowSpan = cell.isCovered ? 1 : min(cell.rowSpan, rowCount - row)
                var columnSpan = cell.isCovered ? 1 : min(cell.columnSpan, columnCount - column)
                if let blocked = (column..<column + columnSpan).first(where: { taken[row][$0] }) { columnSpan = max(1, blocked - column) }
                if !cell.isCovered {
                    cells[row][column].rowSpan = rowSpan
                    cells[row][column].columnSpan = columnSpan
                }
                for r in row..<row + rowSpan {
                    for c in column..<column + columnSpan where r != row || c != column { taken[r][c] = true }
                }
            }
        }
        let rowHeights = rows.map { max(0, PPTXValue.points($0["h"]) ?? 0) }
        var table = Table(columnWidths: columnWidths, rowHeights: rowHeights, cells: cells)

        // The style and which of its parts are on.
        let tblPr = node.child("tblPr")
        var styleNode = tblPr?.child("tableStyle")
        if styleNode == nil, let id = tblPr?.child("tableStyleId")?.text.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            styleNode = package.tableStyle(id: id)
        }
        let options = PPTXTableStyleOptions(tblPr)
        let parts = styleNode.map { style in
            Dictionary(uniqueKeysWithValues: PPTXTableStyleOptions.partNames.compactMap { name in
                style.child(name).map { (name, stylePart($0, fills: fills)) }
            })
        } ?? [:]
        // Behind every cell: the table's own fill, else the style's background.
        let background = fills.fill(in: tblPr) ?? styleNode?.child("tblBg").flatMap { styleFill($0, fills: fills) }

        // Fills and text: the cell's own, over the style parts that reach its block.
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let cell = table.cells[row][column]
                let block = cell.isCovered ? (rows: row...row, columns: column...column)
                    : (rows: row...(row + cell.rowSpan - 1), columns: column...(column + cell.columnSpan - 1))
                let applied = options.parts(rows: block.rows, columns: block.columns, rowCount: rowCount, columnCount: columnCount)
                    .compactMap { parts[$0] }
                var fill = fills.fill(in: properties[row][column]) ?? applied.reversed().lazy.compactMap(\.fill).first
                if fill == nil || fill == Fill.none, let background { fill = background }
                table.cells[row][column].fill = fill ?? Fill.none
                let color = applied.reversed().lazy.compactMap(\.color).first
                let bold = applied.reversed().lazy.compactMap(\.bold).first
                let italic = applied.reversed().lazy.compactMap(\.italic).first
                let font = applied.reversed().lazy.compactMap(\.fontFamily).first
                if color != nil || bold != nil || italic != nil || font != nil {
                    var body = table.cells[row][column].text
                    for level in 0...8 {
                        var style = body.listStyle[level]
                        if style.character.color == nil { style.character.color = color }
                        if style.character.bold == nil { style.character.bold = bold }
                        if style.character.italic == nil { style.character.italic = italic }
                        if style.character.fontFamily == nil { style.character.fontFamily = font }
                        body.listStyle[level] = style
                    }
                    table.cells[row][column].text = body
                }
            }
        }

        // Each grid position's four sides, ranked by where their line comes from: the style's parts in their order of
        // strength, then a merged cell's own lines along its block's edges, then the position's own lines.
        var sides = Array(repeating: Array(repeating: [PPTXRankedLine](repeating: PPTXRankedLine(), count: 4), count: columnCount),
                          count: rowCount)
        let left = 0, right = 1, top = 2, bottom = 3
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                for name in options.parts(rows: row...row, columns: column...column, rowCount: rowCount, columnCount: columnCount) {
                    guard let part = parts[name] else { continue }
                    let region = options.region(of: name, row: row, column: column, rowCount: rowCount, columnCount: columnCount)
                    let names = [column == region.columns.lowerBound ? "left" : "insideV", column == region.columns.upperBound ? "right" : "insideV",
                                 row == region.rows.lowerBound ? "top" : "insideH", row == region.rows.upperBound ? "bottom" : "insideH"]
                    let rank = PPTXTableStyleOptions.partNames.firstIndex(of: name) ?? 0
                    for (side, name) in names.enumerated() {
                        if let line = part.borders[name], line.isSet { sides[row][column][side] = PPTXRankedLine(line: line, rank: rank) }
                    }
                }
            }
        }
        let lineTags = ["lnL", "lnR", "lnT", "lnB"]
        func explicit(_ node: XNode, over base: PPTXRankedLine, rank: Int) -> PPTXRankedLine {
            PPTXRankedLine(line: PPTXEdgeLine(fills.outline(node, base: base.line.outline)), rank: rank)
        }
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let cell = table.cells[row][column]
                guard !cell.isCovered, cell.rowSpan > 1 || cell.columnSpan > 1, let tcPr = properties[row][column] else { continue }
                let lastRow = row + cell.rowSpan - 1, lastColumn = column + cell.columnSpan - 1
                for r in row...lastRow {
                    for c in column...lastColumn {
                        let edges = [c == column, c == lastColumn, r == row, r == lastRow]
                        for side in 0..<4 where edges[side] {
                            if let line = tcPr.child(lineTags[side]) {
                                sides[r][c][side] = explicit(line, over: sides[r][c][side], rank: PPTXRankedLine.mergedCell)
                            }
                        }
                    }
                }
            }
        }
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let cell = table.cells[row][column]
                guard let tcPr = properties[row][column] else { continue }
                // A merged cell's right and bottom lines are its block's, placed above.
                let spans = !cell.isCovered && (cell.rowSpan > 1 || cell.columnSpan > 1)
                for side in 0..<4 where !(spans && (side == right || side == bottom)) {
                    if let line = tcPr.child(lineTags[side]) {
                        sides[row][column][side] = explicit(line, over: sides[row][column][side], rank: PPTXRankedLine.cell)
                    }
                }
            }
        }

        // Neighbors share each edge. The stronger source wins (a header row's line over the inner lines of the whole
        // table, a cell's own line over its style's); between equals, a line wins over none, and the later cell's line
        // over the earlier cell's.
        func shared(_ earlier: PPTXRankedLine?, _ later: PPTXRankedLine?) -> Outline? {
            switch (earlier, later) {
            case let (earlier?, later?):
                if earlier.rank != later.rank { return earlier.rank > later.rank ? earlier.line.outline : later.line.outline }
                return later.line.outline ?? earlier.line.outline
            case let (earlier?, nil): return earlier.line.outline
            case let (nil, later?): return later.line.outline
            case (nil, nil): return nil
            }
        }
        for row in 0...rowCount {
            for column in 0..<columnCount {
                table.horizontalBorders[row][column] = shared(row > 0 ? sides[row - 1][column][bottom] : nil,
                                                              row < rowCount ? sides[row][column][top] : nil)
            }
        }
        for row in 0..<rowCount {
            for column in 0...columnCount {
                table.verticalBorders[row][column] = shared(column > 0 ? sides[row][column - 1][right] : nil,
                                                            column < columnCount ? sides[row][column][left] : nil)
            }
        }
        return table
    }

    /// One part of a table style, with colors read under this part's color map.
    private func stylePart(_ node: XNode, fills: PPTXFillReader) -> PPTXTableStylePart {
        var part = PPTXTableStylePart()
        if let text = node.child("tcTxStyle") {
            part.color = colors.color(in: text) ?? text.child("fontRef").flatMap { colors.color(in: $0) }
            func flag(_ value: String?) -> Bool? {
                switch value {
                case "on": true
                case "off": false
                default: nil
                }
            }
            part.bold = flag(text["b"])
            part.italic = flag(text["i"])
            switch text.child("fontRef")?["idx"] {
            case "major": part.fontFamily = "+mj-lt"
            case "minor": part.fontFamily = "+mn-lt"
            default: break
            }
            if let face = text.child("font")?.child("latin")?["typeface"], !face.isEmpty { part.fontFamily = face }
        }
        if let cell = node.child("tcStyle") {
            part.fill = styleFill(cell, fills: fills)
            for side in cell.child("tcBdr")?.children ?? [] {
                if let line = side.child("ln") {
                    part.borders[side.name] = PPTXEdgeLine(fills.outline(line, base: nil))
                } else if let reference = side.child("lnRef"), let index = PPTXValue.int(reference["idx"]) {
                    let reader = fills.themeStyles(placeholder: colors.color(in: reference))
                    if index > 0, let line = theme.lineStyle(index) {
                        part.borders[side.name] = PPTXEdgeLine(reader.outline(line, base: nil))
                    } else if index > 0, let color = reader.colors.placeholder {
                        part.borders[side.name] = .line(.solid(color))
                    } else {
                        part.borders[side.name] = PPTXEdgeLine.none
                    }
                }
            }
        }
        return part
    }

    /// A style's cell or table background: `a:fill` holding a fill, or `a:fillRef` to the theme's fill styles.
    private func styleFill(_ node: XNode, fills: PPTXFillReader) -> Fill? {
        if let fill = node.child("fill") { return fills.fill(in: fill) }
        guard let reference = node.child("fillRef"), let index = PPTXValue.int(reference["idx"]) else { return nil }
        let reader = fills.themeStyles(placeholder: colors.color(in: reference))
        if index == 0 { return Fill.none }
        return theme.fillStyle(index).flatMap(reader.fill) ?? reader.colors.placeholder.map(Fill.solid)
    }
}

/// Which parts of a table's style are on (header row, banded rows …), and where each applies.
struct PPTXTableStyleOptions {
    var firstRow = false
    var lastRow = false
    var firstColumn = false
    var lastColumn = false
    var bandRows = false
    var bandColumns = false

    /// Style parts from the weakest to the strongest, in the order the schema lists them.
    static let partNames = ["wholeTbl", "band1H", "band2H", "band1V", "band2V", "lastCol", "firstCol", "lastRow", "seCell", "swCell", "firstRow",
                            "neCell", "nwCell"]

    init(_ tblPr: XNode?) {
        guard let tblPr else { return }
        firstRow = PPTXValue.bool(tblPr["firstRow"]) ?? false
        lastRow = PPTXValue.bool(tblPr["lastRow"]) ?? false
        firstColumn = PPTXValue.bool(tblPr["firstCol"]) ?? false
        lastColumn = PPTXValue.bool(tblPr["lastCol"]) ?? false
        bandRows = PPTXValue.bool(tblPr["bandRow"]) ?? false
        bandColumns = PPTXValue.bool(tblPr["bandCol"]) ?? false
    }

    /// The parts that reach a block of cells, weakest first. Bands count from the first row or column after a header.
    func parts(rows: ClosedRange<Int>, columns: ClosedRange<Int>, rowCount: Int, columnCount: Int) -> [String] {
        var result = ["wholeTbl"]
        let isFirstRow = firstRow && rows.lowerBound == 0, isLastRow = lastRow && rows.upperBound == rowCount - 1
        let isFirstColumn = firstColumn && columns.lowerBound == 0, isLastColumn = lastColumn && columns.upperBound == columnCount - 1
        let band = rows.lowerBound - (firstRow ? 1 : 0)
        if bandRows, band >= 0 { result.append(band % 2 == 0 ? "band1H" : "band2H") }
        let columnBand = columns.lowerBound - (firstColumn ? 1 : 0)
        if bandColumns, columnBand >= 0 { result.append(columnBand % 2 == 0 ? "band1V" : "band2V") }
        if isLastColumn { result.append("lastCol") }
        if isFirstColumn { result.append("firstCol") }
        if isLastRow { result.append("lastRow") }
        if isLastRow && isLastColumn { result.append("seCell") }
        if isLastRow && isFirstColumn { result.append("swCell") }
        if isFirstRow { result.append("firstRow") }
        if isFirstRow && isLastColumn { result.append("neCell") }
        if isFirstRow && isFirstColumn { result.append("nwCell") }
        return result
    }

    /// The block of cells a part's outer borders go round, for a cell it reaches: a row, a column, a corner cell or
    /// the whole table.
    func region(of part: String, row: Int, column: Int, rowCount: Int, columnCount: Int) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        let allRows = 0...max(0, rowCount - 1), allColumns = 0...max(0, columnCount - 1)
        switch part {
        case "firstRow", "lastRow", "band1H", "band2H": return (row...row, allColumns)
        case "firstCol", "lastCol", "band1V", "band2V": return (allRows, column...column)
        case "seCell", "swCell", "neCell", "nwCell": return (row...row, column...column)
        default: return (allRows, allColumns)
        }
    }
}
