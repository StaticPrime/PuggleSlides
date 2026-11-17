#if DEBUG
import AppKit
import PuggleSlidesKit

/// Video and audio: inserting, playback settings, playing on the canvas and in slideshows, pictures and files.
extension SelfTest {
    /// The color at a slide point when the slide is drawn with `options`.
    private static func color(at point: SlidePoint, of slide: Slide, in presentation: Presentation,
                              options: SlideRenderer.Options) -> NSColor? {
        let size = presentation.slideSize
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: NSGraphicsContext(bitmapImageRep: rep)!.cgContext, flipped: true)
        NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: size.height)
        NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: -1)
        SlideRenderer.draw(slide, of: presentation, in: CGRect(x: 0, y: 0, width: size.width, height: size.height), options: options)
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: Int(point.x), y: Int(point.y))
    }

    static func addPhase5Steps(_ window: DocumentWindowController) {
        let controller = window.controller
        var slide: Slide { controller.currentSlide! }
        var videoID = UUID(), audioID = UUID()
        var video: MediaClip? { slide.element(id: videoID)?.media }
        var audio: MediaClip? { slide.element(id: audioID)?.media }
        let folder = FileManager.default.temporaryDirectory
        let movieURL = folder.appendingPathComponent("selftest-movie.mp4")
        let soundURL = folder.appendingPathComponent("selftest-sound.wav")
        let bogusURL = folder.appendingPathComponent("selftest-bogus.mp4")

        // Inserting.
        step {
            let theme = controller.presentation.theme(for: slide)
            controller.newSlide(layoutID: theme.layout(kind: .blank)?.id)
            try? SampleContent.sampleMovie().write(to: movieURL)
            Task { await window.insertMedia(from: movieURL) }
            wait { slide.elements.contains { $0.media?.isVideo == true } }
        }
        step {
            videoID = slide.elements.first { $0.media?.isVideo == true }?.id ?? UUID()
            let frame = slide.element(id: videoID)?.placement?.frame
            check(video?.posterID != nil && video.map { controller.presentation.media[$0.mediaID]?.contentType == "video/mp4" } == true,
                  "Insert ▸ Video embeds the movie with its first frame as the poster")
            check(frame.map { abs($0.width / $0.height - 16.0 / 9) < 0.01 } == true, "a video keeps its proportions", "\(String(describing: frame))")
            check(controller.selectionKind() == .media, "an inserted video is selected, with its own toolbar")
            try? Data("not a movie".utf8).write(to: bogusURL)
            Task { await window.insertMedia(from: bogusURL) }
            wait { window.window?.attachedSheet != nil }
        }
        step {
            check(window.window?.attachedSheet != nil && slide.elements.filter { $0.media != nil }.count == 1,
                  "a file that isn't a playable movie is refused with an explanation")
            if let sheet = window.window?.attachedSheet { window.window?.endSheet(sheet) }
            try? SampleContent.sampleSound().write(to: soundURL)
            Task { await window.insertMedia(from: soundURL) }
            wait { slide.elements.contains { $0.media?.kind == .audio } }
        }
        step {
            audioID = slide.elements.first { $0.media?.kind == .audio }?.id ?? UUID()
            let frame = slide.element(id: audioID)?.placement?.frame
            check(audio != nil && frame?.width == audioIconSize && frame?.height == audioIconSize, "Insert ▸ Audio puts a speaker icon on the slide")
            controller.selectElements([videoID])
            controller.setClipPlayback(.automatically)
            controller.setClipTrim(start: 0.5, end: 1.5)
        }
        step {
            controller.setClipMuted(true)
            check(video?.playback == .automatically && video?.start == 0.5 && video?.end == 1.5 && video?.isMuted == true,
                  "Format options sets a video's playback, its start and end, and mute")
        }
        step {
            controller.undoManager?.undo()
            check(video?.isMuted == false && video?.end == 1.5 && video?.playback == .automatically, "each playback setting is one undo step")
            controller.selectElements([audioID])
            controller.setClipPlayback(.automatically)
            controller.setClipHidesWhenPresenting(true)
            controller.setClipLoops(true)
            controller.setClipStopsOnSlideChange(false)
            controller.setClipVolume(0.4)
            check(audio.map { $0.hidesWhenPresenting && $0.loops && !$0.stopsOnSlideChange && $0.volume == 0.4 } == true,
                  "Format options sets a sound's volume, loop, icon and stop on slide change")
        }
        step {
            let presenting = SlideRenderer.Options(isPresenting: true)
            let icon = slide.element(id: audioID)?.placement?.frame
            let middle = SlidePoint(x: (icon?.x ?? 0) + audioIconSize / 2, y: (icon?.y ?? 0) + audioIconSize / 2)
            let hidden = color(at: middle, of: slide, in: controller.presentation, options: presenting)
            check(hidden.map { $0.brightnessComponent > 0.95 } == true, "a sound's icon can hide while presenting")
            controller.setClipPlayback(.onClick)
            check(audio?.hidesWhenPresenting == false, "only a sound that starts automatically hides its icon")
            let frame = slide.element(id: videoID)?.placement?.frame ?? SlideRect(x: 0, y: 0, width: 0, height: 0)
            let poster = color(at: SlidePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2), of: slide, in: controller.presentation,
                               options: SlideRenderer.Options())
            // The movie's amber first frame, not the dark box or the white slide.
            check(poster.map { $0.saturationComponent > 0.3 && $0.brightnessComponent > 0.3 } == true, "a video shows its poster in pictures of the slide",
                  "\(String(describing: poster))")
            check(SVGExport.svg(for: slide, number: (controller.currentSlideIndex ?? 0) + 1, in: controller.presentation).contains("data:image/png"),
                  "SVG downloads show the video's poster")
        }

        // Playing.
        step {
            controller.selectElements([videoID])
            window.playClipInEditor(videoID)
            check(window.clipPreview?.view?.superview === window.canvas, "a video plays in place on the slide")
            controller.selectElements([])
        }
        step {
            check(window.clipPreview == nil, "selecting something else stops it")
            window.startSlideshow(fromBeginning: false, presenterView: false)
            wait(upTo: 3) { SlideshowController.current?.media.clips.first { $0.clip.isVideo }?.isPlaying == true }
        }
        step {
            let show = SlideshowController.current
            check(show?.media.clips.first { $0.clip.isVideo }?.isPlaying == true, "a video set to play automatically starts with its slide")
            check(show?.media.waiting == [audioID], "a sound set to play on click waits for a click")
            show?.next()
            check(show?.media.clips.first { $0.elementID == audioID }?.isPlaying == true, "the click starts it")
            show?.end()
            check(SlideshowController.current == nil, "ending the show stops its clips")
        }
        step {
            controller.selectElements([videoID])
            controller.setClipPlayback(.manually)
            window.startSlideshow(fromBeginning: false, presenterView: false)
            wait(upTo: 3) { SlideshowController.current != nil }
        }
        step {
            let show = SlideshowController.current
            let frame = slide.element(id: videoID)?.placement?.frame ?? SlideRect(x: 0, y: 0, width: 0, height: 0)
            check(show?.media.clips.first { $0.clip.isVideo }?.isPlaying == false, "a video set to play manually waits")
            let started = show?.media.toggleVideo(at: SlidePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)) == true
            check(started && show?.media.clips.first { $0.clip.isVideo }?.isPlaying == true, "clicking it plays it")
            show?.end()
        }

        // Files and VoiceOver.
        step {
            for format in [PresentationFormat.pptx, .odp] {
                let name = format == .pptx ? "a PowerPoint" : "an OpenDocument"
                do {
                    let file = try PresentationIO.read(try PresentationIO.write(controller.presentation, format: format), format: format)
                    let clips = file.presentation.slides.flatMap(\.elements).compactMap(\.media)
                    let movie = clips.first { $0.isVideo }, sound = clips.first { !$0.isVideo }
                    check(movie?.playback == .manually && movie.flatMap { file.presentation.media[$0.mediaID] }?.data == SampleContent.sampleMovie(),
                          "\(name) file keeps videos and how they play")
                    check(sound.map { $0.loops && !$0.stopsOnSlideChange } == true && file.presentation.media[sound?.mediaID ?? ""] != nil,
                          "\(name) file keeps sounds and their settings")
                    check(!file.warnings.contains(.video) && !file.warnings.contains(.audio), "\(name) file with clips opens as itself")
                } catch {
                    check(false, "\(name) file with clips", "\(error)")
                }
            }
            let objects = window.canvas.accessibilityChildren()?.compactMap { $0 as? SlideObjectAccessibility } ?? []
            check(objects.first { $0.elementID == videoID }?.accessibilityRoleDescription() == "video"
                  && objects.first { $0.elementID == audioID }?.accessibilityRoleDescription() == "audio", "VoiceOver names videos and sounds")
            for url in [movieURL, soundURL, bogusURL] { try? FileManager.default.removeItem(at: url) }
        }
    }
}
#endif
