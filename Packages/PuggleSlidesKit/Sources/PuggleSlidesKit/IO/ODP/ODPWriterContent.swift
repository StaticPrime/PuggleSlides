import CoreGraphics
import Foundation

/// What a frame's text inherits in the file: the frame's own style over its master's presentation style for the
/// paragraph's level (outline placeholders) or over its parents. Reading and writing agree on this exactly.
struct ODFFrameBaseline {
    let sheet: ODFStyleSheet
    let own: ODFStyle
    /// Outline placeholders take each level's formatting from "<master>-outlineN".
    let outlineMaster: String?

    func style(level: Int) -> ODFStyle {
        if let master = outlineMaster {
            let name = "\(master)-outline\(min(max(level, 0), 8) + 1)"
            let classStyle = sheet.style("presentation", name) != nil ? name : "\(master)-outline1"
            var own = self.own
            own.parent = nil
            return own.merged(over: sheet.resolved("presentation", classStyle))
        }
        return own.merged(over: sheet.resolved(own.family, own.parent))
    }

    func values(level: Int) -> (text: ODFTextValues, paragraph: ODFParagraphValues, bullet: ODFBulletValues, list: ODFListLevel?) {
        let style = style(level: level)
        let text = ODFTextValues.fallback.applying(style.text)
        let paragraph = ODFParagraphValues.fallback.applying(style.paragraph, fontSize: text.fontSize)
        let list = style.listStyle?[level]
        return (text, paragraph, ODFBulletValues(list), list)
    }
}

/// Writes pages: slides with their notes, timing and placeholders, and master pages' shapes.
struct ODPContentWriter {
    let document: ODPDocumentWriter
    private var presentation: Presentation { document.presentation }

    init(document: ODPDocumentWriter) {
        self.document = document
    }

    /// Where shapes are written and what they inherit.
    struct Page {
        var masterName: String
        var themeIndex: Int
        var theme: Theme
        var styles: ODFAutomaticStyles
        var layer: String
        var isMaster: Bool
        var slideNumber: Int?
        /// Ids of animated elements and their paragraphs.
        var targets: [UUID: (shape: String, paragraphs: [String])] = [:]
        /// How each element's formatting is inherited.
        var style: (SlideElement) -> ElementStyle
    }

    // MARK: Slides

    func slides() -> String {
        var xml = XMLWriter(fragmentCapacity: 64 * 1024 + presentation.slides.count * 8 * 1024)
        for (index, slide) in presentation.slides.enumerated() {
            self.slide(slide, index: index, into: &xml)
        }
        return String(decoding: xml.bytes, as: UTF8.self)
    }

    private func slide(_ slide: Slide, index: Int, into xml: inout XMLWriter) {
        let location = presentation.layoutLocation(slide.layoutID)
        let themeIndex = location?.theme ?? 0
        let theme = presentation.theme(for: slide)
        let pageID = "page\(index + 1)"
        let presentation = self.presentation
        var page = Page(masterName: document.masterName(for: slide), themeIndex: themeIndex, theme: theme, styles: document.contentStyles,
                        layer: "layout", isMaster: false, slideNumber: index + 1, style: { presentation.style(for: $0, on: slide) })
        // Animated elements need ids, and their paragraphs too when they animate by paragraph.
        let animated = Set(slide.animations.map(\.elementID))
        for (elementIndex, element) in slide.elements.enumerated() where animated.contains(element.id) && isWritable(element) {
            let shapeID = "s\(index + 1)e\(elementIndex + 1)"
            var paragraphs: [String] = []
            if slide.animations.contains(where: { $0.elementID == element.id && $0.byParagraph }), let text = element.shape?.text {
                for (paragraphIndex, paragraph) in text.paragraphs.enumerated() where !paragraph.isEmpty {
                    paragraphs.append("\(shapeID)p\(paragraphIndex + 1)")
                }
            }
            page.targets[element.id] = (shapeID, paragraphs)
        }
        // Clips need ids for the commands that play them, wherever they are.
        var clips: [(target: String, clip: MediaClip)] = []
        func findClips(_ elements: [SlideElement], depth: Int) {
            guard depth < 32 else { return }
            for element in elements where isWritable(element) {
                if case .group(let children) = element.content { findClips(children, depth: depth + 1) }
                guard let clip = element.media else { continue }
                if page.targets[element.id] == nil { page.targets[element.id] = ("s\(index + 1)m\(clips.count + 1)", []) }
                if let target = page.targets[element.id]?.shape { clips.append((target, clip)) }
            }
        }
        findClips(slide.elements, depth: 0)
        // Elements comments are about need ids too, which their annotations name.
        var anchors: [UUID: String] = [:]
        for thread in slide.comments {
            guard let elementID = thread.elementID, anchors[elementID] == nil,
                  let element = PPTXComments.element(elementID, in: slide.elements), isWritable(element) else { continue }
            if page.targets[elementID] == nil { page.targets[elementID] = ("s\(index + 1)c\(anchors.count + 1)", []) }
            anchors[elementID] = page.targets[elementID]?.shape
        }

        var style = ODFStyle(family: "drawing-page")
        style.page.backgroundVisible = true
        style.page.backgroundObjectsVisible = true
        style.page.displayFooter = false
        style.page.displayPageNumber = false
        style.page.displayDateTime = false
        if let background = slide.background {
            if case .none = background {
                style.page.backgroundVisible = false
            } else {
                style.page.fill = document.fillProperties(background, colors: theme.colors)
            }
        }
        if slide.isSkipped { style.page.visible = false }
        if let transition = slide.transition, let smil = ODPMotion.smil(transition.kind) {
            style.page.transitionType = smil.type
            style.page.transitionSubtype = smil.subtype
            style.page.transitionSpeed = ODPMotion.speed(transition.duration)
        }
        let pageStyle = document.contentStyles.name(style, kind: "dp")

        xml.raw("<draw:page")
        xml.attribute("draw:name", document.pageNames[slide.id] ?? pageID)
        xml.attribute("draw:style-name", pageStyle)
        xml.attribute("draw:master-page-name", page.masterName)
        if let layout = document.pageLayoutName(for: slide) { xml.attribute("presentation:presentation-page-layout-name", layout) }
        xml.raw(" xml:id=\"\(pageID)\">")
        for element in slide.elements { self.element(element, page: page, into: &xml) }
        if let timing = ODPMotion.timing(for: slide, pageID: pageID, targets: page.targets, clips: clips) { xml.raw(timing) }
        notes(slide, page: page, into: &xml)
        // Comments last, where LibreOffice writes them.
        ODPComments.write(slide.comments.filter { !$0.comments.isEmpty }, slideNumber: index + 1, anchors: anchors, zone: .current, into: &xml)
        xml.raw("</draw:page>")
    }

    private func notes(_ slide: Slide, page: Page, into xml: inout XMLWriter) {
        let frames = ODPDocumentWriter.notesFrames(slideSize: presentation.slideSize)
        xml.raw("<presentation:notes><draw:page-thumbnail draw:layer=\"layout\" \(ODPDocumentWriter.position(frames.thumbnail))")
        xml.raw(" draw:page-number=\"\(page.slideNumber ?? 1)\" presentation:class=\"page\"/>")
        guard !slide.notes.isEmpty else {
            xml.raw("</presentation:notes>")
            return
        }
        // Notes inherit nothing in the model: they're written against the theme's style for other text.
        let element = SlideElement(placement: nil, content: .shape(Shape(text: slide.notes)))
        let style = ElementStyle(element: element, parents: [], theme: page.theme, defaultTextStyle: presentation.defaultTextStyle)
        let own = ODFStyle(family: "presentation", parent: page.masterName + "-notes")
        let name = page.styles.name(own, kind: "pr")
        xml.raw("<draw:frame")
        xml.attribute("presentation:style-name", name)
        xml.raw(" draw:layer=\"layout\" \(ODPDocumentWriter.position(frames.notes)) presentation:class=\"notes\" presentation:user-transformed=\"true\">")
        xml.raw("<draw:text-box>")
        paragraphs(slide.notes, style: style, baseline: ODFFrameBaseline(sheet: document.sheet, own: own, outlineMaster: nil), page: page,
                   paragraphIDs: [], into: &xml)
        xml.raw("</draw:text-box></draw:frame></presentation:notes>")
    }

    // MARK: Master pages

    /// A master page's shapes: the theme's decorations (and a layout's own), then its placeholders.
    func masterPage(_ master: ODPMaster, theme: Theme) -> String {
        var xml = XMLWriter(fragmentCapacity: 16 * 1024)
        let presentation = self.presentation
        var page = Page(masterName: master.name, themeIndex: master.themeIndex, theme: theme, styles: document.masterStyles,
                        layer: "backgroundobjects", isMaster: true, slideNumber: nil, style: { presentation.style(forThemeElement: $0, theme: theme) })
        guard let layout = master.layout else {
            for element in theme.elements { self.element(element, page: page, into: &xml) }
            return String(decoding: xml.bytes, as: UTF8.self)
        }
        if layout.showsThemeElements {
            for element in theme.elements where element.placeholder == nil { self.element(element, page: page, into: &xml) }
        }
        page.style = { presentation.style(for: $0, inLayout: layout, theme: theme) }
        for element in layout.elements where element.placeholder == nil { self.element(element, page: page, into: &xml) }
        // The placeholders LibreOffice's layouts place slides' text by: a title, an outline area and the slide number.
        let placeholders = layout.elements.filter { $0.placeholder != nil }
        var written = Set<String>()
        for element in placeholders {
            guard let type = element.placeholder?.type else { continue }
            let kind = ODPDocumentWriter.presentationClass(type)
            let masterKind = kind == "subtitle" ? "outline" : kind
            guard ["title", "outline", "page-number", "date-time", "footer", "header"].contains(masterKind), written.insert(masterKind).inserted else { continue }
            // A master has an outline area, not a subtitle: a layout's subtitle is where its outline goes.
            var placeholder = element
            if type == .subtitle { placeholder.placeholder?.type = .body }
            self.element(placeholder, page: page, into: &xml)
        }
        return String(decoding: xml.bytes, as: UTF8.self)
    }

    // MARK: Elements

    private func isWritable(_ element: SlideElement) -> Bool {
        switch element.content {
        case .shape: true
        case .picture(let picture): presentation.media[picture.mediaID].map { !$0.data.isEmpty } ?? false
        case .group(let children): children.contains(where: isWritable)
        case .table(let table): !table.rowHeights.isEmpty && !table.columnWidths.isEmpty
        case .chart: true
        case .media(let clip): presentation.media[clip.mediaID].map { !$0.data.isEmpty } ?? false
        }
    }

    func element(_ element: SlideElement, page: Page, into xml: inout XMLWriter, depth: Int = 0) {
        guard isWritable(element), depth < 32 else { return }
        switch element.content {
        case .group(let children):
            xml.raw("<draw:g")
            if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
            identity(element, page: page, into: &xml)
            xml.raw(">")
            altText(element, into: &xml)
            for child in children { self.element(child, page: page, into: &xml, depth: depth + 1) }
            xml.raw("</draw:g>")
        case .picture(let picture):
            self.picture(element, picture, page: page, into: &xml)
        case .shape(let shape):
            if element.placeholder == nil, shape.geometry.isLine, !shape.isWordArt {
                line(element, shape, page: page, into: &xml)
            } else {
                self.shape(element, shape, page: page, into: &xml)
            }
        case .table(let table):
            self.table(element, table, page: page, into: &xml)
        case .chart(let chart):
            self.chart(element, chart, page: page, into: &xml)
        case .media(let clip):
            self.clip(element, clip, page: page, into: &xml)
        }
    }

    /// `xml:id` and `draw:id` for animation targets.
    func identity(_ element: SlideElement, page: Page, into xml: inout XMLWriter) {
        guard let id = page.targets[element.id]?.shape else { return }
        xml.raw(" xml:id=\"\(id)\" draw:id=\"\(id)\"")
    }

    func altText(_ element: SlideElement, into xml: inout XMLWriter) {
        if let title = element.altTitle, !title.isEmpty {
            xml.raw("<svg:title>")
            xml.text(title)
            xml.raw("</svg:title>")
        }
        if let description = element.altDescription, !description.isEmpty {
            xml.raw("<svg:desc>")
            xml.text(description)
            xml.raw("</svg:desc>")
        }
    }

    /// Size and position: `svg:x`/`svg:y`, or a `draw:transform` turning the shape about its corner when rotated.
    static func geometry(_ placement: Placement, into xml: inout XMLWriter) {
        let frame = placement.frame.standardized
        xml.raw(" svg:width=\"\(ODFFormat.pt(frame.width))\" svg:height=\"\(ODFFormat.pt(frame.height))\"")
        let rotation = Placement.normalized(placement.rotation)
        guard rotation != 0 else {
            xml.raw(" svg:x=\"\(ODFFormat.pt(frame.x))\" svg:y=\"\(ODFFormat.pt(frame.y))\"")
            return
        }
        // ODF turns counterclockwise about the shape's own corner, then moves that corner into place.
        let radians = rotation * .pi / 180
        let corner = CGPoint(x: -frame.width / 2, y: -frame.height / 2)
        let x = frame.midX + corner.x * cos(radians) - corner.y * sin(radians)
        let y = frame.midY + corner.x * sin(radians) + corner.y * cos(radians)
        let angle = ODFFormat.number(Placement.normalized(360 - rotation) * .pi / 180, decimals: 9)
        xml.raw(" draw:transform=\"rotate (\(angle)) translate (\(ODFFormat.pt(x)) \(ODFFormat.pt(y)))\"")
    }

    /// A placeholder's inherited formatting at its first level, as ODF values: margins relative to the list level when it has
    /// a bullet. Alignment, spacing and character properties; margins only without a bullet.
    static func layoutLevel(_ style: ElementStyle) -> (text: ODFTextValues, paragraph: ODFParagraphValues) {
        let level = style.inheritedLevelStyle(0)
        let paragraph = level.paragraph
        var values = ODFParagraphValues(alignment: paragraph.alignment ?? .left, lineSpacing: paragraph.lineSpacing ?? 1,
                                        spaceBefore: paragraph.spaceBefore ?? 0, spaceAfter: paragraph.spaceAfter ?? 0,
                                        marginLeft: paragraph.marginLeft ?? 0, indent: paragraph.indent ?? 0)
        if (paragraph.bullet ?? Bullet.none) != Bullet.none {
            let margins = ODFListLevel.paragraphMargins(left: values.marginLeft, indent: values.indent)
            values.marginLeft = margins.margin
            values.indent = margins.textIndent
        }
        return (ODFTextValues(style.resolve(level.character)), values)
    }

    /// The model's frame with sizes made positive, as files store them: a negative size is the same frame, flipped.
    static func standardized(_ placement: Placement) -> Placement {
        var result = placement
        if placement.frame.width < 0 { result.flipHorizontal.toggle() }
        if placement.frame.height < 0 { result.flipVertical.toggle() }
        result.frame = placement.frame.standardized
        return result
    }

    private func shape(_ element: SlideElement, _ shape: Shape, page: Page, into xml: inout XMLWriter) {
        let style = page.style(element)
        let placement = Self.standardized(style.placement)
        let flipped = placement.flipHorizontal || placement.flipVertical
        let isRect = shape.geometry == .rectangle || shape.geometry.presetName == "rect"
        let className = element.placeholder.map { ODPDocumentWriter.presentationClass($0.type) }
        // Frames can't be flipped or take other outlines; such placeholders and text boxes are custom shapes, as is word art.
        let asFrame = isRect && !flipped && (element.placeholder != nil || shape.isTextBox) && !shape.isWordArt
        let textStyle = Self.unscaled(style)

        var own: ODFStyle
        var outlineMaster: String?
        if let ref = element.placeholder {
            own = ODFStyle(family: "presentation", parent: page.masterName + "-" + ODPDocumentWriter.classStyleSuffix(ref.type))
            if className == "outline" { outlineMaster = page.masterName }
            let classBaseline = ODFFrameBaseline(sheet: document.sheet, own: own, outlineMaster: outlineMaster)
            own.graphic = Self.difference(document.frameProperties(style), from: classBaseline.style(level: 0).graphic)
            if !page.isMaster {
                // What the placeholder inherits from its layout is the frame's own text formatting, as ODF applies a
                // frame's text properties to all its paragraphs; readers take it back to the layout.
                let inherited = Self.layoutLevel(textStyle)
                let base = classBaseline.values(level: 0)
                own.text = inherited.text.difference(from: base.text)
                own.paragraph = inherited.paragraph.difference(from: base.paragraph)
                document.use(own.text)
            }
        } else {
            own = ODFStyle(family: "graphic", parent: document.themeMasterName(page.themeIndex) + "-other")
            var graphic = Self.difference(Self.bodyProperties(style.bodyProperties), from: document.sheet.resolved("graphic", own.parent).graphic)
            let fill = document.fillProperties(shape.fill ?? Fill.none, colors: page.theme.colors)
            let stroke = document.strokeProperties(shape.outline ?? Outline.none, colors: page.theme.colors)
            graphic = fill.merged(over: stroke).merged(over: graphic)
            own.graphic = graphic
        }
        let styleName = page.styles.name(own, kind: own.family == "presentation" ? "pr" : "gr")
        let baseline = ODFFrameBaseline(sheet: document.sheet, own: own, outlineMaster: outlineMaster)
        let body = shape.text ?? (element.placeholder != nil ? TextBody() : nil)

        if asFrame {
            xml.raw("<draw:frame")
            if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
            xml.attribute(own.family == "presentation" ? "presentation:style-name" : "draw:style-name", styleName)
            xml.raw(" draw:layer=\"\(page.layer)\"")
            identity(element, page: page, into: &xml)
            Self.geometry(placement, into: &xml)
            if let className {
                xml.raw(" presentation:class=\"\(className)\"")
                if body?.isEmpty ?? true { xml.raw(" presentation:placeholder=\"true\"") }
                if !page.isMaster { xml.raw(" presentation:user-transformed=\"true\"") }
            }
            xml.raw("><draw:text-box>")
            // An empty placeholder keeps its paragraph, which carries the formatting typing will get.
            if let body, !Self.isBlank(body) || element.placeholder != nil {
                paragraphs(body, style: textStyle, baseline: baseline, page: page, paragraphIDs: page.targets[element.id]?.paragraphs ?? [], into: &xml)
            }
            xml.raw("</draw:text-box>")
            altText(element, into: &xml)
            xml.raw("</draw:frame>")
            return
        }

        xml.raw("<draw:custom-shape")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute(own.family == "presentation" ? "presentation:style-name" : "draw:style-name", styleName)
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        Self.geometry(placement, into: &xml)
        xml.raw(">")
        altText(element, into: &xml)
        if let body, !Self.isBlank(body) || element.placeholder != nil {
            paragraphs(body, style: textStyle, baseline: baseline, page: page, paragraphIDs: page.targets[element.id]?.paragraphs ?? [], into: &xml)
        }
        if shape.isWordArt {
            fontworkGeometry(placement: placement, into: &xml)
        } else {
            enhancedGeometry(shape.geometry, placement: placement, into: &xml)
        }
        xml.raw("</draw:custom-shape>")
    }

    /// Word art as LibreOffice's Fontwork: plain text stretched over the whole shape (`fontwork-plain-text`, with the text
    /// following the shape's top and bottom edges and scaled to it), its letters painted with the shape's fill and line.
    /// The path and equations are LibreOffice's own for the shape.
    private func fontworkGeometry(placement: Placement, into xml: inout XMLWriter) {
        xml.raw("<draw:enhanced-geometry svg:viewBox=\"0 0 21600 21600\" draw:text-areas=\"0 0 21600 21600\" draw:text-path=\"true\"")
        xml.raw(" draw:text-path-mode=\"shape\" draw:text-path-scale=\"shape\" draw:text-path-same-letter-heights=\"false\"")
        xml.raw(" draw:type=\"fontwork-plain-text\" draw:modifiers=\"10800\"")
        if placement.flipHorizontal { xml.raw(" draw:mirror-horizontal=\"true\"") }
        if placement.flipVertical { xml.raw(" draw:mirror-vertical=\"true\"") }
        xml.raw(" draw:enhanced-path=\"M ?f3 0 L ?f5 0 N M ?f6 21600 L ?f7 21600 N\">")
        let formulas = ["$0 -10800", "?f0 *2", "abs(?f1 )", "if(?f1 ,0,?f2 )", "21600-?f2 ", "if(?f1 ,?f4 ,21600)", "if(?f1 ,?f2 ,0)", "if(?f1 ,21600,?f4 )"]
        for (index, formula) in formulas.enumerated() {
            xml.raw("<draw:equation draw:name=\"f\(index)\"")
            xml.attribute("draw:formula", formula)
            xml.raw("/>")
        }
        xml.raw("<draw:handle draw:handle-position=\"$0 21600\" draw:handle-range-x-minimum=\"6629\" draw:handle-range-x-maximum=\"14971\"/>")
        xml.raw("</draw:enhanced-geometry>")
    }

    private func enhancedGeometry(_ geometry: ShapeGeometry, placement: Placement, into xml: inout XMLWriter) {
        let path = ODPGeometry.enhancedPath(geometry, size: placement.frame.size)
        xml.raw("<draw:enhanced-geometry svg:viewBox=\"0 0 \(path.viewBox.width) \(path.viewBox.height)\"")
        switch geometry {
        case .preset(let name, let adjustments):
            let type = ODPGeometry.shapeType(name, adjustments: adjustments)
            xml.attribute("draw:type", type.type)
            if let modifiers = type.modifiers { xml.attribute("draw:modifiers", modifiers) }
        case .custom:
            xml.raw(" draw:type=\"non-primitive\"")
        }
        if placement.flipHorizontal { xml.raw(" draw:mirror-horizontal=\"true\"") }
        if placement.flipVertical { xml.raw(" draw:mirror-vertical=\"true\"") }
        xml.attribute("draw:text-areas", path.textArea)
        xml.attribute("draw:enhanced-path", path.path)
        xml.raw("/>")
    }

    /// Lines and connectors: their ends are where the frame's corners land after flips and rotation.
    private func line(_ element: SlideElement, _ shape: Shape, page: Page, into xml: inout XMLWriter) {
        let style = page.style(element)
        let placement = style.placement
        let start = placement.slidePoint(fromShape: SlidePoint(x: 0, y: 0))
        let end = placement.slidePoint(fromShape: SlidePoint(x: placement.frame.width, y: placement.frame.height))
        var own = ODFStyle(family: "graphic", parent: document.themeMasterName(page.themeIndex) + "-other")
        own.graphic = document.strokeProperties(shape.outline ?? Outline.none, colors: page.theme.colors)
        own.graphic.fill = "none"
        let styleName = page.styles.name(own, kind: "gr")
        let name = shape.geometry.presetName ?? "line"
        let connectorType: String? = name.hasPrefix("bentConnector") ? "standard" : name.hasPrefix("curvedConnector") ? "curve"
            : shape.isConnector ? "line" : nil
        let tag = connectorType == nil ? "draw:line" : "draw:connector"
        xml.raw("<\(tag)")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute("draw:style-name", styleName)
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        if let connectorType {
            // Connectors must state a view box; with no path of their own, it's just their extent.
            let box = ODPGeometry.viewBoxSize(SlideSize(width: end.x - start.x, height: end.y - start.y))
            xml.raw(" draw:type=\"\(connectorType)\" svg:viewBox=\"0 0 \(box.width) \(box.height)\"")
        }
        xml.raw(" svg:x1=\"\(ODFFormat.pt(start.x))\" svg:y1=\"\(ODFFormat.pt(start.y))\" svg:x2=\"\(ODFFormat.pt(end.x))\" svg:y2=\"\(ODFFormat.pt(end.y))\">")
        altText(element, into: &xml)
        if let body = shape.text, !Self.isBlank(body) {
            let baseline = ODFFrameBaseline(sheet: document.sheet, own: own, outlineMaster: nil)
            paragraphs(body, style: Self.unscaled(style), baseline: baseline, page: page, paragraphIDs: page.targets[element.id]?.paragraphs ?? [], into: &xml)
        }
        xml.raw("</\(tag)>")
    }

    /// Pictures are framed images, cropped with `fo:clip`. A picture masked to another shape is that shape filled
    /// with the image, as LibreOffice does; such a fill can't be cropped.
    private func picture(_ element: SlideElement, _ picture: Picture, page: Page, into xml: inout XMLWriter) {
        guard let path = document.mediaPath(picture.mediaID), let item = presentation.media[picture.mediaID] else { return }
        let style = page.style(element)
        let placement = Self.standardized(style.placement)
        let isRect = picture.geometry == .rectangle || picture.geometry.presetName == "rect"
        let stroke = document.strokeProperties(picture.outline ?? Outline.none, colors: page.theme.colors)
        let parent = element.placeholder.map { page.masterName + "-" + ODPDocumentWriter.classStyleSuffix($0.type) }
            ?? document.themeMasterName(page.themeIndex) + "-other"
        var own = ODFStyle(family: element.placeholder == nil ? "graphic" : "presentation", parent: parent)

        guard isRect || element.placeholder != nil else {
            own.graphic = ODFGraphicProperties()
            own.graphic.fill = "bitmap"
            own.graphic.imageName = document.fillImageName(picture.mediaID)
            own.graphic.repeatMode = "stretch"
            // A fill takes the picture's transparency; its other adjustments only apply to pictures in frames.
            let transparency = picture.adjustments.transparency
            if transparency.isFinite, transparency > 0.0001 { own.graphic.opacity = min(max(1 - transparency, 0), 1) }
            own.graphic = own.graphic.merged(over: stroke)
            let styleName = page.styles.name(own, kind: "gr")
            xml.raw("<draw:custom-shape")
            if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
            xml.attribute("draw:style-name", styleName)
            xml.raw(" draw:layer=\"\(page.layer)\"")
            identity(element, page: page, into: &xml)
            Self.geometry(placement, into: &xml)
            xml.raw(">")
            altText(element, into: &xml)
            enhancedGeometry(picture.geometry, placement: placement, into: &xml)
            xml.raw("</draw:custom-shape>")
            return
        }

        var graphic = stroke
        graphic.fill = "none"
        if !picture.crop.isNone {
            let natural = Self.naturalSize(of: item.data, frame: placement.frame.size, crop: picture.crop)
            graphic.clip = ODFClip(top: picture.crop.top * natural.height, right: picture.crop.right * natural.width,
                                   bottom: picture.crop.bottom * natural.height, left: picture.crop.left * natural.width)
        }
        if placement.flipHorizontal { graphic.mirrorHorizontal = true }
        if placement.flipVertical { graphic.mirrorVertical = true }
        Self.apply(picture.adjustments, to: &graphic)
        own.graphic = graphic
        let styleName = page.styles.name(own, kind: own.family == "presentation" ? "pr" : "gr")
        var unflipped = placement
        unflipped.flipHorizontal = false
        unflipped.flipVertical = false
        xml.raw("<draw:frame")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute(own.family == "presentation" ? "presentation:style-name" : "draw:style-name", styleName)
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        Self.geometry(unflipped, into: &xml)
        if let ref = element.placeholder {
            xml.raw(" presentation:class=\"\(ODPDocumentWriter.presentationClass(ref.type))\"")
            if !page.isMaster { xml.raw(" presentation:user-transformed=\"true\"") }
        }
        xml.raw("><draw:image")
        xml.attribute("xlink:href", path)
        xml.raw(" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"")
        xml.attribute("draw:mime-type", ODPDocumentWriter.mediaType(item.contentType, path: path))
        xml.raw("/>")
        altText(element, into: &xml)
        xml.raw("</draw:frame>")
    }

    /// A picture's adjustments as ODF's image properties: transparency as `draw:image-opacity`, brightness and contrast as
    /// `draw:luminance` and `draw:contrast`. ODF's only recolors are grayscale and inverted colors, so negative is a
    /// grayscale inverted, and the light, dark, sepia and duotone recolors, which tint the image, are grayscale.
    static func apply(_ adjustments: ImageAdjustments, to graphic: inout ODFGraphicProperties) {
        func significant(_ value: Double) -> Bool { value.isFinite && abs(value) > 0.0001 }
        if significant(adjustments.transparency) { graphic.imageOpacity = min(max(1 - adjustments.transparency, 0), 1) }
        if significant(adjustments.brightness) { graphic.luminance = min(max(adjustments.brightness, -1), 1) }
        if significant(adjustments.contrast) { graphic.contrast = min(max(adjustments.contrast, -1), 1) }
        switch adjustments.recolor {
        case nil:
            break
        case .negative?:
            graphic.colorMode = "greyscale"
            graphic.colorInversion = true
        case .grayscale?, .light?, .dark?, .sepia?, .duotone?:
            graphic.colorMode = "greyscale"
        }
    }

    /// The image's own size, which crops are measured against; without one, the size that shows the cropped part at
    /// the frame's size.
    static func naturalSize(of data: Data, frame: SlideSize, crop: ImageCrop) -> CGSize {
        if let size = ODPImageSize.points(of: data) { return size }
        let width = 1 - crop.left - crop.right, height = 1 - crop.top - crop.bottom
        return CGSize(width: width > 0.001 ? abs(frame.width) / width : abs(frame.width), height: height > 0.001 ? abs(frame.height) / height : abs(frame.height))
    }

    // MARK: Properties

    /// The text frame properties for how text sits in a shape.
    static func bodyProperties(_ properties: ResolvedBodyProperties) -> ODFGraphicProperties {
        var result = ODFGraphicProperties()
        result.anchor = properties.anchor
        result.paddingLeft = properties.insets.left
        result.paddingTop = properties.insets.top
        result.paddingRight = properties.insets.right
        result.paddingBottom = properties.insets.bottom
        result.autoGrowHeight = properties.autofit == .resizeShape
        result.shrinkToFit = properties.autofit == .shrinkOnOverflow
        result.fitToSize = false
        result.wraps = properties.wraps
        return result
    }

    /// The properties of `target` that `base` doesn't already give.
    static func difference(_ target: ODFGraphicProperties, from base: ODFGraphicProperties) -> ODFGraphicProperties {
        var result = ODFGraphicProperties()
        func check<T: Equatable>(_ path: WritableKeyPath<ODFGraphicProperties, T?>) {
            if let value = target[keyPath: path], value != base[keyPath: path] { result[keyPath: path] = value }
        }
        func checkLength(_ path: WritableKeyPath<ODFGraphicProperties, Double?>) {
            if let value = target[keyPath: path], !(base[keyPath: path].map { ODFCompare.same($0, value) } ?? false) { result[keyPath: path] = value }
        }
        check(\.fill)
        check(\.fillColor)
        check(\.gradientName)
        check(\.imageName)
        check(\.repeatMode)
        checkLength(\.opacity)
        check(\.stroke)
        check(\.strokeColor)
        checkLength(\.strokeWidth)
        checkLength(\.strokeOpacity)
        check(\.dashName)
        check(\.markerStart)
        check(\.markerEnd)
        checkLength(\.markerStartWidth)
        checkLength(\.markerEndWidth)
        check(\.markerStartCenter)
        check(\.markerEndCenter)
        check(\.anchor)
        checkLength(\.paddingLeft)
        checkLength(\.paddingTop)
        checkLength(\.paddingRight)
        checkLength(\.paddingBottom)
        check(\.autoGrowHeight)
        check(\.shrinkToFit)
        check(\.fitToSize)
        check(\.wraps)
        checkLength(\.imageOpacity)
        checkLength(\.luminance)
        checkLength(\.contrast)
        check(\.colorMode)
        check(\.colorInversion)
        // Fill and opacity go together: a solid fill keeps its opacity statement.
        if result.fill != nil || result.fillColor != nil, target.opacity == nil, base.opacity != nil { result.opacity = 1 }
        if result.stroke != nil || result.strokeColor != nil, target.strokeOpacity == nil, base.strokeOpacity != nil { result.strokeOpacity = 1 }
        return result
    }

    /// The element's formatting without the font scale and spacing reduction that shrink-on-overflow applies when drawn.
    static func unscaled(_ style: ElementStyle) -> ElementStyle {
        func strip(_ element: SlideElement) -> SlideElement {
            guard var text = element.shape?.text, text.properties.fontScale != nil || text.properties.lineSpacingReduction != nil else { return element }
            var copy = element
            text.properties.fontScale = nil
            text.properties.lineSpacingReduction = nil
            copy.shape?.text = text
            return copy
        }
        return ElementStyle(element: strip(style.element), parents: style.parents.map(strip), theme: style.theme,
                            defaultTextStyle: style.defaultTextStyle)
    }

    /// A body with nothing to write: one empty paragraph with no formatting of its own.
    static func isBlank(_ body: TextBody) -> Bool {
        body.paragraphs.count == 1 && body.paragraphs[0].runs.isEmpty && body.paragraphs[0].style.isEmpty
            && body.paragraphs[0].endStyle.isEmpty && body.paragraphs[0].level == 0
    }

    // MARK: Text

    /// Paragraphs, each stating only what differs from what the frame gives it: paragraph properties and the
    /// paragraph mark's character properties on the paragraph, each run's own on its span. Lists give bullets and levels.
    func paragraphs(_ body: TextBody, style: ElementStyle, baseline: ODFFrameBaseline, page: Page, paragraphIDs: [String],
                             into xml: inout XMLWriter) {
        let resolved = style.resolvedParagraphs(body, slideNumber: page.slideNumber)
        var counters: [Int: (scheme: AutoNumberScheme, next: Int)] = [:]
        var targetIndex = 0
        for (index, paragraph) in body.paragraphs.enumerated() where index < resolved.count {
            let model = resolved[index]
            let level = paragraph.level
            let base = baseline.values(level: level)
            let levelStyle = body.listStyle[level].merged(over: style.inheritedLevelStyle(level))
            let paragraphStyle = paragraph.style.merged(over: levelStyle.paragraph)
            let bullet = ODFBulletValues(bullet: paragraphStyle.bullet ?? Bullet.none, font: paragraphStyle.bulletFont.map(style.theme.fonts.resolve),
                                         color: paragraphStyle.bulletColor.map { style.resolve($0).rgb }, size: paragraphStyle.bulletSize)
            var number: Int?
            switch bullet.bullet {
            case .none, .character:
                counters = counters.filter { $0.key < level }
            case .number(let scheme, let start):
                counters = counters.filter { $0.key <= level }
                var value = start
                if let counter = counters[level], counter.scheme == scheme { value = counter.next }
                if !paragraph.isEmpty { counters[level] = (scheme, value + 1) }
                number = value == start ? nil : value
            }

            var own = ODFStyle(family: "paragraph")
            let inList = bullet.bullet != Bullet.none || level > 0 || base.bullet.bullet != Bullet.none
            // In a list, the list level holds the indentation and the paragraph what's left of it.
            let margins = inList ? ODFListLevel.paragraphMargins(left: model.marginLeft, indent: model.indent) : (model.marginLeft, model.indent)
            let paragraphValues = ODFParagraphValues(alignment: model.alignment, lineSpacing: model.lineSpacing, spaceBefore: model.spaceBefore,
                                                     spaceAfter: model.spaceAfter, marginLeft: margins.0, indent: margins.1)
            own.paragraph = paragraphValues.difference(from: base.paragraph)
            own.text = ODFTextValues(model.endStyle).difference(from: base.text)
            document.use(own.text)
            let paragraphStyleName = own.paragraph.isEmpty && own.text.isEmpty ? nil : page.styles.name(own, kind: "P")
            let markText = base.text.applying(own.text)

            if inList {
                let listLevel = bullet.level(margins: (model.marginLeft, model.indent))
                document.use(listLevel.text)
                let listName = page.styles.listStyle([level: listLevel])
                xml.raw("<text:list text:style-name=\"\(listName)\">")
                for _ in 0..<level { xml.raw("<text:list-item><text:list>") }
                if bullet.bullet == Bullet.none {
                    xml.raw("<text:list-header>")
                } else if let number {
                    xml.raw("<text:list-item text:start-value=\"\(min(max(number, 0), 1_000_000))\">")
                } else {
                    xml.raw("<text:list-item>")
                }
            }
            xml.raw("<text:p")
            if let paragraphStyleName { xml.attribute("text:style-name", paragraphStyleName) }
            if !paragraph.isEmpty, targetIndex < paragraphIDs.count {
                xml.raw(" xml:id=\"\(paragraphIDs[targetIndex])\" text:id=\"\(paragraphIDs[targetIndex])\"")
                targetIndex += 1
            }
            xml.raw(">")
            runs(model.runs, base: markText, page: page, into: &xml)
            xml.raw("</text:p>")
            if inList {
                xml.raw(bullet.bullet == Bullet.none ? "</text:list-header>" : "</text:list-item>")
                for _ in 0..<level { xml.raw("</text:list></text:list-item>") }
                xml.raw("</text:list>")
            }
        }
    }

    private func runs(_ runs: [ResolvedRun], base: ODFTextValues, page: Page, into xml: inout XMLWriter) {
        var spaceIsCollapsible = false
        var index = 0
        while index < runs.count {
            let link = runs[index].style.link
            var end = index + 1
            while end < runs.count, runs[end].style.link == link { end += 1 }
            let href = link.flatMap { linkTarget($0) }
            if let href {
                xml.raw("<text:a xlink:type=\"simple\"")
                xml.attribute("xlink:href", href)
                xml.raw(">")
            }
            for run in runs[index..<end] {
                let own = ODFTextValues(run.style).difference(from: base)
                document.use(own)
                if !own.isEmpty {
                    var style = ODFStyle(family: "text")
                    style.text = own
                    xml.raw("<text:span text:style-name=\"\(page.styles.name(style, kind: "T"))\">")
                }
                content(run, page: page, collapsible: &spaceIsCollapsible, into: &xml)
                if !own.isEmpty { xml.raw("</text:span>") }
            }
            if href != nil { xml.raw("</text:a>") }
            index = end
        }
    }

    private func linkTarget(_ link: Hyperlink) -> String? {
        switch link {
        case .url(let address):
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Self.iri(trimmed)
        case .slide(let id):
            return document.pageNames[id].map { "#" + $0 }
        }
    }

    /// An address as an IRI: spaces, quotes and other characters an IRI can't hold are percent-encoded.
    static func iri(_ address: String) -> String {
        var result = ""
        for scalar in address.unicodeScalars {
            let value = scalar.value
            if value <= 0x20 || value == 0x7F || "\"<>\\^`{|}".unicodeScalars.contains(scalar) {
                for byte in String(scalar).utf8 { result += String(format: "%%%02X", byte) }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// A run's characters with ODF's white-space rules: a space that would collapse into the one before it, or that
    /// starts the paragraph, is `text:s`; tabs and line breaks are elements. Fields are field elements.
    private func content(_ run: ResolvedRun, page: Page, collapsible: inout Bool, into xml: inout XMLWriter) {
        if let field = run.field {
            switch field {
            case .slideNumber:
                xml.raw("<text:page-number text:select-page=\"current\">")
                xml.text(page.slideNumber.map(String.init) ?? run.text)
                xml.raw("</text:page-number>")
                collapsible = true
                return
            case .dateTime(let type):
                let style = document.dateStyleName(type)
                let tag = style.isTime ? "text:time" : "text:date"
                xml.raw("<\(tag)")
                xml.attribute("style:data-style-name", style.name)
                xml.raw(">")
                xml.text(run.text.replacingOccurrences(of: TextRun.lineBreak, with: " "))
                xml.raw("</\(tag)>")
                collapsible = true
                return
            case .other:
                break
            }
        }
        var pending = ""
        var spaces = 0
        func flushText() {
            if !pending.isEmpty {
                xml.text(pending)
                pending = ""
            }
        }
        func flushSpaces() {
            guard spaces > 0 else { return }
            flushText()
            xml.raw(spaces == 1 ? "<text:s/>" : "<text:s text:c=\"\(spaces)\"/>")
            spaces = 0
        }
        var afterReturn = false
        for scalar in run.text.unicodeScalars {
            defer { afterReturn = scalar == "\r" }
            if scalar == "\n", afterReturn { continue }
            switch scalar {
            case " ":
                if collapsible {
                    pending.unicodeScalars.append(scalar)
                    collapsible = false
                } else {
                    spaces += 1
                }
            case "\t":
                flushSpaces()
                flushText()
                xml.raw("<text:tab/>")
                collapsible = false
            case "\u{2028}", "\n", "\r", "\u{0B}":
                flushSpaces()
                flushText()
                xml.raw("<text:line-break/>")
                collapsible = false
            default:
                flushSpaces()
                pending.unicodeScalars.append(scalar)
                collapsible = true
            }
        }
        flushSpaces()
        flushText()
    }
}
