import AppKit
import PuggleSlidesKit

/// Decoded images, by media id. Media ids are unique per image data, so they never go stale.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [String: NSImage?] = [:]

    func image(_ id: MediaID, in presentation: Presentation) -> NSImage? {
        guard let item = presentation.media[id] else { return nil }
        let key = "\(id)|\(item.data.count)"
        if let cached = images[key] { return cached }
        if images.count > 300 { images.removeAll() }
        let image = NSImage(data: item.data)
        images[key] = .some(image)
        return image
    }
}

/// A cell of a table on the slide.
struct TableCellRef: Hashable {
    var elementID: UUID
    var row: Int
    var column: Int
}

/// Draws slides into the current graphics context, which must be flipped (y down), as canvas views are.
@MainActor
enum SlideRenderer {
    struct Options {
        /// Shows "Click to add title" in empty placeholders, as the editor does.
        var showsPrompts = false
        /// The element whose text is being edited; its text is drawn by the editor instead.
        var hiddenTextElementID: UUID?
        /// The table cell being edited, whose text the editor draws.
        var hiddenTableCell: TableCellRef?
        /// Numbers slide number fields.
        var slideNumber: Int?
        /// Where animations have elements (and their paragraphs) at this moment.
        var states: [UUID: ElementRenderState] = [:]
        /// Print settings' "Hide background": slides print on white, without the background or the theme's decorations.
        var hidesBackground = false
        /// The paragraph states of the element being drawn (set per element from `states`).
        var paragraphStates: [ParagraphRenderState]?
        /// A slideshow is drawing: sounds whose icon hides while presenting aren't drawn.
        var isPresenting = false
        /// Videos show a play button, as in the editor.
        var showsPlayButtons = false
    }

    /// An element mid-animation: faded, moved, scaled, turned or hidden.
    struct ElementRenderState: Equatable {
        var opacity: CGFloat = 1
        /// In slide points.
        var offset: CGSize = .zero
        var scale: CGFloat = 1
        /// Degrees clockwise, about the element's center.
        var rotation: CGFloat = 0
        var isHidden = false
        /// For animations by paragraph; nil leaves every paragraph as it is.
        var paragraphs: [ParagraphRenderState]?

        static let hidden = ElementRenderState(isHidden: true)

        var isIdentity: Bool { self == ElementRenderState() }
    }

    struct ParagraphRenderState: Equatable {
        var opacity: CGFloat = 1
        var offset: CGSize = .zero
        var isHidden = false
    }

    /// Draws `slide` scaled into `rect`.
    static func draw(_ slide: Slide, of presentation: Presentation, in rect: CGRect, options: Options = Options()) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = presentation.slideSize
        guard size.width > 0, size.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.clip(to: bounds)
        let theme = presentation.theme(for: slide)
        if options.hidesBackground {
            context.setFillColor(CGColor.white)
            context.fill(bounds)
        } else {
            drawBackground(presentation.background(for: slide), in: bounds, theme: theme, presentation: presentation)
            for (element, style) in presentation.backdropElements(for: slide) {
                draw(element, style: style, presentation: presentation, options: Options(slideNumber: options.slideNumber))
            }
        }
        for element in slide.elements {
            let style = presentation.style(for: element, on: slide)
            guard let state = options.states[element.id], !state.isIdentity else {
                draw(element, style: style, presentation: presentation, options: options)
                continue
            }
            guard !state.isHidden, state.opacity > 0.001, state.scale > 0.001 else { continue }
            let center = style.placement.boundingBox.center
            context.saveGState()
            context.translateBy(x: center.x + state.offset.width, y: center.y + state.offset.height)
            context.rotate(by: state.rotation * .pi / 180)
            context.scaleBy(x: state.scale, y: state.scale)
            context.translateBy(x: -center.x, y: -center.y)
            let fades = state.opacity < 0.999
            if fades {
                context.setAlpha(state.opacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            var elementOptions = options
            elementOptions.paragraphStates = state.paragraphs
            draw(element, style: style, presentation: presentation, options: elementOptions)
            if fades { context.endTransparencyLayer() }
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// A picture of a slide at `size` pixels, for thumbnails.
    static func image(of slide: Slide, in presentation: Presentation, size: CGSize, slideNumber: Int? = nil, scale: CGFloat = 2,
                      showsPrompts: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            draw(slide, of: presentation, in: rect, options: Options(showsPrompts: showsPrompts, slideNumber: slideNumber))
            return true
        }
        // Render now, at the screen's resolution, so the closure doesn't run on every draw.
        let pixels = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
            draw(slide, of: presentation, in: CGRect(origin: .zero, size: size), options: Options(showsPrompts: showsPrompts, slideNumber: slideNumber))
        }
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }

    // MARK: Backgrounds and fills

    static func drawBackground(_ fill: Fill, in rect: CGRect, theme: SlideTheme, presentation: Presentation) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(CGColor.white)
        context.fill(rect)
        if case .none = fill { return }
        paint(fill, path: CGPath(rect: rect, transform: nil), theme: theme, presentation: presentation)
    }

    /// Fills `path` with `fill`. `mode` shades it for the darker and lighter faces of shapes like cubes.
    static func paint(_ fill: Fill, path: CGPath, theme: SlideTheme, presentation: Presentation, mode: PathFillMode = .normal) {
        guard let context = NSGraphicsContext.current?.cgContext, mode != .none else { return }
        let box = path.boundingBoxOfPath
        switch fill {
        case .none:
            return
        case .solid(let color):
            context.setFillColor(shaded(color.resolved(theme.colors), mode).cgColor)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            return
        case .gradient(let gradient):
            let stops = gradient.stops.sorted { $0.position < $1.position }
            guard !stops.isEmpty else { return }
            let colors = stops.map { shaded($0.color.resolved(theme.colors), mode).cgColor } as CFArray
            var locations = stops.map { CGFloat($0.position) }
            guard let cgGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: &locations) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip(using: .evenOdd)
            switch gradient.kind {
            case .linear(let angle):
                let radians = angle * .pi / 180
                let dx = cos(radians), dy = sin(radians)
                let half = (abs(dx) * box.width + abs(dy) * box.height) / 2
                let start = CGPoint(x: box.midX - dx * half, y: box.midY - dy * half)
                let end = CGPoint(x: box.midX + dx * half, y: box.midY + dy * half)
                context.drawLinearGradient(cgGradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .radial:
                let center = CGPoint(x: box.midX, y: box.midY)
                context.drawRadialGradient(cgGradient, startCenter: center, startRadius: 0, endCenter: center,
                                           endRadius: hypot(box.width, box.height) / 2, options: [.drawsAfterEndLocation])
            }
            context.restoreGState()
        case .picture(let picture):
            context.saveGState()
            context.addPath(path)
            context.clip(using: .evenOdd)
            if let image = ImageCache.shared.image(picture.mediaID, in: presentation) {
                if picture.stretches || image.size.width <= 0 {
                    image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high.rawValue])
                } else {
                    var y = box.minY
                    while y < box.maxY {
                        var x = box.minX
                        while x < box.maxX {
                            image.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: image.size), from: .zero, operation: .sourceOver,
                                       fraction: 1, respectFlipped: true, hints: nil)
                            x += image.size.width
                        }
                        y += image.size.height
                    }
                }
            } else {
                context.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
                context.fill(box)
            }
            context.restoreGState()
        }
        // Shaded faces of gradient and picture fills get a translucent wash.
        if mode != .normal {
            context.saveGState()
            context.addPath(path)
            let wash: CGColor = switch mode {
            case .darken: CGColor(gray: 0, alpha: 0.4)
            case .darkenLess: CGColor(gray: 0, alpha: 0.2)
            case .lighten: CGColor(gray: 1, alpha: 0.4)
            default: CGColor(gray: 1, alpha: 0.2)
            }
            context.setFillColor(wash)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }
    }

    private static func shaded(_ color: ResolvedColor, _ mode: PathFillMode) -> ResolvedColor {
        switch mode {
        case .darken: color.adjusted(lightness: 0.6)
        case .darkenLess: color.adjusted(lightness: 0.8)
        case .lighten: ResolvedColor(red: color.red + (1 - color.red) * 0.4, green: color.green + (1 - color.green) * 0.4,
                                     blue: color.blue + (1 - color.blue) * 0.4, alpha: color.alpha)
        case .lightenLess: ResolvedColor(red: color.red + (1 - color.red) * 0.2, green: color.green + (1 - color.green) * 0.2,
                                         blue: color.blue + (1 - color.blue) * 0.2, alpha: color.alpha)
        default: color
        }
    }

    // MARK: Elements

    static func draw(_ element: SlideElement, style: ElementStyle, presentation: Presentation, options: Options) {
        switch element.content {
        case .group(let children):
            for child in children {
                let childStyle = ElementStyle(element: child, parents: [], theme: style.theme, defaultTextStyle: style.defaultTextStyle)
                draw(child, style: childStyle, presentation: presentation, options: options)
            }
        case .shape(let shape):
            if shape.isWordArt {
                drawWordArt(shape, element: element, style: style, presentation: presentation, options: options)
            } else {
                drawShape(shape, element: element, style: style, presentation: presentation, options: options)
            }
        case .picture(let picture):
            drawPicture(picture, style: style, presentation: presentation)
        case .table(let table):
            drawTable(table, element: element, style: style, presentation: presentation, options: options)
        case .chart(let chart):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let placement = style.placement
            context.saveGState()
            context.concatenate(placement.transform)
            ChartRenderer.draw(chart, in: CGRect(x: 0, y: 0, width: abs(placement.frame.width), height: abs(placement.frame.height)), context: context)
            context.restoreGState()
        case .media(let clip):
            drawMedia(clip, style: style, presentation: presentation, options: options)
        }
    }

    /// A video's poster frame, fitted inside its box on black (a dark box without one), or a sound's speaker icon.
    static func drawMedia(_ clip: MediaClip, style: ElementStyle, presentation: Presentation, options: Options) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if !clip.isVideo, options.isPresenting, clip.hidesWhenPresenting { return }
        let placement = style.placement
        let box = CGRect(x: 0, y: 0, width: abs(placement.frame.width), height: abs(placement.frame.height))
        context.saveGState()
        context.concatenate(placement.transform)
        if clip.isVideo {
            context.setFillColor(CGColor(gray: 0.08, alpha: 1))
            context.fill(box)
            if let posterID = clip.posterID, let image = AdjustedImages.image(Picture(mediaID: posterID), theme: style.theme, presentation: presentation),
               image.size.width > 0, image.size.height > 0 {
                let scale = min(box.width / image.size.width, box.height / image.size.height)
                let fitted = CGRect(x: box.midX - image.size.width * scale / 2, y: box.midY - image.size.height * scale / 2,
                                    width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high.rawValue])
            }
            if options.showsPlayButtons { MediaIcons.drawPlayButton(in: box) }
        } else {
            MediaIcons.drawSpeaker(in: box)
        }
        context.restoreGState()
    }

    static func drawShape(_ shape: Shape, element: SlideElement, style: ElementStyle, presentation: Presentation, options: Options) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        context.saveGState()
        context.concatenate(placement.transform)
        let parts = PresetGeometry.paths(for: style.geometry, in: CGRect(origin: .zero, size: size))
        let fill = style.fill
        if !style.geometry.isLine {
            for part in parts where part.fill != .none { paint(fill, path: part.path, theme: style.theme, presentation: presentation, mode: part.fill) }
        }
        stroke(parts, outline: style.outline, theme: style.theme, isLine: style.geometry.isLine)
        context.restoreGState()
        if shape.text != nil, element.id != options.hiddenTextElementID {
            drawText(of: element, style: style, options: options)
        }
    }

    static func drawPicture(_ picture: Picture, style: ElementStyle, presentation: Presentation) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        context.concatenate(placement.transform)
        let parts = PresetGeometry.paths(for: picture.geometry, in: rect)
        context.saveGState()
        for part in parts { context.addPath(part.path) }
        if !parts.isEmpty { context.clip(using: .evenOdd) }
        let crop = picture.crop
        let visibleWidth = max(0.01, 1 - crop.left - crop.right), visibleHeight = max(0.01, 1 - crop.top - crop.bottom)
        let full = CGRect(x: -crop.left / visibleWidth * size.width, y: -crop.top / visibleHeight * size.height,
                          width: size.width / visibleWidth, height: size.height / visibleHeight)
        if let image = AdjustedImages.image(picture, theme: style.theme, presentation: presentation) {
            image.draw(in: full, from: .zero, operation: .sourceOver, fraction: max(0, min(1, 1 - picture.adjustments.transparency)),
                       respectFlipped: true, hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high.rawValue])
        } else {
            context.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
            context.fill(rect)
            if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
                let side = min(size.width, size.height) * 0.3
                symbol.draw(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            }
        }
        context.restoreGState()
        stroke(parts, outline: style.outline, theme: style.theme, isLine: false)
        context.restoreGState()
    }

    // MARK: Outlines and line ends

    static func stroke(_ parts: [ShapePath], outline: Outline, theme: SlideTheme, isLine: Bool) {
        guard outline.isVisible, let context = NSGraphicsContext.current?.cgContext, case .solid(let colorRef) = outline.fill else { return }
        let color = colorRef.resolved(theme.colors)
        let width = CGFloat(outline.width)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(outline.dash == .solid ? (isLine ? .round : .butt) : .butt)
        if !outline.dash.pattern.isEmpty {
            context.setLineDash(phase: 0, lengths: outline.dash.pattern.map { CGFloat($0) * max(width, 0.75) })
        }
        let stroked = parts.filter(\.stroke)
        let hasEnds = isLine && (outline.head != .none || outline.tail != .none)
        for (index, part) in stroked.enumerated() {
            if hasEnds, index == stroked.count - 1 {
                let ends = EndPoints(part.path)
                context.addPath(ends.trimmed(head: trim(for: outline.head, width: width), tail: trim(for: outline.tail, width: width)))
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
                if let head = ends.head { drawEnd(outline.head, at: head.point, direction: head.direction, width: width) }
                if let tail = ends.tail { drawEnd(outline.tail, at: tail.point, direction: tail.direction, width: width) }
            } else {
                context.addPath(part.path)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    static func arrowLength(_ width: CGFloat) -> CGFloat { max(width * 3, 6) }

    /// How far a line stops short of its end so the end shape covers it: hollow ends stop at their back edge.
    static func trim(for end: LineEnd, width: CGFloat) -> CGFloat {
        switch end {
        case .none, .strokeArrow: 0
        case .fillArrow: arrowLength(width) * 0.6
        case .fillCircle, .fillSquare, .fillDiamond: arrowLength(width) / 2
        case .strokeCircle, .strokeSquare, .strokeDiamond: arrowLength(width)
        }
    }

    /// The shape of a line end at `point`, pointing along `direction` (a unit vector out of the line), and whether
    /// it's filled (otherwise stroked).
    static func endShape(_ end: LineEnd, at point: CGPoint, direction: CGVector, width: CGFloat) -> (path: CGPath, filled: Bool)? {
        guard end != .none else { return nil }
        let length = arrowLength(width), half = length / 2
        let back = CGVector(dx: -direction.dx, dy: -direction.dy)
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: point.x + back.dx * along + normal.dx * across, y: point.y + back.dy * along + normal.dy * across)
        }
        let path = CGMutablePath()
        switch end {
        case .none: return nil
        case .fillArrow, .strokeArrow:
            path.move(to: at(length, half))
            path.addLine(to: point)
            path.addLine(to: at(length, -half))
            if end == .fillArrow { path.closeSubpath() }
        case .fillCircle, .strokeCircle:
            let center = at(half, 0)
            path.addEllipse(in: CGRect(x: center.x - half, y: center.y - half, width: length, height: length))
        case .fillSquare, .strokeSquare:
            path.move(to: at(0, half))
            path.addLine(to: at(0, -half))
            path.addLine(to: at(length, -half))
            path.addLine(to: at(length, half))
            path.closeSubpath()
        case .fillDiamond, .strokeDiamond:
            path.move(to: point)
            path.addLine(to: at(half, half))
            path.addLine(to: at(length, 0))
            path.addLine(to: at(half, -half))
            path.closeSubpath()
        }
        return (path, end.isFilled)
    }

    private static func drawEnd(_ end: LineEnd, at point: CGPoint, direction: CGVector, width: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext, let shape = endShape(end, at: point, direction: direction, width: width) else { return }
        context.addPath(shape.path)
        if shape.filled {
            context.fillPath()
        } else {
            context.setLineCap(.round)
            context.strokePath()
        }
    }

    /// The first and last points of a path, with the direction the path leaves through each.
    struct EndPoints {
        var points: [(CGPathElementType, [CGPoint])] = []
        var head: (point: CGPoint, direction: CGVector)?
        var tail: (point: CGPoint, direction: CGVector)?

        init(_ path: CGPath) {
            var elements: [(CGPathElementType, [CGPoint])] = []
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                let count: Int = switch element.type {
                case .moveToPoint, .addLineToPoint: 1
                case .addQuadCurveToPoint: 2
                case .addCurveToPoint: 3
                default: 0
                }
                elements.append((element.type, (0..<count).map { element.points[$0] }))
            }
            points = elements
            let all = elements.flatMap(\.1)
            guard all.count >= 2 else { return }
            head = (all[0], Self.unit(from: all.dropFirst().first { $0 != all[0] } ?? all[1], to: all[0]))
            let last = all[all.count - 1]
            tail = (last, Self.unit(from: all.dropLast().last { $0 != last } ?? all[all.count - 2], to: last))
        }

        static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            return length > 0 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 1, dy: 0)
        }

        /// The path with its ends pulled back, so a line doesn't poke through an arrowhead's tip.
        func trimmed(head headTrim: CGFloat, tail tailTrim: CGFloat) -> CGPath {
            var elements = points
            if headTrim > 0, let head, let index = elements.firstIndex(where: { !$0.1.isEmpty }) {
                elements[index].1[0] = CGPoint(x: head.point.x - head.direction.dx * headTrim, y: head.point.y - head.direction.dy * headTrim)
            }
            if tailTrim > 0, let tail, let index = elements.lastIndex(where: { !$0.1.isEmpty }) {
                let last = elements[index].1.count - 1
                elements[index].1[last] = CGPoint(x: tail.point.x - tail.direction.dx * tailTrim, y: tail.point.y - tail.direction.dy * tailTrim)
            }
            let path = CGMutablePath()
            for (type, points) in elements {
                switch type {
                case .moveToPoint: path.move(to: points[0])
                case .addLineToPoint: path.addLine(to: points[0])
                case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
                case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
                case .closeSubpath: path.closeSubpath()
                @unknown default: break
                }
            }
            return path
        }
    }

    // MARK: Text

    /// The transform for an element's text: its rotation, but not its flips (a vertical flip turns text upside down).
    static func textTransform(for placement: Placement) -> CGAffineTransform {
        let frame = placement.frame
        let angle = placement.rotation + (placement.flipVertical ? 180 : 0)
        return CGAffineTransform(translationX: frame.midX, y: frame.midY)
            .rotated(by: angle * .pi / 180)
            .translatedBy(x: -abs(frame.width) / 2, y: -abs(frame.height) / 2)
    }

    static func drawText(of element: SlideElement, style: ElementStyle, options: Options) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        var paragraphs = style.resolvedParagraphs(slideNumber: options.slideNumber)
        if paragraphs.allSatisfy(\.isEmpty) {
            guard options.showsPrompts, let prompt = style.prompt else { return }
            paragraphs = promptParagraphs(prompt, style: style)
        }
        let (layout, origin) = textPlacement(paragraphs, style: style, size: size)
        context.saveGState()
        context.concatenate(textTransform(for: placement))
        layout.draw(at: origin, paragraphStates: options.paragraphStates)
        context.restoreGState()
    }

    /// An object's laid-out text and where its top-left goes in the object's own space (inside the padding, moved
    /// down for middle and bottom alignment).
    static func textPlacement(_ paragraphs: [ResolvedParagraph], style: ElementStyle, size: CGSize) -> (layout: TextLayout, origin: CGPoint) {
        let area = TextMetrics.textArea(for: style, size: size)
        let layout = TextLayout.make(paragraphs, width: area.width, wraps: style.bodyProperties.wraps)
        let offset: CGFloat = switch style.bodyProperties.anchor {
        case .top: 0
        case .middle: (area.height - layout.usedHeight) / 2
        case .bottom: area.height - layout.usedHeight
        }
        return (layout, CGPoint(x: area.minX, y: area.minY + offset))
    }

    /// The rectangles a character range of an object's text covers, one per line, in the object's text space, with
    /// the transform from there to the slide. Ranges count UTF-16 units of the text, paragraphs ending in newlines.
    static func textRects(of style: ElementStyle, range: NSRange, slideNumber: Int?) -> (rects: [CGRect], transform: CGAffineTransform) {
        let placement = style.placement
        let size = CGSize(width: abs(placement.frame.width), height: abs(placement.frame.height))
        let (layout, origin) = textPlacement(style.resolvedParagraphs(slideNumber: slideNumber), style: style, size: size)
        return (layout.rects(for: range).map { $0.offsetBy(dx: origin.x, dy: origin.y) }, textTransform(for: placement))
    }

    /// The gray prompt, in the placeholder's own font and size, without a bullet.
    static func promptParagraphs(_ prompt: String, style: ElementStyle) -> [ResolvedParagraph] {
        let resolved = style.resolvedParagraphs(TextBody(paragraphs: [TextParagraph(prompt)]))
        return resolved.map { paragraph in
            var paragraph = paragraph
            paragraph.bullet = nil
            paragraph.marginLeft = 0
            paragraph.indent = 0
            paragraph.runs = paragraph.runs.map { run in
                var run = run
                run.style.color = Theme.promptText.resolvedColor
                run.style.underline = false
                return run
            }
            return paragraph
        }
    }
}
