import Foundation
import ImageIO
import Testing
@testable import PuggleSlidesKit

/// Tiny movies and sounds: only the headers their kind and length are read from, and a little padding. Nothing plays.
enum MediaTestFiles {
    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    /// An MPEG-4 file (a QuickTime movie with brand "qt  ", a sound with "M4A ") lasting `seconds`: `ftyp`, then `moov`
    /// holding a movie header of version 0 or 1, then a little `mdat`.
    static func movie(seconds: Double, brand: String = "isom", version: UInt8 = 0) -> Data {
        var data = bigEndian(UInt32(20)) + Data("ftyp".utf8) + Data(brand.utf8) + bigEndian(UInt32(0)) + Data(brand.utf8)
        var header = Data([version, 0, 0, 0])
        if version == 1 {
            header += bigEndian(UInt64(0)) + bigEndian(UInt64(0)) + bigEndian(UInt32(600)) + bigEndian(UInt64(seconds * 600))
        } else {
            header += bigEndian(UInt32(0)) + bigEndian(UInt32(0)) + bigEndian(UInt32(1000)) + bigEndian(UInt32(seconds * 1000))
        }
        header += Data(count: 80)
        let mvhd = bigEndian(UInt32(8 + header.count)) + Data("mvhd".utf8) + header
        data += bigEndian(UInt32(8 + mvhd.count)) + Data("moov".utf8) + mvhd
        data += bigEndian(UInt32(16)) + Data("mdat".utf8) + Data(count: 8)
        return data
    }

    /// A WAV sound: 8-bit mono PCM at 100 samples a second.
    static func wave(seconds: Double) -> Data {
        let samples = Int(seconds * 100)
        var data = Data("RIFF".utf8) + littleEndian(UInt32(36 + samples)) + Data("WAVEfmt ".utf8) + littleEndian(UInt32(16))
        data += littleEndian(UInt16(1)) + littleEndian(UInt16(1)) + littleEndian(UInt32(100)) + littleEndian(UInt32(100))
        data += littleEndian(UInt16(1)) + littleEndian(UInt16(8)) + Data("data".utf8) + littleEndian(UInt32(samples))
        return data + Data(repeating: 0x80, count: samples)
    }

    /// An AIFF sound: 1,000 frames a second, the rate as an 80-bit float.
    static func aiff(seconds: Double) -> Data {
        let frames = UInt32(seconds * 1000)
        // 1000 = 1.953125 × 2^9: exponent 16383 + 9, mantissa 1000 << 54.
        let rate = bigEndian(UInt16(16383 + 9)) + bigEndian(UInt64(1000) << 54)
        let common = Data("COMM".utf8) + bigEndian(UInt32(18)) + bigEndian(UInt16(1)) + bigEndian(frames) + bigEndian(UInt16(8)) + rate
        return Data("FORM".utf8) + bigEndian(UInt32(4 + common.count)) + Data("AIFF".utf8) + common
    }

    /// An MP3 sound at a constant 32 kbit/s (MPEG-1 layer III, 32 kHz, mono): its frames are 4,000 bytes a second.
    static func mp3(seconds: Double) -> Data {
        Data([0xFF, 0xFB, 0x18, 0xC4]) + Data(count: Int(seconds * 4000) - 4)
    }
}

/// Videos and sounds in PowerPoint files: written as PowerPoint 2010 and later embed them, read back with every setting,
/// and read from files shaped like PowerPoint's.
struct PPTXMediaTests {
    static let photo = PPTXSamples.photo
    static let icon = PPTXTestImage.png(width: 4, height: 4) { _, _ in (40, 40, 200) }

    static func clip(_ name: String, _ frame: SlideRect, _ clip: MediaClip) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: frame), content: .media(clip))
    }

    /// Videos and sounds with every setting and playback, posters and none, trims, a clip in a group and animations around them.
    static func deck() -> Presentation {
        var presentation = Presentation.makeDefault()
        let blank = presentation.themes[0].layout(kind: .blank)!.id
        let movie = presentation.addMedia(MediaTestFiles.movie(seconds: 12), contentType: "video/mp4")
        let quickTime = presentation.addMedia(MediaTestFiles.movie(seconds: 30, brand: "qt  ", version: 1), contentType: "video/quicktime")
        let song = presentation.addMedia(MediaTestFiles.mp3(seconds: 2), contentType: "audio/mpeg")
        let wave = presentation.addMedia(MediaTestFiles.wave(seconds: 3), contentType: "audio/x-wav")
        let chime = presentation.addMedia(MediaTestFiles.aiff(seconds: 1.5), contentType: "audio/aiff")
        let melody = presentation.addMedia(MediaTestFiles.movie(seconds: 4, brand: "M4A "), contentType: "audio/mp4")
        let poster = presentation.addMedia(Self.photo, contentType: "image/png")
        let icon = presentation.addMedia(Self.icon, contentType: "image/png")

        var videos = presentation.makeSlide(layoutID: blank)
        let title = SlideElement(name: "Title", placement: Placement(frame: SlideRect(x: 20, y: 10, width: 400, height: 40)),
                                 content: .shape(Shape(text: TextBody("Videos"), isTextBox: true)))
        let box = SlideElement(name: "Box", placement: Placement(frame: SlideRect(x: 500, y: 300, width: 100, height: 60)),
                               content: .shape(Shape(geometry: .preset("ellipse", adjustments: [:]), fill: .solid(ColorRef(theme: .accent2)))))
        let first = clip("Opening", SlideRect(x: 20, y: 60, width: 320, height: 180),
                         MediaClip(kind: .video, mediaID: movie, posterID: poster, playback: .automatically, start: 1.5, end: 9.25, volume: 0.5,
                                   loops: true, hidesWhenPresenting: true))
        let second = clip("Interview", SlideRect(x: 360, y: 60, width: 320, height: 180),
                          MediaClip(kind: .video, mediaID: quickTime, playback: .onClick, end: 20, isMuted: true))
        let third = clip("Outtakes", SlideRect(x: 20, y: 260, width: 240, height: 135),
                         MediaClip(kind: .video, mediaID: movie, posterID: poster, playback: .manually, start: 0.25, volume: 0))
        videos.elements = [title, first, second, third, box]
        videos.animations = [SlideAnimation(elementID: title.id, effect: .fadeIn, start: .onClick),
                             SlideAnimation(elementID: box.id, effect: .flyInFromLeft, start: .afterPrevious, duration: 0.75),
                             SlideAnimation(elementID: third.id, effect: .appear, start: .withPrevious, delay: 0.5),
                             SlideAnimation(elementID: box.id, effect: .spin, start: .onClick, duration: 1)]

        var sounds = presentation.makeSlide(layoutID: blank)
        let background = clip("Background", SlideRect(x: 20, y: 20, width: audioIconSize, height: audioIconSize),
                              MediaClip(kind: .audio, mediaID: song, playback: .automatically, volume: 0.8, loops: true, hidesWhenPresenting: true,
                                        stopsOnSlideChange: false))
        let cue = clip("Cue", SlideRect(x: 80, y: 20, width: 48, height: 48),
                       MediaClip(kind: .audio, mediaID: wave, posterID: icon, playback: .onClick, start: 0.25, end: 2.5, volume: 0.3))
        let bell = clip("Bell", SlideRect(x: 140, y: 20, width: audioIconSize, height: audioIconSize),
                        MediaClip(kind: .audio, mediaID: chime, playback: .manually, isMuted: true))
        let note = clip("Note", SlideRect(x: 200, y: 200, width: audioIconSize, height: audioIconSize),
                        MediaClip(kind: .audio, mediaID: melody, playback: .onClick, end: 3))
        let label = SlideElement(name: "Label", placement: Placement(frame: SlideRect(x: 240, y: 200, width: 120, height: 30)),
                                 content: .shape(Shape(text: TextBody("Listen"), isTextBox: true)))
        let group = SlideElement(name: "Grouped sound", placement: Placement(frame: SlideRect(x: 200, y: 200, width: 160, height: 30)),
                                 content: .group([note, label]))
        sounds.elements = [background, cue, bell, group]
        sounds.animations = [SlideAnimation(elementID: group.id, effect: .fadeIn, start: .withPrevious)]

        // A slide with just a manual video: timing holds only its trigger and media node.
        var plain = presentation.makeSlide(layoutID: blank)
        plain.elements = [clip("Loop", SlideRect(x: 100, y: 100, width: 160, height: 90),
                               MediaClip(kind: .video, mediaID: movie, playback: .manually, loops: true))]
        presentation.slides = [videos, sounds, plain]
        return presentation
    }

    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        try PresentationIO.read(try PresentationIO.write(presentation, format: .pptx), format: .pptx)
    }

    static func text(_ path: String, _ parts: [String: Data]) -> String {
        parts[path].map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    // MARK: Round trips

    @Test func clipsRoundTripWithEverySetting() throws {
        let original = Self.deck()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        // Spot checks on what the canonical comparison rounds.
        let read = file.presentation
        let opening = try #require(read.slides[0].elements[1].media)
        #expect(opening.playback == .automatically && opening.start == 1.5 && opening.end == 9.25 && opening.volume == 0.5)
        let openingPoster = try #require(opening.posterID)
        #expect(opening.loops && opening.hidesWhenPresenting && read.media[openingPoster]?.data == Self.photo)
        #expect(read.slides[0].elements[2].media?.posterID == nil && read.slides[0].elements[2].media?.end == 20)
        #expect(read.slides[1].elements[0].media?.stopsOnSlideChange == false)
        #expect(read.slides[1].elements[3].children?[0].media?.playback == .onClick)
        #expect(read.media[opening.mediaID]?.contentType == "video/mp4")
        // Animations around the clips keep their clicks.
        #expect(read.slides[0].animations.map(\.start) == [.onClick, .afterPrevious, .withPrevious, .onClick])
        #expect(read.slides[1].animations.map(\.start) == [.withPrevious])
        // And again: the second file is the same as the first.
        let again = try Self.roundTrip(read)
        let second = PPTXCanonical.difference(read, again.presentation)
        #expect(second == nil, "\(second ?? "")")
    }

    @Test func sampleDecksKeepTheirClips() throws {
        let original = PPTXSamples.objects()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        let difference = PPTXCanonical.difference(original, file.presentation)
        #expect(difference == nil, "\(difference ?? "")")
        #expect(file.presentation.slides.flatMap(\.elements).contains { $0.media != nil })
    }

    @Test func clipsOnLayoutsStayClips() throws {
        var presentation = Presentation.makeDefault()
        let movie = presentation.addMedia(MediaTestFiles.movie(seconds: 6), contentType: "video/mp4")
        let index = try #require(presentation.themes[0].layouts.firstIndex { $0.kind == .blank })
        presentation.themes[0].layouts[index].elements.append(Self.clip("Backdrop", SlideRect(x: 0, y: 0, width: 160, height: 90),
                                                                        MediaClip(kind: .video, mediaID: movie, start: 1, end: 5, loops: true)))
        for format in [PresentationFormat.pptx, .odp] {
            let file = try PresentationIO.read(try PresentationIO.write(presentation, format: format), format: format)
            #expect(file.warnings.isEmpty, "\(format) \(file.warnings)")
            let layout = try #require(file.presentation.themes[0].layouts.first { $0.kind == .blank })
            let clip = try #require(layout.elements.compactMap(\.media).first)
            // The media and its trim are kept; PowerPoint layouts have no timing for the rest.
            #expect(file.presentation.media[clip.mediaID]?.data == presentation.media[movie]?.data && clip.start == 1 && clip.end == 5)
            #expect(clip.loops == (format == .odp))
        }
    }

    // MARK: Markup

    @Test func clipsAreWrittenAsPowerPointWritesThem() throws {
        let parts = try PPTXTestPackage.parts(of: try PresentationIO.write(Self.deck(), format: .pptx))
        let slide = Self.text("ppt/slides/slide1.xml", parts)
        let relationships = Self.text("ppt/slides/_rels/slide1.xml.rels", parts)
        let types = Self.text("[Content_Types].xml", parts)
        // The picture: the media click action, the linked file, the embedded media with its trim, the poster.
        #expect(slide.contains("<a:hlinkClick r:id=\"\" action=\"ppaction://media\"/>"))
        #expect(slide.contains("<a:videoFile r:link=\"rId"))
        #expect(slide.contains("<p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}\"><p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"rId"))
        // 1.5 s from the start; 12 s long, ending at 9.25 s, is 2.75 s from the end.
        #expect(slide.contains("<p14:trim st=\"1500\" end=\"2750\"/>"))
        // The QuickTime movie is 30 s; ending at 20 s cuts 10 s.
        #expect(slide.contains("<p14:trim end=\"10000\"/>"))
        #expect(slide.contains("<p14:trim st=\"250\"/>"))
        #expect(relationships.contains("Type=\"http://schemas.microsoft.com/office/2007/relationships/media\" Target=\"../media/media1.mp4\""))
        #expect(relationships.contains("Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/video\" Target=\"../media/media1.mp4\""))
        #expect(relationships.contains("Target=\"../media/media2.mov\""))
        #expect(Self.text("ppt/slides/_rels/slide2.xml.rels", parts).contains("Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/audio\""))
        for (fileExtension, type) in [("mp4", "video/mp4"), ("mov", "video/quicktime"), ("mp3", "audio/mpeg"), ("wav", "audio/wav"), ("aiff", "audio/aiff"),
                                      ("m4a", "audio/mp4")] {
            #expect(types.contains("<Default Extension=\"\(fileExtension)\" ContentType=\"\(type)\"/>"), "\(fileExtension)")
        }
        #expect(!types.contains("Override PartName=\"/ppt/media/media"))
        // Timing: the automatic video plays with the slide, the on-click one after the animations, the manual one when clicked.
        #expect(slide.contains("<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>"))
        #expect(slide.contains("presetID=\"1\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"withEffect\""))
        #expect(slide.contains("presetID=\"1\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"clickEffect\""))
        #expect(slide.contains("<p:cmd type=\"call\" cmd=\"playFrom(0.0)\">"))
        #expect(slide.contains("nodeType=\"interactiveSeq\"><p:stCondLst><p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"5\"/>"))
        #expect(slide.contains("<p:cmd type=\"call\" cmd=\"togglePause\">"))
        // Media nodes: volume, mute, loop and whether it shows while stopped.
        #expect(slide.contains("<p:video><p:cMediaNode vol=\"50000\" showWhenStopped=\"0\"><p:cTn id=\""))
        #expect(slide.contains("repeatCount=\"indefinite\" fill=\"hold\" display=\"0\""))
        #expect(slide.contains("<p:cMediaNode vol=\"100000\" mute=\"1\">"))
        #expect(slide.contains("<p:cMediaNode vol=\"0\">"))
        // A sound across slides: 999 slides, ended by a stop-audio event.
        let sounds = Self.text("ppt/slides/slide2.xml", parts)
        #expect(sounds.contains("<p:audio><p:cMediaNode vol=\"80000\" numSld=\"999\" showWhenStopped=\"0\">"))
        #expect(sounds.contains("<p:endCondLst><p:cond evt=\"onStopAudio\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:endCondLst>"))
        #expect(sounds.contains("<a:audioFile r:link=\"rId"))
        // Media is stored as it is: movies and compressed sounds aren't deflated again.
        let archive = try ZipReader(data: try PresentationIO.write(Self.deck(), format: .pptx))
        #expect(archive.entry("ppt/media/media1.mp4")?.method == 0 && archive.entry("ppt/media/media3.mp3")?.method == 0)
    }

    @Test func clipsWithoutPostersShowDefaultPictures() throws {
        var presentation = Self.deck()
        presentation.slides[1].elements[1].media?.posterID = nil
        let data = try PresentationIO.write(presentation, format: .pptx)
        let parts = try PPTXTestPackage.parts(of: data)
        // One picture per kind, shared by every clip without a poster.
        let pictures = parts.filter { $0.key.hasPrefix("ppt/media/image") }.map(\.value)
        #expect(pictures.filter { $0 == MediaPictures.videoPoster }.count == 1)
        #expect(pictures.filter { $0 == MediaPictures.soundIcon }.count == 1)
        #expect(MediaPictures.isDefault(MediaPictures.videoPoster) && MediaPictures.isDefault(MediaPictures.soundIcon))
        #expect(!MediaPictures.isDefault(Self.photo))
        // They say what they are, so they're recognized however a later system encodes them.
        func description(_ data: Data) -> String? {
            let properties = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
            return (properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGDescription] as? String
        }
        #expect(description(MediaPictures.videoPoster) == MediaPictures.videoDescription)
        #expect(description(MediaPictures.soundIcon) == MediaPictures.soundDescription)
        var reencoded = MediaPictures.videoPoster
        reencoded.append(contentsOf: [0])
        #expect(MediaPictures.isDefault(reencoded))
        // They're pictures, a dark frame and a speaker.
        let video = try #require(CGImageSourceCreateWithData(MediaPictures.videoPoster as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(video.width == 64 && video.height == 36)
        let sound = try #require(CGImageSourceCreateWithData(MediaPictures.soundIcon as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(sound.width == 128 && sound.height == 128)
        // Read back, the clips have no poster, and the default pictures aren't kept.
        let read = try PresentationIO.read(data, format: .pptx).presentation
        #expect(read.slides[1].elements[1].media?.posterID == nil && read.slides[0].elements[2].media?.posterID == nil)
        #expect(!read.media.values.contains { $0.data == MediaPictures.videoPoster || $0.data == MediaPictures.soundIcon })
    }

    // MARK: Lengths

    @Test func lengthsAreReadFromHeaders() {
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.movie(seconds: 12)) == 12)
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.movie(seconds: 30, brand: "qt  ", version: 1)) == 30)
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.wave(seconds: 3)) == 3)
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.aiff(seconds: 1.5)) == 1.5)
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.mp3(seconds: 2)) == 2)
        // A variable bit rate MP3 counts its frames: 100 frames of 1,152 samples at 32 kHz.
        var xing = Data([0xFF, 0xFB, 0x18, 0xC4]) + Data(count: 17) + Data("Xing".utf8) + Data([0, 0, 0, 1, 0, 0, 0, 100])
        xing += Data(count: 400)
        #expect(PPTXMediaDuration.seconds(of: xing) == 3.6)
        // Damaged and unknown files have no length.
        #expect(PPTXMediaDuration.seconds(of: Data()) == nil)
        #expect(PPTXMediaDuration.seconds(of: Data("not a movie at all".utf8)) == nil)
        #expect(PPTXMediaDuration.seconds(of: MediaTestFiles.movie(seconds: 12).prefix(40)) == nil)
        var huge = MediaTestFiles.movie(seconds: 12)
        huge.replaceSubrange(20..<24, with: [0xFF, 0xFF, 0xFF, 0xF0])
        #expect(PPTXMediaDuration.seconds(of: huge) == nil)
        #expect(PPTXMediaDuration.seconds(of: Data("RIFF".utf8) + Data(count: 4) + Data("WAVEdata".utf8) + Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(PPTXMediaDuration.seconds(of: PPTXSamples.photo) == nil)
    }

    @Test func otherMediaTypesKeepTheirKind() throws {
        var presentation = Presentation.makeDefault()
        let blank = presentation.themes[0].layout(kind: .blank)!.id
        var slide = presentation.makeSlide(layoutID: blank)
        for (index, type) in ["video/mpeg", "audio/ogg", "audio/flac", "video/webm", "video/x-ms-wmv", "audio/x-ms-wma"].enumerated() {
            let id = presentation.addMedia(Data("media \(index)".utf8), contentType: type)
            slide.elements.append(Self.clip("Clip \(index)", SlideRect(x: Double(index) * 50, y: 0, width: 40, height: 40),
                                            MediaClip(kind: type.hasPrefix("audio") ? .audio : .video, mediaID: id, playback: .onClick)))
        }
        presentation.slides = [slide]
        for format in [PresentationFormat.pptx, .odp] {
            let data = try PresentationIO.write(presentation, format: format)
            let names = try ZipReader(data: data).entries.map(\.path).filter { $0.hasPrefix("ppt/media/media") || $0.hasPrefix("Media/") }
            #expect(Set(names.map { $0.split(separator: ".").last.map(String.init) ?? "" }) == ["mpg", "ogg", "flac", "webm", "wmv", "wma"], "\(format)")
            let read = try PresentationIO.read(data, format: format).presentation
            let clips = read.slides[0].elements.compactMap(\.media)
            #expect(clips.map { read.media[$0.mediaID]?.contentType } == ["video/mpeg", "audio/ogg", "audio/flac", "video/webm", "video/x-ms-wmv", "audio/x-ms-wma"])
            #expect(clips.map(\.kind) == [.video, .audio, .audio, .video, .video, .audio])
        }
    }

    @Test func timeOffsetsAreParsedWithUnits() {
        #expect(PPTXMedia.milliseconds("18374.0515") == 18374.0515)
        #expect(PPTXMedia.milliseconds("1.5s") == 1500 && PPTXMedia.milliseconds("2min") == 120_000 && PPTXMedia.milliseconds("250ms") == 250)
        #expect(PPTXMedia.milliseconds("1h") == 3_600_000 && PPTXMedia.milliseconds("500µs") == 0.5)
        #expect(PPTXMedia.milliseconds("-3") == nil && PPTXMedia.milliseconds("NaN") == nil && PPTXMedia.milliseconds("") == nil)
        #expect(PPTXMedia.timeOffset(milliseconds: 2750) == "2750" && PPTXMedia.timeOffset(milliseconds: 1.25) == "1.25")
        #expect(PPTXMedia.timeOffset(milliseconds: .infinity) == "0" && PPTXMedia.timeOffset(milliseconds: 1e30) == "1000000000000")
    }

    // MARK: Reading PowerPoint's files

    static func pic(_ id: Int, _ name: String, file: String = "videoFile", link: String? = "rId3", embed: String? = "rId2", mediaLink: String? = nil,
                    poster: String? = "rId4", trim: String = "", x: Int = 0) -> String {
        let fileElement = link.map { "<a:\(file) r:link=\"\($0)\"/>" } ?? ""
        var media = ""
        if embed != nil || mediaLink != nil {
            media = "<p:extLst><p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}\"><p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\""
                + (embed.map { " r:embed=\"\($0)\"" } ?? "") + (mediaLink.map { " r:link=\"\($0)\"" } ?? "") + ">\(trim)</p14:media></p:ext></p:extLst>"
        }
        let blip = poster.map { "<a:blip r:embed=\"\($0)\"/>" } ?? "<a:blip/>"
        return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"><a:hlinkClick r:id=\"\" action=\"ppaction://media\"/></p:cNvPr>"
            + "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr>\(fileElement)\(media)</p:nvPr></p:nvPicPr>"
            + "<p:blipFill>\(blip)<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"0\"/>"
            + "<a:ext cx=\"3048000\" cy=\"1714500\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
    }

    static func command(_ id: Int, spid: Int, preset: Int, nodeType: String, command: String, duration: String = "1") -> String {
        "<p:par><p:cTn id=\"\(id)\" presetID=\"\(preset)\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"\(nodeType)\">"
            + "<p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:cmd type=\"call\" cmd=\"\(command)\"><p:cBhvr><p:cTn id=\"\(id + 1)\" "
            + "dur=\"\(duration)\" fill=\"hold\"/><p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl></p:cBhvr></p:cmd></p:childTnLst></p:cTn></p:par>"
    }

    /// The sequence PowerPoint triggers with a clip's click, which toggles it.
    static func trigger(_ id: Int, spid: Int) -> String {
        let target = "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl>"
        return "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"\(id)\" restart=\"whenNotActive\" fill=\"hold\" evtFilter=\"cancelBubble\" "
            + "nodeType=\"interactiveSeq\"><p:stCondLst><p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond></p:stCondLst><p:endSync evt=\"end\" "
            + "delay=\"0\"><p:rtn val=\"all\"/></p:endSync><p:childTnLst><p:par><p:cTn id=\"\(id + 1)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/>"
            + "</p:stCondLst><p:childTnLst><p:par><p:cTn id=\"\(id + 2)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
            + Self.command(id + 3, spid: spid, preset: 2, nodeType: "clickEffect", command: "togglePause")
            + "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn><p:nextCondLst><p:cond evt=\"onClick\" delay=\"0\">"
            + "\(target)</p:cond></p:nextCondLst></p:seq>"
    }

    static func mediaNode(_ id: Int, spid: Int, tag: String = "video", attributes: String = "vol=\"80000\"", timeNode: String = "fill=\"hold\" display=\"0\"",
                          end: String = "") -> String {
        "<p:\(tag)><p:cMediaNode \(attributes)><p:cTn id=\"\(id)\" \(timeNode)><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst>\(end)</p:cTn>"
            + "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl></p:cMediaNode></p:\(tag)>"
    }

    static func timing(main: String, rest: String) -> String {
        let sequence = main.isEmpty ? "" : "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(main)"
            + "</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
            + "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>"
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>\(sequence)\(rest)"
            + "</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
    }

    /// A click group (or, starting with the slide, the first group) holding one step of effects.
    static func group(_ id: Int, withSlide: Bool = false, _ effects: String) -> String {
        "<p:par><p:cTn id=\"\(id)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/>"
            + (withSlide ? "<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>" : "") + "</p:stCondLst><p:childTnLst>"
            + "<p:par><p:cTn id=\"\(id + 1)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>\(effects)"
            + "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>"
    }

    static func fade(_ id: Int, spid: Int, nodeType: String) -> String {
        "<p:par><p:cTn id=\"\(id)\" presetID=\"10\" presetClass=\"entr\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"\(nodeType)\"><p:stCondLst>"
            + "<p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"\(id + 1)\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/>"
            + "</p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName>"
            + "</p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set><p:animEffect transition=\"in\" filter=\"fade\"><p:cBhvr>"
            + "<p:cTn id=\"\(id + 2)\" dur=\"500\"/><p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:cTn></p:par>"
    }

    static let box = "<p:sp><p:nvSpPr><p:cNvPr id=\"9\" name=\"Box\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/>"
        + "<a:ext cx=\"100000\" cy=\"100000\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:sp>"

    static func powerPointPackage() throws -> Data {
        var package = PPTXTestPackage()
        let media = "http://schemas.microsoft.com/office/2007/relationships/media"
        // A video in the click sequence, trimmed and looping, with its poster; one played when clicked, its poster the
        // default picture; a sound that plays in the background, hidden, muted, across slides.
        let tree = Self.pic(4, "Opening", trim: "<p14:trim st=\"1500\" end=\"2000.5\"/><p14:fade in=\"500\"/><p14:bmkLst><p14:bmk name=\"Here\" time=\"3000\"/></p14:bmkLst>")
            + Self.pic(5, "Interview", link: "rId6", embed: "rId5", poster: "rId7", x: 3_048_000)
            + Self.pic(6, "Background", file: "audioFile", link: "rId9", embed: "rId8", poster: "rId10") + Self.box
        let main = Self.group(3, withSlide: true, Self.command(5, spid: 6, preset: 1, nodeType: "afterEffect", command: "playFrom(0.0)"))
            + Self.group(10, Self.command(12, spid: 4, preset: 1, nodeType: "clickEffect", command: "playFrom(0.0)", duration: "12000")
                    + Self.fade(14, spid: 9, nodeType: "withEffect"))
        let rest = Self.trigger(20, spid: 4) + Self.mediaNode(30, spid: 4, timeNode: "repeatCount=\"indefinite\" fill=\"hold\" display=\"0\"")
            + Self.trigger(40, spid: 5) + Self.mediaNode(50, spid: 5, attributes: "")
            + Self.mediaNode(60, spid: 6, tag: "audio", attributes: "vol=\"25%\" mute=\"1\" numSld=\"999\" showWhenStopped=\"0\"",
                        timeNode: "repeatCount=\"indefinite\" fill=\"hold\" display=\"0\"",
                        end: "<p:endCondLst><p:cond evt=\"onStopAudio\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:endCondLst>")
        package.slides = [PPTXTestPackage.Slide(xml: PPTXTestPackage.slide(tree, after: Self.timing(main: main, rest: rest)), relationships: [
            .init("rId2", media, "../media/media1.mp4"), .init("rId3", "video", "../media/media1.mp4"), .init("rId4", "image", "../media/image1.png"),
            .init("rId5", media, "../media/media2.mp4"), .init("rId6", "video", "../media/media2.mp4"), .init("rId7", "image", "../media/image2.png"),
            .init("rId8", media, "../media/media3.m4a"), .init("rId9", "audio", "../media/media3.m4a"), .init("rId10", "image", "../media/image3.png"),
        ])]
        package.media = ["ppt/media/media1.mp4": MediaTestFiles.movie(seconds: 12), "ppt/media/media2.mp4": MediaTestFiles.movie(seconds: 5),
                         "ppt/media/media3.m4a": MediaTestFiles.movie(seconds: 60, brand: "M4A "), "ppt/media/image1.png": Self.photo,
                         "ppt/media/image2.png": MediaPictures.videoPoster, "ppt/media/image3.png": Self.icon]
        // PowerPoint types media it doesn't know as unknown.
        var parts = try PPTXTestPackage.parts(of: try package.data())
        let types = Self.text("[Content_Types].xml", parts).replacingOccurrences(of: "</Types>", with: "<Default Extension=\"mp4\" "
            + "ContentType=\"video/unknown\"/><Default Extension=\"m4a\" ContentType=\"audio/unknown\"/></Types>")
        parts["[Content_Types].xml"] = Data(types.utf8)
        return try PPTXTestPackage.zip(parts)
    }

    @Test func readsPowerPointsClips() throws {
        let file = try PPTXTestPackage.read(try Self.powerPointPackage())
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        let elements = file.presentation.slides[0].elements
        #expect(elements.map(\.name) == ["Opening", "Interview", "Background", "Box"])
        let opening = try #require(elements[0].media)
        #expect(opening.kind == .video && opening.playback == .onClick && opening.loops && !opening.isMuted && opening.volume == 0.8)
        // 1.5 s trimmed off the start, 2.0005 s off the end of 12 s; fades and bookmarks aren't kept.
        #expect(opening.start == 1.5 && opening.end == 9.9995)
        let poster = try #require(opening.posterID)
        #expect(file.presentation.media[poster]?.data == Self.photo)
        #expect(file.presentation.media[opening.mediaID]?.contentType == "video/mp4")
        let interview = try #require(elements[1].media)
        // Played when clicked, at the media node's default volume, with the default picture: no poster.
        #expect(interview.playback == .manually && interview.volume == 0.5 && interview.posterID == nil && !interview.loops)
        let background = try #require(elements[2].media)
        #expect(background.kind == .audio && background.playback == .automatically && background.isMuted && background.loops)
        #expect(background.volume == 0.25 && background.hidesWhenPresenting && !background.stopsOnSlideChange)
        #expect(file.presentation.media[background.mediaID]?.contentType == "audio/mp4")
        let icon = try #require(background.posterID)
        #expect(file.presentation.media[icon]?.data == Self.icon)
        // The fade ran with the video's click, so it takes that click.
        #expect(file.presentation.slides[0].animations.map(\.start) == [.onClick])
        #expect(file.presentation.slides[0].animations.map(\.effect) == [.fadeIn])
    }

    @Test func clipsWithoutTimingPlayOnlyWhenClicked() throws {
        var package = PPTXTestPackage()
        let media = "http://schemas.microsoft.com/office/2007/relationships/media"
        // An older file: the sound embedded through its audio relationship only; a WAV sound embedded the old way.
        let wave = "<p:pic><p:nvPicPr><p:cNvPr id=\"7\" name=\"Old sound\"/><p:cNvPicPr/><p:nvPr><a:wavAudioFile r:embed=\"rId5\" name=\"ding.wav\"/>"
            + "</p:nvPr></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId4\"/></p:blipFill><p:spPr/></p:pic>"
        package.slides = [PPTXTestPackage.Slide(xml: PPTXTestPackage.slide(Self.pic(4, "Song", file: "audioFile", embed: nil) + Self.pic(5, "Movie") + wave),
                                                relationships: [.init("rId2", media, "../media/media1.mp4"), .init("rId3", "audio", "../media/song.mp3"),
                                                                .init("rId4", "image", "../media/image1.png"), .init("rId5", "audio", "../media/ding.wav")])]
        package.media = ["ppt/media/media1.mp4": MediaTestFiles.movie(seconds: 1), "ppt/media/song.mp3": MediaTestFiles.mp3(seconds: 1),
                         "ppt/media/ding.wav": MediaTestFiles.wave(seconds: 1), "ppt/media/image1.png": Self.photo]
        let file = try PPTXTestPackage.read(try package.data())
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        let clips = file.presentation.slides[0].elements.compactMap(\.media)
        #expect(clips.map(\.kind) == [.audio, .video, .audio])
        #expect(clips.allSatisfy { $0.playback == .manually && $0.volume == 1 })
        #expect(clips.map { file.presentation.media[$0.mediaID]?.contentType } == ["audio/mpeg", "video/mp4", "audio/wav"])
    }

    // MARK: What can't be kept

    @Test func linkedAndMissingMediaKeepTheirPosters() throws {
        var package = PPTXTestPackage()
        let media = "http://schemas.microsoft.com/office/2007/relationships/media"
        let tree = Self.pic(4, "Linked", link: "rId2", embed: nil, mediaLink: "rId2")
            + Self.pic(5, "Online", link: "rId3", embed: nil)
            + Self.pic(6, "Missing part", link: "rId6", embed: "rId5")
            + Self.pic(7, "No relationships", link: "rId90", embed: "rId91")
            + Self.pic(8, "Missing sound", file: "audioFile", link: "rId8", embed: "rId7")
            + Self.pic(9, "Too big", link: "rId10", embed: "rId9")
            + "<p:pic><p:nvPicPr><p:cNvPr id=\"10\" name=\"CD\"/><p:cNvPicPr/><p:nvPr><a:audioCd><a:st track=\"1\"/><a:end track=\"2\"/></a:audioCd></p:nvPr>"
            + "</p:nvPicPr><p:blipFill><a:blip r:embed=\"rId4\"/></p:blipFill><p:spPr/></p:pic>"
        let main = Self.group(3, Self.command(5, spid: 4, preset: 1, nodeType: "clickEffect", command: "playFrom(0.0)")
                         + Self.fade(7, spid: 9, nodeType: "withEffect"))
        package.slides = [PPTXTestPackage.Slide(xml: PPTXTestPackage.slide(tree, after: Self.timing(main: main, rest: Self.mediaNode(30, spid: 4))), relationships: [
            .init("rId2", "video", "file:///Users/someone/Movies/linked.mov", external: true),
            .init("rId3", "video", "https://example.com/watch?v=1", external: true), .init("rId4", "image", "../media/image1.png"),
            .init("rId5", media, "../media/gone.mp4"), .init("rId6", "video", "../media/gone.mp4"),
            .init("rId7", media, "../media/gone.mp3"), .init("rId8", "audio", "../media/gone.mp3"),
            .init("rId9", media, "../media/big.mp4"), .init("rId10", "video", "../media/big.mp4"),
        ])]
        package.media = ["ppt/media/image1.png": Self.photo, "ppt/media/big.mp4": MediaTestFiles.movie(seconds: 1)]
        // The big movie claims 2 GB once expanded.
        var data = try package.data()
        let name = Data("ppt/media/big.mp4".utf8)
        var cursor = data.startIndex
        while let range = data.range(of: Data([0x50, 0x4B, 0x01, 0x02]), in: cursor..<data.endIndex) {
            let nameStart = range.lowerBound + 46
            if data[nameStart..<min(nameStart + name.count, data.endIndex)] == name {
                data.replaceSubrange((range.lowerBound + 24)..<(range.lowerBound + 28), with: [0x00, 0x00, 0x00, 0x80])
            }
            cursor = range.upperBound
        }
        let file = try PPTXTestPackage.read(data)
        #expect(file.warnings == [.video, .audio], "\(file.warnings)")
        let elements = file.presentation.slides[0].elements
        // Every poster is kept as a picture; nothing is a clip.
        #expect(elements.map(\.name) == ["Linked", "Online", "Missing part", "No relationships", "Missing sound", "Too big", "CD"])
        #expect(elements.allSatisfy { $0.picture != nil })
        // The play command of a video that isn't kept goes; the fade that ran with it takes its click.
        #expect(file.presentation.slides[0].animations.map(\.start) == [.onClick])
        #expect(file.presentation.slides[0].animations.first?.elementID == elements[5].id)
    }

    @Test func damagedClipsDontStopTheFile() throws {
        var package = PPTXTestPackage()
        let media = "http://schemas.microsoft.com/office/2007/relationships/media"
        // Garbage for a movie; absurd trims, volumes, slide counts and commands.
        let tree = Self.pic(4, "Garbage", trim: "<p14:trim st=\"NaN\" end=\"1e400\"/>")
            + Self.pic(5, "Absurd", link: "rId6", embed: "rId5", trim: "<p14:trim st=\"99999999999999999999\" end=\"-5\"/>", x: 100)
            + Self.pic(6, "Empty trim", link: "rId6", embed: "rId5", trim: "<p14:trim/>", x: 200)
        let main = Self.group(3, Self.command(5, spid: 4, preset: 1, nodeType: "clickEffect", command: "playFrom(abc)")
                         + Self.command(7, spid: 5, preset: 3, nodeType: "withEffect", command: "stop"))
        let rest = Self.mediaNode(30, spid: 4, attributes: "vol=\"99999999\" mute=\"maybe\" numSld=\"-5\" showWhenStopped=\"2\"", timeNode: "repeatCount=\"x\"")
            + Self.mediaNode(31, spid: 5, attributes: "vol=\"-40000\"") + Self.mediaNode(32, spid: 99) + "<p:video><p:cMediaNode/></p:video>"
            + "<p:seq><p:cTn nodeType=\"interactiveSeq\"><p:stCondLst><p:cond evt=\"onClick\"><p:tgtEl><p:spTgt spid=\"6\"/></p:tgtEl></p:cond>"
            + "</p:stCondLst></p:cTn></p:seq>"
        package.slides = [PPTXTestPackage.Slide(xml: PPTXTestPackage.slide(tree, after: Self.timing(main: main, rest: rest)), relationships: [
            .init("rId2", media, "../media/media1.mp4"), .init("rId3", "video", "../media/media1.mp4"), .init("rId4", "image", "../media/image1.png"),
            .init("rId5", media, "../media/media2.mp4"), .init("rId6", "video", "../media/media2.mp4"),
        ])]
        package.media = ["ppt/media/media1.mp4": Data("this is not a movie".utf8), "ppt/media/media2.mp4": MediaTestFiles.movie(seconds: 2),
                         "ppt/media/image1.png": Data("not a picture either".utf8)]
        let file = try PPTXTestPackage.read(try package.data())
        // Stopping a clip can't be kept; the empty trigger isn't a clip's own.
        #expect(file.warnings == [.animations], "\(file.warnings)")
        let clips = file.presentation.slides[0].elements.compactMap(\.media)
        #expect(clips.count == 3)
        // The garbage is kept as the movie it says it is, untrimmed; its poster is kept as is.
        #expect(file.presentation.media[clips[0].mediaID]?.contentType == "video/mp4")
        #expect(clips[0].start == nil && clips[0].end == nil && clips[0].posterID != nil)
        #expect(clips[0].playback == .onClick && clips[0].volume == 1 && !clips[0].isMuted && !clips[0].loops && !clips[0].hidesWhenPresenting)
        #expect(clips[1].start == 1e9 && clips[1].end == nil && clips[1].volume == 0 && clips[1].playback == .manually)
        #expect(clips[2].start == nil && clips[2].end == nil && clips[2].playback == .manually)
        // And it writes again.
        let again = try Self.roundTrip(file.presentation)
        #expect(again.presentation.slides[0].elements.compactMap(\.media).count == 3)
    }

    @Test func damagedMediaMarkupAndBytesDontCrash() throws {
        let fragments = ["<p14:trim st=\"1e400\" end=\"-1\"/>", "<p14:media r:embed=\"rId1\" r:link=\"rId99\"/>", "<a:videoFile r:link=\"rId1\"/>",
                         "<a:audioFile r:link=\"\"/>", "<a:wavAudioFile r:embed=\"rId3\"/>", "<a:audioCd/>", "r:embed=\"rId2\"", "spid=\"3\"", "spid=\"-1\"",
                         "<p:video><p:cMediaNode vol=\"1e9\" numSld=\"99999999999\"><p:cTn repeatCount=\"indefinite\"/><p:tgtEl><p:spTgt spid=\"3\"/></p:tgtEl>"
                            + "</p:cMediaNode></p:video>", "<p:audio><p:cMediaNode/></p:audio>", "<p:cmd type=\"call\" cmd=\"playFrom(1e999)\"/>",
                         "nodeType=\"interactiveSeq\"", "presetClass=\"mediacall\"", "<p:seq><p:cTn nodeType=\"interactiveSeq\"/></p:seq>", "</p:timing>"]
        let original = try PPTXTestPackage.parts(of: try PresentationIO.write(Self.deck(), format: .pptx))
        let targets = ["ppt/slides/slide1.xml", "ppt/slides/slide2.xml", "ppt/slides/_rels/slide1.xml.rels", "[Content_Types].xml"]
        var random = PPTXTestRandom(seed: 55)
        var readable = 0
        for iteration in 0..<240 {
            var parts = original
            let target = targets[iteration % targets.count]
            var scalars = Array(String(decoding: original[target]!, as: UTF8.self).unicodeScalars)
            for _ in 0..<(1 + random.below(3)) {
                let position = random.below(scalars.count)
                if random.below(3) == 0 {
                    scalars.removeSubrange(position..<min(scalars.count, position + random.below(200)))
                } else {
                    scalars.insert(contentsOf: fragments[random.below(fragments.count)].unicodeScalars, at: position)
                }
            }
            parts[target] = Data(String(String.UnicodeScalarView(scalars)).utf8)
            if PPTXFuzzTests.survives(try PPTXTestPackage.zip(parts)) { readable += 1 }
        }
        #expect(readable > 0)
        // Movies and sounds of any bytes at all, and none.
        for size in [0, 1, 4, 8, 12, 20, 40, 120, 4096] {
            var parts = original
            for path in parts.keys where path.hasPrefix("ppt/media/media") {
                parts[path] = Data((0..<size).map { _ in UInt8(truncatingIfNeeded: random.next()) })
            }
            #expect(PPTXFuzzTests.survives(try PPTXTestPackage.zip(parts)))
            let odp = try PresentationIO.write(try PPTXTestPackage.read(try PPTXTestPackage.zip(parts)).presentation, format: .odp)
            #expect(ODPFuzzTests.survives(odp))
        }
    }
}
