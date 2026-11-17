import AppKit
import AVFoundation
import PuggleSlidesKit

/// A video playing in a slideshow, in front of its poster. Clicks go through it to the show.
final class VideoHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Videos and sounds during a slideshow. A slide's clips wait for their moment: the slide appearing, a click once
/// the slide's animations have played, or a click on the video itself. Videos play over their poster; sounds that
/// don't stop on slide change play on over the slides after their own.
final class SlideshowMedia {
    final class Clip {
        let elementID: UUID
        let clip: MediaClip
        let player: AVPlayer
        /// Where the clip is on its slide.
        let frame: SlideRect
        let host: VideoHostView?
        var isPlaying = false
        var hasStarted = false
        var endObserver: NSObjectProtocol?

        init(elementID: UUID, clip: MediaClip, player: AVPlayer, frame: SlideRect, host: VideoHostView?) {
            self.elementID = elementID
            self.clip = clip
            self.player = player
            self.frame = frame
            self.host = host
        }
    }

    private weak var stage: SlideStageView?
    private let presentation: Presentation
    /// The current slide's clips.
    private(set) var clips: [Clip] = []
    /// Sounds from earlier slides still playing.
    private(set) var carried: [Clip] = []
    /// Clips that start with a click, in the order they will.
    private(set) var waiting: [UUID] = []
    private var pendingStart: DispatchWorkItem?

    init(presentation: Presentation, stage: SlideStageView) {
        self.presentation = presentation
        self.stage = stage
    }

    /// A new slide: what played on the old one stops (sounds that play over slides go on), and the new one's clips
    /// get ready. Clips that start automatically do once the transition, `delay` seconds long, is over. A slide shown
    /// fully built (going back) plays nothing by itself.
    func enter(_ slide: Slide, startAfter delay: Double, fullyBuilt: Bool) {
        pendingStart?.cancel()
        pendingStart = nil
        for item in clips {
            if !item.clip.isVideo, !item.clip.stopsOnSlideChange, item.isPlaying { carried.append(item) } else { stop(item) }
        }
        clips = []
        waiting = []
        for element in slide.elements {
            guard let clip = element.media, let item = makeClip(element, clip, on: slide) else { continue }
            clips.append(item)
            if clip.playback == .onClick, !fullyBuilt { waiting.append(element.id) }
        }
        layout()
        let automatic = fullyBuilt ? [] : clips.filter { $0.clip.playback == .automatically }
        guard !automatic.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in automatic.forEach { self?.play($0) } }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    /// A click with nothing else left to show on the slide starts the next clip waiting for one; false when none is.
    func startNextOnClick() -> Bool {
        guard !waiting.isEmpty else { return false }
        let id = waiting.removeFirst()
        if let item = clips.first(where: { $0.elementID == id }) { play(item) }
        return true
    }

    /// A click on a video that plays manually starts or pauses it; false when the click wasn't on one.
    func toggleVideo(at point: SlidePoint) -> Bool {
        for item in clips.reversed() where item.clip.isVideo && item.clip.playback == .manually {
            let frame = item.frame
            guard point.x >= frame.x, point.x <= frame.x + frame.width, point.y >= frame.y, point.y <= frame.y + frame.height else { continue }
            if item.isPlaying {
                item.player.pause()
                item.isPlaying = false
            } else {
                play(item)
            }
            return true
        }
        return false
    }

    /// Everything stops: the show ended.
    func stopAll() {
        pendingStart?.cancel()
        (clips + carried).forEach(stop)
        clips = []
        carried = []
        waiting = []
    }

    /// Puts each video over its poster in the stage.
    func layout() {
        guard let stage, let presentation = stage.controller?.presentation, presentation.slideSize.width > 0 else { return }
        let rect = stage.slideRect
        let scale = rect.width / presentation.slideSize.width
        for item in clips {
            item.host?.frame = CGRect(x: rect.minX + item.frame.x * scale, y: rect.minY + item.frame.y * scale,
                                      width: item.frame.width * scale, height: item.frame.height * scale)
        }
    }

    // MARK: Players

    private func makeClip(_ element: SlideElement, _ clip: MediaClip, on slide: Slide) -> Clip? {
        guard let url = MediaFiles.url(for: clip.mediaID, in: presentation) else { return nil }
        let playerItem = AVPlayerItem(url: url)
        if let end = clip.end { playerItem.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }
        let player = AVPlayer(playerItem: playerItem)
        player.volume = Float(min(1, max(0, clip.volume)))
        player.isMuted = clip.isMuted
        var host: VideoHostView?
        if clip.isVideo, let stage {
            let view = VideoHostView()
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            view.layer = layer
            view.wantsLayer = true
            view.isHidden = true
            view.setAccessibilityElement(false)
            stage.addSubview(view)
            host = view
        }
        let item = Clip(elementID: element.id, clip: clip, player: player, frame: presentation.placement(of: element, on: slide).boundingBox,
                        host: host)
        item.endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem,
                                                                  queue: .main) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let item else { return }
                if item.clip.loops {
                    self?.rewind(item)
                    item.player.play()
                } else {
                    item.isPlaying = false
                    self?.carried.removeAll { $0 === item }
                }
            }
        }
        return item
    }

    private func rewind(_ item: Clip) {
        item.player.seek(to: CMTime(seconds: item.clip.start ?? 0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func play(_ item: Clip) {
        if !item.hasStarted, (item.clip.start ?? 0) > 0 { rewind(item) }
        item.hasStarted = true
        item.host?.isHidden = false
        item.player.play()
        item.isPlaying = true
    }

    private func stop(_ item: Clip) {
        item.player.pause()
        item.isPlaying = false
        item.host?.removeFromSuperview()
        if let observer = item.endObserver { NotificationCenter.default.removeObserver(observer) }
        item.endObserver = nil
    }
}
