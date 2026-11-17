import Foundation

/// The theme builder's edits: themes' names and colors, and their layouts.
extension Presentation {
    public func themeIndex(id: UUID) -> Int? { themes.firstIndex { $0.id == id } }

    public mutating func renameTheme(_ id: UUID, to name: String) {
        guard let index = themeIndex(id: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { themes[index].name = trimmed }
    }

    /// The theme builder's Colors: changes one of a theme's colors, and so everything that uses it.
    public mutating func setThemeColor(_ slot: ThemeColorSlot, to color: RGBColor, themeID: UUID) {
        guard let index = themeIndex(id: themeID) else { return }
        themes[index].colors.colors[slot] = color
    }

    public mutating func renameLayout(_ id: UUID, to name: String) {
        guard let location = layoutLocation(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { themes[location.theme].layouts[location.layout].name = trimmed }
    }

    /// Duplicate layout: a copy right after it, named "<name> copy". Returns the copy's id.
    @discardableResult
    public mutating func duplicateLayout(_ id: UUID) -> UUID? {
        guard let location = layoutLocation(id) else { return nil }
        var copy = themes[location.theme].layouts[location.layout]
        copy.id = UUID()
        copy.name += " copy"
        copy.kind = .custom
        copy.elements = copy.elements.map { $0.withNewIDs() }
        themes[location.theme].layouts.insert(copy, at: location.layout + 1)
        return copy.id
    }

    /// Whether any slide uses a layout; layouts in use can't be deleted.
    public func isLayoutUsed(_ id: UUID) -> Bool { slides.contains { $0.layoutID == id } }

    /// Delete layout, for a layout no slide uses and not a theme's last one.
    public mutating func deleteLayout(_ id: UUID) {
        guard let location = layoutLocation(id), !isLayoutUsed(id), themes[location.theme].layouts.count > 1 else { return }
        themes[location.theme].layouts.remove(at: location.layout)
    }

    /// Moves a layout within its theme.
    public mutating func moveLayout(_ id: UUID, to destination: Int) {
        guard let location = layoutLocation(id) else { return }
        let layout = themes[location.theme].layouts.remove(at: location.layout)
        themes[location.theme].layouts.insert(layout, at: max(0, min(themes[location.theme].layouts.count, destination)))
    }

    /// The theme builder's Insert ▸ Placeholder: a new placeholder on a layout, with the next free index for its type,
    /// sized from the theme's placeholder of the same kind when there is one. Returns the new element.
    @discardableResult
    public mutating func addPlaceholder(_ type: PlaceholderType, toLayout id: UUID) -> SlideElement? {
        guard let location = layoutLocation(id) else { return nil }
        let theme = themes[location.theme]
        let layout = theme.layouts[location.layout]
        let used = Set(layout.elements.compactMap { $0.placeholder?.index })
        let index = type.isTitle ? 0 : (used.max() ?? 0) + 1
        let master = theme.elements.first { $0.placeholder.map { ($0.type.isTitle && type.isTitle) || $0.type == type } ?? false }
        let size = slideSize
        let frame = master?.placement?.frame ?? {
            switch type {
            case .title, .centeredTitle: SlideRect(x: size.width * 0.05, y: size.height * 0.1, width: size.width * 0.9, height: size.height * 0.15)
            case .slideNumber: SlideRect(x: size.width * 0.9, y: size.height * 0.9, width: size.width * 0.07, height: size.height * 0.08)
            default: SlideRect(x: size.width * 0.05, y: size.height * 0.3, width: size.width * 0.9, height: size.height * 0.55)
            }
        }()
        let names: [PlaceholderType: String] = [.title: "Title", .centeredTitle: "Title", .subtitle: "Subtitle", .body: "Text", .slideNumber: "Slide Number"]
        var body = TextBody()
        if type == .slideNumber { body.paragraphs = [TextParagraph(runs: [TextRun("‹#›", field: .slideNumber)])] }
        let element = SlideElement(name: "\(names[type] ?? "Placeholder") \(layout.elements.count + 1)", placement: Placement(frame: frame),
                                   placeholder: PlaceholderRef(type: type, index: index), content: .shape(Shape(text: body)))
        themes[location.theme].layouts[location.layout].elements.append(element)
        return element
    }

    // MARK: New objects

    /// Insert ▸ Table: a new table, centered on the slide with columns of an inch and a half (narrower
    /// when that wouldn't fit).
    public func makeTableElement(rows: Int, columns: Int) -> SlideElement {
        let columns = max(1, min(Table.maximumSize, columns)), rows = max(1, min(Table.maximumSize, rows))
        let width = min(Double(columns) * 108, slideSize.width * 0.9)
        let table = Table.make(rows: rows, columns: columns, width: width)
        let height = table.rowHeights.reduce(0, +)
        let frame = SlideRect(x: ((slideSize.width - width) / 2).rounded(), y: max(20, ((slideSize.height - height) / 2).rounded()), width: width,
                              height: height)
        return SlideElement(name: "Table", placement: Placement(frame: frame), content: .table(table))
    }

    /// Insert ▸ Chart: a chart of sample numbers, centered, at the standard size for a new chart.
    public func makeChartElement(_ kind: ChartKind) -> SlideElement {
        let width = min(450, slideSize.width * 0.8), height = min(278, slideSize.height * 0.8)
        let frame = SlideRect(x: ((slideSize.width - width) / 2).rounded(), y: ((slideSize.height - height) / 2).rounded(), width: width, height: height)
        return SlideElement(name: "Chart", placement: Placement(frame: frame), content: .chart(Chart.sample(kind)))
    }
}
