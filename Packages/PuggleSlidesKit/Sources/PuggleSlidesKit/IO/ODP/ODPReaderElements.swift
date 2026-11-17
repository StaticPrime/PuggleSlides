import CoreGraphics
import Foundation

/// Reads the shapes of one page (a slide, a master page or notes) into elements.
///
/// What an element states is what the file gives it beyond what the model would give it anyway: a placeholder's
/// formatting that matches its theme's is left to inherit, and anything else is kept on the element, its paragraphs
/// and its runs.
final class ODPElementReader {
    static let maxGroupDepth = 32
    static let maxParagraphs = 100_000

    let document: ODPDocumentReader
    let sheet: ODFStyleSheet
    let masterName: String
    let theme: Theme
    let isMaster: Bool
    /// The slide's layout, which its placeholders inherit from.
    var layout: Layout?
    /// Animation targets by id: elements, and paragraphs of elements.
    private(set) var targets: [String: ODPMotion.Target] = [:]
    /// Elements by their `xml:id` and `draw:id`, which comments name the element they're about by.
    private(set) var elementIDs: [String: UUID] = [:]
    /// Comments found so far: annotations on the page, and in elements' text (about the element).
    private var annotations: [ODPComments.Annotation] = []
    /// Annotations met in text whose element isn't read yet.
    private var textAnnotations: [ODFNode] = []

    init(document: ODPDocumentReader, sheet: ODFStyleSheet, masterName: String, theme: Theme, isMaster: Bool) {
        self.document = document
        self.sheet = sheet
        self.masterName = masterName
        self.theme = theme
        self.isMaster = isMaster
    }

    // MARK: Placeholders

    /// The presentation object a shape is: its `presentation:class`, or for a custom shape with a presentation style,
    /// the class of the master style it derives from.
    static func placeholderClass(_ node: ODFNode, sheet: ODFStyleSheet) -> String? {
        if node.name == "draw:frame" {
            guard let className = node["presentation:class"], !["notes", "page", "handout"].contains(className) else { return nil }
            return className
        }
        guard node.name == "draw:custom-shape", let name = node["presentation:style-name"] else { return nil }
        var current: String? = name
        var depth = 0
        while let styleName = current, depth < 16 {
            if styleName.hasSuffix("-title") { return "title" }
            if styleName.hasSuffix("-subtitle") { return "subtitle" }
            if styleName.hasSuffix("-outline1") { return "outline" }
            current = sheet.style("presentation", styleName)?.parent
            depth += 1
        }
        return nil
    }

    /// Theme placeholders, numbered: the title 0, bodies and subtitles from 1, and the footers 10 to 13.
    static func themeRefs(_ master: ODFNode, sheet: ODFStyleSheet) -> [ObjectIdentifier: PlaceholderRef] {
        var result: [ObjectIdentifier: PlaceholderRef] = [:]
        var bodies = 1
        for child in master.elements {
            guard let className = placeholderClass(child, sheet: sheet) else { continue }
            let ref: PlaceholderRef
            switch className {
            case "title": ref = PlaceholderRef(type: .title)
            case "outline", "text", "subtitle":
                ref = PlaceholderRef(type: className == "subtitle" ? .subtitle : .body, index: bodies)
                bodies += 1
            case "page-number": ref = PlaceholderRef(type: .slideNumber, index: 12)
            case "date-time": ref = PlaceholderRef(type: .date, index: 10)
            case "footer": ref = PlaceholderRef(type: .footer, index: 11)
            case "header": ref = PlaceholderRef(type: .header, index: 13)
            default: continue
            }
            result[ObjectIdentifier(child)] = ref
        }
        return result
    }

    /// A slide's placeholders, each paired with the first unused placeholder of its kind on the layout.
    static func slideRefs(_ page: ODFNode, sheet: ODFStyleSheet, layout: Layout) -> [ObjectIdentifier: PlaceholderRef] {
        var result: [ObjectIdentifier: PlaceholderRef] = [:]
        var used = Set<Int>()
        var extra = 100
        let candidates = layout.elements.enumerated().compactMap { index, element in element.placeholder.map { (index, $0) } }
        for child in page.elements {
            guard let className = placeholderClass(child, sheet: sheet) else { continue }
            let wanted: PlaceholderType
            switch className {
            case "title": wanted = layout.kind == .title ? .centeredTitle : .title
            case "subtitle": wanted = .subtitle
            case "outline", "text": wanted = .body
            case "graphic": wanted = .picture
            case "object": wanted = .object
            case "chart": wanted = .chart
            case "table": wanted = .table
            case "orgchart": wanted = .diagram
            case "page-number": wanted = .slideNumber
            case "date-time": wanted = .date
            case "footer": wanted = .footer
            case "header": wanted = .header
            default: continue
            }
            let match = candidates.first { !used.contains($0.0) && $0.1.type == wanted }
                ?? candidates.first { !used.contains($0.0) && Presentation.compatible($0.1.type, wanted) }
            if let match {
                used.insert(match.0)
                result[ObjectIdentifier(child)] = match.1
            } else {
                result[ObjectIdentifier(child)] = PlaceholderRef(type: wanted, index: wanted.isTitle ? 0 : extra)
                extra += 1
            }
        }
        return result
    }

    /// The model's inheritance for an element on this page.
    func modelStyle(_ element: SlideElement) -> ElementStyle {
        var parents: [SlideElement] = []
        if let ref = element.placeholder, !isMaster {
            if let layout, let match = layout.placeholder(matching: ref) {
                parents.append(match)
                if let master = theme.placeholder(matching: match.placeholder ?? ref) { parents.append(master) }
            } else if let master = theme.placeholder(matching: ref) {
                parents.append(master)
            }
        }
        return ElementStyle(element: element, parents: parents, theme: theme, defaultTextStyle: document.defaultTextStyle)
    }

    // MARK: Elements

    func elements(in container: ODFNode, refs: [ObjectIdentifier: PlaceholderRef]) -> [SlideElement] {
        var result: [SlideElement] = []
        for child in container.elements {
            let id = UUID()
            if let element = element(child, refs: refs, depth: 0, topLevel: id) { result.append(element) }
        }
        return result
    }

    /// The comments read so far, which the reader then forgets. Annotations in text outside any element (the notes')
    /// are about the slide.
    func takeAnnotations() -> [ODPComments.Annotation] {
        let result = annotations + textAnnotations.map { ODPComments.annotation($0, element: nil) }
        annotations = []
        textAnnotations = []
        return result
    }

    /// The id an element gets, and the id animations of it (and its paragraphs) name: its top-level element's.
    struct IDs {
        var own: UUID
        var target: UUID
    }

    private func element(_ node: ODFNode, refs: [ObjectIdentifier: PlaceholderRef], depth: Int, topLevel: UUID) -> SlideElement? {
        let ids = IDs(own: depth == 0 ? topLevel : UUID(), target: topLevel)
        let pendingAnnotations = textAnnotations.count
        var element: SlideElement?
        switch node.name {
        case "draw:frame":
            element = frame(node, ref: refs[ObjectIdentifier(node)], ids: ids)
        case "draw:custom-shape":
            element = customShape(node, ref: refs[ObjectIdentifier(node)], ids: ids)
        case "draw:rect", "draw:ellipse", "draw:circle", "draw:polygon", "draw:polyline", "draw:path", "draw:regular-polygon", "draw:caption":
            element = legacyShape(node, ids: ids)
        case "draw:line", "draw:connector", "draw:measure":
            element = line(node, ids: ids)
        case "draw:g":
            guard depth < Self.maxGroupDepth else {
                document.warnings.insert(.otherContent)
                return nil
            }
            let children = node.elements.compactMap { self.element($0, refs: refs, depth: depth + 1, topLevel: topLevel) }
            guard !children.isEmpty else { return nil }
            let bounds = children.compactMap { $0.placement?.boundingBox }.reduce(nil as SlideRect?) { $0?.union($1) ?? $1 } ?? .zero
            element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: Placement(frame: bounds), content: .group(children))
        case "draw:a":
            // A shape that's a link: the shape stays, the link doesn't.
            document.warnings.insert(.otherContent)
            guard depth < Self.maxGroupDepth else { return nil }
            let children = node.elements.compactMap { self.element($0, refs: refs, depth: depth + 1, topLevel: topLevel) }
            return children.count == 1 ? children[0] : children.isEmpty ? nil
                : SlideElement(name: "", placement: Placement(frame: children.compactMap { $0.placement?.boundingBox }.reduce(SlideRect.zero) { $0.union($1) }),
                               content: .group(children))
        case "dr3d:scene", "draw:control":
            document.warnings.insert(.otherContent)
        case "office:annotation", "officeooo:annotation":
            annotations.append(ODPComments.annotation(node, element: nil))
        default:
            break
        }
        // Comments in the element's text are about the element.
        if textAnnotations.count > pendingAnnotations {
            for annotation in textAnnotations[pendingAnnotations...] { annotations.append(ODPComments.annotation(annotation, element: element?.id)) }
            textAnnotations.removeSubrange(pendingAnnotations...)
        }
        guard var result = element else { return nil }
        if result.name.isEmpty, let name = node["draw:name"] { result.name = name }
        result.altTitle = node.child("svg:title")?.textContent.nilIfEmpty
        result.altDescription = node.child("svg:desc")?.textContent.nilIfEmpty
        for key in ["xml:id", "draw:id"] {
            guard let id = node[key] else { continue }
            targets[id] = ODPMotion.Target(element: ids.target, paragraph: nil)
            if elementIDs[id] == nil { elementIDs[id] = result.id }
        }
        return result
    }

    // MARK: Placement

    /// Size and position from `svg:x`, `svg:y`, `svg:width`, `svg:height` and `draw:transform`.
    static func placement(_ node: ODFNode) -> Placement? {
        let width = ODFValue.length(node["svg:width"]) ?? 0, height = ODFValue.length(node["svg:height"]) ?? 0
        let x = ODFValue.length(node["svg:x"]) ?? 0, y = ODFValue.length(node["svg:y"]) ?? 0
        guard node["svg:width"] != nil || node["svg:height"] != nil || node["svg:x"] != nil || node["draw:transform"] != nil else { return nil }
        let size = SlideSize(width: max(0, width), height: max(0, height))
        guard let transform = node["draw:transform"], let matrix = Self.transform(transform) else {
            return Placement(frame: SlideRect(x: x, y: y, width: size.width, height: size.height))
        }
        // The shape is drawn at the origin, transformed, then moved by svg:x and svg:y.
        let full = matrix.concatenating(CGAffineTransform(translationX: x, y: y))
        let center = CGPoint(x: size.width / 2, y: size.height / 2).applying(full)
        let origin = CGPoint.zero.applying(full)
        let xAxis = CGPoint(x: 1, y: 0).applying(full)
        let yAxis = CGPoint(x: 0, y: 1).applying(full)
        let scaleX = hypot(Double(xAxis.x - origin.x), Double(xAxis.y - origin.y))
        let scaleY = hypot(Double(yAxis.x - origin.x), Double(yAxis.y - origin.y))
        let determinant = Double((xAxis.x - origin.x) * (yAxis.y - origin.y) - (xAxis.y - origin.y) * (yAxis.x - origin.x))
        var rotation = atan2(Double(xAxis.y - origin.y), Double(xAxis.x - origin.x)) * 180 / .pi
        let flipped = determinant < 0
        if flipped { rotation += 180 }
        let frameWidth = size.width * (scaleX.isFinite && scaleX > 0 ? scaleX : 1)
        let frameHeight = size.height * (scaleY.isFinite && scaleY > 0 ? scaleY : 1)
        let frame = SlideRect(x: Double(center.x) - frameWidth / 2, y: Double(center.y) - frameHeight / 2, width: frameWidth, height: frameHeight)
        guard [frame.x, frame.y, frame.width, frame.height, rotation].allSatisfy(\.isFinite) else {
            return Placement(frame: SlideRect(x: x, y: y, width: size.width, height: size.height))
        }
        return Placement(frame: frame, rotation: rotation, flipHorizontal: false, flipVertical: flipped)
    }

    /// A `draw:transform` as an affine transform, applied left to right as LibreOffice does. Rotation angles turn
    /// counterclockwise.
    static func transform(_ text: String) -> CGAffineTransform? {
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        var count = 0
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")"), count < 16 {
            count += 1
            let name = rest[..<open].trimmingCharacters(in: .whitespaces).lowercased()
            let arguments = rest[rest.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            rest = rest[rest.index(after: close)...]
            switch name {
            case "rotate":
                guard let angle = arguments.first.flatMap({ ODFValue.angle($0, unitless: 180 / .pi) }) else { return nil }
                result = result.concatenating(CGAffineTransform(rotationAngle: -angle * .pi / 180))
            case "translate":
                guard let dx = arguments.first.flatMap(ODFValue.length) else { return nil }
                let dy = arguments.count > 1 ? ODFValue.length(arguments[1]) ?? 0 : 0
                result = result.concatenating(CGAffineTransform(translationX: dx, y: dy))
            case "scale":
                guard let sx = arguments.first.flatMap(ODFValue.double) else { return nil }
                let sy = arguments.count > 1 ? ODFValue.double(arguments[1]) ?? sx : sx
                result = result.concatenating(CGAffineTransform(scaleX: sx, y: sy))
            case "matrix":
                let values = arguments.compactMap { ODFValue.double($0) ?? ODFValue.length($0) }
                guard values.count == 6 else { return nil }
                result = result.concatenating(CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]))
            default:
                // Skews have no place in the model.
                continue
            }
        }
        let values = [result.a, result.b, result.c, result.d, result.tx, result.ty]
        return values.allSatisfy { $0.isFinite && abs($0) < 1e9 } ? result : nil
    }

    // MARK: Shapes

    struct FrameStyle {
        var own: ODFStyle
        var family: String
        var outlineMaster: String?
    }

    func frameStyle(_ node: ODFNode, className: String?) -> FrameStyle {
        let presentationName = node["presentation:style-name"]
        let family = presentationName != nil ? "presentation" : "graphic"
        let name = presentationName ?? node["draw:style-name"]
        var own = name.flatMap { sheet.style(family, $0) } ?? ODFStyle(family: family)
        if let className, name.flatMap({ sheet.style(family, $0) }) == nil {
            // A placeholder without a style of its own inherits its master's style for its kind.
            own = ODFStyle(family: "presentation", parent: masterName + "-" + Self.classStyleSuffix(className))
        }
        return FrameStyle(own: own, family: own.family, outlineMaster: className == "outline" || className == "text" ? masterName : nil)
    }

    static func classStyleSuffix(_ className: String) -> String {
        switch className {
        case "title": "title"
        case "subtitle": "subtitle"
        case "outline", "text", "graphic", "object", "chart", "table", "orgchart": "outline1"
        case "notes": "notes"
        default: "backgroundobjects"
        }
    }

    private func frame(_ node: ODFNode, ref: PlaceholderRef?, ids: IDs) -> SlideElement? {
        let className = Self.placeholderClass(node, sheet: sheet)
        if node["presentation:class"] != nil, className == nil { return nil }
        let ref = className == nil ? nil : ref
        // Without a place of its own, a placeholder sits where its layout's does.
        var placement = Self.placement(node) ?? (ref != nil ? inheritedPlacement(ref) : Placement(frame: .zero))
        let contents = node.elements
        // A table or chart in a placeholder frame is a table or chart in its place; the placeholder doesn't stay.
        if let table = contents.first(where: { $0.name == "table:table" }) {
            return tableElement(node, table: table, placement: placement, ids: ids)
        }
        if let object = contents.first(where: { $0.name == "draw:object" || $0.name == "draw:object-ole" }) {
            if object.name == "draw:object", let chart = document.chart(object) {
                var unflipped = placement
                unflipped.flipHorizontal = false
                unflipped.flipVertical = false
                return SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: unflipped, content: .chart(chart))
            }
            let href = object["xlink:href"] ?? ""
            let isChart = (document.manifestType(href) ?? "").contains("chart") || object.firstDescendant("chart:chart") != nil
            document.warnings.insert(isChart ? .charts : .embeddedObjects)
            // The replacement image still shows the object.
            guard contents.contains(where: { $0.name == "draw:image" }) else { return nil }
        }
        if let plugin = contents.first(where: { $0.name == "draw:plugin" }) {
            if let clip = clipElement(node, plugin: plugin, placement: placement, ids: ids) { return clip }
            // A plugin that isn't kept still shows its preview, if it has one.
            guard contents.contains(where: { $0.name == "draw:image" }) else { return nil }
        }
        if contents.contains(where: { $0.name == "draw:applet" || $0.name == "draw:floating-frame" }) {
            document.warnings.insert(.embeddedObjects)
            return nil
        }
        let style = frameStyle(node, className: className)
        let baseline = ODFFrameBaseline(sheet: sheet, own: style.own, outlineMaster: style.outlineMaster)
        let graphic = baseline.style(level: 0).graphic

        if let image = contents.first(where: { $0.name == "draw:image" }) {
            guard let href = image["xlink:href"], let mediaID = document.media(at: href) else { return nil }
            var crop = ImageCrop.none
            if let clip = graphic.clip, let data = document.media[mediaID]?.data {
                let natural = ODPImageSize.points(of: data).map { SlideSize(width: Double($0.width), height: Double($0.height)) }
                    ?? SlideSize(width: placement.frame.width + clip.left + clip.right, height: placement.frame.height + clip.top + clip.bottom)
                if natural.width > 0, natural.height > 0 {
                    crop = ImageCrop(left: clip.left / natural.width, top: clip.top / natural.height,
                                     right: clip.right / natural.width, bottom: clip.bottom / natural.height)
                }
            }
            if graphic.mirrorHorizontal == true { placement.flipHorizontal.toggle() }
            if graphic.mirrorVertical == true { placement.flipVertical.toggle() }
            let outline = Self.outline(graphic, document: document)
            let picture = Picture(mediaID: mediaID, crop: crop, outline: outline.isVisible ? outline : nil, adjustments: Self.adjustments(graphic))
            let element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement,
                                       placeholder: ref?.type == .picture || ref == nil ? ref : nil, content: .picture(picture))
            return inherited(element)
        }
        let textBox = contents.first { $0.name == "draw:text-box" }
        var element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement, placeholder: ref,
                                   content: .shape(Shape(text: TextBody(), isTextBox: ref == nil)))
        element = shapeProperties(element, graphic: graphic, node: node)
        let model = modelStyle(withoutText(element))
        var body = textBox.map { text($0, baseline: baseline, model: model, element: ids.target) } ?? TextBody()
        body.properties = element.shape?.text?.properties ?? .empty
        element.shape?.text = body
        return inherited(element)
    }

    private func customShape(_ node: ODFNode, ref: PlaceholderRef?, ids: IDs) -> SlideElement? {
        let className = Self.placeholderClass(node, sheet: sheet)
        let ref = className == nil ? nil : ref
        var placement = Self.placement(node) ?? (ref != nil ? inheritedPlacement(ref) : Placement(frame: .zero))
        let geometryNode = node.child("draw:enhanced-geometry")
        // Fontwork, of any shape, is word art: its letters fill the frame. The path they follow isn't kept.
        let textPath = ODFValue.bool(geometryNode?["draw:text-path"])
        let isWordArt = ref == nil && (textPath == true || ((geometryNode?["draw:type"] ?? "").hasPrefix("fontwork-") && textPath != false))
        let geometry = isWordArt ? .rectangle : geometryNode.map { geometry($0, size: placement.frame.size) } ?? .rectangle
        if ODFValue.bool(geometryNode?["draw:mirror-horizontal"]) == true { placement.flipHorizontal.toggle() }
        if ODFValue.bool(geometryNode?["draw:mirror-vertical"]) == true { placement.flipVertical.toggle() }
        let style = frameStyle(node, className: className)
        let baseline = ODFFrameBaseline(sheet: sheet, own: style.own, outlineMaster: style.outlineMaster)
        let graphic = baseline.style(level: 0).graphic
        var element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement, placeholder: ref,
                                   content: .shape(Shape(geometry: geometry, text: TextBody(), isWordArt: isWordArt)))
        element = shapeProperties(element, graphic: graphic, node: node)
        let model = modelStyle(withoutText(element))
        var body = text(node, baseline: baseline, model: model, element: ids.target)
        body.properties = element.shape?.text?.properties ?? .empty
        element.shape?.text = body
        return inherited(element)
    }

    /// Fill, outline and text frame properties: for placeholders, only what differs from what they inherit.
    private func shapeProperties(_ element: SlideElement, graphic: ODFGraphicProperties, node: ODFNode) -> SlideElement {
        var element = element
        guard var shape = element.shape else { return element }
        let fill = Self.fill(graphic, document: document, sheet: sheet)
        let outline = Self.outline(graphic, document: document)
        let body = Self.bodyProperties(graphic)
        if element.placeholder != nil {
            let model = modelStyle(withoutText(element))
            shape.fill = fill == model.fill ? nil : fill
            shape.outline = outline == model.outline ? nil : outline
            shape.text?.properties = Self.difference(body, from: model.bodyProperties)
        } else {
            shape.fill = fill
            shape.outline = outline.isVisible ? outline : Outline.none
            shape.text?.properties = Self.difference(body, from: ElementStyle(element: withoutText(element), parents: [], theme: theme,
                                                                            defaultTextStyle: document.defaultTextStyle).bodyProperties)
        }
        element.shape = shape
        return element
    }

    private func withoutText(_ element: SlideElement) -> SlideElement {
        var copy = element
        if var shape = copy.shape {
            shape.text = TextBody()
            copy.shape = shape
        }
        return copy
    }

    private func inheritedPlacement(_ ref: PlaceholderRef?) -> Placement {
        guard let ref else { return Placement(frame: .zero) }
        return modelStyle(SlideElement(placement: nil, placeholder: ref, content: .shape(Shape(text: TextBody())))).placement
    }

    /// A placeholder at its layout's place leaves its placement to inherit.
    private func inherited(_ element: SlideElement) -> SlideElement {
        guard !isMaster, let ref = element.placeholder, let placement = element.placement, placement.rotation == 0,
              !placement.flipHorizontal, !placement.flipVertical else { return element }
        let inheritedPlacement = modelStyle(withoutText(SlideElement(placement: nil, placeholder: ref, content: element.content))).placement
        var copy = element
        if inheritedPlacement.rotation == 0, ODFCompare.same(inheritedPlacement.frame, placement.frame) { copy.placement = nil }
        return copy
    }

    /// Geometry from an enhanced geometry: a preset for the types that name one (LibreOffice's own shapes only when
    /// their outline is the preset's), else the path itself.
    private func geometry(_ node: ODFNode, size: SlideSize) -> ShapeGeometry {
        let type = node["draw:type"] ?? "non-primitive"
        var reader = ODPGeometry.EnhancedGeometryReader(node: node, size: size)
        let path = node["draw:enhanced-path"]
        if let preset = ODPGeometry.preset(type: type, modifiers: node["draw:modifiers"]) {
            let geometry = ShapeGeometry.preset(preset.name, adjustments: preset.adjustments)
            // LibreOffice's own shapes without adjust values are the preset; with them, only if they draw like it.
            if preset.exact || path == nil || node["draw:modifiers"] == nil { return geometry }
            let paths = reader.paths(path ?? "")
            let custom = ShapeGeometry.custom(CustomGeometry(paths: paths, textRect: reader.textArea(node["draw:text-areas"])))
            return ODPGeometry.outlinesMatch(geometry, custom, size: size) ? geometry : custom
        }
        guard let path else { return .rectangle }
        let paths = reader.paths(path)
        guard !paths.isEmpty else { return .rectangle }
        return .custom(CustomGeometry(paths: paths, textRect: reader.textArea(node["draw:text-areas"])))
    }

    /// The shapes of ODF 1.0: rectangles, ellipses, polygons and paths.
    private func legacyShape(_ node: ODFNode, ids: IDs) -> SlideElement? {
        let placement = Self.placement(node) ?? Placement(frame: .zero)
        let size = placement.frame.size
        var geometry = ShapeGeometry.rectangle
        switch node.name {
        case "draw:rect", "draw:caption":
            if let radius = ODFValue.length(node["draw:corner-radius"]), radius > 0, min(size.width, size.height) > 0 {
                geometry = .preset("roundRect", adjustments: ["adj": min(radius / min(size.width, size.height) * 100_000, 50_000).rounded()])
            }
        case "draw:ellipse", "draw:circle":
            let kind = node["draw:kind"] ?? "full"
            let start = ODFValue.angle(node["draw:start-angle"]) ?? 0, end = ODFValue.angle(node["draw:end-angle"]) ?? 360
            // ODF's angles turn counterclockwise; DrawingML's clockwise, in 60,000ths of a degree.
            let adj1 = Placement.normalized(360 - end) * 60_000, adj2 = Placement.normalized(360 - start) * 60_000
            switch kind {
            case "section": geometry = .preset("pie", adjustments: ["adj1": adj1.rounded(), "adj2": adj2.rounded()])
            case "cut": geometry = .preset("chord", adjustments: ["adj1": adj1.rounded(), "adj2": adj2.rounded()])
            case "arc": geometry = .preset("arc", adjustments: ["adj1": adj1.rounded(), "adj2": adj2.rounded()])
            default: geometry = .preset("ellipse", adjustments: [:])
            }
        case "draw:polygon", "draw:polyline":
            let box = Self.viewBox(node["svg:viewBox"], size: size)
            let numbers = (node["draw:points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { ODFValue.double(String($0)) }
            var commands: [PathCommand] = []
            for index in stride(from: 0, to: numbers.count - 1, by: 2) {
                let point = SlidePoint(x: numbers[index] - box.minX, y: numbers[index + 1] - box.minY)
                commands.append(commands.isEmpty ? .move(point) : .line(point))
            }
            let closed = node.name == "draw:polygon"
            if closed, !commands.isEmpty { commands.append(.close) }
            geometry = .custom(CustomGeometry(paths: [CustomPath(width: box.width, height: box.height, fill: closed ? .normal : PathFillMode.none, commands: commands)]))
        case "draw:path":
            let box = Self.viewBox(node["svg:viewBox"], size: size)
            let commands = ODPGeometry.svgPath(node["svg:d"] ?? "").map { Self.offset($0, by: SlidePoint(x: -box.minX, y: -box.minY)) }
            geometry = .custom(CustomGeometry(paths: [CustomPath(width: box.width, height: box.height, commands: commands)]))
        case "draw:regular-polygon":
            let corners = min(max(ODFValue.int(node["draw:corners"]) ?? 5, 3), 100)
            let concave = ODFValue.bool(node["draw:concave"]) ?? false
            let sharpness = min(max(ODFValue.percent(node["draw:sharpness"]) ?? 0, 0), 1)
            var commands: [PathCommand] = []
            let points = concave ? corners * 2 : corners
            for index in 0..<points {
                let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(points)
                let radius = concave && index % 2 == 1 ? 0.5 * (1 - sharpness) : 0.5
                let point = SlidePoint(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
                commands.append(commands.isEmpty ? .move(point) : .line(point))
            }
            commands.append(.close)
            geometry = .custom(CustomGeometry(paths: [CustomPath(width: 1, height: 1, commands: commands)]))
        default:
            break
        }
        let style = frameStyle(node, className: nil)
        let baseline = ODFFrameBaseline(sheet: sheet, own: style.own, outlineMaster: nil)
        let graphic = baseline.style(level: 0).graphic
        var element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement,
                                   content: .shape(Shape(geometry: geometry, text: TextBody())))
        element = shapeProperties(element, graphic: graphic, node: node)
        let model = modelStyle(withoutText(element))
        var body = text(node, baseline: baseline, model: model, element: ids.target)
        body.properties = element.shape?.text?.properties ?? .empty
        element.shape?.text = body
        return element
    }

    private static func viewBox(_ text: String?, size: SlideSize) -> (minX: Double, minY: Double, width: Double, height: Double) {
        let values = (text ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { ODFValue.double(String($0)) }
        if values.count == 4, values[2] > 0, values[3] > 0 { return (values[0], values[1], values[2], values[3]) }
        return (0, 0, 0, 0)
    }

    private static func offset(_ command: PathCommand, by delta: SlidePoint) -> PathCommand {
        func move(_ point: SlidePoint) -> SlidePoint { SlidePoint(x: point.x + delta.x, y: point.y + delta.y) }
        switch command {
        case .move(let point): return .move(move(point))
        case .line(let point): return .line(move(point))
        case .quadratic(let control, let end): return .quadratic(control: move(control), end: move(end))
        case .cubic(let control1, let control2, let end): return .cubic(control1: move(control1), control2: move(control2), end: move(end))
        case .arc, .close: return command
        }
    }

    /// Lines and connectors: a frame from one end to the other, flipped when the line runs up or left.
    private func line(_ node: ODFNode, ids: IDs) -> SlideElement? {
        var x1 = ODFValue.length(node["svg:x1"]) ?? 0, y1 = ODFValue.length(node["svg:y1"]) ?? 0
        var x2 = ODFValue.length(node["svg:x2"]) ?? 0, y2 = ODFValue.length(node["svg:y2"]) ?? 0
        if let transform = node["draw:transform"].flatMap(Self.transform) {
            let start = CGPoint(x: x1, y: y1).applying(transform), end = CGPoint(x: x2, y: y2).applying(transform)
            (x1, y1, x2, y2) = (Double(start.x), Double(start.y), Double(end.x), Double(end.y))
        }
        let frame = SlideRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        let placement = Placement(frame: frame, flipHorizontal: x2 < x1, flipVertical: y2 < y1)
        let geometry: ShapeGeometry
        var isConnector = false
        if node.name == "draw:connector" {
            isConnector = true
            switch node["draw:type"] ?? "standard" {
            case "line": geometry = .preset("straightConnector1", adjustments: [:])
            case "curve": geometry = .preset("curvedConnector3", adjustments: [:])
            default: geometry = .preset("bentConnector3", adjustments: [:])
            }
        } else {
            geometry = .line
        }
        let style = frameStyle(node, className: nil)
        let baseline = ODFFrameBaseline(sheet: sheet, own: style.own, outlineMaster: nil)
        let graphic = baseline.style(level: 0).graphic
        var outline = Self.outline(graphic, document: document)
        if !outline.isVisible, graphic.stroke == nil { outline = .solid(.black) }
        var element = SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement,
                                   content: .shape(Shape(geometry: geometry, outline: outline, isConnector: isConnector)))
        let model = modelStyle(element)
        let body = text(node, baseline: baseline, model: model, element: ids.target)
        if !body.isEmpty { element.shape?.text = body }
        return element
    }

    // MARK: Fills and outlines

    /// The fill effective graphic properties give.
    static func fill(_ graphic: ODFGraphicProperties, document: ODPDocumentReader, sheet: ODFStyleSheet) -> Fill {
        switch graphic.fill ?? "none" {
        case "solid":
            let color = graphic.fillColor ?? RGBColor(hex: "729FCF")!
            return .solid(ColorRef(color, alpha: graphic.opacity.flatMap { $0 < 1 ? $0 : nil }))
        case "gradient":
            guard let name = graphic.gradientName, let gradient = sheet.gradients[name] ?? document.commonSheet.gradients[name] else {
                return graphic.fillColor.map { .solid(ColorRef($0)) } ?? Fill.none
            }
            return .gradient(Self.gradient(gradient))
        case "bitmap":
            guard let name = graphic.imageName, let href = sheet.fillImages[name] ?? document.commonSheet.fillImages[name],
                  let id = document.media(at: href) else { return Fill.none }
            return .picture(PictureFill(mediaID: id, stretches: graphic.repeatMode != "repeat" && graphic.repeatMode != "no-repeat"))
        case "hatch":
            let color = graphic.hatchName.flatMap { sheet.hatchColors[$0] ?? document.commonSheet.hatchColors[$0] } ?? graphic.fillColor ?? .black
            return .solid(ColorRef(color))
        default:
            return Fill.none
        }
    }

    static func gradient(_ gradient: ODFGradient) -> GradientFill {
        switch gradient.style {
        case "axial":
            return GradientFill(kind: .linear(angle: Placement.normalized(90 - gradient.angle)), stops: [
                GradientStop(position: 0, color: ColorRef(gradient.start)), GradientStop(position: 0.5, color: ColorRef(gradient.end)),
                GradientStop(position: 1, color: ColorRef(gradient.start)),
            ])
        case "radial", "ellipsoid", "square", "rectangular":
            return GradientFill(kind: .radial, stops: [GradientStop(position: 0, color: ColorRef(gradient.end)),
                                                       GradientStop(position: max(0, 1 - gradient.border), color: ColorRef(gradient.start))])
        default:
            return GradientFill(kind: .linear(angle: Placement.normalized(90 - gradient.angle)), stops: [
                GradientStop(position: min(max(gradient.border, 0), 1), color: ColorRef(gradient.start)), GradientStop(position: 1, color: ColorRef(gradient.end)),
            ])
        }
    }

    /// The outline effective graphic properties give. A hairline (width 0) shows as the thinnest line.
    static func outline(_ graphic: ODFGraphicProperties, document: ODPDocumentReader) -> Outline {
        guard let stroke = graphic.stroke, stroke != "none" else { return Outline.none }
        let color = graphic.strokeColor ?? .black
        var outline = Outline(fill: .solid(ColorRef(color, alpha: graphic.strokeOpacity.flatMap { $0 < 1 ? $0 : nil })),
                              width: max(graphic.strokeWidth ?? 0.75, 0) == 0 ? 0.75 : min(graphic.strokeWidth ?? 0.75, 1000))
        if stroke == "dash" {
            let sheet = document.commonSheet
            if let name = graphic.dashName, let dash = sheet.dashes[name] {
                outline.dash = ODPGeometry.dashStyle(dash.dash, name: dash.name, width: outline.width)
            } else {
                outline.dash = .dash
            }
        }
        if let name = graphic.markerStart { outline.head = ODPGeometry.lineEnd(markerName: document.commonSheet.markers[name]?.name ?? name) }
        if let name = graphic.markerEnd { outline.tail = ODPGeometry.lineEnd(markerName: document.commonSheet.markers[name]?.name ?? name) }
        return outline
    }

    /// A picture's adjustments from its image properties. Grayscale (and black and white) is the grayscale recolor, and
    /// grayscale inverted the negative one; LibreOffice's watermark mode is the change LibreOffice makes for it: 50% more
    /// brightness and 70% less contrast.
    static func adjustments(_ graphic: ODFGraphicProperties) -> ImageAdjustments {
        func clean(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            return abs(clamped) < 0.00005 ? 0 : clamped
        }
        var brightness = graphic.luminance ?? 0, contrast = graphic.contrast ?? 0
        var recolor: ImageRecolor?
        switch graphic.colorMode {
        case "greyscale"?, "mono"?:
            recolor = graphic.colorInversion == true ? .negative : .grayscale
        case "watermark"?:
            brightness += 0.5
            contrast -= 0.7
            if graphic.colorInversion == true { recolor = .negative }
        default:
            if graphic.colorInversion == true { recolor = .negative }
        }
        return ImageAdjustments(transparency: clean(1 - (graphic.imageOpacity ?? 1), 0...1), brightness: clean(brightness, -1...1),
                                contrast: clean(contrast, -1...1), recolor: recolor)
    }

    /// How text sits, from effective graphic properties.
    static func bodyProperties(_ graphic: ODFGraphicProperties) -> ResolvedBodyProperties {
        let autofit: Autofit = graphic.shrinkToFit == true || graphic.fitToSize == true ? .shrinkOnOverflow
            : graphic.autoGrowHeight == true ? .resizeShape : .none
        let insets = TextInsets(left: graphic.paddingLeft ?? TextInsets.office.left, top: graphic.paddingTop ?? TextInsets.office.top,
                                right: graphic.paddingRight ?? TextInsets.office.right, bottom: graphic.paddingBottom ?? TextInsets.office.bottom)
        return ResolvedBodyProperties(anchor: graphic.anchor ?? .top, insets: insets, autofit: autofit, fontScale: 1, lineSpacingReduction: 0,
                                      wraps: graphic.wraps ?? true)
    }

    /// The body properties that differ from what the element would inherit.
    static func difference(_ properties: ResolvedBodyProperties, from base: ResolvedBodyProperties) -> TextBodyProperties {
        var result = TextBodyProperties()
        if properties.anchor != base.anchor { result.anchor = properties.anchor }
        let a = properties.insets, b = base.insets
        if !(ODFCompare.same(a.left, b.left) && ODFCompare.same(a.top, b.top) && ODFCompare.same(a.right, b.right) && ODFCompare.same(a.bottom, b.bottom)) {
            result.insets = a
        }
        if properties.autofit != base.autofit { result.autofit = properties.autofit }
        if properties.wraps != base.wraps { result.wraps = properties.wraps }
        return result
    }

    /// Whether two elements are the same but for their ids.
    static func sameIgnoringIDs(_ a: SlideElement, _ b: SlideElement) -> Bool {
        func strip(_ element: SlideElement) -> SlideElement {
            var copy = element
            copy.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            if case .group(let children) = element.content { copy.content = .group(children.map(strip)) }
            return copy
        }
        return strip(a) == strip(b)
    }

    // MARK: Notes

    func notes(_ node: ODFNode) -> TextBody {
        guard let frame = node.elements.first(where: { $0.name == "draw:frame" && $0["presentation:class"] == "notes" }),
              let textBox = frame.child("draw:text-box") else { return .empty }
        let style = frameStyle(frame, className: "notes")
        let baseline = ODFFrameBaseline(sheet: sheet, own: style.own, outlineMaster: nil)
        let element = SlideElement(placement: nil, content: .shape(Shape(text: TextBody())))
        let model = ElementStyle(element: element, parents: [], theme: theme, defaultTextStyle: document.defaultTextStyle)
        return text(textBox, baseline: baseline, model: model, element: element.id)
    }

    // MARK: Text

    private struct ReadRun {
        var text: String
        var values: ODFTextValues
        var link: Hyperlink?
        var field: TextFieldKind?
    }

    /// The paragraphs of a text box or shape, lists included.
    func text(_ container: ODFNode, baseline: ODFFrameBaseline, model: ElementStyle, element: UUID) -> TextBody {
        var paragraphs: [TextParagraph] = []
        func walk(_ node: ODFNode, nesting: Int, list: ODFListStyle?, labelled: Bool, depth: Int) {
            // Parsing already refuses deeper nesting than this.
            guard depth < ODFXML.maxDepth else { return }
            for child in node.elements {
                guard paragraphs.count < Self.maxParagraphs else { return }
                switch child.name {
                case "text:p", "text:h":
                    let level = min(max(nesting - 1, 0), 8)
                    let listLevel = nesting > 0 ? list?[min(nesting - 1, 9)] : nil
                    paragraphs.append(paragraph(child, level: level, list: listLevel, inList: nesting > 0, labelled: labelled && nesting > 0,
                                                baseline: baseline, model: model, element: element, index: paragraphs.count))
                case "text:list":
                    let style = child["text:style-name"].flatMap { sheet.listStyle($0) } ?? list
                    walk(child, nesting: nesting + 1, list: style, labelled: true, depth: depth + 1)
                case "text:list-item":
                    walk(child, nesting: nesting, list: list, labelled: true, depth: depth + 1)
                case "text:list-header":
                    walk(child, nesting: nesting, list: list, labelled: false, depth: depth + 1)
                default:
                    continue
                }
            }
        }
        walk(container, nesting: 0, list: nil, labelled: false, depth: 0)
        return TextBody(paragraphs: paragraphs)
    }

    private func paragraph(_ node: ODFNode, level: Int, list: ODFListLevel?, inList: Bool, labelled: Bool, baseline: ODFFrameBaseline, model: ElementStyle,
                           element: UUID, index: Int) -> TextParagraph {
        let base = baseline.values(level: level)
        let own = node["text:style-name"].map { sheet.resolved("paragraph", $0) } ?? ODFStyle(family: "paragraph")
        let endValues = base.text.applying(own.text)
        var paragraphValues = base.paragraph.applying(own.paragraph, fontSize: endValues.fontSize)
        if inList, let list {
            let margins = list.modelMargins(margin: paragraphValues.marginLeft, textIndent: paragraphValues.indent)
            paragraphValues.marginLeft = margins.left
            paragraphValues.indent = margins.indent
        }
        let bullet = labelled ? ODFBulletValues(list) : ODFBulletValues.none

        // What the model would give the paragraph anyway.
        let levelStyle = model.inheritedLevelStyle(level)
        let modelText = ODFTextValues(model.resolve(levelStyle.character))
        let modelParagraph = levelStyle.paragraph
        let modelBullet = ODFBulletValues(bullet: modelParagraph.bullet ?? Bullet.none, font: modelParagraph.bulletFont.map(theme.fonts.resolve),
                                          color: modelParagraph.bulletColor.map { model.resolve($0).rgb }, size: modelParagraph.bulletSize)

        var style = ParagraphStyle()
        if paragraphValues.alignment != (modelParagraph.alignment ?? .left) { style.alignment = paragraphValues.alignment }
        if !ODFCompare.same(paragraphValues.lineSpacing, modelParagraph.lineSpacing ?? 1) { style.lineSpacing = paragraphValues.lineSpacing }
        if !ODFCompare.same(paragraphValues.spaceBefore, modelParagraph.spaceBefore ?? 0) { style.spaceBefore = paragraphValues.spaceBefore }
        if !ODFCompare.same(paragraphValues.spaceAfter, modelParagraph.spaceAfter ?? 0) { style.spaceAfter = paragraphValues.spaceAfter }
        if !ODFCompare.same(paragraphValues.marginLeft, modelParagraph.marginLeft ?? 0) { style.marginLeft = paragraphValues.marginLeft }
        if !ODFCompare.same(paragraphValues.indent, modelParagraph.indent ?? 0) { style.indent = paragraphValues.indent }
        if bullet != modelBullet {
            style.bullet = bullet.bullet
            if bullet.bullet != Bullet.none {
                style.bulletFont = bullet.font
                style.bulletColor = bullet.color.map { ColorRef($0) }
                style.bulletSize = bullet.size
            }
        }

        if let id = node["xml:id"] ?? node["text:id"] { targets[id] = ODPMotion.Target(element: element, paragraph: index) }

        var runs: [ReadRun] = []
        var lastWasSpace = true
        collect(node, values: endValues, link: nil, into: &runs, lastWasSpace: &lastWasSpace, depth: 0)
        var textRuns: [TextRun] = []
        for run in runs where !run.text.isEmpty || run.field != nil {
            let linkBase = run.link == nil ? modelText
                : ODFTextValues(model.resolve(CharacterStyle(link: run.link).merged(over: levelStyle.character)))
            var character = Self.difference(run.values, from: linkBase)
            character.link = run.link
            let textRun = TextRun(run.text, style: character, field: run.field)
            if run.field == nil, let last = textRuns.last, last.field == nil, last.style == character {
                textRuns[textRuns.count - 1].text += run.text
            } else {
                textRuns.append(textRun)
            }
        }
        return TextParagraph(runs: textRuns, level: level, style: style, endStyle: Self.difference(endValues, from: modelText))
    }

    /// Character properties that differ from what the model gives.
    static func difference(_ values: ODFTextValues, from base: ODFTextValues) -> CharacterStyle {
        var style = CharacterStyle()
        if values.fontFamily != base.fontFamily { style.fontFamily = values.fontFamily }
        if !ODFCompare.same(values.fontSize, base.fontSize) { style.fontSize = values.fontSize }
        if values.bold != base.bold { style.bold = values.bold }
        if values.italic != base.italic { style.italic = values.italic }
        if values.underline != base.underline { style.underline = values.underline }
        if values.strikethrough != base.strikethrough { style.strikethrough = values.strikethrough }
        if values.color != base.color { style.color = ColorRef(values.color) }
        if values.highlight != base.highlight, let highlight = values.highlight { style.highlight = ColorRef(highlight) }
        if values.baseline != base.baseline { style.baseline = values.baseline }
        return style
    }

    /// Runs of a paragraph, following ODF's white-space rules: runs of spaces, tabs and newlines in the text are one
    /// space, and none at the start of the paragraph.
    private func collect(_ node: ODFNode, values: ODFTextValues, link: Hyperlink?, into runs: inout [ReadRun], lastWasSpace: inout Bool, depth: Int) {
        guard depth < 32 else { return }
        func append(_ text: String, field: TextFieldKind? = nil) {
            if field == nil, let last = runs.last, last.field == nil, last.values == values, last.link == link {
                runs[runs.count - 1].text += text
            } else {
                runs.append(ReadRun(text: text, values: values, link: link, field: field))
            }
        }
        for child in node.children {
            if child.isText {
                var text = ""
                for character in child.text {
                    if character == " " || character == "\t" || character == "\n" || character == "\r" || character == "\r\n" {
                        if lastWasSpace { continue }
                        text.append(" ")
                        lastWasSpace = true
                    } else {
                        text.append(character)
                        lastWasSpace = false
                    }
                }
                if !text.isEmpty { append(text) }
                continue
            }
            switch child.name {
            case "text:span":
                let style = child["text:style-name"].map { sheet.resolved("text", $0).text } ?? ODFTextProperties()
                var nested: [ReadRun] = []
                collect(child, values: values.applying(style), link: link, into: &nested, lastWasSpace: &lastWasSpace, depth: depth + 1)
                for run in nested {
                    if run.field == nil, let last = runs.last, last.field == nil, last.values == run.values, last.link == run.link {
                        runs[runs.count - 1].text += run.text
                    } else {
                        runs.append(run)
                    }
                }
            case "text:a":
                var nested: [ReadRun] = []
                collect(child, values: values, link: hyperlink(child["xlink:href"]), into: &nested, lastWasSpace: &lastWasSpace, depth: depth + 1)
                runs += nested
            case "text:s":
                append(String(repeating: " ", count: min(max(ODFValue.int(child["text:c"]) ?? 1, 1), 1000)))
                lastWasSpace = false
            case "text:tab":
                append("\t")
                lastWasSpace = false
            case "text:line-break":
                append(TextRun.lineBreak)
                lastWasSpace = false
            case "text:page-number":
                append(child.textContent.isEmpty ? "‹#›" : child.textContent, field: .slideNumber)
                lastWasSpace = false
            case "text:date", "text:time", "presentation:date-time":
                var type = child.name == "text:time" ? "datetime10" : "datetime1"
                if let name = child["style:data-style-name"] {
                    let decoded = ODFFormat.decodedStyleName(name)
                    if decoded.hasPrefix("datetime"), Int(decoded.dropFirst(8)) != nil { type = decoded }
                }
                append(child.textContent, field: .dateTime(type))
                lastWasSpace = false
            case "text:soft-page-break", "text:bookmark", "text:bookmark-start", "text:bookmark-end", "text:reference-mark",
                 "text:reference-mark-start", "text:reference-mark-end", "text:note", "draw:frame", "draw:a":
                continue
            case "office:annotation", "officeooo:annotation":
                textAnnotations.append(child)
            default:
                collect(child, values: values, link: link, into: &runs, lastWasSpace: &lastWasSpace, depth: depth + 1)
            }
        }
    }

    /// A link's target: another slide ("#page3", "#Slide 3"), or an address.
    private func hyperlink(_ href: String?) -> Hyperlink? {
        guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty else { return nil }
        if href.hasPrefix("#") {
            let name = String(href.dropFirst())
            if let id = document.slideIDs[name] ?? document.slideIDs[name.removingPercentEncoding ?? name] { return .slide(id) }
            let digits = name.drop { !$0.isNumber }
            if let number = Int(digits), number >= 1, number <= document.slideIDsByNumber.count,
               name.lowercased().hasPrefix("slide") || name.lowercased().hasPrefix("page") {
                return .slide(document.slideIDsByNumber[number - 1])
            }
            return nil
        }
        return .url(href)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
