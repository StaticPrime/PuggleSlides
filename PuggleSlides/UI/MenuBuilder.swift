import AppKit
import PuggleSlidesKit

/// Actions implemented by `DocumentWindowController` and reached through the responder chain.
@objc protocol SlideCommands {
    // Video and audio.
    func ppInsertVideo(_ sender: Any?)
    func ppInsertAudio(_ sender: Any?)
    func ppPlayClip(_ sender: Any?)
    // Phase 4: comments.
    func ppInsertComment(_ sender: Any?)
    func ppShowCommentHistory(_ sender: Any?)
    func ppToggleComments(_ sender: Any?)
    // Phase 4: moving focus with keyboard shortcuts.
    func ppFocusFilmstrip(_ sender: Any?)
    func ppFocusCanvas(_ sender: Any?)
    func ppFocusSpeakerNotes(_ sender: Any?)
    // Phase 4: find and replace.
    func ppFind(_ sender: Any?)
    func ppFindAndReplace(_ sender: Any?)
    func ppFindNext(_ sender: Any?)
    func ppFindPrevious(_ sender: Any?)
    // Phase 3: tables, charts, word art, images, guides and imports.
    func ppInsertTable(_ sender: Any?)
    func ppInsertChart(_ sender: Any?)
    func ppInsertWordArt(_ sender: Any?)
    func ppTableCommand(_ sender: Any?)
    func ppTableBorderPosition(_ sender: Any?)
    func ppCropImage(_ sender: Any?)
    func ppMaskImage(_ sender: Any?)
    func ppResetImage(_ sender: Any?)
    func ppReplaceImage(_ sender: Any?)
    func ppEditChart(_ sender: Any?)
    func ppSnapToGrid(_ sender: Any?)
    func ppSnapToGuides(_ sender: Any?)
    func ppShowRuler(_ sender: Any?)
    func ppShowGuides(_ sender: Any?)
    func ppAddGuide(_ sender: Any?)
    func ppEditGuides(_ sender: Any?)
    func ppClearGuides(_ sender: Any?)
    func ppImportSlides(_ sender: Any?)
    func ppEditTheme(_ sender: Any?)
    func ppInsertPlaceholder(_ sender: Any?)
    func ppDownload(_ sender: Any?)
    func ppPrintSettings(_ sender: Any?)
    func ppPrint(_ sender: Any?)
    func ppRename(_ sender: Any?)
    func ppPageSetup(_ sender: Any?)
    func ppPasteWithoutFormatting(_ sender: Any?)
    func ppDuplicate(_ sender: Any?)
    func ppSelectNone(_ sender: Any?)
    func ppStartSlideshow(_ sender: Any?)
    func ppStartSlideshowFromBeginning(_ sender: Any?)
    func ppPresenterView(_ sender: Any?)
    func ppShowMotion(_ sender: Any?)
    func ppToggleGridView(_ sender: Any?)
    func ppInsertAnimation(_ sender: Any?)
    func ppToggleSpeakerNotes(_ sender: Any?)
    func ppZoomIn(_ sender: Any?)
    func ppZoomOut(_ sender: Any?)
    func ppZoomFit(_ sender: Any?)
    func ppSetZoom(_ sender: Any?)
    func ppInsertImage(_ sender: Any?)
    func ppInsertTextBox(_ sender: Any?)
    func ppInsertShape(_ sender: Any?)
    func ppInsertLine(_ sender: Any?)
    func ppInsertLink(_ sender: Any?)
    func ppSlideNumbers(_ sender: Any?)
    func ppToggleBold(_ sender: Any?)
    func ppToggleItalic(_ sender: Any?)
    func ppToggleUnderline(_ sender: Any?)
    func ppToggleStrikethrough(_ sender: Any?)
    func ppSuperscript(_ sender: Any?)
    func ppSubscript(_ sender: Any?)
    func ppIncreaseFontSize(_ sender: Any?)
    func ppDecreaseFontSize(_ sender: Any?)
    func ppSetFont(_ sender: Any?)
    func ppMoreFonts(_ sender: Any?)
    func ppTextAlign(_ sender: Any?)
    func ppVerticalAlign(_ sender: Any?)
    func ppIncreaseIndent(_ sender: Any?)
    func ppDecreaseIndent(_ sender: Any?)
    func ppLineSpacing(_ sender: Any?)
    func ppParagraphSpacing(_ sender: Any?)
    func ppBulletedList(_ sender: Any?)
    func ppNumberedList(_ sender: Any?)
    func ppFormatOptions(_ sender: Any?)
    func ppAltText(_ sender: Any?)
    func ppClearFormatting(_ sender: Any?)
    func ppBorderWeight(_ sender: Any?)
    func ppBorderDash(_ sender: Any?)
    func ppLineStart(_ sender: Any?)
    func ppLineEnd(_ sender: Any?)
    func ppNewSlide(_ sender: Any?)
    func ppNewSlideWithLayout(_ sender: Any?)
    func ppDuplicateSlide(_ sender: Any?)
    func ppDeleteSlide(_ sender: Any?)
    func ppSkipSlide(_ sender: Any?)
    func ppMoveSlide(_ sender: Any?)
    func ppChangeBackground(_ sender: Any?)
    func ppApplyLayout(_ sender: Any?)
    func ppChangeTheme(_ sender: Any?)
    func ppOrder(_ sender: Any?)
    func ppArrangeAlign(_ sender: Any?)
    func ppDistribute(_ sender: Any?)
    func ppCenterOnPage(_ sender: Any?)
    func ppRotate(_ sender: Any?)
    func ppFlip(_ sender: Any?)
    func ppGroup(_ sender: Any?)
    func ppUngroup(_ sender: Any?)
    func ppToggleSpellCheck(_ sender: Any?)
    func ppPreferences(_ sender: Any?)
    func ppShowShortcuts(_ sender: Any?)
    // Sharing through iCloud.
    func ppCollaborate(_ sender: Any?)
    func ppLeaveShared(_ sender: Any?)
}

/// The responder chain's undo and redo actions (handled by windows and text views), named for `#selector`.
@objc protocol UndoCommands {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

/// File ▸ Download: the formats, in menu order.
enum DownloadFormat: Int, CaseIterable {
    case pptx, odp, pdf, txt, jpg, png, svg

    var title: String {
        switch self {
        case .pptx: "Microsoft PowerPoint (.pptx)"
        case .odp: "ODP Document (.odp)"
        case .pdf: "PDF Document (.pdf)"
        case .txt: "Plain Text (.txt)"
        case .jpg: "JPEG image (.jpg, current slide)"
        case .png: "PNG image (.png, current slide)"
        case .svg: "Scalable Vector Graphics (.svg, current slide)"
        }
    }

    var fileExtension: String {
        switch self {
        case .pptx: "pptx"
        case .odp: "odp"
        case .pdf: "pdf"
        case .txt: "txt"
        case .jpg: "jpg"
        case .png: "png"
        case .svg: "svg"
        }
    }

    /// Image formats download only the current slide.
    var isCurrentSlide: Bool { self == .jpg || self == .png || self == .svg }
}

enum MenuKind: String, CaseIterable {
    case file = "File", edit = "Edit", view = "View", insert = "Insert", format = "Format", slide = "Slide", arrange = "Arrange"
    case tools = "Tools", help = "Help"
}

enum MenuBuilder {
    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                     tag: Int = 0, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    static func submenu(_ title: String, symbol: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    static func represented(_ item: NSMenuItem, _ object: Any) -> NSMenuItem {
        item.representedObject = object
        return item
    }

    static let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    static let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)

    static func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "Main")
        let appItem = NSMenuItem()
        appItem.submenu = makeAppMenu()
        main.addItem(appItem)
        for kind in MenuKind.allCases where kind != .help {
            let item = NSMenuItem(title: kind.rawValue, action: nil, keyEquivalent: "")
            item.submenu = makeMenu(kind)
            main.addItem(item)
        }
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = makeWindowMenu()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = makeMenu(.help)
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu
        return main
    }

    static func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: "PuggleSlides")
        menu.addItem(item("About PuggleSlides", #selector(AppDelegate.showAboutWindow(_:))))
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item("Hide PuggleSlides", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit PuggleSlides", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    static func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    static func makeMenu(_ kind: MenuKind) -> NSMenu {
        let menu = NSMenu(title: kind.rawValue)
        let items: [NSMenuItem] = switch kind {
        case .file: fileItems()
        case .edit: editItems()
        case .view: viewItems()
        case .insert: insertItems()
        case .format: formatItems()
        case .slide: slideItems()
        case .arrange: arrangeItems()
        case .tools: toolsItems()
        case .help: [item("Keyboard shortcuts", #selector(SlideCommands.ppShowShortcuts(_:)), "/", symbol: "keyboard")]
        }
        items.forEach(menu.addItem)
        if kind == .slide { menu.delegate = LayoutMenuDelegate.shared }
        return menu
    }

    static func downloadItems() -> [NSMenuItem] {
        DownloadFormat.allCases.map { format in item(format.title, #selector(SlideCommands.ppDownload(_:)), tag: format.rawValue) }
    }

    /// File ▸ Shared presentations: those shared with this person, and theirs that are shared, filled in as it opens.
    private static func sharedPresentationsMenu() -> NSMenuItem {
        let item = submenu("Shared presentations", symbol: "person.2.circle", [])
        item.submenu?.delegate = SharedPresentationsMenu.shared
        return item
    }

    private static func fileItems() -> [NSMenuItem] {
        [
            item("New presentation", #selector(NSDocumentController.newDocument(_:)), "n", symbol: "plus.square"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o", symbol: "folder"),
            item("Import slides…", #selector(SlideCommands.ppImportSlides(_:)), symbol: "square.and.arrow.down.on.square"),
            .separator(),
            item("Make a copy", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift], symbol: "plus.square.on.square"),
            .separator(),
            item("Collaborate…", #selector(SlideCommands.ppCollaborate(_:)), "c", [.command, .option], symbol: "person.2"),
            item("Leave shared presentation…", #selector(SlideCommands.ppLeaveShared(_:)), symbol: "rectangle.portrait.and.arrow.right"),
            sharedPresentationsMenu(),
            .separator(),
            item("Save", #selector(NSDocument.save(_:)), "s", symbol: "square.and.arrow.down"),
            submenu("Download", symbol: "arrow.down.to.line", downloadItems()),
            item("Rename", #selector(SlideCommands.ppRename(_:)), symbol: "pencil"),
            item("Move…", #selector(NSDocument.move(_:)), symbol: "folder.badge.gearshape"),
            .separator(),
            submenu("Version history", symbol: "clock.arrow.circlepath", [
                item("See version history", #selector(NSDocument.browseVersions(_:))),
                item("Revert to last saved", #selector(NSDocument.revertToSaved(_:))),
            ]),
            .separator(),
            item("Page setup", #selector(SlideCommands.ppPageSetup(_:)), symbol: "rectangle.ratio.16.to.9"),
            item("Print settings and preview", #selector(SlideCommands.ppPrintSettings(_:)), symbol: "doc.text.magnifyingglass"),
            item("Print", #selector(SlideCommands.ppPrint(_:)), "p", symbol: "printer"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]
    }

    private static func editItems() -> [NSMenuItem] {
        [
            item("Undo", #selector(UndoCommands.undo(_:)), "z", symbol: "arrow.uturn.backward"),
            item("Redo", #selector(UndoCommands.redo(_:)), "z", [.command, .shift], symbol: "arrow.uturn.forward"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x", symbol: "scissors"),
            item("Copy", #selector(NSText.copy(_:)), "c", symbol: "doc.on.doc"),
            item("Paste", #selector(NSText.paste(_:)), "v", symbol: "doc.on.clipboard"),
            item("Paste without formatting", #selector(SlideCommands.ppPasteWithoutFormatting(_:)), "v", [.command, .shift]),
            .separator(),
            item("Select all", #selector(NSResponder.selectAll(_:)), "a"),
            item("Select none", #selector(SlideCommands.ppSelectNone(_:))),
            .separator(),
            item("Delete", #selector(NSText.delete(_:)), symbol: "trash"),
            item("Duplicate", #selector(SlideCommands.ppDuplicate(_:)), "d", symbol: "plus.square.on.square"),
            .separator(),
            item("Find and replace", #selector(SlideCommands.ppFindAndReplace(_:)), "h", [.command, .shift], symbol: "magnifyingglass"),
            submenu("Find", symbol: "text.magnifyingglass", [
                item("Find…", #selector(SlideCommands.ppFind(_:)), "f"),
                item("Find again", #selector(SlideCommands.ppFindNext(_:)), "g"),
                item("Find previous", #selector(SlideCommands.ppFindPrevious(_:)), "g", [.command, .shift]),
            ]),
            .separator(),
            item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]),
        ]
    }

    static func zoomItems() -> [NSMenuItem] {
        [
            item("Fit", #selector(SlideCommands.ppZoomFit(_:))),
            .separator(),
        ] + Theme.zoomLevels.map { level in
            item("\(Int(level * 100))%", #selector(SlideCommands.ppSetZoom(_:)), level == 1 ? "0" : "", tag: Int(level * 100))
        } + [
            .separator(),
            item("Zoom in", #selector(SlideCommands.ppZoomIn(_:)), "="),
            item("Zoom out", #selector(SlideCommands.ppZoomOut(_:)), "-"),
        ]
    }

    private static func viewItems() -> [NSMenuItem] {
        [
            item("Slideshow", #selector(SlideCommands.ppStartSlideshow(_:)), "\r", symbol: "play.rectangle"),
            item("Slideshow from beginning", #selector(SlideCommands.ppStartSlideshowFromBeginning(_:)), "\r", [.command, .shift]),
            item("Presenter view", #selector(SlideCommands.ppPresenterView(_:)), symbol: "rectangle.on.rectangle"),
            item("Motion", #selector(SlideCommands.ppShowMotion(_:)), "b", [.command, .option, .shift], symbol: "wand.and.rays"),
            item("Grid view", #selector(SlideCommands.ppToggleGridView(_:)), "1", [.command, .option], symbol: "square.grid.3x2"),
            item("Theme builder", #selector(SlideCommands.ppEditTheme(_:)), symbol: "paintpalette"),
            .separator(),
            item("Show speaker notes", #selector(SlideCommands.ppToggleSpeakerNotes(_:)), symbol: "note.text"),
            submenu("Comments", symbol: "text.bubble", [
                item("Show comments", #selector(SlideCommands.ppToggleComments(_:)), "j", [.command, .option, .shift]),
                item("Open comment history", #selector(SlideCommands.ppShowCommentHistory(_:)), "a", [.command, .option, .shift]),
            ]),
            submenu("Move to", symbol: "arrow.right.to.line", [
                item("Filmstrip", #selector(SlideCommands.ppFocusFilmstrip(_:)), "f", [.command, .option, .shift]),
                item("Canvas", #selector(SlideCommands.ppFocusCanvas(_:)), "c", [.command, .option, .shift]),
                item("Speaker notes", #selector(SlideCommands.ppFocusSpeakerNotes(_:)), "s", [.command, .option, .shift]),
            ]),
            .separator(),
            submenu("Snap to", symbol: "dot.squareshape", [
                item("Grid", #selector(SlideCommands.ppSnapToGrid(_:))),
                item("Guides", #selector(SlideCommands.ppSnapToGuides(_:))),
            ]),
            submenu("Guides", symbol: "ruler", [
                item("Show guides", #selector(SlideCommands.ppShowGuides(_:))),
                .separator(),
                item("Add vertical guide", #selector(SlideCommands.ppAddGuide(_:)), tag: 0),
                item("Add horizontal guide", #selector(SlideCommands.ppAddGuide(_:)), tag: 1),
                item("Edit guides…", #selector(SlideCommands.ppEditGuides(_:))),
                item("Clear guides", #selector(SlideCommands.ppClearGuides(_:))),
            ]),
            item("Show ruler", #selector(SlideCommands.ppShowRuler(_:)), "r", [.command, .shift], symbol: "ruler"),
            .separator(),
            submenu("Zoom", symbol: "plus.magnifyingglass", zoomItems()),
            .separator(),
            item("Full screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]
    }

    /// The shape menu: Shapes, Arrows, Callouts and Equation.
    static func shapeItems() -> [NSMenuItem] {
        ShapeCategory.allCases.map { category in
            submenu(category.title, PresetGeometry.catalog.filter { $0.category == category }.map { info in
                let menuItem = represented(item(info.title, #selector(SlideCommands.ppInsertShape(_:))), info.name)
                menuItem.image = shapeImage(info.name)
                return menuItem
            })
        }
    }

    static func lineItems() -> [NSMenuItem] {
        LineKind.allCases.enumerated().map { index, kind in
            item(kind.title, #selector(SlideCommands.ppInsertLine(_:)), tag: index, symbol: kind.symbol)
        }
    }

    /// A small outline of a preset, for menus.
    static func shapeImage(_ preset: String) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
            let box = CGRect(x: 1.5, y: 2.5, width: rect.width - 3, height: rect.height - 5)
            let geometry = ShapeGeometry.preset(preset, adjustments: PresetGeometry.defaultAdjustments(preset))
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: box.minX, y: box.minY)
            for part in PresetGeometry.paths(for: geometry, in: CGRect(origin: .zero, size: box.size)) where part.stroke {
                context.addPath(part.path)
            }
            context.setStrokeColor(NSColor.labelColor.cgColor)
            context.setLineWidth(1)
            context.strokePath()
            return true
        }
    }

    private static func insertItems() -> [NSMenuItem] {
        [
            submenu("Image", symbol: "photo", [item("Upload from computer…", #selector(SlideCommands.ppInsertImage(_:)))]),
            item("Text box", #selector(SlideCommands.ppInsertTextBox(_:)), symbol: "character.textbox"),
            item("Audio…", #selector(SlideCommands.ppInsertAudio(_:)), symbol: "speaker.wave.2"),
            item("Video…", #selector(SlideCommands.ppInsertVideo(_:)), symbol: "film"),
            submenu("Shape", symbol: "square.on.circle", shapeItems()),
            tableItem(),
            submenu("Chart", symbol: "chart.bar", chartItems()),
            item("Word art", #selector(SlideCommands.ppInsertWordArt(_:)), symbol: "textformat.characters"),
            submenu("Line", symbol: "line.diagonal", lineItems()),
            .separator(),
            item("Special characters", #selector(NSApplication.orderFrontCharacterPalette(_:)), symbol: "character.textbox"),
            .separator(),
            item("Link", #selector(SlideCommands.ppInsertLink(_:)), "k", symbol: "link"),
            item("Animation", #selector(SlideCommands.ppInsertAnimation(_:)), symbol: "wand.and.rays"),
            item("Comment", #selector(SlideCommands.ppInsertComment(_:)), "m", [.command, .option], symbol: "text.bubble"),
            .separator(),
            item("New slide", #selector(SlideCommands.ppNewSlide(_:)), "m", [.control], symbol: "plus.rectangle"),
            item("Slide numbers", #selector(SlideCommands.ppSlideNumbers(_:)), symbol: "number"),
            submenu("Placeholder", symbol: "rectangle.dashed", [
                item("Title", #selector(SlideCommands.ppInsertPlaceholder(_:)), tag: 0),
                item("Subtitle", #selector(SlideCommands.ppInsertPlaceholder(_:)), tag: 1),
                item("Body", #selector(SlideCommands.ppInsertPlaceholder(_:)), tag: 2),
                item("Slide number", #selector(SlideCommands.ppInsertPlaceholder(_:)), tag: 3),
            ]),
        ]
    }

    /// Insert ▸ Table: a grid of up to 20 × 20 cells.
    static func tableItem() -> NSMenuItem {
        let picker = NSMenuItem(title: "Table grid", action: #selector(SlideCommands.ppInsertTable(_:)), keyEquivalent: "")
        picker.view = TableGridPicker()
        return submenu("Table", symbol: "tablecells", [picker])
    }

    /// Insert ▸ Chart: the four chart types.
    static func chartItems() -> [NSMenuItem] {
        [(ChartKind.bar, "chart.bar.xaxis"), (.column, "chart.bar"), (.line, "chart.xyaxis.line"), (.pie, "chart.pie")].map { kind, symbol in
            item(String(kind.title.dropLast(" chart".count)), #selector(SlideCommands.ppInsertChart(_:)), tag: ChartKind.allCases.firstIndex(of: kind) ?? 0,
                 symbol: symbol)
        }
    }

    /// Table commands; the tag picks the command.
    enum TableCommand: Int, CaseIterable {
        case insertRowAbove, insertRowBelow, insertColumnLeft, insertColumnRight, deleteRow, deleteColumn, deleteTable
        case distributeRows, distributeColumns, mergeCells, unmergeCells

        var title: String {
            switch self {
            case .insertRowAbove: "Insert row above"
            case .insertRowBelow: "Insert row below"
            case .insertColumnLeft: "Insert column left"
            case .insertColumnRight: "Insert column right"
            case .deleteRow: "Delete row"
            case .deleteColumn: "Delete column"
            case .deleteTable: "Delete table"
            case .distributeRows: "Distribute rows"
            case .distributeColumns: "Distribute columns"
            case .mergeCells: "Merge cells"
            case .unmergeCells: "Unmerge cells"
            }
        }
    }

    static func tableCommandItems() -> [NSMenuItem] {
        func command(_ kind: TableCommand) -> NSMenuItem { item(kind.title, #selector(SlideCommands.ppTableCommand(_:)), tag: kind.rawValue) }
        return [command(.insertRowAbove), command(.insertRowBelow), command(.insertColumnLeft), command(.insertColumnRight), .separator(),
                command(.deleteRow), command(.deleteColumn), command(.deleteTable), .separator(),
                command(.distributeRows), command(.distributeColumns), .separator(), command(.mergeCells), command(.unmergeCells)]
    }

    /// Mask image: the shape gallery.
    static func maskItems() -> [NSMenuItem] {
        ShapeCategory.allCases.map { category in
            submenu(category.title, PresetGeometry.catalog.filter { $0.category == category }.map { info in
                let menuItem = represented(item(info.title, #selector(SlideCommands.ppMaskImage(_:))), info.name)
                menuItem.image = shapeImage(info.name)
                return menuItem
            })
        }
    }

    static func alignItems() -> [NSMenuItem] {
        [
            item("Left", #selector(SlideCommands.ppTextAlign(_:)), "l", [.command, .shift], tag: 0, symbol: "text.alignleft"),
            item("Center", #selector(SlideCommands.ppTextAlign(_:)), "e", [.command, .shift], tag: 1, symbol: "text.aligncenter"),
            item("Right", #selector(SlideCommands.ppTextAlign(_:)), "r", [.command, .shift], tag: 2, symbol: "text.alignright"),
            item("Justified", #selector(SlideCommands.ppTextAlign(_:)), "j", [.command, .shift], tag: 3, symbol: "text.justify"),
            .separator(),
            item("Top", #selector(SlideCommands.ppVerticalAlign(_:)), tag: 0, symbol: "align.vertical.top"),
            item("Middle", #selector(SlideCommands.ppVerticalAlign(_:)), tag: 1, symbol: "align.vertical.center"),
            item("Bottom", #selector(SlideCommands.ppVerticalAlign(_:)), tag: 2, symbol: "align.vertical.bottom"),
        ]
    }

    static func lineSpacingItems() -> [NSMenuItem] {
        [("Single", 100), ("1.15", 115), ("1.5", 150), ("Double", 200)].map { title, tag in
            item(title, #selector(SlideCommands.ppLineSpacing(_:)), tag: tag)
        } + [
            .separator(),
            item("Add space before paragraph", #selector(SlideCommands.ppParagraphSpacing(_:)), tag: 1),
            item("Add space after paragraph", #selector(SlideCommands.ppParagraphSpacing(_:)), tag: 2),
            item("Remove space before paragraph", #selector(SlideCommands.ppParagraphSpacing(_:)), tag: 3),
            item("Remove space after paragraph", #selector(SlideCommands.ppParagraphSpacing(_:)), tag: 4),
        ]
    }

    /// The bullet presets, as the first level's bullet.
    static let bulletPresets: [(String, String)] = [("●", "Filled circle"), ("○", "Hollow circle"), ("■", "Square"), ("❖", "Diamond"),
                                                     ("➔", "Arrow"), ("➢", "Arrowhead"), ("✔", "Check mark"), ("★", "Star"), ("-", "Dash")]
    static let numberPresets: [AutoNumberScheme] = [.arabicPeriod, .arabicParenR, .alphaUcPeriod, .alphaLcPeriod, .alphaUcParenR,
                                                    .alphaLcParenR, .romanUcPeriod, .romanLcPeriod]

    static func bulletItems() -> [NSMenuItem] {
        bulletPresets.map { character, name in
            represented(item("\(character)   \(name)", #selector(SlideCommands.ppBulletedList(_:))), character)
        }
    }

    static func numberItems() -> [NSMenuItem] {
        numberPresets.map { scheme in
            let sample = [1, 2, 3].map { scheme.label(for: $0) }.joined(separator: "  ")
            return represented(item(sample, #selector(SlideCommands.ppNumberedList(_:))), scheme.rawValue)
        }
    }

    static let borderWeights: [Double] = [1, 2, 3, 4, 8, 12, 16, 24]

    static func borderWeightItems() -> [NSMenuItem] {
        borderWeights.map { pixels in
            item("\(Int(pixels)) px", #selector(SlideCommands.ppBorderWeight(_:)), tag: Int(pixels))
        }
    }

    static func borderDashItems() -> [NSMenuItem] {
        DashStyle.allCases.enumerated().map { index, dash in item(dash.title, #selector(SlideCommands.ppBorderDash(_:)), tag: index) }
    }

    static func lineEndItems(start: Bool) -> [NSMenuItem] {
        LineEnd.allCases.enumerated().map { index, end in
            item(end.title, start ? #selector(SlideCommands.ppLineStart(_:)) : #selector(SlideCommands.ppLineEnd(_:)), tag: index)
        }
    }

    private static func formatItems() -> [NSMenuItem] {
        [
            submenu("Text", symbol: "bold", [
                item("Bold", #selector(SlideCommands.ppToggleBold(_:)), "b", symbol: "bold"),
                item("Italic", #selector(SlideCommands.ppToggleItalic(_:)), "i", symbol: "italic"),
                item("Underline", #selector(SlideCommands.ppToggleUnderline(_:)), "u", symbol: "underline"),
                item("Strikethrough", #selector(SlideCommands.ppToggleStrikethrough(_:)), "x", [.command, .shift], symbol: "strikethrough"),
                item("Superscript", #selector(SlideCommands.ppSuperscript(_:)), ".", symbol: "textformat.superscript"),
                item("Subscript", #selector(SlideCommands.ppSubscript(_:)), ",", symbol: "textformat.subscript"),
                .separator(),
                submenu("Size", [
                    item("Increase font size", #selector(SlideCommands.ppIncreaseFontSize(_:)), ".", [.command, .shift]),
                    item("Decrease font size", #selector(SlideCommands.ppDecreaseFontSize(_:)), ",", [.command, .shift]),
                ]),
            ]),
            submenu("Align & indent", symbol: "text.alignleft", alignItems() + [
                .separator(),
                item("Increase indent", #selector(SlideCommands.ppIncreaseIndent(_:)), "]", symbol: "increase.indent"),
                item("Decrease indent", #selector(SlideCommands.ppDecreaseIndent(_:)), "[", symbol: "decrease.indent"),
            ]),
            submenu("Line & paragraph spacing", symbol: "arrow.up.and.down.text.horizontal", lineSpacingItems()),
            submenu("Bullets & numbering", symbol: "list.bullet", [
                submenu("Bulleted list", bulletItems()),
                submenu("Numbered list", numberItems()),
                .separator(),
                item("Bulleted list", #selector(SlideCommands.ppBulletedList(_:)), "8", [.command, .shift], symbol: "list.bullet"),
                item("Numbered list", #selector(SlideCommands.ppNumberedList(_:)), "7", [.command, .shift], symbol: "list.number"),
            ]),
            .separator(),
            submenu("Borders & lines", symbol: "pencil.line", [
                submenu("Border weight", borderWeightItems()),
                submenu("Border dash", borderDashItems()),
            ]),
            submenu("Table", symbol: "tablecells", tableCommandItems()),
            submenu("Image", symbol: "photo", [
                item("Crop image", #selector(SlideCommands.ppCropImage(_:)), symbol: "crop"),
                submenu("Mask image", maskItems()),
                item("Reset image", #selector(SlideCommands.ppResetImage(_:)), symbol: "arrow.counterclockwise"),
                item("Replace image…", #selector(SlideCommands.ppReplaceImage(_:)), symbol: "photo.on.rectangle"),
            ]),
            item("Edit chart", #selector(SlideCommands.ppEditChart(_:)), symbol: "chart.bar"),
            .separator(),
            item("Format options", #selector(SlideCommands.ppFormatOptions(_:)), symbol: "slider.horizontal.3"),
            item("Alt text", #selector(SlideCommands.ppAltText(_:)), "y", [.command, .option], symbol: "text.below.photo"),
            .separator(),
            item("Clear formatting", #selector(SlideCommands.ppClearFormatting(_:)), "\\", symbol: "textformat"),
        ]
    }

    private static func slideItems() -> [NSMenuItem] {
        [
            item("New slide", #selector(SlideCommands.ppNewSlide(_:)), "m", [.control], symbol: "plus.rectangle"),
            item("Duplicate slide", #selector(SlideCommands.ppDuplicateSlide(_:)), symbol: "plus.rectangle.on.rectangle"),
            item("Delete slide", #selector(SlideCommands.ppDeleteSlide(_:)), symbol: "trash"),
            item("Skip slide", #selector(SlideCommands.ppSkipSlide(_:)), symbol: "eye.slash"),
            .separator(),
            submenu("Move slide", symbol: "arrow.up.arrow.down", [
                item("Move slide to beginning", #selector(SlideCommands.ppMoveSlide(_:)), tag: 0),
                item("Move slide up", #selector(SlideCommands.ppMoveSlide(_:)), tag: 1),
                item("Move slide down", #selector(SlideCommands.ppMoveSlide(_:)), tag: 2),
                item("Move slide to end", #selector(SlideCommands.ppMoveSlide(_:)), tag: 3),
            ]),
            .separator(),
            item("Change background", #selector(SlideCommands.ppChangeBackground(_:)), symbol: "photo.on.rectangle"),
            submenu("Apply layout", symbol: "rectangle.3.group", []),
            item("Transition", #selector(SlideCommands.ppShowMotion(_:)), symbol: "wand.and.rays"),
            item("Change theme", #selector(SlideCommands.ppChangeTheme(_:)), symbol: "paintpalette"),
            item("Edit theme", #selector(SlideCommands.ppEditTheme(_:)), symbol: "paintbrush"),
        ]
    }

    private static func arrangeItems() -> [NSMenuItem] {
        [
            submenu("Order", symbol: "square.3.layers.3d", [
                item("Bring to front", #selector(SlideCommands.ppOrder(_:)), up, [.command, .shift], tag: 0),
                item("Bring forward", #selector(SlideCommands.ppOrder(_:)), up, [.command], tag: 1),
                item("Send backward", #selector(SlideCommands.ppOrder(_:)), down, [.command], tag: 2),
                item("Send to back", #selector(SlideCommands.ppOrder(_:)), down, [.command, .shift], tag: 3),
            ]),
            submenu("Align", symbol: "align.horizontal.left", [
                item("Left", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 0, symbol: "align.horizontal.left"),
                item("Center", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 1, symbol: "align.horizontal.center"),
                item("Right", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 2, symbol: "align.horizontal.right"),
                .separator(),
                item("Top", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 3, symbol: "align.vertical.top"),
                item("Middle", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 4, symbol: "align.vertical.center"),
                item("Bottom", #selector(SlideCommands.ppArrangeAlign(_:)), tag: 5, symbol: "align.vertical.bottom"),
            ]),
            submenu("Distribute", symbol: "distribute.horizontal.center", [
                item("Horizontally", #selector(SlideCommands.ppDistribute(_:)), tag: 0),
                item("Vertically", #selector(SlideCommands.ppDistribute(_:)), tag: 1),
            ]),
            submenu("Center on page", symbol: "align.horizontal.center", [
                item("Horizontally", #selector(SlideCommands.ppCenterOnPage(_:)), tag: 0),
                item("Vertically", #selector(SlideCommands.ppCenterOnPage(_:)), tag: 1),
            ]),
            submenu("Rotate", symbol: "rotate.right", [
                item("Rotate clockwise 90°", #selector(SlideCommands.ppRotate(_:)), tag: 90),
                item("Rotate counter-clockwise 90°", #selector(SlideCommands.ppRotate(_:)), tag: -90),
                .separator(),
                item("Flip horizontally", #selector(SlideCommands.ppFlip(_:)), tag: 0),
                item("Flip vertically", #selector(SlideCommands.ppFlip(_:)), tag: 1),
            ]),
            .separator(),
            item("Group", #selector(SlideCommands.ppGroup(_:)), "g", [.command, .option], symbol: "rectangle.3.group"),
            item("Ungroup", #selector(SlideCommands.ppUngroup(_:)), "g", [.command, .option, .shift]),
        ]
    }

    private static func toolsItems() -> [NSMenuItem] {
        [
            submenu("Spelling", symbol: "textformat.abc.dottedunderline", [
                item("Spell check", #selector(SlideCommands.ppToggleSpellCheck(_:))),
            ]),
            .separator(),
            item("Preferences…", #selector(SlideCommands.ppPreferences(_:)), symbol: "gearshape"),
        ]
    }
}

/// Fills Slide ▸ Apply layout with the current theme's layouts each time the menu opens.
final class LayoutMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = LayoutMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.title == "Apply layout" }), let submenu = item.submenu else { return }
        submenu.removeAllItems()
        guard let window = NSApp.keyWindow?.windowController as? DocumentWindowController else { return }
        for layoutItem in window.layoutMenuItems(action: #selector(SlideCommands.ppApplyLayout(_:)), checkCurrent: true) {
            submenu.addItem(layoutItem)
        }
    }
}

/// Fills File ▸ Shared presentations each time it opens.
final class SharedPresentationsMenu: NSObject, NSMenuDelegate {
    static let shared = SharedPresentationsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller = CollaborationController.shared else { return }
        let others = controller.sharedWithMe
        let mine = controller.mine
        if case let .unavailable(reason) = controller.status {
            let item = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if !others.isEmpty {
            menu.addItem(sectionHeader("Shared with you"))
            for entry in others {
                let item = NSMenuItem(title: entry.title, action: #selector(open(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id.uuidString
                item.toolTip = entry.ownerName.isEmpty ? nil : "Shared by \(entry.ownerName)"
                item.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        if !mine.isEmpty {
            if !others.isEmpty { menu.addItem(.separator()) }
            menu.addItem(sectionHeader("Shared by you"))
            for (id, title) in mine {
                let item = NSMenuItem(title: title, action: #selector(open(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id.uuidString
                item.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        if others.isEmpty, mine.isEmpty {
            let item = NSMenuItem(title: "No shared presentations", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let link = NSMenuItem(title: "Open Invitation Link…", action: #selector(openLink(_:)), keyEquivalent: "")
        link.target = self
        link.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        menu.addItem(link)
    }

    @objc private func openLink(_ sender: Any?) {
        CollaborationController.shared?.askForInvitationLink()
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let controller = CollaborationController.shared, let id = (sender.representedObject as? String).flatMap(UUID.init(uuidString:)) else { return }
        if let entry = controller.sharedWithMe.first(where: { $0.id == id }) {
            controller.openShared(entry)
        } else if let me = controller.status.me {
            controller.openShared(SharedDocumentEntry(id: id, title: sender.title, ownerName: me.name, ownerID: me.id))
        }
    }
}
