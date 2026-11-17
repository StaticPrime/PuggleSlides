import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct FindReplaceTests {
    private static let bold = CharacterStyle(bold: true)

    private static func box(_ text: TextBody, id: UUID = UUID()) -> SlideElement {
        SlideElement(id: id, placement: Placement(frame: SlideRect(x: 0, y: 0, width: 100, height: 50)), content: .shape(Shape(text: text)))
    }

    /// One slide with a box, a group holding a box, a table and notes; a second slide with one box.
    private static func deck() -> (Presentation, box: UUID, group: UUID, inner: UUID, table: UUID) {
        var presentation = Presentation.makeDefault()
        let layoutID = presentation.slides[0].layoutID
        let box = UUID(), group = UUID(), inner = UUID(), tableID = UUID()
        var table = Table.make(rows: 2, columns: 2, width: 200)
        table.cells[0][1].text = TextBody("Cat in a cell")
        table.cells[1][0].text = TextBody("cat")
        let grouped = SlideElement(id: group, placement: Placement(frame: SlideRect(x: 0, y: 0, width: 100, height: 100)),
                                   content: .group([Self.box(TextBody("The CAT inside"), id: inner)]))
        var first = Slide(layoutID: layoutID, elements: [
            Self.box(TextBody(paragraphs: [TextParagraph(runs: [TextRun("A cat", style: Self.bold), TextRun(" sat")])]), id: box),
            grouped,
            SlideElement(id: tableID, placement: Placement(frame: SlideRect(x: 0, y: 0, width: 200, height: 60)), content: .table(table)),
        ])
        first.notes = TextBody("Say cat twice: cat")
        let second = Slide(layoutID: layoutID, elements: [Self.box(TextBody("No pets here"))])
        presentation.slides = [first, second]
        return (presentation, box, group, inner, tableID)
    }

    @Test func findsInReadingOrderAndIgnoresCaseByDefault() {
        let (deck, box, group, inner, table) = Self.deck()
        let matches = deck.matches(of: TextSearch("cat"))
        #expect(matches.map(\.place) == [.element([box]), .element([group, inner]), .cell([table], row: 0, column: 1),
                                         .cell([table], row: 1, column: 0), .notes, .notes])
        #expect(matches.map(\.range) == [2..<5, 4..<7, 0..<3, 0..<3, 4..<7, 15..<18])
        #expect(matches.allSatisfy { $0.slideID == deck.slides[0].id })
        #expect(deck.matches(of: TextSearch("cat", matchesCase: true)).count == 4)
        #expect(deck.matches(of: TextSearch("CAT", matchesCase: true)).map(\.place) == [.element([group, inner])])
        #expect(deck.matches(of: TextSearch("")).isEmpty)
    }

    @Test func regularExpressionsAreOptional() {
        let (deck, _, _, _, _) = Self.deck()
        #expect(deck.matches(of: TextSearch("c.t")).isEmpty)
        #expect(deck.matches(of: TextSearch("c.t", usesRegularExpression: true)).count == 6)
        #expect(deck.matches(of: TextSearch("^no", usesRegularExpression: true)).map(\.slideID) == [deck.slides[1].id])
        let broken = TextSearch("(cat", usesRegularExpression: true)
        #expect(!broken.isValid && deck.matches(of: broken).isEmpty)
        // Patterns that can match nothing find only real text.
        #expect(deck.matches(of: TextSearch("z*", usesRegularExpression: true)).isEmpty)
    }

    @Test func replacingKeepsTheFormattingOfWhatItReplaces() {
        var body = TextBody(paragraphs: [TextParagraph(runs: [TextRun("Hello", style: Self.bold), TextRun(" world")])])
        body.replaceCharacters(in: 3..<8, with: "p, w")
        #expect(body.paragraphs[0].runs == [TextRun("Help, w", style: Self.bold), TextRun("rld")])
        // Inserting takes the formatting before it; at the start, the formatting after.
        body.replaceCharacters(in: 7..<7, with: "!")
        #expect(body.plainText == "Help, w!rld" && body.paragraphs[0].runs[0].text == "Help, w!")
        body.replaceCharacters(in: 0..<0, with: ">")
        #expect(body.paragraphs[0].runs[0] == TextRun(">Help, w!", style: Self.bold))
    }

    @Test func replacingAcrossParagraphsJoinsThemAndNewlinesSplitThem() {
        var body = TextBody(paragraphs: [TextParagraph("First line", level: 1), TextParagraph("Second line")])
        body.replaceCharacters(in: 6..<17, with: "and only")
        #expect(body.paragraphs.count == 1 && body.plainText == "First and only line" && body.paragraphs[0].level == 1)
        body.replaceCharacters(in: 5..<15, with: "\n")
        #expect(body.paragraphs.map(\.text) == ["First", "line"] && body.paragraphs.allSatisfy { $0.level == 1 })
        body.replaceCharacters(in: 0..<10, with: "")
        #expect(body.paragraphs.count == 1 && body.plainText == "")
    }

    @Test func replaceAllChangesEveryPlaceAndCountsThem() {
        let fixture = Self.deck()
        var deck = fixture.0
        let box = fixture.box, table = fixture.table
        let replaced = deck.replaceAll(TextSearch("cat"), with: "dog")
        #expect(replaced == 6)
        #expect(deck.matches(of: TextSearch("cat")).isEmpty)
        #expect(deck.slides[0].text(at: .element([box]))?.paragraphs[0].runs == [TextRun("A dog", style: Self.bold), TextRun(" sat")])
        #expect(deck.slides[0].text(at: .cell([table], row: 0, column: 1))?.plainText == "dog in a cell")
        #expect(deck.slides[0].notes.plainText == "Say dog twice: dog")
        #expect(deck.slides[1].elements[0].content == Self.deck().0.slides[1].elements[0].content)
    }

    @Test func replacingOneMatchChecksItIsStillThere() {
        let fixture = Self.deck()
        var deck = fixture.0
        let group = fixture.group, inner = fixture.inner
        let search = TextSearch("cat")
        let match = deck.matches(of: search)[1]
        let first = deck.replace(match, with: "kitten", search: search)
        #expect(first)
        #expect(deck.slides[0].text(at: .element([group, inner]))?.plainText == "The kitten inside")
        // The same match again: the text has changed.
        let again = deck.replace(match, with: "kitten", search: search)
        let elsewhere = deck.replace(TextMatch(slideID: UUID(), place: .notes, range: 0..<3), with: "x", search: search)
        #expect(!again && !elsewhere)
    }

    @Test func fieldsAreNeverSplit() {
        var presentation = Presentation.makeDefault()
        let body = TextBody(paragraphs: [TextParagraph(runs: [TextRun("Slide "), TextRun("12", field: .slideNumber), TextRun(" of 12")])])
        presentation.slides[0].elements = [Self.box(body)]
        #expect(presentation.matches(of: TextSearch("12")).map(\.range) == [12..<14])
        let replaced = presentation.replaceAll(TextSearch("2"), with: "3")
        #expect(replaced == 1)
        #expect(presentation.slides[0].elements[0].content == .shape(Shape(text: TextBody(paragraphs: [
            TextParagraph(runs: [TextRun("Slide "), TextRun("12", field: .slideNumber), TextRun(" of 13")]),
        ]))))
    }

    @Test func commentThreadsLiveOnSlidesAndOlderSlidesDecodeWithout() throws {
        var presentation = Presentation.makeDefault()
        let thread = CommentThread(comments: [Comment(author: "Ada", date: Date(timeIntervalSince1970: 1_000), text: "Bigger?"),
                                              Comment(author: "Grace", date: Date(timeIntervalSince1970: 2_000), text: "Yes")],
                                   position: SlidePoint(x: 10, y: 20))
        presentation.slides[0].comments = [thread]
        #expect(presentation.commentThreads.map { $0.thread } == [thread])
        #expect(presentation.commentLocation(of: thread.id)?.slide == 0)
        // Copies of a slide (Duplicate slide, paste, import) leave its comments behind.
        #expect(presentation.duplicate(presentation.slides[0]).comments.isEmpty)
        let data = try JSONEncoder().encode(presentation.slides[0])
        #expect(try JSONDecoder().decode(Slide.self, from: data) == presentation.slides[0])
        var older = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        older["comments"] = nil
        let decoded = try JSONDecoder().decode(Slide.self, from: try JSONSerialization.data(withJSONObject: older))
        #expect(decoded.comments.isEmpty)
    }
}
