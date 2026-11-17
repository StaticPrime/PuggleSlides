import AppKit

/// The play button on videos and the speaker icon of sounds, drawn in a flipped context.
enum MediaIcons {
    /// A dark round button with a white triangle, in the middle of a video.
    static func drawPlayButton(in box: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext, box.width > 8, box.height > 8 else { return }
        let side = min(56, min(box.width, box.height) * 0.36)
        let circle = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fillEllipse(in: circle)
        let height = side * 0.42, width = height * 0.88
        let left = circle.midX - width * 0.38
        context.move(to: CGPoint(x: left, y: circle.midY - height / 2))
        context.addLine(to: CGPoint(x: left + width, y: circle.midY))
        context.addLine(to: CGPoint(x: left, y: circle.midY + height / 2))
        context.closePath()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    /// The speaker as a PNG, `side` pixels square, for SVG downloads.
    static func speakerPNG(side: CGFloat) -> Data? {
        let pixels = Int(min(512, max(16, side.rounded())))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawSpeaker(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// A sound's speaker, filling its box.
    static func drawSpeaker(in box: CGRect) {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.27, green: 0.28, blue: 0.27, alpha: 1)])
        guard let symbol = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Audio")?
            .withSymbolConfiguration(configuration), symbol.size.width > 0, symbol.size.height > 0 else { return }
        let scale = min(box.width / symbol.size.width, box.height / symbol.size.height)
        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
