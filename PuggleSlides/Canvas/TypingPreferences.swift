import AppKit
import PuggleSlidesKit

/// PuggleSlides ▸ Settings ▸ Typing: smart quotes, smart dashes, capitals and spelling, for text on slides, in tables
/// and in speaker notes. They're the person's, kept in PuggleSlides' own settings for every presentation, and a change
/// reaches text being typed at once.
enum TypingPreferences {
    static let smartQuotesKey = "PPSmartQuotes"
    static let smartDashesKey = "PPSmartDashes"
    static let capitalizesKey = "PPAutoCapitalize"
    static let spellCheckKey = "PPSpellCheck"

    static var smartQuotes: Bool { value(smartQuotesKey, otherwise: true) }
    static var smartDashes: Bool { value(smartDashesKey, otherwise: true) }
    static var capitalizesWords: Bool { value(capitalizesKey, otherwise: false) }
    static var checksSpelling: Bool { value(spellCheckKey, otherwise: true) }

    private static func value(_ key: String, otherwise fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    /// Sets a text view to follow them. (Capitals are typed by the text views themselves: see `capitalizeWord`.)
    static func apply(to textView: NSTextView) {
        if textView.isAutomaticQuoteSubstitutionEnabled != smartQuotes { textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes }
        if textView.isAutomaticDashSubstitutionEnabled != smartDashes { textView.isAutomaticDashSubstitutionEnabled = smartDashes }
        if textView.isContinuousSpellCheckingEnabled != checksSpelling { textView.isContinuousSpellCheckingEnabled = checksSpelling }
    }

    /// After a change, in Settings or from Tools ▸ Spell check: the text being typed in every window, and every
    /// window's speaker notes, follow it straight away.
    static func applyEverywhere() {
        for window in NSApp.windows {
            guard let controller = window.windowController as? DocumentWindowController else { continue }
            if let textView = controller.canvas.editor?.textView { apply(to: textView) }
            apply(to: controller.notes.textView)
        }
    }

    // MARK: macOS's own capitals

    /// macOS can capitalize sentences itself (System Settings ▸ Keyboard ▸ Capitalize words automatically), which
    /// would leave Settings ▸ Automatically capitalize words saying one thing and the text doing another. So it's
    /// kept out of PuggleSlides' text views, whichever way it's set: from macOS 26 by telling the spelling checker...
    static func checkingOptions(_ options: [NSSpellChecker.OptionKey: Any]) -> [NSSpellChecker.OptionKey: Any] {
        guard #available(macOS 26.0, *) else { return options }
        var options = options
        options[.automaticCapitalizationEnabledKey] = false
        return options
    }

    /// ...and before then by leaving out of what it would change any correction that only gives the first word of a
    /// sentence its capital. Its other corrections stay.
    static func withoutCapitals(_ results: [NSTextCheckingResult], in text: NSString) -> [NSTextCheckingResult] {
        results.filter { !isCapital($0, in: text) }
    }

    private static func isCapital(_ result: NSTextCheckingResult, in text: NSString) -> Bool {
        guard result.resultType == .correction, let replacement = result.replacementString, NSMaxRange(result.range) <= text.length,
              let change = AutoCapitalization.change(in: text, wordEndingAt: NSMaxRange(result.range)),
              NSLocationInRange(change.range.location, result.range) else { return false }
        let capitalized = NSMutableString(string: text.substring(with: result.range))
        capitalized.replaceCharacters(in: NSRange(location: change.range.location - result.range.location, length: change.range.length),
                                      with: change.capital)
        return capitalized as String == replacement
    }
}

extension NSTextView {
    /// Settings ▸ Automatically capitalize words, called after each piece of typing: once the space or line break
    /// after the first word of a sentence is typed, the word gets its capital, as a step of its own, so Undo takes
    /// back just the capital.
    func capitalizeWord(afterTyping typed: Any) {
        guard TypingPreferences.capitalizesWords, !hasMarkedText(), let storage = textStorage else { return }
        let string = (typed as? String) ?? (typed as? NSAttributedString)?.string ?? ""
        let length = (string as NSString).length
        guard length == 1, let scalar = string.unicodeScalars.first, CharacterSet.whitespacesAndNewlines.contains(scalar) else { return }
        let caret = selectedRange()
        guard caret.length == 0, caret.location >= length,
              let change = AutoCapitalization.change(in: storage.mutableString, wordEndingAt: caret.location - length) else { return }
        breakUndoCoalescing()
        guard shouldChangeText(in: change.range, replacementString: change.capital) else { return }
        storage.replaceCharacters(in: change.range, with: change.capital)
        didChangeText()
    }
}
