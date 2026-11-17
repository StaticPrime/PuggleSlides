import Foundation
import Testing
@testable import PuggleSlidesKit

/// Damaged files either read or fail with a message; they never crash. What does read also writes, and reads again.
struct ODPFuzzTests {
    /// Reads `data`; returns whether it read. Anything thrown must be a friendly error.
    @discardableResult
    static func survives(_ data: Data) -> Bool {
        do {
            let file = try PresentationIO.read(data, format: .odp)
            let written = try PresentationIO.write(file.presentation, format: .odp)
            _ = try PresentationIO.read(written, format: .odp)
            return true
        } catch let error as PresentationIOError {
            #expect(!(error.errorDescription ?? "").isEmpty)
            return false
        } catch {
            Issue.record("unexpected error \(error)")
            return false
        }
    }

    @Test func survivesRandomByteDamageAndTruncation() throws {
        let originals = [try ODPWriter.write(ODPSamples.rich()), try ODPWriter.write(ODPSamples.objects())]
        var random = ODPTestRandom(seed: 2026)
        for iteration in 0..<400 {
            var damaged = originals[iteration % originals.count]
            for _ in 0..<(1 + random.below(8)) {
                damaged[random.below(damaged.count)] = UInt8(truncatingIfNeeded: random.next())
            }
            if random.below(4) == 0 { damaged = Data(damaged.prefix(random.below(damaged.count))) }
            Self.survives(damaged)
        }
    }

    /// Damage inside each part's XML, with fragments chosen to reach awkward corners of the reader.
    @Test func survivesDamagedXML() throws {
        let fragments = [
            "<draw:frame>", "</draw:frame>", "<draw:g>", "</draw:g>", "<text:list>", "</text:list>", "<text:list-item>", "<text:span>", "</text:p>",
            "svg:width=\"1e308pt\"", "svg:x=\"-99999999999999999999in\"", "svg:height=\"NaN\"", "draw:transform=\"rotate (1e300) translate (nan inf)\"",
            "draw:transform=\"matrix(1 2 3 4 5 6) skewX(9) scale(0 0)\"", "draw:enhanced-path=\"M ?f0 ?f1 L $9 $0 G 1e308 1e308 1e308 -1e308 T 0 0 1e300 1e300 0 1e300 Z N\"",
            "<draw:equation draw:name=\"f0\" draw:formula=\"?f0*?f1+sqrt(-1)/0+atan2(1)+if(\"/>", "<draw:equation draw:name=\"f1\" draw:formula=\"((((((((\"/>",
            "draw:modifiers=\"1e999 -1e300 x\"", "svg:viewBox=\"0 0 0 0\"", "draw:type=\"ooxml-\"", "draw:type=\"round-rectangle\"",
            "fo:font-size=\"-5pt\"", "fo:font-size=\"1e9%\"", "fo:line-height=\"1e30%\"", "fo:margin-left=\"1e300cm\"", "fo:clip=\"rect(1e300cm, -1cm, x, 2cm)\"",
            "draw:angle=\"1e308deg\"", "smil:dur=\"1e308s\"", "smil:begin=\"-5s\"", "smil:targetElement=\"page1\"", "text:c=\"999999999\"",
            "text:start-value=\"-7\"", "text:level=\"0\"", "style:parent-style-name=\"pr1\"", "style:parent-style-name=\"Simple_20_Light-outline9\"",
            "presentation:class=\"notes\"", "presentation:class=\"page-number\"", "xlink:href=\"../../etc/passwd\"", "xlink:href=\"#page999\"",
            "xlink:href=\"http://example.com/x.png\"", "&amp;", "<![CDATA[<x>]]>", "draw:points=\"1,2,3\"", "svg:d=\"M1 1 A 1e308 0 0 1 1 5 5 Z\"",
            "<anim:par presentation:node-type=\"main-sequence\"><anim:par><anim:set smil:targetElement=\"s3e1\"/></anim:par></anim:par>",
            "<anim:par presentation:preset-class=\"motion-path\"/>", "<table:table/>", "<draw:object xlink:href=\"./Object 1\"/>", "<office:annotation/>",
            "<draw:image xlink:href=\"Pictures/image1.png\"/>", "<text:page-number/>", "<presentation:date-time/>", "style:mirror=\"horizontal vertical\"",
            // Tables, charts, word art, picture adjustments and guides.
            "<table:table-cell table:number-columns-spanned=\"999999\" table:number-rows-spanned=\"-1\">", "table:number-columns-repeated=\"2147483648\"",
            "table:number-rows-repeated=\"99999999\"", "<table:covered-table-cell/>", "</table:table-row>", "<table:table-row>", "</table:table>",
            "fo:border=\"1e308pt solid #zzzzzz\"", "fo:border-top=\"none\"", "fo:padding=\"-5cm\"", "style:column-width=\"-1cm\"", "style:row-height=\"1e300in\"",
            "table:template-name=\"default\" table:use-banding-rows-styles=\"true\" table:use-first-row-styles=\"true\"", "style:vertical-align=\"automatic\"",
            "<style:background-image xlink:href=\"../x\"/>", "chart:values-cell-range-address=\"local-table.$ZZZZZ$99999999:.$A$1 '':.$:\"",
            "chart:label-cell-address=\"''''.\"", "chart:class=\"chart:\"", "<chart:series/>", "<chart:domain/>", "office:value=\"1e999\"", "office:value=\"-NaN\"",
            "chart:hole-size=\"1e9%\"", "<chart:legend chart:legend-position=\"bottom-end\"/>", "draw:type=\"fontwork-wave\" draw:text-path=\"true\"",
            "draw:image-opacity=\"-50%\" draw:luminance=\"1e300%\" draw:color-mode=\"watermark\"", "draw:color-inversion=\"maybe\"",
            "xlink:href=\"./Object 999\"", "xlink:href=\"./Object 2/../Object 3\"",
            "<config:config-item config:name=\"SnapLinesDrawing\" config:type=\"string\">V99999999999999999H-P1,V</config:config-item>",
        ]
        var random = ODPTestRandom(seed: 99)
        func mutated(_ text: String) -> String {
            var scalars = Array(text.unicodeScalars)
            for _ in 0..<(1 + random.below(4)) {
                let position = random.below(scalars.count + 1)
                switch random.below(3) {
                case 0:
                    let length = min(random.below(30), scalars.count - position)
                    scalars.removeSubrange(position..<(position + length))
                case 1:
                    scalars.insert(contentsOf: fragments[random.below(fragments.count)].unicodeScalars, at: position)
                default:
                    let length = min(random.below(60), scalars.count - position)
                    scalars.insert(contentsOf: scalars[position..<(position + length)], at: position)
                }
            }
            return String(String.UnicodeScalarView(scalars))
        }
        let packages = [try ODPTestPackage.parts(of: try ODPWriter.write(ODPSamples.rich())), try ODPTestPackage.parts(of: try ODPLibreOfficeFixture.package()),
                        try ODPTestPackage.parts(of: try ODPWriter.write(ODPSamples.objects()))]
        let targets = ["content.xml", "styles.xml", "META-INF/manifest.xml", "meta.xml", "Object 2/content.xml", "Object 14/content.xml", "settings.xml"]
        var readable = 0
        for iteration in 0..<700 {
            var parts = packages[iteration % packages.count]
            let target = targets[(iteration / packages.count) % targets.count]
            guard let original = parts[target] else { continue }
            parts[target] = Data(mutated(String(decoding: original, as: UTF8.self)).utf8)
            if Self.survives(try ODPTestPackage.zip(parts)) { readable += 1 }
        }
        // Some damage is harmless (inside text, or in parts read leniently).
        #expect(readable > 0)
    }

    @Test func deeplyNestedPartsAreRefusedWithoutCrashing() throws {
        var parts = try ODPTestPackage.parts(of: try ODPWriter.write(Presentation.makeDefault()))
        let depth = 100_000
        let nested = String(repeating: "<draw:g>", count: depth) + String(repeating: "</draw:g>", count: depth)
        let content = String(decoding: parts["content.xml"]!, as: UTF8.self).replacingOccurrences(of: "<presentation:notes>", with: nested + "<presentation:notes>")
        parts["content.xml"] = Data(content.utf8)
        #expect(throws: PresentationIOError.unreadable(ODPMessages.damaged)) {
            try PresentationIO.read(try ODPTestPackage.zip(parts), format: .odp)
        }

        // Groups nested deeper than any real deck, but within what XML allows, are cut off with a warning.
        var groups = try ODPTestPackage.parts(of: try ODPWriter.write(Presentation.makeDefault()))
        let shape = "<draw:custom-shape svg:x=\"0pt\" svg:y=\"0pt\" svg:width=\"10pt\" svg:height=\"10pt\"><draw:enhanced-geometry draw:type=\"rectangle\"/></draw:custom-shape>"
        let deep = String(repeating: "<draw:g>", count: 60) + shape + String(repeating: "</draw:g>", count: 60)
        let text = String(decoding: groups["content.xml"]!, as: UTF8.self).replacingOccurrences(of: "<presentation:notes>", with: deep + "<presentation:notes>")
        groups["content.xml"] = Data(text.utf8)
        let file = try PresentationIO.read(try ODPTestPackage.zip(groups), format: .odp)
        #expect(file.warnings == [.otherContent])

        // Text lists nested past any real use stop at the deepest level the model has.
        var lists = try ODPTestPackage.parts(of: try ODPWriter.write(Presentation.makeDefault()))
        let list = String(repeating: "<text:list><text:list-item>", count: 50) + "<text:p>deep</text:p>" + String(repeating: "</text:list-item></text:list>", count: 50)
        let listed = String(decoding: lists["content.xml"]!, as: UTF8.self).replacingOccurrences(of: "<draw:text-box><text:p", with: "<draw:text-box>\(list)<text:p")
        lists["content.xml"] = Data(listed.utf8)
        let listFile = try PresentationIO.read(try ODPTestPackage.zip(lists), format: .odp)
        let paragraphs = listFile.presentation.slides[0].elements[0].shape?.text?.paragraphs ?? []
        #expect(paragraphs.first?.text == "deep")
        #expect(paragraphs.first?.level == 8)
    }

    @Test func oversizedPartsAreRefused() throws {
        var parts = try ODPTestPackage.parts(of: try ODPWriter.write(Presentation.makeDefault()))
        parts["content.xml"] = Data(count: ODPDocumentReader.maxXMLPartSize + 1)
        #expect(throws: PresentationIOError.unreadable(ODPMessages.tooLarge)) {
            try PresentationIO.read(try ODPTestPackage.zip(parts), format: .odp)
        }
    }
}
