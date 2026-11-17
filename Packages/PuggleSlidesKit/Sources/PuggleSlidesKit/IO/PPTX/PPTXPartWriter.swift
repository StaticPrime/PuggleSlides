import Foundation

/// The relationships of one part (its `_rels/….rels`), numbered rId1, rId2, … in the order added.
struct PPTXRelationshipsWriter {
    private(set) var items: [(id: String, type: String, target: String, isExternal: Bool)] = []

    var isEmpty: Bool { items.isEmpty }

    /// Adds a relationship and returns its id. `target` is relative to the source part, or a URI when external.
    mutating func add(type: String, target: String, isExternal: Bool = false) -> String {
        let id = "rId\(items.count + 1)"
        items.append((id, type, target, isExternal))
        return id
    }

    func data() -> Data {
        var xml = XMLWriter(reservingCapacity: 256 + items.count * 160)
        xml.raw("<Relationships xmlns=\"\(PPTXNamespace.packageRelationships)\">")
        for item in items {
            xml.raw("<Relationship")
            xml.attribute("Id", item.id)
            xml.attribute("Type", item.type)
            xml.attribute("Target", item.target)
            if item.isExternal { xml.raw(" TargetMode=\"External\"") }
            xml.raw("/>")
        }
        xml.raw("</Relationships>")
        return xml.data
    }
}

/// What every part of a package being written shares: where media, slides and charts are stored.
final class PPTXWriteState {
    let media: [MediaID: MediaItem]
    /// Stamps the workbooks embedded for charts, so a presentation always saves to the same bytes.
    let date: Date
    /// Slide parts by slide id, for links between slides.
    var slidePaths: [UUID: String] = [:]
    /// Media parts in the order first used, with their content types.
    private(set) var mediaParts: [(path: String, item: MediaItem)] = []
    private var mediaPaths: [MediaID: String] = [:]
    /// Pictures and clips are numbered apart, as PowerPoint numbers them: image1.png, media1.mp4.
    private var pictureCount = 0
    private var clipCount = 0
    /// The pictures clips without a poster show, by kind.
    private var defaultPicturePaths: [MediaClip.Kind: String] = [:]
    /// Each clip's length in seconds, nil when it isn't known.
    private var durations: [MediaID: Double?] = [:]
    /// Chart parts, numbered across the package in the order written, each with the workbook holding its numbers.
    private(set) var chartParts: [PPTXChartParts] = []

    init(media: [MediaID: MediaItem], date: Date = Date()) {
        self.media = media
        self.date = date
    }

    /// Writes a chart's part and its workbook, and returns the chart part's path ("ppt/charts/chart2.xml").
    func addChart(_ chart: Chart) -> String {
        let number = chartParts.count + 1
        let parts = PPTXChartWriter.parts(chart, number: number, date: date)
        chartParts.append(parts)
        return parts.chartPath
    }

    /// The part a media item is stored in ("ppt/media/image3.png", "ppt/media/media1.mp4"), or nil when the presentation
    /// doesn't have it.
    func mediaPath(_ id: MediaID) -> String? {
        if let path = mediaPaths[id] { return path }
        guard let item = media[id], !item.data.isEmpty else { return nil }
        let path: String
        if item.isVideo || item.isAudio {
            clipCount += 1
            path = "ppt/media/media\(clipCount).\(PPTXMedia.fileExtension(item))"
        } else {
            pictureCount += 1
            path = "ppt/media/image\(pictureCount).\(item.fileExtension)"
        }
        mediaPaths[id] = path
        mediaParts.append((path, item))
        return path
    }

    /// The part holding the picture a clip without a poster shows, stored once per kind.
    func defaultPicturePath(_ kind: MediaClip.Kind) -> String {
        if let path = defaultPicturePaths[kind] { return path }
        pictureCount += 1
        let path = "ppt/media/image\(pictureCount).png"
        defaultPicturePaths[kind] = path
        mediaParts.append((path, MediaItem(data: MediaPictures.picture(for: kind), contentType: "image/png")))
        return path
    }

    /// How long a clip's media plays, read once.
    func duration(of id: MediaID) -> Double? {
        if let known = durations[id] { return known }
        let seconds = media[id].flatMap { PPTXMediaDuration.seconds(of: $0.data) }
        durations[id] = seconds
        return seconds
    }
}

/// Writes one PresentationML part: its XML, its relationships and its shape ids, which are unique in the part
/// and start at 2 (the shape tree itself is 1).
struct PPTXPartWriter {
    let path: String
    let state: PPTXWriteState
    var xml = XMLWriter(reservingCapacity: 16 * 1024)
    var relationships = PPTXRelationshipsWriter()
    /// On a slide, its number: slide number fields show it, for apps that show fields as last saved.
    var slideNumber: Int?
    /// The id and kind of every element written, which animations target.
    private(set) var writtenShapes: [UUID: PPTXWrittenShape] = [:]
    private var nextShapeID = 2
    private var mediaRelationships: [MediaID: String] = [:]
    var linkRelationships: [String: String] = [:]
    /// Relationships to clips' media parts and default pictures, by type and part.
    var clipRelationships: [String: String] = [:]
    /// Clips written, in order, which the slide's timing plays.
    var writtenClips: [PPTXWrittenClip] = []
    /// While a word art shape's text is written: the shape's fill and outline, which paint its letters.
    var wordArtPaint: (fill: Fill?, outline: Outline?)?
    /// How tall each row of a table's text needs it to be, where the part's text styles are known.
    var measureRows: ((Table, SlideElement) -> [Double])?
    /// Elements comments are anchored to: their `cNvPr` carries the creation id the comments name them by.
    var commentAnchors: Set<UUID> = []

    init(path: String, state: PPTXWriteState) {
        self.path = path
        self.state = state
    }

    /// A relationship to another part of the package, by its path.
    mutating func relationship(type: String, to part: String) -> String {
        relationships.add(type: type, target: PPTXPackage.relativeTarget(from: path, to: part))
    }

    mutating func takeShapeID() -> Int {
        defer { nextShapeID += 1 }
        return nextShapeID
    }

    mutating func imageRelationship(_ id: MediaID) -> String? {
        if let known = mediaRelationships[id] { return known }
        guard let part = state.mediaPath(id) else { return nil }
        let relationship = relationship(type: PPTXRelationshipType.image, to: part)
        mediaRelationships[id] = relationship
        return relationship
    }

    // MARK: Shape trees

    /// Whether an element can be written: pictures need their image, groups something to hold, tables a cell.
    func isWritable(_ element: SlideElement) -> Bool {
        switch element.content {
        case .shape: true
        case .picture(let picture): state.media[picture.mediaID].map { !$0.data.isEmpty } ?? false
        case .group(let children): children.contains(where: isWritable)
        case .table(let table): table.rowCount > 0 && table.columnCount > 0
        case .chart: true
        case .media(let clip): state.media[clip.mediaID].map { !$0.data.isEmpty } ?? false
        }
    }

    mutating func shapeTree(_ elements: [SlideElement]) {
        xml.raw("<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>")
        xml.raw("<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/>")
        xml.raw("<a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>")
        for element in elements { self.element(element) }
        xml.raw("</p:spTree>")
    }

    mutating func element(_ element: SlideElement) {
        guard isWritable(element) else { return }
        switch element.content {
        case .shape(let shape):
            if shape.isConnector, element.placeholder == nil, shape.text?.isEmpty ?? true {
                connector(element, shape)
            } else {
                self.shape(element, shape)
            }
        case .picture(let picture):
            self.picture(element, picture)
        case .group(let children):
            // An empty group shows nothing, and Office doesn't expect one.
            group(element, children.filter(isWritable))
        case .table(let table):
            self.table(element, table)
        case .chart(let chart):
            self.chart(element, chart)
        case .media(let clip):
            self.clip(element, clip)
        }
    }

    /// `cNvPr`: id, name and alt text, a clip's media click action, and the creation id of an element comments are
    /// anchored to. `build` is how animations of the element are listed in the slide's build list. Returns the id.
    @discardableResult
    mutating func nonVisualProperties(_ element: SlideElement, fallbackName: String, kind: PPTXWrittenShape.Kind,
                                      build: PPTXWrittenShape.Build = .none, mediaAction: Bool = false) -> Int {
        let id = takeShapeID()
        let isFirst = writtenShapes[element.id] == nil
        if isFirst { writtenShapes[element.id] = PPTXWrittenShape(id: id, build: build, kind: kind) }
        xml.raw("<p:cNvPr id=\"\(id)\"")
        xml.attribute("name", element.name.isEmpty ? "\(fallbackName) \(id - 1)" : element.name)
        if let description = element.altDescription, !description.isEmpty { xml.attribute("descr", description) }
        if let title = element.altTitle, !title.isEmpty { xml.attribute("title", title) }
        let anchored = isFirst && commentAnchors.contains(element.id)
        guard anchored || mediaAction else {
            xml.raw("/>")
            return id
        }
        xml.raw(">")
        // A clip plays when clicked: an empty link with the media action, as PowerPoint writes it.
        if mediaAction { xml.raw("<a:hlinkClick r:id=\"\" action=\"ppaction://media\"/>") }
        if anchored {
            xml.raw("<a:extLst><a:ext uri=\"\(PPTXComments.shapeCreationIDExtension)\"><a16:creationId xmlns:a16=\"\(PPTXNamespace.drawing2014)\"")
            xml.raw(" id=\"\(PPTXComments.shapeCreationID(element.id))\"/></a:ext></a:extLst>")
        }
        xml.raw("</p:cNvPr>")
        return id
    }

    /// `nvPr`, with the placeholder reference when there is one.
    mutating func applicationProperties(_ placeholder: PlaceholderRef?) {
        guard let placeholder else {
            xml.raw("<p:nvPr/>")
            return
        }
        xml.raw("<p:nvPr><p:ph")
        // The type defaults to obj; idx to 0.
        if placeholder.type != .object { xml.attribute("type", placeholder.type.rawValue) }
        if placeholder.index != 0 { xml.attribute("idx", min(max(placeholder.index, 0), Int(UInt32.max))) }
        xml.raw("/></p:nvPr>")
    }

    private mutating func shape(_ element: SlideElement, _ shape: Shape) {
        xml.raw("<p:sp><p:nvSpPr>")
        let fallback = element.placeholder.map { $0.type.defaultName } ?? (shape.isWordArt ? "WordArt" : shape.isTextBox ? "TextBox" : "Shape")
        nonVisualProperties(element, fallbackName: fallback, kind: .shape, build: .paragraphs)
        xml.raw(shape.isTextBox ? "<p:cNvSpPr txBox=\"1\"" : "<p:cNvSpPr")
        xml.raw(element.placeholder == nil ? "/>" : "><a:spLocks noGrp=\"1\"/></p:cNvSpPr>")
        applicationProperties(element.placeholder)
        xml.raw("</p:nvSpPr>")
        if shape.isWordArt {
            // Word art paints its letters, not its box: the box has no fill or line, and every run carries the
            // shape's fill and outline.
            shapeProperties(element.placement, geometry: shape.geometry, fill: Fill.none, outline: Outline.none,
                            isPlaceholder: element.placeholder != nil)
            wordArtPaint = (shape.fill, shape.outline)
            textBody(shape.text ?? TextBody(), tag: "p:txBody")
            wordArtPaint = nil
        } else {
            shapeProperties(element.placement, geometry: shape.geometry, fill: shape.fill, outline: shape.outline,
                            isPlaceholder: element.placeholder != nil)
            if let text = shape.text { textBody(text, tag: "p:txBody") }
        }
        xml.raw("</p:sp>")
    }

    private mutating func connector(_ element: SlideElement, _ shape: Shape) {
        xml.raw("<p:cxnSp><p:nvCxnSpPr>")
        nonVisualProperties(element, fallbackName: "Connector", kind: .connector)
        xml.raw("<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>")
        shapeProperties(element.placement, geometry: shape.geometry, fill: shape.fill, outline: shape.outline, isPlaceholder: false)
        xml.raw("</p:cxnSp>")
    }

    private mutating func picture(_ element: SlideElement, _ picture: Picture) {
        // A picture whose image is gone can't be written: Office needs the image part.
        guard let relationship = imageRelationship(picture.mediaID) else { return }
        xml.raw("<p:pic><p:nvPicPr>")
        nonVisualProperties(element, fallbackName: "Picture", kind: .picture)
        xml.raw("<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr>")
        applicationProperties(element.placeholder)
        xml.raw("</p:nvPicPr><p:blipFill>")
        blip(relationship, adjustments: picture.adjustments)
        let crop = picture.crop
        if !crop.isNone {
            xml.raw("<a:srcRect")
            for (name, value) in [("l", crop.left), ("t", crop.top), ("r", crop.right), ("b", crop.bottom)] where value != 0 {
                xml.attribute(name, PPTXValue.clamped(value * 100_000, -100_000_000...100_000_000))
            }
            xml.raw("/>")
        }
        xml.raw("<a:stretch><a:fillRect/></a:stretch></p:blipFill>")
        xml.raw("<p:spPr>")
        if let placement = element.placement { transform(placement) }
        xml.geometry(picture.geometry, frame: element.placement?.frame.size)
        if let outline = picture.outline { line(outline) }
        xml.raw("</p:spPr></p:pic>")
    }

    private mutating func group(_ element: SlideElement, _ children: [SlideElement]) {
        xml.raw("<p:grpSp><p:nvGrpSpPr>")
        nonVisualProperties(element, fallbackName: "Group", kind: .group)
        xml.raw("<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>")
        // Children are in slide coordinates, so the group's child space is its own frame: off = chOff, ext = chExt.
        let frame = (PPTXGroupTransform.bounds(of: children) ?? element.placement?.frame ?? .zero).standardized
        let x = Self.coordinate(frame.x), y = Self.coordinate(frame.y)
        let width = Self.length(frame.width), height = Self.length(frame.height)
        xml.raw("<a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/>")
        xml.raw("<a:chOff x=\"\(x)\" y=\"\(y)\"/><a:chExt cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm></p:grpSpPr>")
        for child in children { self.element(child) }
        xml.raw("</p:grpSp>")
    }

    // MARK: Shape properties

    static func coordinate(_ points: Double) -> Int {
        PPTXValue.clamped(points * EMU.perPoint, -27_273_042_329_600...27_273_042_316_900)
    }

    static func length(_ points: Double) -> Int {
        PPTXValue.clamped(points * EMU.perPoint, 0...27_273_042_316_900)
    }

    /// `spPr` in schema order: xfrm, geometry, fill, ln. An inheriting placeholder with a plain rectangle and
    /// nothing else of its own is an empty `<p:spPr/>`.
    private mutating func shapeProperties(_ placement: Placement?, geometry: ShapeGeometry, fill: Fill?, outline: Outline?, isPlaceholder: Bool) {
        let writesGeometry = !(isPlaceholder && placement == nil && geometry == .rectangle)
        guard placement != nil || writesGeometry || fill != nil || outline != nil else {
            xml.raw("<p:spPr/>")
            return
        }
        xml.raw("<p:spPr>")
        if let placement { transform(placement) }
        if writesGeometry { xml.geometry(geometry, frame: placement?.frame.size) }
        if let fill { self.fill(fill) }
        if let outline { line(outline) }
        xml.raw("</p:spPr>")
    }

    /// `a:xfrm`, or a graphic frame's `p:xfrm`.
    mutating func transform(_ placement: Placement, tag: String = "a:xfrm") {
        var frame = placement.frame
        var flipHorizontal = placement.flipHorizontal, flipVertical = placement.flipVertical
        // Office sizes are never negative: a negative size is the same frame, flipped.
        if frame.width < 0 { flipHorizontal.toggle() }
        if frame.height < 0 { flipVertical.toggle() }
        frame = frame.standardized
        xml.raw("<\(tag)")
        let rotation = PPTXValue.clamped(Placement.normalized(placement.rotation) * 60_000, 0...21_599_999)
        if rotation != 0 { xml.attribute("rot", rotation) }
        if flipHorizontal { xml.raw(" flipH=\"1\"") }
        if flipVertical { xml.raw(" flipV=\"1\"") }
        xml.raw("><a:off x=\"\(Self.coordinate(frame.x))\" y=\"\(Self.coordinate(frame.y))\"/>")
        xml.raw("<a:ext cx=\"\(Self.length(frame.width))\" cy=\"\(Self.length(frame.height))\"/></\(tag)>")
    }

    /// A fill element. Pictures whose image is gone become no fill.
    mutating func fill(_ fill: Fill) {
        switch fill {
        case .none:
            xml.raw("<a:noFill/>")
        case .solid(let color):
            xml.solidFill(color)
        case .gradient(let gradient):
            self.gradient(gradient)
        case .picture(let picture):
            guard let relationship = imageRelationship(picture.mediaID) else {
                xml.raw("<a:noFill/>")
                return
            }
            xml.raw("<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(relationship)\"/><a:srcRect/>")
            xml.raw(picture.stretches ? "<a:stretch><a:fillRect/></a:stretch>"
                    : "<a:tile tx=\"0\" ty=\"0\" sx=\"100000\" sy=\"100000\" flip=\"none\" algn=\"tl\"/>")
            xml.raw("</a:blipFill>")
        }
    }

    private mutating func gradient(_ gradient: GradientFill) {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        // A gradient needs two stops; one is a solid color, none is nothing.
        guard stops.count >= 2 else {
            if let only = stops.first { xml.solidFill(only.color) } else { xml.raw("<a:noFill/>") }
            return
        }
        xml.raw("<a:gradFill rotWithShape=\"1\"><a:gsLst>")
        for stop in stops {
            xml.raw("<a:gs pos=\"\(PPTXValue.clamped(stop.position * 100_000, 0...100_000))\">")
            xml.color(stop.color)
            xml.raw("</a:gs>")
        }
        xml.raw("</a:gsLst>")
        switch gradient.kind {
        case .linear(let angle):
            xml.raw("<a:lin ang=\"\(PPTXValue.clamped(Placement.normalized(angle) * 60_000, 0...21_599_999))\" scaled=\"0\"/>")
        case .radial:
            xml.raw("<a:path path=\"circle\"><a:fillToRect l=\"50000\" t=\"50000\" r=\"50000\" b=\"50000\"/></a:path>")
        }
        xml.raw("</a:gradFill>")
    }

    /// `ln` (or a table cell's `lnL`, `lnR` …): width, fill, dash and ends, in schema order.
    mutating func line(_ outline: Outline, tag: String = "a:ln") {
        xml.raw("<\(tag) w=\"\(PPTXValue.clamped(outline.width * EMU.perPoint, 0...20_116_800))\">")
        switch outline.fill {
        case .picture: xml.raw("<a:noFill/>")
        default: fill(outline.fill)
        }
        if outline.dash != .solid { xml.raw("<a:prstDash val=\"\(outline.dash.rawValue)\"/>") }
        if outline.head != .none { xml.raw("<a:headEnd type=\"\(Self.lineEnd(outline.head))\"/>") }
        if outline.tail != .none { xml.raw("<a:tailEnd type=\"\(Self.lineEnd(outline.tail))\"/>") }
        xml.raw("</\(tag)>")
    }

    /// DrawingML has arrows, circles and diamonds; squares and outlined ends come closest as these.
    static func lineEnd(_ end: LineEnd) -> String {
        switch end {
        case .none: "none"
        case .fillArrow: "triangle"
        case .strokeArrow: "arrow"
        case .fillCircle, .strokeCircle: "oval"
        case .fillDiamond, .strokeDiamond, .fillSquare, .strokeSquare: "diamond"
        }
    }

    /// A slide, layout or master background.
    mutating func background(_ fill: Fill) {
        xml.raw("<p:bg><p:bgPr>")
        self.fill(fill)
        xml.raw("<a:effectLst/></p:bgPr></p:bg>")
    }
}
