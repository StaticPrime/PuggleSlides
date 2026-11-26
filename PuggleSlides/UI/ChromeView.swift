import AppKit
import PuggleSlidesKit
import SwiftUI

enum ToolbarMenu {
    case zoom, newSlideLayouts, applyLayout, image, lines, font, align, lineSpacing, bullets, numbers
    case borderWeight, borderDash, lineStart, lineEnd, download, slideshow
    case tableBorders, mask, replaceImage
}

/// What the header and toolbar ask their window to do.
protocol ChromeActions: AnyObject {
    var controller: PresentationController { get }
    /// The window the header and toolbar are in.
    var window: NSWindow? { get }
    func popUp(_ menu: ToolbarMenu, from view: NSView?)
    func rename(to title: String)
    func showVersionHistory()
    func toggleCommentsPanel()
    func playClip()
    func dismissBanner()
    func togglePaintFormat()
    func focusCanvas()
    func setTool(_ tool: CanvasTool)
    func insertImageFromFile()
    func startSlideshow(fromBeginning: Bool)
    func startPresenterView()
    func animateSelection()
    func showSidebar(_ kind: SidebarKind)
    func showBackgroundDialog()
    func showLinkEditor()
    func showCustomColorPanel(for target: ColorTarget)
    func undo()
    func redo()
    // Formatting reaches the text being edited or the selected shapes.
    func applyColor(_ color: ColorRef?, to target: ColorTarget)
    func toggleBold()
    func toggleItalic()
    func toggleUnderline()
    func setFontSize(_ size: Double)
    func stepFontSize(by delta: Double)
    func indent(by delta: Int)
    func clearFormatting()
    func toggleList(numbered: Bool)
    // Images and charts.
    func cropImage()
    func resetImage()
    func editChart()
    // The theme builder.
    func renameThemeBuilderPage()
    func showThemeColors()
    func closeThemeBuilder()
    // Sharing.
    func showCollaborate()
    func startComment()
}

/// What a color picker colors.
enum ColorTarget {
    case fill, border, text, highlight, background
}

/// Header, toolbar, and the update and info banners above the canvas.
struct ChromeView: View {
    let state: EditorState
    let actions: ChromeActions

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(state: state, actions: actions)
            FormattingToolbar(state: state, actions: actions)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            if let title = state.themeBuilderTitle {
                ThemeBuilderBar(title: title, actions: actions)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            UpdateBannerView(banner: UpdateController.shared.banner)
            if let banner = state.banner {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color.orange)
                    Text(banner).font(.system(size: 12.5)).foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Dismiss") { actions.dismissBanner() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.bannerFill)
            }
        }
        .background(Color(nsColor: Theme.canvas))
        // The header shares the title bar band with the window buttons.
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Lines a header row up with the window's close, minimise and zoom buttons.
enum TitlebarMetrics {
    static let rowHeight: CGFloat = 32

    /// Leading inset after the window buttons and the vertical center of those buttons, from the window top.
    @MainActor
    static func measure(_ window: NSWindow) -> (leading: CGFloat, centerY: CGFloat) {
        if window.styleMask.contains(.fullScreen) { return (18, 22) }
        guard let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton), close.superview != nil else { return (78, 18) }
        let closeFrame = close.convert(close.bounds, to: nil)
        let zoomFrame = zoom.convert(zoom.bounds, to: nil)
        return (zoomFrame.maxX + 16, window.frame.height - closeFrame.midY)
    }
}

/// Presentation header: icon, editable title, format badge and save status, with version history, Slideshow and
/// Download on the right. Menus live in the macOS menu bar, as in every Mac app.
struct HeaderView: View {
    let state: EditorState
    let actions: ChromeActions
    @State private var titleText = ""
    @FocusState private var titleFocused: Bool
    @State private var slideshowAnchor = AnchorHolder()

    private var titleWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 16)
        let text = titleText.isEmpty ? "Untitled presentation" : titleText
        return min(520, max(80, (text as NSString).size(withAttributes: [.font: font]).width + 14))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .help("PuggleSlides")
            TextField("Untitled presentation", text: $titleText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.primaryText)
                .frame(width: titleWidth, height: 24)
                .padding(.horizontal, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(titleFocused ? Theme.accent : .clear, lineWidth: 1.5))
                .hoverBackground()
                .focused($titleFocused)
                .onSubmit { commitTitle() }
                .disabled(!state.collaboration.isOwner && state.collaboration.isShared)
                .help(state.collaboration.isShared && !state.collaboration.isOwner ? "Only its owner can rename it" : "Rename")
            if let badge = state.formatBadge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.secondaryText.opacity(0.5), lineWidth: 1))
                    .help("This file is stored in \(badge.dropFirst()) format")
            }
            Image(systemName: statusSymbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .help(statusText)
            Spacer(minLength: 12)
            // As the window narrows, the status words go first, then the buttons' words.
            ViewThatFits(in: .horizontal) {
                trailingControls(showsStatus: true, compact: false)
                trailingControls(showsStatus: false, compact: false)
                trailingControls(showsStatus: false, compact: true)
            }
        }
        .frame(height: TitlebarMetrics.rowHeight)
        .padding(.leading, state.titlebarLeading)
        .padding(.trailing, 14)
        .padding(.top, max(0, state.titlebarCenterY - TitlebarMetrics.rowHeight / 2))
        .padding(.bottom, 8)
        .background(WindowDragArea())
        .onAppear { titleText = state.title }
        .onChange(of: state.title) { _, newValue in if !titleFocused { titleText = newValue } }
        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
        .onChange(of: state.renameRequest) { _, _ in
            titleFocused = true
            selectWholeTitle()
        }
        .onExitCommand { titleText = state.title; titleFocused = false; actions.focusCanvas() }
    }

    /// File ▸ Rename: once the name's field is being edited, all of the name is selected, so typing replaces it. The
    /// field is in this header's own window, whichever window happens to be in front.
    private func selectWholeTitle(attempt: Int = 0) {
        if let field = actions.window?.firstResponder as? NSTextView, field.isFieldEditor {
            field.selectAll(nil)
        } else if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { selectWholeTitle(attempt: attempt + 1) }
        }
    }

    private func trailingControls(showsStatus: Bool, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if showsStatus {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            CollaboratorAvatars(state: state.collaboration)
            ToolbarIconButton(symbol: "clock.arrow.circlepath", help: "Open version history") { actions.showVersionHistory() }
            ToolbarIconButton(symbol: "text.bubble", help: "Show all comments (⌥⇧⌘A)", isOn: state.sidebar == .comments) {
                actions.toggleCommentsPanel()
            }
            HStack(spacing: 0) {
                Button {
                    actions.startSlideshow(fromBeginning: false)
                } label: {
                    Group {
                        if compact {
                            Image(systemName: "play.rectangle")
                        } else {
                            Label("Slideshow", systemImage: "play.rectangle")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.leading, compact ? 10 : 12)
                    .padding(.trailing, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Start slideshow (⌘↩)")
                Rectangle().fill(Theme.divider).frame(width: 1, height: 18)
                Button {
                    actions.popUp(.slideshow, from: slideshowAnchor.view)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Slideshow options")
                .background(AnchorView(holder: slideshowAnchor))
            }
            .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
            .clipShape(Capsule())
            .fixedSize()
            if state.showsCollaborateButton { collaborateButton(compact: compact) }
            ToolbarDropdown(help: "Download a copy", showsChevron: false, open: { actions.popUp(.download, from: $0) }) {
                Group {
                    if compact {
                        Image(systemName: "arrow.down.to.line")
                    } else {
                        Label("Download", systemImage: "arrow.down.to.line")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.0, green: 0.12, blue: 0.27))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color(red: 0.76, green: 0.87, blue: 1.0)))
                .fixedSize()
            }
        }
    }

    private var collaborateSymbol: String { state.collaboration.isShared ? "person.2.fill" : "person.badge.plus" }

    /// The Collaborate button, for presentations of this person's: those shared with them don't have it.
    private func collaborateButton(compact: Bool) -> some View {
        Button { actions.showCollaborate() } label: {
            Group {
                if compact {
                    Image(systemName: collaborateSymbol)
                } else {
                    Label("Collaborate", systemImage: collaborateSymbol)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.accent))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(state.collaboration.isShared ? "See and change who this presentation is shared with" : "Share this presentation with people to work on it together")
        .accessibilityLabel("Collaborate")
    }

    /// While shared, how its iCloud copy is keeping up; otherwise how its file is.
    private var statusText: String { state.collaboration.isShared ? state.collaboration.statusText : state.saveStatus.text }
    private var statusSymbol: String { state.collaboration.isShared ? state.collaboration.statusSymbol : state.saveStatus.symbol }

    private func commitTitle() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == state.title {
            titleText = state.title
        } else {
            actions.rename(to: trimmed)
        }
        if titleFocused {
            titleFocused = false
            actions.focusCanvas()
        }
    }
}

/// The rounded toolbar. The right-hand groups follow the selection; groups that do not
/// fit move into an overflow popover.
struct FormattingToolbar: View {
    let state: EditorState
    let actions: ChromeActions
    @State private var showingOverflow = false

    private var controller: PresentationController { actions.controller }

    private enum Group: Hashable {
        case newSlide, history, zoom, tools, slide, shape, line, font, textStyle, paragraph, formatOptions
        case tableBorders, chart, imageTools, wordArtStyle, media
        /// In place of the editing groups, while the presentation can only be commented on.
        case commenting
    }

    private var groups: [Group] {
        // Someone a presentation is shared with to comment on gets zoom and commenting, and nothing that edits.
        if state.access != .full { return [.zoom, .commenting] }
        var result: [Group] = [.newSlide, .history, .zoom, .tools]
        switch state.selectionKind {
        case .none: result.append(.slide)
        case .line: result += [.line, .formatOptions]
        case .image: result += [.imageTools, .shape, .formatOptions]
        case .table:
            result += [.shape, .tableBorders]
            if state.hasText { result += [.font, .textStyle, .paragraph] }
            result.append(.formatOptions)
        case .chart: result += [.chart, .formatOptions]
        case .media: result += [.media, .formatOptions]
        case .wordArt: result += [.shape, .font, .wordArtStyle, .formatOptions]
        case .textBox, .shape, .multiple, .group:
            result.append(.shape)
            if state.hasText { result += [.font, .textStyle, .paragraph] }
            result.append(.formatOptions)
        }
        return result
    }

    var body: some View {
        let groups = groups
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(groups, overflowFrom: groups.count)
                ForEach(Array(stride(from: groups.count - 1, through: 4, by: -1)), id: \.self) { cut in
                    row(groups, overflowFrom: cut)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(Capsule().fill(Theme.toolbarFill))
    }

    private func row(_ groups: [Group], overflowFrom: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(groups.prefix(overflowFrom).enumerated()), id: \.element) { index, group in
                if index > 0 { ToolbarDivider() }
                view(for: group)
            }
            if overflowFrom < groups.count {
                ToolbarDivider()
                ToolbarIconButton(symbol: "ellipsis", help: "More", isOn: showingOverflow) { showingOverflow = true }
                    .popover(isPresented: $showingOverflow, arrowEdge: .bottom) {
                        HStack(spacing: 1) {
                            ForEach(Array(groups.dropFirst(overflowFrom).enumerated()), id: \.element) { index, group in
                                if index > 0 { ToolbarDivider() }
                                view(for: group)
                            }
                        }
                        .padding(8)
                    }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func view(for group: Group) -> some View {
        switch group {
        case .newSlide:
            SplitToolbarButton(symbol: "plus", help: "New slide (⌃M)", action: { controller.newSlide() },
                               openPresets: { actions.popUp(.newSlideLayouts, from: $0) })
        case .history: historyGroup
        case .zoom:
            ToolbarDropdown(help: "Zoom", open: { actions.popUp(.zoom, from: $0) }) {
                Image(systemName: "plus.magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
        case .tools: toolsGroup
        case .slide: slideGroup
        case .shape: shapeGroup
        case .line: lineGroup
        case .font: fontGroup
        case .textStyle: textStyleGroup
        case .paragraph: paragraphGroup
        case .tableBorders:
            ToolbarDropdown(help: "Select borders", open: { actions.popUp(.tableBorders, from: $0) }) {
                Image(systemName: "squareshape.split.3x3").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
        case .chart:
            TextToolbarButton(text: "Edit chart", help: "Edit the chart's type, numbers and labels") { actions.editChart() }
        case .media:
            ToolbarIconButton(symbol: "play.fill", help: "Play") { actions.playClip() }
        case .commenting:
            HStack(spacing: 6) {
                Image(systemName: modeSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                Text(modeTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.trailing, 4)
                if state.access == .commentOnly {
                    TextToolbarButton(text: "Add comment", help: "Add a comment (⌥⌘M)") { actions.startComment() }
                }
            }
            .padding(.horizontal, 6)
            .help(modeHelp)
        case .imageTools:
            HStack(spacing: 1) {
                ToolbarIconButton(symbol: "crop", help: "Crop image") { actions.cropImage() }
                ToolbarDropdown(help: "Mask image", open: { actions.popUp(.mask, from: $0) }) {
                    Image(systemName: "seal").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                }
                ToolbarIconButton(symbol: "arrow.counterclockwise", help: "Reset image") { actions.resetImage() }
                ToolbarDropdown(help: "Replace image", open: { actions.popUp(.replaceImage, from: $0) }) {
                    Text("Replace image").font(.system(size: 13.5)).foregroundStyle(Theme.primaryText)
                }
            }
        case .wordArtStyle:
            HStack(spacing: 1) {
                ToolbarIconButton(symbol: "bold", help: "Bold (⌘B)", isOn: state.text.bold) { actions.toggleBold() }
                ToolbarIconButton(symbol: "italic", help: "Italic (⌘I)", isOn: state.text.italic) { actions.toggleItalic() }
            }
        case .formatOptions:
            HStack(spacing: 1) {
                TextToolbarButton(text: "Format options", help: "Format options") { actions.showSidebar(.formatOptions) }
                TextToolbarButton(text: "Animate", help: "Animate") { actions.animateSelection() }
            }
        }
    }

    /// What the toolbar says in place of its editing tools, when the presentation can't be changed here.
    private var modeTitle: String {
        switch state.access {
        case .offline: "Offline"
        case .locked: "Opening"
        default: "Commenting"
        }
    }

    private var modeSymbol: String {
        switch state.access {
        case .offline: "icloud.slash"
        case .locked: "icloud.and.arrow.down"
        default: "text.bubble"
        }
    }

    private var modeHelp: String {
        switch state.access {
        case .offline: "iCloud can’t be reached, so this presentation can’t be changed until it can"
        case .locked: "The shared copy is opening from iCloud"
        default: "You can comment on this presentation, but not change it"
        }
    }

    private var historyGroup: some View {
        HStack(spacing: 1) {
            ToolbarIconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", isEnabled: state.canUndo) { actions.undo() }
            ToolbarIconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", isEnabled: state.canRedo) { actions.redo() }
            ToolbarIconButton(symbol: "paintbrush.pointed", help: "Paint format", isOn: state.isPaintFormatActive) { actions.togglePaintFormat() }
        }
    }

    private var toolsGroup: some View {
        HStack(spacing: 1) {
            ToolbarIconButton(symbol: "cursorarrow", help: "Select", isOn: state.tool == .select) { actions.setTool(.select) }
            ToolbarIconButton(symbol: "character.textbox", help: "Text box", isOn: state.tool == .textBox) { actions.setTool(.textBox) }
            ToolbarDropdown(help: "Insert image", open: { actions.popUp(.image, from: $0) }) {
                Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            ShapeToolButton(isOn: { if case .shape = state.tool { true } else { false } }()) { preset in actions.setTool(.shape(preset)) }
            ToolbarDropdown(help: "Line", open: { actions.popUp(.lines, from: $0) }) {
                Image(systemName: lineSymbol).font(.system(size: 14))
                    .foregroundStyle({ if case .line = state.tool { Theme.accent } else { Theme.secondaryText } }())
            }
        }
    }

    private var lineSymbol: String {
        if case .line(let kind) = state.tool { return kind.symbol }
        return "line.diagonal"
    }

    private var slideGroup: some View {
        HStack(spacing: 1) {
            TextToolbarButton(text: "Background", help: "Change background") { actions.showBackgroundDialog() }
            // Layouts, themes and transitions belong to slides, not to the theme builder's pages.
            if state.themeBuilderTitle == nil {
                ToolbarDropdown(help: "Layout", open: { actions.popUp(.applyLayout, from: $0) }) {
                    Text("Layout").font(.system(size: 13.5)).foregroundStyle(Theme.primaryText)
                }
                TextToolbarButton(text: "Theme", help: "Change theme") { actions.showSidebar(.themes) }
                TextToolbarButton(text: "Transition", help: "Change transition") { actions.showSidebar(.motion) }
            }
        }
    }

    private var shapeGroup: some View {
        HStack(spacing: 1) {
            if state.selectionKind != .image {
                SlideColorButton(kind: .fill, currentHex: state.shape.fillHex, actions: actions)
            }
            SlideColorButton(kind: .border, currentHex: state.shape.borderHex, actions: actions)
            ToolbarDropdown(help: "Border weight", open: { actions.popUp(.borderWeight, from: $0) }) {
                LineWeightIcon().frame(width: 16, height: 14).foregroundStyle(Theme.secondaryText)
            }
            ToolbarDropdown(help: "Border dash", open: { actions.popUp(.borderDash, from: $0) }) {
                DashIcon().frame(width: 16, height: 14).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var lineGroup: some View {
        HStack(spacing: 1) {
            SlideColorButton(kind: .border, currentHex: state.shape.borderHex, actions: actions, title: "Line color")
            ToolbarDropdown(help: "Line weight", open: { actions.popUp(.borderWeight, from: $0) }) {
                LineWeightIcon().frame(width: 16, height: 14).foregroundStyle(Theme.secondaryText)
            }
            ToolbarDropdown(help: "Line dash", open: { actions.popUp(.borderDash, from: $0) }) {
                DashIcon().frame(width: 16, height: 14).foregroundStyle(Theme.secondaryText)
            }
            ToolbarDropdown(help: "Line start", open: { actions.popUp(.lineStart, from: $0) }) {
                Image(systemName: "arrow.left").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            ToolbarDropdown(help: "Line end", open: { actions.popUp(.lineEnd, from: $0) }) {
                Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var fontGroup: some View {
        HStack(spacing: 1) {
            ToolbarDropdown(help: "Font", open: { actions.popUp(.font, from: $0) }) {
                Text(state.text.fontFamily ?? " ")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .frame(width: 84, alignment: .leading)
            }
            ToolbarDivider()
            FontSizeControl(size: state.text.fontSize.map { CGFloat($0) }, set: { actions.setFontSize(Double($0)) },
                            step: { actions.stepFontSize(by: Double($0)) })
        }
    }

    private var textStyleGroup: some View {
        HStack(spacing: 1) {
            ToolbarIconButton(symbol: "bold", help: "Bold (⌘B)", isOn: state.text.bold) { actions.toggleBold() }
            ToolbarIconButton(symbol: "italic", help: "Italic (⌘I)", isOn: state.text.italic) { actions.toggleItalic() }
            ToolbarIconButton(symbol: "underline", help: "Underline (⌘U)", isOn: state.text.underline) { actions.toggleUnderline() }
            SlideColorButton(kind: .text, currentHex: state.text.colorHex, actions: actions)
            SlideColorButton(kind: .highlight, currentHex: state.text.highlightHex, actions: actions)
            ToolbarIconButton(symbol: "link", help: "Insert link (⌘K)", isOn: state.text.hasLink) { actions.showLinkEditor() }
        }
    }

    private var alignSymbol: String {
        switch state.text.alignment {
        case .center?: "text.aligncenter"
        case .right?: "text.alignright"
        case .justified?: "text.justify"
        default: "text.alignleft"
        }
    }

    private var paragraphGroup: some View {
        HStack(spacing: 1) {
            ToolbarDropdown(help: "Align", open: { actions.popUp(.align, from: $0) }) {
                Image(systemName: alignSymbol).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            ToolbarDropdown(help: "Line & paragraph spacing", open: { actions.popUp(.lineSpacing, from: $0) }) {
                Image(systemName: "arrow.up.and.down.text.horizontal").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            SplitToolbarButton(symbol: "list.bullet", help: "Bulleted list (⇧⌘8)", isOn: state.text.isBulleted,
                               action: { actions.toggleList(numbered: false) }, openPresets: { actions.popUp(.bullets, from: $0) })
            SplitToolbarButton(symbol: "list.number", help: "Numbered list (⇧⌘7)", isOn: state.text.isNumbered,
                               action: { actions.toggleList(numbered: true) }, openPresets: { actions.popUp(.numbers, from: $0) })
            ToolbarIconButton(symbol: "decrease.indent", help: "Decrease indent (⌘[)") { actions.indent(by: -1) }
            ToolbarIconButton(symbol: "increase.indent", help: "Increase indent (⌘])") { actions.indent(by: 1) }
            ToolbarIconButton(symbol: "textformat", help: "Clear formatting (⌘\\)") { actions.clearFormatting() }
        }
    }
}

/// A toolbar button labelled with text ("Background", "Format options").
struct TextToolbarButton: View {
    let text: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 7)
                .frame(height: 28)
                .hoverBackground()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The border weight icon: three lines getting thicker.
nonisolated struct LineWeightIcon: View {
    var body: some View {
        VStack(spacing: 2.5) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 2)
            Rectangle().frame(height: 3.5)
        }
    }
}

/// The border dash icon: a dashed, a dotted and a solid line.
nonisolated struct DashIcon: View {
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Rectangle().frame(height: 2) } }
            HStack(spacing: 2) { ForEach(0..<5, id: \.self) { _ in Rectangle().frame(width: 2, height: 2) } }
            Rectangle().frame(height: 2)
        }
    }
}

/// The Shape button: a gallery of the preset shapes, by category.
struct ShapeToolButton: View {
    let isOn: Bool
    let pick: (String) -> Void
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.on.circle").font(.system(size: 14)).foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 5)
            .frame(height: 28)
            .hoverBackground(isOn: isOn || showing)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Shape")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ShapeGalleryView { preset in
                showing = false
                pick(preset)
            }
        }
    }
}

struct ShapeGalleryView: View {
    let pick: (String) -> Void
    @State private var category = ShapeCategory.shapes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $category) {
                ForEach(ShapeCategory.allCases, id: \.self) { category in Text(category.title).tag(category) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 10), spacing: 4) {
                    ForEach(PresetGeometry.catalog.filter { $0.category == category }, id: \.name) { info in
                        Button {
                            pick(info.name)
                        } label: {
                            ShapeIcon(preset: info.name)
                                .frame(width: 26, height: 26)
                                .hoverBackground()
                        }
                        .buttonStyle(.plain)
                        .help(info.title)
                    }
                }
            }
            .frame(height: 230)
        }
        .padding(12)
        .frame(width: 320)
    }
}

/// A small outline drawing of a preset shape.
struct ShapeIcon: View {
    let preset: String

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 4, y: 5, width: size.width - 8, height: size.height - 10)
            let geometry = ShapeGeometry.preset(preset, adjustments: PresetGeometry.defaultAdjustments(preset))
            for part in PresetGeometry.paths(for: geometry, in: CGRect(origin: .zero, size: rect.size)) {
                let path = Path(part.path).offsetBy(dx: rect.minX, dy: rect.minY)
                if part.fill != .none { context.fill(path, with: .color(Theme.secondaryText.opacity(0.12)), style: FillStyle(eoFill: true)) }
                if part.stroke { context.stroke(path, with: .color(Theme.secondaryText), lineWidth: 1) }
            }
        }
    }
}

/// Fill, border, text and highlight color buttons, with the standard palette, the theme's colors and Transparent.
struct SlideColorButton: View {
    let kind: ColorTarget
    let currentHex: String?
    let actions: ChromeActions
    var title: String?
    @State private var showing = false

    private var help: String {
        title ?? {
            switch kind {
            case .fill: "Fill color"
            case .border: "Border color"
            case .text: "Text color"
            case .highlight: "Highlight color"
            case .background: "Background color"
            }
        }()
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            VStack(spacing: 1) {
                switch kind {
                case .fill, .background: PaintBucketShape().fill(style: FillStyle(eoFill: true)).frame(width: 15, height: 15)
                case .border: Image(systemName: "pencil").font(.system(size: 13, weight: .medium)).frame(height: 15)
                case .text: Text("A").font(.system(size: 15, weight: .medium, design: .serif)).frame(height: 15)
                case .highlight: Image(systemName: "highlighter").font(.system(size: 13)).frame(height: 15)
                }
                Rectangle()
                    .fill(Color(nsColor: currentHex.flatMap(NSColor.init(hex:)) ?? .clear))
                    .frame(width: 16, height: 3.5)
                    .overlay(Rectangle().stroke(Color.black.opacity(currentHex == nil ? 0.25 : 0), lineWidth: 0.5))
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 28, height: 28)
            .hoverBackground(isOn: showing)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            SlideColorPalette(selectedHex: currentHex, themeColors: actions.controller.currentThemeColors,
                              allowsTransparent: kind == .fill || kind == .border || kind == .highlight,
                              resetTitle: kind == .text ? "Reset" : (kind == .highlight ? "None" : nil)) { color in
                showing = false
                actions.applyColor(color, to: kind)
            } custom: {
                showing = false
                actions.showCustomColorPanel(for: kind)
            }
        }
    }
}

struct SlideColorPalette: View {
    let selectedHex: String?
    let themeColors: [(ThemeColorSlot, RGBColor)]
    var allowsTransparent = true
    var resetTitle: String?
    let pick: (ColorRef?) -> Void
    let custom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allowsTransparent || resetTitle != nil {
                Button {
                    pick(nil)
                } label: {
                    Label(resetTitle ?? "Transparent", systemImage: resetTitle == nil ? "circle.slash" : "drop.halffull")
                        .font(.system(size: 13))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .hoverBackground()
                }
                .buttonStyle(.plain)
            }
            swatchRow(ColorPalette.grayRow.map { (ColorRef(hex: $0.hex)!, $0.name, $0.hex) })
            swatchRow(ColorPalette.brightRow.map { (ColorRef(hex: $0.hex)!, $0.name, $0.hex) })
            VStack(spacing: 4) {
                ForEach(Array(ColorPalette.shadeRows.enumerated()), id: \.offset) { _, row in
                    swatchRow(row.map { (ColorRef(hex: $0.hex)!, $0.name, $0.hex) })
                }
            }
            if !themeColors.isEmpty {
                Divider()
                Text("THEME").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                swatchRow(themeColors.prefix(10).map { (ColorRef(theme: $0.0), $0.0.title, $0.1.hex) })
            }
            Divider()
            HStack {
                Text("CUSTOM").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(action: custom) { Image(systemName: "plus.circle").font(.system(size: 16)) }
                    .buttonStyle(.plain)
                    .help("Choose a custom color")
            }
        }
        .padding(12)
        .frame(width: 252)
    }

    private func swatchRow(_ swatches: [(ColorRef, String, String)]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                let color = NSColor(hex: swatch.2) ?? .black
                Button {
                    pick(swatch.0)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .overlay(Circle().stroke(Color.black.opacity(swatch.2.hasPrefix("F") || swatch.2.hasPrefix("E") ? 0.2 : 0), lineWidth: 0.5))
                        .overlay {
                            if swatch.2 == selectedHex {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(color.resolvedColor.luminance > 0.6 ? Color.black : Color.white)
                            }
                        }
                        .frame(width: 19, height: 19)
                }
                .buttonStyle(.plain)
                .help(swatch.1)
            }
        }
    }
}

extension PresentationController {
    /// The current theme's colors, in order: dark 1, light 1, dark 2, light 2, accents, link.
    var currentThemeColors: [(ThemeColorSlot, RGBColor)] {
        guard let slide = currentSlide else { return [] }
        let colors = presentation.theme(for: slide).colors
        return ThemeColorSlot.allCases.filter { $0 != .followedHyperlink }.map { ($0, colors[$0]) }
    }
}

/// The theme builder's bar above the canvas: what's being edited, Rename, Colors and Close.
struct ThemeBuilderBar: View {
    let title: String
    let actions: ChromeActions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintpalette").foregroundStyle(Theme.secondaryText)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primaryText).lineLimit(1)
            PanelButton(title: "Rename", primary: false) { actions.renameThemeBuilderPage() }
            PanelButton(title: "Colors", primary: false) { actions.showThemeColors() }
            Spacer()
            Button {
                actions.closeThemeBuilder()
            } label: {
                Label("Close", systemImage: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primaryText)
            }
            .buttonStyle(.plain)
            .help("Close the theme builder")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.toolbarFill))
    }
}
