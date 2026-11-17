import CoreGraphics
import Foundation

/// Draws charts on screen and into PDFs, pictures and SVG.
///
/// A chart is laid out at the size it's drawn at, in points. Insert ▸ Chart's 450 × 278 point chart is a 600 × 371
/// pixel chart (12 pt title, 9 pt labels); smaller charts shrink their text and spacing but keep labels readable
/// (7 pt at the smallest), and bigger ones grow them slowly, so a chart filling a slide isn't blown up. Text uses the chart's font family, else Roboto, else Arial (whichever is installed).
///
/// The screen, PDF, picture and SVG versions of a chart all come from the same layout, so they look the same. Every
/// function is safe to call from any thread.
public enum ChartRenderer {
    /// Draws `chart` filling `rect`.
    ///
    /// `context` must have its origin at the top left with y growing downward, as the context of a flipped `NSView`
    /// does (for a bitmap or PDF context, which grows upward, translate by its height and scale y by -1 first).
    /// `rect` is in the context's current coordinates, in points. Text comes out upright in that system: Core Text
    /// lays text out with y growing upward, so lines are drawn through a flipped text matrix. Nothing is drawn
    /// outside `rect`, and the context's graphics state and text matrix are as they were when this returns. Empty,
    /// non-finite and absurdly big rects (over 100,000 points) draw nothing.
    public static func draw(_ chart: Chart, in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0, rect.width <= ChartComposer.maximumSide, rect.height <= ChartComposer.maximumSide,
              rect.minX.isFinite, rect.minY.isFinite else { return }
        let scene = ChartComposer.scene(for: chart, size: rect.size)
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        scene.render(in: context)
        context.restoreGState()
    }

    /// The chart as standalone SVG markup: an `<svg>` element whose `width`, `height` and `viewBox` are `size` in
    /// points (as plain numbers, so it nests in a slide's SVG whose units are points), with real text and shapes.
    /// There's no XML declaration, so the markup can be embedded in a larger document as is. Clip path ids are
    /// derived from the chart's content, so several charts can share one document.
    public static func svg(_ chart: Chart, size: CGSize) -> String {
        ChartComposer.scene(for: chart, size: sanitized(size)).svgElement()
    }

    /// The chart as a `<g>` element drawn in `rect` of a larger SVG whose units are points: the same markup as
    /// `svg(_:size:)` without the `<svg>` element, translated to the rect's origin.
    public static func svgGroup(_ chart: Chart, in rect: CGRect) -> String {
        let origin = CGPoint(x: rect.minX.isFinite ? rect.minX : 0, y: rect.minY.isFinite ? rect.minY : 0)
        return ChartComposer.scene(for: chart, size: sanitized(rect.size)).svgGroup(at: origin)
    }

    /// `size` with negative and non-finite sides made zero.
    private static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.isFinite ? Swift.max(0, size.width) : 0, height: size.height.isFinite ? Swift.max(0, size.height) : 0)
    }
}
