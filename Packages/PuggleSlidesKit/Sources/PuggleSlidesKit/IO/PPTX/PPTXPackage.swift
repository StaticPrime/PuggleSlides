import Foundation

/// Messages for PowerPoint files that can't be opened or saved.
enum PPTXMessages {
    static let notAPresentation = "This file isn't a PowerPoint presentation, or it's damaged."
    static let legacyOrEncrypted = "This file is password-protected or uses the older PowerPoint 97–2003 format (.ppt), "
        + "which PuggleSlides can't open. Save it as a PowerPoint presentation (.pptx) without a password and try again."
    static let damaged = "This PowerPoint file is damaged and can't be opened."
    static let unsupported = "This PowerPoint file is stored in a way PuggleSlides can't open."
    static let tooLarge = "This file is too large to open."
    static let tooLargeToSave = "This presentation is too large to save as a PowerPoint file."

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

/// Parses package parts into trees, refusing nesting deeper than real parts ever go (about 40 levels): a tree
/// thousands of levels deep would exhaust the stack when it's taken apart.
enum PPTXXML {
    static let maxDepth = 256

    static func parse(_ data: Data) throws -> XNode {
        let builder = Builder()
        guard XMLParsing.parse(data, delegate: builder), !builder.isTooDeep, let root = builder.tree.root else { throw MalformedXMLError() }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let tree = XNodeBuilder()
        private var depth = 0
        private(set) var isTooDeep = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            depth += 1
            guard depth <= PPTXXML.maxDepth else {
                isTooDeep = true
                parser.abortParsing()
                return
            }
            tree.start(elementName, attributeDict)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            depth -= 1
            tree.end()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            tree.characters(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            tree.characters(String(decoding: CDATABlock, as: UTF8.self))
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            parser.abortParsing()
        }

        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            parser.abortParsing()
        }
    }
}

/// XML namespaces of the parts PuggleSlides writes.
enum PPTXNamespace {
    static let presentation = "http://schemas.openxmlformats.org/presentationml/2006/main"
    static let drawing = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let contentTypes = "http://schemas.openxmlformats.org/package/2006/content-types"
    static let chart = "http://schemas.openxmlformats.org/drawingml/2006/chart"
    static let table = "http://schemas.openxmlformats.org/drawingml/2006/table"
    /// PowerPoint 2013's extensions, which hold guides.
    static let powerPoint2012 = "http://schemas.microsoft.com/office/powerpoint/2012/main"
    static let spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    /// PowerPoint 2010's extensions, which hold slides' creation ids.
    static let powerPoint2010 = "http://schemas.microsoft.com/office/powerpoint/2010/main"
    /// Modern comments and their authors ([MS-PPTX] 2.16).
    static let powerPoint2018 = "http://schemas.microsoft.com/office/powerpoint/2018/8/main"
    /// Content monikers, which name what a modern comment is about: the slide ([MS-PPTX] 2.12) …
    static let powerPointCommand = "http://schemas.microsoft.com/office/powerpoint/2013/main/command"
    /// … or a drawing element or text on it ([MS-ODRAWXML] 2.29).
    static let drawingCommand = "http://schemas.microsoft.com/office/drawing/2013/main/command"
    /// Office 2016's drawing extensions, which hold shapes' creation ids ([MS-ODRAWXML] 2.25).
    static let drawing2014 = "http://schemas.microsoft.com/office/drawing/2014/main"

    /// The declarations on the root of every PresentationML part.
    static let presentationRoot = " xmlns:a=\"\(drawing)\" xmlns:r=\"\(relationships)\" xmlns:p=\"\(presentation)\""
}

/// Relationship types, transitional flavor (the reader matches strict ones by their last segment).
enum PPTXRelationshipType {
    static let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static let officeDocument = base + "officeDocument"
    static let extendedProperties = base + "extended-properties"
    static let coreProperties = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
    static let slideMaster = base + "slideMaster"
    static let slideLayout = base + "slideLayout"
    static let slide = base + "slide"
    static let notesMaster = base + "notesMaster"
    static let notesSlide = base + "notesSlide"
    static let theme = base + "theme"
    static let image = base + "image"
    static let hyperlink = base + "hyperlink"
    static let presProps = base + "presProps"
    static let viewProps = base + "viewProps"
    static let tableStyles = base + "tableStyles"
    static let chart = base + "chart"
    /// An embedded package, such as a chart's workbook.
    static let package = base + "package"
    static let worksheet = base + "worksheet"
    static let styles = base + "styles"
    static let sharedStrings = base + "sharedStrings"
    /// A slide's modern comments, and the presentation's comment authors ([MS-PPTX] 2.1.5, 2.1.6).
    static let modernComments = "http://schemas.microsoft.com/office/2018/10/relationships/comments"
    static let authors = "http://schemas.microsoft.com/office/2018/10/relationships/authors"
}

/// Content types of the parts PuggleSlides writes.
enum PPTXContentType {
    static let prefix = "application/vnd.openxmlformats-officedocument.presentationml."
    static let presentation = prefix + "presentation.main+xml"
    static let slideMaster = prefix + "slideMaster+xml"
    static let slideLayout = prefix + "slideLayout+xml"
    static let slide = prefix + "slide+xml"
    static let notesMaster = prefix + "notesMaster+xml"
    static let notesSlide = prefix + "notesSlide+xml"
    static let presProps = prefix + "presProps+xml"
    static let viewProps = prefix + "viewProps+xml"
    static let tableStyles = prefix + "tableStyles+xml"
    static let theme = "application/vnd.openxmlformats-officedocument.theme+xml"
    static let coreProperties = "application/vnd.openxmlformats-package.core-properties+xml"
    static let extendedProperties = "application/vnd.openxmlformats-officedocument.extended-properties+xml"
    static let relationships = "application/vnd.openxmlformats-package.relationships+xml"
    static let chart = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
    static let workbook = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    static let modernComments = "application/vnd.ms-powerpoint.comments+xml"
    static let authors = "application/vnd.ms-powerpoint.authors+xml"
    static let xml = "application/xml"

    /// The canonical image type for a file extension, as Office writes it in [Content_Types].xml.
    static func image(forExtension fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "png": "image/png"
        case "jpeg", "jpg", "jpe", "jfif": "image/jpeg"
        case "gif": "image/gif"
        case "bmp", "dib": "image/bmp"
        case "tif", "tiff": "image/tiff"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "emf": "image/x-emf"
        case "wmf": "image/x-wmf"
        case "wdp", "hdp", "jxr": "image/vnd.ms-photo"
        case "ico": "image/x-icon"
        default: nil
        }
    }

    /// The type Office files use for a MIME type PuggleSlides may hold in another spelling.
    static func canonical(_ contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/jpg", "image/pjpeg": "image/jpeg"
        case "image/emf": "image/x-emf"
        case "image/wmf": "image/x-wmf"
        case "image/x-png": "image/png"
        default: contentType
        }
    }
}

/// A relationship from one package part to another, or to something outside the package.
struct PPTXRelationship: Sendable {
    var id: String
    var type: String
    /// The target part's path inside the package, or the raw target of an external relationship.
    var target: String
    var isExternal: Bool

    /// Matches the last segment of the type, so transitional and strict URIs both work.
    func hasType(_ name: String) -> Bool {
        type.hasSuffix("/" + name)
    }
}

/// The relationships of one part, by id and in file order.
struct PPTXRelationships: Sendable {
    private(set) var all: [PPTXRelationship] = []
    private var byID: [String: Int] = [:]

    init(_ relationships: [PPTXRelationship] = []) {
        for relationship in relationships where byID[relationship.id] == nil {
            byID[relationship.id] = all.count
            all.append(relationship)
        }
    }

    subscript(id: String?) -> PPTXRelationship? {
        guard let id, let index = byID[id] else { return nil }
        return all[index]
    }

    /// The first internal relationship of a type ("slideLayout", "theme" …).
    func first(_ type: String) -> PPTXRelationship? {
        all.first { $0.hasType(type) && !$0.isExternal }
    }

    func all(_ type: String) -> [PPTXRelationship] {
        all.filter { $0.hasType(type) }
    }
}

enum PPTXPackage {
    /// "ppt/slides/slide1.xml" → "ppt/slides/_rels/slide1.xml.rels"; "" (the package) → "_rels/.rels".
    static func relationshipsPath(for part: String) -> String {
        guard let slash = part.lastIndex(of: "/") else { return "_rels/\(part).rels" }
        return "\(part[..<slash])/_rels/\(part[part.index(after: slash)...]).rels"
    }

    /// The folder holding a part, without a trailing slash ("ppt/slides").
    static func folder(of part: String) -> String {
        guard let slash = part.lastIndex(of: "/") else { return "" }
        return String(part[..<slash])
    }

    /// Resolves a relationship target against the part it comes from: "../slideLayouts/slideLayout1.xml" from
    /// "ppt/slides/slide1.xml" is "ppt/slideLayouts/slideLayout1.xml"; "/ppt/media/image1.png" is absolute.
    static func resolve(_ target: String, from part: String) -> String {
        var target = target.replacingOccurrences(of: "\\", with: "/")
        // A fragment or query never names a part.
        if let mark = target.firstIndex(where: { $0 == "#" || $0 == "?" }) { target = String(target[..<mark]) }
        var segments: [Substring] = []
        if !target.hasPrefix("/") { segments = folder(of: part).split(separator: "/") }
        for segment in target.split(separator: "/") {
            switch segment {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(segment)
            }
        }
        return segments.joined(separator: "/")
    }

    /// A target for a relationship from `part` to `target`, relative to the source's folder, as Office writes them
    /// ("../slideLayouts/slideLayout1.xml").
    static func relativeTarget(from part: String, to target: String) -> String {
        let source = folder(of: part).split(separator: "/")
        let destination = target.split(separator: "/")
        var common = 0
        while common < source.count, common < destination.count - 1, source[common] == destination[common] { common += 1 }
        let ups = Array(repeating: "..", count: source.count - common)
        return (ups + destination[common...].map(String.init)).joined(separator: "/")
    }

    /// Parses a relationships part. Relationships without an id, type or target are skipped.
    static func relationships(_ data: Data, of part: String) throws -> PPTXRelationships {
        let root = try PPTXXML.parse(data)
        var result: [PPTXRelationship] = []
        for node in root.children where node.name == "Relationship" {
            guard let id = node["Id"], let type = node["Type"], let target = node["Target"] else { continue }
            let external = node["TargetMode"]?.caseInsensitiveCompare("External") == .orderedSame
            result.append(PPTXRelationship(id: id, type: type, target: external ? target : resolve(target, from: part), isExternal: external))
        }
        return PPTXRelationships(result)
    }
}

/// [Content_Types].xml: content types by file extension, and overrides for single parts.
struct PPTXContentTypes {
    private var defaults: [String: String] = [:]
    private var overrides: [String: String] = [:]

    init(_ data: Data?) {
        guard let data, let root = try? PPTXXML.parse(data) else { return }
        for node in root.children {
            switch node.name {
            case "Default":
                if let fileExtension = node["Extension"], let type = node["ContentType"] { defaults[fileExtension.lowercased()] = type }
            case "Override":
                if let name = node["PartName"], let type = node["ContentType"] { overrides[ZipReader.normalized(name).lowercased()] = type }
            default:
                continue
            }
        }
    }

    /// The content type of a part: its override, else its extension's default.
    func type(of path: String) -> String? {
        if let type = overrides[ZipReader.normalized(path).lowercased()] { return type }
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return nil }
        return defaults[path[path.index(after: dot)...].lowercased()]
    }
}

/// Reading attribute values tolerantly. Every result is finite.
enum PPTXValue {
    static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func int(_ text: String?) -> Int? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) { return value }
        guard let value = Double(trimmed), value.isFinite, abs(value) < 1e15 else { return nil }
        return Int(value.rounded())
    }

    /// ST_OnOff and xsd:boolean.
    static func bool(_ text: String?) -> Bool? {
        switch text?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "1", "true", "on", "t": true
        case "0", "false", "off", "f": false
        default: nil
        }
    }

    /// A DrawingML percentage as a fraction: "50000" (thousandths of a percent) or strict's "50%" are 0.5.
    static func fraction(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") { return double(String(trimmed.dropLast())).map { $0 / 100 } }
        return double(trimmed).map { $0 / 100_000 }
    }

    /// A length in EMU: a plain number, or one with a unit as strict files allow ("2.5cm", "12pt").
    static func emu(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = double(trimmed) { return value }
        let units: [(String, Double)] = [("mm", 36_000), ("cm", 360_000), ("in", 914_400), ("pt", 12_700), ("pc", 152_400), ("pi", 152_400)]
        for (unit, factor) in units where trimmed.hasSuffix(unit) {
            return double(String(trimmed.dropLast(unit.count))).map { $0 * factor }
        }
        return nil
    }

    /// A length in points, from EMU.
    static func points(_ text: String?) -> Double? {
        emu(text).map { $0 / EMU.perPoint }
    }

    /// An angle in degrees, from DrawingML's 60,000ths of a degree.
    static func degrees(_ text: String?) -> Double? {
        double(text).map { $0 / 60_000 }
    }

    /// Hundredths of a point (font sizes, spacing) in points.
    static func centipoints(_ text: String?) -> Double? {
        double(text).map { $0 / 100 }
    }

    /// Rounds a finite value into an integer range; non-finite values become `fallback`.
    static func clamped(_ value: Double, _ range: ClosedRange<Int>, fallback: Int = 0) -> Int {
        guard value.isFinite else { return min(max(fallback, range.lowerBound), range.upperBound) }
        let rounded = value.rounded()
        if rounded <= Double(range.lowerBound) { return range.lowerBound }
        if rounded >= Double(range.upperBound) { return range.upperBound }
        return Int(rounded)
    }
}
