import Foundation

/// A part that isn't well-formed XML, or that declares a document type (which OOXML never does).
struct MalformedXMLError: Error {}

/// Runs Foundation's SAX parser with the settings every part uses.
enum XMLParsing {
    /// Parses `data` with `delegate`. Returns false when the XML is malformed, declares a document type,
    /// or the delegate aborted. Namespace processing is off: names arrive with their prefixes ("x:c").
    static func parse(_ data: Data, delegate: some XMLParserDelegate) -> Bool {
        guard !declaresDocumentType(data) else { return false }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse()
    }

    /// "x:c" → "c"; nil when the name has no prefix.
    static func strippingPrefix(_ name: String) -> String? {
        guard let colon = name.utf8.lastIndex(of: UInt8(ascii: ":")) else { return nil }
        return String(name[name.utf8.index(after: colon)...])
    }

    static func localName(_ name: String) -> String {
        strippingPrefix(name) ?? name
    }

    /// True when the prolog holds a `<!DOCTYPE` (or anything else that isn't a comment or processing
    /// instruction) before the root element. Such parts could declare entities that expand without
    /// limit, so they're refused unparsed. NUL bytes are skipped so UTF-16 text is checked too.
    static func declaresDocumentType(_ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            var scanner = PrologScanner(bytes: bytes)
            return scanner.findsDeclaration()
        }
    }

    private struct PrologScanner {
        let bytes: UnsafeRawBufferPointer
        var position = 0

        mutating func next() -> UInt8? {
            while position < bytes.count {
                let byte = bytes[position]
                position += 1
                if byte != 0 { return byte }
            }
            return nil
        }

        mutating func findsDeclaration() -> Bool {
            while let byte = next() {
                guard byte == UInt8(ascii: "<") else { continue }
                guard let marker = next() else { return false }
                switch marker {
                case UInt8(ascii: "?"):
                    guard skip(past: Array("?>".utf8)) else { return true }
                case UInt8(ascii: "!"):
                    guard next() == UInt8(ascii: "-"), next() == UInt8(ascii: "-"), skip(past: Array("-->".utf8)) else { return true }
                default:
                    return false
                }
            }
            return false
        }

        /// Moves past the next occurrence of `terminator`; false when there is none.
        mutating func skip(past terminator: [UInt8]) -> Bool {
            var window: [UInt8] = []
            while let byte = next() {
                window.append(byte)
                if window.count > terminator.count { window.removeFirst() }
                if window == terminator { return true }
            }
            return false
        }
    }
}
