#if DEBUG
import AppKit
import PuggleSlidesKit

/// Phase 3: tables, word art, charts, image tools, guides and snapping, rulers, importing, the theme builder, and
/// how all of these export.
extension SelfTest {
    /// Runs `body` with view preferences set for a test, then puts the person's own settings back.
    private static func withPreferences(_ values: [String: Bool], _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = values.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in values { defaults.set(value, forKey: key) }
        body()
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    static func addPhase3Steps(_ window: DocumentWindowController) {
        let controller = window.controller
        let canvas = window.canvas
        var slide: Slide { controller.currentSlide! }
        var tableID = UUID()
        var table: Table? { slide.element(id: tableID)?.table }
        func text(_ row: Int, _ column: Int) -> String { table?.cells[row][column].text.plainText ?? "<none>" }
        /// The middle of a table cell, in slide space.
        func cellPoint(_ row: Int, _ column: Int) -> SlidePoint {
            guard let element = slide.element(id: tableID), let (layout, placement) = canvas.tableGeometry(element) else { return SlidePoint(x: 0, y: 0) }
            let rect = layout.rect(row: row, column: column)
            return placement.slidePoint(fromShape: SlidePoint(x: rect.midX, y: rect.midY))
        }

        // Tables.
        step {
            let theme = controller.presentation.theme(for: slide)
            controller.newSlide(layoutID: theme.layout(kind: .blank)?.id)
            window.ppInsertTable(NSMenuItem().withTag(304))
            tableID = slide.elements.last?.id ?? UUID()
            check(table?.rowCount == 3 && table?.columnCount == 4, "Insert ▸ Table makes a table of the size picked", "\(String(describing: table?.rowCount))")
            check(canvas.editor?.cell?.row == 0 && canvas.editor?.cell?.column == 0, "a new table starts with its first cell ready for typing")
            type("Walks", into: window.window)
        }
        step { type("\t", into: window.window) }
        step {
            check(canvas.editor?.cell?.column == 1, "Tab moves to the next cell")
            check(text(0, 0) == "Walks", "typing fills a cell", text(0, 0))
            let height = slide.element(id: tableID)?.placement?.frame.height ?? 0
            type("One\rTwo\rThree", into: window.window)
            canvas.endEditing()
            check(table?.cells[0][1].text.paragraphs.count == 3, "Return starts a new paragraph in a cell")
            check((slide.element(id: tableID)?.placement?.frame.height ?? 0) > height + 20, "a row grows to fit its text")
            drag(from: cellPoint(1, 0), to: cellPoint(2, 1), in: window)
        }
        step {
            check(controller.tableSelection == TableCellRange(firstRow: 1, firstColumn: 0, lastRow: 2, lastColumn: 1), "dragging across cells selects them",
                  "\(String(describing: controller.tableSelection))")
            check(controller.selectionKind() == .table, "the toolbar shows table controls")
            controller.setFill(.solid(ColorRef(theme: .accent2)))
        }
        step {
            check(table?.cells[2][1].fill == .solid(ColorRef(theme: .accent2)) && table?.cells[0][0].fill == Fill.none, "Fill color fills the selected cells")
            window.ppTableCommand(NSMenuItem().withTag(MenuBuilder.TableCommand.mergeCells.rawValue))
        }
        step {
            check(table?.cells[1][0].rowSpan == 2 && table?.cells[1][0].columnSpan == 2 && table?.cells[2][1].isCovered == true, "Merge cells")
            controller.undoManager?.undo()
        }
        step {
            check(table.map { !$0.hasMergedCells(in: TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 2, lastColumn: 3)) } == true, "undo unmerges")
            controller.tableSelection = TableCellRange(firstRow: 1, firstColumn: 0, lastRow: 2, lastColumn: 1)
            controller.tableBorderPosition = .outer
            controller.setBorderWidth(3)
        }
        step {
            check(table?.horizontalBorders[1][0]?.width == 3 && table?.verticalBorders[1][2]?.width == 3 && table?.horizontalBorders[2][0]?.width == 0.75,
                  "border weight changes only the chosen borders")
            controller.tableBorderPosition = .all
            window.ppTableCommand(NSMenuItem().withTag(MenuBuilder.TableCommand.insertRowBelow.rawValue))
        }
        step {
            check(table?.rowCount == 5, "Insert row below adds as many rows as are selected", "\(table?.rowCount ?? 0)")
            controller.tableSelection = TableCellRange(row: 0, column: 3)
            window.ppTableCommand(NSMenuItem().withTag(MenuBuilder.TableCommand.deleteColumn.rawValue))
        }
        step {
            check(table?.columnCount == 3, "Delete column")
            // Dragging the border between the first two columns trades width between them.
            let widths = table?.columnWidths ?? []
            guard let element = slide.element(id: tableID), let (layout, placement) = canvas.tableGeometry(element) else { return }
            let border = placement.slidePoint(fromShape: SlidePoint(x: layout.columnX[1], y: layout.rowY[1] + 6))
            drag(from: border, to: SlidePoint(x: border.x + 30, y: border.y), in: window)
            check(abs((table?.columnWidths[0] ?? 0) - (widths.first ?? 0) - 30) < 1 && abs((table?.width ?? 0) - widths.reduce(0, +)) < 0.5,
                  "dragging a column border resizes the columns beside it", "\(table?.columnWidths ?? [])")
        }
        step {
            controller.selectElements([tableID])
            window.ppTableCommand(NSMenuItem().withTag(MenuBuilder.TableCommand.distributeColumns.rawValue))
            let widths = table?.columnWidths ?? []
            check(widths.allSatisfy { abs($0 - (widths.first ?? 0)) < 0.01 }, "Distribute columns")
            // Tab in the last cell adds a row.
            let rows = table?.rowCount ?? 0
            canvas.beginEditingCell(tableID, row: rows - 1, column: 2, at: nil)
            type("\t", into: window.window)
        }
        step {
            check(table?.rowCount == 6 && canvas.editor?.cell?.row == 5, "Tab in the last cell adds a row")
            canvas.endEditing()
            controller.selectElements([tableID])
            controller.tableSelection = TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: 1)
            key(127, to: canvas, window: window.window)
        }
        step {
            check(text(0, 0).isEmpty && text(0, 1).isEmpty && slide.element(id: tableID) != nil, "Delete clears the selected cells, not the table")
            window.ppTableCommand(NSMenuItem().withTag(MenuBuilder.TableCommand.deleteTable.rawValue))
            check(slide.element(id: tableID) == nil, "Delete table")
        }

        // Word art.
        step {
            guard let id = controller.insertWordArt("Good dogs") else { return check(false, "Insert ▸ Word art") }
            let element = slide.element(id: id)
            check(element?.isWordArt == true && controller.selectionKind() == .wordArt, "Insert ▸ Word art")
            let frame = element?.placement?.frame
            check((frame?.width ?? 0) > (frame?.height ?? 0) * 2, "word art takes the shape of its text")
            controller.setWordArtText(id, to: "Great dogs")
            controller.setFill(.solid(ColorRef(theme: .accent1)))
            check(slide.element(id: id)?.shape?.text?.plainText == "Great dogs" && slide.element(id: id)?.shape?.fill == .solid(ColorRef(theme: .accent1)),
                  "word art's text and fill change")
            controller.deleteSelectedElements()
        }

        // Charts.
        step {
            window.ppInsertChart(NSMenuItem().withTag(ChartKind.allCases.firstIndex(of: .column) ?? 0))
            guard let chart = controller.selectedChart else { return check(false, "Insert ▸ Chart") }
            check(chart.chart?.kind == .column && chart.chart?.data.series.count == 2, "Insert ▸ Chart adds a chart of sample numbers")
            controller.editChart("Chart Type") { $0.kind = .pie }
            controller.editChart("Edit Chart Data") { $0.data.series[0].values[0] = 99 }
            check(controller.selectedChart?.chart?.kind == .pie && controller.selectedChart?.chart?.data.series[0].values[0] == 99, "the chart editor changes the chart")
            window.editChart()
            check(window.state.sidebar == .chartEditor, "Edit chart opens the chart editor")
            window.closeSidebar()
            controller.deleteSelectedElements()
        }

        // Image tools.
        var pictureID = UUID()
        step {
            _ = controller.insertImage(data: SampleContent.sampleImage())
            pictureID = controller.selectedPicture?.id ?? UUID()
        }
        var cropWidth = 0.0
        step {
            let item = NSMenuItem()
            item.representedObject = "ellipse"
            window.ppMaskImage(item)
            check(slide.element(id: pictureID)?.picture?.geometry.presetName == "ellipse", "Mask image cuts the picture to a shape")
        }
        step {
            cropWidth = slide.element(id: pictureID)?.placement?.frame.width ?? 0
            window.cropImage()
            check(canvas.cropping != nil, "Crop image shows crop marks")
            guard let handle = canvas.cropHandles().first(where: { $0.u == 0 && $0.v == 1 }) else { return }
            drag(from: SlidePoint(x: handle.point.x, y: handle.point.y), to: SlidePoint(x: handle.point.x + 20, y: handle.point.y), in: window)
            key(13, to: canvas, window: window.window)
        }
        step {
            let picture = slide.element(id: pictureID)?.picture
            check(canvas.cropping == nil && abs((picture?.crop.left ?? 0) - 20 / max(cropWidth, 1)) < 0.002, "dragging a crop mark crops the picture",
                  "\(String(describing: picture?.crop))")
            controller.undoManager?.undo()
        }
        step {
            check(slide.element(id: pictureID)?.picture?.crop == ImageCrop.none, "a crop is one undo step")
            controller.setImageAdjustments("Recolor") { $0.recolor = .grayscale }
            controller.setImageAdjustments("Opacity") { $0.transparency = 0.4 }
            check(slide.element(id: pictureID)?.picture?.adjustments == ImageAdjustments(transparency: 0.4, recolor: .grayscale), "Recolor and Opacity")
            window.resetImage()
        }
        step {
            let picture = slide.element(id: pictureID)?.picture
            check(picture?.adjustments == ImageAdjustments.none && picture?.geometry == .rectangle, "Reset image")
            let before = picture?.mediaID
            check(controller.replaceSelectedImage(with: coloredPNG()), "Replace image")
            check(slide.element(id: pictureID)?.picture?.mediaID != before, "a replaced picture shows the new image")
        }

        // Guides, snapping and rulers.
        step {
            withPreferences(["PPSnapToGuides": true, "PPSnapToGrid": false, "PPShowGuides": true]) {
                controller.addGuide(.vertical, at: 200)
                check(controller.presentation.guides.count == 1, "View ▸ Guides ▸ Add vertical guide")
                let shape = controller.makeShape("rect", frame: SlideRect(x: 100, y: 100, width: 80, height: 40))
                controller.insert([shape], actionName: "Insert Shape")
                // Dropping the left edge three points from the guide snaps it there.
                drag(from: SlidePoint(x: 140, y: 120), to: SlidePoint(x: 237, y: 120), in: window)
                check(abs((slide.element(id: shape.id)?.placement?.frame.x ?? 0) - 200) < 0.01, "objects snap to guides",
                      "\(slide.element(id: shape.id)?.placement?.frame.x ?? -1)")
                // Holding Command while dragging moves freely.
                mouse(.leftMouseDown, at: SlidePoint(x: 240, y: 120), in: window)
                mouse(.leftMouseDragged, at: SlidePoint(x: 241.5, y: 120), in: window, modifiers: .command)
                mouse(.leftMouseDragged, at: SlidePoint(x: 243, y: 120), in: window, modifiers: .command)
                mouse(.leftMouseUp, at: SlidePoint(x: 243, y: 120), in: window, modifiers: .command)
                check(abs((slide.element(id: shape.id)?.placement?.frame.x ?? 0) - 203) < 0.01, "Command turns snapping off")
                controller.clearGuides()
                check(controller.presentation.guides.isEmpty, "Clear guides")
                controller.selectElements([shape.id])
                controller.deleteSelectedElements()
            }
            withPreferences(["PPShowRuler": false]) {
                window.ppShowRuler(nil)
                check(window.canvasScroll.rulersVisible, "View ▸ Show ruler")
                window.ppShowRuler(nil)
                check(!window.canvasScroll.rulersVisible, "the ruler hides again")
            }
        }

        // Importing slides and themes.
        step {
            var source = SampleContent.make()
            source.applyTheme(BuiltInThemes.make(BuiltInThemes.designs[3], slideSize: source.slideSize))
            let slides = controller.presentation.slides.count, themes = controller.presentation.themes.count
            window.importSlides([0, 1], from: source, keepingTheme: true)
            check(controller.presentation.slides.count == slides + 2 && controller.presentation.themes.count == themes + 1,
                  "Import slides keeps their theme when asked")
            check(controller.presentation.theme(for: slide).name == BuiltInThemes.designs[3].name, "imported slides show their own theme")
            controller.undoManager?.undo()
            window.importSlides([1], from: source, keepingTheme: false)
            check(controller.presentation.themes.count == themes && controller.presentation.layout(for: slide)?.kind == .titleAndBody,
                  "imported slides can take this presentation's theme")
            controller.undoManager?.undo()
        }

        // The theme builder.
        step {
            let accent = RGBColor(red: 1, green: 2, blue: 3)
            window.ppEditTheme(nil)
            let theme = window.presentationDocument?.presentation.themes.first
            check(controller.isThemeBuilderOpen && controller.presentation.slides.count == (theme?.layouts.count ?? 0) + 1,
                  "Edit theme shows the theme and its layouts", "\(controller.presentation.slides.count)")
            window.refreshState()
            check(window.state.themeBuilderTitle?.hasPrefix("Layout:") == true, "the builder opens on the slide's layout",
                  window.state.themeBuilderTitle ?? "no title")
            controller.renameBuilderPage(to: "Agenda")
            controller.setBuilderThemeColor(.accent1, to: accent)
            check(window.presentationDocument?.presentation.themes.first?.colors[.accent1] == accent, "theme changes reach the document right away")
            controller.insertBuilderPlaceholder(.subtitle)
            check(slide.elements.contains { $0.placeholder?.type == .subtitle }, "Insert ▸ Placeholder on a layout")
            controller.duplicateBuilderLayout()
            check(controller.presentation.slides.count == (theme?.layouts.count ?? 0) + 2, "Duplicate layout")
            controller.deleteBuilderLayout()
            check(controller.presentation.slides.count == (theme?.layouts.count ?? 0) + 1, "an unused layout can be deleted")
            window.closeThemeBuilder()
        }
        step {
            let real = controller.presentation
            check(!controller.isThemeBuilderOpen && real.themes[0].layouts.contains { $0.name == "Agenda" }, "closing the builder keeps its changes")
            check(controller.undoManager?.undoActionName == "Edit Theme", "the builder's changes are one undo step",
                  controller.undoManager?.undoActionName ?? "")
            controller.undoManager?.undo()
        }
        step {
            check(!controller.presentation.themes[0].layouts.contains { $0.name == "Agenda" }
                  && controller.presentation.themes[0].colors[.accent1] != RGBColor(red: 1, green: 2, blue: 3), "undo takes back the whole visit")
        }

        // Tables, charts and word art in downloads and files.
        step {
            let sample = SampleContent.make()
            guard let tableIndex = sample.slides.firstIndex(where: { $0.elements.contains { $0.table != nil } }),
                  let chartIndex = sample.slides.firstIndex(where: { $0.elements.contains { $0.chart != nil } }),
                  let artIndex = sample.slides.firstIndex(where: { $0.elements.contains { $0.isWordArt } }) else {
                return check(false, "the sample deck has a table, a chart and word art")
            }
            let tableSVG = SVGExport.svg(for: sample.slides[tableIndex], number: tableIndex + 1, in: sample)
            check(XMLParser(data: Data(tableSVG.utf8)).parse() && tableSVG.contains(">August</text>") && tableSVG.contains("<line"),
                  "an SVG slide has the table's text and borders")
            let chartSVG = SVGExport.svg(for: sample.slides[chartIndex], number: chartIndex + 1, in: sample)
            check(XMLParser(data: Data(chartSVG.utf8)).parse(), "an SVG slide with a chart is well-formed XML")
            let artSVG = SVGExport.svg(for: sample.slides[artIndex], number: artIndex + 1, in: sample)
            check(artSVG.contains("<path") && !artSVG.contains(">Good dogs!</text>"), "word art exports as letter shapes")
            for format in [PresentationFormat.pptx, .odp] {
                do {
                    let reopened = try PresentationIO.read(try PresentationIO.write(sample, format: format), format: format).presentation
                    let name = format == .pptx ? "PowerPoint" : "OpenDocument"
                    let article = format == .pptx ? "a" : "an"
                    let table = reopened.slides[tableIndex].elements.compactMap(\.table).first
                    check(table.map { $0.rowCount == 5 && $0.cells[2][0].text.plainText == "August" && $0.cells[4][0].columnSpan == 3 } == true,
                          "\(article) \(name) file keeps tables")
                    let chart = reopened.slides[chartIndex].elements.compactMap(\.chart).first
                    check(chart?.kind == .column && chart?.data.series.map(\.values) == sample.slides[chartIndex].elements.compactMap(\.chart).first?.data.series.map(\.values),
                          "\(article) \(name) file keeps charts")
                    check(reopened.slides[artIndex].elements.contains { $0.isWordArt }, "\(article) \(name) file keeps word art")
                    let pictures = reopened.slides[artIndex].elements.compactMap(\.picture)
                    check(pictures.contains { $0.adjustments.recolor == .grayscale } && pictures.contains { $0.adjustments.transparency > 0.4 },
                          "\(article) \(name) file keeps picture adjustments")
                } catch {
                    check(false, "\(format) round trip", "\(error)")
                }
            }
        }
    }

    /// A small PNG of one color, for Replace image.
    private static func coloredPNG() -> Data {
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }
}
#endif
