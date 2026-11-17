import AppKit
import PuggleSlidesKit

/// Videos and sounds on the canvas.
extension SlideEditingView {
    /// Whether a slide point is on a video's play button, which sits in the middle of the video.
    func playButtonContains(_ point: SlidePoint, of element: SlideElement) -> Bool {
        let placement = controller.placement(of: element)
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let local = placement.shapePoint(fromSlide: point)
        let radius = min(56, min(size.width, size.height) * 0.36) / 2
        return hypot(local.x - size.width / 2, local.y - size.height / 2) <= radius
    }

    /// An element's frame in this view, where a player can be placed over it.
    func viewRect(of element: SlideElement) -> CGRect {
        let frame = controller.placement(of: element).boundingBox
        return CGRect(x: frame.x + margin, y: frame.y + margin, width: frame.width, height: frame.height)
    }
}
