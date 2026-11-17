import Foundation

/// Comment threads in PowerPoint files.
///
/// PowerPoint has two formats, and both are read:
/// - Modern comments (PowerPoint for Microsoft 365; [MS-PPTX] 2.1.5, 2.1.6, 2.12 and 2.16). The presentation relates
///   to an author part (`ppt/authors.xml`, `p188:authorLst`); each slide relates to a comment part (`p188:cmLst`) and
///   names it in its extension list (`p188:commentRel`). A `p188:cm` is a thread: the comment, its replies
///   (`p188:replyLst`) and its status ("resolved"). Content monikers anchor it to the slide (`pc:sldMkLst`), a drawing
///   element (`ac:deMkLst`, by `cNvPr` id and `a16:creationId`) or text in one (`ac:txMkLst`), and `p188:pos` places it
///   in EMU from the top-left corner of what it's anchored to.
/// - Legacy comments (ISO/IEC 29500-1 19.4): `ppt/commentAuthors.xml` and one `p:cmLst` part per slide. Comments sit on
///   the slide at `p:pos`, which PowerPoint reads in eighths of a point ([MS-OI29500] 2.1.1137), and PowerPoint 2013's
///   replies name their parent in `p15:threadingInfo` ([MS-PPTX] 2.4.3.2), whose bias puts `dt` in UTC.
///
/// Only modern comments are written. A file shows one kind ("PowerPoint files can only show either modern comments or
/// classic comments, not both"), and PowerPoint for Microsoft 365 shows every comment twice when a slide relates to
/// both kinds of part.
enum PPTXComments {
    /// `p:ext` URIs: the slide's comment part ([MS-PPTX] 2.2.10), the slide's creation id (2.2.9), a legacy comment's
    /// threading (2.2.10); and the `a:ext` URI of a shape's creation id, as Office writes it.
    static let commentRelationshipExtension = "{6950BFC3-D8DA-4A85-94F7-54DA5524770B}"
    static let slideCreationIDExtension = "{BB962C8B-B14F-4D97-AF65-F5344CB8AC3E}"
    static let threadingExtension = "{C676402C-5697-4E1C-873F-D02D1690AC5C}"
    static let shapeCreationIDExtension = "{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236}"

    /// Positions far off the slide are kept within this many points of it.
    static let positionLimit = 100_000.0

    /// A GUID with its braces stripped, uppercased; nil when it isn't one.
    static func guid(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"), trimmed.count > 2 { trimmed = String(trimmed.dropFirst().dropLast()) }
        return UUID(uuidString: trimmed)?.uuidString
    }

    /// The `a16:creationId` an element's `cNvPr` carries when a comment is anchored to it: its id, as a GUID.
    static func shapeCreationID(_ element: UUID) -> String { "{\(element.uuidString)}" }

    // MARK: Reading

    /// The presentation's comment authors: modern ones by GUID (braces stripped, uppercased), legacy ones by number.
    struct Authors {
        var modern: [String: String] = [:]
        var legacy: [Int: String] = [:]
    }

    static func authors(_ package: PPTXPackageReader, relationships: PPTXRelationships) -> Authors {
        var authors = Authors()
        for relationship in relationships.all {
            let isModern = relationship.type == PPTXRelationshipType.authors
            guard isModern || relationship.hasType("commentAuthors") else { continue }
            guard !relationship.isExternal, let root = try? package.xml(relationship.target),
                  root.name == (isModern ? "authorLst" : "cmAuthorLst") else {
                package.warnings.insert(.comments)
                continue
            }
            for author in root.children(isModern ? "author" : "cmAuthor") {
                let name = author["name"] ?? ""
                if isModern {
                    if let id = author["id"].flatMap(guid), authors.modern[id] == nil { authors.modern[id] = name }
                } else if let id = PPTXValue.int(author["id"]), authors.legacy[id] == nil {
                    authors.legacy[id] = name
                }
            }
        }
        return authors
    }

    /// What a slide's comments are read against: its elements by the ids monikers name, and where each one sits.
    struct SlideContext {
        var shapeIDs: [String: UUID] = [:]
        var creationIDs: [String: UUID] = [:]
        var frames: [UUID: SlideRect] = [:]

        /// Every element, groups' children included; `frame` gives an element's frame after inheritance.
        init(elements: [SlideElement], package: PPTXPackageReader, frame: (SlideElement) -> SlideRect) {
            func visit(_ elements: [SlideElement], depth: Int) {
                guard depth < 64 else { return }
                for element in elements {
                    if let id = package.shapeIDs[element.id].map(Self.shapeKey), shapeIDs[id] == nil { shapeIDs[id] = element.id }
                    if let id = package.creationIDs[element.id], creationIDs[id] == nil { creationIDs[id] = element.id }
                    frames[element.id] = frame(element)
                    if let children = element.children { visit(children, depth: depth + 1) }
                }
            }
            visit(elements, depth: 0)
        }

        static func shapeKey(_ id: String) -> String {
            let trimmed = id.trimmingCharacters(in: .whitespaces)
            return Int(trimmed).map(String.init) ?? trimmed
        }

        /// The element a moniker list names: by creation id, else by `cNvPr` id.
        func element(_ list: XNode) -> UUID? {
            guard let moniker = list.children.first(where: { PPTXComments.drawingMonikers.contains($0.name) }) else { return nil }
            if let id = moniker["creationId"].flatMap(PPTXComments.guid), let element = creationIDs[id] { return element }
            if let id = moniker["id"], let element = shapeIDs[Self.shapeKey(id)] { return element }
            return nil
        }
    }

    /// The monikers of drawing elements ([MS-ODRAWXML] 2.29.3.20); text monikers name their shape with `spMk`.
    static let drawingMonikers: Set<String> = ["spMk", "grpSpMk", "graphicFrameMk", "cxnSpMk", "picMk", "inkMk"]

    /// A slide's threads from the comment parts it relates to, modern ones first. A part that can't be read leaves
    /// a warning. `usedIDs` keeps comment ids unique across the presentation.
    static func threads(relationships: PPTXRelationships, context: SlideContext, authors: Authors, package: PPTXPackageReader,
                        usedIDs: inout Set<UUID>) -> [CommentThread] {
        var modern: [CommentThread] = [], legacy: [CommentThread] = []
        var seen = Set<String>()
        for relationship in relationships.all where relationship.hasType("comments") {
            guard !relationship.isExternal, let root = try? package.xml(relationship.target), root.name == "cmLst" else {
                package.warnings.insert(.comments)
                continue
            }
            guard seen.insert(PPTXPackageReader.key(relationship.target)).inserted else { continue }
            if relationship.type == PPTXRelationshipType.modernComments {
                modern += modernThreads(root, context: context, authors: authors, usedIDs: &usedIDs)
            } else {
                legacy += legacyThreads(root, authors: authors, usedIDs: &usedIDs)
            }
        }
        guard !modern.isEmpty, !legacy.isEmpty else { return modern + legacy }
        // Apps that write both kinds write the same comments twice: legacy threads repeating a modern one are dropped.
        func key(_ thread: CommentThread) -> String { thread.first.map { "\($0.author)\u{0}\($0.text)" } ?? "" }
        let modernKeys = Set(modern.map(key))
        return modern + legacy.filter { !modernKeys.contains(key($0)) }
    }

    private static func modernThreads(_ root: XNode, context: SlideContext, authors: Authors, usedIDs: inout Set<UUID>) -> [CommentThread] {
        var threads: [CommentThread] = []
        for node in root.children("cm") {
            var comments = [modernComment(node, authors: authors, usedIDs: &usedIDs)]
            for reply in node.child("replyLst")?.children("reply") ?? [] {
                comments.append(modernComment(reply, authors: authors, usedIDs: &usedIDs))
            }
            let status = node["status"]?.trimmingCharacters(in: .whitespaces)
            var thread = CommentThread(comments: comments, isResolved: status == "resolved" || status == "closed")
            // The anchor comes first; text anchors stand for their shape.
            var frame: SlideRect?
            if let anchor = node.children.first(where: { ["sldMkLst", "deMkLst", "txMkLst", "unknownAnchor"].contains($0.name) }),
               anchor.name == "deMkLst" || anchor.name == "txMkLst", let element = context.element(anchor) {
                thread.elementID = element
                frame = context.frames[element]
            }
            if let position = node.child("pos"), let x = PPTXValue.points(position["x"]), let y = PPTXValue.points(position["y"]) {
                thread.position = clamped(SlidePoint(x: x + (frame?.x ?? 0), y: y + (frame?.y ?? 0)))
            } else if let frame {
                thread.position = clamped(SlidePoint(x: frame.maxX, y: frame.minY))
            }
            threads.append(thread)
        }
        return threads
    }

    private static func modernComment(_ node: XNode, authors: Authors, usedIDs: inout Set<UUID>) -> Comment {
        let author = node["authorId"].flatMap(guid).flatMap { authors.modern[$0] } ?? ""
        // PowerPoint writes UTC; a date without a zone is read as UTC.
        let date = CommentDates.parse(node["created"], zone: CommentDates.utc) ?? CommentDates.unknown
        return Comment(id: uniqueID(node["id"], usedIDs: &usedIDs), author: author, date: date, text: plainText(node.child("txBody")))
    }

    private static func legacyThreads(_ root: XNode, authors: Authors, usedIDs: inout Set<UUID>) -> [CommentThread] {
        var threads: [CommentThread] = []
        /// Threads by their comments' "author index" keys, which replies name their parent by.
        var threadIndex: [String: Int] = [:]
        for node in root.children("cm") {
            let authorID = PPTXValue.int(node["authorId"])
            var key: String?
            if let authorID, let index = PPTXValue.int(node["idx"]) { key = "\(authorID) \(index)" }
            var bias: Int?
            var parent: String?
            for ext in node.child("extLst")?.children("ext") ?? [] where ext["uri"]?.uppercased() == threadingExtension {
                guard let threading = ext.child("threadingInfo") else { continue }
                bias = PPTXValue.int(threading["timeZoneBias"])
                if let parentNode = threading.child("parentCm"), let author = PPTXValue.int(parentNode["authorId"]),
                   let index = PPTXValue.int(parentNode["idx"]) {
                    parent = "\(author) \(index)"
                }
            }
            // `dt` is the author's wall clock: in UTC once the bias is applied, else in the reader's time zone.
            let date = CommentDates.parse(node["dt"], zone: .current, biasMinutes: bias) ?? CommentDates.unknown
            let comment = Comment(id: uniqueID(nil, usedIDs: &usedIDs), author: authorID.flatMap { authors.legacy[$0] } ?? "", date: date,
                                  text: normalizedLines(node.child("text")?.text ?? ""))
            if let parent, let index = threadIndex[parent] {
                threads[index].comments.append(comment)
                if let key, threadIndex[key] == nil { threadIndex[key] = index }
                continue
            }
            var thread = CommentThread(comments: [comment])
            if let position = node.child("pos"), let x = PPTXValue.double(position["x"]), let y = PPTXValue.double(position["y"]) {
                thread.position = clamped(SlidePoint(x: x / 8, y: y / 8))
            }
            if let key, threadIndex[key] == nil { threadIndex[key] = threads.count }
            threads.append(thread)
        }
        return threads
    }

    /// A comment's id: the file's GUID when it has one not used yet, else a new one.
    private static func uniqueID(_ text: String?, usedIDs: inout Set<UUID>) -> UUID {
        if let id = text.flatMap(guid).flatMap(UUID.init(uuidString:)), usedIDs.insert(id).inserted { return id }
        var id = UUID()
        while !usedIDs.insert(id).inserted { id = UUID() }
        return id
    }

    /// A comment's text as plain text: paragraphs and line breaks become new lines.
    static func plainText(_ body: XNode?) -> String {
        guard let body else { return "" }
        let paragraphs = body.children("p").map { paragraph in
            var line = ""
            for child in paragraph.children {
                switch child.name {
                case "r", "fld": line += child.child("t")?.text ?? ""
                case "br": line += "\n"
                default: break
                }
            }
            return line
        }
        return normalizedLines(paragraphs.joined(separator: "\n"))
    }

    /// Line ends as "\n": PowerPoint's vertical tabs and carriage returns included.
    static func normalizedLines(_ text: String) -> String {
        guard text.contains(where: { $0 == "\r" || $0 == "\r\n" || $0 == "\u{0B}" }) else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0B}", with: "\n")
    }

    static func clamped(_ point: SlidePoint) -> SlidePoint {
        SlidePoint(x: min(max(point.x, -positionLimit), positionLimit), y: min(max(point.y, -positionLimit), positionLimit))
    }

    // MARK: Writing

    /// The presentation's authors, one per name in the order they first comment, with ids derived from their names so
    /// a presentation saves the same way every time.
    struct AuthorList {
        private(set) var names: [String] = []
        private var ids: [String: String] = [:]

        init(_ presentation: Presentation) {
            var used = Set<String>()
            for slide in presentation.slides {
                for thread in slide.comments {
                    for comment in thread.comments where ids[comment.author] == nil {
                        var salt: UInt64 = 0
                        var id = PPTXComments.stableGUID(comment.author, salt: salt)
                        while !used.insert(id).inserted {
                            salt += 1
                            id = PPTXComments.stableGUID(comment.author, salt: salt)
                        }
                        ids[comment.author] = id
                        names.append(comment.author)
                    }
                }
            }
        }

        var isEmpty: Bool { names.isEmpty }

        func id(_ name: String) -> String { ids[name] ?? "{00000000-0000-0000-0000-000000000000}" }
    }

    /// `ppt/authors.xml`: each author as PowerPoint writes one for an account it can't name, the user id being the
    /// name and the provider "None". PowerPoint repairs files whose authors lack them.
    static func authorsPart(_ authors: AuthorList) -> Data {
        var xml = XMLWriter(reservingCapacity: 256 + authors.names.count * 160)
        xml.raw("<p188:authorLst xmlns:a=\"\(PPTXNamespace.drawing)\" xmlns:r=\"\(PPTXNamespace.relationships)\"")
        xml.raw(" xmlns:p188=\"\(PPTXNamespace.powerPoint2018)\">")
        for name in authors.names {
            xml.raw("<p188:author id=\"\(authors.id(name))\"")
            xml.attribute("name", name)
            xml.attribute("initials", initials(name))
            xml.attribute("userId", name)
            xml.raw(" providerId=\"None\"/>")
        }
        xml.raw("</p188:authorLst>")
        return xml.data
    }

    /// Initials from a name: the first letters of its first and last words ("Ada Lovelace" is "AL").
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// Where a slide's comments point: the slide's id and creation id, which its moniker names, the shapes written on
    /// it, and each anchored element's frame, which positions are measured from.
    struct SlideTarget {
        var slideID: Int
        var creationID: UInt32
        var shapes: [UUID: PPTXWrittenShape]
        var frames: [UUID: SlideRect]
    }

    /// A slide's comment part. Threads about an element that wasn't written are about the slide.
    static func commentsPart(_ threads: [CommentThread], target: SlideTarget, authors: AuthorList, usedIDs: inout Set<UUID>) -> Data {
        var xml = XMLWriter(reservingCapacity: 1024 + threads.count * 1024)
        xml.raw("<p188:cmLst xmlns:a=\"\(PPTXNamespace.drawing)\" xmlns:r=\"\(PPTXNamespace.relationships)\"")
        xml.raw(" xmlns:p188=\"\(PPTXNamespace.powerPoint2018)\" xmlns:pc=\"\(PPTXNamespace.powerPointCommand)\"")
        xml.raw(" xmlns:ac=\"\(PPTXNamespace.drawingCommand)\">")
        let slideMonikers = "<pc:docMk/><pc:sldMk cId=\"\(target.creationID)\" sldId=\"\(target.slideID)\"/>"
        for thread in threads {
            guard let first = thread.comments.first else { continue }
            xml.raw("<p188:cm")
            attributes(first, authors: authors, status: thread.isResolved ? "resolved" : nil, usedIDs: &usedIDs, into: &xml)
            xml.raw(">")
            var origin = SlidePoint(x: 0, y: 0)
            if let elementID = thread.elementID, let shape = target.shapes[elementID] {
                xml.raw("<ac:deMkLst>\(slideMonikers)<ac:\(shape.kind.moniker) id=\"\(shape.id)\" creationId=\"\(shapeCreationID(elementID))\"/>")
                xml.raw("</ac:deMkLst>")
                if let frame = target.frames[elementID] { origin = frame.origin }
            } else {
                xml.raw("<pc:sldMkLst>\(slideMonikers)</pc:sldMkLst>")
            }
            let x = PPTXPartWriter.coordinate(thread.position.x - origin.x), y = PPTXPartWriter.coordinate(thread.position.y - origin.y)
            xml.raw("<p188:pos x=\"\(x)\" y=\"\(y)\"/>")
            if thread.comments.count > 1 {
                xml.raw("<p188:replyLst>")
                for reply in thread.comments.dropFirst() {
                    xml.raw("<p188:reply")
                    attributes(reply, authors: authors, status: nil, usedIDs: &usedIDs, into: &xml)
                    xml.raw(">")
                    textBody(reply.text, into: &xml)
                    xml.raw("</p188:reply>")
                }
                xml.raw("</p188:replyLst>")
            }
            textBody(first.text, into: &xml)
            xml.raw("</p188:cm>")
        }
        xml.raw("</p188:cmLst>")
        return xml.data
    }

    /// `id`, `authorId`, `status` and `created`. Ids already used in the presentation are replaced.
    private static func attributes(_ comment: Comment, authors: AuthorList, status: String?, usedIDs: inout Set<UUID>,
                                   into xml: inout XMLWriter) {
        var id = comment.id
        var salt: UInt64 = 0
        while !usedIDs.insert(id).inserted {
            salt += 1
            id = UUID(uuidString: String(stableGUID(comment.id.uuidString, salt: salt).dropFirst().dropLast())) ?? UUID()
        }
        xml.raw(" id=\"{\(id.uuidString)}\" authorId=\"\(authors.id(comment.author))\"")
        if let status { xml.raw(" status=\"\(status)\"") }
        xml.raw(" created=\"\(CommentDates.utcString(comment.date))\"")
    }

    /// Plain text as DrawingML paragraphs, one per line.
    private static func textBody(_ text: String, into xml: inout XMLWriter) {
        xml.raw("<p188:txBody><a:bodyPr/><a:lstStyle/>")
        for line in normalizedLines(text).components(separatedBy: "\n") {
            guard !line.isEmpty else {
                xml.raw("<a:p/>")
                continue
            }
            xml.raw("<a:p><a:r><a:t>")
            xml.text(line)
            xml.raw("</a:t></a:r></a:p>")
        }
        xml.raw("</p188:txBody>")
    }

    /// The `p14:creationId` of a slide with comments, which its comments' slide moniker names: from the slide's id.
    static func slideCreationID(_ slide: UUID) -> UInt32 {
        let bytes = slide.uuid
        let value = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
        return max(value, 1)
    }

    /// A GUID ("{…}") derived from text, the same every time.
    static func stableGUID(_ text: String, salt: UInt64) -> String {
        var high: UInt64 = 0xCBF2_9CE4_8422_2325 ^ salt, low: UInt64 = 0x8422_2325_CBF2_9CE4 &+ salt
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for byte in text.utf8 {
            high = (high ^ UInt64(byte)) &* prime
            low = (low &+ UInt64(byte)) &* prime ^ (low >> 29)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * index))
            bytes[8 + index] = UInt8(truncatingIfNeeded: low >> (56 - 8 * index))
        }
        // Version 8 (custom), RFC 9562 variant.
        bytes[6] = bytes[6] & 0x0F | 0x80
        bytes[8] = bytes[8] & 0x3F | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return "{\(uuid.uuidString)}"
    }

    /// An element anywhere on a slide, groups' children included.
    static func element(_ id: UUID, in elements: [SlideElement], depth: Int = 0) -> SlideElement? {
        guard depth < 64 else { return nil }
        for element in elements {
            if element.id == id { return element }
            if let children = element.children, let found = Self.element(id, in: children, depth: depth + 1) { return found }
        }
        return nil
    }
}

/// Comment dates as XML Schema's `dateTime` ("2026-11-17T09:30:00Z"), which both formats use.
enum CommentDates {
    static let utc = TimeZone(secondsFromGMT: 0)!
    /// The date a comment gets when its file gives none.
    static let unknown = Date(timeIntervalSince1970: 0)
    /// Dates written are kept between 1601 and 9999, where every app's calendar agrees.
    static let earliest = -11_644_473_600.0
    static let latest = 253_402_300_799.0

    /// A `dateTime`. One without a zone is the wall clock in `zone`, unless `biasMinutes` is given: then it's
    /// UTC less the bias (legacy PowerPoint's "UTC = local time + bias"). Nil when the text isn't a date.
    static func parse(_ text: String?, zone: TimeZone, biasMinutes: Int? = nil) -> Date? {
        guard let text else { return nil }
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard characters.count <= 64 else { return nil }
        var index = 0
        func digits(_ count: Int) -> Int? {
            guard index + count <= characters.count else { return nil }
            var value = 0
            for offset in 0..<count {
                let character = characters[index + offset]
                guard character >= 0x30, character <= 0x39 else { return nil }
                value = value * 10 + Int(character - 0x30)
            }
            index += count
            return value
        }
        func skip(_ character: UInt8) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }
        guard let year = digits(4), skip(0x2D), let month = digits(2), skip(0x2D), let day = digits(2) else { return nil }
        var hour = 0, minute = 0, second = 0, fraction = 0.0
        if skip(0x54) || skip(0x20) {
            guard let parsedHour = digits(2), skip(0x3A), let parsedMinute = digits(2) else { return nil }
            hour = parsedHour
            minute = parsedMinute
            if skip(0x3A) {
                guard let parsedSecond = digits(2) else { return nil }
                second = parsedSecond
                if skip(0x2E) {
                    var scale = 0.1, any = false
                    while index < characters.count, characters[index] >= 0x30, characters[index] <= 0x39 {
                        fraction += Double(characters[index] - 0x30) * scale
                        scale /= 10
                        index += 1
                        any = true
                    }
                    guard any else { return nil }
                }
            }
        }
        var offset: Int?
        if skip(0x5A) {
            offset = 0
        } else if index < characters.count, characters[index] == 0x2B || characters[index] == 0x2D {
            let sign = characters[index] == 0x2D ? -1 : 1
            index += 1
            guard let hours = digits(2), skip(0x3A), let minutes = digits(2), hours <= 14, minutes <= 59 else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        }
        guard index == characters.count, year >= 1, (1...12).contains(month), (1...31).contains(day), hour <= 24, minute <= 59,
              second <= 60, hour < 24 || (minute == 0 && second == 0 && fraction == 0) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        let bias = biasMinutes.flatMap { abs($0) <= 24 * 60 ? $0 : nil }
        calendar.timeZone = offset.flatMap { TimeZone(secondsFromGMT: $0) } ?? (bias != nil ? utc : zone)
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard var date = calendar.date(from: components) else { return nil }
        date.addTimeInterval(fraction)
        if offset == nil, let bias { date.addTimeInterval(Double(bias) * 60) }
        return date
    }

    /// UTC to the second: "2026-11-17T09:30:00Z".
    static func utcString(_ date: Date) -> String {
        string(date, zone: utc) + "Z"
    }

    /// The wall clock in `zone` to the second, without a zone: "2026-11-17T10:30:00".
    static func string(_ date: Date, zone: TimeZone) -> String {
        let seconds = min(max(date.timeIntervalSince1970.isFinite ? date.timeIntervalSince1970.rounded(.down) : 0, earliest), latest)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        func padded(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(padded(parts.year, 4))-\(padded(parts.month, 2))-\(padded(parts.day, 2))T"
            + "\(padded(parts.hour, 2)):\(padded(parts.minute, 2)):\(padded(parts.second, 2))"
    }
}
