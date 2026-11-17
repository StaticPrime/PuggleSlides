import AppKit
import AVFoundation
import AVKit
import PuggleSlidesKit
import UniformTypeIdentifiers

/// A clip playing on the canvas: a video with its controls over it, or a sound on its own.
final class ClipPreview {
    let elementID: UUID
    let player: AVPlayer
    let view: AVPlayerView?

    init(elementID: UUID, player: AVPlayer, view: AVPlayerView?) {
        self.elementID = elementID
        self.player = player
        self.view = view
    }

    func stop() {
        player.pause()
        view?.removeFromSuperview()
    }
}

/// Insert ▸ Video and Insert ▸ Audio, dropped movies and sounds, and playing a clip on the canvas.
extension DocumentWindowController {
    /// Larger files don't fit in a presentation file.
    static let largestClip = 512 << 20

    func ppInsertVideo(_ sender: Any?) { chooseMedia(video: true) }
    func ppInsertAudio(_ sender: Any?) { chooseMedia(video: false) }

    /// The toolbar's Play button.
    func playClip() { ppPlayClip(nil) }

    func ppPlayClip(_ sender: Any?) {
        guard let (element, _) = controller.selectedClip else { return }
        playClipInEditor(element.id)
    }

    private func chooseMedia(video: Bool) {
        finishEditing()
        guard let window, controller.currentSlide != nil else { return }
        if isGridView { setGridView(false) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = video ? [.movie] : [.audio]
        panel.allowsMultipleSelection = false
        panel.message = video ? "Choose a video to insert" : "Choose a sound to insert"
        panel.prompt = "Insert"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.insertMedia(from: url) }
        }
    }

    /// Movies and sounds dropped on the slide, one after another, each a little below and to the right of the last.
    func insertDroppedMedia(_ urls: [URL], at point: SlidePoint) {
        Task { @MainActor in
            for (index, url) in urls.enumerated() {
                await insertMedia(from: url, at: SlidePoint(x: point.x + Double(index) * 18, y: point.y + Double(index) * 18))
            }
        }
    }

    /// Reads a movie or a sound and puts it on the current slide; says why when it can't.
    func insertMedia(from url: URL, at center: SlidePoint? = nil) async {
        let name = url.lastPathComponent
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.largestClip {
            showMediaProblem("“\(name)” is too large to insert", "Videos and sounds in a presentation can be up to 512 MB.")
            return
        }
        guard let data = try? Data(contentsOf: url), let type = MediaFiles.contentType(of: url, data: data) else {
            showMediaProblem("“\(name)” can't be inserted", "It isn't a video or sound file macOS can play.")
            return
        }
        if type.hasPrefix("video/") {
            guard let info = await MediaFiles.inspectMovie(at: url) else {
                showMediaProblem("“\(name)” can't be played", "PuggleSlides plays the videos macOS can play, such as MP4 and MOV files.")
                return
            }
            controller.insertVideo(data: data, contentType: type, poster: info.poster, size: info.size, at: center)
        } else {
            guard await MediaFiles.inspectSound(at: url) != nil else {
                showMediaProblem("“\(name)” can't be played", "PuggleSlides plays the sounds macOS can play, such as MP3, M4A and WAV files.")
                return
            }
            controller.insertAudio(data: data, contentType: type, at: center)
        }
        focusCanvas()
    }

    private func showMediaProblem(_ message: String, _ detail: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    // MARK: Playing on the canvas

    /// Plays a clip where it is: a video with playback controls over it, a sound on its own, from its start time to
    /// its end time. Selecting something else, another slide or Esc stops it.
    func playClipInEditor(_ elementID: UUID) {
        stopClipPreview()
        guard let element = controller.currentSlide?.element(id: elementID), let clip = element.media,
              let url = MediaFiles.url(for: clip.mediaID, in: controller.presentation) else { return }
        let item = AVPlayerItem(url: url)
        if let end = clip.end { item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }
        let player = AVPlayer(playerItem: item)
        player.isMuted = clip.isMuted
        if let start = clip.start, start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        var view: AVPlayerView?
        if clip.isVideo {
            let playerView = AVPlayerView(frame: canvas.viewRect(of: element))
            playerView.player = player
            playerView.controlsStyle = .inline
            playerView.showsFullScreenToggleButton = false
            playerView.setAccessibilityLabel("Video player")
            canvas.addSubview(playerView)
            view = playerView
        }
        clipPreview = ClipPreview(elementID: elementID, player: player, view: view)
        player.play()
    }

    func stopClipPreview() {
        clipPreview?.stop()
        clipPreview = nil
    }

    /// A preview stops when its clip is no longer the selection.
    func syncClipPreview() {
        guard let preview = clipPreview else { return }
        if controller.selectedElementIDs != [preview.elementID] || controller.currentSlide?.element(id: preview.elementID) == nil {
            stopClipPreview()
        } else if let view = preview.view, let element = controller.currentSlide?.element(id: preview.elementID) {
            view.frame = canvas.viewRect(of: element)
        }
    }

    func validateMedia(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(SlideCommands.ppInsertVideo(_:)), #selector(SlideCommands.ppInsertAudio(_:)):
            return controller.currentSlide != nil
        case #selector(SlideCommands.ppPlayClip(_:)):
            return controller.selectedClip != nil
        default:
            return nil
        }
    }
}
