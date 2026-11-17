import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct TableTests {
    private func text(_ table: Table, _ row: Int, _ column: Int) -> String { table.cells[row][column].text.plainText }

    private func filled(rows: Int, columns: Int) -> Table {
        var table = Table.make(rows: rows, columns: columns, width: Double(columns) * 100)
        for row in 0..<rows {
            for column in 0..<columns { table.cells[row][column].text = TextBody("\(row),\(column)") }
        }
        return table
    }

    @Test func newTablesHaveTheDefaultLook() {
        let table = Table.make(rows: 3, columns: 4, width: 400)
        #expect(table.rowCount == 3 && table.columnCount == 4)
        #expect(table.columnWidths == [100, 100, 100, 100])
        #expect(table.horizontalBorders.count == 4 && table.horizontalBorders.allSatisfy { $0.count == 4 && $0.allSatisfy { $0 == Table.defaultBorder } })
        #expect(table.verticalBorders.count == 3 && table.verticalBorders.allSatisfy { $0.count == 5 })
        #expect(table.cells.joined().allSatisfy { $0.fill == .none && $0.text.listStyle[0].character.fontSize == 14 })
        #expect(Table.make(rows: 50, columns: 0, width: 100).rowCount == Table.maximumSize)
    }

    @Test func insertingRowsAndColumnsKeepsTheGridsInStep() {
        var table = filled(rows: 2, columns: 2)
        table.insertRows(at: 1, count: 2)
        #expect(table.rowCount == 4 && table.cells.count == 4)
        #expect(text(table, 0, 0) == "0,0" && text(table, 1, 0) == "" && text(table, 3, 1) == "1,1")
        #expect(table.horizontalBorders.count == 5 && table.verticalBorders.count == 4)
        table.insertColumns(at: 2)
        #expect(table.columnCount == 3 && table.cells.allSatisfy { $0.count == 3 })
        #expect(table.horizontalBorders.allSatisfy { $0.count == 3 } && table.verticalBorders.allSatisfy { $0.count == 4 })
        #expect(table.width == 300)
        // New cells take the format of the cells beside them, not their text.
        table.cells[0][0].fill = .solid(ColorRef(theme: .accent1))
        table.insertColumns(at: 1)
        #expect(table.cells[0][1].fill == .solid(ColorRef(theme: .accent1)) && text(table, 0, 1) == "")
    }

    @Test func mergedCellsGrowWhenRowsGoInsideThem() {
        var table = filled(rows: 3, columns: 3)
        table.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1))
        #expect(table.cells[0][0].rowSpan == 2 && table.cells[0][0].columnSpan == 2)
        #expect(table.cells[1][1].isCovered && table.cells[0][1].isCovered && !table.cells[2][2].isCovered)
        // Merging keeps every cell's text.
        #expect(table.cells[0][0].text.paragraphs.map { $0.runs.map(\.text).joined() } == ["0,0", "0,1", "1,0", "1,1"])
        table.insertRows(at: 1)
        #expect(table.cells[0][0].rowSpan == 3 && table.cells[1][0].isCovered && table.cells[1][1].isCovered && !table.cells[1][2].isCovered)
        table.insertColumns(at: 1)
        #expect(table.cells[0][0].columnSpan == 3 && table.cells[2][1].isCovered)
        #expect(table.anchor(row: 2, column: 2) == (0, 0))
        #expect(table.anchor(row: 3, column: 3) == (3, 3))
    }

    @Test func deletingTheFirstRowOfAMergedCellMovesItDown() {
        var table = filled(rows: 4, columns: 2)
        table.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 2, lastColumn: 0))
        table.deleteRows(0...0)
        #expect(table.rowCount == 3)
        #expect(table.cells[0][0].rowSpan == 2 && !table.cells[0][0].isCovered && table.cells[1][0].isCovered)
        #expect(text(table, 0, 0).hasPrefix("0,0"))
        table.deleteRows(1...1)
        #expect(table.cells[0][0].rowSpan == 1 && !table.cells[1][0].isCovered)
        // Deleting every row isn't allowed: a table keeps at least one.
        table.deleteRows(0...5)
        #expect(table.rowCount == 2)
    }

    @Test func deletingColumnsShrinksMergedCells() {
        var table = filled(rows: 2, columns: 4)
        table.merge(TableCellRange(firstRow: 0, firstColumn: 1, lastRow: 0, lastColumn: 3))
        table.deleteColumns(2...2)
        #expect(table.columnCount == 3 && table.cells[0][1].columnSpan == 2 && table.cells[0][2].isCovered)
        #expect(table.horizontalBorders.allSatisfy { $0.count == 3 } && table.verticalBorders.allSatisfy { $0.count == 4 })
        // A range that reaches past the table only deletes what's there, and never everything.
        table.deleteColumns(1...9)
        #expect(table.columnCount == 1)
    }

    @Test func unmergeLeavesTheTextInTheFirstCell() {
        var table = filled(rows: 2, columns: 2)
        let all = TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1)
        table.merge(all)
        #expect(table.hasMergedCells(in: TableCellRange(row: 1, column: 1)))
        table.unmerge(TableCellRange(row: 1, column: 1))
        #expect(!table.hasMergedCells(in: all))
        #expect(table.visibleCells.count == 4 && text(table, 1, 1) == "" && text(table, 0, 0).contains("1,1"))
    }

    @Test func selectingAcrossAMergedCellTakesInAllOfIt() {
        var table = filled(rows: 3, columns: 3)
        table.merge(TableCellRange(firstRow: 1, firstColumn: 1, lastRow: 2, lastColumn: 2))
        #expect(table.expanded(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1))
                == TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 2, lastColumn: 2))
    }

    @Test func borderPositionsPickTheirLines() {
        var table = Table.make(rows: 3, columns: 3, width: 300)
        let middle = TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1)
        #expect(table.borderSlots(.outer, in: middle).count == 8)
        #expect(table.borderSlots(.inner, in: middle).count == 4)
        #expect(table.borderSlots(.horizontal, in: middle).count == 2)
        #expect(table.borderSlots(.all, in: middle).count == 12)
        table.updateBorders(.bottom, in: middle) { $0 = nil }
        #expect(table.horizontalBorders[2][0] == nil && table.horizontalBorders[2][1] == nil && table.horizontalBorders[2][2] != nil)
        // The line through a merged cell isn't one of its borders.
        table.merge(middle)
        #expect(table.borderSlots(.inner, in: middle).isEmpty)
        #expect(table.isInsideMergedCell(horizontal: true, row: 1, column: 0))
    }

    @Test func distributingSharesTheSpaceEqually() {
        var table = Table.make(rows: 2, columns: 3, width: 300)
        table.columnWidths = [50, 100, 150]
        table.rowHeights = [20, 40]
        table.distributeColumns()
        table.distributeRows()
        #expect(table.columnWidths == [100, 100, 100] && table.rowHeights == [30, 30])
    }

    @Test func raggedGridsAreEvenedOut() {
        var table = Table(columnWidths: [10, 10], rowHeights: [5, 5, 5], cells: [[TableCell(columnSpan: 5)]])
        #expect(table.cells.count == 3 && table.cells.allSatisfy { $0.count == 2 })
        #expect(table.cells[0][0].columnSpan == 2 && table.cells[0][1].isCovered)
        table.cells[2][1].rowSpan = 4
        table.normalize()
        #expect(table.cells[2][1].rowSpan == 1)
    }

    @Test func elementsScaleWithTheirTables() {
        var element = SlideElement(placement: Placement(frame: SlideRect(x: 10, y: 10, width: 200, height: 60)),
                                   content: .table(Table.make(rows: 2, columns: 2, width: 200)))
        element.scale(x: 2, y: 0.5)
        #expect(element.placement?.frame == SlideRect(x: 20, y: 5, width: 400, height: 30))
        #expect(element.table?.columnWidths == [200, 200])
    }
}

@Suite struct ChartModelTests {
    @Test func samplesHaveTheDefaultShape() {
        let column = Chart.sample(.column)
        #expect(column.data.series.count == 2 && column.data.labels.count == 4)
        #expect(Chart.sample(.pie).data.series.count == 1)
        #expect(column.color(ofSeries: 0) == Chart.palette[0] && column.color(ofSeries: 13) == Chart.palette[1])
        var colored = column
        colored.data.series[1].color = RGBColor(red: 1, green: 2, blue: 3)
        #expect(colored.color(ofSeries: 1) == RGBColor(red: 1, green: 2, blue: 3))
    }

    @Test func paddingEvensOutRaggedData() {
        let data = ChartData(labels: ["a"], series: [ChartSeries(name: "s", values: [1, 2, 3])]).padded()
        #expect(data.labels == ["a", "", ""] && data.series[0].values.count == 3)
    }

    @Test func recolorEndsComeFromTheScheme() {
        let colors = BuiltInThemes.simpleLight().colors
        let dark = ImageRecolor.dark(.accent1).ends(in: colors)
        #expect(dark.dark.red == 0 && dark.light == ColorRef(theme: .accent1).resolved(colors))
        #expect(ImageRecolor.presets.count == 23)
        #expect(ImageRecolor.negative.ends(in: colors).dark.red == 1)
    }
}

@Suite struct ImportAndThemeEditingTests {
    private func deck(_ theme: Theme, slides kinds: [LayoutKind]) -> Presentation {
        var presentation = Presentation(themes: [theme], defaultTextStyle: BuiltInThemes.defaultTextStyle)
        presentation.slides = kinds.map { presentation.makeSlide(layoutID: theme.layout(kind: $0)!.id) }
        return presentation
    }

    @Test func importedSlidesCanKeepTheirTheme() {
        var destination = deck(BuiltInThemes.simpleLight(), slides: [.title])
        let source = deck(BuiltInThemes.make(BuiltInThemes.designs[2], slideSize: .widescreen), slides: [.titleAndBody, .bigNumber])
        let ids = destination.insertSlides(source.slides, themes: source.themes, media: source.media, at: 1, keepingThemes: true)
        #expect(ids.count == 2 && destination.slides.count == 3 && destination.themes.count == 2)
        #expect(destination.theme(for: destination.slides[1]).name == source.themes[0].name)
        #expect(Set(destination.slides.map(\.id)).count == 3 && !source.slides.map(\.id).contains(ids[0]))
        // The same design isn't added twice, even read back with new ids.
        var again = source
        again.themes[0].id = UUID()
        destination.insertSlides(again.slides, themes: again.themes, media: [:], at: 0, keepingThemes: true)
        #expect(destination.themes.count == 2 && destination.slides.allSatisfy { destination.layout(for: $0) != nil })
    }

    @Test func importedSlidesCanMatchThisTheme() {
        var destination = deck(BuiltInThemes.simpleLight(), slides: [.title])
        var source = deck(BuiltInThemes.make(BuiltInThemes.designs[3], slideSize: .standard), slides: [.titleAndBody])
        source.slideSize = .standard
        source.slides[0].elements[0].shape?.text = TextBody("Kept")
        destination.insertSlides(source.slides, themes: source.themes, media: [:], sourceSize: .standard, at: 1, keepingThemes: false)
        #expect(destination.themes.count == 1)
        let slide = destination.slides[1]
        #expect(destination.layout(for: slide)?.kind == .titleAndBody)
        #expect(slide.elements.contains { $0.shape?.text?.plainText == "Kept" })
    }

    @Test func importingAThemeGivesItToEverySlide() {
        var destination = deck(BuiltInThemes.simpleLight(), slides: [.title, .titleAndBody])
        let theme = BuiltInThemes.make(BuiltInThemes.designs[4], slideSize: .widescreen)
        destination.importTheme(theme, media: [:])
        #expect(destination.themes.map(\.name) == [theme.name])
        #expect(destination.slides.map { destination.layout(for: $0)?.kind } == [.title, .titleAndBody])
    }

    @Test func layoutsCanBeDuplicatedRenamedAndDeleted() {
        var presentation = deck(BuiltInThemes.simpleLight(), slides: [.title])
        let theme = presentation.themes[0]
        let body = theme.layout(kind: .titleAndBody)!
        let copyID = presentation.duplicateLayout(body.id)!
        #expect(presentation.layout(id: copyID)?.name == "\(body.name) copy" && presentation.themes[0].layouts.count == theme.layouts.count + 1)
        presentation.renameLayout(copyID, to: "  Agenda ")
        #expect(presentation.layout(id: copyID)?.name == "Agenda")
        presentation.deleteLayout(theme.layout(kind: .title)!.id)
        #expect(presentation.layout(id: theme.layout(kind: .title)!.id) != nil, "a layout in use stays")
        presentation.deleteLayout(copyID)
        #expect(presentation.layout(id: copyID) == nil)
        presentation.setThemeColor(.accent1, to: RGBColor(red: 9, green: 8, blue: 7), themeID: theme.id)
        #expect(presentation.themes[0].colors[.accent1] == RGBColor(red: 9, green: 8, blue: 7))
        let placeholder = presentation.addPlaceholder(.body, toLayout: body.id)
        #expect(placeholder?.placeholder?.type == .body)
        #expect(Set(presentation.layout(id: body.id)!.elements.compactMap(\.placeholder?.index)).count
                == presentation.layout(id: body.id)!.elements.compactMap(\.placeholder?.index).count)
    }

    @Test func pageSetupScalesGuidesToo() {
        var presentation = deck(BuiltInThemes.simpleLight(), slides: [.title])
        presentation.guides = [Guide(orientation: .vertical, position: 360), Guide(orientation: .horizontal, position: 100)]
        presentation.changeSlideSize(to: .standard)
        let sx = SlideSize.standard.width / SlideSize.widescreen.width, sy = SlideSize.standard.height / SlideSize.widescreen.height
        #expect(abs(presentation.guides[0].position - 360 * sx) < 0.001 && abs(presentation.guides[1].position - 100 * sy) < 0.001)
    }

    @Test func olderCopiesStillDecode() throws {
        let picture = #"{"mediaID":"m","crop":{"left":0,"top":0,"right":0,"bottom":0},"geometry":{"preset":{"_0":"rect","adjustments":{}}}}"#
        #expect(try JSONDecoder().decode(Picture.self, from: Data(picture.utf8)).adjustments == .none)
        let shape = #"{"geometry":{"preset":{"_0":"rect","adjustments":{}}},"isTextBox":false,"isConnector":false}"#
        #expect(try JSONDecoder().decode(Shape.self, from: Data(shape.utf8)).isWordArt == false)
        var presentation = Presentation.makeDefault()
        presentation.guides = [Guide(orientation: .vertical, position: 5)]
        let data = try JSONEncoder().encode(presentation)
        #expect(try JSONDecoder().decode(Presentation.self, from: data) == presentation)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["guides"] = nil
        #expect(try JSONDecoder().decode(Presentation.self, from: JSONSerialization.data(withJSONObject: object)).guides.isEmpty)
    }
}
