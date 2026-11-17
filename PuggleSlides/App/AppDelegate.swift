import AppKit
import PuggleSlidesKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MenuBuilder.makeMainMenu()
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugLaunchOptions.runIfRequested()
        SelfTest.runIfRequested()
        #endif
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showAboutWindow(_ sender: Any?) { AboutWindowController.show() }
}

#if DEBUG
/// Launch arguments used during development to check rendering without manual interaction:
/// `-PPSampleDocument YES` fills new presentations with sample slides, and
/// `-PPSnapshot <file name>` writes a PNG of the first window to the app's temporary folder and quits.
enum DebugLaunchOptions {
    static var wantsSample: Bool { UserDefaults.standard.bool(forKey: "PPSampleDocument") }
    /// The window `-PPOpenFile` opened, which the other options then act on.
    static var openedWindow: DocumentWindowController?

    /// `-PPBenchmark YES`: a 300-slide deck, timed for drawing slides and thumbnails and for editing.
    static func runBenchmark() {
        guard UserDefaults.standard.bool(forKey: "PPBenchmark") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let window = NSApp.windows.compactMap({ $0.windowController as? DocumentWindowController }).first,
                  let document = window.presentationDocument else { return }
            let sample = SampleContent.make()
            var presentation = sample
            presentation.slides = (0..<300).map { presentation.duplicate(sample.slides[$0 % sample.slides.count]) }
            document.presentation = presentation
            window.controller.reloadFromDocument()
            let start = Date()
            for slide in presentation.slides.prefix(60) {
                _ = SlideRenderer.image(of: slide, in: presentation, size: CGSize(width: 158, height: 89))
            }
            print(String(format: "BENCHMARK: 60 thumbnails: %.1f ms each", Date().timeIntervalSince(start) * 1000 / 60))
            let drawStart = Date()
            for index in 0..<30 {
                window.controller.selectSlide(presentation.slides[index].id)
                window.canvas.display()
            }
            print(String(format: "BENCHMARK: canvas: %.1f ms per slide", Date().timeIntervalSince(drawStart) * 1000 / 30))
            let editStart = Date()
            window.controller.newSlide()
            print(String(format: "BENCHMARK: new slide with undo: %.1f ms", Date().timeIntervalSince(editStart) * 1000))
            fflush(stdout)
            exit(0)
        }
    }

    static func runIfRequested() {
        runBenchmark()
        // `-PPOpenFile name.pptx`: opens a file from the app's temporary folder.
        if let file = UserDefaults.standard.string(forKey: "PPOpenFile") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
                if let error { print("PPOpenFile: \(error.localizedDescription)") }
                if let document = document as? PresentationDocument {
                    print("PPOpenFile: \(document.presentation.slides.count) slides, warnings \(document.importWarnings.map(\.rawValue).sorted())")
                    openedWindow = document.windowControllers.first as? DocumentWindowController
                }
            }
        }
        guard let name = UserDefaults.standard.string(forKey: "PPSnapshot") else { return }
        let defaults = UserDefaults.standard
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let controller = openedWindow ?? NSApp.windows.compactMap({ $0.windowController as? DocumentWindowController }).first else { return }
            let width = defaults.double(forKey: "PPWindowWidth"), height = defaults.double(forKey: "PPWindowHeight")
            if width > 0 || height > 0, let window = controller.window {
                window.setContentSize(NSSize(width: width > 0 ? width : window.contentLayoutRect.width,
                                             height: height > 0 ? height : window.contentLayoutRect.height))
            }
            let slide = defaults.integer(forKey: "PPSlide")
            if slide > 0, controller.controller.presentation.slides.indices.contains(slide - 1) {
                controller.controller.selectSlide(controller.controller.presentation.slides[slide - 1].id)
            }
            let zoom = defaults.double(forKey: "PPZoom")
            if zoom > 0 { controller.setZoom(zoom) }
            if let element = defaults.object(forKey: "PPSelect") as? String, let index = Int(element),
               let slide = controller.controller.currentSlide, slide.elements.indices.contains(index - 1) {
                controller.controller.selectElements([slide.elements[index - 1].id])
                if defaults.bool(forKey: "PPEditText") {
                    controller.canvas.beginEditing(slide.elements[index - 1].id, at: nil)
                    controller.canvas.editor?.textView.selectAll(nil)
                }
            }
            if defaults.bool(forKey: "PPHideNotes") {
                controller.state.showsSpeakerNotes = false
                controller.applyNotesVisibility()
            }
            if let name = defaults.string(forKey: "PPTheme"), let design = BuiltInThemes.designs.first(where: { $0.name == name }) {
                controller.controller.applyTheme(BuiltInThemes.make(design, slideSize: controller.controller.presentation.slideSize))
            }
            if let name = defaults.string(forKey: "PPWriteFile"), let format = PresentationFormat(typeName: (name as NSString).pathExtension) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try PresentationIO.write(controller.controller.presentation, format: format).write(to: url)
                    print("PPWriteFile: wrote \(url.path)")
                } catch {
                    print("PPWriteFile: failed \(error)")
                }
            }
            // `-PPDownload pdf,svg`: writes each File ▸ Download format to download.<extension> in the temporary folder.
            for name in (defaults.string(forKey: "PPDownload") ?? "").split(separator: ",") {
                guard let format = DownloadFormat.allCases.first(where: { $0.fileExtension == name }) else { continue }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("download.\(name)")
                do {
                    try controller.downloadData(format).write(to: url)
                    print("PPDownload: wrote \(url.path)")
                } catch {
                    print("PPDownload: \(name) failed \(error)")
                }
            }
            // `-PPPrintLayout notes|handout6 -PPPrintLandscape YES`: the print preview's starting settings.
            if let layout = defaults.string(forKey: "PPPrintLayout") {
                if layout == "notes" { controller.printSettings.layout = .slidesWithNotes }
                if layout.hasPrefix("handout"), let count = Int(layout.dropFirst(7)) { controller.printSettings.layout = .handout(count) }
                controller.printSettings.landscape = defaults.bool(forKey: "PPPrintLandscape")
            }
            switch defaults.string(forKey: "PPSidebar") {
            case "themes": controller.showSidebar(.themes)
            case "formatOptions": controller.showSidebar(.formatOptions)
            case "chartEditor": controller.showSidebar(.chartEditor)
            case "comments": controller.showSidebar(.comments)
            default: break
            }
            switch defaults.string(forKey: "PPOpenSheet") {
            case "shortcuts": controller.ppShowShortcuts(nil)
            case "background": controller.showBackgroundDialog()
            case "pageSetup": controller.ppPageSetup(nil)
            case "slideNumbers": controller.ppSlideNumbers(nil)
            case "link": controller.showLinkEditor()
            case "shapes": controller.presentSheet { dismiss in ShapeGalleryView { _ in dismiss() } }
            case "print": controller.ppPrintSettings(nil)
            default: break
            }
            if let menu = defaults.string(forKey: "PPToolbarMenu") {
                // Opening a menu blocks, so only its contents are printed.
                let kinds: [String: ToolbarMenu] = ["layouts": .applyLayout, "zoom": .zoom, "lines": .lines]
                if let kind = kinds[menu] { print("PPToolbarMenu: \(ToolbarMenus.make(kind, controller: controller).items.map(\.title))") }
            }
            if defaults.bool(forKey: "PPPresent") || defaults.bool(forKey: "PPPresenterView") {
                controller.startSlideshow(fromBeginning: false, presenterView: defaults.bool(forKey: "PPPresenterView"))
                if let show = SlideshowController.current {
                    // `-PPFreezeMotion 0.5` stops transitions and animations halfway; `-PPAdvance 2` presses Next twice.
                    let freeze = defaults.double(forKey: "PPFreezeMotion")
                    if freeze > 0 { show.frozenProgress = freeze }
                    for _ in 0..<defaults.integer(forKey: "PPAdvance") { show.next() }
                }
            }
            if defaults.bool(forKey: "PPMotionPanel") { controller.showSidebar(.motion) }
            if defaults.bool(forKey: "PPThemeBuilder") {
                controller.controller.openThemeBuilder()
                if defaults.bool(forKey: "PPThemeColors") { controller.showSidebar(.themeColors) }
            }
            // `-PPAddGuides YES` adds a vertical and a horizontal guide; `-PPCrop YES` crops the selected picture;
            // `-PPCellRange 0,0,1,2` selects table cells; `-PPEditCell 1,1` types into a cell.
            if defaults.bool(forKey: "PPAddGuides") {
                let size = controller.controller.presentation.slideSize
                controller.controller.setGuides([Guide(orientation: .vertical, position: size.width / 3), Guide(orientation: .horizontal, position: size.height * 0.75)])
            }
            // `-PPComments YES` adds a thread about the selected object, with a reply, and one about the slide;
            // `-PPCommentDraft YES` opens Insert ▸ Comment.
            if defaults.bool(forKey: "PPComments"), let slideID = controller.controller.currentSlideID {
                let editor = controller.controller
                if let thread = editor.addComment("Can we make this bigger?", about: editor.selectedElementIDs.first, onSlide: slideID) {
                    editor.replyToComment(thread, text: "Sure, I’ll fix it.")
                }
                editor.addComment("Love this slide.", about: nil, onSlide: slideID)
            }
            if defaults.bool(forKey: "PPCommentDraft") { controller.ppInsertComment(nil) }
            // `-PPFind text` opens Find and replace looking for the text; `-PPFindNext 2` presses Next twice.
            if let text = defaults.string(forKey: "PPFind") {
                controller.findState.query = text
                controller.showFindReplace()
                for _ in 0..<defaults.integer(forKey: "PPFindNext") { controller.findNext(forward: true) }
            }
            if defaults.bool(forKey: "PPCrop"), let picture = controller.controller.selectedPicture {
                controller.canvas.beginCropping(picture.id)
                if let session = controller.canvas.cropping {
                    // Show a crop in progress: a little off the left and the top.
                    let visible = session.visible
                    controller.canvas.cropping?.visible = CGRect(x: visible.width * 0.15, y: visible.height * 0.1, width: visible.width * 0.85,
                                                                 height: visible.height * 0.9)
                }
            }
            if let text = defaults.string(forKey: "PPCellRange"), let table = controller.controller.selectedTableElement {
                let numbers = text.split(separator: ",").compactMap { Int($0) }
                if numbers.count == 4 {
                    controller.controller.tableSelection = TableCellRange(firstRow: numbers[0], firstColumn: numbers[1], lastRow: numbers[2], lastColumn: numbers[3])
                    controller.refreshState()
                    controller.canvas.needsDisplay = true
                }
                _ = table
            }
            if let text = defaults.string(forKey: "PPEditCell"), let table = controller.controller.selectedTableElement {
                let numbers = text.split(separator: ",").compactMap { Int($0) }
                if numbers.count == 2 { controller.canvas.beginEditingCell(table.id, row: numbers[0], column: numbers[1], at: nil) }
            }
            if defaults.bool(forKey: "PPGridView") { controller.setGridView(true) }
            if defaults.bool(forKey: "PPShowAbout"), let appMenu = NSApp.mainMenu?.items.first?.submenu {
                appMenu.performActionForItem(at: appMenu.indexOfItem(withTitle: "About PuggleSlides"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let presenter = defaults.bool(forKey: "PPPresenterView") ? NSApp.windows.first { $0 is PresenterPanel && $0.isVisible } : nil
            let slideshow = presenter ?? NSApp.windows.first { $0 is SlideshowWindow && $0.isVisible }
            guard let documentWindow = openedWindow?.window ?? NSApp.windows.first(where: { $0.windowController is DocumentWindowController }),
                  case let about = NSApp.windows.first(where: { $0.windowController is AboutWindowController && $0.isVisible }),
                  case let panel = defaults.bool(forKey: "PPSnapshotPanel") ? documentWindow.childWindows?.first : nil,
                  case let window = slideshow ?? about ?? documentWindow.attachedSheet ?? panel ?? documentWindow,
                  let view = window.contentView?.superview ?? window.contentView else {
                print("PPSnapshot: no document window")
                NSApp.terminate(nil)
                return
            }
            print("PPSnapshot: window=\(window.frame.size)")
            let bounds = view.bounds
            if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
                view.cacheDisplay(in: bounds, to: rep)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("PPSnapshot: \(url.path)")
            }
            // Exit directly: quitting normally would wait on any open sheet or unsaved-changes prompt.
            NSApp.presentationOptions = []
            fflush(stdout)
            exit(0)
        }
    }
}
#endif
