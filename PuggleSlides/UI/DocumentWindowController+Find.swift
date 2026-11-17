import AppKit
import PuggleSlidesKit
import SwiftUI

/// Edit ▸ Find and replace (⇧⌘H), Find (⌘F), Find again (⌘G) and Find previous (⇧⌘G).
extension DocumentWindowController: FindReplaceActions {
    func ppFind(_ sender: Any?) { showFindReplace() }
    func ppFindAndReplace(_ sender: Any?) { showFindReplace() }
    func ppFindNext(_ sender: Any?) { findAgain(forward: true) }
    func ppFindPrevious(_ sender: Any?) { findAgain(forward: false) }

    private func findAgain(forward: Bool) {
        if findState.query.isEmpty || findPanel == nil { showFindReplace() } else { findNext(forward: forward) }
    }

    /// Shows the dialog above the window; text selected in a text box becomes the search.
    func showFindReplace() {
        if let editor = canvas.editor {
            let selected = (editor.textView.string as NSString).substring(with: editor.textView.selectedRange())
            if !selected.isEmpty, !selected.contains("\n") { findState.query = selected }
        }
        finishEditing()
        guard let window else { return }
        if let panel = findPanel {
            panel.makeKeyAndOrderFront(nil)
            findState.focusRequest += 1
            return
        }
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.title = "Find and replace"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentViewController = NSHostingController(rootView: FindReplaceView(state: findState, actions: self))
        let observer = PanelCloseObserver { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.parent?.removeChildWindow(panel)
            self.findPanel = nil
            self.findPanelObserver = nil
            self.findResults = []
            self.currentFindMatch = nil
            self.updateFindHighlights()
            self.window?.makeFirstResponder(self.canvas)
        }
        panel.delegate = observer
        findPanelObserver = observer
        findPanel = panel
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let frame = window.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 130))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        findChanged()
    }

    func closeFindReplace() { findPanel?.close() }

    // MARK: FindReplaceActions

    /// The search changed: every match again, and the first one from the current slide on is shown.
    func findChanged() {
        currentFindMatch = nil
        refreshFindResults()
        if let first = firstMatch(forward: true) { show(first) }
    }

    func findNext(forward: Bool) {
        refreshFindResults()
        guard !findResults.isEmpty else { return }
        if let current = currentFindMatch, let index = findResults.firstIndex(of: current) {
            show(findResults[(index + (forward ? 1 : findResults.count - 1)) % findResults.count])
        } else if let match = firstMatch(forward: forward) {
            show(match)
        }
    }

    /// Replaces the match being shown and moves on to the next one.
    func replaceCurrent() {
        refreshFindResults()
        guard let match = currentFindMatch, let index = findResults.firstIndex(of: match) else {
            findNext(forward: true)
            return
        }
        finishEditing()
        let search = findState.search
        let replacement = findState.replacement
        guard controller.replaceMatch(match, with: replacement, search: search) else { return }
        currentFindMatch = nil
        refreshFindResults()
        guard !findResults.isEmpty else { return }
        // Past the replacement, which may itself match.
        var next = min(index, findResults.count)
        let end = match.range.lowerBound + (replacement as NSString).length
        while next < findResults.count, findResults[next].slideID == match.slideID, findResults[next].place == match.place,
              findResults[next].range.lowerBound < end {
            next += 1
        }
        show(findResults[next % findResults.count])
    }

    func replaceAllMatches() {
        let search = findState.search
        guard !findState.query.isEmpty, search.isValid else { return }
        finishEditing()
        let count = controller.replaceAll(search, with: findState.replacement)
        currentFindMatch = nil
        refreshFindResults()
        findState.messageIsProblem = false
        findState.message = count == 0 ? "No results" : count == 1 ? "Replaced 1 instance" : "Replaced \(count) instances"
    }

    // MARK: Matches

    /// Every match again after a change; the one shown stays if it's still there.
    func refreshFindResults() {
        let search = findState.search
        if findState.query.isEmpty || !search.isValid {
            findResults = []
            currentFindMatch = nil
            findState.message = search.isValid ? nil : "That regular expression isn’t valid"
            findState.messageIsProblem = !search.isValid
        } else {
            findResults = controller.presentation.matches(of: search)
            if let current = currentFindMatch, !findResults.contains(current) { currentFindMatch = nil }
            updateFindMessage()
        }
        updateFindHighlights()
    }

    private func updateFindMessage() {
        findState.messageIsProblem = false
        if findResults.isEmpty {
            findState.message = "No results"
        } else if let current = currentFindMatch, let index = findResults.firstIndex(of: current) {
            findState.message = "\(index + 1) of \(findResults.count)"
        } else {
            findState.message = findResults.count == 1 ? "1 result" : "\(findResults.count) results"
        }
    }

    /// The canvas marks the matches on the slide shown while the dialog is open.
    func updateFindHighlights() {
        let open = findPanel != nil
        let slideID = controller.currentSlideID
        canvas.findMatches = open ? findResults.filter { $0.slideID == slideID } : []
        canvas.currentFindMatch = open ? currentFindMatch : nil
    }

    /// The first match on or after the current slide (or the last on or before it, going back).
    private func firstMatch(forward: Bool) -> TextMatch? {
        let slides = controller.presentation.slides
        var indexes: [UUID: Int] = [:]
        for (index, slide) in slides.enumerated() { indexes[slide.id] = index }
        let current = controller.currentSlideIndex ?? 0
        if forward { return findResults.first { (indexes[$0.slideID] ?? 0) >= current } ?? findResults.first }
        return findResults.last { (indexes[$0.slideID] ?? 0) <= current } ?? findResults.last
    }

    /// Goes to a match: its slide, with its object selected, or its words selected in the speaker notes.
    private func show(_ match: TextMatch) {
        currentFindMatch = match
        if isGridView { setGridView(false) }
        controller.selectSlide(match.slideID)
        switch match.place {
        case .element(let path), .cell(let path, _, _):
            if let first = path.first { controller.selectElements([first]) }
        case .notes:
            controller.selectElements([])
            if !state.showsSpeakerNotes { ppToggleSpeakerNotes(nil) }
            notes.reload()
            let range = NSRange(location: match.range.lowerBound, length: match.range.count)
            if NSMaxRange(range) <= (notes.textView.string as NSString).length {
                notes.textView.setSelectedRange(range)
                notes.textView.scrollRangeToVisible(range)
                notes.textView.showFindIndicator(for: range)
            }
        }
        updateFindMessage()
        updateFindHighlights()
    }

    func validateFind(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(SlideCommands.ppFind(_:)), #selector(SlideCommands.ppFindAndReplace(_:)),
             #selector(SlideCommands.ppFindNext(_:)), #selector(SlideCommands.ppFindPrevious(_:)):
            return controller.currentSlide != nil
        default:
            return nil
        }
    }
}
