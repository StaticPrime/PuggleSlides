import AppKit
import PuggleSlidesKit
import SwiftUI
import UniformTypeIdentifiers

/// Copied shapes, with the media they show.
struct ElementClipboard: Codable {
    var elements: [SlideElement]
    var media: [MediaID: MediaItem]
}

/// Copied slides, with the themes and media they need.
struct SlideClipboard: Codable {
    var slides: [Slide]
    var themes: [SlideTheme]
    var media: [MediaID: MediaItem]
}

extension NSPasteboard.PasteboardType {
    static let slideElements = NSPasteboard.PasteboardType("com.pugglesoft.puggleslides.elements")
    static let slides = NSPasteboard.PasteboardType("com.pugglesoft.puggleslides.slides")
}

extension DocumentWindowController: SlideCommands, NSMenuItemValidation {
    // MARK: Messages and sheets

    func showProblem(_ message: String) {
        showMessage("There was a problem", detail: message)
    }

    func showMessage(_ message: String, detail: String?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    func presentSheet<Content: View>(_ content: (_ dismiss: @escaping () -> Void) -> Content) {
        guard let window else { return }
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let dismiss = { [weak window, weak sheet] in
            guard let window, let sheet else { return }
            window.endSheet(sheet)
        }
        let host = NSHostingController(rootView: content(dismiss))
        sheet.contentViewController = host
        let ideal = host.view.intrinsicContentSize
        if ideal.width > 0, ideal.height > 0, ideal.width < 2_000, ideal.height < 2_000 { sheet.setContentSize(ideal) }
        sheet.appearance = NSAppearance(named: .aqua)
        window.beginSheet(sheet) { [weak self] _ in self?.focusCanvas() }
    }

    // MARK: Clipboard

    @objc func copy(_ sender: Any?) {
        if isFilmstripFocused || controller.selectedElementIDs.isEmpty {
            copySlides()
        } else {
            copyElements()
        }
    }

    @objc func cut(_ sender: Any?) {
        if isFilmstripFocused || controller.selectedElementIDs.isEmpty {
            copySlides()
            controller.deleteSlides()
        } else {
            copyElements()
            controller.deleteSelectedElements()
        }
    }

    @objc func paste(_ sender: Any?) {
        finishEditing()
        paste(withFormatting: true)
    }

    func ppPasteWithoutFormatting(_ sender: Any?) {
        // While typing, the text goes in plain, with the formatting at the insertion point.
        if let editor = canvas.editor { return editor.textView.pasteAsPlainText(sender) }
        if isEditingNotes { return notes.textView.pasteAsPlainText(sender) }
        finishEditing()
        paste(withFormatting: false)
    }

    @objc func delete(_ sender: Any?) {
        finishEditing()
        if isFilmstripFocused || controller.selectedElementIDs.isEmpty {
            controller.deleteSlides()
        } else {
            controller.deleteSelectedElements()
        }
    }

    private func copyElements() {
        guard let slide = controller.currentSlide else { return }
        let presentation = controller.presentation
        let theme = presentation.theme(for: slide)
        // Placeholders travel as ordinary text boxes with the look they have here.
        let elements = controller.selectedElements.map { element -> SlideElement in
            element.placeholder == nil ? element : presentation.detached(element, on: slide, theme: theme)
        }
        let mediaIDs = elements.reduce(into: Set<MediaID>()) { $0.formUnion($1.mediaIDs) }
        let clipboard = ElementClipboard(elements: elements, media: presentation.media.filter { mediaIDs.contains($0.key) })
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(clipboard) { pasteboard.setData(data, forType: .slideElements) }
        let text = elements.compactMap { $0.shape?.text?.plainText }.filter { !$0.isEmpty }.joined(separator: "\n")
        if !text.isEmpty { pasteboard.setString(text, forType: .string) }
        if elements.count == 1, let picture = elements.first?.picture, let item = presentation.media[picture.mediaID] {
            pasteboard.setData(item.data, forType: NSPasteboard.PasteboardType(item.contentType == "image/png" ? UTType.png.identifier : UTType.jpeg.identifier))
        }
    }

    private func copySlides() {
        let presentation = controller.presentation
        let slides = controller.selectedSlideIndexes.map { presentation.slides[$0] }
        guard !slides.isEmpty else { return }
        var themes: [SlideTheme] = []
        for slide in slides {
            let theme = presentation.theme(for: slide)
            if !themes.contains(where: { $0.id == theme.id }) { themes.append(theme) }
        }
        var mediaIDs = Set<MediaID>()
        for slide in slides {
            slide.elements.forEach { mediaIDs.formUnion($0.mediaIDs) }
            if let id = slide.background?.mediaID { mediaIDs.insert(id) }
        }
        let clipboard = SlideClipboard(slides: slides, themes: themes, media: presentation.media.filter { mediaIDs.contains($0.key) })
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(clipboard) { pasteboard.setData(data, forType: .slides) }
        pasteboard.setString(slides.flatMap { $0.elements.compactMap { $0.shape?.text?.plainText } }.joined(separator: "\n"), forType: .string)
    }

    private func paste(withFormatting: Bool) {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .slides), let clipboard = try? JSONDecoder().decode(SlideClipboard.self, from: data),
           isFilmstripFocused || pasteboard.data(forType: .slideElements) == nil {
            pasteSlides(clipboard)
            return
        }
        if withFormatting, let data = pasteboard.data(forType: .slideElements),
           let clipboard = try? JSONDecoder().decode(ElementClipboard.self, from: data) {
            pasteElements(clipboard)
            return
        }
        if let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))
            ?? pasteboard.data(forType: .tiff), controller.currentSlide != nil {
            var data = image
            if MediaItem.contentType(sniffing: data) == "image/tiff", let rep = NSBitmapImageRep(data: data),
               let png = rep.representation(using: .png, properties: [:]) {
                data = png
            }
            if controller.insertImage(data: data) { return }
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty, controller.currentSlide != nil {
            // Text pasted on the canvas becomes a text box.
            let size = controller.presentation.slideSize
            var element = controller.makeTextBox(frame: SlideRect(x: size.width * 0.2, y: size.height * 0.4, width: size.width * 0.6, height: 30))
            element.shape?.text?.paragraphs = text.components(separatedBy: .newlines).map { TextParagraph($0) }
            if let slide = controller.currentSlide { TextFitting.fit(&element, on: slide, in: controller.presentation) }
            controller.insert([element], actionName: "Paste")
            return
        }
        NSSound.beep()
    }

    private func pasteElements(_ clipboard: ElementClipboard) {
        guard let slide = controller.currentSlide else { return }
        let existing = Set(slide.elements.map { controller.presentation.placement(of: $0, on: slide) })
        let elements = clipboard.elements.map { element -> SlideElement in
            var copy = element.withNewIDs()
            // Pasting where the original still sits offsets the copy, so it doesn't hide it.
            if let placement = copy.placement, existing.contains(placement) {
                var moved = placement
                moved.frame = placement.frame.offsetBy(dx: 9, dy: 9)
                copy.placement = moved
                copy.offsetChildren(dx: 9, dy: 9)
            }
            return copy
        }
        controller.insert(elements, media: clipboard.media, actionName: "Paste")
    }

    /// Pasted slides take the matching layouts of this presentation's theme ("Match theme").
    private func pasteSlides(_ clipboard: SlideClipboard) {
        let presentation = controller.presentation
        let index = (controller.currentSlideIndex ?? presentation.slides.count - 1) + 1
        let theme = controller.currentSlide.map { presentation.theme(for: $0) } ?? presentation.themes.first
        var pasted: [UUID] = []
        controller.perform("Paste", update: [.slides, .content], selecting: []) { presentation in
            pasted = presentation.insertSlides(clipboard.slides, themes: clipboard.themes, media: clipboard.media, at: index,
                                               keepingThemes: false, theme: theme)
        }
        if let first = pasted.first { controller.selectSlide(first) }
    }

    // MARK: Edit

    func ppDuplicate(_ sender: Any?) {
        finishEditing()
        if isFilmstripFocused || controller.selectedElementIDs.isEmpty { controller.duplicateSlides() } else { controller.duplicateSelectedElements() }
    }

    func ppSelectNone(_ sender: Any?) {
        finishEditing()
        controller.selectElements([])
    }

    // MARK: File

    func ppDownload(_ sender: Any?) {
        finishEditing()
        guard let window, let item = sender as? NSMenuItem, let format = DownloadFormat(rawValue: item.tag) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        let slideName = format.isCurrentSlide ? " - \((controller.currentSlideIndex ?? 0) + 1)" : ""
        panel.nameFieldStringValue = "\(state.title)\(slideName).\(format.fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.downloadData(format).write(to: url)
            } catch {
                self.showProblem(error.localizedDescription)
            }
        }
    }

    /// The presentation (or the current slide) in a download format.
    func downloadData(_ format: DownloadFormat) throws -> Data {
        var presentation = controller.presentation
        presentation.removeUnusedMedia()
        if presentation.title == nil { presentation.title = state.title }
        switch format {
        case .pptx: return try PresentationIO.write(presentation, format: .pptx)
        case .odp: return try PresentationIO.write(presentation, format: .odp)
        case .pdf: return PrintPagesView(presentation: presentation, settings: SlidePrintSettings()).pdfData()
        case .txt: return Data(presentation.plainText.utf8)
        case .jpg, .png, .svg:
            guard let index = controller.currentSlideIndex else { throw PresentationIOError.unwritable("There's no slide to download.") }
            let slide = presentation.slides[index]
            if format == .svg { return Data(SVGExport.svg(for: slide, number: index + 1, in: presentation).utf8) }
            // Slide pictures are 1600 pixels wide.
            let size = presentation.slideSize
            let image = SlideRenderer.image(of: slide, in: presentation, size: CGSize(width: 1600, height: (1600 * size.height / size.width).rounded()),
                                            slideNumber: index + 1, scale: 1)
            guard let rep = image.representations.first as? NSBitmapImageRep,
                  let data = rep.representation(using: format == .png ? .png : .jpeg, properties: format == .png ? [:] : [.compressionFactor: 0.9]) else {
                throw PresentationIOError.unwritable("The slide couldn't be turned into a picture.")
            }
            return data
        }
    }

    // MARK: Printing

    func ppPrintSettings(_ sender: Any?) {
        finishEditing()
        let presentation = controller.presentation
        let settings = printSettings
        presentSheet { [weak self] dismiss in
            PrintSettingsView(presentation: presentation, settings: settings) { chosen, download in
                dismiss()
                guard let self, let chosen else { return }
                self.printSettings = chosen
                DispatchQueue.main.async {
                    if download { self.exportPDF(chosen) } else { self.runPrint(chosen) }
                }
            }
        }
    }

    func ppPrint(_ sender: Any?) {
        finishEditing()
        runPrint(printSettings)
    }

    private func runPrint(_ settings: SlidePrintSettings) {
        guard let window else { return }
        let view = PrintPagesView(presentation: controller.presentation, settings: settings)
        let operation = NSPrintOperation(view: view, printInfo: view.printInfo())
        operation.jobTitle = state.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func exportPDF(_ settings: SlidePrintSettings) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = state.title + ".pdf"
        let data = PrintPagesView(presentation: controller.presentation, settings: settings).pdfData()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url) } catch { self?.showProblem(error.localizedDescription) }
        }
    }

    /// File ▸ Rename: the name in the header, all of it selected, ready to type over. It answers the standard rename
    /// command, so the File menu has this one Rename and macOS doesn't add a second beside Make a copy.
    @objc(renameDocument:) func renameFromMenu(_ sender: Any?) {
        state.renameRequest += 1
    }

    func ppPageSetup(_ sender: Any?) {
        finishEditing()
        let current = controller.presentation.slideSize
        presentSheet { [weak self] dismiss in
            PageSetupView(current: current, apply: { size in self?.controller.setSlideSize(size) }, dismiss: dismiss)
        }
    }

    // MARK: View

    func ppStartSlideshow(_ sender: Any?) { startSlideshow(fromBeginning: false) }
    func ppStartSlideshowFromBeginning(_ sender: Any?) { startSlideshow(fromBeginning: true) }
    func ppPresenterView(_ sender: Any?) { startPresenterView() }
    func ppShowMotion(_ sender: Any?) { showSidebar(.motion) }
    func ppToggleGridView(_ sender: Any?) { setGridView(!isGridView) }
    func ppInsertAnimation(_ sender: Any?) { animateSelection() }

    func ppToggleSpeakerNotes(_ sender: Any?) {
        state.showsSpeakerNotes.toggle()
        UserDefaults.standard.set(state.showsSpeakerNotes, forKey: "PPShowSpeakerNotes")
        applyNotesVisibility()
    }

    func ppZoomIn(_ sender: Any?) {
        let next = Theme.zoomLevels.first { $0 > canvasScroll.zoom + 0.01 } ?? min(Theme.maximumZoom, canvasScroll.zoom * 1.25)
        setZoom(next)
    }

    func ppZoomOut(_ sender: Any?) {
        let next = Theme.zoomLevels.last { $0 < canvasScroll.zoom - 0.01 } ?? max(Theme.minimumZoom, canvasScroll.zoom / 1.25)
        setZoom(next)
    }

    func ppZoomFit(_ sender: Any?) { setZoom(nil) }

    func ppSetZoom(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, item.tag > 0 else { return }
        setZoom(CGFloat(item.tag) / 100)
    }

    // MARK: Insert

    func ppInsertImage(_ sender: Any?) { insertImageFromFile() }
    func ppInsertTextBox(_ sender: Any?) { setTool(.textBox) }

    func ppInsertShape(_ sender: Any?) {
        guard let preset = (sender as? NSMenuItem)?.representedObject as? String else { return }
        setTool(.shape(preset))
    }

    func ppInsertLine(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, LineKind.allCases.indices.contains(item.tag) else { return }
        setTool(.line(LineKind.allCases[item.tag]))
    }

    func ppInsertLink(_ sender: Any?) { showLinkEditor() }

    func showLinkEditor() {
        let editor = canvas.editor
        let current: Hyperlink? = editor?.selectedEffectiveStyles.first?.link ?? (editor == nil ? controller.selectedResolvedParagraphs.first?.runs.first?.style.link : nil)
        guard editor != nil || !controller.selectedTextElementIDs.isEmpty else {
            showMessage("Select some text first", detail: "Select text or a shape to link it to a web page or another slide.")
            return
        }
        if let editor, editor.textView.selectedRange().length == 0, current == nil {
            showMessage("Select some text first", detail: "Select the words to turn into a link.")
            return
        }
        let slides = controller.presentation.slides.enumerated().map { index, slide -> (id: UUID, title: String) in
            let title = slide.elements.first { $0.placeholder?.type.isTitle == true }?.shape?.text?.plainText ?? ""
            return (slide.id, "Slide \(index + 1)" + (title.isEmpty ? "" : ": \(title)"))
        }
        presentSheet { [weak self] dismiss in
            LinkEditorView(slides: slides, current: current, apply: { link in
                guard let self else { return }
                if let editor = self.canvas.editor { editor.applyCharacters { $0.link = link } } else { self.controller.setLink(link) }
                self.scheduleStateRefresh()
            }, dismiss: dismiss)
        }
    }

    func ppSlideNumbers(_ sender: Any?) {
        finishEditing()
        presentSheet { [weak self] dismiss in
            SlideNumbersView(apply: { on, skip, selected in
                self?.controller.setSlideNumbers(on, skipTitleSlides: skip, onlySelected: selected)
            }, dismiss: dismiss)
        }
    }

    // MARK: Format

    func ppToggleBold(_ sender: Any?) { toggleBold() }
    func ppToggleItalic(_ sender: Any?) { toggleItalic() }
    func ppToggleUnderline(_ sender: Any?) { toggleUnderline() }
    func ppToggleStrikethrough(_ sender: Any?) { toggleStrikethrough() }
    func ppSuperscript(_ sender: Any?) { setBaseline(.superscript) }
    func ppSubscript(_ sender: Any?) { setBaseline(.subscript) }
    func ppIncreaseFontSize(_ sender: Any?) { stepFontSize(by: 1, standardSteps: true) }
    func ppDecreaseFontSize(_ sender: Any?) { stepFontSize(by: -1, standardSteps: true) }

    func ppSetFont(_ sender: Any?) {
        guard let family = (sender as? NSMenuItem)?.representedObject as? String else { return }
        setFontFamily(family)
    }

    func ppMoreFonts(_ sender: Any?) {
        let families = NSFontManager.shared.availableFontFamilies
        let menu = NSMenu()
        for family in families {
            let item = MenuBuilder.represented(MenuBuilder.item(family, #selector(SlideCommands.ppSetFont(_:))), family)
            item.target = self
            menu.addItem(item)
        }
        if let window, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: window.contentView ?? canvas)
        }
    }

    func ppTextAlign(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let alignments: [PuggleSlidesKit.TextAlignment] = [.left, .center, .right, .justified]
        guard alignments.indices.contains(item.tag) else { return }
        setAlignment(alignments[item.tag])
    }

    func ppVerticalAlign(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let anchors: [VerticalAnchor] = [.top, .middle, .bottom]
        guard anchors.indices.contains(item.tag) else { return }
        setAnchor(anchors[item.tag])
    }

    func ppIncreaseIndent(_ sender: Any?) { indent(by: 1) }
    func ppDecreaseIndent(_ sender: Any?) { indent(by: -1) }

    func ppLineSpacing(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, item.tag > 0 else { return }
        setLineSpacing(Double(item.tag) / 100)
    }

    func ppParagraphSpacing(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        switch item.tag {
        case 1: setParagraphSpacing(before: 10, after: nil)
        case 2: setParagraphSpacing(before: nil, after: 10)
        case 3: setParagraphSpacing(before: 0, after: nil)
        default: setParagraphSpacing(before: nil, after: 0)
        }
    }

    func ppBulletedList(_ sender: Any?) {
        if let character = (sender as? NSMenuItem)?.representedObject as? String { setList(.bulleted(character)) } else { toggleList(numbered: false) }
    }

    func ppNumberedList(_ sender: Any?) {
        if let raw = (sender as? NSMenuItem)?.representedObject as? String, let scheme = AutoNumberScheme(rawValue: raw) {
            setList(.numbered(scheme))
        } else {
            toggleList(numbered: true)
        }
    }

    func ppFormatOptions(_ sender: Any?) { showSidebar(.formatOptions) }

    func ppAltText(_ sender: Any?) {
        finishEditing()
        guard let element = controller.selectedElements.first else { return }
        presentSheet { [weak self] dismiss in
            AltTextView(title: element.altTitle ?? "", description: element.altDescription ?? "", apply: { title, description in
                self?.controller.setAltText(title: title, description: description)
            }, dismiss: dismiss)
        }
    }

    func ppClearFormatting(_ sender: Any?) { clearFormatting() }

    func ppBorderWeight(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, item.tag > 0 else { return }
        // The menu's weights are pixels: 1 px is 0.75 points.
        controller.setBorderWidth(Double(item.tag) * 0.75)
    }

    func ppBorderDash(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, DashStyle.allCases.indices.contains(item.tag) else { return }
        controller.setBorderDash(DashStyle.allCases[item.tag])
    }

    func ppLineStart(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, LineEnd.allCases.indices.contains(item.tag) else { return }
        controller.setLineEnds(head: LineEnd.allCases[item.tag])
    }

    func ppLineEnd(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, LineEnd.allCases.indices.contains(item.tag) else { return }
        controller.setLineEnds(tail: LineEnd.allCases[item.tag])
    }

    // MARK: Slide

    func ppNewSlide(_ sender: Any?) {
        finishEditing()
        controller.newSlide()
        focusCanvas()
    }

    func ppNewSlideWithLayout(_ sender: Any?) {
        finishEditing()
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return }
        controller.newSlide(layoutID: id)
    }

    func ppDuplicateSlide(_ sender: Any?) {
        finishEditing()
        if controller.isThemeBuilderOpen { return controller.duplicateBuilderLayout() }
        controller.duplicateSlides()
    }

    func ppDeleteSlide(_ sender: Any?) {
        finishEditing()
        if controller.isThemeBuilderOpen { return controller.deleteBuilderLayout() }
        controller.deleteSlides()
    }

    func ppSkipSlide(_ sender: Any?) {
        finishEditing()
        controller.toggleSkip()
    }

    func ppMoveSlide(_ sender: Any?) {
        finishEditing()
        switch (sender as? NSMenuItem)?.tag {
        case 0: controller.moveSlidesToBeginning()
        case 1: controller.moveSlidesUp()
        case 2: controller.moveSlidesDown()
        default: controller.moveSlidesToEnd()
        }
        filmstrip.scrollToCurrent()
    }

    func ppChangeBackground(_ sender: Any?) { showBackgroundDialog() }

    func showBackgroundDialog() {
        finishEditing()
        guard let slide = controller.currentSlide else { return }
        let theme = controller.presentation.theme(for: slide)
        let currentHex: String? = if case .solid(let color) = controller.presentation.background(for: slide) { color.resolved(theme.colors).rgb.hex } else { nil }
        presentSheet { [weak self] dismiss in
            BackgroundView(themeColors: self?.controller.currentThemeColors ?? [], currentHex: currentHex, setColor: { color in
                self?.controller.setBackground(color.map(Fill.solid) ?? Fill.none)
            }, chooseImage: {
                dismiss()
                DispatchQueue.main.async { self?.chooseBackgroundImage() }
            }, reset: {
                self?.controller.setBackground(nil)
            }, addToTheme: {
                guard let self, let slide = self.controller.currentSlide else { return }
                self.controller.setThemeBackground(self.controller.presentation.background(for: slide))
            }, dismiss: dismiss)
        }
    }

    private func chooseBackgroundImage() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self, let file = try? Data(contentsOf: url),
                  let (data, type) = MediaItem.storable(file) else { return }
            let ids = self.controller.selectedSlideIDs
            self.controller.perform("Change Background") { presentation in
                let id = presentation.addMedia(data, contentType: type)
                for index in presentation.slides.indices where ids.contains(presentation.slides[index].id) {
                    presentation.slides[index].background = .picture(PictureFill(mediaID: id))
                }
            }
        }
    }

    func ppApplyLayout(_ sender: Any?) {
        finishEditing()
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return }
        controller.applyLayout(id)
    }

    func ppChangeTheme(_ sender: Any?) { showSidebar(.themes) }

    // MARK: Arrange

    func ppOrder(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag else { return }
        let changes: [OrderChange] = [.bringToFront, .bringForward, .sendBackward, .sendToBack]
        guard changes.indices.contains(tag) else { return }
        controller.changeOrder(changes[tag])
    }

    func ppArrangeAlign(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag else { return }
        let edges: [AlignEdge] = [.left, .center, .right, .top, .middle, .bottom]
        guard edges.indices.contains(tag) else { return }
        controller.align(edges[tag])
    }

    func ppDistribute(_ sender: Any?) { controller.distribute(horizontally: (sender as? NSMenuItem)?.tag == 0) }
    func ppCenterOnPage(_ sender: Any?) { controller.centerOnPage(horizontally: (sender as? NSMenuItem)?.tag == 0) }
    func ppRotate(_ sender: Any?) { controller.rotateSelection(by: Double((sender as? NSMenuItem)?.tag ?? 90)) }
    func ppFlip(_ sender: Any?) { controller.flipSelection(horizontal: (sender as? NSMenuItem)?.tag == 0) }

    func ppGroup(_ sender: Any?) {
        finishEditing()
        controller.groupSelection()
    }

    func ppUngroup(_ sender: Any?) {
        finishEditing()
        controller.ungroupSelection()
    }

    // MARK: Tools and Help

    func ppToggleSpellCheck(_ sender: Any?) {
        let on = !(UserDefaults.standard.object(forKey: "PPSpellCheck") as? Bool ?? true)
        UserDefaults.standard.set(on, forKey: "PPSpellCheck")
        canvas.editor?.textView.isContinuousSpellCheckingEnabled = on
        notes.textView.isContinuousSpellCheckingEnabled = on
    }

    func ppPreferences(_ sender: Any?) {
        presentSheet { dismiss in PreferencesView(dismiss: dismiss) }
    }

    func ppShowShortcuts(_ sender: Any?) {
        presentSheet { dismiss in ShortcutsView(dismiss: dismiss) }
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let result = validateCollaboration(menuItem) { return result }
        if let result = validatePhase3(menuItem) { return result }
        if let result = validateComments(menuItem) { return result }
        if let result = validateFind(menuItem) { return result }
        if let result = validateMedia(menuItem) { return result }
        let hasSlide = controller.currentSlide != nil
        let hasSelection = !controller.selectedElementIDs.isEmpty
        let hasText = canvas.editor != nil || !controller.selectedTextElementIDs.isEmpty || isEditingNotes
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return hasSelection || (hasSlide && (isFilmstripFocused || !hasSelection))
        case #selector(paste(_:)), #selector(SlideCommands.ppPasteWithoutFormatting(_:)):
            return NSPasteboard.general.types?.isEmpty == false
        case #selector(SlideCommands.ppInsertAnimation(_:)):
            return hasSelection
        case #selector(SlideCommands.ppPresenterView(_:)), #selector(SlideCommands.ppShowMotion(_:)):
            return hasSlide
        case #selector(SlideCommands.ppToggleGridView(_:)):
            menuItem.state = isGridView ? .on : .off
        case #selector(SlideCommands.ppDuplicate(_:)), #selector(SlideCommands.ppDuplicateSlide(_:)),
             #selector(SlideCommands.ppDeleteSlide(_:)), #selector(SlideCommands.ppChangeBackground(_:)),
             #selector(SlideCommands.ppStartSlideshow(_:)), #selector(SlideCommands.ppStartSlideshowFromBeginning(_:)):
            return hasSlide
        case #selector(SlideCommands.ppSkipSlide(_:)):
            menuItem.title = controller.selectedSlidesAreSkipped ? "Unskip slide" : "Skip slide"
            return hasSlide
        case #selector(SlideCommands.ppMoveSlide(_:)):
            return menuItem.tag < 2 ? controller.canMoveSlidesUp : controller.canMoveSlidesDown
        case #selector(SlideCommands.ppToggleSpeakerNotes(_:)):
            menuItem.state = state.showsSpeakerNotes ? .on : .off
        case #selector(SlideCommands.ppZoomFit(_:)):
            menuItem.state = state.zoomIsFit ? .on : .off
        case #selector(SlideCommands.ppSetZoom(_:)):
            menuItem.state = !state.zoomIsFit && abs(canvasScroll.zoom * 100 - CGFloat(menuItem.tag)) < 0.5 ? .on : .off
        case #selector(SlideCommands.ppToggleBold(_:)):
            menuItem.state = state.text.bold && hasText ? .on : .off
            return hasText
        case #selector(SlideCommands.ppToggleItalic(_:)):
            menuItem.state = state.text.italic && hasText ? .on : .off
            return hasText
        case #selector(SlideCommands.ppToggleUnderline(_:)):
            menuItem.state = state.text.underline && hasText ? .on : .off
            return hasText
        case #selector(SlideCommands.ppToggleStrikethrough(_:)), #selector(SlideCommands.ppSuperscript(_:)),
             #selector(SlideCommands.ppSubscript(_:)), #selector(SlideCommands.ppIncreaseFontSize(_:)),
             #selector(SlideCommands.ppDecreaseFontSize(_:)), #selector(SlideCommands.ppSetFont(_:)),
             #selector(SlideCommands.ppTextAlign(_:)), #selector(SlideCommands.ppIncreaseIndent(_:)),
             #selector(SlideCommands.ppDecreaseIndent(_:)), #selector(SlideCommands.ppLineSpacing(_:)),
             #selector(SlideCommands.ppParagraphSpacing(_:)), #selector(SlideCommands.ppBulletedList(_:)),
             #selector(SlideCommands.ppNumberedList(_:)), #selector(SlideCommands.ppClearFormatting(_:)),
             #selector(SlideCommands.ppInsertLink(_:)), #selector(SlideCommands.ppVerticalAlign(_:)), #selector(SlideCommands.ppMoreFonts(_:)):
            return hasText && !isEditingNotes
        case #selector(SlideCommands.ppOrder(_:)), #selector(SlideCommands.ppRotate(_:)), #selector(SlideCommands.ppFlip(_:)),
             #selector(SlideCommands.ppCenterOnPage(_:)), #selector(SlideCommands.ppArrangeAlign(_:)), #selector(SlideCommands.ppAltText(_:)),
             #selector(SlideCommands.ppBorderWeight(_:)), #selector(SlideCommands.ppBorderDash(_:)):
            return hasSelection
        case #selector(SlideCommands.ppLineStart(_:)), #selector(SlideCommands.ppLineEnd(_:)):
            return controller.selectedElements.contains { $0.isLine }
        case #selector(SlideCommands.ppDistribute(_:)):
            return controller.selectedElementIDs.count >= 3
        case #selector(SlideCommands.ppGroup(_:)):
            return controller.canGroup
        case #selector(SlideCommands.ppUngroup(_:)):
            return controller.canUngroup
        case #selector(SlideCommands.ppInsertImage(_:)), #selector(SlideCommands.ppInsertTextBox(_:)),
             #selector(SlideCommands.ppInsertShape(_:)), #selector(SlideCommands.ppInsertLine(_:)), #selector(SlideCommands.ppSlideNumbers(_:)):
            return hasSlide
        case #selector(SlideCommands.ppToggleSpellCheck(_:)):
            menuItem.state = UserDefaults.standard.object(forKey: "PPSpellCheck") as? Bool ?? true ? .on : .off
        case #selector(SlideCommands.ppApplyLayout(_:)):
            return hasSlide
        default:
            break
        }
        return true
    }

    // MARK: Context menus

    private func add(_ items: [NSMenuItem], to menu: NSMenu) {
        for item in items {
            if item.action != nil, item.target == nil { item.target = self }
            item.submenu?.items.forEach { if $0.action != nil, $0.target == nil { $0.target = self } }
            menu.addItem(item)
        }
    }

    func canvasMenu(for element: SlideElement?) -> NSMenu {
        let menu = NSMenu()
        add([
            MenuBuilder.item("Cut", #selector(cut(_:)), symbol: "scissors"),
            MenuBuilder.item("Copy", #selector(copy(_:)), symbol: "doc.on.doc"),
            MenuBuilder.item("Paste", #selector(paste(_:)), symbol: "doc.on.clipboard"),
            MenuBuilder.item("Paste without formatting", #selector(SlideCommands.ppPasteWithoutFormatting(_:))),
        ], to: menu)
        if element != nil {
            add([MenuBuilder.item("Delete", #selector(delete(_:)), symbol: "trash"), .separator()], to: menu)
            // Object-specific items come first: table rows and columns, image tools, the chart editor.
            if element?.table != nil { add(MenuBuilder.tableCommandItems() + [.separator()], to: menu) }
            if element?.picture != nil {
                add([MenuBuilder.item("Crop image", #selector(SlideCommands.ppCropImage(_:)), symbol: "crop"),
                     MenuBuilder.submenu("Mask image", MenuBuilder.maskItems()),
                     MenuBuilder.item("Reset image", #selector(SlideCommands.ppResetImage(_:)), symbol: "arrow.counterclockwise"),
                     MenuBuilder.item("Replace image…", #selector(SlideCommands.ppReplaceImage(_:)), symbol: "photo.on.rectangle"),
                     .separator()], to: menu)
            }
            if element?.chart != nil { add([MenuBuilder.item("Edit chart", #selector(SlideCommands.ppEditChart(_:)), symbol: "chart.bar"), .separator()], to: menu) }
            if element?.media != nil { add([MenuBuilder.item("Play", #selector(SlideCommands.ppPlayClip(_:)), symbol: "play"), .separator()], to: menu) }
            add([
                MenuBuilder.submenu("Order", [
                    MenuBuilder.item("Bring to front", #selector(SlideCommands.ppOrder(_:)), tag: 0),
                    MenuBuilder.item("Bring forward", #selector(SlideCommands.ppOrder(_:)), tag: 1),
                    MenuBuilder.item("Send backward", #selector(SlideCommands.ppOrder(_:)), tag: 2),
                    MenuBuilder.item("Send to back", #selector(SlideCommands.ppOrder(_:)), tag: 3),
                ]),
                MenuBuilder.submenu("Rotate", [
                    MenuBuilder.item("Rotate clockwise 90°", #selector(SlideCommands.ppRotate(_:)), tag: 90),
                    MenuBuilder.item("Rotate counter-clockwise 90°", #selector(SlideCommands.ppRotate(_:)), tag: -90),
                    MenuBuilder.item("Flip horizontally", #selector(SlideCommands.ppFlip(_:)), tag: 0),
                    MenuBuilder.item("Flip vertically", #selector(SlideCommands.ppFlip(_:)), tag: 1),
                ]),
                MenuBuilder.submenu("Center on page", [
                    MenuBuilder.item("Horizontally", #selector(SlideCommands.ppCenterOnPage(_:)), tag: 0),
                    MenuBuilder.item("Vertically", #selector(SlideCommands.ppCenterOnPage(_:)), tag: 1),
                ]),
            ], to: menu)
            if controller.canGroup { add([MenuBuilder.item("Group", #selector(SlideCommands.ppGroup(_:)))], to: menu) }
            if controller.canUngroup { add([MenuBuilder.item("Ungroup", #selector(SlideCommands.ppUngroup(_:)))], to: menu) }
            add([
                .separator(),
                MenuBuilder.item("Comment", #selector(SlideCommands.ppInsertComment(_:)), symbol: "text.bubble"),
                .separator(),
                MenuBuilder.item("Format options", #selector(SlideCommands.ppFormatOptions(_:))),
                MenuBuilder.item("Alt text", #selector(SlideCommands.ppAltText(_:))),
            ], to: menu)
        } else {
            add([
                .separator(),
                MenuBuilder.item("Comment", #selector(SlideCommands.ppInsertComment(_:)), symbol: "text.bubble"),
                .separator(),
                MenuBuilder.item("Change background", #selector(SlideCommands.ppChangeBackground(_:))),
            ], to: menu)
            let layouts = MenuBuilder.submenu("Apply layout", layoutMenuItems(action: #selector(SlideCommands.ppApplyLayout(_:)), checkCurrent: true))
            add([layouts, MenuBuilder.item("Change theme", #selector(SlideCommands.ppChangeTheme(_:)))], to: menu)
        }
        return menu
    }

    func filmstripMenu(at index: Int?) -> NSMenu {
        let menu = NSMenu()
        if controller.isThemeBuilderOpen {
            // The theme builder's pages: layouts can be copied, renamed and (when unused) deleted.
            if index != nil {
                let rename = MenuBuilder.item(controller.isEditingMaster ? "Rename theme" : "Rename layout", #selector(SlideCommands.ppEditTheme(_:)))
                rename.action = #selector(renameBuilderPageFromMenu(_:))
                rename.target = self
                add([MenuBuilder.item("Duplicate layout", #selector(SlideCommands.ppDuplicateSlide(_:))),
                     MenuBuilder.item("Delete layout", #selector(SlideCommands.ppDeleteSlide(_:))), rename, .separator(),
                     MenuBuilder.item("Change background", #selector(SlideCommands.ppChangeBackground(_:)))], to: menu)
            }
            return menu
        }
        add([MenuBuilder.item("New slide", #selector(SlideCommands.ppNewSlide(_:)))], to: menu)
        if index != nil {
            add([
                MenuBuilder.item("Cut", #selector(cut(_:))),
                MenuBuilder.item("Copy", #selector(copy(_:))),
                MenuBuilder.item("Paste", #selector(paste(_:))),
                MenuBuilder.item("Delete", #selector(delete(_:))),
                MenuBuilder.item("Duplicate slide", #selector(SlideCommands.ppDuplicateSlide(_:))),
                MenuBuilder.item(controller.selectedSlidesAreSkipped ? "Unskip slide" : "Skip slide", #selector(SlideCommands.ppSkipSlide(_:))),
                .separator(),
                MenuBuilder.item("Change background", #selector(SlideCommands.ppChangeBackground(_:))),
                MenuBuilder.submenu("Apply layout", layoutMenuItems(action: #selector(SlideCommands.ppApplyLayout(_:)), checkCurrent: true)),
                MenuBuilder.item("Change theme", #selector(SlideCommands.ppChangeTheme(_:))),
                .separator(),
                MenuBuilder.item("Move slide to beginning", #selector(SlideCommands.ppMoveSlide(_:)), tag: 0),
                MenuBuilder.item("Move slide to end", #selector(SlideCommands.ppMoveSlide(_:)), tag: 3),
            ], to: menu)
        } else {
            add([MenuBuilder.item("Paste", #selector(paste(_:)))], to: menu)
        }
        return menu
    }
}
