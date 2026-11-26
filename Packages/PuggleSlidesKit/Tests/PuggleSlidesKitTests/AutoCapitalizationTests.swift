import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct AutoCapitalizationTests {
    /// The text as it would be with the word before `|` capitalized (the bar marks the end of the word just typed),
    /// or nil when nothing would change.
    private static func capitalized(_ marked: String) -> String? {
        let parts = marked.components(separatedBy: "|")
        let text = parts.joined() as NSString
        guard let change = AutoCapitalization.change(in: text, wordEndingAt: (parts[0] as NSString).length) else { return nil }
        return text.replacingCharacters(in: change.range, with: change.capital)
    }

    @Test func capitalizesTheFirstWordOfTheText() {
        #expect(Self.capitalized("hello| ") == "Hello ")
        #expect(Self.capitalized("hello,| ") == "Hello, ")
        #expect(Self.capitalized("“hello|”") == "“Hello”")
        #expect(Self.capitalized("  (well|") == "  (Well")
    }

    @Test func capitalizesAfterTheEndOfASentence() {
        #expect(Self.capitalized("Dogs nap. they|") == "Dogs nap. They")
        #expect(Self.capitalized("Really? yes|") == "Really? Yes")
        #expect(Self.capitalized("Wow!  so|") == "Wow!  So")
        #expect(Self.capitalized("He said “stop.” then|") == "He said “stop.” Then")
        #expect(Self.capitalized("(It rained.) we|") == "(It rained.) We")
    }

    @Test func capitalizesAtTheStartOfEachLine() {
        #expect(Self.capitalized("First line\nsecond|") == "First line\nSecond")
        #expect(Self.capitalized("Item one\u{2028}item|") == "Item one\u{2028}Item")
        #expect(Self.capitalized("Bullet\n\tindented|") == "Bullet\n\tIndented")
    }

    @Test func leavesWordsInsideASentence() {
        #expect(Self.capitalized("Dogs nap|") == nil)
        #expect(Self.capitalized("Dogs, cats|") == nil)
        #expect(Self.capitalized("Wait… what|") == nil)
        #expect(Self.capitalized("Hello there|") == nil)
    }

    @Test func leavesWordsAfterAbbreviations() {
        #expect(Self.capitalized("Ask Dr. smith|") == nil)
        #expect(Self.capitalized("Fruit, e.g. apples|") == nil)
        #expect(Self.capitalized("At 9 a.m. sharp|") == nil)
        #expect(Self.capitalized("John F. kennedy|") == nil)
        #expect(Self.capitalized("Cats vs. dogs|") == nil)
        #expect(Self.capitalized("Apples, pears etc. are|") == nil)
    }

    @Test func leavesWordsThatAreNotPlainWords() {
        #expect(Self.capitalized("iPhone|") == nil)
        #expect(Self.capitalized("macOS|") == nil)
        #expect(Self.capitalized("www.example.com|") == nil)
        #expect(Self.capitalized("name@example.com|") == nil)
        #expect(Self.capitalized("3rd|") == nil)
        #expect(Self.capitalized("Hello|") == nil)
        #expect(Self.capitalized("--|") == nil)
        #expect(Self.capitalized("“|") == nil)
    }

    @Test func keepsApostrophesHyphensAndAccents() {
        #expect(Self.capitalized("don't|") == "Don't")
        #expect(Self.capitalized("it’s|") == "It’s")
        #expect(Self.capitalized("well-known|") == "Well-known")
        #expect(Self.capitalized("été|") == "Été")
        #expect(Self.capitalized("e\u{301}te\u{301}|") == "E\u{301}te\u{301}")
        #expect(Self.capitalized("ßig|") == nil)
        #expect(Self.capitalized("don''t|") == nil)
    }

    @Test func reportsTheLetterToChange() {
        let text = "Done. next step" as NSString
        #expect(AutoCapitalization.change(in: text, wordEndingAt: 10) == AutoCapitalization.Change(range: NSRange(location: 6, length: 1), capital: "N"))
        #expect(AutoCapitalization.change(in: text, wordEndingAt: 0) == nil)
        #expect(AutoCapitalization.change(in: text, wordEndingAt: 99) == nil)
    }
}
