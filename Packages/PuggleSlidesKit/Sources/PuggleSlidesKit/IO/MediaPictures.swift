import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pictures a clip shows when it has no poster of its own: a dark frame for a video, a speaker icon for a sound.
/// PowerPoint files need a picture for every clip, so the writer stores one of these; readers recognize them (by their
/// bytes, or the description they carry) and leave the clip without a poster, as it was.
enum MediaPictures {
    /// What each picture's PNG description says, so it's recognized even when a later system encodes it differently.
    static let videoDescription = "PuggleSlides video poster"
    static let soundDescription = "PuggleSlides sound icon"

    /// A dark frame, stretched to the video's frame.
    static let videoPoster: Data = encode(drawVideoPoster(), description: videoDescription)
    /// A speaker on a dark disc, which shows on light and dark slides alike.
    static let soundIcon: Data = encode(drawSoundIcon(), description: soundDescription)

    static func picture(for kind: MediaClip.Kind) -> Data {
        kind == .video ? videoPoster : soundIcon
    }

    /// Pictures bigger than this aren't default pictures, so readers needn't look at them.
    static let maxDefaultSize = 64 * 1024

    /// Whether `data` is one of these pictures. Only small PNG files are looked into.
    static func isDefault(_ data: Data) -> Bool {
        if data == videoPoster || data == soundIcon { return true }
        guard data.count <= maxDefaultSize, data.starts(with: [0x89, 0x50, 0x4E, 0x47]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let description = png[kCGImagePropertyPNGDescription] as? String else { return false }
        return description == videoDescription || description == soundDescription
    }

    // MARK: Drawing

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func drawVideoPoster() -> CGImage? {
        guard let context = context(width: 64, height: 36) else { return nil }
        context.setFillColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return context.makeImage()
    }

    private static func drawSoundIcon() -> CGImage? {
        guard let context = context(width: 128, height: 128) else { return nil }
        context.setFillColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 0.92)
        context.fillEllipse(in: CGRect(x: 4, y: 4, width: 120, height: 120))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        // The speaker: a box and its cone, facing right.
        let speaker = CGMutablePath()
        speaker.move(to: CGPoint(x: 26, y: 50))
        speaker.addLine(to: CGPoint(x: 44, y: 50))
        speaker.addLine(to: CGPoint(x: 66, y: 30))
        speaker.addLine(to: CGPoint(x: 66, y: 98))
        speaker.addLine(to: CGPoint(x: 44, y: 78))
        speaker.addLine(to: CGPoint(x: 26, y: 78))
        speaker.closeSubpath()
        context.addPath(speaker)
        context.fillPath()
        // Two sound waves.
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.setLineWidth(7)
        context.setLineCap(.round)
        for radius in [16.0, 30.0] {
            context.addArc(center: CGPoint(x: 70, y: 64), radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
            context.strokePath()
        }
        return context.makeImage()
    }

    private static func encode(_ image: CGImage?, description: String) -> Data {
        let data = NSMutableData()
        guard let image, let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return Data()
        }
        let properties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: description]] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }
}
