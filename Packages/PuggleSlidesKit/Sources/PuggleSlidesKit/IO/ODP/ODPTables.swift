import Foundation

// MARK: - Cell properties

/// One side of a table cell's border as `fo:border-*` states it: "none", or a width, a line style and a color
/// ("0.75pt solid #000000").
enum ODFBorder: Hashable {
    case none
    case line(width: Double, style: String, color: RGBColor)

    /// Reads a border whatever order its parts come in. A line that leaves out its width or color is a thin black one,
    /// and a line with no width is no line.
    init?(_ text: String?) {
        guard let text else { return nil }
        let tokens = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        var width: Double?
        var style: String?
        var color: RGBColor?
        for token in tokens {
            if let rgb = ODFValue.color(token) {
                color = rgb
            } else if let length = ODFValue.length(token) {
                width = length
            } else {
                // CSS's keyword widths, then the line style.
                switch token {
                case "thin": width = 0.75
                case "medium": width = 2.25
                case "thick": width = 3.75
                default: style = token
                }
            }
        }
        if style == "none" || style == "hidden" || (width.map { $0 <= 0 } ?? false) {
            self = .none
            return
        }
        self = .line(width: min(width ?? 0.75, 100), style: style ?? "solid", color: color ?? .black)
    }

    /// The border an outline draws: its width, its dash as the nearest border style, and its color resolved (borders
    /// have no transparency, so it's dropped).
    init(_ outline: Outline?, colors: ColorScheme) {
        guard let outline, outline.isVisible else {
            self = .none
            return
        }
        let color: ColorRef?
        switch outline.fill {
        case .solid(let solid): color = solid
        case .gradient(let gradient): color = gradient.stops.min { $0.position < $1.position }?.color
        case .none, .picture: color = nil
        }
        guard let color else {
            self = .none
            return
        }
        self = .line(width: min(max(outline.width, 0.01), 100), style: Self.style(outline.dash), color: color.resolved(colors).rgb)
    }

    /// Border dashes as the border styles LibreOffice draws: its fine dashes are short and its plain dashes long.
    static func style(_ dash: DashStyle) -> String {
        switch dash {
        case .solid: "solid"
        case .dot: "dotted"
        case .dash: "fine-dashed"
        case .longDash: "dashed"
        case .dashDot: "dash-dot"
        case .longDashDot: "dash-dot-dot"
        }
    }

    /// The nearest dash to a border style; double, grooved and other lines are solid.
    static func dash(_ style: String) -> DashStyle {
        switch style {
        case "dotted": .dot
        case "fine-dashed": .dash
        case "dashed": .longDash
        case "dash-dot": .dashDot
        case "dash-dot-dot": .longDashDot
        default: .solid
        }
    }

    var text: String {
        switch self {
        case .none: "none"
        case .line(let width, let style, let color): "\(ODFFormat.pt(width)) \(style) \(ODFFormat.color(color))"
        }
    }

    /// The line the border draws; nil for none.
    var outline: Outline? {
        guard case .line(let width, let style, let color) = self else { return nil }
        return Outline(fill: .solid(ColorRef(color)), width: width, dash: Self.dash(style))
    }

    /// Which of two borders LibreOffice draws where the cells on either side of an edge disagree: a line over none,
    /// the wider of two lines, and between equals the later one. None only fills an edge nothing else claimed.
    static func wins(_ candidate: ODFBorder, over current: ODFBorder?) -> Bool {
        guard let current else { return true }
        switch (candidate, current) {
        case (.none, _): return false
        case (.line, .none): return true
        case (.line(let width, _, _), .line(let currentWidth, _, _)): return width >= currentWidth
        }
    }
}

/// A table cell's fill: `fo:background-color` (nil is "transparent"), a `style:background-image`, or the fill LibreOffice
/// Impress keeps in `style:graphic-properties`.
enum ODFCellFill: Hashable {
    case color(RGBColor?)
    case image(href: String, repeatMode: String?)
    case graphic(ODFGraphicProperties)
}

/// What a table cell style states about a cell's look; nil properties inherit. Written as `style:table-cell-properties`.
struct ODFCellProperties: Hashable {
    var fill: ODFCellFill?
    var top: ODFBorder?
    var bottom: ODFBorder?
    var left: ODFBorder?
    var right: ODFBorder?
    var anchor: VerticalAnchor?
    var paddingLeft: Double?
    var paddingTop: Double?
    var paddingRight: Double?
    var paddingBottom: Double?
    /// Rotated text and diagonal lines, which cells in the model don't have: reading notes them to warn.
    var isTurnedOrCrossed: Bool?

    var isEmpty: Bool { self == ODFCellProperties() }

    init() {}

    /// Reads `style:table-cell-properties`. A table cell style also gives what LibreOffice Impress keeps elsewhere: the
    /// fill, padding and alignment in `style:graphic-properties`, and (in files from older versions) the borders in
    /// `style:paragraph-properties`. What `style:table-cell-properties` says wins.
    init(style node: ODFNode, family: String) {
        if let cell = node.child("style:table-cell-properties") {
            readBorders(cell)
            readPadding(cell)
            switch cell["style:vertical-align"] {
            case "top": anchor = .top
            case "middle": anchor = .middle
            case "bottom": anchor = .bottom
            default: break
            }
            if let image = cell.child("style:background-image"), let href = image["xlink:href"], !href.isEmpty {
                fill = .image(href: href, repeatMode: image["style:repeat"])
            } else if let background = cell["fo:background-color"] {
                if background.lowercased() == "transparent" {
                    fill = .color(nil)
                } else if let rgb = ODFValue.color(background) {
                    fill = .color(rgb)
                }
            }
            let turned = ODFValue.angle(cell["style:rotation-angle"]).map { Placement.normalized($0) != 0 }
            let crossed = [cell["style:diagonal-tl-br"], cell["style:diagonal-bl-tr"]].contains { ODFBorder($0).map { $0 != .none } ?? false }
            if turned != nil || crossed { isTurnedOrCrossed = (turned ?? false) || crossed }
        }
        guard family == "table-cell" else { return }
        if let graphicNode = node.child("style:graphic-properties") {
            let graphic = ODFGraphicProperties(graphicNode)
            if fill == nil, graphic.fill != nil || graphic.fillColor != nil {
                var fillOnly = ODFGraphicProperties()
                fillOnly.fill = graphic.fill
                fillOnly.fillColor = graphic.fillColor
                fillOnly.gradientName = graphic.gradientName
                fillOnly.imageName = graphic.imageName
                fillOnly.hatchName = graphic.hatchName
                fillOnly.repeatMode = graphic.repeatMode
                fillOnly.opacity = graphic.opacity
                fill = .graphic(fillOnly)
            }
            anchor = anchor ?? graphic.anchor
            paddingLeft = paddingLeft ?? graphic.paddingLeft.map { max(0, $0) }
            paddingTop = paddingTop ?? graphic.paddingTop.map { max(0, $0) }
            paddingRight = paddingRight ?? graphic.paddingRight.map { max(0, $0) }
            paddingBottom = paddingBottom ?? graphic.paddingBottom.map { max(0, $0) }
        }
        if let paragraphNode = node.child("style:paragraph-properties") {
            var legacy = ODFCellProperties()
            legacy.readBorders(paragraphNode)
            top = top ?? legacy.top
            bottom = bottom ?? legacy.bottom
            left = left ?? legacy.left
            right = right ?? legacy.right
        }
    }

    private mutating func readBorders(_ node: ODFNode) {
        let all = ODFBorder(node["fo:border"])
        top = ODFBorder(node["fo:border-top"]) ?? all
        bottom = ODFBorder(node["fo:border-bottom"]) ?? all
        left = ODFBorder(node["fo:border-left"]) ?? all
        right = ODFBorder(node["fo:border-right"]) ?? all
    }

    private mutating func readPadding(_ node: ODFNode) {
        func length(_ name: String) -> Double? { ODFValue.length(node[name]).map { min(max(0, $0), 10_000) } }
        let all = length("fo:padding")
        paddingLeft = length("fo:padding-left") ?? all
        paddingTop = length("fo:padding-top") ?? all
        paddingRight = length("fo:padding-right") ?? all
        paddingBottom = length("fo:padding-bottom") ?? all
    }

    /// These properties over a parent's. LibreOffice's fills merge attribute by attribute, as a style that only changes
    /// the fill color keeps its parent's fill.
    func merged(over base: ODFCellProperties) -> ODFCellProperties {
        var result = self
        switch (fill, base.fill) {
        case (.graphic(let own)?, .graphic(let inherited)?): result.fill = .graphic(own.merged(over: inherited))
        case (nil, _): result.fill = base.fill
        default: break
        }
        result.top = top ?? base.top
        result.bottom = bottom ?? base.bottom
        result.left = left ?? base.left
        result.right = right ?? base.right
        result.anchor = anchor ?? base.anchor
        result.paddingLeft = paddingLeft ?? base.paddingLeft
        result.paddingTop = paddingTop ?? base.paddingTop
        result.paddingRight = paddingRight ?? base.paddingRight
        result.paddingBottom = paddingBottom ?? base.paddingBottom
        result.isTurnedOrCrossed = isTurnedOrCrossed ?? base.isTurnedOrCrossed
        return result
    }

    /// `style:table-cell-properties`, holding a `style:background-image` when the cell shows a picture.
    func write(to xml: inout XMLWriter) {
        xml.raw("<style:table-cell-properties")
        switch anchor {
        case .top?: xml.raw(" style:vertical-align=\"top\"")
        case .middle?: xml.raw(" style:vertical-align=\"middle\"")
        case .bottom?: xml.raw(" style:vertical-align=\"bottom\"")
        case nil: break
        }
        switch fill {
        case .color(let rgb)?: xml.raw(" fo:background-color=\"\(rgb.map(ODFFormat.color) ?? "transparent")\"")
        case .image?: xml.raw(" fo:background-color=\"transparent\"")
        case .graphic?, nil: break
        }
        for (name, border) in [("fo:border-top", top), ("fo:border-bottom", bottom), ("fo:border-left", left), ("fo:border-right", right)] {
            if let border { xml.attribute(name, border.text) }
        }
        if let paddingLeft { xml.raw(" fo:padding-left=\"\(ODFFormat.pt(min(max(0, paddingLeft), 10_000)))\"") }
        if let paddingTop { xml.raw(" fo:padding-top=\"\(ODFFormat.pt(min(max(0, paddingTop), 10_000)))\"") }
        if let paddingRight { xml.raw(" fo:padding-right=\"\(ODFFormat.pt(min(max(0, paddingRight), 10_000)))\"") }
        if let paddingBottom { xml.raw(" fo:padding-bottom=\"\(ODFFormat.pt(min(max(0, paddingBottom), 10_000)))\"") }
        if case .image(let href, let repeatMode)? = fill {
            xml.raw("><style:background-image")
            if let repeatMode, ["no-repeat", "repeat", "stretch"].contains(repeatMode) { xml.raw(" style:repeat=\"\(repeatMode)\"") }
            xml.raw(" xlink:type=\"simple\"")
            xml.attribute("xlink:href", href)
            xml.raw(" xlink:actuate=\"onLoad\"/></style:table-cell-properties>")
        } else {
            xml.raw("/>")
        }
    }
}

// MARK: - Writing

extension ODPContentWriter {
    /// The style of a table's or chart's frame: its theme's style for other text, with no fill or line of its own, so
    /// the frame itself draws nothing.
    static func objectFrameStyle(master: String) -> ODFStyle {
        var style = ODFStyle(family: "graphic", parent: master + "-other")
        style.graphic.fill = "none"
        style.graphic.stroke = "none"
        return style
    }

    /// How a cell's text is formatted, as PuggleSlides lays tables out: the cell's own list style over the theme's style
    /// for other text, as a table has no placeholder to inherit from. The cell's padding and alignment are its own, so its
    /// text body's are left out (and with them any shrink-to-fit scale).
    static func cellTextStyle(_ cell: TableCell, theme: Theme, defaultTextStyle: ListStyle) -> ElementStyle {
        var text = cell.text
        text.properties = .empty
        return ElementStyle(element: SlideElement(placement: nil, content: .shape(Shape(text: text))), parents: [], theme: theme,
                            defaultTextStyle: defaultTextStyle)
    }

    /// A table as LibreOffice Impress writes one: a frame holding `table:table`, a style per column (its width), per row
    /// (its height) and per cell. Each cell's style states all it shows: its fill, its four borders (taken from the
    /// table's shared edges, so neighbors agree), padding, alignment, and the character formatting its text starts from,
    /// so the cell reads the same whatever an app gives cells by default. Merged cells span rows and columns and cover the
    /// cells beneath them, which keep their own styles.
    func table(_ element: SlideElement, _ original: Table, page: Page, into xml: inout XMLWriter) {
        var table = original
        table.normalize()
        guard table.rowCount > 0, table.columnCount > 0 else { return }
        var placement = Self.standardized(page.style(element).placement)
        // Tables don't flip.
        placement.flipHorizontal = false
        placement.flipVertical = false
        let frameStyle = Self.objectFrameStyle(master: document.themeMasterName(page.themeIndex))
        xml.raw("<draw:frame")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute("draw:style-name", page.styles.name(frameStyle, kind: "gr"))
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        Self.geometry(placement, into: &xml)
        xml.raw("><table:table>")
        for width in table.columnWidths {
            var column = ODFStyle(family: "table-column")
            column.columnWidth = width.isFinite ? width : 72
            xml.raw("<table:table-column table:style-name=\"\(page.styles.name(column, kind: "co"))\"/>")
        }
        let colors = page.theme.colors
        for row in 0..<table.rowCount {
            var rowStyle = ODFStyle(family: "table-row")
            rowStyle.rowHeight = table.rowHeights[row].isFinite ? table.rowHeights[row] : 20
            xml.raw("<table:table-row table:style-name=\"\(page.styles.name(rowStyle, kind: "ro"))\">")
            for column in 0..<table.columnCount {
                let cell = table.cells[row][column]
                let textStyle = Self.cellTextStyle(cell, theme: page.theme, defaultTextStyle: document.presentation.defaultTextStyle)
                var own = ODFStyle(family: "table-cell")
                own.cell = cellProperties(table, row: row, column: column, colors: colors)
                own.text = ODPDocumentWriter.properties(ODFTextValues(textStyle.resolve(textStyle.levelStyle(0).character)))
                document.use(own.text)
                let styleName = page.styles.name(own, kind: "ce")
                if cell.isCovered {
                    xml.raw("<table:covered-table-cell table:style-name=\"\(styleName)\"/>")
                    continue
                }
                xml.raw("<table:table-cell table:style-name=\"\(styleName)\"")
                if cell.columnSpan > 1 { xml.raw(" table:number-columns-spanned=\"\(cell.columnSpan)\"") }
                if cell.rowSpan > 1 { xml.raw(" table:number-rows-spanned=\"\(cell.rowSpan)\"") }
                guard !Self.isBlank(cell.text) else {
                    xml.raw("/>")
                    continue
                }
                xml.raw(">")
                var textBase = frameStyle
                textBase.text = own.text
                let baseline = ODFFrameBaseline(sheet: document.sheet, own: textBase, outlineMaster: nil)
                paragraphs(cell.text, style: textStyle, baseline: baseline, page: page, paragraphIDs: [], into: &xml)
                xml.raw("</table:table-cell>")
            }
            xml.raw("</table:table-row>")
        }
        xml.raw("</table:table>")
        altText(element, into: &xml)
        xml.raw("</draw:frame>")
    }

    /// A cell's look as a style states it. A merged cell's borders are the edges of the whole merged area along its first
    /// row and column; the cells it covers state their own edges.
    private func cellProperties(_ table: Table, row: Int, column: Int, colors: ColorScheme) -> ODFCellProperties {
        let cell = table.cells[row][column]
        var result = ODFCellProperties()
        result.fill = cellFill(cell.fill, colors: colors)
        result.anchor = cell.anchor
        result.paddingLeft = cell.insets.left.isFinite ? cell.insets.left : 0
        result.paddingTop = cell.insets.top.isFinite ? cell.insets.top : 0
        result.paddingRight = cell.insets.right.isFinite ? cell.insets.right : 0
        result.paddingBottom = cell.insets.bottom.isFinite ? cell.insets.bottom : 0
        let lastRow = min(row + (cell.isCovered ? 1 : cell.rowSpan), table.rowCount)
        let lastColumn = min(column + (cell.isCovered ? 1 : cell.columnSpan), table.columnCount)
        result.top = ODFBorder(table.horizontalBorders[row][column], colors: colors)
        result.bottom = ODFBorder(table.horizontalBorders[lastRow][column], colors: colors)
        result.left = ODFBorder(table.verticalBorders[row][column], colors: colors)
        result.right = ODFBorder(table.verticalBorders[row][lastColumn], colors: colors)
        return result
    }

    /// A cell's fill as a cell background: a color, transparent, or a picture. Cells have no gradients in ODF, so a gradient
    /// is its middle color; a nearly invisible color is transparent.
    private func cellFill(_ fill: Fill, colors: ColorScheme) -> ODFCellFill {
        switch fill {
        case .none:
            return .color(nil)
        case .solid(let color):
            let resolved = color.resolved(colors)
            return .color(resolved.alpha <= 0.01 ? nil : resolved.rgb)
        case .gradient(let gradient):
            return .color(Self.middleColor(gradient, colors: colors))
        case .picture(let picture):
            guard let path = document.mediaPath(picture.mediaID) else { return .color(nil) }
            return .image(href: path, repeatMode: picture.stretches ? "stretch" : "repeat")
        }
    }

    /// The color halfway along a gradient.
    static func middleColor(_ gradient: GradientFill, colors: ColorScheme) -> RGBColor? {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        guard let first = stops.first else { return nil }
        var before = first, after = first
        for stop in stops {
            if stop.position <= 0.5 { before = stop }
            if stop.position >= 0.5 {
                after = stop
                break
            }
            after = stop
        }
        let a = before.color.resolved(colors), b = after.color.resolved(colors)
        let span = after.position - before.position
        let t = span > 0.0001 ? min(max((0.5 - before.position) / span, 0), 1) : 0
        return RGBColor(unitRed: a.red + (b.red - a.red) * t, unitGreen: a.green + (b.green - a.green) * t, unitBlue: a.blue + (b.blue - a.blue) * t)
    }
}

// MARK: - Reading

extension ODPElementReader {
    /// Tables larger than this are cut down, with a warning: far past what any slide shows, and enough to stop a damaged
    /// file's repeat counts from making millions of cells.
    static let maxTableSide = 200
    static let maxTableCells = 10_000

    /// One cell's four borders as its styles state them, before they're shared with its neighbors.
    struct CellSides {
        var top: ODFBorder?
        var bottom: ODFBorder?
        var left: ODFBorder?
        var right: ODFBorder?
    }

    /// A frame's `table:table` as a table element; nil, with a warning, when it has no cells.
    func tableElement(_ frame: ODFNode, table node: ODFNode, placement: Placement, ids: IDs) -> SlideElement? {
        var placement = placement
        placement.flipHorizontal = false
        placement.flipVertical = false
        let frameStyle = frameStyle(frame, className: nil).own
        guard let table = table(node, frameStyle: frameStyle, size: placement.frame.size, element: ids.target) else {
            document.warnings.insert(.tables)
            return nil
        }
        return SlideElement(id: ids.own, name: frame["draw:name"] ?? "", placement: placement, content: .table(table))
    }

    private struct ReadRow {
        var style: String?
        var defaultCellStyle: String?
        var cells: [(node: ODFNode, covered: Bool)]
    }

    /// Reads a table: its columns' widths and rows' heights from their styles (sharing out the frame's size where a style
    /// says nothing), and each cell's look from its own style over what its table design gives that part of the table.
    func table(_ node: ODFNode, frameStyle: ODFStyle, size: SlideSize, element: UUID) -> Table? {
        var columns: [(style: String?, defaultCellStyle: String?)] = []
        var rows: [ReadRow] = []
        var truncated = false
        func collect(_ parent: ODFNode, depth: Int) {
            guard depth < 8 else { return }
            for child in parent.elements {
                switch child.name {
                case "table:table-column":
                    let repeated = max(ODFValue.int(child["table:number-columns-repeated"]) ?? 1, 1)
                    let count = min(repeated, Self.maxTableSide - columns.count)
                    if count < repeated { truncated = true }
                    for _ in 0..<max(count, 0) { columns.append((child["table:style-name"], child["table:default-cell-style-name"])) }
                case "table:table-row":
                    var cells: [(ODFNode, Bool)] = []
                    for cell in child.elements where cell.name == "table:table-cell" || cell.name == "table:covered-table-cell" {
                        let repeated = max(ODFValue.int(cell["table:number-columns-repeated"]) ?? 1, 1)
                        let count = min(repeated, Self.maxTableSide - cells.count)
                        if count < repeated { truncated = true }
                        for _ in 0..<max(count, 0) { cells.append((cell, cell.name == "table:covered-table-cell")) }
                    }
                    let repeated = max(ODFValue.int(child["table:number-rows-repeated"]) ?? 1, 1)
                    let count = min(repeated, Self.maxTableSide - rows.count)
                    if count < repeated { truncated = true }
                    for _ in 0..<max(count, 0) {
                        rows.append(ReadRow(style: child["table:style-name"], defaultCellStyle: child["table:default-cell-style-name"], cells: cells))
                    }
                case "table:table-columns", "table:table-header-columns", "table:table-column-group", "table:table-rows",
                     "table:table-header-rows", "table:table-row-group":
                    collect(child, depth: depth + 1)
                default:
                    continue
                }
            }
        }
        collect(node, depth: 0)
        let columnCount = max(columns.count, rows.map(\.cells.count).max() ?? 0)
        guard !rows.isEmpty, columnCount > 0 else { return nil }
        if rows.count * columnCount > Self.maxTableCells {
            rows = Array(rows.prefix(max(1, Self.maxTableCells / columnCount)))
            truncated = true
        }
        if truncated { document.warnings.insert(.tables) }
        let rowCount = rows.count

        // Sizes: what styles say, with the rest of the frame shared out among the columns and rows they don't size.
        let sheet = self.sheet
        func shared(_ sizes: [Double?], total: Double) -> [Double] {
            let known = sizes.compactMap { $0 }.reduce(0, +)
            let missing = sizes.filter { $0 == nil }.count
            let share = missing == 0 ? 0 : total > known + 1 ? (total - known) / Double(missing) : total > 0 ? total / Double(sizes.count) : 36
            return sizes.map { min(max($0 ?? share, 1), 100_000) }
        }
        let widths = shared((0..<columnCount).map { index in
            index < columns.count ? columns[index].style.flatMap { sheet.resolved("table-column", $0).columnWidth } : nil
        }, total: size.width)
        let heights = shared(rows.map { row in row.style.flatMap { sheet.resolved("table-row", $0).rowHeight } }, total: size.height)

        // The table design, and which of its parts each cell is, as LibreOffice picks them: the first or last row, then
        // the first or last column, then the banded rows and columns, then the body.
        let template = node["table:template-name"].flatMap { document.commonSheet.tableTemplate($0) }
        func uses(_ part: String) -> Bool { ODFValue.bool(node["table:use-\(part)-styles"]) ?? false }
        let firstRow = uses("first-row"), lastRow = uses("last-row"), firstColumn = uses("first-column"), lastColumn = uses("last-column")
        let bandedRows = uses("banding-rows"), bandedColumns = uses("banding-columns")
        func templateStyle(row: Int, column: Int) -> String? {
            guard let template else { return nil }
            var name: String?
            if firstRow, row == 0 {
                name = template["first-row"]
            } else if lastRow, row == rowCount - 1 {
                name = template["last-row"]
            }
            if name == nil {
                if firstColumn, column == 0 {
                    name = template["first-column"]
                } else if lastColumn, column == columnCount - 1 {
                    name = template["last-column"]
                }
            }
            if name == nil, bandedRows { name = template[row % 2 == 0 ? "even-rows" : "odd-rows"] }
            if name == nil, bandedColumns { name = template[column % 2 == 0 ? "even-columns" : "odd-columns"] }
            return name ?? template["body"]
        }
        let defaults = sheet.defaultStyle("table-cell")
        // A cell's look: its own style (or its row's or column's default cell style) over its part of the design.
        func look(row: Int, column: Int, node: ODFNode?) -> ODFStyle {
            var result = ODFStyle(family: "table-cell")
            if let name = templateStyle(row: row, column: column) { result = document.commonSheet.chained("table-cell", name) }
            let own = node?["table:style-name"] ?? rows[row].defaultCellStyle ?? (column < columns.count ? columns[column].defaultCellStyle : nil)
            if let own { result = sheet.chained("table-cell", own).merged(over: result) }
            if let defaults { result = result.merged(over: defaults) }
            return result
        }

        var cells: [[TableCell]] = []
        var looks: [[ODFStyle]] = []
        cells.reserveCapacity(rowCount)
        for row in 0..<rowCount {
            var rowCells: [TableCell] = []
            var rowLooks: [ODFStyle] = []
            for column in 0..<columnCount {
                let entry = column < rows[row].cells.count ? rows[row].cells[column] : nil
                let style = look(row: row, column: column, node: entry?.node)
                if style.cell.isTurnedOrCrossed == true { document.warnings.insert(.tables) }
                var cell = TableCell()
                cell.fill = cellFill(style.cell.fill)
                cell.anchor = style.cell.anchor ?? .top
                let defaultInsets = TableCell.defaultInsets
                cell.insets = TextInsets(left: style.cell.paddingLeft ?? defaultInsets.left, top: style.cell.paddingTop ?? defaultInsets.top,
                                         right: style.cell.paddingRight ?? defaultInsets.right, bottom: style.cell.paddingBottom ?? defaultInsets.bottom)
                if let entry, !entry.covered {
                    cell.rowSpan = min(max(ODFValue.int(entry.node["table:number-rows-spanned"]) ?? 1, 1), rowCount - row)
                    cell.columnSpan = min(max(ODFValue.int(entry.node["table:number-columns-spanned"]) ?? 1, 1), columnCount - column)
                }
                cell.text = cellText(entry.flatMap { $0.covered ? nil : $0.node }, look: style, frameStyle: frameStyle, element: element)
                rowCells.append(cell)
                rowLooks.append(style)
            }
            cells.append(rowCells)
            looks.append(rowLooks)
        }
        var table = Table(columnWidths: widths, rowHeights: heights, cells: cells)
        let sides = looks.map { $0.map { CellSides(top: $0.cell.top, bottom: $0.cell.bottom, left: $0.cell.left, right: $0.cell.right) } }
        let borders = Self.sharedBorders(table, sides: sides)
        table.horizontalBorders = borders.horizontal
        table.verticalBorders = borders.vertical
        return table
    }

    /// A cell's fill from what its style states; none when it states nothing.
    private func cellFill(_ fill: ODFCellFill?) -> Fill {
        switch fill {
        case .color(let rgb)?:
            return rgb.map { .solid(ColorRef($0)) } ?? Fill.none
        case .image(let href, let repeatMode)?:
            guard let id = document.media(at: href) else { return Fill.none }
            return .picture(PictureFill(mediaID: id, stretches: repeatMode == "stretch"))
        case .graphic(let graphic)?:
            return Self.fill(graphic, document: document, sheet: sheet)
        case nil:
            return Fill.none
        }
    }

    /// A cell's text. The character formatting its style gives (over its frame's) is, where it differs from the theme's
    /// style for other text, the cell's own list style at the first level, which its paragraphs then start from.
    private func cellText(_ node: ODFNode?, look: ODFStyle, frameStyle: ODFStyle, element: UUID) -> TextBody {
        var own = frameStyle
        own.text = look.text.merged(over: frameStyle.text)
        own.paragraph = look.paragraph.merged(over: frameStyle.paragraph)
        let baseline = ODFFrameBaseline(sheet: sheet, own: own, outlineMaster: nil)
        let probe = SlideElement(placement: nil, content: .shape(Shape(text: TextBody())))
        let plain = ElementStyle(element: probe, parents: [], theme: theme, defaultTextStyle: document.defaultTextStyle)
        let level = LevelStyle(character: Self.difference(baseline.values(level: 0).text, from: ODFTextValues(plain.resolve(plain.inheritedLevelStyle(0).character))))
        var modelTheme = theme
        modelTheme.otherStyle[0] = level.merged(over: modelTheme.otherStyle[0])
        let model = ElementStyle(element: probe, parents: [], theme: modelTheme, defaultTextStyle: document.defaultTextStyle)
        var body = node.map { text($0, baseline: baseline, model: model, element: element) } ?? TextBody()
        body.listStyle[0] = level
        return body
    }

    /// The table's shared edges from its cells' four borders, as LibreOffice draws them: the sides of the cells on either
    /// side of an edge (where they disagree, the wider line, and between equals the later cell's), and where neither of
    /// them says anything, the outline of a merged cell spanning it.
    static func sharedBorders(_ table: Table, sides: [[CellSides]]) -> (horizontal: [[Outline?]], vertical: [[Outline?]]) {
        let rows = table.rowCount, columns = table.columnCount
        var direct = (horizontal: Array(repeating: [ODFBorder?](repeating: nil, count: columns), count: rows + 1),
                      vertical: Array(repeating: [ODFBorder?](repeating: nil, count: columns + 1), count: rows))
        var spanned = direct
        func offer(_ border: ODFBorder?, _ slot: inout ODFBorder?) {
            if let border, ODFBorder.wins(border, over: slot) { slot = border }
        }
        for row in 0..<rows {
            for column in 0..<columns where row < sides.count && column < sides[row].count {
                let cell = table.cells[row][column], side = sides[row][column]
                offer(side.top, &direct.horizontal[row][column])
                offer(side.left, &direct.vertical[row][column])
                if cell.isCovered || cell.rowSpan == 1 { offer(side.bottom, &direct.horizontal[row + 1][column]) }
                if cell.isCovered || cell.columnSpan == 1 { offer(side.right, &direct.vertical[row][column + 1]) }
                guard !cell.isCovered else { continue }
                let lastRow = row + cell.rowSpan, lastColumn = column + cell.columnSpan
                for spannedColumn in column..<lastColumn {
                    offer(side.top, &spanned.horizontal[row][spannedColumn])
                    offer(side.bottom, &spanned.horizontal[lastRow][spannedColumn])
                }
                for spannedRow in row..<lastRow {
                    offer(side.left, &spanned.vertical[spannedRow][column])
                    offer(side.right, &spanned.vertical[spannedRow][lastColumn])
                }
            }
        }
        let horizontal = (0...rows).map { row in (0..<columns).map { column in (direct.horizontal[row][column] ?? spanned.horizontal[row][column])?.outline } }
        let vertical = (0..<rows).map { row in (0...columns).map { column in (direct.vertical[row][column] ?? spanned.vertical[row][column])?.outline } }
        return (horizontal, vertical)
    }
}
