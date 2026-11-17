import CoreGraphics
import Foundation

/// The groups in the Insert ▸ Shape menu.
public enum ShapeCategory: String, CaseIterable, Sendable {
    case shapes, arrows, callouts, equation

    public var title: String {
        switch self {
        case .shapes: "Shapes"
        case .arrows: "Arrows"
        case .callouts: "Callouts"
        case .equation: "Equation"
        }
    }
}

/// One entry in the shape gallery.
public struct PresetShapeInfo: Hashable, Sendable {
    /// The DrawingML preset name ("roundRect").
    public let name: String
    /// The tooltip ("Rounded Rectangle").
    public let title: String
    public let category: ShapeCategory

    public init(name: String, title: String, category: ShapeCategory) {
        self.name = name
        self.title = title
        self.category = category
    }
}

/// One drawable part of a shape's outline.
public struct ShapePath {
    public var path: CGPath
    public var fill: PathFillMode
    public var stroke: Bool

    public init(path: CGPath, fill: PathFillMode = .normal, stroke: Bool = true) {
        self.path = path
        self.fill = fill
        self.stroke = stroke
    }
}

/// A yellow adjustment handle (a diamond) in shape space, and how dragging it changes an adjust value.
public struct AdjustHandle: Hashable, Sendable {
    /// The adjust value the handle changes ("adj", "adj1" …). A handle that changes two values (a callout's tail,
    /// a block arc's angle and thickness) is named after its first: gdRefX for ahXY, gdRefAng for ahPolar.
    public let name: String
    /// Where the handle sits, in shape space.
    public let position: CGPoint

    public init(name: String, position: CGPoint) {
        self.name = name
        self.position = position
    }
}

/// A point where connectors attach to a shape (DrawingML's cxn).
public struct ConnectionSite: Hashable, Sendable {
    /// In shape space.
    public let position: CGPoint
    /// The direction a connector leaves the shape, in degrees clockwise from the positive x axis (y down).
    public let angle: Double

    public init(position: CGPoint, angle: Double) {
        self.position = position
        self.angle = angle
    }
}

/// DrawingML preset and custom geometry: the outline drawn for each shape.
///
/// Every ECMA-376 preset (ST_ShapeType) is defined, from the standard's presetShapeDefinitions.xml, and drawn by
/// evaluating its shape guides for the frame's size.
public enum PresetGeometry {
    /// The shape gallery, in its order.
    public static let catalog: [PresetShapeInfo] = galleryShapes + galleryArrows + galleryCallouts + galleryEquation

    /// Every preset name this engine draws (all of ST_ShapeType), sorted.
    public static let presetNames: [String] = PresetShapeSource.all.keys.sorted()

    private static let catalogByName: [String: PresetShapeInfo] =
        Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    public static func info(named name: String) -> PresetShapeInfo? { catalogByName[name] }

    /// The adjust values a new shape starts with.
    public static func defaultAdjustments(_ name: String) -> [String: Double] {
        PresetShapeLibrary.shared.definition(named: name)?.defaultAdjustments ?? [:]
    }

    /// The outline parts of `geometry` drawn in `rect` (shape space, y down). Draw them in order, filling and then
    /// stroking each one. A fill-only part that a definition lists after outline-only parts (chartPlus, chartStar,
    /// chartX) comes before them, so outlines stay on top as in PowerPoint.
    public static func paths(for geometry: ShapeGeometry, in rect: CGRect) -> [ShapePath] {
        guard let frame = usable(rect) else { return [] }
        switch geometry {
        case .preset(let name, let adjustments):
            let definition = definition(named: name)
            let values = definition.evaluate(width: frame.width, height: frame.height, adjustments: adjustments)
            return layered(definition.paths.map { path(for: $0, values: values, frame: frame) })
        case .custom(let custom):
            return layered(custom.paths.map { path(for: $0, frame: frame) })
        }
    }

    /// Where text goes inside the shape, in shape space.
    public static func textRect(for geometry: ShapeGeometry, in rect: CGRect) -> CGRect {
        guard let frame = usable(rect) else { return rect }
        switch geometry {
        case .preset(let name, let adjustments):
            let definition = definition(named: name)
            guard let textRect = definition.textRect else { return frame }
            let values = definition.evaluate(width: frame.width, height: frame.height, adjustments: adjustments)
            let left = textRect.left.value(in: values), right = textRect.right.value(in: values)
            let top = textRect.top.value(in: values), bottom = textRect.bottom.value(in: values)
            return CGRect(x: frame.minX + min(left, right), y: frame.minY + min(top, bottom),
                          width: abs(right - left), height: abs(bottom - top))
        case .custom(let custom):
            guard let insets = custom.textRect else { return frame }
            return CGRect(x: frame.minX + frame.width * insets.left, y: frame.minY + frame.height * insets.top,
                          width: frame.width * (1 - insets.left - insets.right),
                          height: frame.height * (1 - insets.top - insets.bottom)).standardized
        }
    }

    /// Adjustment handles for the shape, in shape space.
    public static func handles(for geometry: ShapeGeometry, in rect: CGRect) -> [AdjustHandle] {
        guard case .preset(let name, let adjustments) = geometry, let frame = usable(rect),
              let definition = PresetShapeLibrary.shared.definition(named: name) else { return [] }
        let values = definition.evaluate(width: frame.width, height: frame.height, adjustments: adjustments)
        return definition.handles.map { handle in
            AdjustHandle(name: definition.adjusts[handle.axes[0].adjust].name,
                         position: CGPoint(x: frame.minX + handle.x.value(in: values), y: frame.minY + handle.y.value(in: values)))
        }
    }

    /// The new adjust values after dragging `handle` to `point` (shape space): the values the handle sets, found by
    /// inverting the shape's guides, within the handle's limits and whole, as files store them. Values the drag
    /// doesn't change (including every other adjust value) are returned as they were.
    public static func adjustments(for geometry: ShapeGeometry, in rect: CGRect, dragging handle: String, to point: CGPoint) -> [String: Double] {
        guard case .preset(let name, let adjustments) = geometry else { return [:] }
        guard let frame = usable(rect), point.x.isFinite, point.y.isFinite,
              let definition = PresetShapeLibrary.shared.definition(named: name),
              let dragged = definition.handles.first(where: { definition.adjusts[$0.axes[0].adjust].name == handle })
        else { return adjustments }
        let start = definition.adjustValues(adjustments)
        let solved = AdjustHandleSolver.solve(definition, handle: dragged, width: frame.width, height: frame.height, start: start,
                                              target: (x: point.x - frame.minX, y: point.y - frame.minY))
        var result = adjustments
        for axis in dragged.axes where solved[axis.adjust] != start[axis.adjust] {
            result[definition.adjusts[axis.adjust].name] = solved[axis.adjust].rounded()
        }
        return result
    }

    /// Where connectors attach to the shape, in shape space. Custom geometry has none.
    public static func connectionSites(for geometry: ShapeGeometry, in rect: CGRect) -> [ConnectionSite] {
        guard case .preset(let name, let adjustments) = geometry, let frame = usable(rect) else { return [] }
        let definition = definition(named: name)
        let values = definition.evaluate(width: frame.width, height: frame.height, adjustments: adjustments)
        return definition.connectionSites.map { site in
            ConnectionSite(position: CGPoint(x: frame.minX + site.x.value(in: values), y: frame.minY + site.y.value(in: values)),
                           angle: site.angle.value(in: values) / 60_000)
        }
    }

    // MARK: - Drawing

    /// The preset's definition; unknown names draw as rectangles.
    static func definition(named name: String) -> PresetShapeDefinition {
        if let definition = PresetShapeLibrary.shared.definition(named: name) { return definition }
        guard let rectangle = PresetShapeLibrary.shared.definition(named: "rect") else {
            preconditionFailure("The rect preset is missing")
        }
        return rectangle
    }

    /// Moves fill-only parts beneath the outline-only parts listed before them; everything else keeps its order.
    private static func layered(_ paths: [ShapePath]) -> [ShapePath] {
        var ordered: [ShapePath] = []
        var outlines: [ShapePath] = []
        for path in paths {
            if path.fill == .none {
                outlines.append(path)
            } else if !path.stroke {
                ordered.append(path)
            } else {
                ordered += outlines
                outlines.removeAll()
                ordered.append(path)
            }
        }
        return ordered + outlines
    }

    private static func usable(_ rect: CGRect) -> CGRect? {
        let frame = rect.standardized
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return nil }
        return frame
    }

    private static func path(for path: PresetShapeDefinition.Path, values: [Double], frame: CGRect) -> ShapePath {
        var builder = ShapePathBuilder(origin: frame.origin,
                                       scaleX: path.width > 0 ? frame.width / path.width : 1,
                                       scaleY: path.height > 0 ? frame.height / path.height : 1)
        for command in path.commands {
            switch command {
            case .move(let x, let y):
                builder.move(x.value(in: values), y.value(in: values))
            case .line(let x, let y):
                builder.line(x.value(in: values), y.value(in: values))
            case .arc(let widthRadius, let heightRadius, let start, let sweep):
                builder.arc(widthRadius: widthRadius.value(in: values), heightRadius: heightRadius.value(in: values),
                            start: start.value(in: values) * GuideOperator.radiansPerUnit,
                            sweep: sweep.value(in: values) * GuideOperator.radiansPerUnit)
            case .quadratic(let x1, let y1, let x, let y):
                builder.quadratic(x1.value(in: values), y1.value(in: values), x.value(in: values), y.value(in: values))
            case .cubic(let x1, let y1, let x2, let y2, let x, let y):
                builder.cubic(x1.value(in: values), y1.value(in: values), x2.value(in: values), y2.value(in: values),
                              x.value(in: values), y.value(in: values))
            case .close:
                builder.close()
            }
        }
        return ShapePath(path: builder.path, fill: path.fill, stroke: path.stroke)
    }

    /// A freeform path: its own coordinate space scaled to the frame (0 means points).
    private static func path(for path: CustomPath, frame: CGRect) -> ShapePath {
        var builder = ShapePathBuilder(origin: frame.origin,
                                       scaleX: path.width > 0 ? frame.width / path.width : 1,
                                       scaleY: path.height > 0 ? frame.height / path.height : 1)
        let radiansPerDegree = Double.pi / 180
        for command in path.commands {
            switch command {
            case .move(let point):
                builder.move(point.x, point.y)
            case .line(let point):
                builder.line(point.x, point.y)
            case .quadratic(let control, let end):
                builder.quadratic(control.x, control.y, end.x, end.y)
            case .cubic(let control1, let control2, let end):
                builder.cubic(control1.x, control1.y, control2.x, control2.y, end.x, end.y)
            case .arc(let widthRadius, let heightRadius, let startAngle, let sweepAngle):
                builder.arc(widthRadius: widthRadius, heightRadius: heightRadius, start: startAngle * radiansPerDegree,
                            sweep: sweepAngle * radiansPerDegree)
            case .close:
                builder.close()
            }
        }
        return ShapePath(path: builder.path, fill: path.fill, stroke: path.stroke)
    }
}
