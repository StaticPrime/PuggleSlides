import AppKit
import PuggleSlidesKit

/// Keys for moving between the filmstrip, the slide and the speaker notes.
extension DocumentWindowController {
    /// ⌥⇧⌘F: the filmstrip (or grid view's slides).
    func ppFocusFilmstrip(_ sender: Any?) {
        finishEditing()
        window?.makeFirstResponder(isGridView ? grid : filmstrip)
    }

    /// ⌥⇧⌘C: the slide.
    func ppFocusCanvas(_ sender: Any?) {
        if isGridView { setGridView(false) }
        focusCanvas()
    }

    /// ⌥⇧⌘S: the speaker notes, shown if they were hidden.
    func ppFocusSpeakerNotes(_ sender: Any?) {
        finishEditing()
        if isGridView { setGridView(false) }
        if !state.showsSpeakerNotes { ppToggleSpeakerNotes(nil) }
        window?.makeFirstResponder(notes.textView)
    }
}
