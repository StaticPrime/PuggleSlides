import Foundation

/// When a video or a sound starts during a slideshow.
public enum MediaPlayback: String, Codable, Sendable, CaseIterable {
    /// With the next click, the way an animation set to start on click does. The default.
    case onClick
    /// As soon as the slide appears.
    case automatically
    /// Only when its play button is clicked.
    case manually

    /// The words in Format options' playback menus.
    public var title: String {
        switch self {
        case .onClick: "On click"
        case .automatically: "Automatically"
        case .manually: "Manually"
        }
    }
}

/// Insert ▸ Video and Insert ▸ Audio: a movie or a sound the presentation embeds. A video shows its poster frame
/// until it plays; a sound shows as a speaker icon, which can be hidden while presenting.
public struct MediaClip: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case video, audio
    }

    public var kind: Kind
    /// The movie or sound, in the presentation's media.
    public var mediaID: MediaID
    /// A video's poster frame, the picture shown before it plays. Nil draws a dark frame.
    public var posterID: MediaID?
    public var playback: MediaPlayback
    /// "Start at" and "End at": where it starts and stops, in seconds from the beginning of the file. Nil is the
    /// beginning and the end.
    public var start: Double?
    public var end: Double?
    /// "Volume when presenting", 0 to 1.
    public var volume: Double
    /// "Mute audio".
    public var isMuted: Bool
    /// "Loop audio": starts again each time it ends.
    public var loops: Bool
    /// "Hide icon when presenting": the speaker icon of a sound that starts by itself doesn't show in slideshows.
    public var hidesWhenPresenting: Bool
    /// "Stop on slide change": false keeps a sound playing over the slides after its own.
    public var stopsOnSlideChange: Bool

    public init(kind: Kind, mediaID: MediaID, posterID: MediaID? = nil, playback: MediaPlayback = .onClick, start: Double? = nil,
                end: Double? = nil, volume: Double = 1, isMuted: Bool = false, loops: Bool = false, hidesWhenPresenting: Bool = false,
                stopsOnSlideChange: Bool = true) {
        self.kind = kind
        self.mediaID = mediaID
        self.posterID = posterID
        self.playback = playback
        self.start = start
        self.end = end
        self.volume = volume
        self.isMuted = isMuted
        self.loops = loops
        self.hidesWhenPresenting = hidesWhenPresenting
        self.stopsOnSlideChange = stopsOnSlideChange
    }

    public var isVideo: Bool { kind == .video }

    /// Media the clip shows: its file and its poster.
    public var mediaIDs: Set<MediaID> { Set([mediaID] + (posterID.map { [$0] } ?? [])) }

    /// The trim as a range of seconds, given the file's length.
    public func playRange(duration: Double) -> ClosedRange<Double> {
        let length = duration.isFinite ? max(0, duration) : 0
        let from = min(max(0, start ?? 0), length)
        let to = min(max(from, end ?? length), length)
        return from...to
    }
}

/// The size a sound's speaker icon is given when inserted: 32 pixels at 100%.
public let audioIconSize = 24.0
