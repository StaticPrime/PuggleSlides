import Foundation

/// Settings ▸ Automatically capitalize words: once a word that starts a sentence has been typed, it gets a capital
/// letter. A sentence starts at the beginning of the text or of a line, and after a full stop, a question mark or an
/// exclamation mark. Words that already have a capital (iPhone), a digit, or punctuation inside other than an
/// apostrophe or a hyphen (web and email addresses, e.g.) stay as they are, and so does a word after an abbreviation
/// such as "e.g.", "Dr." or an initial.
public enum AutoCapitalization {
    /// A letter to capitalize: where it is in the text, in UTF-16 units, and the capital to put there.
    public struct Change: Equatable {
        public var range: NSRange
        public var capital: String

        public init(range: NSRange, capital: String) {
            self.range = range
            self.capital = capital
        }
    }

    /// What to capitalize now that the word ending at `end` (a UTF-16 offset in `text`: where the space or line break
    /// typed after the word begins) has been typed, or nil when it isn't the first word of a sentence or should keep
    /// its letters as typed.
    public static func change(in text: NSString, wordEndingAt end: Int) -> Change? {
        guard end > 0, end <= text.length else { return nil }
        var start = end
        while start > 0, !isSpace(text.character(at: start - 1)) { start -= 1 }
        // Quotes and brackets around the word, and the punctuation after it, aren't part of it.
        var first = start
        while first < end, openers.contains(text.character(at: first)) { first += 1 }
        var last = end
        while last > first, closers.contains(text.character(at: last - 1)) { last -= 1 }
        guard first < last, isLowercaseWord(text.substring(with: NSRange(location: first, length: last - first))),
              startsSentence(text, before: start) else { return nil }
        let letter = text.rangeOfComposedCharacterSequence(at: first)
        let original = text.substring(with: letter)
        let capital = original.capitalized
        // A letter whose capital is longer (ß) is left alone, so nothing after it moves.
        guard capital != original, (capital as NSString).length == letter.length else { return nil }
        return Change(range: letter, capital: capital)
    }

    // MARK: Words and sentences

    private static let openers = characters("\"'“‘„‚([{«¿¡")
    private static let closers = characters(".,;:!?…\"'”’)]}»")
    /// Closing quotes and brackets that can follow the end of a sentence.
    private static let sentenceClosers = characters("\"'”’)]}»")
    /// Apostrophes and hyphens, which can join the letters of a word.
    private static let joiners = Set("'’-‐".unicodeScalars)
    /// Words that end in a full stop without ending a sentence. Initials, and abbreviations with stops inside
    /// (e.g., i.e., a.m.), count too.
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr", "vs", "etc", "cf"]

    private static func characters(_ string: String) -> Set<unichar> { Set(string.utf16) }

    private static func isSpace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }

    /// Letters, all of them small, perhaps joined by apostrophes or hyphens.
    private static func isLowercaseWord(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else { return false }
        var afterJoiner = false
        for scalar in word.unicodeScalars {
            if CharacterSet.uppercaseLetters.contains(scalar) { return false }
            if joiners.contains(scalar) {
                if afterJoiner { return false }
                afterJoiner = true
            } else if CharacterSet.letters.contains(scalar) {
                afterJoiner = false
            } else {
                return false
            }
        }
        return !afterJoiner
    }

    /// Whether a word starting at `start` begins a sentence, from what's before it.
    private static func startsSentence(_ text: NSString, before start: Int) -> Bool {
        var index = start - 1
        while index >= 0, isSpace(text.character(at: index)), !isLineBreak(text.character(at: index)) { index -= 1 }
        if index < 0 || isLineBreak(text.character(at: index)) { return true }
        while index >= 0, sentenceClosers.contains(text.character(at: index)) { index -= 1 }
        guard index >= 0 else { return false }
        let mark = text.character(at: index)
        if mark == unichar(UInt8(ascii: "!")) || mark == unichar(UInt8(ascii: "?")) { return true }
        guard mark == unichar(UInt8(ascii: ".")) else { return false }
        var wordStart = index
        while wordStart > 0, !isSpace(text.character(at: wordStart - 1)) { wordStart -= 1 }
        return !isAbbreviation(text.substring(with: NSRange(location: wordStart, length: index - wordStart)))
    }

    /// `word` is what comes before a full stop, back to the space before it.
    private static func isAbbreviation(_ word: String) -> Bool {
        let letters = String(word.drop { openers.contains(String($0).utf16.first ?? 0) }).lowercased()
        if letters.isEmpty || letters.contains(".") { return true }
        if letters.count == 1, letters.first?.isLetter == true { return true }
        return abbreviations.contains(letters)
    }
}
