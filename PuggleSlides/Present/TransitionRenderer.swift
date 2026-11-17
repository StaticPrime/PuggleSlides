import AppKit
import PuggleSlidesKit

/// Draws the slide transitions frame by frame into the current (flipped) graphics context.
@MainActor
enum TransitionRenderer {
    /// Draws the transition `progress` (0...1) of the way from `old` to `new`, both pictures of `rect`'s size.
    static func draw(_ kind: TransitionKind, progress: Double, from old: CGImage?, to new: CGImage, in rect: CGRect, seed: UInt64) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let p = CGFloat(max(0, min(1, progress)))
        let eased = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        context.saveGState()
        context.clip(to: rect.insetBy(dx: -rect.width, dy: 0))
        switch kind {
        case .none:
            image(new, in: rect)
        case .fade:
            if let old { image(old, in: rect) }
            image(new, in: rect, alpha: p)
        case .dissolve:
            if let old { image(old, in: rect) }
            dissolve(new, in: rect, progress: p, seed: seed)
        case .slideFromRight, .slideFromLeft:
            if let old { image(old, in: rect) }
            let direction: CGFloat = kind == .slideFromRight ? 1 : -1
            image(new, in: rect.offsetBy(dx: direction * rect.width * (1 - eased), dy: 0))
        case .gallery:
            let dip = 1 - 0.12 * sin(.pi * p)
            func scaled(_ frame: CGRect) -> CGRect {
                CGRect(x: frame.midX - frame.width * dip / 2, y: frame.midY - frame.height * dip / 2, width: frame.width * dip, height: frame.height * dip)
            }
            if let old { image(old, in: scaled(rect.offsetBy(dx: -rect.width * eased, dy: 0))) }
            image(new, in: scaled(rect.offsetBy(dx: rect.width * (1 - eased), dy: 0)))
        case .flip:
            if p < 0.5 {
                if let old { turned(old, in: rect, angle: eased * .pi) }
            } else {
                turned(new, in: rect, angle: eased * .pi - .pi)
            }
        case .cube:
            // The cube pulls back a little as it turns, so its edges stay on screen.
            let dip = 1 - 0.18 * sin(.pi * p)
            let cubeRect = CGRect(x: rect.midX - rect.width * dip / 2, y: rect.midY - rect.height * dip / 2,
                                  width: rect.width * dip, height: rect.height * dip)
            cube(old: old, new: new, in: cubeRect, angle: eased * .pi / 2)
        }
        context.restoreGState()
    }

    /// Draws an image upright in a flipped context.
    static func image(_ image: CGImage, in rect: CGRect, alpha: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext, alpha > 0.001 else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Dissolve: the new slide appears block by block, in a random order.
    private static func dissolve(_ new: CGImage, in rect: CGRect, progress: CGFloat, seed: UInt64) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let columns = 40, rows = max(1, Int((CGFloat(columns) * rect.height / max(rect.width, 1)).rounded()))
        let cellWidth = rect.width / CGFloat(columns), cellHeight = rect.height / CGFloat(rows)
        var state = seed | 1
        var cells: [CGRect] = []
        for row in 0..<rows {
            for column in 0..<columns {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let threshold = CGFloat(state >> 40) / CGFloat(1 << 24)
                if threshold < progress {
                    cells.append(CGRect(x: rect.minX + CGFloat(column) * cellWidth, y: rect.minY + CGFloat(row) * cellHeight,
                                        width: cellWidth + 0.5, height: cellHeight + 0.5))
                }
            }
        }
        guard !cells.isEmpty else { return }
        context.saveGState()
        context.clip(to: cells)
        image(new, in: rect)
        context.restoreGState()
    }

    /// One face turned about its vertical center line by `angle` (radians), seen in perspective.
    private static func turned(_ face: CGImage, in rect: CGRect, angle: CGFloat) {
        let half = rect.width / 2, distance = rect.width * 2.5
        func project(_ x: CGFloat) -> (x: CGFloat, scale: CGFloat) {
            let depth = x * sin(angle)
            let scale = distance / (distance + depth)
            return (rect.midX + x * cos(angle) * scale, scale)
        }
        let left = project(-half), right = project(half)
        perspective(face, left: left.x, leftHeight: rect.height * left.scale, right: right.x, rightHeight: rect.height * right.scale,
                    midY: rect.midY)
    }

    /// Cube: the old slide turns away to the left as the new one comes round from the right.
    private static func cube(old: CGImage?, new: CGImage, in rect: CGRect, angle: CGFloat) {
        let half = rect.width / 2, distance = rect.width * 2.5
        // Corners relative to the cube's center, which sits half a slide behind the screen; the cube turns by -angle.
        func project(_ x: CGFloat, _ z: CGFloat) -> (x: CGFloat, scale: CGFloat) {
            let phi = -angle
            let turnedX = x * cos(phi) - z * sin(phi)
            let turnedZ = x * sin(phi) + z * cos(phi)
            let scale = distance / (distance + turnedZ + half)
            return (rect.midX + turnedX * scale, scale)
        }
        let oldLeft = project(-half, -half), shared = project(half, -half), newRight = project(half, half)
        // Two neighboring faces of a cube seen from the front never overlap, so their order doesn't matter.
        let faces: [(CGImage?, (x: CGFloat, scale: CGFloat), (x: CGFloat, scale: CGFloat))] = [(old, oldLeft, shared), (new, shared, newRight)]
        for (image, left, right) in faces {
            guard let image, right.x - left.x > 0.5 else { continue }
            perspective(image, left: left.x, leftHeight: rect.height * left.scale, right: right.x, rightHeight: rect.height * right.scale,
                        midY: rect.midY)
        }
    }

    /// Draws an image into a quadrilateral with vertical left and right edges of different heights, in narrow strips.
    /// Faces are never turned past 90 degrees, so the left edge is always left of the right one.
    private static func perspective(_ image: CGImage, left x0: CGFloat, leftHeight h0: CGFloat, right x1: CGFloat,
                                    rightHeight h1: CGFloat, midY: CGFloat, strips: Int = 48) {
        guard let context = NSGraphicsContext.current?.cgContext, x1 - x0 > 0.5 else { return }
        // Hard-edged strips that overlap by a pixel: antialiased clips leave hairline seams between them.
        context.saveGState()
        context.setShouldAntialias(false)
        defer { context.restoreGState() }
        for strip in 0..<strips {
            let t0 = CGFloat(strip) / CGFloat(strips), t1 = CGFloat(strip + 1) / CGFloat(strips)
            let sx0 = x0 + (x1 - x0) * t0, sx1 = x0 + (x1 - x0) * t1
            let height = h0 + (h1 - h0) * (t0 + t1) / 2
            context.saveGState()
            context.clip(to: CGRect(x: sx0.rounded(.down), y: midY - height / 2, width: (sx1 - sx0).rounded(.up) + 1, height: height))
            // The whole image, scaled so its columns t0...t1 land on this strip.
            let fullWidth = (sx1 - sx0) / (t1 - t0)
            context.translateBy(x: sx0 - t0 * fullWidth, y: midY + height / 2)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: fullWidth, height: height))
            context.restoreGState()
        }
    }
}
