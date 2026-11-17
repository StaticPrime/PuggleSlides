import Foundation

/// What reading the elements of one part (a master, layout, slide or notes slide) needs.
struct PPTXPartContext {
    let package: PPTXPackageReader
    let path: String
    let relationships: PPTXRelationships
    let map: PPTXColorMap
    let theme: PPTXThemeData
    /// The geometry of the placeholder a placeholder without geometry of its own inherits.
    var parentGeometry: (PlaceholderRef) -> ShapeGeometry? = { _ in nil }
    /// Keeps placeholders' list styles as found, for color map fixes once everything is read.
    var recordsListStyles = false

    static let maxGroupDepth = 32

    init(package: PPTXPackageReader, path: String, relationships: PPTXRelationships, map: PPTXColorMap, theme: PPTXThemeData) {
        self.package = package
        self.path = path
        self.relationships = relationships
        self.map = map
        self.theme = theme
    }

    var colors: PPTXColorReader { PPTXColorReader(map: map) }

    func fills(groupFill: Fill? = nil) -> PPTXFillReader {
        let package = package, relationships = relationships
        return PPTXFillReader(colors: colors, theme: theme, media: { id in
            guard let relationship = relationships[id], !relationship.isExternal else { return nil }
            return package.media(at: relationship.target)
        }, groupFill: groupFill)
    }

    var text: PPTXTextReader {
        let package = package, relationships = relationships
        return PPTXTextReader(colors: colors) { node in
            Self.link(node, relationships: relationships, slideIDs: package.slideIDs)
        }
    }

    /// A run's link: a web address, or a jump to another slide.
    static func link(_ node: XNode, relationships: PPTXRelationships, slideIDs: [String: UUID]) -> Hyperlink? {
        let action = node["action"] ?? ""
        guard let relationship = relationships[node["id"]] else { return nil }
        if action.hasPrefix("ppaction://hlinksldjump") {
            guard !relationship.isExternal, let id = slideIDs[PPTXPackageReader.key(relationship.target)] else { return nil }
            return .slide(id)
        }
        guard action.isEmpty || action.hasPrefix("ppaction://hlinkfile") else { return nil }
        if relationship.isExternal {
            let target = relationship.target.trimmingCharacters(in: .whitespacesAndNewlines)
            return target.isEmpty ? nil : .url(target)
        }
        if let id = slideIDs[PPTXPackageReader.key(relationship.target)] { return .slide(id) }
        return nil
    }

    // MARK: Element trees

    /// The elements of an `spTree` or group, in drawing order.
    func elements(in container: XNode?, depth: Int = 0, groupFill: Fill? = nil) -> [SlideElement] {
        guard let container else { return [] }
        var result: [SlideElement] = []
        for child in container.children {
            result += elements(from: child, depth: depth, groupFill: groupFill)
        }
        return result
    }

    private func elements(from node: XNode, depth: Int, groupFill: Fill?) -> [SlideElement] {
        switch node.name {
        case "sp":
            return shape(node, groupFill: groupFill, isConnector: false).map { [$0] } ?? []
        case "cxnSp":
            return shape(node, groupFill: groupFill, isConnector: true).map { [$0] } ?? []
        case "pic":
            return picture(node, groupFill: groupFill).map { [$0] } ?? []
        case "grpSp":
            guard depth < Self.maxGroupDepth else {
                package.warnings.insert(.otherContent)
                return []
            }
            return group(node, depth: depth, groupFill: groupFill).map { [$0] } ?? []
        case "graphicFrame":
            return graphicFrame(node).map { [$0] } ?? []
        case "contentPart":
            package.warnings.insert(.ink)
            return []
        case "AlternateContent":
            guard depth < Self.maxGroupDepth else { return [] }
            return alternateContent(node).flatMap { elements(from: $0, depth: depth + 1, groupFill: groupFill) }
        default:
            return []
        }
    }

    static let elementNames: Set<String> = ["sp", "cxnSp", "pic", "grpSp"]

    /// Newer content with a fallback for older apps: ink, equations, slide zooms and 3D models fall back to
    /// pictures, which are kept. Newer charts (chartex) fall back to a note that the chart can't be shown, which isn't.
    /// Tables and charts offered as a choice are read from it.
    private func alternateContent(_ node: XNode) -> [XNode] {
        let choices = node.children("Choice")
        for choice in choices {
            if choice.children.contains(where: { $0.name == "contentPart" }) { package.warnings.insert(.ink) }
            let frames = choice.children("graphicFrame")
            if frames.contains(where: { Self.frameURI($0).contains("chartex") }) {
                package.warnings.insert(.charts)
                return []
            }
            if !frames.isEmpty, frames.allSatisfy(Self.holdsTableOrChart) { return choice.children }
            frames.forEach(noteGraphicFrame)
        }
        if let fallback = node.child("Fallback"), fallback.children.contains(where: { Self.elementNames.contains($0.name) }) {
            return fallback.children
        }
        if let choice = choices.first(where: { $0.children.contains { Self.elementNames.contains($0.name) } }) {
            return choice.children
        }
        if let fallback = node.child("Fallback") {
            fallback.children("graphicFrame").forEach(noteGraphicFrame)
        }
        return []
    }

    /// What a graphic frame says it holds: its `graphicData`'s URI.
    static func frameURI(_ node: XNode) -> String {
        node.child("graphic")?.child("graphicData")?["uri"] ?? ""
    }

    /// Whether a graphic frame holds a table or a DrawingML chart (transitional or strict), which are read.
    static func holdsTableOrChart(_ node: XNode) -> Bool {
        let data = node.child("graphic")?.child("graphicData")
        if data?.child("tbl") != nil { return true }
        let uri = data?["uri"] ?? ""
        return data?.child("chart") != nil && (uri.hasSuffix("drawingml/2006/chart") || uri.hasSuffix("ooxml/drawingml/chart"))
    }

    // MARK: Graphic frames

    /// A table or chart. Frames that can't be read, and diagrams and embedded objects, leave a warning.
    private func graphicFrame(_ node: XNode) -> SlideElement? {
        guard Self.holdsTableOrChart(node), let data = node.child("graphic")?.child("graphicData") else {
            noteGraphicFrame(node)
            return nil
        }
        let nonVisual = node.child("nvGraphicFramePr")
        let identity = Identity(nonVisual?.child("cNvPr"), package: package)
        guard !identity.isHidden else {
            package.warnings.insert(.otherContent)
            return nil
        }
        let content: ElementContent
        if let tbl = data.child("tbl") {
            guard let table = table(tbl) else {
                package.warnings.insert(.tables)
                return nil
            }
            content = .table(table)
        } else {
            guard let chart = chart(relationship: data.child("chart")?["id"]) else {
                package.warnings.insert(.charts)
                return nil
            }
            content = .chart(chart)
        }
        let element = SlideElement(name: identity.name, placement: Self.placement(node.child("xfrm")) ?? Placement(frame: .zero),
                                   placeholder: Self.placeholder(nonVisual?.child("nvPr")), content: content, altTitle: identity.altTitle,
                                   altDescription: identity.altDescription)
        identity.record(element.id, in: package)
        return element
    }

    /// The chart in the part a relationship names, read with this part's colors; nil when it can't be read. Charts
    /// drawn only approximately leave a warning.
    private func chart(relationship id: String?) -> Chart? {
        guard let relationship = relationships[id], !relationship.isExternal else { return nil }
        let key = PPTXChartKey(path: PPTXPackageReader.key(relationship.target), map: map, colors: theme.colors)
        if let known = package.charts[key] {
            if known.isApproximate, known.chart != nil { package.warnings.insert(.charts) }
            return known.chart
        }
        guard let root = try? package.xml(relationship.target) else {
            package.charts[key] = PPTXChartReader.Result(chart: nil, isApproximate: true)
            return nil
        }
        let chartPath = relationship.target
        let package = package
        var workbook: PPTXWorkbookReader??
        let reader = PPTXChartReader(colors: colors, scheme: theme.colors) {
            if let known = workbook { return known }
            let embedded = package.relationshipsIfReadable(of: chartPath).first("package").flatMap { package.embeddedPackage(at: $0.target) }
            let opened = embedded.flatMap(PPTXWorkbookReader.init)
            workbook = .some(opened)
            return opened
        }
        let result = reader.read(root)
        package.charts[key] = result
        if result.isApproximate, result.chart != nil { package.warnings.insert(.charts) }
        return result.chart
    }

    /// Tables, charts, diagrams and embedded objects that can't be kept; each leaves a warning.
    private func noteGraphicFrame(_ node: XNode) {
        let data = node.child("graphic")?.child("graphicData")
        let uri = data?["uri"] ?? ""
        let names = Set(data?.children.map(\.name) ?? [])
        if uri.hasSuffix("/table") || names.contains("tbl") {
            package.warnings.insert(.tables)
        } else if uri.contains("chart") || names.contains("chart") {
            package.warnings.insert(.charts)
        } else if uri.hasSuffix("/diagram") || names.contains("relIds") {
            package.warnings.insert(.diagrams)
        } else if uri.hasSuffix("/ole") || names.contains("oleObj") {
            package.warnings.insert(.embeddedObjects)
        } else {
            package.warnings.insert(.otherContent)
        }
    }

    // MARK: Shapes

    /// Name, alt text and visibility from `cNvPr`. A link or action on the whole shape has no place in the model,
    /// so it leaves a warning.
    private struct Identity {
        var id: String?
        var name = ""
        var altTitle: String?
        var altDescription: String?
        var isHidden = false
        /// Office 2016's creation id (`a16:creationId`), which modern comments name shapes by.
        var creationID: String?

        init(_ node: XNode?, package: PPTXPackageReader) {
            guard let node else { return }
            id = node["id"]
            for ext in node.child("extLst")?.children("ext") ?? [] where ext["uri"]?.uppercased() == PPTXComments.shapeCreationIDExtension {
                creationID = ext.child("creationId")?["id"].flatMap(PPTXComments.guid)
            }
            name = node["name"] ?? ""
            altTitle = node["title"].flatMap { $0.isEmpty ? nil : $0 }
            altDescription = node["descr"].flatMap { $0.isEmpty ? nil : $0 }
            isHidden = PPTXValue.bool(node["hidden"]) ?? false
            // A clip's media action plays it, as the clip does.
            if let link = node.child("hlinkClick") {
                let action = link["action"] ?? ""
                if !(link["id"] ?? "").isEmpty || !(action.isEmpty || action == "ppaction://noaction" || action == "ppaction://media") {
                    package.warnings.insert(.otherContent)
                }
            }
        }

        /// Notes the ids animations and comments name the element by.
        func record(_ element: UUID, in package: PPTXPackageReader) {
            if let id { package.shapeIDs[element] = id }
            if let creationID { package.creationIDs[element] = creationID }
        }
    }

    static func placeholder(_ nvPr: XNode?) -> PlaceholderRef? {
        guard let ph = nvPr?.child("ph") else { return nil }
        // The type defaults to obj, as the schema says.
        let type = ph["type"].flatMap(PlaceholderType.init(rawValue:)) ?? .object
        let index = min(max(PPTXValue.int(ph["idx"]) ?? 0, 0), Int(UInt32.max))
        return PlaceholderRef(type: type, index: index)
    }

    /// An `xfrm`'s frame, rotation and flips; nil when there is none.
    static func placement(_ xfrm: XNode?) -> Placement? {
        guard let xfrm, xfrm.child("off") != nil || xfrm.child("ext") != nil else { return nil }
        let offset = xfrm.child("off"), extent = xfrm.child("ext")
        let frame = SlideRect(x: PPTXValue.points(offset?["x"]) ?? 0, y: PPTXValue.points(offset?["y"]) ?? 0,
                              width: max(0, PPTXValue.points(extent?["cx"]) ?? 0), height: max(0, PPTXValue.points(extent?["cy"]) ?? 0))
        return Placement(frame: frame, rotation: PPTXValue.degrees(xfrm["rot"]) ?? 0,
                         flipHorizontal: PPTXValue.bool(xfrm["flipH"]) ?? false, flipVertical: PPTXValue.bool(xfrm["flipV"]) ?? false)
    }

    private func shape(_ node: XNode, groupFill: Fill?, isConnector: Bool) -> SlideElement? {
        let nonVisual = node.child(isConnector ? "nvCxnSpPr" : "nvSpPr")
        let identity = Identity(nonVisual?.child("cNvPr"), package: package)
        guard !identity.isHidden else {
            package.warnings.insert(.otherContent)
            return nil
        }
        let nvPr = nonVisual?.child("nvPr")
        let placeholder = isConnector ? nil : Self.placeholder(nvPr)
        let spPr = node.child("spPr")
        let placement = Self.placement(spPr?.child("xfrm"))
        let fills = fills(groupFill: groupFill)
        let references = fills.styleReferences(node.child("style"))
        let geometry = PPTXGeometry.read(spPr, size: placement?.frame.size)
            ?? placeholder.flatMap(parentGeometry) ?? .rectangle
        let fill = fills.fill(in: spPr) ?? references.fill
        let outline = fills.outline(spPr?.child("ln"), base: references.outline)

        var body: TextBody?
        let txBody = isConnector ? nil : node.child("txBody")
        if let txBody {
            var text = self.text.body(txBody)
            // The style's font and color sit just above inherited text formatting.
            if references.fontColor != nil || references.fontFamily != nil {
                for level in 0...8 {
                    var style = text.listStyle[level]
                    if style.character.color == nil { style.character.color = references.fontColor }
                    if style.character.fontFamily == nil { style.character.fontFamily = references.fontFamily }
                    text.listStyle[level] = style
                }
            }
            body = text
        }
        let isTextBox = PPTXValue.bool(nonVisual?.child("cNvSpPr")?["txBox"]) ?? false
        var shape = Shape(geometry: geometry, fill: fill, outline: outline, text: body, isTextBox: isTextBox, isConnector: isConnector)
        var inheritsColor = false
        if let txBody, let text = body, Self.isWordArt(txBody.child("bodyPr")) {
            wordArt(&shape, text: text, txBody: txBody, fills: fills, fontColor: references.fontColor)
            // Word art marked `fromWordArt` states its paint; text PowerPoint warped shows in the color it inherits.
            inheritsColor = shape.fill == nil && PPTXValue.bool(txBody.child("bodyPr")?["fromWordArt"]) != true
        }
        let element = SlideElement(name: identity.name, placement: placement ?? (placeholder == nil ? Placement(frame: .zero) : nil),
                                   placeholder: placeholder, content: .shape(shape), altTitle: identity.altTitle,
                                   altDescription: identity.altDescription)
        identity.record(element.id, in: package)
        if inheritsColor { package.wordArtWithInheritedColor.insert(element.id) }
        if recordsListStyles, placeholder != nil {
            package.listStyleNodes[element.id] = txBody?.child("lstStyle")
            if let reference = node.child("style")?.child("fontRef"), colors.color(in: reference) != nil {
                package.fontReferenceNodes[element.id] = reference
            }
        }
        return element
    }

    /// Word art: marked as such (`fromWordArt`), or text PowerPoint warps into a shape. Only the plain warp is drawn;
    /// other warps are kept as word art all the same. `textNoShape` is PowerPoint's "no warp".
    static func isWordArt(_ bodyPr: XNode?) -> Bool {
        guard let bodyPr else { return false }
        if PPTXValue.bool(bodyPr["fromWordArt"]) == true { return true }
        guard let warp = bodyPr.child("prstTxWarp") else { return false }
        return warp["prst"] != "textNoShape"
    }

    /// Word art letters are painted with the shape's fill and outline, which files keep on the runs: they're taken
    /// from the first run (or the paragraph end), and the runs' own colors, which word art doesn't show, go.
    private func wordArt(_ shape: inout Shape, text: TextBody, txBody: XNode, fills: PPTXFillReader, fontColor: ColorRef?) {
        let paragraph = txBody.children("p").first
        let properties = paragraph?.children.first { ($0.name == "r" || $0.name == "fld") && $0.child("rPr") != nil }?.child("rPr")
            ?? paragraph?.child("endParaRPr")
        var body = text
        shape.isWordArt = true
        shape.fill = fills.fill(in: properties) ?? fontColor.map(Fill.solid) ?? text.listStyle[0].character.color.map(Fill.solid)
        shape.outline = properties?.child("ln").flatMap { fills.outline($0, base: nil) }
        body.paragraphs = text.paragraphs.map { paragraph in
            var paragraph = paragraph
            paragraph.runs = PPTXTextReader.merged(paragraph.runs.map { run in
                var run = run
                run.style.color = nil
                return run
            })
            paragraph.endStyle.color = nil
            return paragraph
        }
        shape.text = body
    }

    private func picture(_ node: XNode, groupFill: Fill?) -> SlideElement? {
        let nonVisual = node.child("nvPicPr")
        let identity = Identity(nonVisual?.child("cNvPr"), package: package)
        guard !identity.isHidden else {
            package.warnings.insert(.otherContent)
            return nil
        }
        let nvPr = nonVisual?.child("nvPr")
        let blipFill = node.child("blipFill")
        if let source = mediaSource(nvPr) {
            if let mediaID = source.mediaID {
                let clip = clip(source, mediaID: mediaID, blip: blipFill?.child("blip"))
                let placeholder = Self.placeholder(nvPr)
                let element = SlideElement(name: identity.name, placement: Self.placement(node.child("spPr")?.child("xfrm"))
                                            ?? (placeholder == nil ? Placement(frame: .zero) : nil),
                                           placeholder: placeholder, content: .media(clip), altTitle: identity.altTitle,
                                           altDescription: identity.altDescription)
                identity.record(element.id, in: package)
                return element
            }
            // Linked, missing or unreadable media can't be kept; the poster is.
            package.warnings.insert(source.kind == .audio ? .audio : .video)
        }
        let fills = fills(groupFill: groupFill)
        guard let mediaID = fills.media(blipFill?.child("blip")?["embed"]) else {
            // Linked pictures and missing images can't be shown.
            package.warnings.insert(.otherContent)
            return nil
        }
        var crop = ImageCrop.none
        if let source = blipFill?.child("srcRect") {
            crop = ImageCrop(left: PPTXValue.fraction(source["l"]) ?? 0, top: PPTXValue.fraction(source["t"]) ?? 0,
                             right: PPTXValue.fraction(source["r"]) ?? 0, bottom: PPTXValue.fraction(source["b"]) ?? 0)
        }
        let placeholder = Self.placeholder(nvPr)
        let spPr = node.child("spPr")
        let placement = Self.placement(spPr?.child("xfrm"))
        let references = fills.styleReferences(node.child("style"))
        let geometry = PPTXGeometry.read(spPr, size: placement?.frame.size) ?? .rectangle
        let outline = fills.outline(spPr?.child("ln"), base: references.outline)
        let picture = Picture(mediaID: mediaID, crop: crop, geometry: geometry, outline: outline,
                              adjustments: PPTXPictureEffects.adjustments(blipFill?.child("blip"), colors: colors))
        let element = SlideElement(name: identity.name, placement: placement ?? (placeholder == nil ? Placement(frame: .zero) : nil),
                                   placeholder: placeholder, content: .picture(picture), altTitle: identity.altTitle,
                                   altDescription: identity.altDescription)
        identity.record(element.id, in: package)
        return element
    }

    private func group(_ node: XNode, depth: Int, groupFill: Fill?) -> SlideElement? {
        let nonVisual = node.child("nvGrpSpPr")
        let identity = Identity(nonVisual?.child("cNvPr"), package: package)
        guard !identity.isHidden else {
            package.warnings.insert(.otherContent)
            return nil
        }
        let properties = node.child("grpSpPr")
        let ownFill = fills(groupFill: groupFill).fill(in: properties)
        let children = elements(in: node, depth: depth + 1, groupFill: ownFill ?? groupFill)
        guard !children.isEmpty else { return nil }
        let transform = PPTXGroupTransform(properties?.child("xfrm"))
        let mapped = children.map(transform.map)
        let element = PPTXGroupTransform.group(mapped, name: identity.name, altTitle: identity.altTitle, altDescription: identity.altDescription)
        identity.record(element.id, in: package)
        return element
    }
}

/// A chart part read with one color map and theme: what a chart read once can be shared by.
struct PPTXChartKey: Hashable {
    var path: String
    var map: PPTXColorMap
    var colors: ColorScheme
}

/// A group's mapping from its children's coordinate space (chOff, chExt) to its parent's, with its own
/// rotation and flips. Children are kept in slide coordinates, so groups are flattened into them.
struct PPTXGroupTransform {
    var offset = SlidePoint.zero
    var size = SlideSize(width: 0, height: 0)
    var childOffset = SlidePoint.zero
    var childSize = SlideSize(width: 0, height: 0)
    var rotation = 0.0
    var flipHorizontal = false
    var flipVertical = false
    var isIdentity = true

    init(_ xfrm: XNode?) {
        guard let xfrm else { return }
        func point(_ node: XNode?) -> SlidePoint {
            SlidePoint(x: PPTXValue.points(node?["x"]) ?? 0, y: PPTXValue.points(node?["y"]) ?? 0)
        }
        func extent(_ node: XNode?) -> SlideSize {
            SlideSize(width: max(0, PPTXValue.points(node?["cx"]) ?? 0), height: max(0, PPTXValue.points(node?["cy"]) ?? 0))
        }
        offset = point(xfrm.child("off"))
        size = extent(xfrm.child("ext"))
        childOffset = xfrm.child("chOff") == nil ? offset : point(xfrm.child("chOff"))
        childSize = xfrm.child("chExt") == nil ? size : extent(xfrm.child("chExt"))
        rotation = Placement.normalized(PPTXValue.degrees(xfrm["rot"]) ?? 0)
        flipHorizontal = PPTXValue.bool(xfrm["flipH"]) ?? false
        flipVertical = PPTXValue.bool(xfrm["flipV"]) ?? false
        // Groups PuggleSlides writes keep their children in slide coordinates: nothing to map.
        isIdentity = offset == childOffset && size == childSize && rotation == 0 && !flipHorizontal && !flipVertical
    }

    func map(_ element: SlideElement) -> SlideElement {
        guard !isIdentity else { return element }
        var copy = element
        if case .group(let children) = element.content {
            let mapped = children.map(map)
            copy.content = .group(mapped)
            copy.placement = Placement(frame: Self.bounds(of: mapped) ?? .zero)
            return copy
        }
        copy.placement = element.placement.map(map)
        // A table is laid out from its columns and rows, which stretch with the group.
        if case .table(var table) = element.content, scale != (1, 1) {
            table.scale(width: scale.x, height: scale.y)
            copy.content = .table(table)
        }
        return copy
    }

    /// How much the group stretches its children.
    var scale: (x: Double, y: Double) {
        var scaleX = childSize.width > 0 ? size.width / childSize.width : 1
        var scaleY = childSize.height > 0 ? size.height / childSize.height : 1
        if !scaleX.isFinite { scaleX = 1 }
        if !scaleY.isFinite { scaleY = 1 }
        return (scaleX, scaleY)
    }

    func map(_ placement: Placement) -> Placement {
        let (scaleX, scaleY) = scale
        var frame = placement.frame
        frame = SlideRect(x: offset.x + (frame.x - childOffset.x) * scaleX, y: offset.y + (frame.y - childOffset.y) * scaleY,
                          width: frame.width * scaleX, height: frame.height * scaleY)
        var rotation = placement.rotation
        var flipHorizontal = placement.flipHorizontal, flipVertical = placement.flipVertical
        if self.rotation != 0 || self.flipHorizontal || self.flipVertical {
            // Flip, then turn, about the group's center: the child's center moves, and its own turn and flips combine.
            let centerX = offset.x + size.width / 2, centerY = offset.y + size.height / 2
            var dx = frame.midX - centerX, dy = frame.midY - centerY
            if self.flipHorizontal { dx = -dx }
            if self.flipVertical { dy = -dy }
            let angle = self.rotation * .pi / 180
            let x = dx * cos(angle) - dy * sin(angle), y = dx * sin(angle) + dy * cos(angle)
            frame.x = centerX + x - frame.width / 2
            frame.y = centerY + y - frame.height / 2
            rotation = self.rotation + (self.flipHorizontal != self.flipVertical ? -rotation : rotation)
            flipHorizontal = flipHorizontal != self.flipHorizontal
            flipVertical = flipVertical != self.flipVertical
        }
        return Placement(frame: frame, rotation: rotation, flipHorizontal: flipHorizontal, flipVertical: flipVertical)
    }

    /// The smallest upright rectangle around the elements.
    static func bounds(of elements: [SlideElement]) -> SlideRect? {
        elements.compactMap { $0.placement?.boundingBox }.reduce(nil as SlideRect?) { $0?.union($1) ?? $1 }
    }

    /// A group of elements already in slide coordinates; its placement is their bounding box.
    static func group(_ children: [SlideElement], name: String, altTitle: String? = nil, altDescription: String? = nil) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: bounds(of: children) ?? .zero), content: .group(children),
                     altTitle: altTitle, altDescription: altDescription)
    }
}
