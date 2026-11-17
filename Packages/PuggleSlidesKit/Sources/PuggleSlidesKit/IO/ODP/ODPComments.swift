import Foundation

/// Comment threads in OpenDocument presentations, kept as LibreOffice Impress keeps comments: each an annotation on the
/// page (`officeooo:annotation`, after the page's notes) placed by `svg:x` and `svg:y` from the page's top-left corner,
/// holding `dc:creator`, `dc:date` (the author's wall clock, without a zone), `meta:creator-initials` and the text as
/// paragraphs (LibreOffice's `SdXMLExport::exportAnnotations`). ODF 1.3 has no place for comments on a page, so
/// LibreOffice writes them only to extended ODF, in its own namespace; it reads `office:annotation` there too, and
/// annotations in text belong to the object holding the text.
///
/// Impress has no threads (a reply rewrites the comment, quoting it) and no resolved comments. So each comment and reply
/// is an annotation of its own, in order, at the thread's position, and threads are marked as LibreOffice Writer marks
/// its comments: the first names the thread (`office:name`) and is `loext:resolved` when resolved, and replies name it
/// (`loext:parent-name`). `loext:date-utc` holds the moment each was written, as LibreOffice now writes beside
/// `dc:date`. A thread about an object names the object's `xml:id` in `psext:anchor`, PuggleSlides' own extension.
/// LibreOffice shows every comment and reply where its thread is, and drops these marks when it saves.
enum ODPComments {
    static let officeExtension = "http://openoffice.org/2009/office"
    static let libreOfficeExtension = "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0"
    static let puggleExtension = "urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0"

    // MARK: Writing

    /// A slide's threads as annotations; `anchors` are the ids written on the elements threads are about. Wall clock
    /// dates are written in `zone`.
    static func write(_ threads: [CommentThread], slideNumber: Int, anchors: [UUID: String], zone: TimeZone, into xml: inout XMLWriter) {
        for (threadIndex, thread) in threads.enumerated() {
            let name = "__Annotation__\(slideNumber)_\(threadIndex + 1)"
            for (commentIndex, comment) in thread.comments.enumerated() {
                xml.raw("<officeooo:annotation xmlns:officeooo=\"\(officeExtension)\" xmlns:loext=\"\(libreOfficeExtension)\"")
                let anchor = commentIndex == 0 ? thread.elementID.flatMap { anchors[$0] } : nil
                if anchor != nil { xml.raw(" xmlns:psext=\"\(puggleExtension)\"") }
                xml.raw(" svg:x=\"\(ODFFormat.pt(thread.position.x))\" svg:y=\"\(ODFFormat.pt(thread.position.y))\"")
                if commentIndex == 0 {
                    xml.attribute("office:name", name)
                    if thread.isResolved { xml.raw(" loext:resolved=\"true\"") }
                    if let anchor { xml.attribute("psext:anchor", anchor) }
                } else {
                    xml.attribute("loext:parent-name", name)
                }
                xml.raw(" loext:date-utc=\"\(CommentDates.utcString(comment.date))\">")
                if !comment.author.isEmpty {
                    xml.raw("<dc:creator>")
                    xml.text(comment.author)
                    xml.raw("</dc:creator>")
                }
                xml.raw("<dc:date>\(CommentDates.string(comment.date, zone: zone))</dc:date>")
                let initials = PPTXComments.initials(comment.author)
                if !initials.isEmpty {
                    xml.raw("<meta:creator-initials>")
                    xml.text(initials)
                    xml.raw("</meta:creator-initials>")
                }
                for line in PPTXComments.normalizedLines(comment.text).components(separatedBy: "\n") {
                    if line.isEmpty {
                        xml.raw("<text:p/>")
                    } else {
                        xml.raw("<text:p>")
                        ODPChartWriter.paragraphText(line, into: &xml)
                        xml.raw("</text:p>")
                    }
                }
                xml.raw("</officeooo:annotation>")
            }
        }
    }

    // MARK: Reading

    /// One annotation: its comment, where it is, and how it joins a thread.
    struct Annotation {
        var comment: Comment
        var position: SlidePoint?
        var name: String?
        var parentName: String?
        var isResolved = false
        /// The `xml:id` of the element its thread is about.
        var anchor: String?
        /// The element whose text holds it.
        var element: UUID?
    }

    static func annotation(_ node: ODFNode, element: UUID?) -> Annotation {
        var author = "", wallClock: String?
        var paragraphs: [String] = []
        func collect(_ node: ODFNode, depth: Int) {
            guard depth < 8 else { return }
            for child in node.elements {
                switch child.name {
                case "dc:creator" where depth == 0: author = child.textContent
                case "dc:date" where depth == 0: wallClock = child.textContent
                case "text:p", "text:h": paragraphs.append(ODPChartReader.paragraphText(child))
                case "text:list", "text:list-item", "text:list-header": collect(child, depth: depth + 1)
                default: break
                }
            }
        }
        collect(node, depth: 0)
        // The moment it was written, else the author's wall clock, read in the reader's time zone.
        let date = CommentDates.parse(node["loext:date-utc"], zone: CommentDates.utc)
            ?? CommentDates.parse(wallClock, zone: .current) ?? CommentDates.unknown
        var result = Annotation(comment: Comment(author: author, date: date, text: paragraphs.joined(separator: "\n")), element: element)
        let x = ODFValue.length(node["svg:x"]), y = ODFValue.length(node["svg:y"])
        if x != nil || y != nil { result.position = PPTXComments.clamped(SlidePoint(x: x ?? 0, y: y ?? 0)) }
        result.name = node["office:name"]
        result.parentName = node["loext:parent-name"]
        result.isResolved = node["loext:resolved"]?.trimmingCharacters(in: .whitespaces) == "true"
        result.anchor = node["psext:anchor"]
        return result
    }

    /// Threads from a page's annotations, in order: replies join the thread they name. `elementIDs` are the page's
    /// elements by `xml:id` and `draw:id`; `frame` places a comment about an element that gives no position at the
    /// element's top-right corner.
    static func threads(_ annotations: [Annotation], elementIDs: [String: UUID], frame: (UUID) -> SlideRect?) -> [CommentThread] {
        var threads: [CommentThread] = []
        var named: [String: Int] = [:]
        for annotation in annotations {
            if let parent = annotation.parentName, let index = named[parent] {
                threads[index].comments.append(annotation.comment)
                continue
            }
            var thread = CommentThread(comments: [annotation.comment], isResolved: annotation.isResolved)
            thread.elementID = annotation.element ?? annotation.anchor.flatMap { elementIDs[$0] }
            if let position = annotation.position {
                thread.position = position
            } else if let element = thread.elementID, let frame = frame(element) {
                thread.position = PPTXComments.clamped(SlidePoint(x: frame.maxX, y: frame.minY))
            }
            if let name = annotation.name, named[name] == nil { named[name] = threads.count }
            threads.append(thread)
        }
        return threads
    }
}
