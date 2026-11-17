import AppKit
import CoreImage
import PuggleSlidesKit

/// Word art: the letters' outlines, stretched to fill the frame, filled and outlined with the shape's own fill and
/// border.
@MainActor
enum WordArt {
    private struct Key: Hashable {
        let paragraphs: [ResolvedParagraph]
    }

    private static var cache: [Key: CGPath] = [:]

    /// The letters of every line, stacked and centered, in points with y growing downward.
    static func glyphPath(_ paragraphs: [ResolvedParagraph]) -> CGPath {
        let key = Key(paragraphs: paragraphs)
        if let path = cache[key] { return path }
        if cache.count > 200 { cache.removeAll() }
        let path = CGMutablePath()
        var lines: [(line: CTLine, width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat)] = []
        for paragraph in paragraphs {
            let text = NSMutableAttributedString()
            for run in paragraph.runs where !run.text.isEmpty {
                let style = run.style
                let font = SlideFonts.font(family: style.fontFamily, size: style.fontSize, bold: style.bold, italic: style.italic)
                text.append(NSAttributedString(string: run.text.replacingOccurrences(of: TextRun.lineBreak, with: " "), attributes: [.font: font]))
            }
            if text.length == 0 {
                let style = paragraph.endStyle
                text.append(NSAttributedString(string: " ", attributes: [.font: SlideFonts.font(family: style.fontFamily, size: style.fontSize,
                                                                                               bold: style.bold, italic: style.italic)]))
            }
            let line = CTLineCreateWithAttributedString(text)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            lines.append((line, width, ascent, descent, leading))
        }
        let widest = lines.map(\.width).max() ?? 0
        var baseline: CGFloat = 0
        for item in lines {
            baseline += item.ascent
            let left = (widest - item.width) / 2
            for run in (CTLineGetGlyphRuns(item.line) as? [CTRun]) ?? [] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let fontValue = attributes[kCTFontAttributeName], CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID() else { continue }
                let font = fontValue as! CTFont
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for index in 0..<count {
                    // Glyph outlines are y-up; flip them into the y-down space slides use.
                    var transform = CGAffineTransform(translationX: left + positions[index].x, y: baseline).scaledBy(x: 1, y: -1)
                    if let glyph = CTFontCreatePathForGlyph(font, glyphs[index], &transform) { path.addPath(glyph) }
                }
            }
            baseline += item.descent + item.leading
        }
        cache[key] = path
        return path
    }

    /// The letters mapped onto a frame of the given size.
    static func fittedPath(_ paragraphs: [ResolvedParagraph], size: CGSize) -> CGPath? {
        let path = glyphPath(paragraphs)
        let bounds = path.boundingBoxOfPath
        guard !path.isEmpty, bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return nil }
        var transform = CGAffineTransform(scaleX: size.width / bounds.width, y: size.height / bounds.height)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
        return path.copy(using: &transform)
    }

    /// The size word art takes for its text at the text's own size, for a new word art object.
    static func naturalSize(_ paragraphs: [ResolvedParagraph]) -> CGSize {
        let bounds = glyphPath(paragraphs).boundingBoxOfPath
        return CGSize(width: max(10, bounds.width), height: max(10, bounds.height))
    }
}

extension SlideRenderer {
    static func drawWordArt(_ shape: Shape, element: SlideElement, style: ElementStyle, presentation: Presentation, options: Options) {
        guard let context = NSGraphicsContext.current?.cgContext, element.id != options.hiddenTextElementID else { return }
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        guard let path = WordArt.fittedPath(style.resolvedParagraphs(slideNumber: options.slideNumber), size: size) else { return }
        context.saveGState()
        context.concatenate(placement.transform)
        paint(style.fill, path: path, theme: style.theme, presentation: presentation, mode: .normal)
        stroke([ShapePath(path: path, fill: .none)], outline: style.outline, theme: style.theme, isLine: false)
        context.restoreGState()
    }
}

/// Pictures with Format options ▸ Adjustments and Recolor applied, made once and kept.
@MainActor
enum AdjustedImages {
    private static var cache: [String: NSImage] = [:]
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(_ picture: Picture, theme: SlideTheme, presentation: Presentation) -> NSImage? {
        guard let original = ImageCache.shared.image(picture.mediaID, in: presentation) else { return nil }
        let adjustments = picture.adjustments
        guard adjustments.brightness != 0 || adjustments.contrast != 0 || adjustments.recolor != nil else { return original }
        var key = "\(picture.mediaID)|\(presentation.media[picture.mediaID]?.data.count ?? 0)|\(adjustments.brightness)|\(adjustments.contrast)"
        if let recolor = adjustments.recolor {
            let ends = recolor.ends(in: theme.colors)
            key += "|\(ends.dark)|\(ends.light)"
        }
        if let cached = cache[key] { return cached }
        if cache.count > 60 { cache.removeAll() }
        guard let data = presentation.media[picture.mediaID]?.data, var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return original
        }
        let extent = image.extent
        if adjustments.brightness != 0 || adjustments.contrast != 0, let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(image, forKey: kCIInputImageKey)
            controls.setValue(adjustments.brightness * 0.6, forKey: kCIInputBrightnessKey)
            // −1 flattens the picture to gray; +1 makes it three times as contrasty.
            controls.setValue(adjustments.contrast >= 0 ? 1 + adjustments.contrast * 2 : 1 + adjustments.contrast, forKey: kCIInputContrastKey)
            image = controls.outputImage ?? image
        }
        if let recolor = adjustments.recolor, let falseColor = CIFilter(name: "CIFalseColor") {
            let ends = recolor.ends(in: theme.colors)
            falseColor.setValue(image, forKey: kCIInputImageKey)
            falseColor.setValue(CIColor(red: ends.dark.red, green: ends.dark.green, blue: ends.dark.blue), forKey: "inputColor0")
            falseColor.setValue(CIColor(red: ends.light.red, green: ends.light.green, blue: ends.light.blue), forKey: "inputColor1")
            // False color drops transparency; put the picture's alpha back.
            if let colored = falseColor.outputImage, let mask = CIFilter(name: "CIBlendWithAlphaMask") {
                mask.setValue(colored, forKey: kCIInputImageKey)
                mask.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                mask.setValue(image, forKey: kCIInputMaskImageKey)
                image = mask.outputImage ?? colored
            }
        }
        guard let cgImage = context.createCGImage(image.cropped(to: extent), from: extent) else { return original }
        let result = NSImage(cgImage: cgImage, size: original.size)
        cache[key] = result
        return result
    }
}
