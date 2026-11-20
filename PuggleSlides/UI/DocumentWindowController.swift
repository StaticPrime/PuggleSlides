import AppKit
import PuggleSlidesKit
import SwiftUI
import UniformTypeIdentifiers

/// The field editor for this window's text fields. Its typing undo stays local, so editing the title or a
/// panel field never lands in the presentation's undo history.
final class LocalUndoFieldEditor: NSTextView {
    private let localUndoManager = UndoManager()
    override var undoManager: UndoManager? { localUndoManager }
}

/// The vertical split between the slide and the speaker notes.
final class NotesSplitView: NSSplitView {
    /// Called once the split view first has a real size, to place the divider.
    var onFirstLayout: (() -> Void)?

    override func layout() {
        super.layout()
        if bounds.height > 100, let action = onFirstLayout {
            onFirstLayout = nil
            action()
        }
    }

    override var dividerThickness: CGFloat { 9 }
    override var dividerColor: NSColor { Theme.canvas }

    override func drawDivider(in rect: NSRect) {
        Theme.canvas.setFill()
        rect.fill()
        // The grip: three dots in the middle.
        NSColor(white: 0.55, alpha: 1).setFill()
        for offset in [-6.0, 0, 6] {
            NSBezierPath(ovalIn: NSRect(x: rect.midX + offset - 1.5, y: rect.midY - 1.5, width: 3, height: 3)).fill()
        }
    }
}

/// A presentation's window. While its shared presentation can't save to iCloud it has no undo manager, so Undo and Redo
/// do nothing and the presentation's own steps wait, untouched, until iCloud's back.
final class DocumentWindow: NSWindow {
    var pausesUndo: () -> Bool = { false }

    override var undoManager: UndoManager? { pausesUndo() ? nil : super.undoManager }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if pausesUndo(), item.action == #selector(UndoCommands.undo(_:)) || item.action == #selector(UndoCommands.redo(_:)) { return false }
        return super.validateUserInterfaceItem(item)
    }
}

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, ChromeActions, SidebarActions {
    let state = EditorState()
    let controller: PresentationController
    let canvas: SlideEditingView
    let canvasScroll: CanvasScrollView
    let filmstrip: FilmstripView
    let notes: SpeakerNotesView
    /// View ▸ Grid view's slides.
    let grid: FilmstripView
    private let gridScroll = NSScrollView()
    private let gridZoom = NSSlider(value: 220, minValue: 120, maxValue: 420, target: nil, action: nil)
    private let filmstripScroll = NSScrollView()
    private let split = NotesSplitView()
    private var chromeHost: NSHostingView<ChromeView>!
    private var sidebarWidth: NSLayoutConstraint!
    /// The column of comment cards beside the slide; zero wide when there are no open comments.
    var commentsWidth: NSLayoutConstraint!
    /// Edit ▸ Find and replace: the dialog's fields, its panel while it's open, every match, and the one shown.
    let findState = FindReplaceState()
    var findPanel: NSPanel?
    var findPanelObserver: PanelCloseObserver?
    var findResults: [TextMatch] = []
    var currentFindMatch: TextMatch?
    /// A video or sound playing on the canvas.
    var clipPreview: ClipPreview?
    private var refreshScheduled = false
    private var colorTarget = ColorTarget.fill
    private var notesHeight: CGFloat = 112
    /// The divider has been placed once; until then, sizes the split view picks on its own aren't remembered.
    private var notesPlaced = false
    /// Paint format: the formatting picked up, waiting for a click on another shape.
    var paintFormat: SlideElement?
    /// The Motion panel's Play, while it plays.
    var motionPreview: MotionPreviewView?
    /// The last print settings used in this window.
    var printSettings = SlidePrintSettings()
    private lazy var fieldEditor: LocalUndoFieldEditor = {
        let editor = LocalUndoFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    var presentationDocument: PresentationDocument? { document as? PresentationDocument }

    init(document: PresentationDocument) {
        controller = PresentationController(document: document, state: state)
        canvas = SlideEditingView(controller: controller)
        canvasScroll = CanvasScrollView(editingView: canvas)
        filmstrip = FilmstripView(controller: controller)
        grid = FilmstripView(controller: controller, isGrid: true)
        notes = SpeakerNotesView(controller: controller)
        let window = DocumentWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        window.pausesUndo = { [weak state] in state?.access == .offline }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Theme.canvas
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 720, height: 420)
        window.isRestorable = true
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        buildContent()
        wireUp(document)

        if !document.importWarnings.isEmpty, let name = document.importedFileName {
            let list = Self.list(document.importWarnings.map(\.userDescription).sorted())
            state.banner = "This is a copy of “\(name)”. PuggleSlides can’t keep \(list) yet, so your original file was left untouched. Saving creates a new file."
        }
        state.showsSpeakerNotes = UserDefaults.standard.object(forKey: "PPShowSpeakerNotes") as? Bool ?? true
        state.showsComments = UserDefaults.standard.object(forKey: "PPShowComments") as? Bool ?? true
        refreshAll()
        updateStatus()
        window.setContentSize(NSSize(width: 1280, height: 860))
        window.center()
        updateTitlebarMetrics()
        DispatchQueue.main.async { [weak self] in
            self?.updateTitlebarMetrics()
            self?.canvasScroll.refit()
        }
        window.makeFirstResponder(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    private func buildContent() {
        guard let window else { return }
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.canvas.cgColor
        window.contentView = content

        chromeHost = NSHostingView(rootView: ChromeView(state: state, actions: self))
        chromeHost.sizingOptions = [.intrinsicContentSize]
        chromeHost.safeAreaRegions = []
        chromeHost.setContentHuggingPriority(.required, for: .vertical)
        chromeHost.setContentCompressionResistancePriority(.required, for: .vertical)

        filmstripScroll.documentView = filmstrip
        filmstripScroll.hasVerticalScroller = true
        filmstripScroll.autohidesScrollers = true
        filmstripScroll.scrollerStyle = .overlay
        filmstripScroll.drawsBackground = true
        filmstripScroll.backgroundColor = Theme.canvas

        split.isVertical = false
        split.delegate = self
        split.addArrangedSubview(canvasScroll)
        let notesFrame = NSView()
        notesFrame.wantsLayer = true
        notesFrame.layer?.cornerRadius = 8
        notesFrame.layer?.masksToBounds = true
        notesFrame.layer?.borderColor = Theme.slideBorder.cgColor
        notesFrame.layer?.borderWidth = 1
        notes.translatesAutoresizingMaskIntoConstraints = false
        notesFrame.addSubview(notes)
        NSLayoutConstraint.activate([
            notes.topAnchor.constraint(equalTo: notesFrame.topAnchor),
            notes.bottomAnchor.constraint(equalTo: notesFrame.bottomAnchor),
            notes.leadingAnchor.constraint(equalTo: notesFrame.leadingAnchor),
            notes.trailingAnchor.constraint(equalTo: notesFrame.trailingAnchor),
        ])
        split.addArrangedSubview(notesFrame)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        split.onFirstLayout = { [weak self] in self?.applyNotesVisibility() }
        notes.textView.setAccessibilityLabel("Speaker notes")

        gridScroll.documentView = grid
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.drawsBackground = true
        gridScroll.backgroundColor = Theme.canvas
        gridScroll.isHidden = true
        gridZoom.controlSize = .small
        gridZoom.target = self
        gridZoom.action = #selector(gridZoomChanged(_:))
        gridZoom.toolTip = "Zoom"
        gridZoom.isHidden = true

        let sidebar = NSHostingView(rootView: SidebarView(state: state, actions: self))
        sidebar.sizingOptions = []
        sidebar.safeAreaRegions = []
        let comments = NSHostingView(rootView: CommentsColumn(state: state, actions: self))
        comments.sizingOptions = []
        comments.safeAreaRegions = []
        for view in [chromeHost!, filmstripScroll, split, comments, gridScroll, gridZoom, sidebar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 0)
        commentsWidth = comments.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            chromeHost.topAnchor.constraint(equalTo: content.topAnchor),
            chromeHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chromeHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            filmstripScroll.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            filmstripScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            filmstripScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            filmstripScroll.widthAnchor.constraint(equalToConstant: FilmstripView.width),
            split.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: filmstripScroll.trailingAnchor),
            split.trailingAnchor.constraint(equalTo: comments.leadingAnchor, constant: -10),
            comments.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            comments.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            comments.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            commentsWidth,
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            gridScroll.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            gridScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            gridZoom.trailingAnchor.constraint(equalTo: gridScroll.trailingAnchor, constant: -24),
            gridZoom.bottomAnchor.constraint(equalTo: gridScroll.bottomAnchor, constant: -16),
            gridZoom.widthAnchor.constraint(equalToConstant: 140),
            sidebar.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebarWidth,
        ])
    }

    private func wireUp(_ document: PresentationDocument) {
        controller.onUpdate = { [weak self] update in self?.handle(update) }
        document.onStatusChange = { [weak self] in self?.updateStatus() }
        document.onReload = { [weak self] in self?.controller.reloadFromDocument() }
        document.onWillSave = { [weak self] in self?.finishEditing() }
        canvas.menuProvider = { [weak self] element in self?.canvasMenu(for: element) }
        canvas.onEditWordArt = { [weak self] id in self?.editWordArt(id) }
        canvas.onEditChart = { [weak self] in self?.editChart() }
        canvas.onPlayMedia = { [weak self] id in self?.playClipInEditor(id) }
        canvas.onDropMedia = { [weak self] urls, point in self?.insertDroppedMedia(urls, at: point) }
        applyRulerVisibility()
        canvas.onToolFinished = { [weak self] in
            self?.state.tool = .select
        }
        canvas.onEditingChange = { [weak self] in self?.scheduleStateRefresh() }
        canvas.onPaintFormat = { [weak self] target in
            guard let self, let source = self.paintFormat else { return false }
            self.controller.applyFormat(from: source, to: target.id)
            self.controller.selectElements([target.id])
            if !NSEvent.modifierFlags.contains(.option) {
                self.paintFormat = nil
                self.state.isPaintFormatActive = false
            }
            return true
        }
        canvasScroll.onZoomGesture = { [weak self] in
            guard let self else { return }
            self.state.zoom = self.canvasScroll.zoom
            self.state.zoomIsFit = false
        }
        filmstrip.menuProvider = { [weak self] index in self?.filmstripMenu(at: index) }
        grid.menuProvider = { [weak self] index in self?.filmstripMenu(at: index) }
        grid.onOpenSlide = { [weak self] id in
            self?.controller.selectSlide(id)
            self?.setGridView(false)
        }
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleStateRefresh() }
            }
        }
    }

    // MARK: Updates

    private func handle(_ update: PresentationUpdate) {
        if !update.isDisjoint(with: [.content, .theme, .slides, .selection]) {
            canvas.reloadSize()
            canvas.needsDisplay = true
        }
        if update.contains(.selection) || update.contains(.slides) {
            // A change of slide ends text editing on the old one.
            if let editor = canvas.editor, controller.currentSlide?.element(id: editor.elementID) == nil { canvas.endEditing() }
        }
        if update.contains(.theme) { canvasScroll.refit() }
        if !update.isDisjoint(with: [.content, .theme, .slides, .selection]) {
            if update.contains(.slides) || update.contains(.theme) {
                filmstrip.reload()
                if !gridScroll.isHidden { grid.reload() }
            }
            filmstrip.needsDisplay = true
            grid.needsDisplay = true
            if update.contains(.selection) { filmstrip.scrollToCurrent() }
        }
        if !update.isDisjoint(with: [.notes, .selection, .slides]) { notes.reload() }
        if findPanel != nil, !update.isDisjoint(with: [.content, .slides, .notes, .theme]) { refreshFindResults() }
        // VoiceOver follows the selection and hears about slides that change.
        if update.contains(.selection) {
            NSAccessibility.post(element: canvas, notification: .selectedChildrenChanged)
            NSAccessibility.post(element: filmstrip, notification: .selectedChildrenChanged)
        }
        if !update.isDisjoint(with: [.slides, .theme]) { NSAccessibility.post(element: canvas, notification: .layoutChanged) }
        if let editor = canvas.editor, update.contains(.content), !controller.isInteractive { editor.layout() }
        scheduleStateRefresh()
    }

    func scheduleStateRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.refreshState()
        }
    }

    private func refreshAll() {
        canvas.reloadSize()
        filmstrip.reload()
        notes.reload()
        refreshState()
    }

    /// Updates the toolbar and panels from the selection.
    func refreshState() {
        let editing = canvas.editor
        state.isEditingText = editing != nil
        let undoManager = state.access == .offline ? nil : editing?.textView.undoManager ?? controller.undoManager
        state.canUndo = undoManager?.canUndo ?? false
        state.canRedo = undoManager?.canRedo ?? false
        let kind = controller.selectionKind()
        if state.selectionKind != kind { state.selectionKind = kind }
        let hasText = editing != nil || controller.selectedElements.contains { $0.shape != nil && !$0.isLine }
        if state.hasText != hasText { state.hasText = hasText }
        let text = editing?.textSummary() ?? (hasText ? controller.textSummary() : TextSummary())
        if state.text != text { state.text = text }
        let shape = controller.shapeSummary()
        if state.shape != shape { state.shape = shape }
        let layout = controller.currentSlide.flatMap { controller.presentation.layout(for: $0)?.name } ?? ""
        if state.layoutName != layout { state.layoutName = layout }
        let builderTitle: String? = controller.builder.map { session in
            let pageID = controller.currentSlideID
            if session.isMaster(pageID) { return "Theme: \(session.pageName(pageID))" }
            let uses = pageID.map { id in session.base.slides.filter { $0.layoutID == id }.count } ?? 0
            return "Layout: \(session.pageName(pageID))" + (uses > 0 ? " (used by \(uses) slide\(uses == 1 ? "" : "s"))" : "")
        }
        if state.themeBuilderTitle != builderTitle { state.themeBuilderTitle = builderTitle }
        state.slideCount = controller.presentation.slides.count
        state.currentSlideIndex = controller.currentSlideIndex ?? 0
        syncComments()
        updateFindHighlights()
        syncClipPreview()
        state.revision += 1
        if state.tool != canvas.tool { canvas.tool = state.tool }
    }

    // MARK: Status and title

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        updateStatus()
        // A shared presentation of this person's that moved or was renamed is still found by its new name, and everyone
        // it's shared with sees the new name.
        if let document = presentationDocument, let collaboration = document.collaboration, collaboration.isOwner, let url = document.fileURL {
            CollaborationController.shared?.link(collaboration.id, to: url)
            collaboration.titleChanged()
        }
    }

    func updateStatus() {
        guard let document = presentationDocument else { return }
        var title = document.displayName ?? "Untitled presentation"
        if let ext = document.fileURL?.pathExtension, !ext.isEmpty, title.lowercased().hasSuffix("." + ext.lowercased()) {
            title = String(title.dropLast(ext.count + 1))
        }
        state.title = title
        state.formatBadge = document.fileURL == nil ? nil : document.format?.badge
        if document.sharedCopy != nil {
            state.saveStatus = .saved
        } else if document.fileURL == nil {
            state.saveStatus = .draft
        } else {
            state.saveStatus = document.isDocumentEdited ? .edited : .saved
        }
    }

    // MARK: Header alignment

    func updateTitlebarMetrics() {
        guard let window else { return }
        let metrics = TitlebarMetrics.measure(window)
        if state.titlebarLeading != metrics.leading { state.titlebarLeading = metrics.leading }
        if abs(state.titlebarCenterY - metrics.centerY) > 0.5 { state.titlebarCenterY = metrics.centerY }
    }

    func windowDidResize(_ notification: Notification) {
        updateTitlebarMetrics()
        canvasScroll.refit()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { updateTitlebarMetrics() }
    func windowDidExitFullScreen(_ notification: Notification) { updateTitlebarMetrics() }

    func windowDidBecomeKey(_ notification: Notification) {
        updateTitlebarMetrics()
        filmstrip.needsDisplay = true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client is NSTextField ? fieldEditor : nil
    }

    func windowWillClose(_ notification: Notification) {
        if SlideshowController.current != nil { SlideshowController.current?.end() }
    }

    // MARK: Speaker notes

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 160)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.height - 40)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        canvasScroll.refit()
        if notesPlaced, state.showsSpeakerNotes, split.arrangedSubviews.count > 1, !split.isSubviewCollapsed(split.arrangedSubviews[1]) {
            let height = split.arrangedSubviews[1].frame.height
            if height > 30 { notesHeight = height }
        }
    }

    func applyNotesVisibility() {
        guard split.arrangedSubviews.count > 1 else { return }
        let notesPane = split.arrangedSubviews[1]
        notesPane.isHidden = !state.showsSpeakerNotes
        split.adjustSubviews()
        if state.showsSpeakerNotes {
            split.setPosition(max(160, split.bounds.height - notesHeight), ofDividerAt: 0)
        }
        notesPlaced = true
        canvasScroll.refit()
    }

    // MARK: Editing state

    /// Commits any text being typed, on the canvas or in the notes.
    func finishEditing() {
        if canvas.editor != nil { canvas.endEditing() }
        notes.commit()
    }

    var isEditingNotes: Bool { window?.firstResponder === notes.textView }
    var isFilmstripFocused: Bool { window?.firstResponder === filmstrip || window?.firstResponder === grid }

    // MARK: Grid view

    var isGridView: Bool { !gridScroll.isHidden }

    /// View ▸ Grid view: every slide in rows, in place of the filmstrip and the slide.
    func setGridView(_ on: Bool) {
        finishEditing()
        gridScroll.isHidden = !on
        gridZoom.isHidden = !on
        filmstripScroll.isHidden = on
        split.isHidden = on
        if on {
            grid.thumbnailWidth = CGFloat(gridZoom.doubleValue)
            grid.reload()
            grid.scrollToCurrent()
            window?.makeFirstResponder(grid)
        } else {
            canvasScroll.refit()
            focusCanvas()
        }
    }

    @objc private func gridZoomChanged(_ sender: NSSlider) {
        grid.thumbnailWidth = CGFloat(sender.doubleValue)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if isGridView { grid.reload() }
    }

    // MARK: ChromeActions

    func rename(to title: String) {
        guard let document = presentationDocument else { return }
        guard let url = document.fileURL else {
            document.customTitle = title
            synchronizeWindowTitleWithDocumentName()
            return
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(title).appendingPathExtension(url.pathExtension)
        document.move(to: target) { [weak self] error in
            guard let self, error != nil else { return }
            // Sandboxed apps may not rename in place; ask where to save under the new name instead.
            let panel = NSSavePanel()
            panel.nameFieldStringValue = target.lastPathComponent
            panel.directoryURL = url.deletingLastPathComponent()
            panel.message = "Choose where to save “\(title)”."
            panel.beginSheetModal(for: self.window!) { response in
                guard response == .OK, let chosen = panel.url else {
                    self.updateStatus()
                    return
                }
                document.move(to: chosen) { _ in self.updateStatus() }
            }
        }
    }

    func showVersionHistory() {
        guard let document = presentationDocument else { return }
        if document.fileURL == nil {
            showMessage("No versions yet", detail: "Version history becomes available after the presentation is saved to a file.")
            return
        }
        document.browseVersions(nil)
    }

    func dismissBanner() { state.banner = nil }

    func togglePaintFormat() {
        finishEditing()
        if paintFormat != nil || state.isPaintFormatActive {
            paintFormat = nil
            state.isPaintFormatActive = false
        } else if let element = controller.selectedElements.first {
            paintFormat = element
            state.isPaintFormatActive = true
        } else {
            NSSound.beep()
        }
        focusCanvas()
    }

    func focusCanvas() {
        window?.makeFirstResponder(canvas)
    }

    func setTool(_ tool: CanvasTool) {
        finishEditing()
        state.tool = tool
        canvas.tool = tool
        if tool != .select { controller.selectElements([]) }
        focusCanvas()
    }

    func insertImageFromFile() {
        finishEditing()
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let data = try? Data(contentsOf: url), self.controller.insertImage(data: data) else {
                self.showProblem("PuggleSlides can’t read this image.")
                return
            }
            self.focusCanvas()
        }
    }

    func startPresenterView() {
        startSlideshow(fromBeginning: false, presenterView: true)
    }

    /// The toolbar's Animate and Insert ▸ Animation: a new animation for the selection, in the Motion panel.
    func animateSelection() {
        finishEditing()
        showSidebar(.motion)
        controller.addAnimation()
    }

    /// The Motion panel's Play: the slide's transition and animations, on the canvas.
    func playMotionPreview() {
        finishEditing()
        guard let index = controller.currentSlideIndex else { return }
        motionPreview?.stop()
        let slideFrame = canvas.convert(canvas.slideRect, to: canvasScroll)
        let preview = MotionPreviewView(frame: canvasScroll.bounds, slideFrame: slideFrame, presentation: controller.presentation, slideIndex: index)
        preview.autoresizingMask = [.width, .height]
        preview.onFinish = { [weak self, weak preview] in
            preview?.stop()
            if self?.motionPreview === preview { self?.motionPreview = nil }
        }
        canvasScroll.addSubview(preview)
        motionPreview = preview
    }

    func startSlideshow(fromBeginning: Bool) {
        startSlideshow(fromBeginning: fromBeginning, presenterView: false)
    }

    func startSlideshow(fromBeginning: Bool, presenterView: Bool) {
        finishEditing()
        let start = fromBeginning ? 0 : (controller.currentSlideIndex ?? 0)
        let show = SlideshowController.start(controller.presentation, from: start, on: window?.screen, presenterView: presenterView)
        show?.onEnd = { [weak self] index in
            guard let self, self.controller.presentation.slides.indices.contains(index) else { return }
            self.controller.selectSlide(self.controller.presentation.slides[index].id)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    func showSidebar(_ kind: SidebarKind) {
        if kind == .themes { finishEditing() }
        state.sidebar = kind
        sidebarWidth.constant = 300
        updateCommentsColumn()
        DispatchQueue.main.async { [weak self] in self?.canvasScroll.refit() }
    }

    func closeSidebar() {
        state.sidebar = nil
        sidebarWidth.constant = 0
        updateCommentsColumn()
        DispatchQueue.main.async { [weak self] in self?.canvasScroll.refit() }
        focusCanvas()
    }

    func showCustomColorPanel(for target: ColorTarget) {
        colorTarget = target
        let panel = NSColorPanel.shared
        panel.showsAlpha = target == .fill || target == .background
        panel.isContinuous = false
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        let resolved = sender.color.resolvedColor
        applyColor(ColorRef(resolved.rgb).withAlpha(resolved.alpha), to: colorTarget)
    }

    func undo() {
        if let editor = canvas.editor, editor.textView.undoManager?.canUndo == true {
            editor.textView.undoManager?.undo()
        } else {
            finishEditing()
            controller.undoManager?.undo()
        }
    }

    func redo() {
        if let editor = canvas.editor, editor.textView.undoManager?.canRedo == true {
            editor.textView.undoManager?.redo()
        } else {
            controller.undoManager?.redo()
        }
    }

    // MARK: Formatting, for the text being edited or the selected shapes

    func applyColor(_ color: ColorRef?, to target: ColorTarget) {
        switch target {
        case .fill: controller.setFill(color.map(Fill.solid) ?? .none)
        case .border: controller.setBorderColor(color)
        case .background: controller.setBackground(color.map(Fill.solid))
        case .text:
            if let editor = canvas.editor { editor.applyCharacters { $0.color = color } } else { controller.setTextColor(color) }
        case .highlight:
            if let editor = canvas.editor { editor.applyCharacters { $0.highlight = color } } else { controller.setHighlight(color) }
        }
        scheduleStateRefresh()
    }

    func toggleBold() {
        if isEditingNotes { return notes.toggleTrait(.boldFontMask) }
        if let editor = canvas.editor {
            let on = !editor.selectedEffectiveStyles.allSatisfy { $0.bold == true }
            editor.applyCharacters { $0.bold = on }
        } else {
            controller.toggleBold()
        }
    }

    func toggleItalic() {
        if isEditingNotes { return notes.toggleTrait(.italicFontMask) }
        if let editor = canvas.editor {
            let on = !editor.selectedEffectiveStyles.allSatisfy { $0.italic == true }
            editor.applyCharacters { $0.italic = on }
        } else {
            controller.toggleItalic()
        }
    }

    func toggleUnderline() {
        if isEditingNotes { return notes.toggleUnderline() }
        if let editor = canvas.editor {
            let on = !editor.selectedEffectiveStyles.allSatisfy { $0.underline == true }
            editor.applyCharacters { $0.underline = on }
        } else {
            controller.toggleUnderline()
        }
    }

    func toggleStrikethrough() {
        if let editor = canvas.editor {
            let on = !editor.selectedEffectiveStyles.allSatisfy { $0.strikethrough == true }
            editor.applyCharacters { $0.strikethrough = on }
        } else {
            controller.toggleStrikethrough()
        }
    }

    func setBaseline(_ baseline: BaselineShift) {
        if let editor = canvas.editor {
            let on = !editor.selectedEffectiveStyles.allSatisfy { $0.baseline == baseline }
            editor.applyCharacters { $0.baseline = on ? baseline : .normal }
        } else {
            controller.setBaseline(baseline)
        }
    }

    func setFontFamily(_ family: String) {
        if let editor = canvas.editor { editor.applyCharacters { $0.fontFamily = family } } else { controller.setFontFamily(family) }
        scheduleStateRefresh()
    }

    func setFontSize(_ size: Double) {
        let clamped = max(1, min(400, size))
        if let editor = canvas.editor { editor.applyCharacters { $0.fontSize = clamped } } else { controller.setFontSize(clamped) }
        scheduleStateRefresh()
    }

    func stepFontSize(by delta: Double) {
        stepFontSize(by: delta, standardSteps: false)
    }

    func stepFontSize(by delta: Double, standardSteps: Bool) {
        if let editor = canvas.editor {
            let sizes = editor.selectedEffectiveStyles.compactMap(\.fontSize)
            guard let current = sizes.first else { return }
            let next: Double
            if standardSteps {
                next = delta > 0 ? (standardFontSizes.first { $0 > current } ?? current + 12) : (standardFontSizes.last { $0 < current } ?? max(1, current - 1))
            } else {
                next = max(1, min(400, current + delta))
            }
            editor.applyCharacters { $0.fontSize = next }
        } else {
            controller.stepFontSize(by: delta, standardSteps: standardSteps)
        }
        scheduleStateRefresh()
    }

    func setAlignment(_ alignment: PuggleSlidesKit.TextAlignment) {
        if let editor = canvas.editor { editor.applyParagraphs { $0.style.alignment = alignment } } else { controller.setAlignment(alignment) }
        scheduleStateRefresh()
    }

    func setLineSpacing(_ spacing: Double) {
        if let editor = canvas.editor { editor.applyParagraphs { $0.style.lineSpacing = spacing } } else { controller.setLineSpacing(spacing) }
        scheduleStateRefresh()
    }

    func setParagraphSpacing(before: Double?, after: Double?) {
        if let editor = canvas.editor {
            editor.applyParagraphs { paragraph in
                if let before { paragraph.style.spaceBefore = before }
                if let after { paragraph.style.spaceAfter = after }
            }
        } else {
            controller.setParagraphSpacing(before: before, after: after)
        }
    }

    func setList(_ kind: ListKind) {
        if let editor = canvas.editor {
            let style = editor.style
            editor.applyParagraphs { PresentationController.applyList(kind, to: &$0, style: style) }
        } else {
            controller.setList(kind)
        }
        scheduleStateRefresh()
    }

    func toggleList(numbered: Bool) {
        let isOn = numbered ? state.text.isNumbered : state.text.isBulleted
        setList(isOn ? .none : (numbered ? .numbered(.arabicPeriod) : .bulleted("●")))
    }

    func indent(by delta: Int) {
        if let editor = canvas.editor { editor.indent(by: delta) } else { controller.indent(by: delta) }
        scheduleStateRefresh()
    }

    func clearFormatting() {
        if let editor = canvas.editor {
            editor.applyCharacters { style in style = CharacterStyle(link: style.link) }
            editor.applyParagraphs { paragraph in paragraph.style = .empty }
        } else {
            controller.clearTextFormatting()
        }
        scheduleStateRefresh()
    }

    func setAnchor(_ anchor: VerticalAnchor) {
        let editing = canvas.editor?.elementID
        if editing != nil { finishEditing() }
        controller.setAnchor(anchor)
    }

    func popUp(_ menu: ToolbarMenu, from view: NSView?) {
        guard let view else { return }
        ToolbarMenus.make(menu, controller: self).popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 3), in: view)
    }

    // MARK: Zoom

    func setZoom(_ zoom: CGFloat?) {
        canvasScroll.setZoom(zoom)
        state.zoomIsFit = zoom == nil
        state.zoom = canvasScroll.zoom
    }

    // MARK: Layout menus

    /// Menu items for the current theme's layouts, with a thumbnail of each.
    func layoutMenuItems(action: Selector, checkCurrent: Bool) -> [NSMenuItem] {
        let presentation = controller.presentation
        let theme = controller.currentSlide.map { presentation.theme(for: $0) } ?? presentation.themes.first
        guard let theme else { return [] }
        let currentLayout = controller.currentSlide?.layoutID
        return theme.layouts.map { layout in
            let item = MenuBuilder.represented(MenuBuilder.item(layout.name, action), layout.id)
            item.target = self
            item.image = LayoutThumbnails.image(for: layout, theme: theme, presentation: presentation)
            if checkCurrent { item.state = layout.id == currentLayout ? .on : .off }
            return item
        }
    }
}

/// Small pictures of layouts, with their placeholders' prompts, for the layout menus.
@MainActor
enum LayoutThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(for layout: SlideLayout, theme: SlideTheme, presentation: Presentation) -> NSImage {
        let size = presentation.slideSize
        let key = "\(layout.id)|\(theme.colors.colors.count)|\(size.width)x\(size.height)"
        if let image = cache[key] { return image }
        var preview = Presentation(slideSize: size, themes: [theme], defaultTextStyle: presentation.defaultTextStyle)
        let slide = preview.makeSlide(layoutID: layout.id)
        preview.slides = [slide]
        let width: CGFloat = 96, height = width * size.height / max(size.width, 1)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            SlideRenderer.draw(slide, of: preview, in: rect, options: SlideRenderer.Options(showsPrompts: true))
            NSColor(white: 0.8, alpha: 1).setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
        cache[key] = image
        return image
    }
}
