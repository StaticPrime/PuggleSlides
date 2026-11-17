import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct XMLTreeTests {
    @Test func parsesElementsTextAndAttributes() throws {
        let root = try XMLTree.parse(Data(#"<a:p xmlns:a="x"><a:r><a:t lang="en">Hi</a:t></a:r></a:p>"#.utf8))
        #expect(root.name == "p")
        #expect(root.firstDescendant("t")?.text == "Hi")
        #expect(root.firstDescendant("t")?.attributes["lang"] == "en")
    }

    @Test func refusesNestingTooDeepToFreeSafely() {
        let depth = 50_000
        let xml = String(repeating: "<a>", count: depth) + String(repeating: "</a>", count: depth)
        #expect(throws: MalformedXMLError.self) { try XMLTree.parse(Data(xml.utf8)) }
        let fine = String(repeating: "<a>", count: 200) + String(repeating: "</a>", count: 200)
        #expect((try? XMLTree.parse(Data(fine.utf8))) != nil)
    }

    @Test func skippedElementsKeepTheirEndsToThemselves() {
        // A streamed element goes on receiving events past the limit: the ends of the elements it skipped
        // mustn't close the ones it kept, or text and later elements land in the wrong place.
        let builder = XNodeBuilder(rootName: "root", attributes: [:])
        let nested = XNodeBuilder.maximumDepth + 9
        for _ in 0..<nested { builder.start("a", [:]) }
        builder.characters("skipped")
        var rootClosed = false
        for _ in 0..<nested { rootClosed = builder.end() || rootClosed }
        #expect(builder.isTooDeep)
        #expect(!rootClosed)
        #expect(builder.end())
        var depth = 0
        var deepest = builder.root
        while let child = deepest?.children.first {
            depth += 1
            deepest = child
        }
        #expect(depth == XNodeBuilder.maximumDepth - 1)
        #expect(deepest?.text == "")
    }
}
