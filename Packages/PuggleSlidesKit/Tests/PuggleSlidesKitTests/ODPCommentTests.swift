import Foundation
import Testing
@testable import PuggleSlidesKit

/// Comment threads in OpenDocument presentations: LibreOffice Impress's page annotations, one per comment and reply,
/// with threads marked as LibreOffice Writer marks them.
struct ODPCommentTests {
    static func content(_ data: Data) throws -> String {
        try #require(try ODPTestPackage.part("content.xml", of: data))
    }

    static func annotations(_ content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<officeooo:annotation .*?</officeooo:annotation>") else { return [] }
        return regex.matches(in: content, range: NSRange(content.startIndex..., in: content)).compactMap { Range($0.range, in: content).map { String(content[$0]) } }
    }

    static func read(shapes: String, styles: String = "") throws -> PresentationFile {
        try PresentationIO.read(try ODPObjectFixture.package(styles: styles, shapes: shapes), format: .odp)
    }

    static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Double = 0) -> Date {
        PPTXCommentTests.utc(year, month, day, hour, minute, second, zone: .current)
    }

    // MARK: Writing

    @Test func threadsRoundTrip() throws {
        let deck = PPTXCommentTests.deck()
        let file = try PresentationIO.read(try PresentationIO.write(deck.presentation, format: .odp), format: .odp)
        #expect(file.warnings.isEmpty)
        let difference = ODPRendering.difference(deck.presentation, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        let original = ODPRendering.comments(deck.slide), read = ODPRendering.comments(file.presentation.slides[0])
        #expect(read == original)
        #expect(read.count == 9 && read[0].hasPrefix("about 1 resolved false at 300.0,80.0: Zoë Ångström|1763370000|Make it bigger?\nAnd bluer. / 田中 太郎|"))
        #expect(read[5].hasPrefix("about 6.2 resolved false"))
        #expect(read[8].hasPrefix("about slide resolved false at 33.0,44.0: |1763370660|About something deleted"))
        // The rich and objects decks too.
        for source in [ODPSamples.rich(), ODPSamples.objects()] {
            let again = try PresentationIO.read(try PresentationIO.write(source, format: .odp), format: .odp).presentation
            #expect(zip(source.slides, again.slides).allSatisfy { ODPRendering.comments($0) == ODPRendering.comments($1) })
            #expect(source.slides.contains { !$0.comments.isEmpty })
        }
    }

    @Test func writesAnnotationsAsLibreOfficeDoes() throws {
        let deck = PPTXCommentTests.deck()
        let content = try Self.content(try PresentationIO.write(deck.presentation, format: .odp))
        let annotations = Self.annotations(content)
        // One annotation per comment and reply, after the page's notes, as LibreOffice writes them.
        #expect(annotations.count == 12)
        #expect(content.contains("</presentation:notes><officeooo:annotation "))
        let first = annotations[0]
        #expect(first.hasPrefix("<officeooo:annotation xmlns:officeooo=\"http://openoffice.org/2009/office\" "
            + "xmlns:loext=\"urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0\" "
            + "xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" svg:x=\"300pt\" svg:y=\"80pt\" "
            + "office:name=\"__Annotation__1_1\" psext:anchor=\"s1c1\" loext:date-utc=\"2025-11-17T09:00:00Z\">"))
        let wallClock = CommentDates.string(PPTXSamples.commentDate, zone: .current)
        #expect(first.hasSuffix("<dc:creator>Zoë Ångström</dc:creator><dc:date>\(wallClock)</dc:date><meta:creator-initials>ZÅ</meta:creator-initials>"
            + "<text:p>Make it bigger?</text:p><text:p>And bluer.</text:p></officeooo:annotation>"))
        // The object a thread is about carries the id its first annotation names.
        #expect(content.contains("draw:name=\"Box\" draw:style-name=") && content.contains("xml:id=\"s1c1\" draw:id=\"s1c1\""))
        // Replies name their thread; resolved threads say so; an author-less comment has no creator.
        #expect(annotations[1].contains("loext:parent-name=\"__Annotation__1_1\"") && !annotations[1].contains("office:name"))
        #expect(annotations[2].contains("loext:parent-name=\"__Annotation__1_1\""))
        #expect(content.components(separatedBy: "loext:resolved=\"true\"").count - 1 == 2)
        #expect(annotations[11].contains("svg:x=\"33pt\" svg:y=\"44pt\" office:name=\"__Annotation__1_9\" loext:date-utc"))
        #expect(!annotations[11].contains("psext:anchor") && !annotations[11].contains("dc:creator"))
        #expect(annotations[10].contains("<text:p>Ünïcödé — 🎉 &lt;&amp;&gt; \"quoted\"</text:p><text:p/><text:p><text:s text:c=\"2\"/>spaced <text:s/></text:p>"))
        // Pages without comments have none.
        let plain = try Self.content(try PresentationIO.write(Presentation.makeDefault(), format: .odp))
        #expect(!plain.contains("annotation") && !plain.contains("loext"))
    }

    // MARK: Reading LibreOffice's files

    static let box = """
        <draw:frame draw:name="Box" draw:style-name="gr1" draw:layer="layout" xml:id="id1" draw:id="id1" svg:width="4cm" svg:height="2cm" \
        svg:x="2cm" svg:y="3cm"><draw:text-box><text:p>Box text<office:annotation><dc:creator>Im Text</dc:creator><dc:date>2025-01-02T03:04:05Z\
        </dc:date><text:p>About the box</text:p></office:annotation></text:p></draw:text-box></draw:frame>
        """

    @Test func readsLibreOfficeAnnotations() throws {
        let annotations = """
            <presentation:notes><draw:page-thumbnail draw:layer="layout" svg:width="14cm" svg:height="8cm" svg:x="3cm" svg:y="2cm" \
            draw:page-number="1" presentation:class="page"/></presentation:notes>\
            <officeooo:annotation svg:x="13.97cm" svg:y="0.25cm" svg:width="0.635cm" svg:height="0.635cm"><dc:creator>Jürgen Groß</dc:creator>\
            <dc:date>2025-11-17T10:00:00.123456789</dc:date><meta:creator-initials>JG</meta:creator-initials><text:p>Erste \
            <text:span text:style-name="T1">Zeile</text:span></text:p><text:p>zweite<text:s text:c="3"/>Zeile<text:tab/>!</text:p></officeooo:annotation>\
            <officeooo:annotation svg:x="1cm" svg:y="1cm" loext:date-utc="2025-11-17T09:00:00.5Z"><dc:creator>Amélie</dc:creator>\
            <dc:date>2025-11-17T10:00:00.5</dc:date><loext:sender-initials>A</loext:sender-initials><text:list><text:list-item><text:p>Listed</text:p>\
            </text:list-item></text:list></officeooo:annotation>\
            <office:annotation svg:x="2cm" svg:y="2cm"><dc:date>2010-01-01T00:00:00</dc:date><text:p>Older, without an author</text:p></office:annotation>\
            <officeooo:annotation svg:x="5cm" svg:y="5cm" office:name="t1" loext:resolved="true" psext:anchor="id1" \
            xmlns:psext="urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0"><dc:creator>Ada</dc:creator><text:p>Thread</text:p>\
            </officeooo:annotation><officeooo:annotation svg:x="5cm" svg:y="5cm" loext:parent-name="t1"><dc:creator>Bob</dc:creator><text:p>Reply</text:p>\
            </officeooo:annotation><officeooo:annotation svg:x="6cm" svg:y="6cm" loext:parent-name="gone"><text:p>Reply to nothing</text:p></officeooo:annotation>
            """
        let file = try Self.read(shapes: Self.box + annotations)
        #expect(file.warnings.isEmpty)
        let slide = file.presentation.slides[0]
        let threads = slide.comments
        #expect(threads.count == 6)
        // In text: about the frame, at its top-right corner.
        #expect(threads[0].elementID == slide.elements[0].id)
        #expect(threads[0].comments[0].author == "Im Text" && threads[0].comments[0].text == "About the box")
        #expect(threads[0].comments[0].date == PPTXCommentTests.utc(2025, 1, 2, 3, 4, 5))
        #expect(abs(threads[0].position.x - ODPReadTests.points(6)) < 0.001 && abs(threads[0].position.y - ODPReadTests.points(3)) < 0.001)
        #expect(slide.elements[0].shape?.text?.plainText == "Box text")
        // On the page: placed in centimeters; the wall clock in the reader's time zone unless the moment is given.
        #expect(abs(threads[1].position.x - ODPReadTests.points(13.97)) < 0.001 && abs(threads[1].position.y - ODPReadTests.points(0.25)) < 0.001)
        #expect(threads[1].elementID == nil && !threads[1].isResolved)
        #expect(threads[1].comments[0].author == "Jürgen Groß")
        #expect(threads[1].comments[0].text == "Erste Zeile\nzweite   Zeile\t!")
        #expect(PPTXCommentTests.same([threads[1].comments[0].date], [Self.local(2025, 11, 17, 10, 0, 0.123456789)]))
        #expect(PPTXCommentTests.same([threads[2].comments[0].date], [PPTXCommentTests.utc(2025, 11, 17, 9, 0, 0.5)]))
        #expect(threads[2].comments[0].text == "Listed")
        #expect(threads[3].comments[0].author == "" && threads[3].comments[0].date == Self.local(2010, 1, 1, 0, 0))
        // Threads marked as Writer marks them, about the object they name.
        #expect(threads[4].comments.map(\.text) == ["Thread", "Reply"] && threads[4].isResolved)
        #expect(threads[4].elementID == slide.elements[0].id)
        #expect(threads[5].comments.map(\.text) == ["Reply to nothing"])
    }

    @Test func commentsLibreOfficeSavedAgainAreEachTheirOwn() throws {
        // LibreOffice keeps comments, but not threads, anchors or the moment written, when it saves.
        let deck = PPTXCommentTests.deck()
        let data = try PresentationIO.write(deck.presentation, format: .odp)
        var parts = try ODPTestPackage.parts(of: data)
        var content = String(decoding: try #require(parts["content.xml"]), as: UTF8.self)
        content = content.replacingOccurrences(of: " (office:name|loext:[a-z-]+|psext:anchor)=\"[^\"]*\"", with: "", options: .regularExpression)
        parts["content.xml"] = Data(content.utf8)
        let resaved = try ODPTestPackage.zip(parts)
        let threads = try PresentationIO.read(resaved, format: .odp).presentation.slides[0].comments
        #expect(threads.count == 12)
        #expect(threads.allSatisfy { $0.comments.count == 1 && $0.elementID == nil && !$0.isResolved })
        #expect(threads[0].position == SlidePoint(x: 300, y: 80) && threads[1].position == SlidePoint(x: 300, y: 80))
        #expect(threads[0].comments[0].date == Date(timeIntervalSince1970: 1_763_370_000))
    }

    @Test func commentsOnMasterPagesLeaveAWarning() throws {
        let master = "<style:master-page style:name=\"Default\" style:page-layout-name=\"PM1\"/>"
        let styles = ODPObjectFixture.styles().replacingOccurrences(of: master, with: "<style:master-page style:name=\"Default\" "
            + "style:page-layout-name=\"PM1\"><officeooo:annotation svg:x=\"1cm\" svg:y=\"1cm\"><text:p>On the master</text:p></officeooo:annotation>"
            + "</style:master-page>")
        #expect(styles != ODPObjectFixture.styles())
        let manifest = "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\">"
            + "<manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.presentation\"/></manifest:manifest>"
        let data = try ODPTestPackage.zip([("content.xml", Data(ODPObjectFixture.content(styles: "", shapes: "").utf8)), ("styles.xml", Data(styles.utf8)),
                                           ("META-INF/manifest.xml", Data(manifest.utf8))])
        let file = try PresentationIO.read(data, format: .odp)
        #expect(file.warnings == [.comments])
        #expect(file.presentation.slides.allSatisfy { $0.comments.isEmpty })
    }

    /// Damaged annotations read and write again; they never crash or hang.
    @Test(.timeLimit(.minutes(2)))
    func survivesDamagedAnnotations() throws {
        let fragments = [
            "<officeooo:annotation>", "</officeooo:annotation>", "<office:annotation/>", "<text:list><text:list-item>", "<text:p>", "</text:p>",
            "loext:parent-name=\"__Annotation__1_1\"", "office:name=\"__Annotation__1_1\"", "office:name=\"\"", "psext:anchor=\"s1c1\"",
            "psext:anchor=\"page1\"", "svg:x=\"1e400cm\"", "svg:y=\"NaN\"", "svg:x=\"-9e99in\"", "loext:date-utc=\"nope\"", "loext:resolved=\"TRUE\"",
            "<dc:date>99999</dc:date>", "<dc:date>2025-02-30T25:61:61</dc:date>", "<dc:creator/>", "<text:s text:c=\"999999999\"/>", "&amp;", "\u{FFFF}",
        ]
        let original = try Self.content(try PresentationIO.write(PPTXCommentTests.deck().presentation, format: .odp))
        let start = try #require(original.range(of: "</presentation:notes>")).upperBound
        let parts = try ODPTestPackage.parts(of: try PresentationIO.write(PPTXCommentTests.deck().presentation, format: .odp))
        var random = ODPTestRandom(seed: 77)
        for iteration in 0..<200 {
            var text = original
            for _ in 0..<(1 + random.below(4)) {
                let tail = text.distance(from: start, to: text.endIndex)
                guard tail > 0 else { break }
                let offset = text.index(start, offsetBy: random.below(tail))
                if random.below(3) == 0 {
                    text.remove(at: offset)
                } else {
                    text.insert(contentsOf: fragments[random.below(fragments.count)], at: offset)
                }
            }
            if iteration % 40 == 0 {
                // Many comments, and annotations nested deep in lists.
                let many = String(repeating: "<officeooo:annotation office:name=\"x\" loext:parent-name=\"x\"><text:p>x</text:p></officeooo:annotation>", count: 3_000)
                let deep = String(repeating: "<text:list><text:list-item>", count: 300)
                text = text.replacingOccurrences(of: "</draw:page>", with: many + "<officeooo:annotation>\(deep)</officeooo:annotation></draw:page>")
            }
            var damaged = parts
            damaged["content.xml"] = Data(text.utf8)
            ODPFuzzTests.survives(try ODPTestPackage.zip(damaged))
        }
    }
}
