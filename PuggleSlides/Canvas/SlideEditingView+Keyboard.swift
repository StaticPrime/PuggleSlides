import AppKit
import PuggleSlidesKit

extension SlideEditingView {
    /// One pixel, the nudge step: 1/96 inch.
    static let nudge: Double = 0.75

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers, let key = characters.unicodeScalars.first else {
            super.keyDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasSelection = !controller.selectedElementIDs.isEmpty
        // While cropping, Return keeps the crop and Esc puts it back.
        if cropping != nil, [13, 3, 27].contains(Int(key.value)) {
            endCropping(commit: key.value != 27)
            return
        }
        let table = controller.selectedTableElement
        switch Int(key.value) {
        case NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSUpArrowFunctionKey, NSDownArrowFunctionKey:
            guard hasSelection else { return super.keyDown(with: event) }
            let left = Int(key.value) == NSLeftArrowFunctionKey, right = Int(key.value) == NSRightArrowFunctionKey
            if modifiers.contains(.option), left || right {
                controller.rotateSelection(by: (modifiers.contains(.shift) ? 1 : 15) * (right ? 1 : -1))
                return
            }
            let step = modifiers.contains(.shift) ? Self.nudge * 10 : Self.nudge
            switch Int(key.value) {
            case NSLeftArrowFunctionKey: controller.nudgeSelection(dx: -step, dy: 0)
            case NSRightArrowFunctionKey: controller.nudgeSelection(dx: step, dy: 0)
            case NSUpArrowFunctionKey: controller.nudgeSelection(dx: 0, dy: -step)
            default: controller.nudgeSelection(dx: 0, dy: step)
            }
        case 9, 25:
            // Tab and Shift-Tab: next and previous shape.
            selectNeighbor(forward: !modifiers.contains(.shift) && key.value == 9)
        case 13, 3:
            if let table, let cells = table.table {
                // Return in a selected table types into its first selected cell.
                let range = controller.tableRange(cells)
                beginEditingCell(table.id, row: range.firstRow, column: range.firstColumn, at: nil)
                editor?.textView.selectAll(nil)
                return
            }
            if let element = controller.selectedElements.first, controller.selectedElements.count == 1, element.isWordArt {
                onEditWordArt?(element.id)
                return
            }
            if let element = controller.selectedElements.first, controller.selectedElements.count == 1, element.shape != nil, !element.isLine {
                beginEditing(element.id, at: nil)
                editor?.textView.selectAll(nil)
            }
        case 27:
            if tool.isInsertTool {
                tool = .select
                onToolFinished?()
            } else {
                controller.selectElements([])
            }
        case 127, NSDeleteFunctionKey, 8:
            // Selected cells lose their text; the table stays.
            if table != nil, controller.tableSelection != nil {
                controller.editTable("Clear Cells") { cells, range in
                    cells.updateTexts(in: range) { text in
                        text.paragraphs = [TextParagraph(runs: [], style: text.paragraphs.first?.style ?? ParagraphStyle(),
                                                         endStyle: text.paragraphs.first?.runs.first?.style ?? CharacterStyle())]
                    }
                    return range
                }
                return
            }
            controller.deleteSelectedElements()
        default:
            // Typing with one shape selected starts editing its text.
            if modifiers.isDisjoint(with: [.command, .control]), let table, let cells = table.table,
               let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                // Typing into a selected table replaces the first selected cell's text.
                let range = controller.tableRange(cells)
                beginEditingCell(table.id, row: range.firstRow, column: range.firstColumn, at: nil)
                editor?.textView.selectAll(nil)
                editor?.textView.insertText(text, replacementRange: editor?.textView.selectedRange() ?? NSRange(location: 0, length: 0))
                return
            }
            if modifiers.isDisjoint(with: [.command, .control]), let element = controller.selectedElements.first,
               controller.selectedElements.count == 1, element.shape != nil, !element.isLine, !element.isWordArt,
               let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing(element.id, at: nil)
                editor?.textView.insertText(text, replacementRange: editor?.textView.selectedRange() ?? NSRange(location: 0, length: 0))
                return
            }
            super.keyDown(with: event)
        }
    }

    private func selectNeighbor(forward: Bool) {
        guard let slide = controller.currentSlide, !slide.elements.isEmpty else { return }
        let ids = slide.elements.map(\.id)
        let current = controller.selectedElementIDs.last.flatMap { ids.firstIndex(of: $0) }
        let next: Int
        if let current {
            next = (current + (forward ? 1 : -1) + ids.count) % ids.count
        } else {
            next = forward ? 0 : ids.count - 1
        }
        controller.selectElements([ids[next]])
    }

    override func selectAll(_ sender: Any?) {
        guard let slide = controller.currentSlide else { return }
        controller.selectElements(slide.elements.map(\.id))
    }
}
