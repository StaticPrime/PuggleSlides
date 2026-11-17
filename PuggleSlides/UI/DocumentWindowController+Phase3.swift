import AppKit
import PuggleSlidesKit
import SwiftUI
import UniformTypeIdentifiers

/// View settings that belong to the person, not the presentation.
enum ViewPreferences {
    static var snapsToGrid: Bool {
        get { UserDefaults.standard.bool(forKey: "PPSnapToGrid") }
        set { UserDefaults.standard.set(newValue, forKey: "PPSnapToGrid") }
    }

    /// On by default: objects line up with each other, the slide and guides as they move.
    static var snapsToGuides: Bool {
        get { UserDefaults.standard.object(forKey: "PPSnapToGuides") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PPSnapToGuides") }
    }

    static var showsRuler: Bool {
        get { UserDefaults.standard.bool(forKey: "PPShowRuler") }
        set { UserDefaults.standard.set(newValue, forKey: "PPShowRuler") }
    }

    static var showsGuides: Bool {
        get { UserDefaults.standard.object(forKey: "PPShowGuides") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PPShowGuides") }
    }
}

extension DocumentWindowController {
    // MARK: Insert

    func ppInsertTable(_ sender: Any?) {
        finishEditing()
        guard let item = sender as? NSMenuItem, item.tag > 0 else { return }
        let rows = item.tag / 100, columns = item.tag % 100
        guard rows > 0, columns > 0, let id = controller.insertTable(rows: rows, columns: columns) else { return }
        focusCanvas()
        canvas.beginEditingCell(id, row: 0, column: 0, at: nil)
    }

    func ppInsertChart(_ sender: Any?) {
        finishEditing()
        guard let item = sender as? NSMenuItem, ChartKind.allCases.indices.contains(item.tag) else { return }
        controller.insertChart(ChartKind.allCases[item.tag])
    }

    func ppInsertWordArt(_ sender: Any?) {
        finishEditing()
        presentSheet { [weak self] dismiss in
            WordArtPrompt(insert: { text in self?.controller.insertWordArt(text) }, dismiss: dismiss)
        }
    }

    // MARK: Tables

    func ppTableCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let command = MenuBuilder.TableCommand(rawValue: item.tag) else { return }
        finishEditing()
        switch command {
        case .insertRowAbove: controller.insertTableRows(below: false)
        case .insertRowBelow: controller.insertTableRows(below: true)
        case .insertColumnLeft: controller.insertTableColumns(right: false)
        case .insertColumnRight: controller.insertTableColumns(right: true)
        case .deleteRow: controller.deleteTableRows()
        case .deleteColumn: controller.deleteTableColumns()
        case .deleteTable: controller.deleteSelectedElements()
        case .distributeRows: controller.distributeTableRows()
        case .distributeColumns: controller.distributeTableColumns()
        case .mergeCells: controller.mergeTableCells()
        case .unmergeCells: controller.unmergeTableCells()
        }
    }

    func ppTableBorderPosition(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, TableBorderPosition.allCases.indices.contains(item.tag) else { return }
        controller.tableBorderPosition = TableBorderPosition.allCases[item.tag]
        canvas.needsDisplay = true
        refreshState()
    }

    // MARK: Images and charts

    func ppCropImage(_ sender: Any?) { cropImage() }
    func ppResetImage(_ sender: Any?) { resetImage() }
    func ppEditChart(_ sender: Any?) { editChart() }

    func cropImage() {
        guard let id = controller.selectedPicture?.id else { return }
        finishEditing()
        canvas.beginCropping(id)
    }

    func resetImage() {
        finishEditing()
        canvas.endCropping(commit: false)
        controller.resetSelectedImage()
    }

    func editChart() {
        guard controller.selectedChart != nil else { return }
        finishEditing()
        showSidebar(.chartEditor)
    }

    func ppMaskImage(_ sender: Any?) {
        guard let preset = (sender as? NSMenuItem)?.representedObject as? String else { return }
        finishEditing()
        controller.maskSelectedImage(preset)
    }

    func ppReplaceImage(_ sender: Any?) {
        guard controller.selectedPicture != nil, let window else { return }
        finishEditing()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let data = try? Data(contentsOf: url), self.controller.replaceSelectedImage(with: data) else {
                self.showProblem("That file isn't an image PuggleSlides can show.")
                return
            }
        }
    }

    // MARK: Snapping, rulers and guides

    /// View ▸ Show ruler: inch rulers along the top and left of the canvas, starting at the slide's corner.
    func applyRulerVisibility() {
        canvasScroll.hasHorizontalRuler = true
        canvasScroll.hasVerticalRuler = true
        for ruler in [canvasScroll.horizontalRulerView, canvasScroll.verticalRulerView].compactMap({ $0 }) {
            ruler.measurementUnits = .inches
            ruler.originOffset = canvas.margin
            ruler.reservedThicknessForMarkers = 0
            ruler.reservedThicknessForAccessoryView = 0
        }
        canvasScroll.rulersVisible = ViewPreferences.showsRuler
    }

    /// A double-click (or Return) on word art: change its text.
    func editWordArt(_ id: UUID) {
        guard let element = controller.currentSlide?.element(id: id), element.isWordArt else { return }
        let text = element.shape?.text?.paragraphs.map { $0.runs.map(\.text).joined() }.joined(separator: "\n") ?? ""
        presentSheet { [weak self] dismiss in
            WordArtPrompt(initial: text, buttonTitle: "Update", insert: { self?.controller.setWordArtText(id, to: $0) }, dismiss: dismiss)
        }
    }

    func ppSnapToGrid(_ sender: Any?) { ViewPreferences.snapsToGrid.toggle() }
    func ppSnapToGuides(_ sender: Any?) { ViewPreferences.snapsToGuides.toggle() }

    func ppShowRuler(_ sender: Any?) {
        ViewPreferences.showsRuler.toggle()
        applyRulerVisibility()
    }

    func ppShowGuides(_ sender: Any?) {
        ViewPreferences.showsGuides.toggle()
        canvas.needsDisplay = true
    }

    func ppAddGuide(_ sender: Any?) {
        finishEditing()
        ViewPreferences.showsGuides = true
        controller.addGuide((sender as? NSMenuItem)?.tag == 1 ? .horizontal : .vertical)
        canvas.needsDisplay = true
    }

    func ppEditGuides(_ sender: Any?) {
        finishEditing()
        let guides = controller.presentation.guides
        let size = controller.presentation.slideSize
        presentSheet { [weak self] dismiss in
            EditGuidesView(guides: guides, slideSize: size, apply: { self?.controller.setGuides($0) }, dismiss: dismiss)
        }
    }

    func ppClearGuides(_ sender: Any?) {
        finishEditing()
        controller.clearGuides()
    }

    // MARK: Import slides

    /// File ▸ Import slides: pick a presentation, then the slides to bring in.
    func ppImportSlides(_ sender: Any?) {
        guard let window else { return }
        finishEditing()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PresentationFormat.allCases.compactMap { UTType($0.typeIdentifier) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let format = PresentationFormat(typeName: url.pathExtension) ?? .pptx
                let file = try PresentationIO.read(try Data(contentsOf: url), format: format)
                DispatchQueue.main.async { self.chooseSlidesToImport(from: file.presentation, name: url.deletingPathExtension().lastPathComponent) }
            } catch {
                self.showProblem(error.localizedDescription)
            }
        }
    }

    func chooseSlidesToImport(from source: Presentation, name: String) {
        guard !source.slides.isEmpty else { return showProblem("“\(name)” has no slides to import.") }
        presentSheet { [weak self] dismiss in
            ImportSlidesView(source: source, name: name, importSlides: { indexes, keepTheme in
                self?.importSlides(indexes, from: source, keepingTheme: keepTheme)
            }, dismiss: dismiss)
        }
    }

    func importSlides(_ indexes: [Int], from source: Presentation, keepingTheme: Bool) {
        let slides = indexes.sorted().compactMap { source.slides.indices.contains($0) ? source.slides[$0] : nil }
        guard !slides.isEmpty else { return }
        let position = (controller.currentSlideIndex ?? controller.presentation.slides.count - 1) + 1
        let theme = controller.currentSlide.map { controller.presentation.theme(for: $0) }
        var inserted: [UUID] = []
        controller.perform("Import Slides", update: [.slides, .content, .theme]) { presentation in
            inserted = presentation.insertSlides(slides, themes: source.themes, media: source.media, sourceSize: source.slideSize,
                                                 at: position, keepingThemes: keepingTheme, theme: theme)
        }
        if let first = inserted.first { controller.selectSlide(first) }
    }

    /// Themes ▸ Import theme: pick a presentation and use its theme.
    func importTheme() {
        guard let window else { return }
        finishEditing()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PresentationFormat.allCases.compactMap { UTType($0.typeIdentifier) }
        panel.message = "Choose a presentation whose theme you want to use"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let format = PresentationFormat(typeName: url.pathExtension) ?? .pptx
                let source = try PresentationIO.read(try Data(contentsOf: url), format: format).presentation
                guard let theme = source.slides.first.map(source.theme(for:)) ?? source.themes.first else { return }
                self.controller.perform("Import Theme", update: [.slides, .content, .theme]) { presentation in
                    presentation.importTheme(theme, media: source.media, sourceSize: source.slideSize)
                }
            } catch {
                self.showProblem(error.localizedDescription)
            }
        }
    }

    // MARK: Theme builder

    /// Slide ▸ Edit theme, or View ▸ Theme builder: opens the builder, or closes it when it's open.
    func ppEditTheme(_ sender: Any?) {
        finishEditing()
        if controller.isThemeBuilderOpen {
            closeThemeBuilder()
        } else {
            setGridView(false)
            controller.openThemeBuilder()
            focusCanvas()
        }
    }

    func closeThemeBuilder() {
        finishEditing()
        if state.sidebar == .themeColors { closeSidebar() }
        controller.closeThemeBuilder()
        focusCanvas()
    }

    func renameThemeBuilderPage() {
        guard let session = controller.builder else { return }
        finishEditing()
        let name = session.pageName(controller.currentSlideID)
        let master = controller.isEditingMaster
        presentSheet { [weak self] dismiss in
            WordArtPrompt(initial: name, buttonTitle: "Rename", title: master ? "Rename theme" : "Rename layout",
                          insert: { self?.controller.renameBuilderPage(to: $0) }, dismiss: dismiss)
        }
    }

    func showThemeColors() { showSidebar(.themeColors) }

    @objc func renameBuilderPageFromMenu(_ sender: Any?) { renameThemeBuilderPage() }

    func ppInsertPlaceholder(_ sender: Any?) {
        let types: [PlaceholderType] = [.title, .subtitle, .body, .slideNumber]
        guard let tag = (sender as? NSMenuItem)?.tag, types.indices.contains(tag) else { return }
        finishEditing()
        controller.insertBuilderPlaceholder(types[tag])
    }

    /// Commands that make sense only for slides, off while the theme builder is open.
    static let slideOnlyCommands: Set<Selector> = [
        #selector(SlideCommands.ppNewSlide(_:)), #selector(SlideCommands.ppNewSlideWithLayout(_:)), #selector(SlideCommands.ppSkipSlide(_:)),
        #selector(SlideCommands.ppApplyLayout(_:)), #selector(SlideCommands.ppChangeTheme(_:)), #selector(SlideCommands.ppStartSlideshow(_:)),
        #selector(SlideCommands.ppStartSlideshowFromBeginning(_:)), #selector(SlideCommands.ppPresenterView(_:)),
        #selector(SlideCommands.ppShowMotion(_:)), #selector(SlideCommands.ppInsertAnimation(_:)), #selector(SlideCommands.ppSlideNumbers(_:)),
        #selector(SlideCommands.ppImportSlides(_:)), #selector(SlideCommands.ppToggleGridView(_:)), #selector(SlideCommands.ppMoveSlide(_:)),
        #selector(SlideCommands.ppDownload(_:)), #selector(SlideCommands.ppPrint(_:)), #selector(SlideCommands.ppPrintSettings(_:)),
    ]

    // MARK: Validation

    /// Menu validation for phase 3's commands; nil for commands it doesn't know.
    func validatePhase3(_ item: NSMenuItem) -> Bool? {
        let hasSlide = controller.currentSlide != nil
        if controller.isThemeBuilderOpen, let action = item.action {
            if Self.slideOnlyCommands.contains(action) { return false }
            switch action {
            case #selector(SlideCommands.ppDuplicateSlide(_:)):
                item.title = "Duplicate layout"
                return !controller.isEditingMaster
            case #selector(SlideCommands.ppDeleteSlide(_:)):
                item.title = "Delete layout"
                return controller.canDeleteBuilderLayout
            default:
                break
            }
        } else if item.action == #selector(SlideCommands.ppDuplicateSlide(_:)) || item.action == #selector(SlideCommands.ppDeleteSlide(_:)) {
            item.title = item.action == #selector(SlideCommands.ppDuplicateSlide(_:)) ? "Duplicate slide" : "Delete slide"
        }
        switch item.action {
        case #selector(SlideCommands.ppEditTheme(_:)):
            item.state = controller.isThemeBuilderOpen ? .on : .off
            return hasSlide
        case #selector(SlideCommands.ppInsertPlaceholder(_:)):
            return controller.isThemeBuilderOpen && !controller.isEditingMaster
        case #selector(SlideCommands.ppInsertTable(_:)), #selector(SlideCommands.ppInsertChart(_:)), #selector(SlideCommands.ppInsertWordArt(_:)),
             #selector(SlideCommands.ppImportSlides(_:)):
            return hasSlide || item.action == #selector(SlideCommands.ppImportSlides(_:))
        case #selector(SlideCommands.ppTableCommand(_:)):
            guard controller.selectedTableElement != nil else { return false }
            switch MenuBuilder.TableCommand(rawValue: item.tag) {
            case .mergeCells: return controller.canMergeTableCells
            case .unmergeCells: return controller.canUnmergeTableCells
            default: return true
            }
        case #selector(SlideCommands.ppTableBorderPosition(_:)):
            item.state = TableBorderPosition.allCases.firstIndex(of: controller.tableBorderPosition) == item.tag ? .on : .off
            return controller.selectedTableElement != nil
        case #selector(SlideCommands.ppCropImage(_:)), #selector(SlideCommands.ppMaskImage(_:)), #selector(SlideCommands.ppResetImage(_:)),
             #selector(SlideCommands.ppReplaceImage(_:)):
            return controller.selectedPicture != nil
        case #selector(SlideCommands.ppEditChart(_:)):
            return controller.selectedChart != nil
        case #selector(SlideCommands.ppSnapToGrid(_:)):
            item.state = ViewPreferences.snapsToGrid ? .on : .off
            return true
        case #selector(SlideCommands.ppSnapToGuides(_:)):
            item.state = ViewPreferences.snapsToGuides ? .on : .off
            return true
        case #selector(SlideCommands.ppShowRuler(_:)):
            item.state = ViewPreferences.showsRuler ? .on : .off
            return true
        case #selector(SlideCommands.ppShowGuides(_:)):
            item.state = ViewPreferences.showsGuides ? .on : .off
            return true
        case #selector(SlideCommands.ppAddGuide(_:)):
            return hasSlide
        case #selector(SlideCommands.ppEditGuides(_:)), #selector(SlideCommands.ppClearGuides(_:)):
            return !controller.presentation.guides.isEmpty
        default:
            return nil
        }
    }
}
