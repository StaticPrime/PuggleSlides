import Foundation

/// Builds an XML document as UTF-8 bytes. Markup passed to `raw` is trusted; text and attribute values
/// are escaped, and characters XML 1.0 can't hold (most control characters, U+FFFE, U+FFFF) are dropped.
struct XMLWriter {
    private(set) var bytes: [UInt8] = []

    init(reservingCapacity capacity: Int = 1024) {
        bytes.reserveCapacity(capacity)
        raw("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
    }

    /// A piece of a document, without the XML declaration.
    init(fragmentCapacity capacity: Int) {
        bytes.reserveCapacity(capacity)
    }

    var data: Data { Data(bytes) }

    var isEmpty: Bool { bytes.isEmpty }

    mutating func append(_ fragment: XMLWriter) {
        bytes.append(contentsOf: fragment.bytes)
    }

    mutating func removeAll() {
        bytes.removeAll(keepingCapacity: true)
    }

    mutating func raw(_ markup: String) {
        bytes.append(contentsOf: markup.utf8)
    }

    /// Element content.
    mutating func text(_ value: String) {
        append(value, inAttribute: false)
    }

    /// ` name="value"`.
    mutating func attribute(_ name: String, _ value: String) {
        bytes.append(0x20)
        raw(name)
        bytes.append(contentsOf: [0x3D, 0x22])
        append(value, inAttribute: true)
        bytes.append(0x22)
    }

    mutating func attribute(_ name: String, _ value: Int) {
        raw(" \(name)=\"\(value)\"")
    }

    private mutating func append(_ value: String, inAttribute: Bool) {
        var value = value
        value.withUTF8 { source in
            let count = source.count
            var runStart = 0
            var index = 0
            while index < count {
                let byte = source[index]
                let replacement: StaticString?
                var length = 1
                switch byte {
                case 0x26: replacement = "&amp;"
                case 0x3C: replacement = "&lt;"
                case 0x3E: replacement = "&gt;"
                case 0x22 where inAttribute: replacement = "&quot;"
                // A literal carriage return would become a line feed when parsed; tabs and line feeds
                // in attributes would become spaces.
                case 0x0D: replacement = "&#13;"
                case 0x0A where inAttribute: replacement = "&#10;"
                case 0x09 where inAttribute: replacement = "&#9;"
                case 0x09, 0x0A:
                    index += 1
                    continue
                case 0x00...0x1F:
                    replacement = ""
                case 0xEF where index + 2 < count && source[index + 1] == 0xBF && source[index + 2] >= 0xBE:
                    // U+FFFE and U+FFFF.
                    replacement = ""
                    length = 3
                default:
                    index += 1
                    continue
                }
                bytes.append(contentsOf: UnsafeBufferPointer(rebasing: source[runStart..<index]))
                if let replacement, replacement.utf8CodeUnitCount > 0 {
                    bytes.append(contentsOf: UnsafeBufferPointer(start: replacement.utf8Start, count: replacement.utf8CodeUnitCount))
                }
                index += length
                runStart = index
            }
            bytes.append(contentsOf: UnsafeBufferPointer(rebasing: source[runStart..<count]))
        }
    }
}
