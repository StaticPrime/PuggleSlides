import Foundation

/// Each part's color map, and the XML that colors are inherited from, as read.
struct PPTXColorMapSources {
    struct Background {
        var node: XNode
        var relationships: PPTXRelationships
    }

    struct Master {
        var map: PPTXColorMap
        var title: XNode?
        var body: XNode?
        var other: XNode?
        var background: Background?
    }

    struct Part {
        var map: PPTXColorMap
        var background: Background?
    }

    /// The map the presentation's default text style was read with (the first master's).
    var defaultMap = PPTXColorMap.standard
    var defaultTextStyle: XNode?
    var masters: [UUID: Master] = [:]
    var layouts: [UUID: Part] = [:]
    var slides: [UUID: Part] = [:]
}

/// Scheme colors are read with the color map in force where they appear. Colors a layout or slide inherits from
/// a part with another map (a master's text styles under a layout that overrides the map, say) would then show
/// in the wrong theme color, so they're read again with the inheriting part's map and set on it explicitly.
struct PPTXColorMapFixes {
    let sources: PPTXColorMapSources
    let listStyles: [UUID: XNode]
    let fontReferences: [UUID: XNode]
    let themes: [UUID: PPTXThemeData]

    /// Where an inherited color can come from, nearest first.
    private enum Source {
        case listStyle(XNode?)
        /// A `p:style` font reference, which colors every level.
        case fontReference(XNode?)
    }

    func apply(to presentation: inout Presentation) {
        let maps = sources.masters.values.map(\.map) + sources.layouts.values.map(\.map) + sources.slides.values.map(\.map)
        guard maps.contains(where: { $0 != sources.defaultMap }) else { return }
        fixThemes(&presentation)
        fixLayouts(&presentation)
        fixSlides(&presentation)
    }

    // MARK: Parts

    /// Theme text styles inherit the presentation's defaults, read with the first master's map.
    private func fixThemes(_ presentation: inout Presentation) {
        guard let defaults = sources.defaultTextStyle else { return }
        for index in presentation.themes.indices {
            guard let map = sources.masters[presentation.themes[index].id]?.map, map != sources.defaultMap else { continue }
            for keyPath in [\Theme.titleStyle, \Theme.bodyStyle, \Theme.otherStyle] {
                var style = presentation.themes[index][keyPath: keyPath]
                for level in 0...8 {
                    var own = style[level]
                    let inherited = presentation.defaultTextStyle[level]
                    if own.character.color == nil, let container = statedColor(in: .listStyle(defaults), level: level, bullet: false),
                       let corrected = PPTXColorReader(map: map).color(in: container), corrected != inherited.character.color {
                        own.character.color = corrected
                    }
                    if own.paragraph.bulletColor == nil, let container = statedColor(in: .listStyle(defaults), level: level, bullet: true),
                       let corrected = PPTXColorReader(map: map).color(in: container), corrected != inherited.paragraph.bulletColor {
                        own.paragraph.bulletColor = corrected
                    }
                    style[level] = own
                }
                presentation.themes[index][keyPath: keyPath] = style
            }
        }
    }

    private func fixLayouts(_ presentation: inout Presentation) {
        for themeIndex in presentation.themes.indices {
            let theme = presentation.themes[themeIndex]
            guard let master = sources.masters[theme.id] else { continue }
            for layoutIndex in theme.layouts.indices {
                var layout = theme.layouts[layoutIndex]
                guard let map = sources.layouts[layout.id]?.map, map != master.map else { continue }
                if layout.background == nil, let background = master.background,
                   let corrected = reread(background, map: map, theme: theme.id), corrected != theme.background {
                    layout.background = corrected
                }
                let snapshot = presentation, original = layout
                layout.elements = original.elements.map { element in
                    var element = element
                    let style = snapshot.style(for: element, inLayout: original, theme: theme)
                    fixText(&element, map: map, chain: chain(for: style, master: master), inherited: style.inheritedLevelStyle)
                    return element
                }
                presentation.themes[themeIndex].layouts[layoutIndex] = layout
            }
        }
    }

    private func fixSlides(_ presentation: inout Presentation) {
        for index in presentation.slides.indices {
            let slide = presentation.slides[index]
            guard let map = sources.slides[slide.id]?.map, let layout = presentation.layout(for: slide) else { continue }
            let theme = presentation.theme(for: slide)
            guard let master = sources.masters[theme.id] else { continue }
            let layoutMap = sources.layouts[layout.id]?.map ?? master.map
            guard map != layoutMap || map != master.map else { continue }
            var fixed = slide
            if slide.background == nil, let background = sources.layouts[layout.id]?.background ?? master.background,
               let corrected = reread(background, map: map, theme: theme.id), corrected != presentation.background(for: slide) {
                fixed.background = corrected
            }
            fixed.elements = slide.elements.map { element in
                var element = element
                fixSlideElement(&element, on: slide, map: map, master: master, presentation: presentation)
                return element
            }
            presentation.slides[index] = fixed
        }
    }

    private func fixSlideElement(_ element: inout SlideElement, on slide: Slide, map: PPTXColorMap, master: PPTXColorMapSources.Master,
                                 presentation: Presentation) {
        if case .group(let children) = element.content {
            element.content = .group(children.map { child in
                var child = child
                fixSlideElement(&child, on: slide, map: map, master: master, presentation: presentation)
                return child
            })
            return
        }
        let style = presentation.style(for: element, on: slide)
        fixText(&element, map: map, chain: chain(for: style, master: master), inherited: style.inheritedLevelStyle)
    }

    // MARK: Text

    /// The raw sources of an element's inherited text formatting, nearest first, as the model inherits.
    private func chain(for style: ElementStyle, master: PPTXColorMapSources.Master) -> [Source] {
        var result: [Source] = []
        if style.element.placeholder != nil {
            for parent in style.parents {
                result.append(.listStyle(listStyles[parent.id]))
                result.append(.fontReference(fontReferences[parent.id]))
            }
        }
        switch style.category {
        case .title: result.append(.listStyle(master.title))
        case .body: result.append(.listStyle(master.body))
        case .other: result.append(.listStyle(master.other))
        }
        result.append(.listStyle(sources.defaultTextStyle))
        return result
    }

    /// The element containing the color a source states for a level, if it states one.
    private func statedColor(in source: Source, level: Int, bullet: Bool) -> XNode? {
        switch source {
        case .fontReference(let node):
            return bullet ? nil : node
        case .listStyle(let node):
            guard let node else { return nil }
            for name in ["lvl\(level + 1)pPr", "defPPr"] {
                guard let properties = node.child(name) else { continue }
                if bullet {
                    if let color = properties.child("buClr") { return color }
                } else if let fill = properties.child("defRPr")?.child("solidFill") {
                    return fill
                }
            }
            return nil
        }
    }

    /// Fixes the text of a shape, or of every cell of a table, which inherits like any text that isn't a placeholder's.
    private func fixText(_ element: inout SlideElement, map: PPTXColorMap, chain: [Source], inherited: (Int) -> LevelStyle) {
        switch element.content {
        case .shape(var shape):
            guard var text = shape.text, fixBody(&text, map: map, chain: chain, inherited: inherited) else { return }
            shape.text = text
            element.content = .shape(shape)
        case .table(var table):
            var changed = false
            for row in table.cells.indices {
                for column in table.cells[row].indices where fixBody(&table.cells[row][column].text, map: map, chain: chain, inherited: inherited) {
                    changed = true
                }
            }
            if changed { element.content = .table(table) }
        case .picture, .group, .chart, .media:
            return
        }
    }

    /// Sets the colors a body inherits under another map on its own list style; true when anything changed.
    private func fixBody(_ text: inout TextBody, map: PPTXColorMap, chain: [Source], inherited: (Int) -> LevelStyle) -> Bool {
        let reader = PPTXColorReader(map: map)
        var changed = false
        for level in Set(text.paragraphs.map(\.level)).union([0]).sorted() {
            var own = text.listStyle[level]
            let current = inherited(level)
            if own.character.color == nil,
               let container = chain.lazy.compactMap({ statedColor(in: $0, level: level, bullet: false) }).first,
               let corrected = reader.color(in: container), corrected != current.character.color {
                own.character.color = corrected
                changed = true
            }
            if own.paragraph.bulletColor == nil,
               let container = chain.lazy.compactMap({ statedColor(in: $0, level: level, bullet: true) }).first,
               let corrected = reader.color(in: container), corrected != current.paragraph.bulletColor {
                own.paragraph.bulletColor = corrected
                changed = true
            }
            text.listStyle[level] = own
        }
        return changed
    }

    // MARK: Backgrounds

    private func reread(_ background: PPTXColorMapSources.Background, map: PPTXColorMap, theme: UUID) -> Fill? {
        guard let data = themes[theme] else { return nil }
        let reader = PPTXFillReader(colors: PPTXColorReader(map: map), theme: data, media: { _ in nil }, groupFill: nil)
        // Pictures read the same under any map; only colors change.
        if background.node.child("bgPr")?.child("blipFill") != nil { return nil }
        return reader.background(background.node)
    }
}
