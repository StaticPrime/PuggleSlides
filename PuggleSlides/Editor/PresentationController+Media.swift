import AppKit
import PuggleSlidesKit

/// Insert ▸ Video, Insert ▸ Audio and Format options' playback settings: each change is one undoable step.
extension PresentationController {
    /// The clip selected on its own, if any.
    var selectedClip: (element: SlideElement, clip: MediaClip)? {
        guard selectedElements.count == 1, let element = selectedElements.first, let clip = element.media else { return nil }
        return (element, clip)
    }

    /// Adds a video, at its own proportions and at most 60% of the slide's size, in the middle of the slide.
    @discardableResult
    func insertVideo(data: Data, contentType: String, poster: Data?, size natural: CGSize, at center: SlidePoint? = nil) -> UUID? {
        let slide = presentation.slideSize
        let width = max(1, Double(natural.width)), height = max(1, Double(natural.height))
        let scale = min(slide.width * 0.6 / width, slide.height * 0.6 / height)
        return insertClip(.video, data: data, contentType: contentType, poster: poster, size: CGSize(width: width * scale, height: height * scale),
                          at: center, actionName: "Insert Video")
    }

    /// Adds a sound as a speaker icon in the middle of the slide.
    @discardableResult
    func insertAudio(data: Data, contentType: String, at center: SlidePoint? = nil) -> UUID? {
        insertClip(.audio, data: data, contentType: contentType, poster: nil, size: CGSize(width: audioIconSize, height: audioIconSize),
                   at: center, actionName: "Insert Audio")
    }

    private func insertClip(_ kind: MediaClip.Kind, data: Data, contentType: String, poster: Data?, size: CGSize, at center: SlidePoint?,
                            actionName: String) -> UUID? {
        guard currentSlideIndex != nil, !data.isEmpty else { return nil }
        let slide = presentation.slideSize
        let middle = center ?? SlidePoint(x: slide.width / 2, y: slide.height / 2)
        var probe = presentation
        let mediaID = probe.addMedia(data, contentType: contentType)
        let posterID = poster.map { probe.addMedia($0, contentType: "image/png") }
        var media = [mediaID: probe.media[mediaID]!]
        if let posterID { media[posterID] = probe.media[posterID] }
        let frame = SlideRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
        let element = SlideElement(name: nextElementName(kind == .video ? "Video" : "Audio"), placement: Placement(frame: frame),
                                   content: .media(MediaClip(kind: kind, mediaID: mediaID, posterID: posterID)))
        insert([element], media: media, actionName: actionName)
        return element.id
    }

    /// Changes the selected clip's playback settings.
    func editClip(_ actionName: String, _ edit: @escaping (inout MediaClip) -> Void) {
        guard let (element, _) = selectedClip else { return }
        editSelectedElements(actionName) { item, _ in
            guard item.id == element.id, var clip = item.media else { return }
            edit(&clip)
            item.content = .media(clip)
        }
    }

    func setClipPlayback(_ playback: MediaPlayback) {
        editClip("Playback") { clip in
            clip.playback = playback
            // Only a sound that starts by itself can hide its icon.
            if playback != .automatically { clip.hidesWhenPresenting = false }
        }
    }

    /// "Start at" and "End at", in seconds; nil is the beginning or the end.
    func setClipTrim(start: Double?, end: Double?) {
        editClip("Playback") { clip in
            clip.start = start.flatMap { $0 > 0 ? $0 : nil }
            clip.end = end
            if let from = clip.start, let to = clip.end, to < from { clip.end = from }
        }
    }

    func setClipMuted(_ muted: Bool) { editClip("Mute Audio") { $0.isMuted = muted } }
    func setClipVolume(_ volume: Double) { editClip("Volume") { $0.volume = min(1, max(0, volume)) } }
    func setClipLoops(_ loops: Bool) { editClip("Loop Audio") { $0.loops = loops } }
    func setClipHidesWhenPresenting(_ hides: Bool) { editClip("Hide Icon") { $0.hidesWhenPresenting = hides } }
    func setClipStopsOnSlideChange(_ stops: Bool) { editClip("Stop on Slide Change") { $0.stopsOnSlideChange = stops } }
}
