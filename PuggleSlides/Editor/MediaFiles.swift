import AppKit
import AVFoundation
import PuggleSlidesKit
import UniformTypeIdentifiers

/// Embedded movies and sounds as files AVFoundation can open: each is written once to the app's temporary folder.
enum MediaFiles {
    private static var urls: [String: URL] = [:]
    private static var hasCleared = false

    /// A file holding a presentation's media item; nil when it can't be written.
    static func url(for id: MediaID, in presentation: Presentation) -> URL? {
        guard let item = presentation.media[id], !item.data.isEmpty else { return nil }
        // Ids are only unique within a presentation, so the contents name the file too.
        let key = "\(id)-\(item.data.count)-\(item.data.prefix(4096).hashValue)"
        if let url = urls[key], FileManager.default.fileExists(atPath: url.path) { return url }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Media", isDirectory: true)
        if !hasCleared {
            // Files from earlier launches aren't needed any more.
            try? FileManager.default.removeItem(at: folder)
            hasCleared = true
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString).\(item.fileExtension)")
        do {
            try item.data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        urls[key] = url
        return url
    }

    /// A movie or sound's MIME type, from its file name or its first bytes.
    static func contentType(of url: URL, data: Data) -> String? {
        if let sniffed = MediaItem.contentType(sniffing: data), !sniffed.hasPrefix("image/") { return sniffed }
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audiovisualContent) else { return nil }
        return type.preferredMIMEType
    }

    /// What Insert ▸ Video needs from a movie: its first frame as PNG, its size as shown, and its length.
    struct MovieInfo {
        var poster: Data?
        var size: CGSize
        var duration: Double
    }

    /// Nil when AVFoundation can't play the movie.
    static func inspectMovie(at url: URL) async -> MovieInfo? {
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
              let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let natural = (try? await track.load(.naturalSize)) ?? CGSize(width: 640, height: 360)
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        var poster: Data?
        if let (image, _) = try? await generator.image(at: CMTime(seconds: min(0.1, duration / 2), preferredTimescale: 600)) {
            poster = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
        return MovieInfo(poster: poster, size: CGSize(width: abs(shown.width), height: abs(shown.height)), duration: duration.isFinite ? duration : 0)
    }

    /// A sound's length; nil when AVFoundation can't play it.
    static func inspectSound(at url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
              let track = try? await asset.loadTracks(withMediaType: .audio).first,
              (try? await track.load(.isPlayable)) == true else { return nil }
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        return duration.isFinite ? duration : 0
    }

    /// A clip's length in its file, for Format options' times; nil while it can't be read.
    static func duration(of clip: MediaClip, in presentation: Presentation) async -> Double? {
        guard let url = url(for: clip.mediaID, in: presentation) else { return nil }
        let duration = (try? await AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds)
        return duration.flatMap { $0.isFinite ? $0 : nil }
    }
}
