import AppKit
import PuggleSlidesKit

/// Edit ▸ Find and replace: replacing is one undoable step, Replace all included.
extension PresentationController {
    /// Replaces one match; false when the text no longer holds it.
    @discardableResult
    func replaceMatch(_ match: TextMatch, with text: String, search: TextSearch) -> Bool {
        var replaced = false
        perform("Replace", update: [.content, .notes]) { replaced = $0.replace(match, with: text, search: search) }
        return replaced
    }

    /// Replaces every match; returns how many there were.
    func replaceAll(_ search: TextSearch, with text: String) -> Int {
        var count = 0
        perform("Replace All", update: [.content, .notes]) { count = $0.replaceAll(search, with: text) }
        return count
    }
}
