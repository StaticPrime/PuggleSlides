#if DEBUG
import AppKit
import PuggleSlidesKit

/// Settings ▸ Typing: smart quotes, smart dashes, capitals and spelling, in text boxes and speaker notes; a change
/// reaching text being typed at once; and macOS's own capitals kept out.
extension SelfTest {
    static func addTypingSteps(_ window: DocumentWindowController) {
        let controller = window.controller
        let canvas = window.canvas
        let notes = window.notes
        var slide: Slide { controller.currentSlide! }
        var typed: String { canvas.editor?.textView.string ?? "<not editing>" }
        let defaults = UserDefaults.standard
        let keys = [TypingPreferences.smartQuotesKey, TypingPreferences.smartDashesKey, TypingPreferences.capitalizesKey,
                    TypingPreferences.spellCheckKey]
        // A debug build shares PuggleSlides' settings: the person's own are put back at the end.
        let saved = keys.map { defaults.object(forKey: $0) }
        func set(quotes: Bool, dashes: Bool, capitals: Bool) {
            defaults.set(quotes, forKey: TypingPreferences.smartQuotesKey)
            defaults.set(dashes, forKey: TypingPreferences.smartDashesKey)
            defaults.set(capitals, forKey: TypingPreferences.capitalizesKey)
            TypingPreferences.applyEverywhere()
        }
        /// Starts a new text box there, to type in.
        func newTextBox(at point: SlidePoint) {
            canvas.endEditing()
            window.setTool(.textBox)
            mouse(.leftMouseDown, at: point, in: window)
            mouse(.leftMouseUp, at: point, in: window)
        }

        step {
            // A blank slide of its own, so every click lands on empty space.
            window.ppNewSlide(nil)
            if let blank = controller.presentation.theme(for: slide).layout(kind: .blank) { controller.applyLayout(blank.id) }
            set(quotes: true, dashes: true, capitals: false)
            newTextBox(at: SlidePoint(x: 120, y: 70))
            type("\"Walks\" -- daily ", into: window.window)
            wait(upTo: 5) { typed.contains("“") && typed.contains("—") }
        }
        step {
            check(typed == "“Walks” — daily ", "smart quotes and dashes, with them on", typed)
            set(quotes: false, dashes: false, capitals: false)
            check(canvas.editor?.textView.isAutomaticQuoteSubstitutionEnabled == false
                  && canvas.editor?.textView.isAutomaticDashSubstitutionEnabled == false, "turning them off reaches the text being typed")
            newTextBox(at: SlidePoint(x: 120, y: 160))
            type("\"Naps\" -- often ", into: window.window)
            wait(upTo: 1.5) { false }
        }
        step {
            check(typed == "\"Naps\" -- often ", "straight quotes and dashes, with them off", typed)
            set(quotes: true, dashes: true, capitals: true)
            newTextBox(at: SlidePoint(x: 120, y: 250))
            type("hello there. this is it!\rand more", into: window.window)
        }
        step {
            check(typed == "Hello there. This is it!\nAnd more", "capitals for the first word of each sentence and line, with them on", typed)
            type(". then", into: window.window)
        }
        step {
            type(" ", into: window.window)
        }
        step {
            check(typed == "Hello there. This is it!\nAnd more. Then ", "the capital comes as the space after the word is typed", typed)
            canvas.editor?.textView.undoManager?.undo()
        }
        step {
            check(typed == "Hello there. This is it!\nAnd more. then ", "Undo takes back just the capital", typed)
            set(quotes: true, dashes: true, capitals: false)
            newTextBox(at: SlidePoint(x: 520, y: 70))
            type("hello there. this ", into: window.window)
        }
        step {
            check(typed == "hello there. this ", "no capitals, with them off", typed)
            // macOS's own capitals are kept out as well, and its other corrections aren't.
            guard let editor = canvas.editor else { return check(false, "still typing in the text box") }
            var types = NSTextCheckingResult.CheckingType.correction.rawValue
            let options = editor.textView(editor.textView, willCheckTextIn: NSRange(location: 0, length: 0), options: [:], types: &types)
            if #available(macOS 26.0, *) {
                check(options[.automaticCapitalizationEnabledKey] as? Bool == false, "macOS is told not to capitalize slides' text")
            }
            let results = [NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 0, length: 5), replacementString: "Hello"),
                           NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 6, length: 5), replacementString: "their")]
            let kept = editor.textView(editor.textView, didCheckTextIn: NSRange(location: 0, length: 18), types: types, options: [:],
                                       results: results, orthography: NSOrthography.defaultOrthography(forLanguage: "en"), wordCount: 3)
            check(kept.map(\.replacementString) == ["their"], "macOS's capitals are left out of its corrections, and its other corrections stay",
                  "\(kept.map(\.replacementString))")
        }
        step {
            // Speaker notes follow the same settings.
            canvas.endEditing()
            set(quotes: false, dashes: false, capitals: true)
            check(!notes.textView.isAutomaticQuoteSubstitutionEnabled && !notes.textView.isAutomaticDashSubstitutionEnabled,
                  "speaker notes follow the settings too")
            window.window?.makeFirstResponder(notes.textView)
            type("bring treats. lots of them", into: window.window)
            window.window?.makeFirstResponder(canvas)
            check(slide.notes.plainText == "Bring treats. Lots of them", "and get capitals", slide.notes.plainText)
        }
        step {
            // Tools ▸ Spell check is Settings ▸ Check spelling as you type, and reaches text being typed and the notes.
            newTextBox(at: SlidePoint(x: 520, y: 160))
            let spelling = TypingPreferences.checksSpelling
            window.ppToggleSpellCheck(nil)
            check(TypingPreferences.checksSpelling == !spelling && canvas.editor?.textView.isContinuousSpellCheckingEnabled == !spelling
                  && notes.textView.isContinuousSpellCheckingEnabled == !spelling, "Tools ▸ Spell check changes the setting, everywhere at once")
            window.ppToggleSpellCheck(nil)
            check(TypingPreferences.checksSpelling == spelling && notes.textView.isContinuousSpellCheckingEnabled == spelling, "and back")
        }
        step {
            canvas.endEditing()
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            TypingPreferences.applyEverywhere()
        }
    }
}
#endif
