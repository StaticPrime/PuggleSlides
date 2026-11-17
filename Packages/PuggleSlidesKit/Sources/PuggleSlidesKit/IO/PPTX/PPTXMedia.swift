import Foundation

/// Videos and sounds, embedded the way PowerPoint 2010 and later embed them. A clip is a picture (`p:pic`, whose picture is
/// the poster) with the movie or sound named twice in its `p:nvPr`: `a:videoFile` or `a:audioFile` links it through a
/// video or audio relationship (ECMA-376 Part 1, 20.1.3.6 and 20.1.3.1; parts 15.2.17 and 15.2.2), and the `p14:media`
/// extension embeds it through a media relationship, with its trim ([MS-PPTX] 2.1.1, 2.2.4, 2.3.3.14, 2.3.3.18).
/// How it plays is in the slide's timing (`PPTXAnimationWriter`, `PPTXAnimationReader`): a media node (`p:video` or
/// `p:audio` with `p:cMediaNode`, 19.5.93, 19.5.9, 19.5.29) holds the volume, mute, loop, whether it shows while stopped and
/// how many slides it plays across; a play command (`p:cmd`, 19.5.28) in the main sequence starts it with a click or as the
/// slide appears; a sequence its own click triggers plays and pauses it otherwise.
enum PPTXMedia {
    /// The `p:ext` of `p:nvPr` that holds `p14:media` ([MS-PPTX] 2.2.4).
    static let extensionURI = "{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}"
    /// The Media part's relationship ([MS-PPTX] 2.1.1), and the Video and Audio parts' (transitional names).
    static let mediaRelationship = "http://schemas.microsoft.com/office/2007/relationships/media"
    static let videoRelationship = PPTXRelationshipType.base + "video"
    static let audioRelationship = PPTXRelationshipType.base + "audio"
    /// A movie may be much bigger than a picture; the package's read budget still bounds them all together.
    static let maxClipSize = 1 << 30

    // MARK: Content types

    /// The content type of a media file by its extension, as written in [Content_Types].xml.
    static func contentType(forExtension fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "mp4", "mpg4": "video/mp4"
        case "m4v": "video/x-m4v"
        case "mov", "qt": "video/quicktime"
        case "avi": "video/x-msvideo"
        case "wmv": "video/x-ms-wmv"
        case "mpg", "mpeg": "video/mpeg"
        case "mp3": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "aac": "audio/aac"
        case "wav", "wave": "audio/wav"
        case "aif", "aiff", "aifc": "audio/aiff"
        case "wma": "audio/x-ms-wma"
        case "mid", "midi": "audio/midi"
        case "ogg", "oga", "opus": "audio/ogg"
        case "flac": "audio/flac"
        case "ogv": "video/ogg"
        case "webm": "video/webm"
        case "mkv": "video/x-matroska"
        default: nil
        }
    }

    /// The extension a media part is stored with: the model's, or for movies and sounds it has none for, the usual one.
    static func fileExtension(_ item: MediaItem) -> String {
        let known = item.fileExtension
        guard known == "bin" else { return known }
        switch item.contentType.lowercased() {
        case "video/mpeg": return "mpg"
        case "video/ogg": return "ogv"
        case "video/webm": return "webm"
        case "video/x-matroska": return "mkv"
        case "audio/ogg": return "ogg"
        case "audio/flac": return "flac"
        case "audio/midi", "audio/mid": return "mid"
        default: return known
        }
    }

    /// A declared type that says what a file is: audio or video, but not PowerPoint's "video/unknown" and "audio/unknown".
    static func isTelling(_ declared: String) -> Bool {
        let type = declared.lowercased()
        return (type.hasPrefix("audio/") || type.hasPrefix("video/")) && !type.hasSuffix("/unknown")
    }

    /// Sounds by the extension of a part or file they're stored in.
    static func isAudio(path: String) -> Bool {
        let fileExtension = path.split(separator: ".").last.map(String.init) ?? ""
        return contentType(forExtension: fileExtension)?.hasPrefix("audio/") ?? false
    }

    // MARK: Times

    /// [MS-PPTX]'s ST_UniversalTimeOffset in milliseconds: a number with an optional unit, milliseconds by default.
    static func milliseconds(_ text: String?) -> Double? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var factor = 1.0
        for (unit, scale) in [("min", 60_000.0), ("ms", 1), ("µs", 0.001), ("us", 0.001), ("ns", 0.000_001), ("h", 3_600_000), ("s", 1000)]
        where text.hasSuffix(unit) {
            text.removeLast(unit.count)
            factor = scale
            break
        }
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return min(value * factor, 1e12)
    }

    /// Milliseconds as ST_UniversalTimeOffset: digits, maybe a fraction, never an exponent.
    static func timeOffset(milliseconds: Double) -> String {
        let value = min(max(milliseconds.isFinite ? milliseconds : 0, 0), 1e12)
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: Commands

    /// Whether a `p:cmd` starts or resumes playback: play, playFrom(s), resume and togglePause (19.5.28).
    static func isPlayCommand(_ node: XNode) -> Bool {
        guard node.name == "cmd", (node["type"] ?? "call") == "call" else { return false }
        let command = (node["cmd"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return command == "play" || command.hasPrefix("playfrom") || command == "togglepause" || command == "resume"
    }

    /// The shape a behavior or media node targets.
    static func targetShape(_ node: XNode) -> String? {
        (node.child("cBhvr") ?? node.child("cMediaNode"))?.child("tgtEl")?.child("spTgt")?["spid"]
    }

    // MARK: Media node

    /// A clip's settings from its media node's `p:cMediaNode`: the volume (50% when not stated), mute, whether it shows
    /// while stopped, loops (repeats indefinitely) and, for a sound, plays across slides.
    static func apply(mediaNode node: XNode, to clip: inout MediaClip) {
        clip.volume = min(max(PPTXValue.fraction(node["vol"]) ?? 0.5, 0), 1)
        clip.isMuted = PPTXValue.bool(node["mute"]) ?? false
        clip.hidesWhenPresenting = PPTXValue.bool(node["showWhenStopped"]) == false
        clip.loops = node.child("cTn")?["repeatCount"]?.trimmingCharacters(in: .whitespaces) == "indefinite"
        clip.stopsOnSlideChange = clip.kind == .video || (PPTXValue.int(node["numSld"]) ?? 1) <= 1
    }
}

// MARK: - Reading

extension PPTXPartContext {
    /// What a picture's `nvPr` says about a movie or sound it plays.
    struct MediaSource {
        var kind: MediaClip.Kind
        /// The embedded movie or sound; nil when it's linked, missing or too large.
        var mediaID: MediaID?
        var trim: XNode?
    }

    /// The media a picture plays, if any. `p14:media` embeds it ([MS-PPTX]: when it also links, the link wins); without
    /// it, a video or audio file whose relationship stays in the package is embedded too. Files outside the package, CD
    /// tracks and media that can't be read have no media.
    func mediaSource(_ nvPr: XNode?) -> MediaSource? {
        guard let nvPr else { return nil }
        var kind: MediaClip.Kind?
        var fileRelationship: PPTXRelationship?
        var isCD = false
        for child in nvPr.children {
            switch child.name {
            case "videoFile", "quickTimeFile":
                kind = .video
                fileRelationship = relationships[child["link"]]
            case "audioFile":
                kind = .audio
                fileRelationship = relationships[child["link"]]
            case "wavAudioFile":
                kind = .audio
                fileRelationship = relationships[child["embed"]]
            case "audioCd":
                kind = .audio
                isCD = true
            default:
                continue
            }
        }
        let extensions = nvPr.child("extLst")?.children("ext") ?? []
        let media = extensions.first { $0["uri"] == PPTXMedia.extensionURI }?.child("media") ?? extensions.lazy.compactMap { $0.child("media") }.first
        guard kind != nil || media != nil else { return nil }
        var relationship: PPTXRelationship?
        var isLinked = isCD
        if let media {
            if let link = media["link"], !link.isEmpty {
                isLinked = true
                relationship = relationships[link]
            } else {
                relationship = relationships[media["embed"]]
            }
        }
        if relationship == nil, !isCD { relationship = fileRelationship }
        let guessed = kind ?? (relationship.map { PPTXMedia.isAudio(path: $0.target) } == true ? .audio : .video)
        guard !isLinked, let relationship, !relationship.isExternal,
              let mediaID = package.media(at: relationship.target, maxSize: PPTXMedia.maxClipSize) else {
            return MediaSource(kind: guessed, mediaID: nil, trim: nil)
        }
        let resolved = kind ?? ((package.media[mediaID]?.isAudio ?? false) ? .audio : guessed)
        return MediaSource(kind: resolved, mediaID: mediaID, trim: media?.child("trim"))
    }

    /// A clip from a picture that plays embedded media. Its picture is the poster, unless it's the default one the writer
    /// stores for clips without a poster; a picture that's missing leaves the clip without one. The trim's end, which
    /// counts back from the end of the media, needs the media's length; without it, the clip plays to the end.
    func clip(_ source: MediaSource, mediaID: MediaID, blip: XNode?) -> MediaClip {
        // Without timing, nothing plays it but its own controls.
        var clip = MediaClip(kind: source.kind, mediaID: mediaID, playback: .manually)
        if let relationship = relationships[blip?["embed"]], !relationship.isExternal {
            let small = package.data(at: relationship.target, maxSize: MediaPictures.maxDefaultSize)
            clip.posterID = small.map(MediaPictures.isDefault) == true ? nil : package.media(at: relationship.target)
        }
        if let trim = source.trim {
            func rounded(_ seconds: Double) -> Double { (seconds * 1_000_000).rounded() / 1_000_000 }
            let start = (PPTXMedia.milliseconds(trim["st"]) ?? 0) / 1000
            let cut = (PPTXMedia.milliseconds(trim["end"]) ?? 0) / 1000
            if start > 0 { clip.start = rounded(start) }
            if cut > 0, let data = package.media[mediaID]?.data, let duration = PPTXMediaDuration.seconds(of: data), duration - cut > start {
                clip.end = rounded(duration - cut)
            }
        }
        return clip
    }
}

// MARK: - Writing

/// A clip the part writer wrote: its shape id, which the slide's timing targets.
struct PPTXWrittenClip {
    var spid: Int
    var clip: MediaClip
}

extension PPTXPartWriter {
    /// A relationship of a type to a media part or a default picture, once per part and type.
    mutating func mediaRelationship(type: String, to part: String) -> String {
        let key = type + " " + part
        if let known = clipRelationships[key] { return known }
        let id = relationship(type: type, to: part)
        clipRelationships[key] = id
        return id
    }

    /// A clip as PowerPoint writes one: a picture whose `cNvPr` has the media click action, whose `nvPr` links the file and
    /// embeds it in `p14:media` with the trim, and whose picture is the poster, or the default picture for its kind.
    mutating func clip(_ element: SlideElement, _ clip: MediaClip) {
        guard let part = state.mediaPath(clip.mediaID) else { return }
        let poster = clip.posterID.flatMap { imageRelationship($0) }
            ?? mediaRelationship(type: PPTXRelationshipType.image, to: state.defaultPicturePath(clip.kind))
        let embed = mediaRelationship(type: PPTXMedia.mediaRelationship, to: part)
        let link = mediaRelationship(type: clip.kind == .video ? PPTXMedia.videoRelationship : PPTXMedia.audioRelationship, to: part)
        xml.raw("<p:pic><p:nvPicPr>")
        let spid = nonVisualProperties(element, fallbackName: clip.kind == .video ? "Video" : "Audio", kind: .picture, mediaAction: true)
        xml.raw("<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr>")
        if let placeholder = element.placeholder {
            xml.raw("<p:ph")
            if placeholder.type != .object { xml.attribute("type", placeholder.type.rawValue) }
            if placeholder.index != 0 { xml.attribute("idx", min(max(placeholder.index, 0), Int(UInt32.max))) }
            xml.raw("/>")
        }
        xml.raw(clip.kind == .video ? "<a:videoFile r:link=\"\(link)\"/>" : "<a:audioFile r:link=\"\(link)\"/>")
        xml.raw("<p:extLst><p:ext uri=\"\(PPTXMedia.extensionURI)\"><p14:media xmlns:p14=\"\(PPTXNamespace.powerPoint2010)\" r:embed=\"\(embed)\"")
        if let trim = trim(clip) {
            xml.raw("><p14:trim")
            if let start = trim.start { xml.attribute("st", PPTXMedia.timeOffset(milliseconds: start * 1000)) }
            if let cut = trim.cut { xml.attribute("end", PPTXMedia.timeOffset(milliseconds: cut * 1000)) }
            xml.raw("/></p14:media>")
        } else {
            xml.raw("/>")
        }
        xml.raw("</p:ext></p:extLst></p:nvPr></p:nvPicPr>")
        xml.raw("<p:blipFill><a:blip r:embed=\"\(poster)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>")
        if let placement = element.placement { transform(placement) }
        xml.raw("<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>")
        writtenClips.append(PPTXWrittenClip(spid: spid, clip: clip))
    }

    /// The trim in seconds: from the start, and back from the end, which needs the media's length. Each must leave
    /// something to play; nil when there's nothing to trim.
    private func trim(_ clip: MediaClip) -> (start: Double?, cut: Double?)? {
        let start = clip.start.flatMap { $0.isFinite && $0 >= 0.000_001 ? $0 : nil }
        var cut: Double?
        if let end = clip.end, end.isFinite, let duration = state.duration(of: clip.mediaID) {
            let remaining = duration - end
            if remaining >= 0.000_001, end > (start ?? 0) { cut = remaining }
        }
        if let length = state.duration(of: clip.mediaID), let start, start >= length - (cut ?? 0) { return cut.map { (nil, $0) } }
        guard start != nil || cut != nil else { return nil }
        return (start, cut)
    }
}
