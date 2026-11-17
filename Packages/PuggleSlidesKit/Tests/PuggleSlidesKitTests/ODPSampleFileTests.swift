import Foundation
import Testing
@testable import PuggleSlidesKit

/// Writes the sample decks to the folder in `PUGGLESLIDES_ODP_SAMPLES`, for checking them in other apps (LibreOffice,
/// schema validation). Skipped unless the variable is set.
struct ODPSampleFileTests {
    static let folder = ProcessInfo.processInfo.environment["PUGGLESLIDES_ODP_SAMPLES"]

    @Test(.enabled(if: folder != nil))
    func writeSampleDecks() throws {
        let folder = URL(fileURLWithPath: try #require(Self.folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decks: [(String, Presentation)] = [
            ("default", Presentation.makeDefault()),
            ("all-themes", ODPSamples.allThemes()),
            ("rich", ODPSamples.rich()),
            ("objects", ODPSamples.objects()),
            ("media", PPTXMediaTests.deck()),
        ]
        for (name, deck) in decks {
            try PresentationIO.write(deck, format: .odp).write(to: folder.appendingPathComponent(name + ".odp"))
        }
        // LibreOffice's file, written again.
        let fixture = try PresentationIO.read(try ODPLibreOfficeFixture.package(), format: .odp).presentation
        try PresentationIO.write(fixture, format: .odp).write(to: folder.appendingPathComponent("fixture-again.odp"))
    }
}
