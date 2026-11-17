import Foundation

extension SlideElement {
    /// Stretches the element's position and size (and a group's children, and a table's columns and rows), as
    /// Page setup and importing slides from a page of another size do.
    public mutating func scale(x sx: Double, y sy: Double) {
        guard sx.isFinite, sy.isFinite, sx > 0, sy > 0 else { return }
        if var placement {
            let frame = placement.frame
            placement.frame = SlideRect(x: frame.x * sx, y: frame.y * sy, width: frame.width * sx, height: frame.height * sy)
            self.placement = placement
        }
        switch content {
        case .group(var children):
            for index in children.indices { children[index].scale(x: sx, y: sy) }
            content = .group(children)
        case .table(var table):
            table.scale(width: sx, height: sy)
            content = .table(table)
        case .shape, .picture, .chart, .media:
            break
        }
    }
}

extension Presentation {
    /// Scales every element of every theme, layout and slide to a new page size (File ▸ Page setup).
    public mutating func changeSlideSize(to size: SlideSize) {
        let old = slideSize
        guard size != old, size.width > 0, size.height > 0, old.width > 0, old.height > 0 else { return }
        let sx = size.width / old.width, sy = size.height / old.height
        slideSize = size
        for themeIndex in themes.indices {
            for index in themes[themeIndex].elements.indices { themes[themeIndex].elements[index].scale(x: sx, y: sy) }
            for layoutIndex in themes[themeIndex].layouts.indices {
                for index in themes[themeIndex].layouts[layoutIndex].elements.indices {
                    themes[themeIndex].layouts[layoutIndex].elements[index].scale(x: sx, y: sy)
                }
            }
        }
        for slideIndex in slides.indices {
            for index in slides[slideIndex].elements.indices { slides[slideIndex].elements[index].scale(x: sx, y: sy) }
        }
        for index in guides.indices {
            guides[index].position *= guides[index].orientation == .vertical ? sx : sy
        }
    }

    /// Whether two themes are the same design (one presentation's theme read back from a file, say): the same
    /// name, colors, fonts and layout names.
    static func isSameDesign(_ a: Theme, _ b: Theme) -> Bool {
        a.name == b.name && a.colors == b.colors && a.fonts == b.fonts && a.layouts.map(\.name) == b.layouts.map(\.name)
    }

    /// Adds slides from elsewhere (pasted, or File ▸ Import slides) at `index`, with new ids.
    ///
    /// With `keepingThemes`, each slide keeps its own theme, which joins this presentation unless the same design is
    /// already here. Otherwise slides take the matching layouts of `theme` ("Match theme"). Slides
    /// from a page of another size are scaled to fit this one. Returns the new slides' ids.
    @discardableResult
    public mutating func insertSlides(_ incoming: [Slide], themes sourceThemes: [Theme], media sourceMedia: [MediaID: MediaItem],
                                      sourceSize: SlideSize? = nil, at index: Int, keepingThemes: Bool, theme target: Theme? = nil) -> [UUID] {
        let target = target ?? themes.first ?? BuiltInThemes.simpleLight()
        var inserted: [Slide] = []
        let sx = sourceSize.map { $0.width > 0 ? slideSize.width / $0.width : 1 } ?? 1
        let sy = sourceSize.map { $0.height > 0 ? slideSize.height / $0.height : 1 } ?? 1
        for slide in incoming {
            var copy = duplicate(slide)
            if sx != 1 || sy != 1 {
                for element in copy.elements.indices { copy.elements[element].scale(x: sx, y: sy) }
            }
            let sourceTheme = sourceThemes.first { $0.layout(id: slide.layoutID) != nil }
            let sourceLayout = sourceTheme?.layout(id: slide.layoutID)
            if layout(id: slide.layoutID) != nil {
                // The layout is already here (a slide copied within this presentation).
            } else if keepingThemes, let sourceTheme, let sourceLayout {
                if let existing = themes.first(where: { Self.isSameDesign($0, sourceTheme) }) {
                    let match = existing.layouts.first { $0.name == sourceLayout.name } ?? existing.layout(kind: sourceLayout.kind) ?? existing.layouts.first
                    if let match { copy.layoutID = match.id }
                } else {
                    var added = sourceTheme
                    if sx != 1 || sy != 1 {
                        for element in added.elements.indices { added.elements[element].scale(x: sx, y: sy) }
                        for layout in added.layouts.indices {
                            for element in added.layouts[layout].elements.indices { added.layouts[layout].elements[element].scale(x: sx, y: sy) }
                        }
                    }
                    themes.append(added)
                }
            } else {
                let kind = sourceLayout?.kind
                let match = kind.flatMap { $0 == .custom ? nil : target.layout(kind: $0) } ?? target.layout(kind: .titleAndBody) ?? target.layouts.first
                if let match {
                    // Apply layout needs the slide's old layout to move its text into the new placeholders.
                    var scratch = Presentation(slideSize: slideSize, themes: sourceThemes + themes, slides: [copy], media: [:],
                                               defaultTextStyle: defaultTextStyle)
                    scratch.applyLayout(match.id, toSlideAt: 0)
                    copy = scratch.slides[0]
                }
            }
            inserted.append(copy)
        }
        for slide in inserted {
            for id in slide.elements.reduce(into: Set<MediaID>(), { $0.formUnion($1.mediaIDs) }).union(slide.background?.mediaID.map { [$0] } ?? [])
            where media[id] == nil {
                if let item = sourceMedia[id] { media[id] = item }
            }
        }
        // Media the added themes use.
        for theme in themes {
            var ids = Set(theme.elements.flatMap(\.mediaIDs))
            if let id = theme.background.mediaID { ids.insert(id) }
            for layout in theme.layouts {
                ids.formUnion(layout.elements.flatMap(\.mediaIDs))
                if let id = layout.background?.mediaID { ids.insert(id) }
            }
            for id in ids where media[id] == nil {
                if let item = sourceMedia[id] { media[id] = item }
            }
        }
        let position = max(0, min(slides.count, index))
        slides.insert(contentsOf: inserted, at: position)
        return inserted.map(\.id)
    }

    /// Themes ▸ Import theme: adds a theme from another presentation (unless the same design is already here) and
    /// gives it to every slide. Returns the theme now in use.
    @discardableResult
    public mutating func importTheme(_ theme: Theme, media sourceMedia: [MediaID: MediaItem], sourceSize: SlideSize? = nil) -> Theme {
        var theme = theme
        if let sourceSize, sourceSize != slideSize, sourceSize.width > 0, sourceSize.height > 0 {
            let sx = slideSize.width / sourceSize.width, sy = slideSize.height / sourceSize.height
            for element in theme.elements.indices { theme.elements[element].scale(x: sx, y: sy) }
            for layout in theme.layouts.indices {
                for element in theme.layouts[layout].elements.indices { theme.layouts[layout].elements[element].scale(x: sx, y: sy) }
            }
        }
        var ids = Set(theme.elements.flatMap(\.mediaIDs))
        if let id = theme.background.mediaID { ids.insert(id) }
        for layout in theme.layouts {
            ids.formUnion(layout.elements.flatMap(\.mediaIDs))
            if let id = layout.background?.mediaID { ids.insert(id) }
        }
        for id in ids where media[id] == nil {
            if let item = sourceMedia[id] { media[id] = item }
        }
        applyTheme(theme)
        return theme
    }
}
