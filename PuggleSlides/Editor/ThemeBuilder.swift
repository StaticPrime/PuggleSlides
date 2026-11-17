import AppKit
import PuggleSlidesKit

/// The theme builder (Slide ▸ Edit theme): a theme's master and each of its layouts shown as pages that edit like
/// slides. The editor works on a stand-in presentation whose slides are those pages; every edit is mapped back into
/// the real theme, so the document stays current, and leaving the builder records the whole visit as one undo step.
struct ThemeBuilderSession {
    let themeID: UUID
    /// The presentation as it was when the builder opened; its slides and other themes stay as they were.
    let base: Presentation
    /// The stand-in: page one is the theme, the rest its layouts, each on a layout of its own with nothing on it.
    var proxy: Presentation
    /// The builder's own undo history, kept apart from the document's.
    let undoManager = UndoManager()
    /// Where to return when the builder closes.
    let returnSlideID: UUID?

    /// Pages are keyed by the real theme's or layout's id; each page sits on an empty stand-in layout that carries the
    /// layout's name and whether it shows the theme's graphics.
    static func make(from real: Presentation, themeID: UUID, returnSlideID: UUID?) -> ThemeBuilderSession? {
        guard let themeIndex = real.themeIndex(id: themeID) else { return nil }
        let theme = real.themes[themeIndex]
        var standIn = theme
        let masterLayout = Layout(name: theme.name, kind: .blank, showsThemeElements: false)
        var layouts = [masterLayout]
        var pages = [Slide(id: theme.id, layoutID: masterLayout.id, elements: theme.elements, background: theme.background)]
        for layout in theme.layouts {
            let blank = Layout(name: layout.name, kind: layout.kind, showsThemeElements: layout.showsThemeElements)
            layouts.append(blank)
            pages.append(Slide(id: layout.id, layoutID: blank.id, elements: layout.elements, background: layout.background))
        }
        standIn.layouts = layouts
        var proxy = real
        proxy.themes = [standIn]
        proxy.slides = pages
        return ThemeBuilderSession(themeID: themeID, base: real, proxy: proxy, returnSlideID: returnSlideID)
    }

    func isMaster(_ pageID: UUID?) -> Bool { pageID == themeID }

    /// The name shown above the page: the theme's or the layout's.
    func pageName(_ pageID: UUID?) -> String {
        guard let pageID, let page = proxy.slides.first(where: { $0.id == pageID }) else { return "" }
        if isMaster(pageID) { return proxy.themes.first?.name ?? "" }
        return proxy.themes.first?.layout(id: page.layoutID)?.name ?? ""
    }

    /// Layouts inherit from the theme page, so the stand-in theme follows it.
    static func syncMaster(_ proxy: inout Presentation, themeID: UUID) {
        guard let master = proxy.slides.first(where: { $0.id == themeID }), !proxy.themes.isEmpty else { return }
        proxy.themes[0].elements = master.elements
        if let background = master.background { proxy.themes[0].background = background }
    }

    /// The real presentation the pages describe: the theme's name, colors, graphics and background from the theme
    /// page, and its layouts, in page order, from the others.
    func real(from proxy: Presentation) -> Presentation {
        var real = base
        guard let themeIndex = real.themeIndex(id: themeID), let standIn = proxy.themes.first else { return base }
        var theme = real.themes[themeIndex]
        theme.name = standIn.name
        theme.colors = standIn.colors
        theme.fonts = standIn.fonts
        if let master = proxy.slides.first(where: { $0.id == themeID }) {
            theme.elements = master.elements
            theme.background = master.background ?? theme.background
        }
        theme.layouts = proxy.slides.filter { $0.id != themeID }.map { page in
            let blank = standIn.layout(id: page.layoutID)
            var layout = theme.layout(id: page.id) ?? Layout(id: page.id, name: blank?.name ?? "Layout", kind: .custom)
            layout.name = blank?.name ?? layout.name
            layout.elements = page.elements
            layout.background = page.background
            layout.showsThemeElements = blank?.showsThemeElements ?? layout.showsThemeElements
            return layout
        }
        real.themes[themeIndex] = theme
        real.media = proxy.media
        real.guides = proxy.guides
        return real
    }
}

extension PresentationController {
    var isThemeBuilderOpen: Bool { builder != nil }

    /// Slide ▸ Edit theme: opens on the current slide's layout.
    func openThemeBuilder() {
        guard builder == nil, let theme = currentSlide.map(presentation.theme(for:)) ?? presentation.themes.first else { return }
        let layoutID = currentSlide?.layoutID
        guard let session = ThemeBuilderSession.make(from: presentation, themeID: theme.id, returnSlideID: currentSlideID) else { return }
        startThemeBuilder(session, showing: layoutID.flatMap { id in session.proxy.slides.contains { $0.id == id } ? id : nil } ?? theme.id)
    }

    /// Closes the theme builder; everything done there becomes one "Edit Theme" step.
    func closeThemeBuilder() {
        guard let session = builder else { return }
        let final = session.real(from: session.proxy)
        finishThemeBuilder(restoring: session.base, returnTo: session.returnSlideID)
        if final != session.base {
            perform("Edit Theme", update: [.slides, .content, .theme]) { $0 = final }
        }
    }

    /// The page being edited is the theme's.
    var isEditingMaster: Bool { builder?.isMaster(currentSlideID) ?? false }

    func editBuilderProxy(_ actionName: String, update: PresentationUpdate = [.content, .theme], showing pageID: UUID? = nil,
                          _ edit: (inout Presentation, ThemeBuilderSession) -> Void) {
        guard let session = builder else { return }
        perform(actionName, update: update, showing: pageID) { proxy in edit(&proxy, session) }
    }

    /// The theme builder's Rename: the theme's name on the theme page, a layout's name on a layout page.
    func renameBuilderPage(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pageID = currentSlideID, let page = currentSlide else { return }
        editBuilderProxy(isEditingMaster ? "Rename Theme" : "Rename Layout") { proxy, session in
            if session.isMaster(pageID) {
                proxy.themes[0].name = trimmed
            } else if let index = proxy.themes[0].layoutIndex(id: page.layoutID) {
                proxy.themes[0].layouts[index].name = trimmed
            }
        }
    }

    /// The theme builder's Colors.
    func setBuilderThemeColor(_ slot: ThemeColorSlot, to color: RGBColor) {
        editBuilderProxy("Theme Colors") { proxy, _ in proxy.themes[0].colors.colors[slot] = color }
    }

    /// Duplicate layout: a copy after this one, with its own name.
    func duplicateBuilderLayout() {
        guard let page = currentSlide, !isEditingMaster, let blank = presentation.themes.first?.layout(id: page.layoutID) else { return }
        var copyLayout = Layout(name: blank.name + " copy", kind: .custom, showsThemeElements: blank.showsThemeElements)
        copyLayout.background = nil
        let copy = Slide(layoutID: copyLayout.id, elements: page.elements.map { $0.withNewIDs() }, background: page.background)
        editBuilderProxy("Duplicate Layout", update: [.slides, .content, .theme], showing: copy.id) { proxy, _ in
            proxy.themes[0].layouts.append(copyLayout)
            let index = (proxy.slideIndex(id: page.id) ?? proxy.slides.count - 1) + 1
            proxy.slides.insert(copy, at: index)
        }
    }

    /// Delete layout: only layouts no slide uses.
    var canDeleteBuilderLayout: Bool {
        guard let session = builder, let pageID = currentSlideID, !session.isMaster(pageID) else { return false }
        return !session.base.isLayoutUsed(pageID) && presentation.slides.count > 2
    }

    func deleteBuilderLayout() {
        guard canDeleteBuilderLayout, let page = currentSlide else { return }
        editBuilderProxy("Delete Layout", update: [.slides, .content, .theme]) { proxy, _ in
            proxy.slides.removeAll { $0.id == page.id }
            proxy.themes[0].layouts.removeAll { $0.id == page.layoutID }
        }
    }

    /// Insert ▸ Placeholder, on a layout page: sized like the theme's placeholder of that kind.
    func insertBuilderPlaceholder(_ type: PlaceholderType) {
        guard let pageIndex = currentSlideIndex, !isEditingMaster else { return }
        let size = presentation.slideSize
        let used = Set(presentation.slides[pageIndex].elements.compactMap { $0.placeholder?.index })
        let index = type.isTitle ? 0 : (used.max() ?? 0) + 1
        let master = presentation.themes.first?.elements.first { $0.placeholder.map { ($0.type.isTitle && type.isTitle) || $0.type == type } ?? false }
        let frame = master?.placement?.frame ?? SlideRect(x: size.width * 0.1, y: size.height * 0.3, width: size.width * 0.8, height: size.height * 0.4)
        var body = TextBody()
        if type == .slideNumber { body.paragraphs = [TextParagraph(runs: [TextRun("‹#›", field: .slideNumber)])] }
        let names: [PlaceholderType: String] = [.title: "Title", .subtitle: "Subtitle", .body: "Text", .slideNumber: "Slide Number"]
        let element = SlideElement(name: nextElementName(names[type] ?? "Placeholder"), placement: Placement(frame: frame),
                                   placeholder: PlaceholderRef(type: type, index: index), content: .shape(Shape(text: body)))
        perform("Insert Placeholder", selecting: [element.id]) { proxy in proxy.slides[pageIndex].elements.append(element) }
    }
}
