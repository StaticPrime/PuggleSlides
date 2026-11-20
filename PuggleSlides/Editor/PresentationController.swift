import AppKit
import PuggleSlidesKit

/// What changed, so views know what to refresh.
struct PresentationUpdate: OptionSet {
    let rawValue: Int
    /// Elements, text or backgrounds on slides.
    static let content = PresentationUpdate(rawValue: 1)
    /// Slides added, removed, moved or skipped.
    static let slides = PresentationUpdate(rawValue: 2)
    static let selection = PresentationUpdate(rawValue: 4)
    /// Themes, layouts or the slide size: every slide looks different.
    static let theme = PresentationUpdate(rawValue: 8)
    static let notes = PresentationUpdate(rawValue: 16)
    /// Comment threads added, answered, resolved or removed.
    static let comments = PresentationUpdate(rawValue: 32)
    static let all: PresentationUpdate = [.content, .slides, .selection, .theme, .notes, .comments]
}

/// Owns a window's editing: the current slide, selections, and edits with undo.
final class PresentationController {
    /// Weak: a window's views can outlive its document by a moment while the window closes.
    private(set) weak var document: PresentationDocument?
    /// The presentation as last stored, shown if the document has already gone away.
    private var lastPresentation: Presentation
    let state: EditorState
    /// Tells this window's clipboard contents apart from other windows'.
    let documentID = UUID()
    /// Called after every change with what needs refreshing.
    var onUpdate: ((PresentationUpdate) -> Void)?

    private(set) var currentSlideID: UUID?
    /// Slides selected in the filmstrip; always includes the current slide.
    private(set) var selectedSlideIDs: Set<UUID> = []
    /// Elements selected on the current slide, in the order they were picked.
    private(set) var selectedElementIDs: [UUID] = []
    /// Bumped when themes, layouts or the slide size change, so every thumbnail redraws.
    private(set) var themeRevision = 0
    /// The cells selected in the selected table; nil when the whole table (or no table) is selected.
    var tableSelection: TableCellRange?
    /// Which borders of the selected cells the border controls change (the toolbar's border menu).
    var tableBorderPosition = TableBorderPosition.all
    /// While the theme builder is open: the theme's pages being edited, and how to put them back.
    private(set) var builder: ThemeBuilderSession?
    /// While the presentation is shared: its part in that, which takes in edits as they're recorded and keeps undo.
    weak var collaboration: PresentationCollaboration?

    private struct Snapshot {
        var presentation: Presentation
        var slideID: UUID?
        var slideSelection: Set<UUID>
        var elements: [UUID]
    }

    private var interactiveStart: Snapshot?

    init(document: PresentationDocument, state: EditorState) {
        self.document = document
        self.state = state
        lastPresentation = document.presentation
        currentSlideID = document.presentation.slides.first?.id
        selectedSlideIDs = currentSlideID.map { [$0] } ?? []
    }

    var presentation: Presentation { builder?.proxy ?? document?.presentation ?? lastPresentation }
    var undoManager: UndoManager? { builder?.undoManager ?? document?.undoManager }
    /// The presentation itself, never the theme builder's pages.
    var realPresentation: Presentation { document?.presentation ?? lastPresentation }

    /// Whether the slides may be changed here: not while a shared presentation is only to be commented on (or is still
    /// opening).
    var canEditContent: Bool { state.access == .full }

    /// Whether edits go to a shared presentation's session, as changes and undo steps of their own.
    private var sharedSession: PresentationCollaboration? { collaboration?.isLive == true ? collaboration : nil }

    /// Puts an edited presentation in the document. In the theme builder the edit is to the theme's pages, which are
    /// mapped back into the real theme as they change.
    private func store(_ presentation: Presentation) {
        if var session = builder {
            var proxy = presentation
            ThemeBuilderSession.syncMaster(&proxy, themeID: session.themeID)
            session.proxy = proxy
            builder = session
            let real = session.real(from: proxy)
            lastPresentation = real
            document?.presentation = real
            collaboration?.noteLocalChange()
            return
        }
        lastPresentation = presentation
        document?.presentation = presentation
        collaboration?.noteLocalChange()
    }

    // MARK: Shared presentations

    /// Shows the presentation as other people changed it (or as a shared presentation's parts say it is): no undo, and
    /// the selection kept wherever it still can be. With the theme builder open, the builder carries on over it.
    func applyShared(_ shared: Presentation, update: PresentationUpdate) {
        let before = (currentSlideID, selectedSlideIDs, selectedElementIDs)
        if var session = builder {
            session.base = shared
            builder = session
            let real = session.real(from: session.proxy)
            lastPresentation = real
            document?.presentation = real
        } else {
            lastPresentation = shared
            document?.presentation = shared
        }
        if update.contains(.theme) { themeRevision += 1 }
        repairSelection()
        var update = update
        if (currentSlideID, selectedSlideIDs, selectedElementIDs) != before { update.insert(.selection) }
        notify(update)
    }

    /// Replaces the whole presentation, as Revert would: a shared presentation's copy from iCloud.
    func replacePresentation(_ shared: Presentation) {
        lastPresentation = shared
        document?.presentation = shared
        reloadFromDocument()
    }

    /// Undo in a shared presentation brings back what was selected, where it still exists.
    func restoreSharedSelection(slideID: UUID?, elements: [UUID]) {
        if let slideID, presentation.slideIndex(id: slideID) != nil {
            currentSlideID = slideID
            selectedSlideIDs = [slideID]
        }
        repairSelection()
        selectedElementIDs = elements.filter { currentSlide?.element(id: $0) != nil }
        notify(.selection)
    }

    /// `edited` with only its comments taken, onto `original`: what someone who may only comment can change.
    private static func keepingComments(of edited: Presentation, in original: Presentation) -> Presentation {
        var result = original
        let threads = Dictionary(edited.slides.map { ($0.id, $0.comments) }, uniquingKeysWith: { first, _ in first })
        for index in result.slides.indices {
            if let comments = threads[result.slides[index].id] { result.slides[index].comments = comments }
        }
        return result
    }

    func startThemeBuilder(_ session: ThemeBuilderSession, showing pageID: UUID) {
        builder = session
        currentSlideID = pageID
        selectedSlideIDs = [pageID]
        selectedElementIDs = []
        tableSelection = nil
        themeRevision += 1
        notify([.slides, .content, .selection, .theme])
    }

    /// Leaves the builder with the document as it was when it opened (closing then records the change as one step).
    func finishThemeBuilder(restoring base: Presentation, returnTo slideID: UUID?) {
        builder = nil
        store(base)
        currentSlideID = slideID.flatMap { id in base.slideIndex(id: id) != nil ? id : nil } ?? base.slides.first?.id
        selectedSlideIDs = currentSlideID.map { [$0] } ?? []
        selectedElementIDs = []
        tableSelection = nil
        themeRevision += 1
        notify([.slides, .content, .selection, .theme])
    }

    var currentSlideIndex: Int? { currentSlideID.flatMap(presentation.slideIndex(id:)) }

    var currentSlide: Slide? { currentSlideIndex.map { presentation.slides[$0] } }

    var selectedElements: [SlideElement] {
        guard let slide = currentSlide else { return [] }
        return selectedElementIDs.compactMap(slide.element(id:))
    }

    /// The selected slides in presentation order.
    var selectedSlideIndexes: [Int] {
        presentation.slides.indices.filter { selectedSlideIDs.contains(presentation.slides[$0].id) }
    }

    func notify(_ update: PresentationUpdate) {
        onUpdate?(update)
    }

    /// Called when the document's contents were replaced (Revert, or a file applied after the window opened).
    func reloadFromDocument() {
        // A revert replaces everything, the theme builder's pages included.
        builder = nil
        let slides = presentation.slides
        if currentSlideID == nil || !slides.contains(where: { $0.id == currentSlideID }) { currentSlideID = slides.first?.id }
        selectedSlideIDs = currentSlideID.map { [$0] } ?? []
        selectedElementIDs = []
        themeRevision += 1
        notify(.all)
    }

    // MARK: Selection

    /// Shows a slide. `extend` adds the range from the current slide (Shift-click); `toggle` adds or removes it (⌘-click).
    func selectSlide(_ id: UUID, extend: Bool = false, toggle: Bool = false) {
        guard let index = presentation.slideIndex(id: id) else { return }
        if extend, let current = currentSlideIndex {
            let range = min(current, index)...max(current, index)
            selectedSlideIDs = Set(range.map { presentation.slides[$0].id })
        } else if toggle {
            if selectedSlideIDs.contains(id), selectedSlideIDs.count > 1 {
                selectedSlideIDs.remove(id)
                if currentSlideID == id {
                    currentSlideID = presentation.slides.first { selectedSlideIDs.contains($0.id) }?.id
                    selectedElementIDs = []
                }
                notify(.selection)
                return
            }
            selectedSlideIDs.insert(id)
        } else {
            selectedSlideIDs = [id]
        }
        if currentSlideID != id {
            currentSlideID = id
            selectedElementIDs = []
        }
        notify(.selection)
    }

    func selectSlides(_ ids: Set<UUID>, current: UUID) {
        guard presentation.slideIndex(id: current) != nil else { return }
        selectedSlideIDs = ids.union([current])
        if currentSlideID != current {
            selectedElementIDs = []
            tableSelection = nil
        }
        currentSlideID = current
        notify(.selection)
    }

    func selectElements(_ ids: [UUID]) {
        guard let slide = currentSlide else { return }
        var seen = Set<UUID>()
        let valid = ids.filter { slide.element(id: $0) != nil && seen.insert($0).inserted }
        guard valid != selectedElementIDs else { return }
        selectedElementIDs = valid
        tableSelection = nil
        notify(.selection)
    }

    // MARK: Edits with undo

    private var snapshot: Snapshot {
        Snapshot(presentation: presentation, slideID: currentSlideID, slideSelection: selectedSlideIDs, elements: selectedElementIDs)
    }

    /// Applies `edit` as one undoable step named `actionName`. Afterwards the given slide and elements are selected
    /// (the current ones by default); undo brings back the selection from before.
    func perform(_ actionName: String, update: PresentationUpdate = .content, showing slideID: UUID? = nil, selecting elements: [UUID]? = nil,
                 _ edit: (inout Presentation) -> Void) {
        let before = snapshot
        var presentation = self.presentation
        edit(&presentation)
        switch state.access {
        case .full: break
        // Someone who may only comment changes comments, and nothing else.
        case .commentOnly: presentation = Self.keepingComments(of: presentation, in: before.presentation)
        // A shared presentation that's opening, or can't save to iCloud, doesn't change at all.
        case .locked, .offline: presentation = before.presentation
        }
        // Animations go with their elements.
        for index in presentation.slides.indices {
            let slide = presentation.slides[index]
            guard !slide.animations.isEmpty else { continue }
            let ids = Set(slide.elements.map(\.id))
            if slide.animations.contains(where: { !ids.contains($0.elementID) }) { presentation.slides[index].pruneAnimations() }
        }
        guard presentation != before.presentation else {
            if let slideID { selectSlide(slideID) }
            if let elements { selectElements(elements) }
            return
        }
        store(presentation)
        if let slideID, presentation.slideIndex(id: slideID) != nil {
            currentSlideID = slideID
            selectedSlideIDs = [slideID]
        }
        repairSelection()
        if let elements { selectedElementIDs = elements.filter { currentSlide?.element(id: $0) != nil } }
        if update.contains(.theme) { themeRevision += 1 }
        record(before: before, after: snapshot, actionName: actionName, update: update)
        notify(update.union(.selection))
    }

    private func record(before: Snapshot, after: Snapshot, actionName: String, update: PresentationUpdate) {
        // In a shared presentation the session makes the undo step: one that takes back only this Mac's changes. (The
        // theme builder keeps its own undo for its pages; leaving it makes the shared step.)
        if builder == nil, let session = sharedSession {
            session.recorded(actionName: actionName, selection: SharedSelection(slideID: before.slideID, elements: before.elements))
            return
        }
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.restore(before, other: after, actionName: actionName, update: update)
        }
        undoManager?.setActionName(actionName)
    }

    private func restore(_ target: Snapshot, other: Snapshot, actionName: String, update: PresentationUpdate) {
        store(target.presentation)
        currentSlideID = target.slideID
        selectedSlideIDs = target.slideSelection
        selectedElementIDs = target.elements
        repairSelection()
        if update.contains(.theme) { themeRevision += 1 }
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.restore(other, other: target, actionName: actionName, update: update)
        }
        undoManager?.setActionName(actionName)
        notify(update.union(.selection))
    }

    /// Keeps the current slide and selection pointing at things that exist.
    private func repairSelection() {
        let slides = presentation.slides
        if let id = currentSlideID, slides.contains(where: { $0.id == id }) {
            // Fine.
        } else {
            currentSlideID = slides.first?.id
        }
        let ids = Set(slides.map(\.id))
        selectedSlideIDs = selectedSlideIDs.intersection(ids)
        if let id = currentSlideID { selectedSlideIDs.insert(id) }
        if let slide = currentSlide {
            selectedElementIDs = selectedElementIDs.filter { slide.element(id: $0) != nil }
        } else {
            selectedElementIDs = []
        }
    }

    // MARK: Interactive edits (dragging)

    /// Starts an edit that updates live (a drag); `endInteractive` records it as one undo step.
    func beginInteractive() {
        interactiveStart = snapshot
    }

    var isInteractive: Bool { interactiveStart != nil }

    func updateInteractive(_ update: PresentationUpdate = .content, _ edit: (inout Presentation) -> Void) {
        guard interactiveStart != nil, canEditContent else { return }
        // Edit a copy: the edit may read the controller (and so the document) while it runs.
        var presentation = self.presentation
        edit(&presentation)
        store(presentation)
        notify(update)
    }

    func endInteractive(actionName: String, update: PresentationUpdate = .content) {
        guard let start = interactiveStart else { return }
        interactiveStart = nil
        if builder == nil, let session = sharedSession {
            session.recorded(actionName: actionName, selection: SharedSelection(slideID: start.slideID, elements: start.elements))
            notify(update)
            return
        }
        guard start.presentation != presentation else { return }
        record(before: start, after: snapshot, actionName: actionName, update: update)
        notify(update)
    }

    func cancelInteractive() {
        guard let start = interactiveStart else { return }
        interactiveStart = nil
        // Shared: other people's changes made meanwhile stay; only this edit goes.
        if builder == nil, let session = sharedSession {
            session.cancelGroup()
            notify(.content)
            return
        }
        store(start.presentation)
        notify(.content)
    }

    // MARK: Lookups

    func style(of element: SlideElement) -> ElementStyle? {
        guard let slide = currentSlide else { return nil }
        return presentation.style(for: element, on: slide)
    }

    func placement(of element: SlideElement) -> Placement {
        guard let slide = currentSlide else { return element.placement ?? Placement(frame: .zero) }
        return presentation.placement(of: element, on: slide)
    }

    /// Edits the current slide's elements with these ids.
    func editElements(_ ids: [UUID], _ actionName: String, update: PresentationUpdate = .content,
                      _ edit: (inout SlideElement, ElementStyle) -> Void) {
        guard let slideIndex = currentSlideIndex, !ids.isEmpty else { return }
        perform(actionName, update: update) { presentation in
            let slide = presentation.slides[slideIndex]
            for id in ids {
                guard let index = slide.elementIndex(id: id) else { continue }
                let style = presentation.style(for: slide.elements[index], on: slide)
                edit(&presentation.slides[slideIndex].elements[index], style)
            }
        }
    }

    func editSelectedElements(_ actionName: String, _ edit: (inout SlideElement, ElementStyle) -> Void) {
        editElements(selectedElementIDs, actionName, edit)
    }
}
