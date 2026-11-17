import Foundation
import Testing
@testable import PuggleSlidesKit

/// Writes the sample decks to the folder in `PUGGLESLIDES_PPTX_SAMPLES`, for checking them in other apps
/// (Quick Look, schema validation). Skipped unless the variable is set.
struct PPTXSampleFileTests {
    static let folder = ProcessInfo.processInfo.environment["PUGGLESLIDES_PPTX_SAMPLES"]

    @Test(.enabled(if: folder != nil))
    func writeSampleDecks() throws {
        let folder = URL(fileURLWithPath: try #require(Self.folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decks: [(String, Presentation)] = [
            ("default", Presentation.makeDefault()),
            ("all-themes", PPTXSamples.allThemes()),
            ("rich", PPTXSamples.rich()),
            ("objects", PPTXSamples.objects()),
            ("media", PPTXMediaTests.deck()),
        ] + BuiltInThemes.designs.map { ("theme-\($0.name.replacingOccurrences(of: " ", with: "-").lowercased())", PPTXSamples.themeShowcase($0)) }
        for (name, deck) in decks {
            try PresentationIO.write(deck, format: .pptx).write(to: folder.appendingPathComponent(name + ".pptx"))
        }
        // Decks read from other apps' files, written again.
        let imports: [(String, PPTXTestPackage)] = [("import-powerpoint", PPTXReadTests.powerPointPackage()),
                                                     ("import-exported", PPTXReadTests.exportedPackage()),
                                                     ("import-color-map", PPTXReadTests.colorMapOverridePackage()),
                                                     ("import-table-style", PPTXTableTests.defaultStylePackage()),
                                                     ("import-custom-table-style", PPTXTableTests.customStylePackage()),
                                                     ("import-charts", PPTXChartTests.powerPointChartsPackage())]
        for (name, package) in imports {
            let presentation = try PPTXTestPackage.read(try package.data()).presentation
            try PresentationIO.write(presentation, format: .pptx).write(to: folder.appendingPathComponent(name + ".pptx"))
        }
        let media = try PPTXTestPackage.read(try PPTXMediaTests.powerPointPackage()).presentation
        try PresentationIO.write(media, format: .pptx).write(to: folder.appendingPathComponent("import-media.pptx"))
        // Quick Look shows a deck's first slide: one file per slide of the rich and objects decks, with that slide first.
        for (name, source) in [("rich", PPTXSamples.rich()), ("objects", PPTXSamples.objects())] {
            for index in source.slides.indices {
                var deck = source
                deck.slides.insert(deck.slides.remove(at: index), at: 0)
                deck.slides[0].isSkipped = false
                try PresentationIO.write(deck, format: .pptx).write(to: folder.appendingPathComponent("\(name)-slide\(index + 1).pptx"))
            }
        }
    }
}
