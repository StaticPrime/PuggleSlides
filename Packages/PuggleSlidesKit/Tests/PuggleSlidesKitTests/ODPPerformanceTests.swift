import Foundation
import Testing
@testable import PuggleSlidesKit

/// Speed checks with generous limits. The meaningful numbers come from `swift test -c release`;
/// debug builds only get a sanity limit.
struct ODPPerformanceTests {
    #if DEBUG
    static let limit: Duration = .seconds(30)
    #else
    static let limit: Duration = .seconds(1)
    #endif

    @Test func writesAndReadsTwoHundredSlides() throws {
        let presentation = ODPSamples.large(slides: 200)
        let clock = ContinuousClock()
        var data = Data()
        let writing = try clock.measure { data = try PresentationIO.write(presentation, format: .odp) }
        var file: PresentationFile?
        let reading = try clock.measure { file = try PresentationIO.read(data, format: .odp) }
        print("200 slides: wrote \(data.count / 1024) KB in \(writing), read in \(reading)")
        #expect(writing < Self.limit)
        #expect(reading < Self.limit)
        let read = try #require(file).presentation
        #expect(read.slides.count == 200)
        #expect(read.slides[199].elements.count == presentation.slides[199].elements.count)
        #expect(read.slides[199].notes.plainText == "Notes for slide 200")
        #expect(read.slides[199].animations.count == 1)
        #expect(read.slides[199].transition?.kind == .fade)
    }
}
