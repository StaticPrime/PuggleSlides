import Foundation
import Testing
@testable import PuggleSlidesKit

/// Tables: written with every cell's look stated and no style, read back exactly; PowerPoint's styled tables read
/// into the same explicit look.
struct PPTXTableTests {
    typealias Package = PPTXTestPackage

    /// A blank slide holding `elements`.
    static func deck(_ elements: [SlideElement]) -> Presentation {
        var presentation = Presentation.makeDefault()
        var slide = presentation.makeSlide(layoutID: presentation.themes[0].layout(kind: .blank)!.id)
        slide.elements = elements
        presentation.slides = [slide]
        return presentation
    }

    static func tc(_ text: String, attributes: String = "", properties: String = "<a:tcPr/>") -> String {
        let paragraph = text.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : "<a:p><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(text)</a:t></a:r></a:p>"
        return "<a:tc\(attributes)><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraph)</a:txBody>\(properties)</a:tc>"
    }

    /// A table as PowerPoint writes one: `rows` of cell markup, columns of 160 pt, rows of 29.2 pt.
    static func tbl(_ rows: [[String]], properties: String) -> String {
        let columns = rows.map(\.count).max() ?? 0
        return "<a:tbl>\(properties)<a:tblGrid>" + String(repeating: "<a:gridCol w=\"2032000\"/>", count: columns) + "</a:tblGrid>"
            + rows.map { "<a:tr h=\"370840\">" + $0.joined() + "</a:tr>" }.joined() + "</a:tbl>"
    }

    static func package(_ tables: [String], styles: String? = nil) -> Package {
        var package = Package()
        package.tableStyles = styles
        let frames = tables.enumerated().map { index, table in
            Package.graphicFrame(4 + index, "Table \(index + 3)", y: index * 2_000_000, uri: Package.tableURI, content: table)
        }
        package.slides = [Package.Slide(xml: Package.slide(frames.joined()))]
        return package
    }

    // MARK: Writing

    @Test func tablesRoundTrip() throws {
        let original = PPTXSamples.objects()
        let file = try PPTXRoundTripTests.roundTrip(original)
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        // Writing what was read changes nothing more.
        let again = try PPTXRoundTripTests.roundTrip(file.presentation).presentation
        #expect(PPTXCanonical.difference(file.presentation, again) == nil)
        let tables = file.presentation.slides[ChartKind.allCases.count].elements.compactMap(\.table)
        #expect(tables.count == 3)
        #expect(tables[0].cells[2][1].rowSpan == 2 && tables[0].cells[2][1].columnSpan == 2 && tables[0].cells[3][2].isCovered)
    }

    @Test func tablesAreWrittenAsPowerPointWritesThem() throws {
        var table = Table.make(rows: 3, columns: 3, width: 300)
        table.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1))
        table.cells[0][0].text.paragraphs = [TextParagraph("Merged")]
        table.cells[0][2].anchor = .middle
        table.cells[0][2].insets = TextInsets(left: 7.2, top: 3.6, right: 10, bottom: 3.6)
        table.cells[2][2].fill = .solid(ColorRef(theme: .accent1))
        table.horizontalBorders[3][2] = nil
        table.verticalBorders[2][3] = Outline(fill: .solid(.black), width: 2, dash: .dash, head: .fillArrow)
        let element = PPTXSamples.table("Grid", at: SlidePoint(x: 100, y: 50), table, title: "Grid", description: "A grid")
        let slide = try #require(try Package.writtenParts(Self.deck([element]))["ppt/slides/slide1.xml"])
        // A graphic frame with locks against grouping, the table's own size, and no style or style options.
        #expect(slide.contains("<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"2\" name=\"Grid\" descr=\"A grid\" title=\"Grid\"/>"
            + "<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"))
        #expect(slide.contains("<p:xfrm><a:off x=\"1270000\" y=\"635000\"/><a:ext cx=\"3810000\" cy=\"914400\"/></p:xfrm>"))
        #expect(slide.contains("<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr/><a:tblGrid>"
            + "<a:gridCol w=\"1270000\"/><a:gridCol w=\"1270000\"/><a:gridCol w=\"1270000\"/></a:tblGrid><a:tr h=\"304800\">"))
        #expect(!slide.contains("tableStyleId"))
        // Merges as PowerPoint writes them: spans on the top-left cell, repeated along its row and column.
        let cells = slide.matches(of: /<a:tc((?: [^>]*)?)>/).map { String($0.1) }
        #expect(cells.count == 9)
        #expect(cells[0] == " rowSpan=\"2\" gridSpan=\"2\"")
        #expect(cells[1] == " rowSpan=\"2\" hMerge=\"1\"")
        #expect(cells[2] == "")
        #expect(cells[3] == " gridSpan=\"2\" vMerge=\"1\"")
        #expect(cells[4] == " hMerge=\"1\" vMerge=\"1\"")
        // Margins only where they differ, the anchor, every border (none as no fill), then the fill.
        #expect(slide.contains("<a:tcPr marR=\"127000\" anchor=\"ctr\"><a:lnL w=\"9525\">"))
        #expect(slide.contains("<a:lnB><a:noFill/></a:lnB><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill></a:tcPr>"))
        // Borders keep their dash but not line ends.
        #expect(slide.contains("<a:lnR w=\"25400\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:prstDash val=\"dash\"/></a:lnR>"))
        #expect(!slide.contains("headEnd"))
        let read = try PPTXTestPackage.read(try PresentationIO.write(Self.deck([element]), format: .pptx)).presentation
        #expect(read.slides[0].elements[0].altTitle == "Grid" && read.slides[0].elements[0].altDescription == "A grid")
    }

    @Test func rowsAreWrittenAsTallAsTheirText() throws {
        var table = Table.make(rows: 2, columns: 2, width: 120)
        table.cells[0][0].text.paragraphs = [TextParagraph("A cell whose text wraps onto several lines in its narrow column")]
        table.cells[1][1].text.paragraphs = [TextParagraph("Fits")]
        let element = PPTXSamples.table("Tall", at: SlidePoint(x: 40, y: 40), table)
        let file = try PPTXRoundTripTests.roundTrip(Self.deck([element]))
        let read = try #require(file.presentation.slides[0].elements[0].table)
        // The first row grows to its text, as it shows; the second keeps its height.
        #expect(read.rowHeights[0] > 70)
        #expect(read.rowHeights[1] == table.rowHeights[1])
        #expect(abs(try #require(file.presentation.slides[0].elements[0].placement).frame.height - read.rowHeights.reduce(0, +)) < 0.001)
        // Rows that fit their text are then written as they are.
        let again = try PPTXRoundTripTests.roundTrip(file.presentation).presentation
        #expect(again.slides[0].elements[0].table?.rowHeights == read.rowHeights)
        // Text in a merged block stretches the block's last row.
        var merged = Table.make(rows: 3, columns: 1, width: 60)
        merged.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 0))
        merged.cells[0][0].text.paragraphs = [TextParagraph("Merged text that needs four or five lines here")]
        let block = try PPTXRoundTripTests.roundTrip(Self.deck([PPTXSamples.table("Block", at: .zero, merged)])).presentation
        let heights = try #require(block.slides[0].elements[0].table?.rowHeights)
        #expect(heights[0] == merged.rowHeights[0] && heights[1] > merged.rowHeights[1] && heights[2] == merged.rowHeights[2])
    }

    // MARK: Reading styled tables

    /// Medium Style 2 – Accent 1 with a header row and banded rows; the part doesn't define it, as PowerPoint leaves it out.
    static func defaultStylePackage() -> Package {
        let rows = (0..<4).map { row in (0..<2).map { column in Self.tc(row == 0 ? "Head \(column)" : "\(row),\(column)") } }
        let table = Self.tbl(rows, properties: "<a:tblPr firstRow=\"1\" bandRow=\"1\"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>")
        return Self.package([table], styles: "")
    }

    @Test func powerPointsDefaultStyleBecomesExplicit() throws {
        let file = try PPTXReadTests.read(Self.defaultStylePackage())
        #expect(file.warnings.isEmpty)
        let read = try #require(file.presentation.slides[0].elements.first?.table)
        #expect(read.columnWidths == [160, 160])
        #expect(read.rowHeights == [29.2, 29.2, 29.2, 29.2])
        let accent = ColorRef(theme: .accent1)
        #expect(read.cells[0].allSatisfy { $0.fill == .solid(accent) })
        // Banded rows start below the header: light, lighter, light.
        #expect(read.cells[1][0].fill == .solid(ColorRef(.theme(.accent1), tint: 0.4)))
        #expect(read.cells[2][1].fill == .solid(ColorRef(.theme(.accent1), tint: 0.2)))
        #expect(read.cells[3][0].fill == .solid(ColorRef(.theme(.accent1), tint: 0.4)))
        // Header text is light and bold in the body font; the rest dark.
        let header = read.cells[0][0].text.listStyle[0].character
        #expect(header.color == ColorRef(theme: .light1) && header.bold == true && header.fontFamily == "+mn-lt")
        #expect(read.cells[1][0].text.listStyle[0].character.color == ColorRef(theme: .dark1))
        #expect(read.cells[1][0].text.listStyle[0].character.bold == nil)
        #expect(read.cells[0][0].text.paragraphs[0].runs[0].style == .empty)
        // White lines everywhere, a thick one under the header.
        let thin = Outline.solid(ColorRef(theme: .light1), width: 1), thick = Outline.solid(ColorRef(theme: .light1), width: 3)
        #expect(read.horizontalBorders[0] == [thin, thin])
        #expect(read.horizontalBorders[1] == [thick, thick])
        #expect(read.horizontalBorders[2] == [thin, thin] && read.horizontalBorders[4] == [thin, thin])
        #expect(read.verticalBorders.allSatisfy { $0 == [thin, thin, thin] })
        // As it shows: white bold header text on the accent.
        let slide = file.presentation.slides[0]
        let resolved = file.presentation.style(for: slide.elements[0], on: slide).resolvedParagraphs(read.cells[0][1].text)
        #expect(resolved[0].runs[0].style.color.rgb == .white && resolved[0].runs[0].style.bold)
    }

    /// A style of every part (a background, fills from the theme, lines by reference, banded columns, a last row, a first
    /// column and a corner cell), on a plain table and on one whose cells have looks of their own.
    static func customStylePackage() -> Package {
        let line = { (color: String, width: Int) in "<a:ln w=\"\(width)\"><a:solidFill><a:schemeClr val=\"\(color)\"/></a:solidFill></a:ln>" }
        let style = "<a:tblStyle styleId=\"{11111111-2222-3333-4444-555555555555}\" styleName=\"Custom\">"
            + "<a:tblBg><a:fillRef idx=\"1\"><a:schemeClr val=\"accent6\"/></a:fillRef></a:tblBg>"
            + "<a:wholeTbl><a:tcTxStyle i=\"on\"><a:font><a:latin typeface=\"Georgia\"/></a:font><a:srgbClr val=\"112233\"/></a:tcTxStyle>"
            + "<a:tcStyle><a:tcBdr><a:left>\(line("accent2", 25400))</a:left><a:right>\(line("accent2", 25400))</a:right>"
            + "<a:top><a:lnRef idx=\"2\"><a:schemeClr val=\"accent3\"/></a:lnRef></a:top><a:bottom>\(line("accent2", 25400))</a:bottom>"
            + "<a:insideH>\(line("accent4", 12700))</a:insideH><a:insideV><a:ln><a:noFill/></a:ln></a:insideV></a:tcBdr></a:tcStyle></a:wholeTbl>"
            + "<a:band1V><a:tcStyle><a:fill><a:solidFill><a:srgbClr val=\"EEEEEE\"/></a:solidFill></a:fill></a:tcStyle></a:band1V>"
            + "<a:firstCol><a:tcTxStyle b=\"on\"/><a:tcStyle><a:tcBdr><a:right>\(line("accent5", 38100))</a:right></a:tcBdr></a:tcStyle></a:firstCol>"
            + "<a:lastRow><a:tcTxStyle b=\"off\" i=\"off\"><a:fontRef idx=\"major\"><a:schemeClr val=\"accent1\"/></a:fontRef></a:tcTxStyle>"
            + "<a:tcStyle><a:fill><a:solidFill><a:schemeClr val=\"accent2\"/></a:solidFill></a:fill></a:tcStyle></a:lastRow>"
            + "<a:swCell><a:tcStyle><a:fill><a:noFill/></a:fill></a:tcStyle></a:swCell></a:tblStyle>"
        let rows = (0..<3).map { row in (0..<3).map { column in Self.tc("\(row)\(column)") } }
        let options = "<a:tblPr lastRow=\"1\" firstCol=\"1\" bandCol=\"1\"><a:tableStyleId>{11111111-2222-3333-4444-555555555555}</a:tableStyleId></a:tblPr>"
        // The same table with cells of its own look: a fill, a border on one side only, and padding.
        var overridden = rows
        overridden[0][1] = Self.tc("own", properties: "<a:tcPr marL=\"0\" anchor=\"b\"><a:lnR w=\"50800\"><a:solidFill><a:srgbClr val=\"FF0000\"/>"
            + "</a:solidFill></a:lnR><a:lnB><a:noFill/></a:lnB><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill></a:tcPr>")
        overridden[1][1] = Self.tc("no fill", properties: "<a:tcPr><a:noFill/></a:tcPr>")
        overridden[2][2] = Self.tc("width only", properties: "<a:tcPr><a:lnT w=\"63500\"/></a:tcPr>")
        return Self.package([Self.tbl(rows, properties: options), Self.tbl(overridden, properties: options)], styles: style)
    }

    @Test func stylesDefinedInThePackageApplyPartByPart() throws {
        let file = try PPTXReadTests.read(Self.customStylePackage())
        #expect(file.warnings.isEmpty)
        let tables = file.presentation.slides[0].elements.compactMap(\.table)
        let plain = tables[0], own = tables[1]

        // Banded columns count from the column after the first; cells without a fill show the background.
        let background = Fill.solid(ColorRef(theme: .accent6))
        let band = Fill.solid(ColorRef(RGBColor(red: 0xEE, green: 0xEE, blue: 0xEE)))
        #expect(plain.cells[0].map(\.fill) == [background, band, background])
        #expect(plain.cells[2].map(\.fill) == [background, .solid(ColorRef(theme: .accent2)), .solid(ColorRef(theme: .accent2))])
        // Text: Georgia italic in a set color, bold in the first column, the last row in the heading font, upright.
        let body = plain.cells[0][1].text.listStyle[0].character
        #expect(body == CharacterStyle(fontFamily: "Georgia", italic: true, color: ColorRef(RGBColor(red: 0x11, green: 0x22, blue: 0x33))))
        #expect(plain.cells[1][0].text.listStyle[4].character.bold == true)
        let last = plain.cells[2][2].text.listStyle[0].character
        #expect(last == CharacterStyle(fontFamily: "+mj-lt", bold: false, italic: false, color: ColorRef(theme: .accent1)))
        #expect(plain.cells[2][0].text.listStyle[0].character.bold == false)
        // Lines: the theme's second line style in accent 3 along the top, inner rows in accent 4, none between columns
        // except the first column's own right line, accent 2 round the outside.
        let themeLine = Outline.solid(ColorRef(theme: .accent3), width: 2)
        #expect(plain.horizontalBorders[0] == [themeLine, themeLine, themeLine])
        #expect(plain.horizontalBorders[1] == Array(repeating: Outline.solid(ColorRef(theme: .accent4), width: 1), count: 3))
        #expect(plain.horizontalBorders[3] == Array(repeating: Outline.solid(ColorRef(theme: .accent2), width: 2), count: 3))
        #expect(plain.verticalBorders[1] == [.solid(ColorRef(theme: .accent2), width: 2), .solid(ColorRef(theme: .accent5), width: 3), nil,
                                             .solid(ColorRef(theme: .accent2), width: 2)])

        // A cell's own look wins over its style's: its fill, padding and anchor, and its lines over its neighbors' style lines.
        #expect(own.cells[0][1].fill == .solid(ColorRef(RGBColor(red: 0, green: 255, blue: 0))))
        #expect(own.cells[0][1].insets.left == 0 && own.cells[0][1].anchor == .bottom)
        #expect(own.verticalBorders[0][2] == .solid(ColorRef(RGBColor(red: 255, green: 0, blue: 0)), width: 4))
        // A cell's "no line" beats the style's line on the cell below; a line with only a width takes the style's color.
        #expect(own.horizontalBorders[1][1] == nil)
        #expect(own.horizontalBorders[1][0] == .solid(ColorRef(theme: .accent4), width: 1))
        #expect(own.horizontalBorders[2][2] == .solid(ColorRef(theme: .accent4), width: 5))
        // No fill of its own shows the table's background.
        #expect(own.cells[1][1].fill == background)
    }

    @Test func tableTextFollowsAColorMapOverride() throws {
        // A slide that turns the theme dark: text the table inherits from the master is light there.
        var package = Package()
        package.textStyles = "<p:titleStyle/><p:bodyStyle/><p:otherStyle><a:lvl1pPr><a:defRPr><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:defRPr>"
            + "</a:lvl1pPr></p:otherStyle>"
        let dark = "<p:clrMapOvr><a:overrideClrMapping bg1=\"dk1\" tx1=\"lt1\" bg2=\"dk2\" tx2=\"lt2\" accent1=\"accent1\" accent2=\"accent2\" "
            + "accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/></p:clrMapOvr>"
        let frame = Package.graphicFrame(4, "Table", uri: Package.tableURI, content: Self.tbl([[Self.tc("x")]], properties: "<a:tblPr/>"))
        package.slides = [Package.Slide(xml: Package.slide(frame).replacingOccurrences(of: "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>", with: dark))]
        let presentation = try PPTXReadTests.read(package).presentation
        let slide = presentation.slides[0]
        let table = try #require(slide.elements[0].table)
        #expect(table.cells[0][0].text.listStyle[0].character.color == ColorRef(theme: .light1))
        let resolved = presentation.style(for: slide.elements[0], on: slide).resolvedParagraphs(table.cells[0][0].text)
        #expect(resolved[0].runs[0].style.color.rgb == .white)
    }

    @Test func tablesInGroupsAndChoicesRead() throws {
        let rows = [[Self.tc("a"), Self.tc("b")]]
        let table = Self.tbl(rows, properties: "<a:tblPr/>")
        let frame = Package.graphicFrame(5, "Grouped", x: 0, y: 0, cx: 4_064_000, cy: 370_840, uri: Package.tableURI, content: table)
        // A group showing its children at half their size.
        let group = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"4\" name=\"Group\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm>"
            + "<a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"2032000\" cy=\"185420\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"4064000\" cy=\"370840\"/>"
            + "</a:xfrm></p:grpSpPr>\(frame)\(PPTXReadTests.sp(6, "Box", xfrm: "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"100\" cy=\"100\"/></a:xfrm>"))</p:grpSp>"
        let choice = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"a14\">"
            + Package.graphicFrame(7, "Chosen", uri: Package.tableURI, content: table) + "</mc:Choice><mc:Fallback>"
            + PPTXReadTests.sp(8, "Fallback picture") + "</mc:Fallback></mc:AlternateContent>"
        var package = Package()
        package.slides = [Package.Slide(xml: Package.slide(group + choice))]
        let file = try PPTXReadTests.read(package)
        #expect(file.warnings.isEmpty)
        let elements = file.presentation.slides[0].elements
        #expect(elements.map(\.name) == ["Group", "Chosen"])
        let grouped = try #require(elements[0].children?.first)
        #expect(grouped.placement?.frame == SlideRect(x: 100, y: 100, width: 160, height: 14.6))
        #expect(grouped.table?.columnWidths == [80, 80])
        #expect(grouped.table?.rowHeights == [14.6])
        #expect(elements[1].table?.cells[0].map(\.text.plainText) == ["a", "b"])
    }

    @Test func tablesThatCannotBeKeptWarn() throws {
        let empty = "<a:tbl><a:tblPr/><a:tblGrid/></a:tbl>"
        let huge = "<a:tbl><a:tblPr/><a:tblGrid>" + String(repeating: "<a:gridCol w=\"1\"/>", count: 400)
            + "</a:tblGrid>" + String(repeating: "<a:tr h=\"1\"/>", count: 400) + "</a:tbl>"
        // Ragged rows and spans past the table's edge are evened out.
        let ragged = Self.tbl([[Self.tc("only", attributes: " gridSpan=\"9\" rowSpan=\"-4\"")], [Self.tc("x"), Self.tc("y"), Self.tc("z", attributes: " hMerge=\"1\"")]],
                              properties: "<a:tblPr><a:tableStyleId>{00000000-0000-0000-0000-000000000000}</a:tableStyleId></a:tblPr>")
        let file = try PPTXReadTests.read(Self.package([empty, huge, ragged]))
        #expect(file.warnings == [.tables])
        let tables = file.presentation.slides[0].elements.compactMap(\.table)
        #expect(tables.count == 1)
        let table = try #require(tables.first)
        #expect(table.columnCount == 3 && table.rowCount == 2)
        #expect(table.cells[0][0].columnSpan == 3 && table.cells[0][0].rowSpan == 1)
        #expect(table.cells[0][1].isCovered && !table.cells[1][2].isCovered)
        // An unknown style adds nothing.
        #expect(table.cells.joined().allSatisfy { $0.fill == .none && $0.text.listStyle.isEmpty })
    }
}
