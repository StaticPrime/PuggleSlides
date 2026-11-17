import AppKit
import PuggleSlidesKit

/// Native menus opened from toolbar dropdowns.
enum ToolbarMenus {
    /// Fonts offered in the font menu, shown when installed.
    static let featuredFonts = ["Arial", "Avenir Next", "Baskerville", "Comic Sans MS", "Courier New", "Futura", "Georgia", "Gill Sans",
                                "Helvetica", "Helvetica Neue", "Impact", "Optima", "Palatino", "Times New Roman", "Trebuchet MS", "Verdana"]

    static func make(_ kind: ToolbarMenu, controller: DocumentWindowController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true
        let state = controller.state
        func add(_ item: NSMenuItem) {
            if item.action != nil && item.target == nil { item.target = controller }
            item.submenu?.items.forEach { if $0.action != nil && $0.target == nil { $0.target = controller } }
            menu.addItem(item)
        }

        switch kind {
        case .zoom:
            for item in MenuBuilder.zoomItems() {
                if item.action == #selector(SlideCommands.ppZoomFit(_:)) { item.state = state.zoomIsFit ? .on : .off }
                if item.action == #selector(SlideCommands.ppSetZoom(_:)) {
                    item.state = !state.zoomIsFit && abs(state.zoom * 100 - CGFloat(item.tag)) < 0.5 ? .on : .off
                }
                add(item)
            }

        case .newSlideLayouts:
            for item in controller.layoutMenuItems(action: #selector(SlideCommands.ppNewSlideWithLayout(_:)), checkCurrent: false) { add(item) }

        case .applyLayout:
            for item in controller.layoutMenuItems(action: #selector(SlideCommands.ppApplyLayout(_:)), checkCurrent: true) { add(item) }

        case .image:
            add(MenuBuilder.item("Upload from computer…", #selector(SlideCommands.ppInsertImage(_:)), symbol: "square.and.arrow.up"))

        case .lines:
            for item in MenuBuilder.lineItems() { add(item) }

        case .font:
            add(MenuBuilder.item("More fonts…", #selector(SlideCommands.ppMoreFonts(_:)), symbol: "textformat"))
            menu.addItem(.separator())
            let installed = Set(NSFontManager.shared.availableFontFamilies)
            var fonts = featuredFonts.filter { installed.contains($0) }
            if let current = state.text.fontFamily, !fonts.contains(current) { fonts.insert(current, at: 0) }
            for family in fonts {
                let item = MenuBuilder.represented(MenuBuilder.item(family, #selector(SlideCommands.ppSetFont(_:))), family)
                item.attributedTitle = NSAttributedString(string: family, attributes: [.font: NSFont(name: family, size: 14) ?? NSFont.systemFont(ofSize: 14)])
                item.state = family == state.text.fontFamily ? .on : .off
                add(item)
            }

        case .align:
            for item in MenuBuilder.alignItems() {
                item.keyEquivalent = ""
                if item.action == #selector(SlideCommands.ppTextAlign(_:)) {
                    let current = [TextAlignment.left, .center, .right, .justified].firstIndex { $0 == state.text.alignment } ?? -1
                    item.state = item.tag == current ? .on : .off
                } else if item.action == #selector(SlideCommands.ppVerticalAlign(_:)) {
                    let current = [VerticalAnchor.top, .middle, .bottom].firstIndex { $0 == state.text.anchor } ?? -1
                    item.state = item.tag == current ? .on : .off
                }
                add(item)
            }

        case .lineSpacing:
            for item in MenuBuilder.lineSpacingItems() {
                if item.action == #selector(SlideCommands.ppLineSpacing(_:)), let spacing = state.text.lineSpacing {
                    item.state = abs(spacing * 100 - Double(item.tag)) < 1 ? .on : .off
                }
                add(item)
            }

        case .bullets:
            for item in MenuBuilder.bulletItems() { add(item) }

        case .numbers:
            for item in MenuBuilder.numberItems() { add(item) }

        case .borderWeight:
            for item in MenuBuilder.borderWeightItems() {
                if let width = state.shape.borderWidth { item.state = abs(width / 0.75 - Double(item.tag)) < 0.3 ? .on : .off }
                item.image = weightImage(CGFloat(item.tag))
                add(item)
            }

        case .borderDash:
            for item in MenuBuilder.borderDashItems() {
                item.state = state.shape.dash == DashStyle.allCases[item.tag] ? .on : .off
                item.image = dashImage(DashStyle.allCases[item.tag])
                add(item)
            }

        case .lineStart, .lineEnd:
            let start = kind == .lineStart
            for item in MenuBuilder.lineEndItems(start: start) {
                let end = LineEnd.allCases[item.tag]
                item.state = (start ? state.shape.head : state.shape.tail) == end ? .on : .off
                item.image = lineEndImage(end, atStart: start)
                add(item)
            }

        case .download:
            for item in MenuBuilder.downloadItems() { add(item) }

        case .tableBorders:
            for position in TableBorderPosition.allCases {
                let item = MenuBuilder.item(position.title, #selector(SlideCommands.ppTableBorderPosition(_:)), tag: TableBorderPosition.allCases.firstIndex(of: position) ?? 0)
                item.state = controller.controller.tableBorderPosition == position ? .on : .off
                item.image = tableBorderImage(position)
                add(item)
            }

        case .mask:
            for item in MenuBuilder.maskItems() { add(item) }

        case .replaceImage:
            add(MenuBuilder.item("Upload from computer…", #selector(SlideCommands.ppReplaceImage(_:)), symbol: "square.and.arrow.up"))

        case .slideshow:
            add(MenuBuilder.item("Presenter view", #selector(SlideCommands.ppPresenterView(_:)), symbol: "rectangle.on.rectangle"))
            add(MenuBuilder.item("Start from beginning", #selector(SlideCommands.ppStartSlideshowFromBeginning(_:)), symbol: "backward.end"))
        }
        return menu
    }

    /// A small 2×2 grid with the chosen borders drawn dark and the rest light.
    static func tableBorderImage(_ position: TableBorderPosition) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let grid = Table.make(rows: 2, columns: 2, width: 2)
            let range = TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 1, lastColumn: 1)
            let chosen = grid.borderSlots(position, in: range)
            func line(_ horizontal: Bool, _ row: Int, _ column: Int) -> NSBezierPath {
                let path = NSBezierPath()
                let x = 2 + CGFloat(column) * 6, y = 2 + CGFloat(row) * 6
                path.move(to: NSPoint(x: x, y: y))
                path.line(to: horizontal ? NSPoint(x: x + 6, y: y) : NSPoint(x: x, y: y + 6))
                path.lineWidth = 1.2
                return path
            }
            for row in 0...2 {
                for column in 0..<2 {
                    let on = chosen.contains { $0.horizontal && $0.row == row && $0.column == column }
                    (on ? NSColor.labelColor : NSColor.tertiaryLabelColor).setStroke()
                    line(true, row, column).stroke()
                }
            }
            for row in 0..<2 {
                for column in 0...2 {
                    let on = chosen.contains { !$0.horizontal && $0.row == row && $0.column == column }
                    (on ? NSColor.labelColor : NSColor.tertiaryLabelColor).setStroke()
                    line(false, row, column).stroke()
                }
            }
            return true
        }
    }

    static func weightImage(_ pixels: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 40, height: 14), flipped: true) { rect in
            NSColor.labelColor.setFill()
            NSRect(x: 0, y: rect.midY - min(pixels, 12) / 2, width: rect.width, height: max(1, min(pixels, 12))).fill()
            return true
        }
    }

    static func dashImage(_ dash: DashStyle) -> NSImage {
        NSImage(size: NSSize(width: 40, height: 14), flipped: true) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: rect.midY))
            path.line(to: NSPoint(x: rect.width, y: rect.midY))
            path.lineWidth = 2
            let pattern = dash.pattern.map { CGFloat($0) * 2 }
            if !pattern.isEmpty { path.setLineDash(pattern, count: pattern.count, phase: 0) }
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
    }

    static func lineEndImage(_ end: LineEnd, atStart: Bool) -> NSImage {
        NSImage(size: NSSize(width: 40, height: 14), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let line = CGMutablePath()
            line.move(to: CGPoint(x: atStart ? rect.width - 2 : 2, y: rect.midY))
            line.addLine(to: CGPoint(x: atStart ? 6 : rect.width - 6, y: rect.midY))
            let outline = Outline(fill: .solid(ColorRef(RGBColor(red: 0x44, green: 0x47, blue: 0x46))), width: 1.5,
                                  head: .none, tail: end)
            context.saveGState()
            SlideRenderer.stroke([ShapePath(path: line, fill: .none)], outline: outline,
                                 theme: BuiltInThemes.simpleLight(), isLine: true)
            context.restoreGState()
            return true
        }
    }
}
