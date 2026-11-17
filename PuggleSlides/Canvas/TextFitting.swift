import AppKit
import PuggleSlidesKit

/// Text fitting, applied after text or size changes.
@MainActor
enum TextFitting {
    /// "Resize shape to fit text" sets the frame height (keeping the anchored edge in place); "Shrink text on
    /// overflow" sets the font scale. "Do not autofit" leaves the element alone.
    static func fit(_ element: inout SlideElement, on slide: Slide, in presentation: Presentation) {
        guard var shape = element.shape, var text = shape.text, !element.isLine else { return }
        let style = presentation.style(for: element, on: slide)
        let properties = style.bodyProperties
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        switch properties.autofit {
        case .none:
            return
        case .resizeShape:
            let height = TextMetrics.fittedHeight(style.resolvedParagraphs(), style: style, size: size)
            guard abs(height - size.height) > 0.01 else { return }
            element.placement = resized(placement, toHeight: height, anchor: properties.anchor)
        case .shrinkOnOverflow:
            var unscaled = element
            var unscaledText = text
            unscaledText.properties.fontScale = nil
            unscaledText.properties.lineSpacingReduction = nil
            shape.text = unscaledText
            unscaled.shape = shape
            let (scale, reduction) = TextMetrics.shrinkScale(for: unscaled, style: presentation.style(for: unscaled, on: slide), size: size)
            text.properties.fontScale = scale >= 1 ? nil : scale
            text.properties.lineSpacingReduction = scale >= 1 || reduction == 0 ? nil : reduction
            shape.text = text
            element.shape = shape
        }
    }

    /// The placement with a new height, growing away from the edge the text is anchored to.
    static func resized(_ placement: Placement, toHeight height: Double, anchor: VerticalAnchor) -> Placement {
        let frame = placement.frame
        let delta = height - abs(frame.height)
        // How far the center moves along the element's own vertical axis.
        let shift: Double = switch anchor {
        case .top: delta / 2
        case .middle: 0
        case .bottom: -delta / 2
        }
        let radians = placement.rotation * .pi / 180
        let center = CGPoint(x: frame.midX - shift * sin(radians), y: frame.midY + shift * cos(radians))
        var result = placement
        result.frame = SlideRect(x: center.x - abs(frame.width) / 2, y: center.y - height / 2, width: abs(frame.width), height: height)
        return result
    }
}
