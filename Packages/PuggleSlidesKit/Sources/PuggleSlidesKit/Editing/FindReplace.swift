import Foundation

/// Edit ▸ Find and replace: what to look for.
public struct TextSearch: Hashable, Sendable {
    public var text: String
    /// "Match case".
    public var matchesCase: Bool
    /// "Match using regular expressions". Replacements are still inserted as typed.
    public var usesRegularExpression: Bool

    public init(_ text: String, matchesCase: Bool = false, usesRegularExpression: Bool = false) {
        self.text = text
        self.matchesCase = matchesCase
        self.usesRegularExpression = usesRegularExpression
    }

    /// The search as an expression; nil when there's nothing to find or the regular expression isn't valid.
    public var expression: NSRegularExpression? {
        guard !text.isEmpty else { return nil }
        let pattern = usesRegularExpression ? text : NSRegularExpression.escapedPattern(for: text)
        return try? NSRegularExpression(pattern: pattern, options: matchesCase ? [] : [.caseInsensitive])
    }

    /// False for a regular expression that can't be used.
    public var isValid: Bool { text.isEmpty || expression != nil }
}

/// Where a match is.
public enum TextPlace: Hashable, Sendable {
    /// An object's text. The ids lead from the slide's object down through groups to the one holding the text.
    case element([UUID])
    /// A table cell; the ids lead to the table.
    case cell([UUID], row: Int, column: Int)
    /// The slide's speaker notes.
    case notes
}

/// One place the search text was found.
public struct TextMatch: Hashable, Sendable {
    public var slideID: UUID
    public var place: TextPlace
    /// UTF-16 offsets into the place's plain text, whose paragraphs are separated by newlines.
    public var range: Range<Int>

    public init(slideID: UUID, place: TextPlace, range: Range<Int>) {
        self.slideID = slideID
        self.place = place
        self.range = range
    }
}

extension Presentation {
    /// Every match, slide by slide. On a slide: its objects back to front (a group's in its order, a table's cells
    /// row by row), then the speaker notes. Matches never take in part of a field such as a slide number.
    public func matches(of search: TextSearch) -> [TextMatch] {
        guard let expression = search.expression else { return [] }
        return slides.flatMap { slide in
            slide.searchableTexts().flatMap { place, body in
                Self.ranges(of: expression, in: body).map { TextMatch(slideID: slide.id, place: place, range: $0) }
            }
        }
    }

    /// Replaces one match with `replacement`, which takes the formatting of the text it replaces. False when the
    /// text no longer holds that match.
    @discardableResult
    public mutating func replace(_ match: TextMatch, with replacement: String, search: TextSearch) -> Bool {
        guard let expression = search.expression, let index = slideIndex(id: match.slideID),
              var body = slides[index].text(at: match.place), Self.ranges(of: expression, in: body).contains(match.range) else { return false }
        body.replaceCharacters(in: match.range, with: replacement)
        return slides[index].setText(body, at: match.place)
    }

    /// Replaces every match; returns how many there were.
    @discardableResult
    public mutating func replaceAll(_ search: TextSearch, with replacement: String) -> Int {
        guard let expression = search.expression else { return 0 }
        var count = 0
        for index in slides.indices {
            for (place, body) in slides[index].searchableTexts() {
                let ranges = Self.ranges(of: expression, in: body)
                guard !ranges.isEmpty else { continue }
                var edited = body
                for range in ranges.reversed() { edited.replaceCharacters(in: range, with: replacement) }
                if slides[index].setText(edited, at: place) { count += ranges.count }
            }
        }
        return count
    }

    /// Non-empty matches of `expression` in a body's plain text that don't take in part of a field.
    static func ranges(of expression: NSRegularExpression, in body: TextBody) -> [Range<Int>] {
        let text = body.plainText
        let fields = body.fieldRanges
        var result: [Range<Int>] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, _ in
            guard let found = match?.range, found.location != NSNotFound, found.length > 0 else { return }
            let range = found.location..<(found.location + found.length)
            if !fields.contains(where: { $0.overlaps(range) }) { result.append(range) }
        }
        return result
    }
}

extension Slide {
    /// The slide's text in search order, with where each is.
    func searchableTexts() -> [(place: TextPlace, body: TextBody)] {
        var result: [(place: TextPlace, body: TextBody)] = []
        func visit(_ elements: [SlideElement], path: [UUID]) {
            for element in elements {
                let here = path + [element.id]
                switch element.content {
                case .shape(let shape):
                    if let text = shape.text, !text.isEmpty { result.append((.element(here), text)) }
                case .group(let children):
                    visit(children, path: here)
                case .table(let table):
                    for (row, column) in table.visibleCells where !table.cells[row][column].text.isEmpty {
                        result.append((.cell(here, row: row, column: column), table.cells[row][column].text))
                    }
                case .picture, .chart, .media:
                    break
                }
            }
        }
        visit(elements, path: [])
        if !notes.isEmpty { result.append((.notes, notes)) }
        return result
    }

    /// The text at a place; nil when it's gone.
    public func text(at place: TextPlace) -> TextBody? {
        switch place {
        case .notes:
            return notes
        case .element(let path):
            guard case .shape(let shape)? = Self.element(at: path[...], in: elements)?.content else { return nil }
            return shape.text
        case .cell(let path, let row, let column):
            guard case .table(let table)? = Self.element(at: path[...], in: elements)?.content,
                  table.cells.indices.contains(row), table.cells[row].indices.contains(column) else { return nil }
            return table.cells[row][column].text
        }
    }

    /// Puts `body` at a place; false when the place is gone.
    @discardableResult
    public mutating func setText(_ body: TextBody, at place: TextPlace) -> Bool {
        switch place {
        case .notes:
            notes = body
            return true
        case .element(let path):
            return Self.modifyElement(at: path[...], in: &elements) { element in
                guard case .shape(var shape) = element.content, shape.text != nil else { return false }
                shape.text = body
                element.content = .shape(shape)
                return true
            }
        case .cell(let path, let row, let column):
            return Self.modifyElement(at: path[...], in: &elements) { element in
                guard case .table(var table) = element.content, table.cells.indices.contains(row),
                      table.cells[row].indices.contains(column) else { return false }
                table.cells[row][column].text = body
                element.content = .table(table)
                return true
            }
        }
    }

    static func element(at path: ArraySlice<UUID>, in elements: [SlideElement]) -> SlideElement? {
        guard let id = path.first, let element = elements.first(where: { $0.id == id }) else { return nil }
        if path.count == 1 { return element }
        guard case .group(let children) = element.content else { return nil }
        return Self.element(at: path.dropFirst(), in: children)
    }

    static func modifyElement(at path: ArraySlice<UUID>, in elements: inout [SlideElement],
                              _ edit: (inout SlideElement) -> Bool) -> Bool {
        guard let id = path.first, let index = elements.firstIndex(where: { $0.id == id }) else { return false }
        if path.count == 1 { return edit(&elements[index]) }
        guard case .group(var children) = elements[index].content else { return false }
        guard modifyElement(at: path.dropFirst(), in: &children, edit) else { return false }
        elements[index].content = .group(children)
        return true
    }
}

extension TextBody {
    /// UTF-16 ranges of `plainText` held by fields (slide numbers, dates).
    var fieldRanges: [Range<Int>] {
        var result: [Range<Int>] = []
        var offset = 0
        for paragraph in paragraphs {
            for run in paragraph.runs {
                let length = run.text.utf16.count
                if run.field != nil, length > 0 { result.append(offset..<(offset + length)) }
                offset += length
            }
            offset += 1
        }
        return result
    }

    /// Replaces the characters in `range` (UTF-16 offsets into `plainText`) with `replacement`, which takes the
    /// formatting of the first character it replaces, or of the character before when nothing is replaced. Newlines
    /// in the replacement start paragraphs formatted like the one the replacement starts in.
    public mutating func replaceCharacters(in range: Range<Int>, with replacement: String) {
        var starts: [Int] = []
        var offset = 0
        for paragraph in paragraphs {
            starts.append(offset)
            offset += paragraph.text.utf16.count + 1
        }
        let total = offset - 1
        let lower = min(max(range.lowerBound, 0), total)
        let upper = min(max(range.upperBound, lower), total)
        func locate(_ position: Int) -> (paragraph: Int, offset: Int) {
            let index = starts.lastIndex { $0 <= position } ?? 0
            return (index, position - starts[index])
        }
        let (first, firstOffset) = locate(lower)
        let (last, lastOffset) = locate(upper)
        let style = upper > lower ? paragraphs[first].characterStyle(at: firstOffset)
            : paragraphs[first].characterStyle(at: max(0, firstOffset - 1))
        let head = paragraphs[first].split(at: firstOffset).head
        let tail = paragraphs[last].split(at: lastOffset).tail
        let lines = replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var built: [TextParagraph] = []
        for (index, line) in lines.enumerated() {
            var paragraph = paragraphs[first]
            var runs = index == 0 ? head : []
            if !line.isEmpty { runs.append(TextRun(line, style: style)) }
            if index == lines.count - 1 {
                runs += tail
                paragraph.endStyle = paragraphs[last].endStyle
            } else if index > 0 {
                paragraph.endStyle = style
            }
            paragraph.runs = TextParagraph.joined(runs)
            built.append(paragraph)
        }
        paragraphs.replaceSubrange(first...last, with: built)
    }
}

extension TextParagraph {
    /// The runs before and after a UTF-16 offset into `text`.
    func split(at offset: Int) -> (head: [TextRun], tail: [TextRun]) {
        var head: [TextRun] = [], tail: [TextRun] = []
        var position = 0
        for run in runs {
            let length = run.text.utf16.count
            if position + length <= offset {
                head.append(run)
            } else if position >= offset {
                tail.append(run)
            } else {
                let text = run.text as NSString
                var before = run, after = run
                before.text = text.substring(to: offset - position)
                after.text = text.substring(from: offset - position)
                head.append(before)
                tail.append(after)
            }
            position += length
        }
        return (head, tail)
    }

    /// The formatting of the character at a UTF-16 offset, else of the last character, else of the paragraph's end.
    func characterStyle(at offset: Int) -> CharacterStyle {
        var position = 0
        var last: CharacterStyle?
        for run in runs where !run.text.isEmpty {
            let length = run.text.utf16.count
            if offset < position + length { return run.style }
            last = run.style
            position += length
        }
        return last ?? endStyle
    }

    /// Runs without empty ones, neighbors with the same formatting joined.
    static func joined(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if let previous = result.last, previous.field == nil, run.field == nil, previous.style == run.style {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}
