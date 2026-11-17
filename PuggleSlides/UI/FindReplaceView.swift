import AppKit
import PuggleSlidesKit
import SwiftUI

/// The Find and replace dialog's fields, and what it last found.
@Observable
final class FindReplaceState {
    var query = ""
    var replacement = ""
    var matchesCase = false
    var usesRegularExpression = false
    /// "3 of 12", "No results", "Replaced 4 instances" …
    var message: String?
    var messageIsProblem = false
    /// Bumped to put the cursor back in Find.
    var focusRequest = 0

    var search: TextSearch { TextSearch(query, matchesCase: matchesCase, usesRegularExpression: usesRegularExpression) }
}

/// What the dialog asks its window to do.
protocol FindReplaceActions: AnyObject {
    func findChanged()
    func findNext(forward: Bool)
    func replaceCurrent()
    func replaceAllMatches()
    func closeFindReplace()
}

/// Edit ▸ Find and replace (⇧⌘H). It stays open while you work on the slides.
struct FindReplaceView: View {
    @Bindable var state: FindReplaceState
    let actions: FindReplaceActions
    @FocusState private var findFocused: Bool

    private var canSearch: Bool { !state.query.isEmpty && state.search.isValid }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    label("Find")
                    PanelField(placeholder: "", text: $state.query)
                        .focused($findFocused)
                        .onSubmit { actions.findNext(forward: true) }
                }
                GridRow {
                    label("Replace with")
                    PanelField(placeholder: "", text: $state.replacement)
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Match case", isOn: $state.matchesCase)
                        Toggle("Match using regular expressions", isOn: $state.usesRegularExpression)
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                }
            }
            Text(state.message ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(state.messageIsProblem ? Color.red : Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: 8) {
                PanelButton(title: "Replace", primary: false, isEnabled: canSearch) { actions.replaceCurrent() }
                PanelButton(title: "Replace all", primary: false, isEnabled: canSearch) { actions.replaceAllMatches() }
                Spacer()
                PanelButton(title: "Prev", primary: false, isEnabled: canSearch) { actions.findNext(forward: false) }
                PanelButton(title: "Next", isEnabled: canSearch) { actions.findNext(forward: true) }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: state.query) { _, _ in actions.findChanged() }
        .onChange(of: state.matchesCase) { _, _ in actions.findChanged() }
        .onChange(of: state.usesRegularExpression) { _, _ in actions.findChanged() }
        .onAppear { findFocused = true }
        .onChange(of: state.focusRequest) { _, _ in findFocused = true }
        .onExitCommand { actions.closeFindReplace() }
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(Theme.primaryText).gridColumnAlignment(.leading)
    }
}

/// Calls back when a panel closes, so its owner can let go of it.
final class PanelCloseObserver: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}
