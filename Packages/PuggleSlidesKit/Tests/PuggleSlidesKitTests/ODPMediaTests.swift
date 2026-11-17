import Foundation
import Testing
@testable import PuggleSlidesKit

/// Videos and sounds in OpenDocument presentations: written as LibreOffice Impress keeps media objects, read back with every
/// setting, and read from files shaped like Impress's.
struct ODPMediaTests {
    static func roundTrip(_ presentation: Presentation) throws -> PresentationFile {
        try PresentationIO.read(try PresentationIO.write(presentation, format: .odp), format: .odp)
    }

    static func text(_ path: String, _ parts: [String: Data]) -> String {
        parts[path].map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// Every clip, slide by slide and group by group, as files keep it: its media and poster by their bytes and types.
    static func clips(_ presentation: Presentation) -> [String] {
        func describe(_ elements: [SlideElement], path: String) -> [String] {
            elements.enumerated().flatMap { index, element -> [String] in
                if let children = element.children { return describe(children, path: "\(path).\(index)") }
                guard let clip = element.media else { return [] }
                let media = { (id: MediaID) in
                    presentation.media[id].map { "\($0.data.hashValue) \(PPTXMedia.contentType(forExtension: $0.fileExtension) ?? $0.contentType)" } ?? "-"
                }
                return ["\(path).\(index) \(element.name) \(PPTXCanonical.clip(clip, media: media))"]
            }
        }
        return presentation.slides.enumerated().flatMap { describe($1.elements, path: "\($0 + 1)") }
    }

    // MARK: Round trips

    @Test func clipsRoundTripWithEverySetting() throws {
        let original = PPTXMediaTests.deck()
        let file = try Self.roundTrip(original)
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        #expect(Self.clips(file.presentation) == Self.clips(original))
        let shown = ODPRendering.difference(original, file.presentation)
        #expect(shown == nil, "\(shown ?? "")")
        // The exact volume, the trim and the poster come back.
        let read = file.presentation
        let opening = try #require(read.slides[0].elements[1].media)
        #expect(opening.playback == .automatically && opening.start == 1.5 && opening.end == 9.25 && opening.volume == 0.5 && opening.loops)
        let poster = try #require(opening.posterID)
        #expect(read.media[poster]?.data == PPTXMediaTests.photo)
        #expect(read.slides[1].elements[1].media?.volume == 0.3 && read.slides[1].elements[0].media?.stopsOnSlideChange == false)
        #expect(read.slides[1].elements[3].children?[0].media?.playback == .onClick)
        #expect(read.slides[0].animations.map(\.start) == [.onClick, .afterPrevious, .withPrevious, .onClick])
        // A second time through gives the same.
        let again = try Self.roundTrip(read)
        #expect(Self.clips(again.presentation) == Self.clips(original))
    }

    @Test func clipsSurviveBothFormats() throws {
        // To PowerPoint and on to OpenDocument, and back.
        let original = PPTXMediaTests.deck()
        let viaPowerPoint = try PresentationIO.read(try PresentationIO.write(original, format: .pptx), format: .pptx).presentation
        let file = try Self.roundTrip(viaPowerPoint)
        #expect(file.warnings.isEmpty)
        #expect(Self.clips(file.presentation) == Self.clips(original))
        let shown = ODPRendering.difference(original, file.presentation)
        #expect(shown == nil, "\(shown ?? "")")
        let back = try PresentationIO.read(try PresentationIO.write(file.presentation, format: .pptx), format: .pptx)
        #expect(back.warnings.isEmpty)
        #expect(Self.clips(back.presentation) == Self.clips(original))
        #expect(back.presentation.slides.map { $0.animations.map(\.start) } == original.slides.map { $0.animations.map(\.start) })
    }

    // MARK: Markup

    @Test func clipsAreWrittenAsImpressWritesThem() throws {
        let data = try PresentationIO.write(PPTXMediaTests.deck(), format: .odp)
        let parts = try ODPTestPackage.parts(of: data)
        let content = Self.text("content.xml", parts)
        // The plugin: the movie in Media/, LibreOffice's media type, its parameters, then the poster.
        #expect(content.contains("<draw:plugin xlink:href=\"Media/media1.mp4\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\" "
            + "draw:mime-type=\"application/vnd.sun.star.media\" xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" "
            + "psext:start=\"1.5s\" psext:end=\"9.25s\" psext:volume=\"0.5\" psext:hides-when-presenting=\"true\">"))
        #expect(content.contains("<draw:param draw:name=\"Loop\" draw:value=\"true\"/><draw:param draw:name=\"Mute\" draw:value=\"false\"/>"
            + "<draw:param draw:name=\"VolumeDB\" draw:value=\"-6\"/></draw:plugin><draw:image xlink:href=\"Pictures/image1.png\""))
        // Silent is LibreOffice's quietest volume; full volume needs nothing of PuggleSlides' own.
        #expect(content.contains("draw:mime-type=\"application/vnd.sun.star.media\" xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" "
            + "psext:start=\"0.25s\"><draw:param draw:name=\"Loop\" draw:value=\"false\"/><draw:param draw:name=\"Mute\" draw:value=\"false\"/>"
            + "<draw:param draw:name=\"VolumeDB\" draw:value=\"-40\"/>"))
        #expect(content.contains("xlink:href=\"Media/media2.mov\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\" "
            + "draw:mime-type=\"application/vnd.sun.star.media\" xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" "
            + "psext:end=\"20s\"><draw:param draw:name=\"Loop\" draw:value=\"false\"/><draw:param draw:name=\"Mute\" draw:value=\"true\"/>"))
        #expect(content.contains("psext:volume=\"0.8\" psext:hides-when-presenting=\"true\" psext:stops-on-slide-change=\"false\">"))
        // A clip without a poster has no preview: Impress makes its own.
        #expect(!content.contains("Media/media2.mov\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\" draw:mime-type=\"application/"
            + "vnd.sun.star.media\" xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" psext:end=\"20s\"><draw:param "
            + "draw:name=\"Loop\" draw:value=\"false\"/><draw:param draw:name=\"Mute\" draw:value=\"true\"/><draw:param draw:name=\"VolumeDB\" "
            + "draw:value=\"0\"/></draw:plugin><draw:image"))
        // Timing: Start with the slide's first effects, Start on a click after its animations, Toggle Pause on its own click.
        #expect(content.contains("<anim:seq presentation:node-type=\"main-sequence\"><anim:par smil:begin=\"0s\"><anim:par smil:begin=\"0s\">"
            + "<anim:par smil:begin=\"0s\" smil:fill=\"hold\" presentation:node-type=\"with-previous\" presentation:preset-class=\"media-call\" "
            + "presentation:preset-id=\"ooo-media-start\"><anim:command smil:begin=\"0s\" smil:targetElement=\"s1m1\" anim:command=\"play\"/></anim:par>"))
        #expect(content.contains("<anim:par smil:begin=\"next\"><anim:par smil:begin=\"0s\"><anim:par smil:begin=\"0s\" smil:fill=\"hold\" "
            + "presentation:node-type=\"on-click\" presentation:preset-class=\"media-call\" presentation:preset-id=\"ooo-media-start\">"
            + "<anim:command smil:begin=\"0s\" smil:targetElement=\"s1m2\" anim:command=\"play\"/>"))
        #expect(content.contains("<anim:seq presentation:node-type=\"interactive-sequence\" smil:restart=\"whenNotActive\"><anim:par smil:begin=\"s1e4.click\">"
            + "<anim:par smil:begin=\"0s\"><anim:par smil:begin=\"0s\" smil:fill=\"hold\" presentation:node-type=\"on-click\" presentation:preset-class="
            + "\"media-call\" presentation:preset-id=\"ooo-media-toggle-pause\"><anim:command smil:begin=\"0s\" smil:targetElement=\"s1e4\" "
            + "anim:command=\"toggle-pause\"/></anim:par></anim:par></anim:par></anim:seq>"))
        #expect(content.contains("<draw:frame draw:name=\"Opening\" draw:style-name=\"gr"))
        // The manifest types each file; movies and sounds are stored, not deflated, as LibreOffice stores them.
        let manifest = Self.text("META-INF/manifest.xml", parts)
        for (path, type) in [("Media/media1.mp4", "video/mp4"), ("Media/media2.mov", "video/quicktime"), ("Media/media3.mp3", "audio/mpeg"),
                             ("Media/media4.wav", "audio/x-wav"), ("Media/media5.aiff", "audio/aiff"), ("Media/media6.m4a", "audio/mp4")] {
            #expect(manifest.contains("<manifest:file-entry manifest:full-path=\"\(path)\" manifest:media-type=\"\(type)\"/>"), "\(path)")
        }
        let archive = try ZipReader(data: data)
        #expect(archive.entries.filter { $0.path.hasPrefix("Media/") }.allSatisfy { $0.method == 0 })
        // Volumes in whole decibels, as LibreOffice's players take them.
        #expect(ODPMedia.decibels(1) == 0 && ODPMedia.decibels(0.5) == -6 && ODPMedia.decibels(0) == -40 && ODPMedia.decibels(.nan) == -40)
        #expect(ODPMedia.volume(decibels: -40) == 0 && ODPMedia.volume(decibels: -100) == 0 && ODPMedia.volume(decibels: 12) == 1)
        #expect(abs(ODPMedia.volume(decibels: -6) - 0.501) < 0.001)
    }

    // MARK: Reading Impress's files

    static func frame(_ name: String, href: String, type: String = "application/vnd.sun.star.media", id: String? = nil, params: String = "",
                      preview: String? = nil, attributes: String = "", x: Double = 1) -> String {
        "<draw:frame draw:name=\"\(name)\" draw:style-name=\"gr1\" draw:layer=\"layout\"" + (id.map { " xml:id=\"\($0)\" draw:id=\"\($0)\"" } ?? "")
            + " svg:width=\"8cm\" svg:height=\"4.5cm\" svg:x=\"\(x)cm\" svg:y=\"1cm\"><draw:plugin xlink:href=\"\(href)\" xlink:type=\"simple\" "
            + "xlink:show=\"embed\" xlink:actuate=\"onLoad\" draw:mime-type=\"\(type)\"\(attributes)>\(params)</draw:plugin>"
            + (preview.map { "<draw:image xlink:href=\"\($0)\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>" } ?? "")
            + "</draw:frame>"
    }

    static func params(loop: Bool = false, mute: Bool = false, volume: String = "0") -> String {
        "<draw:param draw:name=\"Loop\" draw:value=\"\(loop)\"/><draw:param draw:name=\"Mute\" draw:value=\"\(mute)\"/>"
            + "<draw:param draw:name=\"VolumeDB\" draw:value=\"\(volume)\"/><draw:param draw:name=\"Zoom\" draw:value=\"fit\"/>"
    }

    static func effect(_ target: String, nodeType: String, preset: String = "ooo-media-toggle-pause", command: String = "toggle-pause") -> String {
        "<anim:par smil:begin=\"0s\" smil:fill=\"hold\" presentation:node-type=\"\(nodeType)\" presentation:preset-class=\"media-call\" "
            + "presentation:preset-id=\"\(preset)\"><anim:command smil:begin=\"0s\" smil:dur=\"0.001s\" anim:command=\"\(command)\" "
            + "smil:targetElement=\"\(target)\"/></anim:par>"
    }

    static let fade = "<anim:par smil:begin=\"0s\" smil:fill=\"hold\" presentation:node-type=\"with-previous\" presentation:preset-class=\"entrance\" "
        + "presentation:preset-id=\"ooo-entrance-fade-in\"><anim:set smil:begin=\"0s\" smil:dur=\"0.001s\" smil:fill=\"hold\" smil:targetElement=\"id9\" "
        + "smil:attributeName=\"visibility\" smil:to=\"visible\"/><anim:transitionFilter smil:dur=\"0.5s\" smil:targetElement=\"id9\" "
        + "smil:type=\"fade\" smil:subtype=\"crossfade\"/></anim:par>"

    static let box = "<draw:custom-shape draw:name=\"Box\" draw:style-name=\"gr1\" draw:layer=\"layout\" xml:id=\"id9\" draw:id=\"id9\" svg:width=\"2cm\" "
        + "svg:height=\"2cm\" svg:x=\"20cm\" svg:y=\"10cm\"><draw:enhanced-geometry svg:viewBox=\"0 0 21600 21600\" draw:type=\"rectangle\"/></draw:custom-shape>"

    @Test func readsImpressMediaObjects() throws {
        // A video LibreOffice 7.5 wrote (its generic type) on a click with a fade; a sound a newer version wrote (its own
        // type), with no command, so it plays as the slide appears; a video played by its own click; one started by a
        // with-previous command.
        let shapes = Self.frame("Clip", href: "Media/clip.mp4", id: "id1", params: Self.params(loop: true, volume: "-6"), preview: "Pictures/MediaPreview1.png")
            + Self.frame("Song", href: "Media/song.mp3", type: "audio/mpeg", params: Self.params(mute: true, volume: "-40"), x: 10)
            + Self.frame("Trigger", href: "Media/clip.mp4", type: "video/mp4", id: "id3", params: Self.params(), x: 19)
            + Self.frame("Auto", href: "Media/other.mov", id: "id4", params: Self.params(volume: "-12"),
                         preview: "Pictures/MediaPreview2.png", x: 1)
            + Self.box
            + "<anim:par presentation:node-type=\"timing-root\"><anim:seq presentation:node-type=\"main-sequence\">"
            + "<anim:par smil:begin=\"0s\"><anim:par smil:begin=\"0s\">"
            + Self.effect("id4", nodeType: "with-previous", preset: "ooo-media-start", command: "play") + "</anim:par></anim:par>"
            + "<anim:par smil:begin=\"next\"><anim:par smil:begin=\"0s\">" + Self.effect("id1", nodeType: "on-click") + Self.fade + "</anim:par></anim:par>"
            + "</anim:seq><anim:seq smil:restart=\"whenNotActive\" presentation:node-type=\"interactive-sequence\"><anim:par smil:begin=\"id3.click\">"
            + "<anim:par smil:begin=\"0s\">" + Self.effect("id3", nodeType: "on-click") + "</anim:par></anim:par></anim:seq></anim:par>"
        let package = try ODPObjectFixture.package(shapes: shapes, images: [
            "Media/clip.mp4": MediaTestFiles.movie(seconds: 4), "Media/song.mp3": MediaTestFiles.mp3(seconds: 1),
            "Media/other.mov": MediaTestFiles.movie(seconds: 2, brand: "qt  "), "Pictures/MediaPreview1.png": PPTXMediaTests.photo,
            "Pictures/MediaPreview2.png": MediaPictures.videoPoster])
        let file = try PresentationIO.read(package, format: .odp)
        #expect(file.warnings.isEmpty, "\(file.warnings)")
        let elements = file.presentation.slides[0].elements
        #expect(elements.map(\.name) == ["Clip", "Song", "Trigger", "Auto", "Box"])
        let clip = try #require(elements[0].media)
        #expect(clip.kind == .video && clip.playback == .onClick && clip.loops && !clip.isMuted && abs(clip.volume - 0.501) < 0.001)
        let poster = try #require(clip.posterID)
        #expect(file.presentation.media[poster]?.data == PPTXMediaTests.photo)
        #expect(abs((elements[0].placement?.frame.width ?? 0) - 8 * 72 / 2.54) < 0.01)
        let song = try #require(elements[1].media)
        #expect(song.kind == .audio && song.playback == .automatically && song.isMuted && song.volume == 0 && song.posterID == nil)
        #expect(file.presentation.media[song.mediaID]?.contentType == "audio/mpeg")
        // The same movie twice is stored once.
        #expect(elements[2].media?.playback == .manually && elements[2].media?.mediaID == clip.mediaID)
        let auto = try #require(elements[3].media)
        #expect(auto.playback == .automatically && auto.posterID == nil && file.presentation.media[auto.mediaID]?.contentType == "video/quicktime")
        // The fade ran with the clip's click: it takes the click.
        #expect(file.presentation.slides[0].animations.map(\.start) == [.onClick])
    }

    // MARK: What can't be kept

    @Test func linkedMissingAndOtherPluginsKeepTheirPreviews() throws {
        let shapes = Self.frame("Linked", href: "../movies/linked.mp4", preview: "Pictures/preview.png")
            + Self.frame("Online", href: "https://example.com/movie.mp4", type: "video/mp4", preview: "Pictures/preview.png", x: 5)
            + Self.frame("Missing", href: "Media/gone.mp3", type: "audio/mpeg", x: 9)
            + Self.frame("Applet", href: "Media/thing.swf", type: "application/x-shockwave-flash", preview: "Pictures/preview.png", x: 13)
            + Self.frame("Too big", href: "Media/big.mp4", x: 17)
        var package = try ODPObjectFixture.package(shapes: shapes, images: ["Pictures/preview.png": PPTXMediaTests.photo,
                                                                             "Media/big.mp4": MediaTestFiles.movie(seconds: 1)])
        // The big movie claims 2 GB once expanded.
        let name = Data("Media/big.mp4".utf8)
        var cursor = package.startIndex
        while let range = package.range(of: Data([0x50, 0x4B, 0x01, 0x02]), in: cursor..<package.endIndex) {
            let start = range.lowerBound + 46
            if package[start..<min(start + name.count, package.endIndex)] == name {
                package.replaceSubrange((range.lowerBound + 24)..<(range.lowerBound + 28), with: [0x00, 0x00, 0x00, 0x80])
            }
            cursor = range.upperBound
        }
        let file = try PresentationIO.read(package, format: .odp)
        #expect(file.warnings == [.video, .audio, .embeddedObjects], "\(file.warnings)")
        let elements = file.presentation.slides[0].elements
        // Previews are kept as pictures; frames without one go.
        #expect(elements.map(\.name) == ["Linked", "Online", "Applet"])
        #expect(elements.allSatisfy { $0.picture != nil })
    }

    @Test func damagedClipsDontStopTheFile() throws {
        let shapes = Self.frame("Garbage", href: "Media/garbage.mp4", id: "id1",
                                params: "<draw:param draw:name=\"VolumeDB\" draw:value=\"9999999999\"/><draw:param draw:name=\"Loop\" draw:value=\"perhaps\"/>"
                                    + "<draw:param/><draw:param draw:name=\"Mute\"/>",
                                preview: "Pictures/broken.png",
                                attributes: " xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" psext:start=\"-5s\" "
                                    + "psext:end=\"1e400s\" psext:volume=\"NaN\" psext:hides-when-presenting=\"maybe\" psext:stops-on-slide-change=\"\"")
            + Self.frame("Odd", href: "./Media/odd%20name.mp4", id: "id2", params: Self.params(volume: "-3.6"),
                         attributes: " xmlns:psext=\"urn:com:pugglesoft:names:experimental:puggleslides:xmlns:psext:1.0\" psext:start=\"3s\" psext:end=\"2s\" "
                             + "psext:volume=\"7\"", x: 10)
            + "<anim:par presentation:node-type=\"timing-root\"><anim:seq presentation:node-type=\"main-sequence\"><anim:par smil:begin=\"next\">"
            + "<anim:par smil:begin=\"0s\">" + Self.effect("id1", nodeType: "on-click", preset: "ooo-media-stop", command: "stop")
            + Self.effect("id99", nodeType: "with-previous") + "</anim:par></anim:par></anim:seq>"
            + "<anim:seq presentation:node-type=\"interactive-sequence\"><anim:par smil:begin=\"id2.click\"><anim:par smil:begin=\"0s\">"
            + Self.effect("id1", nodeType: "on-click") + "</anim:par></anim:par></anim:seq></anim:par>"
        let package = try ODPObjectFixture.package(shapes: shapes, images: ["Media/garbage.mp4": Data("not a movie".utf8),
                                                                             "Media/odd name.mp4": MediaTestFiles.movie(seconds: 1),
                                                                             "Pictures/broken.png": Data("not a picture".utf8)])
        let file = try PresentationIO.read(package, format: .odp)
        // Stopping a clip can't be kept, nor a trigger that plays another clip.
        #expect(file.warnings == [.animations], "\(file.warnings)")
        let clips = file.presentation.slides[0].elements.compactMap(\.media)
        #expect(clips.count == 2)
        #expect(file.presentation.media[clips[0].mediaID]?.contentType == "video/mp4")
        #expect(clips[0].volume == 1 && !clips[0].loops && !clips[0].isMuted && clips[0].start == nil && clips[0].end == nil)
        #expect(!clips[0].hidesWhenPresenting && clips[0].stopsOnSlideChange && clips[0].playback == .automatically && clips[0].posterID != nil)
        // A start after the end keeps the start; the volume is the most there is.
        #expect(clips[1].start == 3 && clips[1].end == nil && clips[1].volume == 1 && clips[1].playback == .automatically)
        // And it writes again.
        let again = try Self.roundTrip(file.presentation)
        #expect(again.presentation.slides[0].elements.compactMap(\.media).count == 2)
    }
}
