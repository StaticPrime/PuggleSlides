import AppKit
import PuggleSlidesKit

enum ListKind: Equatable {
    case none
    case bulleted(String)
    case numbered(AutoNumberScheme)
}

/// The font sizes for the size menu and for stepping with ⇧⌘. and ⇧⌘,.
let standardFontSizes: [Double] = [6, 7, 8, 9, 10, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96]

extension PresentationController {
    // MARK: Text in whole shapes (when a shape is selected but not being edited)

    /// Selected elements that hold or can hold text, including those inside groups.
    var selectedTextElementIDs: [UUID] {
        selectedElements.filter { $0.shape != nil && !$0.isLine }.map(\.id)
    }

    /// Edits the text of every selected shape. Groups pass the edit to their children.
    func editSelectedText(_ actionName: String, _ edit: @escaping (inout TextBody, ElementStyle) -> Void) {
        guard let slideIndex = currentSlideIndex else { return }
        let ids = Set(selectedElementIDs)
        // A selected table's text changes in its selected cells (or all of them).
        let cells = selectedTableElement?.table.map(tableRange)
        perform(actionName) { presentation in
            let slide = presentation.slides[slideIndex]
            func apply(_ element: inout SlideElement) {
                if var children = element.children {
                    for index in children.indices { apply(&children[index]) }
                    element.children = children
                    return
                }
                if var table = element.table {
                    let style = presentation.style(for: element, on: slide)
                    table.updateTexts(in: cells) { text in edit(&text, style) }
                    element.table = table
                    return
                }
                guard var shape = element.shape, !element.isLine else { return }
                var text = shape.text ?? TextBody()
                edit(&text, presentation.style(for: element, on: slide))
                shape.text = text
                element.shape = shape
            }
            for index in slide.elements.indices where ids.contains(slide.elements[index].id) {
                var element = presentation.slides[slideIndex].elements[index]
                apply(&element)
                if element.table != nil { fitTableFrame(&element, style: presentation.style(for: element, on: slide)) }
                presentation.slides[slideIndex].elements[index] = element
            }
        }
    }

    /// Sets a character property on every run and paragraph mark.
    func setCharacters(_ actionName: String, _ change: @escaping (inout CharacterStyle) -> Void) {
        editSelectedText(actionName) { text, _ in
            for p in text.paragraphs.indices {
                for r in text.paragraphs[p].runs.indices { change(&text.paragraphs[p].runs[r].style) }
                change(&text.paragraphs[p].endStyle)
            }
        }
    }

    func setParagraphs(_ actionName: String, _ change: @escaping (inout TextParagraph, ElementStyle) -> Void) {
        editSelectedText(actionName) { text, style in
            for p in text.paragraphs.indices { change(&text.paragraphs[p], style) }
        }
    }

    /// Resolved runs of the selected shapes' text, for toggles and the toolbar.
    var selectedResolvedParagraphs: [ResolvedParagraph] {
        guard let slide = currentSlide else { return [] }
        var result: [ResolvedParagraph] = []
        let cells = selectedTableElement?.table.map(tableRange)
        func collect(_ element: SlideElement) {
            if let children = element.children { children.forEach(collect); return }
            if let table = element.table {
                let style = presentation.style(for: element, on: slide)
                let range = cells ?? tableRange(table)
                for row in range.rows {
                    for column in range.columns where !table.cells[row][column].isCovered {
                        result += style.resolvedParagraphs(table.cells[row][column].text)
                    }
                }
                return
            }
            guard element.shape != nil, !element.isLine else { return }
            result += presentation.style(for: element, on: slide).resolvedParagraphs()
        }
        selectedElements.forEach(collect)
        return result
    }

    private var selectedResolvedRuns: [ResolvedCharacterStyle] {
        selectedResolvedParagraphs.flatMap { paragraph in
            paragraph.runs.isEmpty ? [paragraph.endStyle] : paragraph.runs.map(\.style)
        }
    }

    func toggleBold() {
        let on = !selectedResolvedRuns.allSatisfy(\.bold)
        setCharacters("Bold") { $0.bold = on }
    }

    func toggleItalic() {
        let on = !selectedResolvedRuns.allSatisfy(\.italic)
        setCharacters("Italic") { $0.italic = on }
    }

    func toggleUnderline() {
        let on = !selectedResolvedRuns.allSatisfy(\.underline)
        setCharacters("Underline") { $0.underline = on }
    }

    func toggleStrikethrough() {
        let on = !selectedResolvedRuns.allSatisfy(\.strikethrough)
        setCharacters("Strikethrough") { $0.strikethrough = on }
    }

    func setBaseline(_ baseline: BaselineShift) {
        let current = selectedResolvedRuns.allSatisfy { $0.baseline == baseline }
        setCharacters(baseline == .superscript ? "Superscript" : "Subscript") { $0.baseline = current ? .normal : baseline }
    }

    func setFontFamily(_ family: String) { setCharacters("Font") { $0.fontFamily = family } }

    func setFontSize(_ size: Double) {
        let clamped = max(1, min(400, size))
        setCharacters("Font Size") { $0.fontSize = clamped }
    }

    /// The toolbar's − and + step by one point; the menu steps through the standard sizes.
    func stepFontSize(by delta: Double, standardSteps: Bool = false) {
        guard let slide = currentSlide else { return }
        let ids = Set(selectedElementIDs)
        let stepped: (Double) -> Double = { size in
            guard standardSteps else { return max(1, min(400, size + delta)) }
            if delta > 0 { return standardFontSizes.first { $0 > size } ?? size + 12 }
            return standardFontSizes.last { $0 < size } ?? max(1, size - 1)
        }
        guard let slideIndex = currentSlideIndex else { return }
        perform("Font Size") { presentation in
            for index in slide.elements.indices where ids.contains(slide.elements[index].id) {
                let element = slide.elements[index]
                guard var shape = element.shape, var text = shape.text, !element.isLine else { continue }
                let resolved = presentation.style(for: element, on: slide).resolvedParagraphs()
                let scale = presentation.style(for: element, on: slide).bodyProperties
                let fontScale = scale.autofit == .shrinkOnOverflow ? scale.fontScale : 1
                for p in text.paragraphs.indices where p < resolved.count {
                    for r in text.paragraphs[p].runs.indices where r < resolved[p].runs.count {
                        text.paragraphs[p].runs[r].style.fontSize = stepped(resolved[p].runs[r].style.fontSize / fontScale)
                    }
                    text.paragraphs[p].endStyle.fontSize = stepped(resolved[p].endStyle.fontSize / fontScale)
                }
                shape.text = text
                presentation.slides[slideIndex].elements[index].shape = shape
            }
        }
    }

    func setTextColor(_ color: ColorRef?) { setCharacters("Text Color") { $0.color = color } }
    func setHighlight(_ color: ColorRef?) { setCharacters("Highlight Color") { $0.highlight = color } }
    func setLink(_ link: Hyperlink?) { setCharacters(link == nil ? "Remove Link" : "Insert Link") { $0.link = link } }

    func setAlignment(_ alignment: PuggleSlidesKit.TextAlignment) {
        setParagraphs("Align") { paragraph, _ in paragraph.style.alignment = alignment }
    }

    func setLineSpacing(_ spacing: Double) {
        setParagraphs("Line Spacing") { paragraph, _ in paragraph.style.lineSpacing = spacing }
    }

    func setParagraphSpacing(before: Double? = nil, after: Double? = nil) {
        setParagraphs("Paragraph Spacing") { paragraph, _ in
            if let before { paragraph.style.spaceBefore = before }
            if let after { paragraph.style.spaceAfter = after }
        }
    }

    /// Bulleted and numbered lists. The presets set the bullet for the first level and indent the text.
    func setList(_ kind: ListKind) {
        setParagraphs("List") { paragraph, style in
            Self.applyList(kind, to: &paragraph, style: style)
        }
    }

    static func applyList(_ kind: ListKind, to paragraph: inout TextParagraph, style: ElementStyle) {
        let inherited = style.inheritedLevelStyle(paragraph.level).paragraph
        let margin = 36.0 * Double(paragraph.level + 1)
        switch kind {
        case .none:
            paragraph.style.bullet = Bullet.none
            if inherited.bullet != Bullet.none && inherited.bullet != nil {
                paragraph.style.marginLeft = 36.0 * Double(paragraph.level)
            } else {
                paragraph.style.marginLeft = nil
            }
            paragraph.style.indent = 0
        case .bulleted(let character):
            paragraph.style.bullet = .character(character)
            if inherited.marginLeft ?? 0 <= 0 { paragraph.style.marginLeft = margin }
            if inherited.indent ?? 0 >= 0 { paragraph.style.indent = -18 }
        case .numbered(let scheme):
            paragraph.style.bullet = .number(scheme, startAt: 1)
            if inherited.marginLeft ?? 0 <= 0 { paragraph.style.marginLeft = margin }
            if inherited.indent ?? 0 >= 0 { paragraph.style.indent = -18 }
        }
    }

    /// Format ▸ Align & indent ▸ Increase / Decrease indent.
    func indent(by delta: Int) {
        setParagraphs(delta > 0 ? "Increase Indent" : "Decrease Indent") { paragraph, _ in
            paragraph.level = max(0, min(8, paragraph.level + delta))
            if let margin = paragraph.style.marginLeft { paragraph.style.marginLeft = max(0, margin + 36 * Double(delta)) }
        }
    }

    /// Format ▸ Clear formatting (⌘\): text goes back to its theme's look.
    func clearTextFormatting() {
        editSelectedText("Clear Formatting") { text, _ in
            for p in text.paragraphs.indices {
                for r in text.paragraphs[p].runs.indices {
                    let link = text.paragraphs[p].runs[r].style.link
                    text.paragraphs[p].runs[r].style = CharacterStyle(link: link)
                }
                text.paragraphs[p].style = .empty
                text.paragraphs[p].endStyle = .empty
            }
        }
    }

    func setAnchor(_ anchor: VerticalAnchor) {
        if selectedTableElement != nil { return setTableCellAnchor(anchor) }
        editSelectedText("Vertical Align") { text, _ in text.properties.anchor = anchor }
    }

    func setAutofit(_ autofit: Autofit) {
        editSelectedText("Text Fitting") { text, _ in
            text.properties.autofit = autofit
            text.properties.fontScale = nil
            text.properties.lineSpacingReduction = nil
        }
    }

    func setInsets(_ insets: TextInsets) {
        editSelectedText("Indentation Padding") { text, _ in text.properties.insets = insets }
    }

    // MARK: Fill and border

    func setFill(_ fill: Fill) {
        if selectedTableElement != nil { return setTableFill(fill) }
        editSelectedElements("Fill Color") { element, _ in
            guard var shape = element.shape, !element.isLine else { return }
            shape.fill = fill
            element.shape = shape
        }
    }

    /// Changes the borders (or lines) of the selected elements, starting from what they show now. Changing the
    /// weight, dash or line ends of a hidden border shows it in the default line color.
    func editOutline(_ actionName: String, showsHidden: Bool = true, _ change: @escaping (inout Outline) -> Void) {
        if selectedTableElement != nil { return editTableBorders(actionName, showsHidden: showsHidden, change) }
        let lineColor = defaultLineColor
        editSelectedElements(actionName) { element, style in
            var outline = style.outline
            if showsHidden, outline.fill.isNone { outline.fill = .solid(lineColor) }
            if outline.width <= 0 { outline.width = 0.75 }
            change(&outline)
            if var shape = element.shape {
                shape.outline = outline
                element.shape = shape
            } else if var picture = element.picture {
                picture.outline = outline
                element.picture = picture
            }
        }
    }

    func setBorderColor(_ color: ColorRef?) {
        editOutline("Border Color", showsHidden: false) { outline in outline.fill = color.map(Fill.solid) ?? .none }
    }

    func setBorderWidth(_ width: Double) {
        editOutline("Border Weight") { outline in outline.width = width }
    }

    func setBorderDash(_ dash: DashStyle) {
        editOutline("Border Dash") { outline in outline.dash = dash }
    }

    func setLineEnds(head: LineEnd? = nil, tail: LineEnd? = nil) {
        editOutline(head != nil ? "Line Start" : "Line End") { outline in
            if let head { outline.head = head }
            if let tail { outline.tail = tail }
        }
    }

    func setAltText(title: String?, description: String?) {
        editSelectedElements("Alt Text") { element, _ in
            element.altTitle = title?.isEmpty == true ? nil : title
            element.altDescription = description?.isEmpty == true ? nil : description
        }
    }

    /// Paint format: gives `target` the fill, border and text look of `source`.
    func applyFormat(from source: SlideElement, to targetID: UUID) {
        guard let slide = currentSlide, source.id != targetID else { return }
        let sourceStyle = presentation.style(for: source, on: slide)
        let character = sourceStyle.resolvedParagraphs().first?.runs.first?.style
        let paragraph = source.shape?.text?.paragraphs.first?.style
        editElements([targetID], "Paint Format") { element, _ in
            if var shape = element.shape, source.shape != nil {
                if !element.isLine, !source.isLine { shape.fill = sourceStyle.fill }
                shape.outline = sourceStyle.outline
                if var text = shape.text, let character {
                    let style = CharacterStyle(fontFamily: character.fontFamily, fontSize: character.fontSize, bold: character.bold,
                                               italic: character.italic, underline: character.underline, strikethrough: character.strikethrough,
                                               color: source.shape?.text?.paragraphs.first?.runs.first?.style.color ?? ColorRef(character.color.rgb),
                                               highlight: nil, baseline: character.baseline)
                    for p in text.paragraphs.indices {
                        for r in text.paragraphs[p].runs.indices { text.paragraphs[p].runs[r].style = style.merged(over: CharacterStyle(link: text.paragraphs[p].runs[r].style.link)) }
                        text.paragraphs[p].endStyle = style
                        if let paragraph { text.paragraphs[p].style.alignment = paragraph.alignment ?? text.paragraphs[p].style.alignment }
                    }
                    shape.text = text
                }
                element.shape = shape
            } else if var picture = element.picture {
                picture.outline = sourceStyle.outline
                element.picture = picture
            }
        }
    }

    // MARK: What the toolbar shows

    func selectionKind() -> SelectionKind {
        let elements = selectedElements
        guard let first = elements.first else { return .none }
        if elements.count > 1 { return .multiple }
        if first.children != nil { return .group }
        if first.picture != nil { return .image }
        if first.media != nil { return .media }
        if first.table != nil { return .table }
        if first.chart != nil { return .chart }
        if first.isWordArt { return .wordArt }
        if first.isLine { return .line }
        if first.shape?.isTextBox == true || first.placeholder != nil { return .textBox }
        return .shape
    }

    func shapeSummary() -> ShapeSummary {
        guard let slide = currentSlide else { return ShapeSummary() }
        if let element = selectedTableElement, let table = element.table {
            return tableSummary(table, theme: presentation.theme(for: slide))
        }
        let styles = selectedElements.map { presentation.style(for: $0, on: slide) }
        guard let first = styles.first else { return ShapeSummary() }
        func same<T: Equatable>(_ value: (ElementStyle) -> T?) -> T? {
            let firstValue = value(first)
            return styles.allSatisfy { value($0) == firstValue } ? firstValue : nil
        }
        func hex(_ fill: Fill) -> String? {
            guard case .solid(let color) = fill else { return nil }
            return color.resolved(first.theme.colors).rgb.hex
        }
        return ShapeSummary(fillHex: same { hex($0.fill) }, borderHex: same { $0.outline.isVisible ? hex($0.outline.fill) : nil },
                            borderWidth: same { $0.outline.isVisible ? $0.outline.width : nil }, dash: same { $0.outline.dash },
                            head: same { $0.outline.head }, tail: same { $0.outline.tail })
    }

    func textSummary() -> TextSummary {
        let paragraphs = selectedResolvedParagraphs
        let runs = paragraphs.flatMap { $0.runs.isEmpty ? [$0.endStyle] : $0.runs.map(\.style) }
        guard let first = runs.first else { return TextSummary() }
        var summary = TextSummary()
        summary.fontFamily = runs.allSatisfy { $0.fontFamily == first.fontFamily } ? first.fontFamily : nil
        let fontScale = selectedElements.first.flatMap { style(of: $0)?.bodyProperties }.map { $0.autofit == .shrinkOnOverflow ? $0.fontScale : 1 } ?? 1
        summary.fontSize = runs.allSatisfy { $0.fontSize == first.fontSize } ? (first.fontSize / fontScale).rounded(toPlaces: 1) : nil
        summary.bold = runs.allSatisfy(\.bold)
        summary.italic = runs.allSatisfy(\.italic)
        summary.underline = runs.allSatisfy(\.underline)
        summary.strikethrough = runs.allSatisfy(\.strikethrough)
        summary.colorHex = runs.allSatisfy { $0.color == first.color } ? first.color.rgb.hex : nil
        summary.highlightHex = first.highlight?.rgb.hex
        summary.alignment = paragraphs.allSatisfy { $0.alignment == paragraphs[0].alignment } ? paragraphs[0].alignment : nil
        summary.lineSpacing = paragraphs.first?.lineSpacing
        if let bullet = paragraphs.first?.bullet {
            summary.isNumbered = bullet.text.last == "." || bullet.text.last == ")"
            summary.isBulleted = !summary.isNumbered
        }
        summary.anchor = selectedElements.first.flatMap { style(of: $0)?.bodyProperties.anchor }
        summary.hasLink = runs.contains { $0.link != nil }
        return summary
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
