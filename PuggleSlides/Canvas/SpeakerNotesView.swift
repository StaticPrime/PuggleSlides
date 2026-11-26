import AppKit
import PuggleSlidesKit

/// The notes text view: shows a prompt when empty, and keeps its typing undo to itself.
final class NotesTextView: NSTextView, LocalUndo {
    var onFocusChange: ((Bool) -> Void)?
    let localUndoManager = UndoManager()

    override var undoManager: UndoManager? { localUndoManager }

    @objc func undo(_ sender: Any?) { localUndoManager.undo() }
    @objc func redo(_ sender: Any?) { localUndoManager.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return localUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return localUndoManager.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        capitalizeWord(afterTyping: string)
    }

    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        capitalizeWord(afterTyping: "\n")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, window?.firstResponder !== self {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.promptText]
            ("Click to add speaker notes" as NSString).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height), withAttributes: attributes)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        needsDisplay = true
        return accepted
    }
}

/// Speaker notes for the current slide, below the canvas.
final class SpeakerNotesView: NSScrollView, NSTextViewDelegate {
    let controller: PresentationController
    let textView: NotesTextView
    /// The slide whose notes are showing.
    private(set) var slideID: UUID?
    private var shownNotes = TextBody()
    /// In a shared presentation: commits the notes being typed a moment after each pause, so others see them.
    private var liveCommit: DispatchWorkItem?
    private static let font = "Arial"
    private static let size: CGFloat = 14

    init(controller: PresentationController) {
        self.controller = controller
        textView = NotesTextView(frame: .zero)
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .white
        borderType = .noBorder
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.usesFontPanel = false
        TypingPreferences.apply(to: textView)
        textView.delegate = self
        textView.typingAttributes = Self.attributes(bold: false, italic: false, underline: false)
        textView.onFocusChange = { [weak self] focused in if !focused { self?.commit() } }
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func attributes(bold: Bool, italic: Bool, underline: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFontManager.shared.font(withFamily: font, traits: [bold ? .boldFontMask : [], italic ? .italicFontMask : []],
                                             weight: 5, size: size) ?? NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor(white: 0.13, alpha: 1),
        ]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// Shows the current slide's notes (committing the previous slide's first).
    func reload() {
        let slide = controller.currentSlide
        if slide?.id != slideID { commit() }
        guard let slide else {
            slideID = nil
            textView.string = ""
            textView.isEditable = false
            return
        }
        // People a shared presentation is shared with to comment on can read the notes, not change them.
        textView.isEditable = controller.canEditContent
        if slide.id == slideID, slide.notes == shownNotes { return }
        if slide.id == slideID, window?.firstResponder === textView { return }
        slideID = slide.id
        shownNotes = slide.notes
        textView.textStorage?.setAttributedString(Self.attributedString(slide.notes))
        textView.localUndoManager.removeAllActions()
        textView.needsDisplay = true
    }

    static func attributedString(_ notes: TextBody) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in notes.paragraphs.enumerated() {
            for run in paragraph.runs where !run.text.isEmpty {
                result.append(NSAttributedString(string: run.text, attributes: attributes(bold: run.style.bold == true, italic: run.style.italic == true,
                                                                                         underline: run.style.underline == true)))
            }
            if index < notes.paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes(bold: false, italic: false, underline: false)))
            }
        }
        return result
    }

    /// The notes as a text body: paragraphs with bold, italic and underline.
    func currentNotes() -> TextBody {
        guard let storage = textView.textStorage else { return shownNotes }
        let string = storage.string as NSString
        var paragraphs: [TextParagraph] = []
        var location = 0
        repeat {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            var content = range
            if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
            var runs: [TextRun] = []
            storage.enumerateAttributes(in: content) { attributes, runRange, _ in
                let font = attributes[.font] as? NSFont
                let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
                var style = CharacterStyle()
                if traits.contains(.boldFontMask) { style.bold = true }
                if traits.contains(.italicFontMask) { style.italic = true }
                if (attributes[.underlineStyle] as? Int ?? 0) != 0 { style.underline = true }
                let text = string.substring(with: runRange)
                if let last = runs.last, last.style == style { runs[runs.count - 1].text += text } else { runs.append(TextRun(text, style: style)) }
            }
            paragraphs.append(TextParagraph(runs: runs))
            location = NSMaxRange(range)
        } while location < string.length
        if string.hasSuffix("\n") { paragraphs.append(TextParagraph()) }
        return TextBody(paragraphs: paragraphs)
    }

    /// Saves typed notes into the presentation, unless they still say what the slide had.
    func textDidChange(_ notification: Notification) {
        guard controller.collaboration?.isLive == true else { return }
        liveCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        liveCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
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

    func commit() {
        liveCommit?.cancel()
        guard let slideID, controller.canEditContent else { return }
        let notes = currentNotes()
        guard notes.plainText != shownNotes.plainText || Self.signature(notes) != Self.signature(shownNotes) else { return }
        shownNotes = notes
        controller.setNotes(notes, slideID: slideID)
    }

    /// The parts of notes this view can show, for telling real edits from round-trip differences.
    private static func signature(_ notes: TextBody) -> [[String]] {
        notes.paragraphs.map { paragraph in
            paragraph.runs.filter { !$0.text.isEmpty }.map { "\($0.style.bold == true)\($0.style.italic == true)\($0.style.underline == true)\($0.text)" }
        }
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        let range = textView.selectedRange()
        guard let storage = textView.textStorage else { return }
        if range.length == 0 {
            if let font = textView.typingAttributes[.font] as? NSFont {
                let has = NSFontManager.shared.traits(of: font).contains(trait)
                textView.typingAttributes[.font] = has ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
            }
            return
        }
        var all = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, !NSFontManager.shared.traits(of: font).contains(trait) { all = false }
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: all ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait),
                                 range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func toggleUnderline() {
        let range = textView.selectedRange()
        guard let storage = textView.textStorage else { return }
        if range.length == 0 {
            let on = (textView.typingAttributes[.underlineStyle] as? Int ?? 0) == 0
            textView.typingAttributes[.underlineStyle] = on ? NSUnderlineStyle.single.rawValue : nil
            return
        }
        var all = true
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in if (value as? Int ?? 0) == 0 { all = false } }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        if all { storage.removeAttribute(.underlineStyle, range: range) } else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        textView.didChangeText()
    }
}
