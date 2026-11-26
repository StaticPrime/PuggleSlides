import AppKit
import PuggleSlidesKit

/// Undo for a text view of its own: typing undoes step by step while editing, and the finished edit becomes one
/// step in the presentation's history.
protocol LocalUndo: NSTextView {
    var localUndoManager: UndoManager { get }
}

/// The text view used to edit a shape's text in place.
final class SlideTextView: NSTextView, LocalUndo {
    weak var session: SlideTextEditor?
    let localUndoManager = UndoManager()

    override var undoManager: UndoManager? { localUndoManager }

    @objc func undo(_ sender: Any?) { localUndoManager.undo() }
    @objc func redo(_ sender: Any?) { localUndoManager.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return localUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return localUndoManager.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func insertTab(_ sender: Any?) {
        // In a table, Tab moves to the next cell (and adds a row after the last one).
        if let session, session.cell != nil {
            session.canvas?.moveToNextCell(forward: true)
            return
        }
        if session?.indentIfList(by: 1) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if let session, session.cell != nil {
            session.canvas?.moveToNextCell(forward: false)
            return
        }
        if session?.indentIfList(by: -1) == true { return }
        super.insertBacktab(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if session?.endListOnEmptyParagraph() == true { return }
        super.insertNewline(sender)
        capitalizeWord(afterTyping: "\n")
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        capitalizeWord(afterTyping: string)
    }

    override func cancelOperation(_ sender: Any?) {
        session?.canvas?.endEditing()
    }

    override func paste(_ sender: Any?) {
        // Plain text keeps the formatting at the insertion point; rich text from other apps keeps its own.
        if NSPasteboard.general.availableType(from: [.rtf, .rtfd]) == nil {
            pasteAsPlainText(sender)
        } else {
            super.paste(sender)
        }
    }
}

/// One text editing session on the canvas.
@MainActor
final class SlideTextEditor: NSObject, NSTextViewDelegate {
    let elementID: UUID
    /// The table cell being edited, when the element is a table.
    let cell: (row: Int, column: Int)?
    /// The slide being edited, which stays put even if another slide is shown before editing ends.
    let slideID: UUID?
    let container: FlippedContainerView
    let textView: SlideTextView
    private(set) var style: ElementStyle
    let originalBody: TextBody
    let isNew: Bool
    weak var canvas: SlideEditingView?
    private let layoutManager = SlideLayoutManager()
    /// In a shared presentation: the text as the presentation last had it, from here or from someone else, so that a
    /// change someone else makes to it shows up here.
    var knownBody: TextBody
    /// In a shared presentation: sends the text being typed a moment after each pause.
    var livePush: DispatchWorkItem?

    init(element: SlideElement, style: ElementStyle, canvas: SlideEditingView, isNew: Bool, cell: (row: Int, column: Int)? = nil) {
        elementID = element.id
        self.cell = cell
        slideID = canvas.controller.currentSlideID
        self.style = style
        self.canvas = canvas
        self.isNew = isNew
        if let cell, let table = element.table, table.cells.indices.contains(cell.row), table.cells[cell.row].indices.contains(cell.column) {
            originalBody = table.cells[cell.row][cell.column].text
        } else {
            originalBody = element.shape?.text ?? TextBody()
        }
        container = FlippedContainerView()
        textView = SlideTextView(frame: .zero)
        knownBody = originalBody
        super.init()
        textView.textContainer?.replaceLayoutManager(layoutManager)
        layoutManager.showsEmptyBullets = true
        layoutManager.usesFontLeading = true
        textView.session = self
        textView.delegate = self
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.usesFontPanel = false
        textView.usesFindBar = false
        TypingPreferences.apply(to: textView)
        textView.smartInsertDeleteEnabled = true
        textView.linkTextAttributes = [:]
        textView.insertionPointColor = .black
        let paragraphs = style.resolvedParagraphs(originalBody)
        let text = SlideText.attributedString(paragraphs, body: originalBody, style: style, trailingSpace: false)
        textView.textStorage?.setAttributedString(text)
        if let typing = emptyAttributes(for: paragraphs.last) { textView.typingAttributes = typing }
        container.addSubview(textView)
        canvas.addSubview(container)
        layout()
        updateTrailingBullet()
    }

    /// Attributes for typing into an empty paragraph: its end style, paragraph style and bullet.
    private func emptyAttributes(for paragraph: ResolvedParagraph?) -> [NSAttributedString.Key: Any]? {
        guard var paragraph else { return nil }
        let index = originalBody.paragraphs.count - 1
        paragraph.runs = []
        let model = TextBody(paragraphs: [index >= 0 ? originalBody.paragraphs[index] : TextParagraph()], properties: originalBody.properties,
                             listStyle: originalBody.listStyle)
        let built = SlideText.attributedString([paragraph], body: model, style: style, trailingSpace: true)
        guard built.length > 0 else { return nil }
        return built.attributes(at: 0, effectiveRange: nil)
    }

    // MARK: Layout

    /// The element as it is now (its frame may grow while typing).
    private var element: SlideElement? {
        guard let canvas else { return nil }
        return canvas.controller.currentSlide?.element(id: elementID)
    }

    /// Positions the editor over the element, turned with it.
    func layout() {
        guard let canvas, let element, let slide = canvas.controller.currentSlide else { return }
        style = canvas.controller.presentation.style(for: element, on: slide)
        if let cell, let table = element.table {
            layoutInCell(cell, table: table, canvas: canvas)
            return
        }
        let placement = style.placement
        let frame = placement.frame
        let size = CGSize(width: abs(frame.width), height: abs(frame.height))
        // Turn the editor with the shape about the shape's center. A frame rotation pivots on the frame's origin, so the
        // origin is placed where the turned center lands on the shape's center.
        let degrees = placement.rotation + (placement.flipVertical ? 180 : 0)
        let radians = degrees * .pi / 180
        let half = CGPoint(x: size.width / 2, y: size.height / 2)
        let turned = CGPoint(x: half.x * cos(radians) - half.y * sin(radians), y: half.x * sin(radians) + half.y * cos(radians))
        container.frameRotation = 0
        container.setFrameSize(size)
        container.frameRotation = CGFloat(degrees)
        container.setFrameOrigin(CGPoint(x: frame.midX + canvas.margin - turned.x, y: frame.midY + canvas.margin - turned.y))
        let area = TextMetrics.textArea(for: style, size: size)
        let wraps = style.bodyProperties.wraps
        textView.textContainer?.size = NSSize(width: wraps ? area.width : 100_000, height: 100_000)
        layoutManager.ensureLayout(for: textView.textContainer!)
        var used = layoutManager.usedRect(for: textView.textContainer!).height
        if textView.string.isEmpty || textView.string.hasSuffix("\n") {
            used = max(used, layoutManager.extraLineFragmentRect.maxY)
        }
        let offset: CGFloat = switch style.bodyProperties.anchor {
        case .top: 0
        case .middle: (area.height - used) / 2
        case .bottom: area.height - used
        }
        textView.minSize = NSSize(width: area.width, height: max(used, 1))
        textView.maxSize = NSSize(width: wraps ? area.width : 100_000, height: 100_000)
        textView.frame = CGRect(x: area.minX, y: area.minY + offset, width: wraps ? area.width : max(area.width, layoutManager.usedRect(for: textView.textContainer!).width + 4),
                                height: max(used, 1))
    }

    /// Positions the editor over a table cell: the table's frame, with the text view at the cell's text.
    private func layoutInCell(_ cell: (row: Int, column: Int), table: Table, canvas: SlideEditingView) {
        guard table.cells.indices.contains(cell.row), table.cells[cell.row].indices.contains(cell.column) else { return }
        let tableLayout = TableLayout(table, style: style)
        let frame = style.placement.frame
        container.frameRotation = 0
        container.setFrameSize(tableLayout.size)
        container.setFrameOrigin(CGPoint(x: frame.x + canvas.margin, y: frame.y + canvas.margin))
        let rect = tableLayout.rect(row: cell.row, column: cell.column)
        let insets = table.cells[cell.row][cell.column].insets
        let width = max(1, rect.width - insets.left - insets.right)
        textView.textContainer?.size = NSSize(width: width, height: 100_000)
        layoutManager.ensureLayout(for: textView.textContainer!)
        var used = layoutManager.usedRect(for: textView.textContainer!).height
        if textView.string.isEmpty || textView.string.hasSuffix("\n") { used = max(used, layoutManager.extraLineFragmentRect.maxY) }
        let area = rect.inset(by: insets)
        let offset: CGFloat = switch table.cells[cell.row][cell.column].anchor {
        case .top: 0
        case .middle: max(0, (area.height - used) / 2)
        case .bottom: max(0, area.height - used)
        }
        textView.minSize = NSSize(width: width, height: max(used, 1))
        textView.maxSize = NSSize(width: width, height: 100_000)
        textView.frame = CGRect(x: area.minX, y: area.minY + offset, width: width, height: max(used, 1))
    }

    // MARK: Session

    func begin(at point: SlidePoint?) {
        guard let canvas else { return }
        canvas.window?.makeFirstResponder(textView)
        if let point {
            let local = canvas.convert(canvas.viewPoint(point), to: textView)
            let index = textView.characterIndexForInsertion(at: local)
            textView.setSelectedRange(NSRange(location: min(index, textView.string.utf16.count), length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }
    }

    func end() {
        livePush?.cancel()
        container.removeFromSuperview()
    }

    func textDidChange(_ notification: Notification) {
        updateTrailingBullet()
        grow()
        canvas?.onEditingChange?()
        scheduleLivePush()
    }

    /// In a shared presentation, the text goes to the others as it's typed: a moment after each pause.
    private func scheduleLivePush() {
        guard let canvas, canvas.controller.collaboration?.isLive == true else { return }
        livePush?.cancel()
        let work = DispatchWorkItem { [weak canvas] in canvas?.pushEditingText() }
        livePush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Shows the text as someone else changed it, keeping the selection where it was as far as it can.
    func replaceText(with body: TextBody, style: ElementStyle) {
        self.style = style
        let selection = textView.selectedRange()
        let paragraphs = style.resolvedParagraphs(body)
        textView.textStorage?.setAttributedString(SlideText.attributedString(paragraphs, body: body, style: style, trailingSpace: false))
        let length = textView.string.utf16.count
        let start = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        knownBody = body
        updateTrailingBullet()
        layout()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateTrailingBullet()
        canvas?.onEditingChange?()
    }

    /// Keeps macOS's own capitals out, so Settings ▸ Automatically capitalize words decides (see `TypingPreferences`).
    func textView(_ view: NSTextView, willCheckTextIn range: NSRange, options: [NSSpellChecker.OptionKey: Any] = [:],
                  types checkingTypes: UnsafeMutablePointer<NSTextCheckingTypes>) -> [NSSpellChecker.OptionKey: Any] {
        TypingPreferences.checkingOptions(options)
    }

    func textView(_ view: NSTextView, didCheckTextIn range: NSRange, types checkingTypes: NSTextCheckingTypes,
                  options: [NSSpellChecker.OptionKey: Any] = [:], results: [NSTextCheckingResult], orthography: NSOrthography,
                  wordCount: Int) -> [NSTextCheckingResult] {
        TypingPreferences.withoutCapitals(results, in: view.textStorage?.mutableString ?? "")
    }

    private func updateTrailingBullet() {
        let typing = textView.typingAttributes
        if let info = typing[.slideBullet] as? BulletInfo, let font = typing[.font] as? NSFont {
            layoutManager.trailingBullet = (info, font, typing[.foregroundColor] as? NSColor ?? .black)
        } else {
            layoutManager.trailingBullet = nil
        }
        textView.needsDisplay = true
    }

    /// "Resize shape to fit text" grows the box while typing; a table cell's row grows to fit.
    private func grow() {
        guard let canvas, let slideIndex = canvas.controller.currentSlideIndex, let element else { return }
        if let cell {
            let body = currentBody()
            let id = element.id
            canvas.controller.updateInteractive { presentation in
                let slide = presentation.slides[slideIndex]
                guard let index = slide.elementIndex(id: id), var table = slide.elements[index].table,
                      table.cells.indices.contains(cell.row), table.cells[cell.row].indices.contains(cell.column) else { return }
                table.cells[cell.row][cell.column].text = body
                var edited = slide.elements[index]
                edited.table = table
                canvas.controller.fitTableFrame(&edited, style: presentation.style(for: edited, on: slide))
                presentation.slides[slideIndex].elements[index] = edited
            }
            knownBody = body
            layout()
            return
        }
        if style.bodyProperties.autofit == .resizeShape {
            layoutManager.ensureLayout(for: textView.textContainer!)
            var used = layoutManager.usedRect(for: textView.textContainer!).height
            if textView.string.isEmpty || textView.string.hasSuffix("\n") { used = max(used, layoutManager.extraLineFragmentRect.maxY) }
            let size = CGSize(width: abs(style.placement.frame.width), height: abs(style.placement.frame.height))
            let area = TextMetrics.textArea(for: style, size: size)
            let height = max(1, used + (size.height - area.height))
            if abs(height - size.height) > 0.5 {
                let placement = TextFitting.resized(style.placement, toHeight: height, anchor: style.bodyProperties.anchor)
                let id = element.id
                canvas.controller.updateInteractive { presentation in
                    guard let index = presentation.slides[slideIndex].elementIndex(id: id) else { return }
                    presentation.slides[slideIndex].elements[index].placement = placement
                }
            }
        }
        layout()
    }

    // MARK: Converting back to the model

    /// The edited text as a model text body, keeping only formatting that differs from what it inherits.
    func currentBody() -> TextBody {
        guard let storage = textView.textStorage else { return originalBody }
        let string = storage.string as NSString
        var paragraphs: [TextParagraph] = []
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph(in: range))
            location = NSMaxRange(range)
        }
        if string.length == 0 || string.hasSuffix("\n") {
            paragraphs.append(paragraph(from: textView.typingAttributes))
        }
        return TextBody(paragraphs: paragraphs, properties: originalBody.properties, listStyle: originalBody.listStyle)
    }

    /// The model paragraph for a range of the text storage (with or without its newline).
    func paragraph(in range: NSRange) -> TextParagraph {
        guard let storage = textView.textStorage, range.length > 0 else { return paragraph(from: textView.typingAttributes) }
        let string = storage.string as NSString
        var content = range
        if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
        let attributes = storage.attributes(at: range.location, effectiveRange: nil)
        var paragraph = paragraph(from: attributes)
        var runs: [TextRun] = []
        storage.enumerateAttributes(in: content) { runAttributes, runRange, _ in
            let text = string.substring(with: runRange).replacingOccurrences(of: "\u{200B}", with: "")
            guard !text.isEmpty else { return }
            let style = explicitStyle(runAttributes, level: paragraph.level)
            let field = (runAttributes[.slideField] as? String).map(TextFieldKind.init(typeName:))
            if let last = runs.last, last.style == style, last.field == nil, field == nil {
                runs[runs.count - 1].text += text
            } else {
                runs.append(TextRun(text, style: style, field: field))
            }
        }
        paragraph.runs = runs
        if content.length < range.length {
            paragraph.endStyle = explicitStyle(storage.attributes(at: NSMaxRange(content), effectiveRange: nil), level: paragraph.level)
        } else if let last = runs.last {
            paragraph.endStyle = last.style
        }
        return paragraph
    }

    /// An empty paragraph with the level, formatting and end style these attributes carry.
    private func paragraph(from attributes: [NSAttributedString.Key: Any]) -> TextParagraph {
        let level = attributes[.slideLevel] as? Int ?? 0
        let style = (attributes[.slideParagraph] as? AttributeBox<ParagraphStyle>)?.value ?? .empty
        return TextParagraph(runs: [], level: level, style: style, endStyle: explicitStyle(attributes, level: level))
    }

    /// The fully specified style these display attributes show, before shrinking.
    func effectiveStyle(_ attributes: [NSAttributedString.Key: Any]) -> CharacterStyle {
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
        let baseline = (attributes[.slideBaseline] as? String).flatMap(BaselineShift.init(rawValue:)) ?? .normal
        let scale = style.bodyProperties.autofit == .shrinkOnOverflow ? style.bodyProperties.fontScale : 1
        var size = Double(font.pointSize) / (baseline == .normal ? 1 : SlideText.baselineScale) / max(scale, 0.05)
        size = (size * 10).rounded() / 10
        let traits = NSFontManager.shared.traits(of: font)
        let theme = style.theme.colors
        let link = (attributes[.slideLink] as? AttributeBox<Hyperlink>)?.value
        var color: ColorRef?
        let shown = (attributes[.foregroundColor] as? NSColor)?.resolvedColor
        if let stored = (attributes[.slideColor] as? AttributeBox<ColorRef>)?.value,
           shown == nil || stored.resolved(theme).rgb == shown!.rgb {
            color = stored
        } else if let shown {
            color = ColorRef(shown.rgb).withAlpha(shown.alpha)
        }
        var highlight: ColorRef?
        if let stored = (attributes[.slideHighlight] as? AttributeBox<ColorRef>)?.value {
            highlight = stored
        } else if let shown = (attributes[.backgroundColor] as? NSColor)?.resolvedColor {
            highlight = ColorRef(shown.rgb)
        }
        return CharacterStyle(fontFamily: font.familyName ?? "Arial", fontSize: size, bold: traits.contains(.boldFontMask),
                              italic: traits.contains(.italicFontMask), underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
                              strikethrough: (attributes[.strikethroughStyle] as? Int ?? 0) != 0, color: color, highlight: highlight,
                              baseline: baseline, link: link)
    }

    /// Only what differs from the level's inherited formatting.
    func explicitStyle(_ attributes: [NSAttributedString.Key: Any], level: Int) -> CharacterStyle {
        minimized(effectiveStyle(attributes), level: level)
    }

    func minimized(_ effective: CharacterStyle, level: Int) -> CharacterStyle {
        let inherited = style.levelStyle(level).character
        var resolved = style.resolve(inherited)
        if effective.link != nil {
            // Link text is underlined in the link color unless it says otherwise.
            resolved.underline = true
            if inherited.color == nil || effective.color?.themeSlot == .hyperlink { resolved.color = style.resolve(ColorRef(theme: .hyperlink)) }
        }
        var result = CharacterStyle()
        if let family = effective.fontFamily, family != resolved.fontFamily { result.fontFamily = family }
        if let size = effective.fontSize, abs(size - resolved.fontSize) > 0.05 { result.fontSize = size }
        if let bold = effective.bold, bold != resolved.bold { result.bold = bold }
        if let italic = effective.italic, italic != resolved.italic { result.italic = italic }
        if let underline = effective.underline, underline != resolved.underline { result.underline = underline }
        if let strike = effective.strikethrough, strike != resolved.strikethrough { result.strikethrough = strike }
        if let color = effective.color {
            let shown = style.resolve(color)
            if shown.rgb != resolved.color.rgb || abs(shown.alpha - resolved.color.alpha) > 0.01 { result.color = color }
        }
        result.highlight = effective.highlight
        if let baseline = effective.baseline, baseline != resolved.baseline { result.baseline = baseline }
        result.link = effective.link
        return result
    }

    // MARK: Formatting while editing

    /// The selected paragraph ranges (whole paragraphs, with their newlines).
    private var selectedParagraphRanges: [NSRange] {
        guard let storage = textView.textStorage else { return [] }
        let string = storage.string as NSString
        let selection = textView.selectedRange()
        guard string.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var location = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0)).location
        let end = max(NSMaxRange(selection), selection.location)
        repeat {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            guard range.length > 0 else { break }
            ranges.append(range)
            location = NSMaxRange(range)
        } while location < end && location < string.length
        return ranges
    }

    /// The insertion point sits in the empty paragraph after a final newline (or in empty text).
    private var isInTrailingEmptyParagraph: Bool {
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        return selection.length == 0 && selection.location == string.length && (string.length == 0 || string.hasSuffix("\n"))
    }

    /// Applies a character change to the selection, or to what's typed next when nothing is selected.
    func applyCharacters(_ change: (inout CharacterStyle) -> Void) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            var typing = textView.typingAttributes
            let level = typing[.slideLevel] as? Int ?? 0
            var explicit = explicitStyle(typing, level: level)
            change(&explicit)
            let resolved = style.resolve(explicit.merged(over: style.levelStyle(level).character),
                                         scale: style.bodyProperties.autofit == .shrinkOnOverflow ? style.bodyProperties.fontScale : 1)
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .backgroundColor, .baselineOffset, .slideBaseline,
                        .slideLink, .slideColor, .slideHighlight] { typing[key] = nil }
            typing.merge(SlideText.attributes(for: resolved, explicit: explicit)) { $1 }
            textView.typingAttributes = typing
            canvas?.onEditingChange?()
            return
        }
        guard textView.shouldChangeText(in: selection, replacementString: nil) else { return }
        storage.beginEditing()
        var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: selection) { attributes, range, _ in
            let level = attributes[.slideLevel] as? Int ?? 0
            var explicit = explicitStyle(attributes, level: level)
            change(&explicit)
            let resolved = style.resolve(explicit.merged(over: style.levelStyle(level).character),
                                         scale: style.bodyProperties.autofit == .shrinkOnOverflow ? style.bodyProperties.fontScale : 1)
            var updated = attributes
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .backgroundColor, .baselineOffset, .slideBaseline,
                        .slideLink, .slideColor, .slideHighlight] { updated[key] = nil }
            updated.merge(SlideText.attributes(for: resolved, explicit: explicit)) { $1 }
            changes.append((range, updated))
        }
        for (range, attributes) in changes { storage.setAttributes(attributes, range: range) }
        storage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }

    /// The selection's character styles, fully specified.
    var selectedEffectiveStyles: [CharacterStyle] {
        guard let storage = textView.textStorage else { return [] }
        let selection = textView.selectedRange()
        if selection.length == 0 { return [effectiveStyle(textView.typingAttributes)] }
        var styles: [CharacterStyle] = []
        storage.enumerateAttributes(in: selection) { attributes, _, _ in styles.append(effectiveStyle(attributes)) }
        return styles
    }

    /// Applies a paragraph change to every selected paragraph, rebuilding its formatting from the model.
    func applyParagraphs(_ change: (inout TextParagraph) -> Void) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        var ranges = selectedParagraphRanges
        if isInTrailingEmptyParagraph || ranges.isEmpty {
            var paragraph = paragraph(from: textView.typingAttributes)
            change(&paragraph)
            if let built = rebuilt(paragraph), built.length > 0 {
                var typing = textView.typingAttributes
                typing.merge(built.attributes(at: 0, effectiveRange: nil)) { $1 }
                textView.typingAttributes = typing
            }
            if ranges.isEmpty || selection.location == storage.length {
                updateTrailingBullet()
                grow()
                canvas?.onEditingChange?()
                return
            }
            ranges = ranges.filter { NSMaxRange($0) > selection.location }
        }
        guard let first = ranges.first, let last = ranges.last else { return }
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        guard textView.shouldChangeText(in: whole, replacementString: nil) else { return }
        storage.beginEditing()
        for range in ranges {
            var paragraph = paragraph(in: range)
            change(&paragraph)
            guard let built = rebuilt(paragraph) else { continue }
            // Same characters, new attributes; the newline takes the paragraph's end formatting.
            let length = min(built.length, range.length)
            built.enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, builtRange, _ in
                storage.setAttributes(attributes, range: NSRange(location: range.location + builtRange.location, length: builtRange.length))
            }
            if range.length > length, built.length > 0 {
                let tail = NSRange(location: range.location + length, length: range.length - length)
                var attributes = built.attributes(at: max(0, built.length - 1), effectiveRange: nil)
                if built.length > length { attributes = built.attributes(at: length, effectiveRange: nil) }
                storage.setAttributes(attributes, range: tail)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
        updateTrailingBullet()
    }

    /// One paragraph's text with all its formatting, ending with a newline carrying the end formatting.
    private func rebuilt(_ paragraph: TextParagraph) -> NSMutableAttributedString? {
        let body = TextBody(paragraphs: [paragraph, TextParagraph()], properties: originalBody.properties, listStyle: originalBody.listStyle)
        let resolved = style.resolvedParagraphs(body)
        guard let first = resolved.first else { return nil }
        let built = SlideText.attributedString([first, resolved[1]], body: body, style: style, trailingSpace: false)
        if paragraph.isEmpty, built.length > 0 {
            // An empty paragraph is just its newline.
            return NSMutableAttributedString(attributedString: built.attributedSubstring(from: NSRange(location: 0, length: 1)))
        }
        return built
    }

    /// The paragraph formatting under the insertion point, for the toolbar.
    var currentParagraph: TextParagraph {
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        if isInTrailingEmptyParagraph || string.length == 0 { return paragraph(from: textView.typingAttributes) }
        return paragraph(in: string.paragraphRange(for: NSRange(location: min(selection.location, string.length - 1), length: 0)))
    }

    /// Tab and Shift-Tab change a list paragraph's level (or several selected paragraphs').
    func indentIfList(by delta: Int) -> Bool {
        let selection = textView.selectedRange()
        let string = textView.string as NSString
        let multiple = selectedParagraphRanges.count > 1
        let paragraph = currentParagraph
        let resolved = style.resolvedParagraphs(TextBody(paragraphs: [paragraph], properties: originalBody.properties, listStyle: originalBody.listStyle))
        let isList = resolved.first?.bullet != nil
        let atStart = selection.length == 0 && (selection.location == 0 || string.length == 0
            || string.paragraphRange(for: NSRange(location: min(selection.location, max(0, string.length - 1)), length: 0)).location == selection.location
            || isInTrailingEmptyParagraph)
        guard multiple || (isList && (atStart || delta < 0)) else { return false }
        indent(by: delta)
        return true
    }

    func indent(by delta: Int) {
        applyParagraphs { paragraph in
            paragraph.level = max(0, min(8, paragraph.level + delta))
            if let margin = paragraph.style.marginLeft { paragraph.style.marginLeft = max(0, margin + 36 * Double(delta)) }
        }
    }

    /// Return in an empty list paragraph ends the list: it outdents, or at the first level drops the bullet.
    func endListOnEmptyParagraph() -> Bool {
        let paragraph = currentParagraph
        guard paragraph.isEmpty, textView.selectedRange().length == 0 else { return false }
        let resolved = style.resolvedParagraphs(TextBody(paragraphs: [paragraph], properties: originalBody.properties, listStyle: originalBody.listStyle))
        guard resolved.first?.bullet != nil else { return false }
        if paragraph.level > 0 {
            indent(by: -1)
        } else {
            let elementStyle = style
            applyParagraphs { paragraph in PresentationController.applyList(.none, to: &paragraph, style: elementStyle) }
        }
        return true
    }

    // MARK: Toolbar state

    func textSummary() -> TextSummary {
        let styles = selectedEffectiveStyles
        guard let first = styles.first else { return TextSummary() }
        let theme = style.theme.colors
        var summary = TextSummary()
        summary.fontFamily = styles.allSatisfy { $0.fontFamily == first.fontFamily } ? first.fontFamily : nil
        summary.fontSize = styles.allSatisfy { $0.fontSize == first.fontSize } ? first.fontSize : nil
        summary.bold = styles.allSatisfy { $0.bold == true }
        summary.italic = styles.allSatisfy { $0.italic == true }
        summary.underline = styles.allSatisfy { $0.underline == true }
        summary.strikethrough = styles.allSatisfy { $0.strikethrough == true }
        summary.colorHex = first.color?.resolved(theme).rgb.hex
        summary.highlightHex = first.highlight?.resolved(theme).rgb.hex
        summary.hasLink = first.link != nil
        let paragraph = currentParagraph
        let resolved = style.resolvedParagraphs(TextBody(paragraphs: [paragraph], properties: originalBody.properties, listStyle: originalBody.listStyle))
        if let first = resolved.first {
            summary.alignment = first.alignment
            summary.lineSpacing = first.lineSpacing
            if case .number = paragraph.style.merged(over: style.levelStyle(paragraph.level).paragraph).bullet ?? Bullet.none {
                summary.isNumbered = true
            } else {
                summary.isBulleted = first.bullet != nil
            }
        }
        summary.anchor = style.bodyProperties.anchor
        return summary
    }
}

/// A flipped view that holds the text view, so it can turn with a rotated shape.
final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: Starting and ending editing

extension SlideEditingView {
    /// Starts editing an element's text, with the insertion point at `point` (or at the end).
    func beginEditing(_ id: UUID, at point: SlidePoint?, isNew: Bool = false) {
        guard editor?.elementID != id, controller.canEditContent else { return }
        if editor != nil { endEditing() }
        guard let slide = controller.currentSlide, var element = slide.element(id: id), element.shape != nil, !element.isLine else { return }
        controller.selectElements([id])
        controller.beginInteractive()
        if element.shape?.text == nil, let slideIndex = controller.currentSlideIndex {
            // Shapes without text get an empty text body, centered like a new shape's text.
            var shape = element.shape!
            var text = TextBody(properties: TextBodyProperties(anchor: .middle, insets: .standard, wraps: true))
            text.listStyle[0] = LevelStyle(paragraph: ParagraphStyle(alignment: .center), character: CharacterStyle(fontSize: 14))
            shape.text = text
            element.shape = shape
            controller.updateInteractive { presentation in
                guard let index = presentation.slides[slideIndex].elementIndex(id: id) else { return }
                presentation.slides[slideIndex].elements[index].shape = shape
            }
        }
        guard let current = controller.currentSlide?.element(id: id) else { return }
        let style = controller.presentation.style(for: current, on: controller.currentSlide!)
        let session = SlideTextEditor(element: current, style: style, canvas: self, isNew: isNew)
        editor = session
        session.begin(at: point)
        needsDisplay = true
        onEditingChange?()
    }

    /// Starts editing a table cell's text, with the insertion point at `point` (or at the end).
    func beginEditingCell(_ id: UUID, row: Int, column: Int, at point: SlidePoint?) {
        guard controller.canEditContent else { return }
        if let editor, editor.elementID == id, let cell = editor.cell, cell.row == row, cell.column == column { return }
        if editor != nil { endEditing() }
        guard let slide = controller.currentSlide, let element = slide.element(id: id), let table = element.table,
              table.cells.indices.contains(row), table.cells[row].indices.contains(column) else { return }
        let anchor = table.anchor(row: row, column: column)
        controller.selectElements([id])
        controller.tableSelection = TableCellRange(row: anchor.row, column: anchor.column)
        controller.beginInteractive()
        let style = controller.presentation.style(for: element, on: slide)
        let session = SlideTextEditor(element: element, style: style, canvas: self, isNew: false, cell: anchor)
        editor = session
        session.begin(at: point)
        needsDisplay = true
        onEditingChange?()
    }

    /// Tab and Shift-Tab in a table: the next or previous cell, adding a row after the last cell.
    func moveToNextCell(forward: Bool) {
        guard let session = editor, let cell = session.cell else { return }
        let id = session.elementID
        endEditing()
        guard let table = controller.currentSlide?.element(id: id)?.table else { return }
        let visible = table.visibleCells
        guard let position = visible.firstIndex(where: { $0.row == cell.row && $0.column == cell.column }) else { return }
        if forward, position == visible.count - 1 {
            controller.tableSelection = TableCellRange(row: cell.row, column: cell.column)
            controller.insertTableRows(below: true)
            beginEditingCell(id, row: table.rowCount, column: 0, at: nil)
            return
        }
        let next = visible[max(0, min(visible.count - 1, position + (forward ? 1 : -1)))]
        beginEditingCell(id, row: next.row, column: next.column, at: nil)
        // Moving into a cell selects its text.
        editor?.textView.selectAll(nil)
    }

    /// In a shared presentation: the text being typed goes into the presentation, and from there to the others, while
    /// it's still being edited (without fitting, which happens when editing ends).
    func pushEditingText() {
        guard let session = editor, controller.collaboration?.isLive == true, !session.textView.hasMarkedText(),
              let slideIndex = session.slideID.flatMap(controller.presentation.slideIndex(id:)) else { return }
        session.livePush?.cancel()
        let body = session.currentBody()
        let id = session.elementID, cell = session.cell
        controller.updateInteractive { presentation in
            guard let index = presentation.slides[slideIndex].elementIndex(id: id) else { return }
            if let cell {
                guard var table = presentation.slides[slideIndex].elements[index].table, table.cells.indices.contains(cell.row),
                      table.cells[cell.row].indices.contains(cell.column) else { return }
                table.cells[cell.row][cell.column].text = body
                presentation.slides[slideIndex].elements[index].table = table
            } else {
                presentation.slides[slideIndex].elements[index].shape?.text = body
            }
        }
        session.knownBody = body
        controller.collaboration?.captureLocal()
    }

    /// In a shared presentation: someone else changed the text being edited here, so it shows their change.
    func reloadEditingText() {
        guard let session = editor, let slideID = session.slideID, let slide = controller.presentation.slides.first(where: { $0.id == slideID }),
              let element = slide.element(id: session.elementID) else { return }
        let body: TextBody
        if let cell = session.cell {
            guard let table = element.table, table.cells.indices.contains(cell.row), table.cells[cell.row].indices.contains(cell.column) else { return }
            body = table.cells[cell.row][cell.column].text
        } else {
            body = element.shape?.text ?? TextBody()
        }
        guard body != session.knownBody else { return }
        session.replaceText(with: body, style: controller.presentation.style(for: element, on: slide))
    }

    /// Commits the text being edited (with text fitting) as one undo step and returns to the shape.
    func endEditing() {
        guard let session = editor else { return }
        editor = nil
        let body = session.currentBody()
        session.end()
        let id = session.elementID
        if session.isNew, body.isEmpty {
            // An empty new text box goes away.
            controller.cancelInteractive()
            controller.undoManager?.undo()
        } else if let slideIndex = session.slideID.flatMap(controller.presentation.slideIndex(id:)) ?? controller.currentSlideIndex {
            let cell = session.cell
            controller.updateInteractive { presentation in
                let slide = presentation.slides[slideIndex]
                guard let index = slide.elementIndex(id: id) else { return }
                if let cell {
                    guard var table = slide.elements[index].table, table.cells.indices.contains(cell.row),
                          table.cells[cell.row].indices.contains(cell.column) else { return }
                    table.cells[cell.row][cell.column].text = body
                    var edited = slide.elements[index]
                    edited.table = table
                    controller.fitTableFrame(&edited, style: presentation.style(for: edited, on: slide))
                    presentation.slides[slideIndex].elements[index] = edited
                    return
                }
                presentation.slides[slideIndex].elements[index].shape?.text = body
                TextFitting.fit(&presentation.slides[slideIndex].elements[index], on: presentation.slides[slideIndex], in: presentation)
            }
            controller.endInteractive(actionName: "Typing")
        } else {
            controller.cancelInteractive()
        }
        if window?.firstResponder == nil || window?.firstResponder === session.textView { window?.makeFirstResponder(self) }
        needsDisplay = true
        onEditingChange?()
    }
}
