import Foundation
import Testing
@testable import PuggleSlidesKit

/// Comment threads in PowerPoint files: written as PowerPoint for Microsoft 365's modern comments, read from modern
/// and legacy ones.
struct PPTXCommentTests {
    typealias Package = PPTXTestPackage

    static let modernComments = "http://schemas.microsoft.com/office/2018/10/relationships/comments"
    static let authors = "http://schemas.microsoft.com/office/2018/10/relationships/authors"
    static let modernNamespaces = "xmlns:a=\"{A}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p188=\"http://schemas.microsoft.com/office/powerpoint/2018/8/main\" "
        + "xmlns:pc=\"http://schemas.microsoft.com/office/powerpoint/2013/main/command\" "
        + "xmlns:ac=\"http://schemas.microsoft.com/office/drawing/2013/main/command\""

    /// Every kind of object on one slide, and threads about each, about a shape in a group, about the slide and about an
    /// object that's gone.
    struct Deck {
        var presentation: Presentation
        var box, line, photo, table, chart, group, grouped: SlideElement

        var slide: Slide { presentation.slides[0] }
    }

    static func deck() -> Deck {
        var presentation = Presentation.makeDefault()
        let image = presentation.addMedia(PPTXSamples.photo, contentType: "image/png")
        var slide = presentation.makeSlide(layoutID: presentation.themes[0].layout(kind: .blank)!.id)
        let box = PPTXSamples.shape("Box", SlideRect(x: 100, y: 80, width: 200, height: 100),
                                    Shape(fill: .solid(ColorRef(theme: .accent1)), text: TextBody("Box")))
        let line = PPTXSamples.shape("Line", SlideRect(x: 400, y: 60, width: 120, height: 0),
                                     Shape(geometry: .line, outline: Outline(fill: .solid(ColorRef(theme: .dark1)), width: 2), isConnector: true))
        let photo = SlideElement(name: "Photo", placement: Placement(frame: SlideRect(x: 560, y: 200, width: 120, height: 90)),
                                 content: .picture(Picture(mediaID: image)))
        let table = PPTXSamples.table("Table", at: SlidePoint(x: 60, y: 260), PPTXSamples.smallTable())
        let chart = PPTXSamples.chart("Chart", SlideRect(x: 330, y: 230, width: 200, height: 140), PPTXSamples.salesChart(.column))
        let grouped = PPTXSamples.shape("Grouped", SlideRect(x: 600, y: 40, width: 50, height: 50), Shape(fill: .solid(ColorRef(theme: .accent2))))
        let group = PPTXGroupTransform.group([PPTXSamples.shape("Other", SlideRect(x: 660, y: 40, width: 50, height: 50), Shape()), grouped], name: "Group")
        slide.elements = [box, line, photo, table, chart, group]
        func comment(_ author: String, _ minutes: Double, _ text: String) -> PuggleSlidesKit.Comment {
            PuggleSlidesKit.Comment(author: author, date: PPTXSamples.commentDate.addingTimeInterval(minutes * 60), text: text)
        }
        var edited = comment("Ada Lovelace", 2, "Edited later")
        edited.editedDate = PPTXSamples.commentDate.addingTimeInterval(3600)
        slide.comments = [
            CommentThread(comments: [comment("Zoë Ångström", 0, "Make it bigger?\nAnd bluer."), comment("田中 太郎", 1, "はい、そうしましょう"), edited],
                          elementID: box.id, position: SlidePoint(x: 300, y: 80)),
            CommentThread(comments: [comment("Ada Lovelace", 3, "Straighten this line")], elementID: line.id, position: SlidePoint(x: 520, y: 60)),
            CommentThread(comments: [comment("Ада Лавлейс", 4, "Фото ✓"), comment("Zoë Ångström", 5, "Merci !")], isResolved: true,
                          elementID: photo.id, position: SlidePoint(x: 680.25, y: 200.5)),
            CommentThread(comments: [comment("Ada Lovelace", 6, "Totals?")], elementID: table.id, position: SlidePoint(x: 70, y: 255)),
            CommentThread(comments: [comment("Ada Lovelace", 7, "Label the axes")], isResolved: true, elementID: chart.id, position: SlidePoint(x: 530, y: 230)),
            CommentThread(comments: [comment("Zoë Ångström", 8, "Just this one")], elementID: grouped.id, position: SlidePoint(x: 650, y: 40)),
            CommentThread(comments: [comment("Zoë Ångström", 9, "The whole group")], elementID: group.id, position: SlidePoint(x: 710, y: 40)),
            CommentThread(comments: [comment("Ada Lovelace", 10, "Ünïcödé — 🎉 <&> \"quoted\"\n\n  spaced  ")], position: SlidePoint(x: 10.5, y: 20.25)),
            CommentThread(comments: [comment("", 11, "About something deleted")], elementID: UUID(), position: SlidePoint(x: 33, y: 44)),
        ]
        presentation.slides = [slide]
        return Deck(presentation: presentation, box: box, line: line, photo: photo, table: table, chart: chart, group: group, grouped: grouped)
    }

    static func read(_ package: Package) throws -> PresentationFile {
        try Package.read(try package.data())
    }

    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: Writing

    @Test func threadsRoundTrip() throws {
        let deck = Self.deck()
        let file = try Package.read(try PresentationIO.write(deck.presentation, format: .pptx))
        #expect(file.warnings.isEmpty)
        let difference = PPTXCanonical.difference(deck.presentation, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        let threads = file.presentation.slides[0].comments
        // Comment ids are kept; dates to the second; edit dates have no place in the file.
        #expect(threads.flatMap(\.comments).map(\.id) == deck.slide.comments.flatMap(\.comments).map(\.id))
        #expect(threads[0].comments[0].date == Date(timeIntervalSince1970: 1_763_370_000))
        #expect(threads.flatMap(\.comments).allSatisfy { $0.editedDate == nil })
        #expect(threads.map(\.isResolved) == [false, false, true, false, true, false, false, false, false])
        // The thread about an object that's gone is about the slide, where it was.
        #expect(threads[8].elementID == nil && threads[8].position == SlidePoint(x: 33, y: 44))
        #expect(threads[7].comments[0].text == "Ünïcödé — 🎉 <&> \"quoted\"\n\n  spaced  ")
        // Saving again writes the comments, their authors and the slides the same way.
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try Package.parts(of: try PPTXWriter.write(deck.presentation, date: date))
        let second = try Package.parts(of: try PPTXWriter.write(deck.presentation, date: date))
        #expect(first.keys.sorted() == second.keys.sorted())
        let differing = first.filter { $0.key.hasPrefix("ppt/comments/") || $0.key.hasPrefix("ppt/slides/") || $0.key == "ppt/authors.xml" }
            .filter { second[$0.key] != $0.value }.keys.sorted()
        #expect(differing.isEmpty, "\(differing)")
    }

    @Test func writesModernCommentsAsPowerPointDoes() throws {
        let deck = Self.deck()
        let parts = try Package.writtenParts(deck.presentation)
        // Modern comments only: PowerPoint shows a slide's comments twice when it has both kinds.
        #expect(parts["ppt/commentAuthors.xml"] == nil)
        #expect(!parts.keys.contains { $0.hasPrefix("ppt/comments/comment") })
        let authors = try #require(parts["ppt/authors.xml"])
        #expect(authors.contains("name=\"Zoë Ångström\" initials=\"ZÅ\" userId=\"Zoë Ångström\" providerId=\"None\"/>"))
        #expect(authors.components(separatedBy: "<p188:author ").count - 1 == 5)
        let presentationRelationships = try #require(parts["ppt/_rels/presentation.xml.rels"])
        #expect(presentationRelationships.contains("Type=\"\(Self.authors)\" Target=\"authors.xml\""))
        let path = try #require(parts.keys.first { $0.hasPrefix("ppt/comments/modernComment_") })
        let types = try #require(parts["[Content_Types].xml"])
        #expect(types.contains("<Override PartName=\"/ppt/authors.xml\" ContentType=\"application/vnd.ms-powerpoint.authors+xml\"/>"))
        #expect(types.contains("<Override PartName=\"/\(path)\" ContentType=\"application/vnd.ms-powerpoint.comments+xml\"/>"))

        // The slide relates to the part, names the relationship in its extension list, and has the creation id the
        // comments' slide moniker names.
        let slide = try #require(parts["ppt/slides/slide1.xml"])
        let relationships = try #require(parts["ppt/slides/_rels/slide1.xml.rels"])
        let relationship = try #require(Self.first("Id=\"(rId\\d+)\" Type=\"\(Self.modernComments)\"", in: relationships))
        #expect(slide.hasSuffix("<p:extLst><p:ext uri=\"{6950BFC3-D8DA-4A85-94F7-54DA5524770B}\"><p188:commentRel "
            + "xmlns:p188=\"http://schemas.microsoft.com/office/powerpoint/2018/8/main\" r:id=\"\(relationship)\"/></p:ext></p:extLst></p:sld>"))
        let creationID = try #require(Self.first("<p:ext uri=\"\\{BB962C8B-B14F-4D97-AF65-F5344CB8AC3E\\}\"><p14:creationId [^>]*val=\"(\\d+)\"/>"
            + "</p:ext></p:extLst></p:cSld>", in: slide))
        let comments = try #require(parts[path])
        #expect(comments.components(separatedBy: "<pc:sldMk cId=\"\(creationID)\" sldId=\"256\"/>").count - 1 == 9)

        // Each object a thread is about carries a creation id, which the thread's moniker names along with its kind.
        let kinds = [(deck.box, "spMk"), (deck.line, "cxnSpMk"), (deck.photo, "picMk"), (deck.table, "graphicFrameMk"),
                     (deck.chart, "graphicFrameMk"), (deck.group, "grpSpMk"), (deck.grouped, "spMk")]
        for (element, kind) in kinds {
            let guid = "{\(element.id.uuidString)}"
            let id = try #require(Self.first("<p:cNvPr id=\"(\\d+)\" name=\"\(element.name)\"><a:extLst><a:ext uri=\"\\{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236\\}\">"
                + "<a16:creationId xmlns:a16=\"http://schemas.microsoft.com/office/drawing/2014/main\" id=\"\(NSRegularExpression.escapedPattern(for: guid))\"/>",
                in: slide), "\(element.name)")
            #expect(comments.contains("<ac:\(kind) id=\"\(id)\" creationId=\"\(guid)\"/></ac:deMkLst>"), "\(element.name)")
        }
        // Objects nothing is said about carry no creation id.
        #expect(slide.components(separatedBy: "<a16:creationId").count - 1 == kinds.count)
        #expect(comments.components(separatedBy: "<pc:sldMkLst>").count - 1 == 2)
        #expect(comments.components(separatedBy: "status=\"resolved\"").count - 1 == 2)
        #expect(comments.components(separatedBy: "<p188:reply ").count - 1 == 3)
        #expect(comments.contains("created=\"2025-11-17T09:00:00Z\""))
        #expect(comments.contains("<a:p><a:r><a:t>Ünïcödé — 🎉 &lt;&amp;&gt; \"quoted\"</a:t></a:r></a:p><a:p/><a:p><a:r><a:t>  spaced  </a:t></a:r></a:p>"))
    }

    @Test func positionsAreMeasuredFromWhatTheThreadIsAbout() throws {
        let deck = Self.deck()
        let comments = try #require(try Package.writtenParts(deck.presentation).first { $0.key.hasPrefix("ppt/comments/") }?.value)
        // The box is at (100, 80) and its thread at (300, 80); the slide's thread is at (10.5, 20.25) from the slide's corner.
        #expect(comments.contains("creationId=\"{\(deck.box.id.uuidString)}\"/></ac:deMkLst><p188:pos x=\"2540000\" y=\"0\"/>"))
        #expect(comments.contains("</pc:sldMkLst><p188:pos x=\"133350\" y=\"257175\"/>"))
        // The table's thread is left of and above its corner.
        #expect(comments.contains("creationId=\"{\(deck.table.id.uuidString)}\"/></ac:deMkLst><p188:pos x=\"127000\" y=\"-63500\"/>"))
    }

    @Test func positionsSurviveFramesWrittenOtherwise() throws {
        var deck = Self.deck()
        // A group whose frame isn't its children's bounds (the file has the bounds), and a box with a negative width.
        deck.presentation.slides[0].elements[5].placement = Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10))
        deck.presentation.slides[0].elements[0].placement = Placement(frame: SlideRect(x: 300, y: 80, width: -200, height: 100))
        let read = try Package.read(try PresentationIO.write(deck.presentation, format: .pptx)).presentation.slides[0]
        #expect(read.comments.map(\.position) == deck.slide.comments.map(\.position))
        #expect(read.comments.map(\.elementID) == [read.elements[0].id, read.elements[1].id, read.elements[2].id, read.elements[3].id,
                                                   read.elements[4].id, read.elements[5].children?[1].id, read.elements[5].id, nil, nil])
    }

    @Test func idsStayUniqueAndEmptyThreadsAreLeftOut() throws {
        var deck = Self.deck()
        let shared = UUID()
        deck.presentation.slides[0].comments[0].comments[0].id = shared
        deck.presentation.slides[0].comments[1].comments[0].id = shared
        deck.presentation.slides[0].comments.append(CommentThread(comments: []))
        let data = try PresentationIO.write(deck.presentation, format: .pptx)
        let comments = try #require(try Package.parts(of: data).first { $0.key.hasPrefix("ppt/comments/") }.map { String(decoding: $0.value, as: UTF8.self) })
        #expect(comments.components(separatedBy: "<p188:cm ").count - 1 == 9)
        let read = try Package.read(data).presentation.slides[0].comments
        let ids = read.flatMap(\.comments).map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids[0] == shared)
    }

    // MARK: Reading PowerPoint's files

    static let titleCreation = "{3F2A0C11-7B4E-4E0B-9A51-0D1C2B3A4F50}"

    /// A slide as PowerPoint for Microsoft 365 saves one with modern comments: a title with a creation id, a text box,
    /// a picture, and threads about each, about text and about the slide.
    static func modernPackage(comments: String? = nil, authorsPart: String? = nil) -> Package {
        var package = Package()
        package.media = ["ppt/media/image1.png": PPTXSamples.photo]
        let title = PPTXReadTests.sp(4, "Title 1", xfrm: "<a:xfrm><a:off x=\"914400\" y=\"457200\"/><a:ext cx=\"7315200\" cy=\"914400\"/></a:xfrm>",
                                     text: "<a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Quarterly review</a:t></a:r></a:p>",
                                     extra: "><a:extLst><a:ext uri=\"{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236}\"><a16:creationId "
                                        + "xmlns:a16=\"http://schemas.microsoft.com/office/drawing/2014/main\" id=\"\(titleCreation)\"/></a:ext></a:extLst></p:cNvPr")
            .replacingOccurrences(of: "</p:cNvPr/>", with: "</p:cNvPr>")
        let body = PPTXReadTests.sp(5, "TextBox 2", xfrm: "<a:xfrm><a:off x=\"914400\" y=\"1828800\"/><a:ext cx=\"3657600\" cy=\"1371600\"/></a:xfrm>",
                                    text: "<a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Revenue grew</a:t></a:r></a:p>", textBox: true)
        let picture = "<p:pic><p:nvPicPr><p:cNvPr id=\"6\" name=\"Picture 5\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId3\"/>"
            + "<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"6096000\" y=\"2286000\"/><a:ext cx=\"1828800\" cy=\"1371600\"/>"
            + "</a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        let slide = Package.slide(title + body + picture, after: "<p:extLst><p:ext uri=\"{6950BFC3-D8DA-4A85-94F7-54DA5524770B}\">"
            + "<p188:commentRel xmlns:p188=\"http://schemas.microsoft.com/office/powerpoint/2018/8/main\" r:id=\"rId5\"/></p:ext></p:extLst>")
        package.slides = [Package.Slide(xml: slide, relationships: [Package.Relationship("rId3", "image", "../media/image1.png"),
                                                                    Package.Relationship("rId5", modernComments, "../comments/modernComment_100_8E1B9C2D.xml")])]
        package.presentationRelationships = [Package.Relationship("rId50", authors, "authors.xml")]
        package.extraParts["ppt/authors.xml"] = authorsPart ?? "<p188:authorLst \(modernNamespaces)>"
            + "<p188:author id=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" name=\"Rosa Díaz\" initials=\"RD\" userId=\"S::rosa@example.com::f2b0c1d2\" providerId=\"AD\"/>"
            + "<p188:author id=\"{1B2C3D4E-2222-4F5A-8B9C-0D1E2F3A4B5C}\" name=\"Jürgen Groß\" initials=\"JG\" userId=\"Jürgen Groß\" providerId=\"None\"/>"
            + "</p188:authorLst>"
        let slideMonikers = "<pc:docMk/><pc:sldMk cId=\"2384756190\" sldId=\"256\"/>"
        package.extraParts["ppt/comments/modernComment_100_8E1B9C2D.xml"] = comments ?? "<p188:cmLst \(modernNamespaces)>"
            // About the title, named by its creation id (its id in the moniker is out of date), resolved, with replies.
            + "<p188:cm id=\"{0A1B2C3D-0001-4000-8000-000000000001}\" authorId=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" status=\"resolved\" "
            + "created=\"2024-05-06T07:08:09.123\"><ac:deMkLst xmlns:ac=\"http://schemas.microsoft.com/office/drawing/2013/main/command\">"
            + "\(slideMonikers)<ac:spMk id=\"999\" creationId=\"\(titleCreation)\"/></ac:deMkLst><p188:pos x=\"12700\" y=\"25400\"/>"
            + "<p188:replyLst><p188:reply id=\"{0A1B2C3D-0002-4000-8000-000000000002}\" authorId=\"{1B2C3D4E-2222-4F5A-8B9C-0D1E2F3A4B5C}\" "
            + "created=\"2024-05-06T09:00:00.5Z\"><p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang=\"de-DE\"/><a:t>Erledigt</a:t></a:r>"
            + "</a:p></p188:txBody></p188:reply><p188:reply id=\"{0A1B2C3D-0003-4000-8000-000000000003}\" authorId=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" "
            + "created=\"2024-05-07T00:00:00\"><p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Gracias</a:t></a:r><a:br/><a:r><a:t>¡Perfecto!</a:t>"
            + "</a:r></a:p></p188:txBody></p188:reply></p188:replyLst><p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Shorter title?</a:t></a:r>"
            + "</a:p></p188:txBody></p188:cm>"
            // About text in the text box: the text box. No position: at its top-right corner.
            + "<p188:cm id=\"{0A1B2C3D-0004-4000-8000-000000000004}\" authorId=\"{1B2C3D4E-2222-4F5A-8B9C-0D1E2F3A4B5C}\" created=\"2024-05-08T10:00:00\">"
            + "<ac:txMkLst xmlns:ac=\"http://schemas.microsoft.com/office/drawing/2013/main/command\">\(slideMonikers)<ac:spMk id=\"5\"/>"
            + "<ac:txMk cp=\"0\" len=\"7\"><ac:context len=\"12\" hash=\"2914315217\"/></ac:txMk></ac:txMkLst><p188:txBody><a:bodyPr/><a:lstStyle/>"
            + "<a:p><a:r><a:t>By how much?</a:t></a:r></a:p></p188:txBody></p188:cm>"
            // About the slide, in another time zone, closed.
            + "<p188:cm id=\"{0A1B2C3D-0005-4000-8000-000000000005}\" authorId=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" status=\"closed\" "
            + "created=\"2024-05-09T12:30:00+02:00\"><pc:sldMkLst>\(slideMonikers)</pc:sldMkLst><p188:pos x=\"635000\" y=\"317500\"/><p188:txBody>"
            + "<a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Slide </a:t></a:r><a:fld id=\"{B1}\" type=\"slidenum\"><a:t>1</a:t></a:fld></a:p><a:p/>"
            + "<a:p><a:r><a:t>third line</a:t></a:r></a:p></p188:txBody></p188:cm>"
            // An anchor PowerPoint couldn't name, and a picture named by id only, by an author not in the list.
            + "<p188:cm id=\"{0A1B2C3D-0006-4000-8000-000000000006}\" authorId=\"{1B2C3D4E-2222-4F5A-8B9C-0D1E2F3A4B5C}\" created=\"2024-05-10T00:00:00\">"
            + "<p188:unknownAnchor/><p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Lost anchor</a:t></a:r></a:p></p188:txBody></p188:cm>"
            + "<p188:cm id=\"{0A1B2C3D-0007-4000-8000-000000000007}\" authorId=\"{FFFFFFFF-2222-4F5A-8B9C-0D1E2F3A4B5C}\" created=\"2024-05-11T00:00:00\">"
            + "<ac:deMkLst xmlns:ac=\"http://schemas.microsoft.com/office/drawing/2013/main/command\">\(slideMonikers)<ac:picMk id=\"6\" "
            + "creationId=\"{99999999-9999-4999-8999-999999999999}\"/></ac:deMkLst><p188:pos x=\"-12700\" y=\"0\"/><p188:txBody><a:bodyPr/><a:lstStyle/>"
            + "<a:p><a:r><a:t>Who wrote this?</a:t></a:r></a:p></p188:txBody></p188:cm>"
            + "</p188:cmLst>"
        return package
    }

    /// Dates equal to the millisecond.
    static func same(_ a: [Date], _ b: [Date]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.timeIntervalSince($1)) < 0.001 }
    }

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Double = 0, zone: TimeZone = CommentDates.utc) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return date.addingTimeInterval(second)
    }

    @Test func readsPowerPointModernComments() throws {
        let file = try Self.read(Self.modernPackage())
        #expect(file.warnings.isEmpty)
        let slide = file.presentation.slides[0]
        let title = slide.elements[0], body = slide.elements[1], picture = slide.elements[2]
        let threads = slide.comments
        #expect(threads.count == 5)

        #expect(threads[0].elementID == title.id)
        #expect(threads[0].isResolved)
        #expect(threads[0].position == SlidePoint(x: 73, y: 38))
        #expect(threads[0].comments.map(\.author) == ["Rosa Díaz", "Jürgen Groß", "Rosa Díaz"])
        #expect(threads[0].comments.map(\.text) == ["Shorter title?", "Erledigt", "Gracias\n¡Perfecto!"])
        #expect(Self.same(threads[0].comments.map(\.date), [Self.utc(2024, 5, 6, 7, 8, 9.123), Self.utc(2024, 5, 6, 9, 0, 0.5), Self.utc(2024, 5, 7, 0, 0)]))
        #expect(threads[0].comments.map(\.id.uuidString) == ["0A1B2C3D-0001-4000-8000-000000000001", "0A1B2C3D-0002-4000-8000-000000000002",
                                                            "0A1B2C3D-0003-4000-8000-000000000003"])

        #expect(threads[1].elementID == body.id)
        #expect(!threads[1].isResolved)
        #expect(threads[1].position == SlidePoint(x: 360, y: 144))

        #expect(threads[2].elementID == nil)
        #expect(threads[2].isResolved)
        #expect(threads[2].position == SlidePoint(x: 50, y: 25))
        #expect(threads[2].comments[0].date == Self.utc(2024, 5, 9, 10, 30))
        #expect(threads[2].comments[0].text == "Slide 1\n\nthird line")

        #expect(threads[3].elementID == nil && threads[3].position == SlidePoint(x: 0, y: 0))

        #expect(threads[4].elementID == picture.id)
        #expect(threads[4].position == SlidePoint(x: 479, y: 180))
        #expect(threads[4].comments[0].author == "")
    }

    @Test func placeholdersArePlacedFromTheirLayoutOrMaster() throws {
        let title = "<p:ph type=\"title\"/>"
        var package = Self.modernPackage(comments: "<p188:cmLst \(Self.modernNamespaces)><p188:cm id=\"{0A1B2C3D-0009-4000-8000-000000000009}\" "
            + "authorId=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" created=\"2024-05-06T07:08:09\"><ac:deMkLst><pc:docMk/><pc:sldMk sldId=\"256\"/>"
            + "<ac:spMk id=\"2\"/></ac:deMkLst><p188:pos x=\"12700\" y=\"0\"/><p188:txBody><a:bodyPr/><a:lstStyle/><a:p/></p188:txBody></p188:cm>"
            + "<p188:cm id=\"{0A1B2C3D-0010-4000-8000-000000000010}\" authorId=\"{8A9D1B3E-1111-4C2B-9D3A-5E6F7A8B9C0D}\" created=\"2024-05-06T07:08:09\">"
            + "<ac:deMkLst><pc:docMk/><pc:sldMk sldId=\"256\"/><ac:spMk id=\"2\"/></ac:deMkLst><p188:txBody><a:bodyPr/><a:lstStyle/><a:p/></p188:txBody>"
            + "</p188:cm></p188:cmLst>")
        // The slide's and the layout's titles say nothing of where they are: the master's does.
        package.masterTree = PPTXReadTests.sp(2, "Title", ph: title, xfrm: "<a:xfrm><a:off x=\"1270000\" y=\"254000\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>")
        package.layouts = [Package.layout(type: "title", name: "Title", tree: PPTXReadTests.sp(2, "Title", ph: title, xfrm: nil))]
        package.slides[0].xml = Package.slide(PPTXReadTests.sp(2, "Title 1", ph: title, xfrm: nil, text: "<a:bodyPr/><a:lstStyle/><a:p/>"))
        let file = try Self.read(package)
        let slide = file.presentation.slides[0]
        #expect(slide.elements[0].placement == nil)
        #expect(slide.comments.map(\.elementID) == [slide.elements[0].id, slide.elements[0].id])
        #expect(slide.comments.map(\.position) == [SlidePoint(x: 101, y: 20), SlidePoint(x: 500, y: 20)])
        // Written again, the positions are measured from the same place.
        let again = try Package.read(try PresentationIO.write(file.presentation, format: .pptx)).presentation.slides[0]
        #expect(again.comments.map(\.position) == slide.comments.map(\.position))
    }

    @Test func readsLegacyComments() throws {
        var package = Package()
        let threading = "{C676402C-5697-4E1C-873F-D02D1690AC5C}"
        let p15 = "xmlns:p15=\"http://schemas.microsoft.com/office/powerpoint/2012/main\""
        package.slides = [Package.Slide(xml: Package.slide(PPTXReadTests.sp(2, "Box")), relationships: [Package.Relationship("rId7", "comments", "../comments/comment1.xml")])]
        package.presentationRelationships = [Package.Relationship("rId60", "commentAuthors", "commentAuthors.xml")]
        package.extraParts["ppt/commentAuthors.xml"] = "<p:cmAuthorLst {NS}><p:cmAuthor id=\"0\" name=\"Jürgen Groß\" initials=\"JG\" lastIdx=\"2\" clrIdx=\"0\"/>"
            + "<p:cmAuthor id=\"1\" name=\"Amélie Dupont\" initials=\"AD\" lastIdx=\"1\" clrIdx=\"1\"/></p:cmAuthorLst>"
        package.extraParts["ppt/comments/comment1.xml"] = "<p:cmLst {NS}>"
            + "<p:cm authorId=\"0\" dt=\"2013-03-04T10:32:12.360\" idx=\"1\"><p:pos x=\"10\" y=\"20\"/><p:text>First line\nsecond line</p:text>"
            + "<p:extLst><p:ext uri=\"\(threading)\"><p15:threadingInfo \(p15) timeZoneBias=\"-60\"/></p:ext></p:extLst></p:cm>"
            + "<p:cm authorId=\"1\" dt=\"2013-03-04T11:00:00.000\" idx=\"1\"><p:pos x=\"10\" y=\"20\"/><p:text>Réponse</p:text>"
            + "<p:extLst><p:ext uri=\"\(threading)\"><p15:threadingInfo \(p15) timeZoneBias=\"-60\"><p15:parentCm authorId=\"0\" idx=\"1\"/>"
            + "</p15:threadingInfo></p:ext></p:extLst></p:cm>"
            + "<p:cm authorId=\"0\" dt=\"2013-03-05T08:00:00\" idx=\"2\"><p:pos x=\"800\" y=\"400\"/><p:text>Older, unthreaded</p:text></p:cm>"
            // A reply to a comment that isn't there starts a thread; an unknown author has no name.
            + "<p:cm authorId=\"7\" dt=\"2013-03-06T08:00:00Z\" idx=\"1\"><p:pos x=\"0\" y=\"0\"/><p:text>Orphan</p:text><p:extLst><p:ext uri=\"\(threading)\">"
            + "<p15:threadingInfo \(p15)><p15:parentCm authorId=\"9\" idx=\"9\"/></p15:threadingInfo></p:ext></p:extLst></p:cm>"
            + "</p:cmLst>"
        let file = try Self.read(package)
        #expect(file.warnings.isEmpty)
        let threads = file.presentation.slides[0].comments
        #expect(threads.count == 3)
        // Positions are in eighths of a point; dates are the author's wall clock, in UTC once the bias is applied.
        #expect(threads[0].position == SlidePoint(x: 1.25, y: 2.5))
        #expect(threads[0].elementID == nil && !threads[0].isResolved)
        #expect(threads[0].comments.map(\.author) == ["Jürgen Groß", "Amélie Dupont"])
        #expect(threads[0].comments.map(\.text) == ["First line\nsecond line", "Réponse"])
        #expect(Self.same(threads[0].comments.map(\.date), [Self.utc(2013, 3, 4, 9, 32, 12.36), Self.utc(2013, 3, 4, 10, 0)]))
        #expect(threads[1].position == SlidePoint(x: 100, y: 50))
        #expect(threads[1].comments[0].date == Self.utc(2013, 3, 5, 8, 0, zone: .current))
        #expect(threads[2].comments[0].author == "" && threads[2].comments[0].text == "Orphan")
        #expect(threads[2].comments[0].date == Self.utc(2013, 3, 6, 8, 0))
        // Saved, they're modern comments.
        let parts = try Package.writtenParts(file.presentation)
        #expect(parts.keys.contains { $0.hasPrefix("ppt/comments/modernComment_") } && parts["ppt/authors.xml"] != nil)
    }

    @Test func aSlideWithBothKindsKeepsTheModernComments() throws {
        var package = Self.modernPackage()
        package.slides[0].relationships.append(Package.Relationship("rId8", "comments", "../comments/comment1.xml"))
        package.presentationRelationships.append(Package.Relationship("rId60", "commentAuthors", "commentAuthors.xml"))
        package.extraParts["ppt/commentAuthors.xml"] = "<p:cmAuthorLst {NS}><p:cmAuthor id=\"0\" name=\"Rosa Díaz\" initials=\"RD\" lastIdx=\"2\" clrIdx=\"0\"/>"
            + "</p:cmAuthorLst>"
        package.extraParts["ppt/comments/comment1.xml"] = "<p:cmLst {NS}><p:cm authorId=\"0\" dt=\"2024-05-06T07:08:09\" idx=\"1\"><p:pos x=\"0\" y=\"0\"/>"
            + "<p:text>Shorter title?</p:text></p:cm><p:cm authorId=\"0\" dt=\"2024-05-06T07:08:09\" idx=\"2\"><p:pos x=\"0\" y=\"0\"/>"
            + "<p:text>Only here</p:text></p:cm></p:cmLst>"
        let threads = try Self.read(package).presentation.slides[0].comments
        #expect(threads.map { $0.comments[0].text } == ["Shorter title?", "By how much?", "Slide 1\n\nthird line", "Lost anchor", "Who wrote this?", "Only here"])
    }

    @Test func commentPartsThatCantBeReadLeaveAWarning() throws {
        // No comments, no warning.
        var plain = Package()
        plain.slides = [Package.Slide(xml: Package.slide(""))]
        #expect(try Self.read(plain).warnings.isEmpty)

        var missing = Self.modernPackage()
        missing.extraParts["ppt/comments/modernComment_100_8E1B9C2D.xml"] = nil
        let missingFile = try Self.read(missing)
        #expect(missingFile.warnings == [.comments] && missingFile.presentation.slides[0].comments.isEmpty)

        for damaged in ["<p188:cmLst \(Self.modernNamespaces)><p188:cm>", "<p:sld {NS}/>", "not xml at all"] {
            let file = try Self.read(Self.modernPackage(comments: damaged))
            #expect(file.warnings == [.comments], "\(damaged)")
            #expect(file.presentation.slides[0].comments.isEmpty)
        }

        // Damaged authors: the comments are kept without names.
        let file = try Self.read(Self.modernPackage(authorsPart: "<p188:authorLst"))
        #expect(file.warnings == [.comments])
        #expect(file.presentation.slides[0].comments.count == 5)
        #expect(file.presentation.slides[0].comments.allSatisfy { $0.comments.allSatisfy { $0.author.isEmpty } })
    }

    /// Damaged comment parts read (or leave a warning) and write again; they never crash or hang.
    @Test(.timeLimit(.minutes(2)))
    func survivesDamagedCommentParts() throws {
        let fragments = [
            "<p188:cm>", "</p188:cm>", "<p188:replyLst>", "</p188:replyLst>", "<p188:reply/>", "<p188:txBody>", "<a:p>", "</a:p>", "<a:br/>",
            "created=\"9999-99-99T99:99:99\"", "created=\"-0001-01-01T00:00:00Z\"", "created=\"2024-02-30T24:00:00+14:59\"", "created=\"\"",
            "status=\"resolved\"", "status=\"\u{0}\"", "id=\"{GGGG}\"", "id=\"{0A1B2C3D-0001-4000-8000-000000000001}\"", "authorId=\"{}\"",
            "<ac:spMk id=\"-1\" creationId=\"{zz}\"/>", "<ac:spMk id=\"4\"/>", "<ac:picMk/>", "<p188:pos x=\"1e400\" y=\"NaN\"/>", "<p188:pos x=\"-9e99\" y=\"inf\"/>",
            "<p188:pos/>", "<pc:sldMkLst/>", "<ac:deMkLst/>", "<ac:txMkLst><ac:txMk cp=\"-5\"/></ac:txMkLst>", "<p188:unknownAnchor/>", "&amp;",
            "<![CDATA[<x>]]>", "\u{FFFF}", "<p:cm authorId=\"0\" idx=\"1\"><p:pos x=\"1\" y=\"2\"/><p:text>loop</p:text><p:extLst><p:ext "
                + "uri=\"{C676402C-5697-4E1C-873F-D02D1690AC5C}\"><p15:threadingInfo timeZoneBias=\"99999999999\"><p15:parentCm authorId=\"0\" idx=\"1\"/>"
                + "</p15:threadingInfo></p:ext></p:extLst></p:cm>",
        ]
        let original = try #require(Self.modernPackage().extraParts["ppt/comments/modernComment_100_8E1B9C2D.xml"])
        var random = PPTXTestRandom(seed: 4242)
        for iteration in 0..<300 {
            var text = original
            for _ in 0..<(1 + random.below(4)) where !text.isEmpty {
                let offset = text.index(text.startIndex, offsetBy: random.below(text.count))
                switch random.below(3) {
                case 0: text.insert(contentsOf: fragments[random.below(fragments.count)], at: offset)
                case 1: text = String(text[..<offset])
                default: text.remove(at: offset)
                }
            }
            if iteration % 50 == 0 {
                // Deep nesting and many comments.
                text = "<p188:cmLst \(Self.modernNamespaces)>" + String(repeating: "<p188:cm>", count: 400) + "</p188:cmLst>"
                if iteration % 100 == 0 {
                    let one = "<p188:cm id=\"{0A1B2C3D-0001-4000-8000-000000000001}\" authorId=\"{}\" created=\"x\"><p188:unknownAnchor/></p188:cm>"
                    text = "<p188:cmLst \(Self.modernNamespaces)>" + String(repeating: one, count: 5_000) + "</p188:cmLst>"
                }
            }
            let data = try Self.modernPackage(comments: text).data()
            do {
                let file = try Package.read(data)
                let written = try PresentationIO.write(file.presentation, format: .pptx)
                let again = try Package.read(written)
                #expect(again.presentation.slides[0].comments.count == file.presentation.slides[0].comments.count)
            } catch let error as PresentationIOError {
                #expect(!(error.errorDescription ?? "").isEmpty)
            }
        }
    }

    // MARK: Dates

    @Test func datesReadAsXMLSchemaDateTimes() {
        let zone = TimeZone(secondsFromGMT: 3600)!
        #expect(CommentDates.parse("2024-05-06T07:08:09Z", zone: zone) == Self.utc(2024, 5, 6, 7, 8, 9))
        #expect(Self.same([CommentDates.parse(" 2024-05-06T07:08:09.25-05:30 ", zone: zone) ?? .distantPast], [Self.utc(2024, 5, 6, 12, 38, 9.25)]))
        #expect(CommentDates.parse("2024-05-06T07:08:09", zone: zone) == Self.utc(2024, 5, 6, 6, 8, 9))
        #expect(CommentDates.parse("2024-05-06T07:08", zone: CommentDates.utc) == Self.utc(2024, 5, 6, 7, 8))
        #expect(CommentDates.parse("2024-05-06", zone: CommentDates.utc) == Self.utc(2024, 5, 6, 0, 0))
        #expect(CommentDates.parse("2024-05-06T24:00:00Z", zone: zone) == Self.utc(2024, 5, 7, 0, 0))
        // Legacy PowerPoint's bias: UTC = local time + bias.
        #expect(CommentDates.parse("2013-03-04T10:00:00", zone: zone, biasMinutes: 300) == Self.utc(2013, 3, 4, 15, 0))
        #expect(CommentDates.parse("2013-03-04T10:00:00Z", zone: zone, biasMinutes: 300) == Self.utc(2013, 3, 4, 10, 0))
        for bad in ["", "yesterday", "2024-13-01T00:00:00", "2024-05-06T25:00:00", "2024-05-06T24:00:01", "2024-05-06T07:08:09.", "2024-5-6",
                    "2024-05-06T07:08:09+15:00", "2024-05-06T07:08:09Z junk", "0000-01-01", String(repeating: "9", count: 100)] {
            #expect(CommentDates.parse(bad, zone: zone) == nil, "\(bad)")
        }
        #expect(CommentDates.utcString(Self.utc(2024, 5, 6, 7, 8, 9.999)) == "2024-05-06T07:08:09Z")
        #expect(CommentDates.string(Self.utc(2024, 5, 6, 23, 30), zone: zone) == "2024-05-07T00:30:00")
        // Dates far out are kept where every app's calendar agrees.
        #expect(CommentDates.utcString(Date(timeIntervalSince1970: 1e12)) == "9999-12-31T23:59:59Z")
        #expect(CommentDates.utcString(.distantPast) == "1601-01-01T00:00:00Z")
        #expect(CommentDates.utcString(Date(timeIntervalSince1970: .nan)) == "1970-01-01T00:00:00Z")
    }
}
