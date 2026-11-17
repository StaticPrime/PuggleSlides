import Foundation

/// The XML namespaces of OpenDocument and the prefixes PuggleSlides writes them with. Reading maps every
/// namespace a file declares to these prefixes, so names compare the same whatever prefixes the file chose.
enum ODFNamespace {
    static let office = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    static let style = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    static let text = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    static let table = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
    static let draw = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
    static let fo = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    static let xlink = "http://www.w3.org/1999/xlink"
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let meta = "urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
    static let number = "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0"
    static let presentation = "urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
    static let svg = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
    static let smil = "urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0"
    static let anim = "urn:oasis:names:tc:opendocument:xmlns:animation:1.0"
    static let manifest = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    static let xml = "http://www.w3.org/XML/1998/namespace"
    static let chart = "urn:oasis:names:tc:opendocument:xmlns:chart:1.0"
    static let config = "urn:oasis:names:tc:opendocument:xmlns:config:1.0"

    /// Namespace URIs by the prefix the reader gives them. Older files use W3C namespaces for SMIL, SVG and FO.
    static let prefixes: [String: String] = [
        office: "office", style: "style", text: "text", table: "table", draw: "draw", fo: "fo", xlink: "xlink", dc: "dc",
        meta: "meta", number: "number", presentation: "presentation", svg: "svg", smil: "smil", anim: "anim", manifest: "manifest",
        xml: "xml", chart: "chart", config: "config",
        "urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0": "dr3d",
        "urn:oasis:names:tc:opendocument:xmlns:form:1.0": "form",
        "urn:oasis:names:tc:opendocument:xmlns:script:1.0": "script",
        "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0": "loext",
        "http://openoffice.org/2009/office": "officeooo",
        "http://openoffice.org/2010/draw": "drawooo",
        "urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0": "psext",
        "http://www.w3.org/2001/SMIL20/": "smil",
        "http://www.w3.org/2001/SMIL20": "smil",
        "http://www.w3.org/2000/svg": "svg",
        "http://www.w3.org/1999/XSL/Format": "fo",
    ]

    /// The declarations on the root of content.xml and styles.xml.
    static let documentRoot = " xmlns:office=\"\(office)\" xmlns:style=\"\(style)\" xmlns:text=\"\(text)\" xmlns:table=\"\(table)\""
        + " xmlns:draw=\"\(draw)\" xmlns:fo=\"\(fo)\" xmlns:xlink=\"\(xlink)\" xmlns:dc=\"\(dc)\" xmlns:meta=\"\(meta)\""
        + " xmlns:number=\"\(number)\" xmlns:presentation=\"\(presentation)\" xmlns:svg=\"\(svg)\" xmlns:smil=\"\(smil)\""
        + " xmlns:anim=\"\(anim)\" office:version=\"1.3\""
}

/// Messages for OpenDocument files that can't be opened or saved.
enum ODPMessages {
    static let notAPresentation = "This file isn't an OpenDocument presentation, or it's damaged."
    static let otherDocument = "This file is an OpenDocument file, but not a presentation."
    static let encrypted = "This presentation is password-protected, which PuggleSlides can't open. "
        + "Save it without a password and try again."
    static let damaged = "This OpenDocument presentation is damaged and can't be opened."
    static let unsupported = "This OpenDocument presentation is stored in a way PuggleSlides can't open."
    static let tooLarge = "This file is too large to open."
    static let tooLargeToSave = "This presentation is too large to save as an OpenDocument file."

    static func readError(for error: Error) -> PresentationIOError {
        if let error = error as? PresentationIOError { return error }
        switch error as? ZipError {
        case .notAZip: return .unreadable(notAPresentation)
        case .unsupported: return .unreadable(unsupported)
        case .tooLarge: return .unreadable(tooLarge)
        case .damaged, nil: return .unreadable(damaged)
        }
    }
}

/// The media types of an OpenDocument presentation and its template, and of the chart objects it embeds.
enum ODPMediaType {
    static let presentation = "application/vnd.oasis.opendocument.presentation"
    static let template = "application/vnd.oasis.opendocument.presentation-template"
    static let chart = "application/vnd.oasis.opendocument.chart"
}

/// Reading attribute values tolerantly. Every result is finite.
enum ODFValue {
    static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func int(_ text: String?) -> Int? {
        guard let value = double(text), abs(value) < 1e15 else { return nil }
        return Int(value.rounded())
    }

    static func bool(_ text: String?) -> Bool? {
        switch text?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1": true
        case "false", "0": false
        default: nil
        }
    }

    /// Splits "12.5pt" into 12.5 and "pt".
    static func split(_ text: String) -> (Double, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var end = trimmed.endIndex
        while end > trimmed.startIndex {
            let previous = trimmed.index(before: end)
            let character = trimmed[previous]
            if character.isLetter || character == "%" { end = previous } else { break }
        }
        guard let value = Double(trimmed[..<end]), value.isFinite else { return nil }
        return (value, String(trimmed[end...]).lowercased())
    }

    /// A length in points. Unitless values are taken as points.
    static func length(_ text: String?) -> Double? {
        guard let text, let (value, unit) = split(text) else { return nil }
        let factor: Double
        switch unit {
        case "pt", "": factor = 1
        case "in", "inch": factor = 72
        case "cm": factor = 72 / 2.54
        case "mm": factor = 72 / 25.4
        case "pc": factor = 12
        case "px": factor = 0.75
        case "em": factor = 12
        default: return nil
        }
        let points = value * factor
        return points.isFinite ? points : nil
    }

    /// "45%" as 0.45.
    static func percent(_ text: String?) -> Double? {
        guard let text, let (value, unit) = split(text), unit == "%" else { return nil }
        return value / 100
    }

    /// "#rrggbb".
    static func color(_ text: String?) -> RGBColor? {
        guard let text else { return nil }
        return RGBColor(hex: text)
    }

    /// An angle in degrees: "90deg", "1.57rad", "100grad", or a bare number in `unitless` degrees.
    static func angle(_ text: String?, unitless: Double = 1) -> Double? {
        guard let text, let (value, unit) = split(text) else { return nil }
        let degrees: Double
        switch unit {
        case "deg": degrees = value
        case "rad": degrees = value * 180 / .pi
        case "grad": degrees = value * 0.9
        case "": degrees = value * unitless
        default: return nil
        }
        return degrees.isFinite ? degrees : nil
    }

    /// A SMIL clock value in seconds: "0.5s", "500ms", "2", "1min", "00:00:02.5". Nil for events and "indefinite".
    static func seconds(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { Double($0) }
            guard parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
            let total = parts.reduce(0.0) { $0 * 60 + ($1 ?? 0) }
            return total.isFinite ? max(0, total) : nil
        }
        guard let (value, unit) = split(trimmed) else { return nil }
        let result: Double
        switch unit {
        case "", "s": result = value
        case "ms": result = value / 1000
        case "min": result = value * 60
        case "h": result = value * 3600
        default: return nil
        }
        return result.isFinite ? result : nil
    }

    /// An ISO 8601 duration ("PT00H00M02.5S") in seconds.
    static func isoDuration(_ text: String?) -> Double? {
        guard let text, let start = text.firstIndex(of: "T") else { return seconds(text) }
        var total = 0.0
        var number = ""
        for character in text[text.index(after: start)...] {
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number) else { return nil }
            switch character {
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: return nil
            }
            number = ""
        }
        return total.isFinite ? total : nil
    }
}

/// Writing attribute values.
enum ODFFormat {
    /// A number with up to `decimals` decimals and no exponent: "12.5", "0", "-3".
    static func number(_ value: Double, decimals: Int = 4) -> String {
        guard value.isFinite else { return "0" }
        let clamped = min(max(value, -1e12), 1e12)
        var scale: Double = 1
        // Keep the scaled value well inside 64 bits.
        for _ in 0..<min(max(decimals, 0), 9) where abs(clamped) * scale * 10 < 9e17 { scale *= 10 }
        let decimals = Int(log10(scale).rounded())
        let scaled = (clamped * scale).rounded()
        if scaled == 0 { return "0" }
        let negative = scaled < 0
        let magnitude = Int64(abs(scaled))
        let whole = magnitude / Int64(scale)
        var fraction = magnitude % Int64(scale)
        var result = negative ? "-\(whole)" : "\(whole)"
        if fraction != 0 {
            var digits = decimals
            while fraction % 10 == 0 {
                fraction /= 10
                digits -= 1
            }
            let text = String(fraction)
            result += "." + String(repeating: "0", count: max(0, digits - text.count)) + text
        }
        return result
    }

    static func pt(_ value: Double) -> String { number(value) + "pt" }

    static func percent(_ fraction: Double) -> String { number(fraction * 100, decimals: 2) + "%" }

    static func color(_ rgb: RGBColor) -> String { "#" + rgb.hex.lowercased() }

    static func seconds(_ value: Double) -> String { number(max(0, value), decimals: 3) + "s" }

    /// A name as an ODF style name (an NCName): characters other than ASCII letters, digits, "-" and "." are
    /// written as "_hex_", as LibreOffice does ("Simple Light" is "Simple_20_Light", "_" is "_5f_").
    static func styleName(_ name: String) -> String {
        var result = ""
        for (index, scalar) in name.unicodeScalars.enumerated() {
            if isPlain(scalar, first: index == 0) {
                result.unicodeScalars.append(scalar)
            } else {
                result += "_" + String(scalar.value, radix: 16) + "_"
            }
        }
        return result.isEmpty ? "_5f_" : result
    }

    private static func isPlain(_ scalar: Unicode.Scalar, first: Bool) -> Bool {
        let value = scalar.value
        let isLetter = (65...90).contains(value) || (97...122).contains(value)
        let isDigit = (48...57).contains(value)
        return isLetter || (!first && (isDigit || value == 45 || value == 46))
    }

    /// Undoes `styleName`'s "_hex_" escapes; an escape of a character that never needs one is left as it is.
    static func decodedStyleName(_ name: String) -> String {
        guard name.contains("_") else { return name }
        var result = ""
        var scalars = Array(name.unicodeScalars)[...]
        while let first = scalars.first {
            if first == "_", let close = scalars.dropFirst().firstIndex(of: "_") {
                let hex = String(String.UnicodeScalarView(scalars[(scalars.startIndex + 1)..<close]))
                if (1...6).contains(hex.count), let value = UInt32(hex, radix: 16), value >= 0x20,
                   let scalar = Unicode.Scalar(value), !isPlain(scalar, first: false) {
                    result.unicodeScalars.append(scalar)
                    scalars = scalars[(close + 1)...]
                    continue
                }
            }
            result.unicodeScalars.append(first)
            scalars = scalars.dropFirst()
        }
        return result
    }
}

/// The natural size of an image, as office apps compute it: pixels at the resolution the file states, or 96 per inch.
/// Picture crops (`fo:clip`) are lengths measured against it.
enum ODPImageSize {
    static func points(of data: Data) -> CGSize? {
        let bytes = [UInt8](data.prefix(256 * 1024))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return png(bytes) }
        if bytes.starts(with: [0xFF, 0xD8]) { return jpeg(bytes) }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]), bytes.count >= 10 {
            return size(pixels: Double(UInt16(bytes[6]) | UInt16(bytes[7]) << 8), Double(UInt16(bytes[8]) | UInt16(bytes[9]) << 8))
        }
        if bytes.starts(with: [0x42, 0x4D]), bytes.count >= 46 {
            let width = Double(abs(Int32(bitPattern: le32(bytes, 18))))
            let height = Double(abs(Int32(bitPattern: le32(bytes, 22))))
            let ppmX = Double(le32(bytes, 38)), ppmY = Double(le32(bytes, 42))
            return size(pixels: width, height, dpiX: ppmX > 0 ? ppmX * 0.0254 : nil, dpiY: ppmY > 0 ? ppmY * 0.0254 : nil)
        }
        return nil
    }

    private static func size(pixels width: Double, _ height: Double, dpiX: Double? = nil, dpiY: Double? = nil) -> CGSize? {
        guard width > 0, height > 0 else { return nil }
        let x = dpiX.flatMap { $0 >= 1 ? $0 : nil } ?? 96, y = dpiY.flatMap { $0 >= 1 ? $0 : nil } ?? 96
        return CGSize(width: width * 72 / x, height: height * 72 / y)
    }

    private static func be32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func png(_ bytes: [UInt8]) -> CGSize? {
        guard bytes.count >= 24 else { return nil }
        let width = Double(be32(bytes, 16)), height = Double(be32(bytes, 20))
        var offset = 8
        var dpiX: Double?, dpiY: Double?
        while offset + 8 <= bytes.count {
            let length = Int(be32(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if type == "pHYs", offset + 17 <= bytes.count, bytes[offset + 16] == 1 {
                dpiX = Double(be32(bytes, offset + 8)) * 0.0254
                dpiY = Double(be32(bytes, offset + 12)) * 0.0254
            }
            if type == "IDAT" || type == "IEND" || length < 0 { break }
            offset += 12 + length
        }
        return size(pixels: width, height, dpiX: dpiX, dpiY: dpiY)
    }

    private static func jpeg(_ bytes: [UInt8]) -> CGSize? {
        var offset = 2
        var dpiX: Double?, dpiY: Double?
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { return nil }
            let marker = bytes[offset + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                offset += 2
                continue
            }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2 else { return nil }
            if marker == 0xE0, offset + 18 <= bytes.count, Array(bytes[(offset + 4)..<(offset + 9)]) == [0x4A, 0x46, 0x49, 0x46, 0x00] {
                let units = bytes[offset + 11]
                let x = Double(Int(bytes[offset + 12]) << 8 | Int(bytes[offset + 13]))
                let y = Double(Int(bytes[offset + 14]) << 8 | Int(bytes[offset + 15]))
                if units == 1 { (dpiX, dpiY) = (x, y) }
                if units == 2 { (dpiX, dpiY) = (x * 2.54, y * 2.54) }
            }
            let isFrame = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isFrame, offset + 9 <= bytes.count {
                let height = Double(Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]))
                let width = Double(Int(bytes[offset + 7]) << 8 | Int(bytes[offset + 8]))
                return size(pixels: width, height, dpiX: dpiX, dpiY: dpiY)
            }
            offset += 2 + length
        }
        return nil
    }
}
