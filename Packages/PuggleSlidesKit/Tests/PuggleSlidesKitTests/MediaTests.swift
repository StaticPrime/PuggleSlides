import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct MediaTests {
    private static func bytes(_ text: String, padTo count: Int = 16) -> Data {
        var data = Data(text.utf8)
        while data.count < count { data.append(0) }
        return data
    }

    @Test func moviesAndSoundsAreRecognized() {
        // MPEG-4 and QuickTime boxes: the size, then "ftyp" and a brand.
        #expect(MediaItem.contentType(sniffing: Data([0, 0, 0, 0x20]) + Self.bytes("ftypisom")) == "video/mp4")
        #expect(MediaItem.contentType(sniffing: Data([0, 0, 0, 0x14]) + Self.bytes("ftypqt  ")) == "video/quicktime")
        #expect(MediaItem.contentType(sniffing: Data([0, 0, 0, 0x20]) + Self.bytes("ftypM4A ")) == "audio/mp4")
        #expect(MediaItem.contentType(sniffing: Data([0, 0, 0, 0x08]) + Self.bytes("wide")) == "video/quicktime")
        // HEIF pictures share the box, and aren't movies.
        #expect(MediaItem.contentType(sniffing: Data([0, 0, 0, 0x18]) + Self.bytes("ftypheic")) == nil)
        #expect(MediaItem.contentType(sniffing: Self.bytes("RIFF\u{24}\0\0\0WAVEfmt ")) == "audio/wav")
        #expect(MediaItem.contentType(sniffing: Self.bytes("FORM\0\0\0\u{20}AIFFCOMM")) == "audio/aiff")
        #expect(MediaItem.contentType(sniffing: Self.bytes("ID3\u{4}\0\0\0\0")) == "audio/mpeg")
        #expect(MediaItem.contentType(sniffing: Data([0xFF, 0xFB, 0x90, 0x64]) + Data(count: 12)) == "audio/mpeg")
        // Pictures are still pictures.
        #expect(MediaItem.contentType(sniffing: Data([0x89, 0x50, 0x4E, 0x47]) + Data(count: 12)) == "image/png")
        #expect(MediaItem(data: Data(), contentType: "video/quicktime").fileExtension == "mov")
        #expect(MediaItem(data: Data(), contentType: "audio/mpeg").fileExtension == "mp3")
        #expect(MediaItem(data: Data(), contentType: "audio/mpeg").isAudio && MediaItem(data: Data(), contentType: "video/mp4").isVideo)
    }

    @Test func clipsKeepTheirSettingsAndMedia() throws {
        let movie: MediaID = "movie", poster: MediaID = "poster"
        let clip = MediaClip(kind: .video, mediaID: movie, posterID: poster, playback: .automatically, start: 1.5, end: 4,
                             volume: 0.5, isMuted: true)
        #expect(clip.mediaIDs == [movie, poster])
        let element = SlideElement(placement: Placement(frame: SlideRect(x: 0, y: 0, width: 320, height: 180)), content: .media(clip))
        #expect(element.media == clip && element.mediaIDs == [movie, poster])
        let decoded = try JSONDecoder().decode(SlideElement.self, from: try JSONEncoder().encode(element))
        #expect(decoded == element)
        // A sound starts on click, stops when the slide changes and shows its icon unless told otherwise.
        let sound = MediaClip(kind: .audio, mediaID: movie)
        #expect(sound.playback == .onClick && sound.stopsOnSlideChange && !sound.hidesWhenPresenting && !sound.loops && sound.volume == 1)
    }

    @Test func trimsStayInsideTheFile() {
        let clip = MediaClip(kind: .video, mediaID: "clip", start: 2, end: 30)
        #expect(clip.playRange(duration: 10) == 2...10)
        #expect(MediaClip(kind: .video, mediaID: "clip").playRange(duration: 10) == 0...10)
        #expect(MediaClip(kind: .video, mediaID: "clip", start: 8, end: 3).playRange(duration: 10) == 8...8)
        #expect(MediaClip(kind: .audio, mediaID: "sound", start: -4).playRange(duration: .nan) == 0...0)
    }

    @Test func mediaObjectsAreScaledAndNeverSearched() {
        var element = SlideElement(placement: Placement(frame: SlideRect(x: 10, y: 10, width: 100, height: 50)),
                                   content: .media(MediaClip(kind: .video, mediaID: "clip")))
        element.scale(x: 2, y: 2)
        #expect(element.placement?.frame == SlideRect(x: 20, y: 20, width: 200, height: 100))
        var presentation = Presentation.makeDefault()
        presentation.slides[0].elements.append(element)
        #expect(presentation.matches(of: TextSearch("video")).isEmpty)
    }
}
