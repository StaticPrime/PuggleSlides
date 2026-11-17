import Foundation

/// The placeholder kinds of PresentationML (ST_PlaceholderType), by their file names.
public enum PlaceholderType: String, Codable, CaseIterable, Sendable {
    case title
    case centeredTitle = "ctrTitle"
    case subtitle = "subTitle"
    case body
    case object = "obj"
    case picture = "pic"
    case chart
    case table = "tbl"
    case clipArt
    case diagram = "dgm"
    case media
    case slideNumber = "sldNum"
    case date = "dt"
    case footer = "ftr"
    case header = "hdr"
    case slideImage = "sldImg"

    public var isTitle: Bool { self == .title || self == .centeredTitle }

    /// Footer-like placeholders that a slide shows only when they're switched on.
    public var isFooterKind: Bool { self == .slideNumber || self == .date || self == .footer || self == .header }

    /// The gray prompt shown in an empty placeholder while editing.
    public var prompt: String? {
        switch self {
        case .title, .centeredTitle: "Click to add title"
        case .subtitle: "Click to add subtitle"
        case .body, .object: "Click to add text"
        default: nil
        }
    }
}

/// Marks an element as a placeholder; `index` is PresentationML's idx, which pairs a slide's placeholder
/// with its layout's.
public struct PlaceholderRef: Hashable, Codable, Sendable {
    public var type: PlaceholderType
    public var index: Int

    public init(type: PlaceholderType, index: Int = 0) {
        self.type = type
        self.index = index
    }
}

/// How custom path areas are painted (DrawingML's path fill modes).
public enum PathFillMode: String, Codable, Sendable {
    case normal = "norm"
    case none
    case darken
    case darkenLess
    case lighten
    case lightenLess
}

public enum PathCommand: Hashable, Codable, Sendable {
    case move(SlidePoint)
    case line(SlidePoint)
    case quadratic(control: SlidePoint, end: SlidePoint)
    case cubic(control1: SlidePoint, control2: SlidePoint, end: SlidePoint)
    /// DrawingML's arcTo: an elliptical arc continuing from the current point. Angles are degrees, clockwise.
    case arc(widthRadius: Double, heightRadius: Double, startAngle: Double, sweepAngle: Double)
    case close
}

/// One path of a freeform shape, in its own coordinate space (scaled to the shape's frame when drawn).
public struct CustomPath: Hashable, Codable, Sendable {
    /// The path's coordinate space; 0 means the shape's own width or height in points.
    public var width: Double
    public var height: Double
    public var fill: PathFillMode
    public var stroke: Bool
    public var commands: [PathCommand]

    public init(width: Double, height: Double, fill: PathFillMode = .normal, stroke: Bool = true, commands: [PathCommand]) {
        self.width = width
        self.height = height
        self.fill = fill
        self.stroke = stroke
        self.commands = commands
    }
}

public struct CustomGeometry: Hashable, Codable, Sendable {
    public var paths: [CustomPath]
    /// Where text goes, as fractions of the frame (left, top, right, bottom); nil uses the whole frame.
    public var textRect: TextInsetFractions?

    public init(paths: [CustomPath], textRect: TextInsetFractions? = nil) {
        self.paths = paths
        self.textRect = textRect
    }
}

/// A rectangle inside a frame, as fractions of the frame's size measured from each edge.
public struct TextInsetFractions: Hashable, Codable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

public enum ShapeGeometry: Hashable, Codable, Sendable {
    /// A DrawingML preset ("rect", "roundRect", "rightArrow" …) with its adjust values as stored in files
    /// ("adj" → 16667 means 16.667%).
    case preset(String, adjustments: [String: Double])
    case custom(CustomGeometry)

    public static let rectangle = ShapeGeometry.preset("rect", adjustments: [:])
    public static let line = ShapeGeometry.preset("line", adjustments: [:])

    public var presetName: String? {
        if case .preset(let name, _) = self { return name }
        return nil
    }

    /// Lines and connectors: geometry with no inside.
    public var isLine: Bool {
        guard let name = presetName else { return false }
        return name == "line" || name == "straightConnector1" || name.hasPrefix("bentConnector") || name.hasPrefix("curvedConnector")
    }
}

/// A shape, text box, line or placeholder.
public struct Shape: Hashable, Codable, Sendable {
    public var geometry: ShapeGeometry
    /// Nil inherits from the placeholder this shape fills; for other shapes nil means no fill.
    public var fill: Fill?
    /// Nil inherits like `fill`; for other shapes nil means no border.
    public var outline: Outline?
    public var text: TextBody?
    /// Created with the Text box tool (PresentationML's txBox).
    public var isTextBox: Bool
    /// Saved as a connector (lines drawn with the Line tool).
    public var isConnector: Bool
    /// Insert ▸ Word art: the text's letters fill the frame, painted with the shape's fill and outline.
    public var isWordArt: Bool

    public init(geometry: ShapeGeometry = .rectangle, fill: Fill? = nil, outline: Outline? = nil, text: TextBody? = nil,
                isTextBox: Bool = false, isConnector: Bool = false, isWordArt: Bool = false) {
        self.geometry = geometry
        self.fill = fill
        self.outline = outline
        self.text = text
        self.isTextBox = isTextBox
        self.isConnector = isConnector
        self.isWordArt = isWordArt
    }

    private enum CodingKeys: String, CodingKey {
        case geometry, fill, outline, text, isTextBox, isConnector, isWordArt
    }

    /// Shapes copied before word art existed decode without it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        geometry = try container.decode(ShapeGeometry.self, forKey: .geometry)
        fill = try container.decodeIfPresent(Fill.self, forKey: .fill)
        outline = try container.decodeIfPresent(Outline.self, forKey: .outline)
        text = try container.decodeIfPresent(TextBody.self, forKey: .text)
        isTextBox = try container.decodeIfPresent(Bool.self, forKey: .isTextBox) ?? false
        isConnector = try container.decodeIfPresent(Bool.self, forKey: .isConnector) ?? false
        isWordArt = try container.decodeIfPresent(Bool.self, forKey: .isWordArt) ?? false
    }

    /// New word art: light gray letters with a thin black outline.
    public static func wordArt(_ text: String, fontFamily: String = "Arial") -> Shape {
        var body = TextBody(text, style: CharacterStyle(fontFamily: fontFamily, fontSize: 72),
                            properties: TextBodyProperties(anchor: .middle, insets: TextInsets(all: 0), autofit: Autofit.none, wraps: false))
        body.paragraphs = text.components(separatedBy: "\n").map { TextParagraph($0, style: CharacterStyle(fontFamily: fontFamily, fontSize: 72)) }
        return Shape(fill: .solid(ColorRef(RGBColor(red: 0xCC, green: 0xCC, blue: 0xCC))),
                     outline: Outline(fill: .solid(ColorRef(RGBColor(red: 0, green: 0, blue: 0))), width: 0.75), text: body, isWordArt: true)
    }
}

/// How much of an image is cut off each edge, as fractions of its size.
public struct ImageCrop: Hashable, Codable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public static let none = ImageCrop()
    public var isNone: Bool { self == .none }
}

/// Format options ▸ Recolor: the Slides API's recolor effects. Light and dark ones use one of the page's ten scheme
/// colors (Dark 1, Light 1, Dark 2, Light 2, Accent 1 to 6, in that order).
public enum ImageRecolor: Hashable, Codable, Sendable {
    case light(ThemeColorSlot)
    case dark(ThemeColorSlot)
    case grayscale
    /// Negative grayscale.
    case negative
    case sepia
    /// From files: the image's shades mapped from one color (its darkest) to another (its lightest).
    case duotone(ColorRef, ColorRef)

    /// The scheme colors light and dark recolors draw on, in the Slides API's order.
    public static let schemeSlots: [ThemeColorSlot] = [.dark1, .light1, .dark2, .light2, .accent1, .accent2, .accent3, .accent4, .accent5, .accent6]

    /// The recolor menu: the light versions, the dark versions, then grayscale, negative and sepia.
    public static let presets: [ImageRecolor] = schemeSlots.map { .light($0) } + schemeSlots.map { .dark($0) } + [.grayscale, .negative, .sepia]

    public var title: String {
        switch self {
        case .light(let slot): "\(slot.title) light"
        case .dark(let slot): "\(slot.title) dark"
        case .grayscale: "Grayscale"
        case .negative: "Negative"
        case .sepia: "Sepia"
        case .duotone: "Custom"
        }
    }

    /// Sepia's two ends.
    public static let sepiaDark = RGBColor(red: 0x3B, green: 0x2A, blue: 0x17)
    public static let sepiaLight = RGBColor(red: 0xF4, green: 0xE8, blue: 0xD0)

    /// The color the image's darkest shade becomes, and the color its lightest becomes.
    public func ends(in colors: ColorScheme) -> (dark: ResolvedColor, light: ResolvedColor) {
        let black = ResolvedColor(red: 0, green: 0, blue: 0, alpha: 1), white = ResolvedColor(red: 1, green: 1, blue: 1, alpha: 1)
        switch self {
        case .light(let slot): return (ColorRef(theme: slot).resolved(colors), white)
        case .dark(let slot): return (black, ColorRef(theme: slot).resolved(colors))
        case .grayscale: return (black, white)
        case .negative: return (white, black)
        case .sepia: return (ColorRef(Self.sepiaDark).resolved(colors), ColorRef(Self.sepiaLight).resolved(colors))
        case .duotone(let dark, let light): return (dark.resolved(colors), light.resolved(colors))
        }
    }
}

/// Format options ▸ Adjustments and Recolor.
public struct ImageAdjustments: Hashable, Codable, Sendable {
    /// 0 is opaque, 1 invisible.
    public var transparency: Double
    /// -1 to 1; 0 leaves the image as it is.
    public var brightness: Double
    /// -1 to 1; 0 leaves the image as it is.
    public var contrast: Double
    public var recolor: ImageRecolor?

    public init(transparency: Double = 0, brightness: Double = 0, contrast: Double = 0, recolor: ImageRecolor? = nil) {
        self.transparency = transparency
        self.brightness = brightness
        self.contrast = contrast
        self.recolor = recolor
    }

    public static let none = ImageAdjustments()
    public var isNone: Bool { self == .none }
}

public struct Picture: Hashable, Codable, Sendable {
    public var mediaID: MediaID
    public var crop: ImageCrop
    /// The mask the image is cut to (Mask image); a rectangle by default.
    public var geometry: ShapeGeometry
    public var outline: Outline?
    public var adjustments: ImageAdjustments

    public init(mediaID: MediaID, crop: ImageCrop = .none, geometry: ShapeGeometry = .rectangle, outline: Outline? = nil,
                adjustments: ImageAdjustments = .none) {
        self.mediaID = mediaID
        self.crop = crop
        self.geometry = geometry
        self.outline = outline
        self.adjustments = adjustments
    }

    private enum CodingKeys: String, CodingKey {
        case mediaID, crop, geometry, outline, adjustments
    }

    /// Pictures copied before adjustments existed decode without them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try container.decode(MediaID.self, forKey: .mediaID)
        crop = try container.decodeIfPresent(ImageCrop.self, forKey: .crop) ?? .none
        geometry = try container.decodeIfPresent(ShapeGeometry.self, forKey: .geometry) ?? .rectangle
        outline = try container.decodeIfPresent(Outline.self, forKey: .outline)
        adjustments = try container.decodeIfPresent(ImageAdjustments.self, forKey: .adjustments) ?? .none
    }
}

public indirect enum ElementContent: Hashable, Codable, Sendable {
    case shape(Shape)
    case picture(Picture)
    /// Grouped elements, positioned on the slide like any other element.
    case group([SlideElement])
    case table(Table)
    case chart(Chart)
    /// A video or a sound.
    case media(MediaClip)
}

/// One object on a slide, layout or theme.
public struct SlideElement: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// The name shown in files and to screen readers ("Title 1", "TextBox 3").
    public var name: String
    /// Nil only for placeholders that sit where their layout's placeholder does.
    public var placement: Placement?
    public var placeholder: PlaceholderRef?
    public var content: ElementContent
    /// Alt text: a title and a description.
    public var altTitle: String?
    public var altDescription: String?

    public init(id: UUID = UUID(), name: String = "", placement: Placement?, placeholder: PlaceholderRef? = nil,
                content: ElementContent, altTitle: String? = nil, altDescription: String? = nil) {
        self.id = id
        self.name = name
        self.placement = placement
        self.placeholder = placeholder
        self.content = content
        self.altTitle = altTitle
        self.altDescription = altDescription
    }

    public var shape: Shape? {
        get {
            if case .shape(let shape) = content { return shape }
            return nil
        }
        set {
            if let newValue { content = .shape(newValue) }
        }
    }

    public var picture: Picture? {
        get {
            if case .picture(let picture) = content { return picture }
            return nil
        }
        set {
            if let newValue { content = .picture(newValue) }
        }
    }

    public var children: [SlideElement]? {
        get {
            if case .group(let children) = content { return children }
            return nil
        }
        set {
            if let newValue { content = .group(newValue) }
        }
    }

    public var table: Table? {
        get {
            if case .table(let table) = content { return table }
            return nil
        }
        set {
            if let newValue { content = .table(newValue) }
        }
    }

    public var chart: Chart? {
        get {
            if case .chart(let chart) = content { return chart }
            return nil
        }
        set {
            if let newValue { content = .chart(newValue) }
        }
    }

    public var media: MediaClip? {
        get {
            if case .media(let clip) = content { return clip }
            return nil
        }
        set {
            if let newValue { content = .media(newValue) }
        }
    }

    public var isLine: Bool { shape?.geometry.isLine == true }
    public var isWordArt: Bool { shape?.isWordArt == true }

    /// Media this element and its children show.
    public var mediaIDs: Set<MediaID> {
        switch content {
        case .shape(let shape): shape.fill?.mediaID.map { [$0] } ?? []
        case .picture(let picture): [picture.mediaID]
        case .group(let children): children.reduce(into: Set<MediaID>()) { $0.formUnion($1.mediaIDs) }
        case .table(let table): Set(table.cells.joined().compactMap(\.fill.mediaID))
        case .chart: []
        case .media(let clip): clip.mediaIDs
        }
    }

    /// A copy with new ids, here and in any children.
    public func withNewIDs() -> SlideElement {
        var copy = self
        copy.id = UUID()
        if case .group(let children) = content { copy.content = .group(children.map { $0.withNewIDs() }) }
        return copy
    }
}
