import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension MediaItem {
    /// A picture as it's kept in a presentation: one that comes as TIFF or BMP (as pasted and dragged pictures often
    /// do), uncompressed and many times the size of the same picture as PNG, becomes PNG, with its resolution kept so it
    /// shows at the same size; anything else stays as it is. Nil when `data` isn't a kind of file presentations hold.
    /// Keeping pictures small keeps files, and the changes and snapshots of shared presentations, small too.
    public static func storable(_ data: Data) -> (data: Data, contentType: String)? {
        guard let type = contentType(sniffing: data) else { return nil }
        guard type == "image/tiff" || type == "image/bmp", let png = png(from: data) else { return (data, type) }
        return (png, "image/png")
    }

    /// The first picture in `data` as PNG, with its resolution and orientation.
    static func png(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var properties: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyOrientation] {
            if let value = original[key] { properties[key] = value }
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
