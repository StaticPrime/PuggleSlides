import Foundation

/// Writes OpenDocument presentations (.odp), as LibreOffice Impress lays them out.
///
/// Each theme is a master page whose presentation styles ("<Master>-title", "-outline1" … "-outline9", "-subtitle",
/// "-notes", "-background", "-backgroundobjects") hold the theme's text styles, so placeholders inherit through ODF's
/// own mechanism. A layout with decorations, a background or hidden theme decorations gets a master page of its own
/// ("<Theme>: <Layout>"), so LibreOffice shows its slides as PuggleSlides does. Every layout is also a presentation page
/// layout ("<Theme>: <Layout>") recording its placeholders, which slides name. Slides state their placeholders' positions
/// and whatever formatting differs from what their master gives; theme colors and fonts are written resolved.
///
/// Tables are `table:table`s in frames with a style per column, row and cell; charts are embedded chart objects
/// ("Object 1/" …) keeping their numbers in their own tables; word art is Fontwork; picture adjustments are image
/// properties; guides are the view's snap lines in settings.xml. Every part keeps to the ODF 1.3 schema.
enum ODPWriter {
    static func write(_ presentation: Presentation) throws -> Data {
        try write(presentation, date: Date())
    }

    static func write(_ presentation: Presentation, date: Date) throws -> Data {
        do {
            let writer = ODPDocumentWriter(presentation: normalized(presentation), date: date)
            return try writer.write()
        } catch let error as PresentationIOError {
            throw error
        } catch {
            throw PresentationIOError.unwritable(ODPMessages.tooLargeToSave)
        }
    }

    /// Every presentation needs a master with at least one layout, and every slide a layout.
    static func normalized(_ presentation: Presentation) -> Presentation {
        var result = presentation
        if result.themes.isEmpty { result.themes = [BuiltInThemes.simpleLight(slideSize: presentation.slideSize)] }
        for index in result.themes.indices where result.themes[index].layouts.isEmpty {
            result.themes[index].layouts = [Layout(name: LayoutKind.blank.title, kind: .blank)]
        }
        let firstLayout = result.themes[0].layouts[0].id
        for index in result.slides.indices where result.layoutLocation(result.slides[index].layoutID) == nil {
            result.slides[index].layoutID = firstLayout
        }
        let size = result.slideSize
        if !(size.width >= 1 && size.width <= 10_000 && size.height >= 1 && size.height <= 10_000) { result.slideSize = .widescreen }
        return result
    }
}

/// Automatic styles of one part, named as LibreOffice names them ("gr1", "P1", "T1" …) and shared by identical uses.
final class ODFAutomaticStyles {
    let prefix: String
    private var names: [String: String] = [:]
    private var counters: [String: Int] = [:]
    private(set) var xml = XMLWriter(fragmentCapacity: 64 * 1024)

    init(prefix: String) {
        self.prefix = prefix
    }

    /// The name of an automatic style with these properties, written the first time it's needed.
    func name(_ style: ODFStyle, kind: String) -> String {
        var body = XMLWriter(fragmentCapacity: 256)
        style.writeBody(name: "", to: &body)
        let key = style.family + "\u{1}" + (style.parent ?? "") + "\u{1}" + String(decoding: body.bytes, as: UTF8.self)
        if let known = names[key] { return known }
        let count = (counters[kind] ?? 0) + 1
        counters[kind] = count
        let name = prefix + kind + String(count)
        names[key] = name
        xml.raw("<style:style style:name=\"\(name)\" style:family=\"\(style.family)\"")
        if let parent = style.parent { xml.attribute("style:parent-style-name", parent) }
        xml.raw(">")
        style.writeBody(name: name, to: &xml)
        xml.raw("</style:style>")
        return name
    }

    func listStyle(_ levels: ODFListStyle) -> String {
        var body = XMLWriter(fragmentCapacity: 256)
        for level in levels.keys.sorted() { levels[level]?.write(level: level, to: &body) }
        let content = String(decoding: body.bytes, as: UTF8.self)
        let key = "list\u{1}" + content
        if let known = names[key] { return known }
        let count = (counters["L"] ?? 0) + 1
        counters["L"] = count
        let name = prefix + "L" + String(count)
        names[key] = name
        xml.raw("<text:list-style style:name=\"\(name)\">")
        xml.raw(content)
        xml.raw("</text:list-style>")
        return name
    }
}

/// One master page being written: a theme's, or a layout's own.
struct ODPMaster {
    var name: String
    var displayName: String
    var themeIndex: Int
    var layout: Layout?
}

/// What writing one presentation shares across its parts.
final class ODPDocumentWriter {
    let presentation: Presentation
    let date: Date
    /// Common styles and masters' styles, to work out what each frame inherits.
    let sheet = ODFStyleSheet()
    let masterStyles = ODFAutomaticStyles(prefix: "M")
    let contentStyles = ODFAutomaticStyles(prefix: "")

    private(set) var masters: [ODPMaster] = []
    /// Each theme's master, by theme index.
    private(set) var themeMasters: [Int: String] = [:]
    /// Each layout's own master and presentation page layout, by layout id.
    /// Keyed by theme index and layout id, since a theme can appear twice with the same layouts.
    private var layoutMasters: [String: String] = [:]
    private var pageLayoutNames: [String: String] = [:]

    private static func key(_ themeIndex: Int, _ layoutID: UUID) -> String { "\(themeIndex) \(layoutID)" }
    private var pageLayoutXML = XMLWriter(fragmentCapacity: 16 * 1024)

    // Shared resources in styles.xml, written once each.
    private var gradients: [ODFGradient: String] = [:]
    private var gradientXML = XMLWriter(fragmentCapacity: 4096)
    private var images: [String: String] = [:]
    private var imageXML = XMLWriter(fragmentCapacity: 4096)
    private var markerNames: [LineEnd: String] = [:]
    private var markerXML = XMLWriter(fragmentCapacity: 4096)
    private var dashNames: [DashStyle: String] = [:]
    private var dashXML = XMLWriter(fragmentCapacity: 1024)
    private var fonts: [String] = []
    private var fontSet: Set<String> = []
    private var dateStyles: [String: String] = [:]
    private var dateStyleXML = XMLWriter(fragmentCapacity: 1024)

    // Media in Pictures/, once per item.
    private(set) var mediaPaths: [MediaID: String] = [:]
    private(set) var mediaParts: [(path: String, item: MediaItem)] = []
    private var pictureCount = 0
    private var clipCount = 0
    /// Chart objects, "Object 1" …: each a folder of parts beside the presentation's.
    private(set) var chartObjects: [(path: String, content: Data)] = []

    /// Slide page names by slide id, for links between slides.
    private(set) var pageNames: [UUID: String] = [:]

    init(presentation: Presentation, date: Date) {
        self.presentation = presentation
        self.date = date
    }

    // MARK: Package

    func write() throws -> Data {
        for (index, slide) in presentation.slides.enumerated() where pageNames[slide.id] == nil { pageNames[slide.id] = "page\(index + 1)" }
        planMasters()
        let commonStyles = buildCommonStyles()
        let masterPages = writeMasterPages()
        let body = ODPContentWriter(document: self).slides()
        let content = contentPart(body: body)
        let styles = stylesPart(common: commonStyles, masterPages: masterPages)

        var zip = ZipWriter(date: date)
        // The media type comes first and uncompressed, so tools can identify the file from its first bytes.
        try zip.add("mimetype", Data(ODPMediaType.presentation.utf8), compress: false)
        try zip.add("content.xml", content)
        try zip.add("styles.xml", styles)
        try zip.add("meta.xml", metaPart())
        let settings = ODPSettings.part(guides: presentation.guides)
        if let settings { try zip.add("settings.xml", settings) }
        let compressedFormats: Set<String> = ["png", "jpeg", "jpg", "gif", "webp"]
        for (path, item) in mediaParts {
            // Movies and sounds are stored as LibreOffice stores them, uncompressed.
            if path.hasPrefix("Media/") {
                try zip.add(path, item.data, compress: false)
                continue
            }
            let fileExtension = path.split(separator: ".").last.map(String.init) ?? ""
            try zip.add(path, item.data, compress: !compressedFormats.contains(fileExtension))
        }
        for object in chartObjects {
            try zip.add(object.path + "/content.xml", object.content)
            try zip.add(object.path + "/styles.xml", ODPChartWriter.stylesPart)
            try zip.add(object.path + "/meta.xml", ODPChartWriter.metaPart)
        }
        try zip.add("META-INF/manifest.xml", manifestPart(hasSettings: settings != nil))
        return try zip.finish()
    }

    private func contentPart(body: String) -> Data {
        var xml = XMLWriter(reservingCapacity: body.utf8.count + contentStyles.xml.bytes.count + 4096)
        xml.raw("<office:document-content\(ODFNamespace.documentRoot)>")
        writeFontDeclarations(&xml)
        xml.raw("<office:automatic-styles>")
        xml.append(contentStyles.xml)
        xml.raw("</office:automatic-styles><office:body><office:presentation>")
        xml.raw(body)
        xml.raw("</office:presentation></office:body></office:document-content>")
        return xml.data
    }

    private func stylesPart(common: XMLWriter, masterPages: XMLWriter) -> Data {
        var xml = XMLWriter(reservingCapacity: common.bytes.count + masterPages.bytes.count + masterStyles.xml.bytes.count + 8192)
        xml.raw("<office:document-styles\(ODFNamespace.documentRoot)>")
        writeFontDeclarations(&xml)
        xml.raw("<office:styles>")
        xml.append(common)
        xml.append(gradientXML)
        xml.append(imageXML)
        xml.append(markerXML)
        xml.append(dashXML)
        xml.append(pageLayoutXML)
        xml.append(dateStyleXML)
        xml.raw("</office:styles><office:automatic-styles>")
        let size = presentation.slideSize
        xml.raw("<style:page-layout style:name=\"PM1\"><style:page-layout-properties fo:margin-top=\"0pt\" fo:margin-bottom=\"0pt\"")
        xml.raw(" fo:margin-left=\"0pt\" fo:margin-right=\"0pt\" fo:page-width=\"\(ODFFormat.pt(size.width))\" fo:page-height=\"\(ODFFormat.pt(size.height))\"")
        xml.raw(" style:print-orientation=\"\(size.width >= size.height ? "landscape" : "portrait")\"/></style:page-layout>")
        xml.raw("<style:page-layout style:name=\"PM2\"><style:page-layout-properties fo:margin-top=\"0pt\" fo:margin-bottom=\"0pt\"")
        xml.raw(" fo:margin-left=\"0pt\" fo:margin-right=\"0pt\" fo:page-width=\"612pt\" fo:page-height=\"792pt\" style:print-orientation=\"portrait\"/>")
        xml.raw("</style:page-layout>")
        xml.append(masterStyles.xml)
        xml.raw("</office:automatic-styles><office:master-styles><draw:layer-set><draw:layer draw:name=\"layout\"/>")
        xml.raw("<draw:layer draw:name=\"background\"/><draw:layer draw:name=\"backgroundobjects\"/><draw:layer draw:name=\"controls\"/>")
        xml.raw("<draw:layer draw:name=\"measurelines\"/></draw:layer-set>")
        xml.append(masterPages)
        xml.raw("</office:master-styles></office:document-styles>")
        return xml.data
    }

    /// The title, and PuggleSlides as the generator: never anyone's name.
    private func metaPart() -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = String(formatter.string(from: date).dropLast())
        var xml = XMLWriter(reservingCapacity: 1024)
        xml.raw("<office:document-meta xmlns:office=\"\(ODFNamespace.office)\" xmlns:meta=\"\(ODFNamespace.meta)\" xmlns:dc=\"\(ODFNamespace.dc)\"")
        xml.raw(" office:version=\"1.3\"><office:meta><meta:generator>PuggleSlides</meta:generator>")
        if let title = presentation.title, !title.isEmpty {
            xml.raw("<dc:title>")
            xml.text(title)
            xml.raw("</dc:title>")
        }
        xml.raw("<meta:creation-date>\(stamp)</meta:creation-date><dc:date>\(stamp)</dc:date>")
        xml.raw("<meta:document-statistic meta:object-count=\"\(presentation.slides.reduce(0) { $0 + $1.elements.count })\"/>")
        xml.raw("</office:meta></office:document-meta>")
        return xml.data
    }

    private func manifestPart(hasSettings: Bool) -> Data {
        var xml = XMLWriter(reservingCapacity: 1024 + mediaParts.count * 160 + chartObjects.count * 480)
        xml.raw("<manifest:manifest xmlns:manifest=\"\(ODFNamespace.manifest)\" manifest:version=\"1.3\">")
        xml.raw("<manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"\(ODPMediaType.presentation)\"/>")
        for part in ["content.xml", "styles.xml", "meta.xml"] + (hasSettings ? ["settings.xml"] : []) {
            xml.raw("<manifest:file-entry manifest:full-path=\"\(part)\" manifest:media-type=\"text/xml\"/>")
        }
        for (path, item) in mediaParts {
            xml.raw("<manifest:file-entry")
            xml.attribute("manifest:full-path", path)
            xml.attribute("manifest:media-type", Self.mediaType(item.contentType, path: path))
            xml.raw("/>")
        }
        // A chart object is a sub-document: its folder has the chart's media type, its parts are XML.
        for object in chartObjects {
            xml.raw("<manifest:file-entry")
            xml.attribute("manifest:full-path", object.path + "/")
            xml.raw(" manifest:version=\"1.3\" manifest:media-type=\"\(ODPMediaType.chart)\"/>")
            for part in ["content.xml", "styles.xml", "meta.xml"] {
                xml.raw("<manifest:file-entry")
                xml.attribute("manifest:full-path", object.path + "/" + part)
                xml.raw(" manifest:media-type=\"text/xml\"/>")
            }
        }
        xml.raw("</manifest:manifest>")
        return xml.data
    }

    static func mediaType(_ contentType: String, path: String) -> String {
        switch contentType.lowercased() {
        case "image/jpg", "image/pjpeg": return "image/jpeg"
        case "image/emf": return "image/x-emf"
        case "image/wmf": return "image/x-wmf"
        case let type where type.contains("/"): return type
        default: return "application/octet-stream"
        }
    }

    private func writeFontDeclarations(_ xml: inout XMLWriter) {
        xml.raw("<office:font-face-decls>")
        for font in fonts {
            xml.raw("<style:font-face")
            xml.attribute("style:name", font)
            xml.attribute("svg:font-family", font.contains(" ") || font.contains(",") ? "'" + font.replacingOccurrences(of: "'", with: "") + "'" : font)
            xml.raw("/>")
        }
        xml.raw("</office:font-face-decls>")
    }

    // MARK: Shared resources

    /// Records a font family so it's declared.
    func use(font: String?) {
        guard let font, !font.isEmpty, fontSet.insert(font).inserted else { return }
        fonts.append(font)
    }

    /// Records the fonts text properties name.
    func use(_ properties: ODFTextProperties) {
        use(font: properties.fontFamily)
    }

    func use(_ style: ODFStyle) {
        use(style.text)
        for level in (style.listStyle ?? [:]).values { use(level.text) }
    }

    /// Stores a chart as an embedded chart object of the given size and returns its folder ("Object 1").
    func chartObject(_ chart: Chart, size: SlideSize) -> String {
        let path = "Object \(chartObjects.count + 1)"
        chartObjects.append((path, ODPChartWriter(chart: chart, size: size).content()))
        return path
    }

    /// The path a media item is stored at: pictures in Pictures/, movies and sounds in Media/, where LibreOffice keeps
    /// them. Nil when the presentation doesn't have it.
    func mediaPath(_ id: MediaID) -> String? {
        if let known = mediaPaths[id] { return known }
        guard let item = presentation.media[id], !item.data.isEmpty else { return nil }
        let path: String
        if item.isVideo || item.isAudio {
            clipCount += 1
            path = "Media/media\(clipCount).\(PPTXMedia.fileExtension(item))"
        } else {
            pictureCount += 1
            path = "Pictures/image\(pictureCount).\(item.fileExtension)"
        }
        mediaPaths[id] = path
        mediaParts.append((path, item))
        return path
    }

    func gradientName(_ gradient: ODFGradient) -> String {
        if let known = gradients[gradient] { return known }
        let display = "Gradient \(gradients.count + 1)"
        let name = ODFFormat.styleName(display)
        gradients[gradient] = name
        gradient.write(name: name, displayName: display, to: &gradientXML)
        return name
    }

    /// The `draw:fill-image` for a picture, or nil when the image is gone.
    func fillImageName(_ id: MediaID) -> String? {
        if let known = images[id] { return known }
        guard let path = mediaPath(id) else { return nil }
        let display = "Image \(images.count + 1)"
        let name = ODFFormat.styleName(display)
        images[id] = name
        imageXML.raw("<draw:fill-image")
        imageXML.attribute("draw:name", name)
        imageXML.attribute("draw:display-name", display)
        imageXML.attribute("xlink:href", path)
        imageXML.raw(" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>")
        return name
    }

    func markerName(_ end: LineEnd) -> (name: String, centered: Bool)? {
        guard let definition = ODPGeometry.marker(end) else { return nil }
        if let known = markerNames[end] { return (known, definition.centered) }
        let name = ODFFormat.styleName(definition.name)
        markerNames[end] = name
        markerXML.raw("<draw:marker")
        markerXML.attribute("draw:name", name)
        markerXML.attribute("draw:display-name", definition.name)
        markerXML.attribute("svg:viewBox", definition.marker.viewBox)
        markerXML.attribute("svg:d", definition.marker.path)
        markerXML.raw("/>")
        return (name, definition.centered)
    }

    func dashName(_ style: DashStyle) -> String? {
        guard let definition = ODPGeometry.dash(style) else { return nil }
        if let known = dashNames[style] { return known }
        let name = ODFFormat.styleName(definition.name)
        dashNames[style] = name
        definition.dash.write(name: name, displayName: definition.name, to: &dashXML)
        return name
    }

    /// A data style for a DrawingML date or time field ("datetime4" …), named after it.
    func dateStyleName(_ type: String) -> (name: String, isTime: Bool) {
        let number = Int(type.dropFirst("datetime".count)) ?? 1
        let isTime = (10...13).contains(number)
        if let known = dateStyles[type] { return (known, isTime) }
        let name = ODFFormat.styleName(type)
        dateStyles[type] = name
        let tag = isTime ? "number:time-style" : "number:date-style"
        dateStyleXML.raw("<\(tag) style:name=\"\(name)\">")
        let text = { (value: String) in "<number:text>\(value)</number:text>" }
        switch number {
        case 2: dateStyleXML.raw("<number:day-of-week number:style=\"long\"/>\(text(", "))<number:month number:textual=\"true\" number:style=\"long\"/>"
            + "\(text(" "))<number:day/>\(text(", "))<number:year number:style=\"long\"/>")
        case 3: dateStyleXML.raw("<number:day/>\(text(" "))<number:month number:textual=\"true\" number:style=\"long\"/>\(text(" "))<number:year number:style=\"long\"/>")
        case 4: dateStyleXML.raw("<number:month number:textual=\"true\" number:style=\"long\"/>\(text(" "))<number:day/>\(text(", "))<number:year number:style=\"long\"/>")
        case 5: dateStyleXML.raw("<number:day/>\(text("-"))<number:month number:textual=\"true\"/>\(text("-"))<number:year/>")
        case 6: dateStyleXML.raw("<number:month number:textual=\"true\" number:style=\"long\"/>\(text(" "))<number:year/>")
        case 7: dateStyleXML.raw("<number:month number:textual=\"true\"/>\(text("-"))<number:year/>")
        case 10: dateStyleXML.raw("<number:hours/>\(text(":"))<number:minutes number:style=\"long\"/>")
        case 11: dateStyleXML.raw("<number:hours/>\(text(":"))<number:minutes number:style=\"long\"/>\(text(":"))<number:seconds number:style=\"long\"/>")
        case 12: dateStyleXML.raw("<number:hours/>\(text(":"))<number:minutes number:style=\"long\"/>\(text(" "))<number:am-pm/>")
        case 13: dateStyleXML.raw("<number:hours/>\(text(":"))<number:minutes number:style=\"long\"/>\(text(":"))<number:seconds number:style=\"long\"/>"
            + "\(text(" "))<number:am-pm/>")
        case 8, 9: dateStyleXML.raw("<number:month/>\(text("/"))<number:day/>\(text("/"))<number:year number:style=\"long\"/>\(text(" "))<number:hours/>"
            + "\(text(":"))<number:minutes number:style=\"long\"/>")
            if number == 9 { dateStyleXML.raw("\(text(":"))<number:seconds number:style=\"long\"/>") }
            dateStyleXML.raw("\(text(" "))<number:am-pm/>")
        default: dateStyleXML.raw("<number:month/>\(text("/"))<number:day/>\(text("/"))<number:year number:style=\"long\"/>")
        }
        dateStyleXML.raw("</\(tag)>")
        return (name, isTime)
    }

    // MARK: Masters

    /// Whether a layout needs a master page of its own to look right in other apps.
    static func needsOwnMaster(_ layout: Layout) -> Bool {
        layout.background != nil || !layout.showsThemeElements || layout.elements.contains { $0.placeholder == nil }
    }

    private func planMasters() {
        var used = Set<String>()
        var usedPageLayouts = Set<String>()
        func unique(_ display: String, in set: inout Set<String>) -> (name: String, display: String) {
            var candidate = display.isEmpty ? "Master" : display
            var number = 2
            while !set.insert(ODFFormat.styleName(candidate)).inserted {
                candidate = (display.isEmpty ? "Master" : display) + " \(number)"
                number += 1
            }
            return (ODFFormat.styleName(candidate), candidate)
        }
        for (index, theme) in presentation.themes.enumerated() {
            let master = unique(theme.name, in: &used)
            themeMasters[index] = master.name
            masters.append(ODPMaster(name: master.name, displayName: master.display, themeIndex: index, layout: nil))
            for layout in theme.layouts {
                let display = master.display + ": " + layout.name
                if pageLayoutNames[Self.key(index, layout.id)] == nil {
                    let pageLayout = unique(display, in: &usedPageLayouts)
                    pageLayoutNames[Self.key(index, layout.id)] = pageLayout.name
                    writePageLayout(layout, theme: theme, name: pageLayout.name, display: pageLayout.display)
                }
                guard Self.needsOwnMaster(layout), layoutMasters[Self.key(index, layout.id)] == nil else { continue }
                let own = unique(display, in: &used)
                layoutMasters[Self.key(index, layout.id)] = own.name
                masters.append(ODPMaster(name: own.name, displayName: own.display, themeIndex: index, layout: layout))
            }
        }
    }

    /// The master page a slide uses: its layout's own, else its theme's.
    func masterName(for slide: Slide) -> String {
        let themeIndex = presentation.layoutLocation(slide.layoutID)?.theme ?? 0
        if let own = layoutMasters[Self.key(themeIndex, slide.layoutID)] { return own }
        return themeMasters[themeIndex] ?? themeMasters[0] ?? "Master"
    }

    func themeMasterName(_ themeIndex: Int) -> String { themeMasters[themeIndex] ?? themeMasters[0] ?? "Master" }

    /// The presentation page layout a slide names.
    func pageLayoutName(for slide: Slide) -> String? {
        pageLayoutNames[Self.key(presentation.layoutLocation(slide.layoutID)?.theme ?? 0, slide.layoutID)]
    }

    /// The ODF presentation object a placeholder is.
    static func presentationClass(_ type: PlaceholderType) -> String {
        switch type {
        case .title, .centeredTitle: "title"
        case .subtitle: "subtitle"
        case .body, .object: "outline"
        case .picture, .clipArt: "graphic"
        case .chart: "chart"
        case .table: "table"
        case .diagram: "orgchart"
        case .media: "object"
        case .slideNumber: "page-number"
        case .date: "date-time"
        case .footer: "footer"
        case .header: "header"
        case .slideImage: "page"
        }
    }

    /// The master presentation style a placeholder's own style derives from.
    static func classStyleSuffix(_ type: PlaceholderType) -> String {
        switch TextCategory(type) {
        case .title: "title"
        case .body: type == .subtitle ? "subtitle" : "outline1"
        case .other: "backgroundobjects"
        }
    }

    private func writePageLayout(_ layout: Layout, theme: Theme, name: String, display: String) {
        pageLayoutXML.raw("<style:presentation-page-layout")
        pageLayoutXML.attribute("style:name", name)
        pageLayoutXML.attribute("style:display-name", display)
        pageLayoutXML.raw(">")
        let placeholders = layout.elements.filter { $0.placeholder.map { !$0.type.isFooterKind && $0.type != .slideImage } ?? false }
        // LibreOffice recognizes its layouts by the title coming first.
        let ordered = placeholders.filter { $0.placeholder?.type.isTitle == true } + placeholders.filter { $0.placeholder?.type.isTitle != true }
        for element in ordered {
            guard let ref = element.placeholder else { continue }
            let frame = (element.placement ?? theme.placeholder(matching: ref)?.placement ?? Placement(frame: .zero)).frame.standardized
            pageLayoutXML.raw("<presentation:placeholder presentation:object=\"\(Self.presentationClass(ref.type))\"")
            pageLayoutXML.raw(" svg:x=\"\(ODFFormat.pt(frame.x))\" svg:y=\"\(ODFFormat.pt(frame.y))\"")
            pageLayoutXML.raw(" svg:width=\"\(ODFFormat.pt(frame.width))\" svg:height=\"\(ODFFormat.pt(frame.height))\"/>")
        }
        pageLayoutXML.raw("</style:presentation-page-layout>")
    }

    // MARK: Common styles

    /// A theme's text at one level, as a placeholder (or other text) on it would show it.
    func themeText(_ theme: Theme, placeholder: SlideElement?, parents extra: [SlideElement] = [], type: PlaceholderType?, level: Int)
        -> (text: ODFTextValues, paragraph: ODFParagraphValues, bullet: ODFBulletValues) {
        let element = SlideElement(placement: nil, placeholder: type.map { PlaceholderRef(type: $0) }, content: .shape(Shape(text: TextBody())))
        var parents = extra
        if let placeholder { parents.append(placeholder) }
        let style = ElementStyle(element: element, parents: parents, theme: theme, defaultTextStyle: presentation.defaultTextStyle)
        let levelStyle = style.inheritedLevelStyle(level)
        let text = ODFTextValues(style.resolve(levelStyle.character))
        let paragraph = levelStyle.paragraph
        let values = ODFParagraphValues(alignment: paragraph.alignment ?? .left, lineSpacing: paragraph.lineSpacing ?? 1,
                                        spaceBefore: paragraph.spaceBefore ?? 0, spaceAfter: paragraph.spaceAfter ?? 0,
                                        marginLeft: paragraph.marginLeft ?? 0, indent: paragraph.indent ?? 0)
        let bullet = ODFBulletValues(bullet: paragraph.bullet ?? Bullet.none, font: paragraph.bulletFont.map(theme.fonts.resolve),
                                     color: paragraph.bulletColor.map { style.resolve($0).rgb }, size: paragraph.bulletSize)
        return (text, values, bullet)
    }

    /// Text properties stating every value.
    static func properties(_ values: ODFTextValues) -> ODFTextProperties {
        var result = ODFTextProperties()
        result.fontFamily = values.fontFamily
        result.fontSize = values.fontSize
        result.bold = values.bold
        result.italic = values.italic
        result.underline = values.underline
        result.strikethrough = values.strikethrough
        result.color = values.color
        result.highlight = values.highlight.map { .color($0) }
        result.baseline = values.baseline
        return result
    }

    static func properties(_ values: ODFParagraphValues) -> ODFParagraphProperties {
        var result = ODFParagraphProperties()
        result.alignment = values.alignment
        result.lineSpacing = values.lineSpacing
        result.spaceBefore = values.spaceBefore
        result.spaceAfter = values.spaceAfter
        result.marginLeft = values.marginLeft
        result.indent = values.indent
        return result
    }

    /// Graphic properties for how a placeholder's text sits and what it's filled and outlined with.
    func frameProperties(_ style: ElementStyle) -> ODFGraphicProperties {
        var result = ODPContentWriter.bodyProperties(style.bodyProperties)
        let fill = fillProperties(style.fill, colors: style.theme.colors)
        let stroke = strokeProperties(style.outline, colors: style.theme.colors)
        result = fill.merged(over: stroke).merged(over: result)
        return result
    }

    /// The styles every theme's text inherits through: the master's presentation styles and the theme's style for
    /// other text, written fully so they don't depend on anything else.
    private func buildCommonStyles() -> XMLWriter {
        var xml = XMLWriter(fragmentCapacity: 64 * 1024)
        // Defaults beneath everything: the presentation's text defaults, with the first theme's fonts and colors.
        let firstTheme = presentation.themes[0]
        var defaults = ODFStyle(family: "graphic")
        let base = themeText(firstTheme, placeholder: nil, type: nil, level: 0)
        defaults.text = Self.properties(ODFTextValues(fontFamily: base.text.fontFamily, fontSize: base.text.fontSize, bold: false, italic: false,
                                                      underline: false, strikethrough: false, color: base.text.color, highlight: nil, baseline: .normal))
        defaults.text.highlight = nil
        defaults.paragraph = Self.properties(ODFParagraphValues.fallback)
        sheet.defaults["graphic"] = defaults
        use(defaults)
        xml.raw("<style:default-style style:family=\"graphic\">")
        defaults.writeBody(name: "", to: &xml)
        xml.raw("</style:default-style>")

        // LibreOffice's base drawing style, set to how DrawingML shapes behave when nothing is said.
        var standard = ODFStyle(family: "graphic")
        standard.graphic.fill = "solid"
        standard.graphic.fillColor = RGBColor(hex: "729FCF")
        standard.graphic.stroke = "solid"
        standard.graphic.strokeColor = RGBColor(hex: "3465A4")
        standard.graphic.strokeWidth = 0
        standard.graphic.merge(body: ODPContentWriter.bodyProperties(ResolvedBodyProperties(anchor: .top, insets: .office, autofit: .none,
                                                                                            fontScale: 1, lineSpacingReduction: 0, wraps: true)))
        commonStyle(standard, name: "standard", display: nil, into: &xml)

        for (index, theme) in presentation.themes.enumerated() {
            let master = themeMasterName(index)
            var other = ODFStyle(family: "graphic", parent: "standard")
            let values = themeText(theme, placeholder: nil, type: nil, level: 0)
            other.text = Self.properties(values.text)
            other.paragraph = Self.properties(values.paragraph)
            commonStyle(other, name: master + "-other", display: (masters.first { $0.name == master }?.displayName ?? theme.name) + "-other", into: &xml)
        }
        for master in masters {
            writePresentationStyles(master, into: &xml)
        }
        return xml
    }

    private func commonStyle(_ style: ODFStyle, name: String, display: String?, into xml: inout XMLWriter) {
        sheet.add(style, name: name)
        use(style)
        xml.raw("<style:style")
        xml.attribute("style:name", name)
        if let display { xml.attribute("style:display-name", display) }
        xml.raw(" style:family=\"\(style.family)\"")
        if let parent = style.parent { xml.attribute("style:parent-style-name", parent) }
        xml.raw(">")
        style.writeBody(name: name, to: &xml)
        xml.raw("</style:style>")
    }

    private func writePresentationStyles(_ master: ODPMaster, into xml: inout XMLWriter) {
        let theme = presentation.themes[master.themeIndex]
        let title = theme.placeholder(matching: PlaceholderRef(type: .title))
        let body = theme.placeholder(matching: PlaceholderRef(type: .body))
        let subtitleLayout = theme.layout(kind: .title)?.placeholder(matching: PlaceholderRef(type: .subtitle))
        func define(_ suffix: String, parent: String? = nil, _ build: (inout ODFStyle) -> Void) {
            var style = ODFStyle(family: "presentation", parent: parent.map { master.name + "-" + $0 })
            build(&style)
            // LibreOffice pairs presentation styles with masters by display name ("Simple Light-title").
            let display = master.displayName + "-" + suffix
            commonStyle(style, name: master.name + "-" + suffix, display: ODFFormat.styleName(master.displayName) == master.displayName ? nil : display,
                        into: &xml)
        }
        func placeholderStyle(_ element: SlideElement?, type: PlaceholderType, extra: [SlideElement] = []) -> ODFGraphicProperties {
            let probe = SlideElement(placement: nil, placeholder: PlaceholderRef(type: type), content: .shape(Shape(text: TextBody())))
            var parents = extra
            if let element { parents.append(element) }
            return frameProperties(ElementStyle(element: probe, parents: parents, theme: theme, defaultTextStyle: self.presentation.defaultTextStyle))
        }

        define("background") { style in
            style.graphic = fillProperties(theme.background, colors: theme.colors)
            style.graphic.stroke = "none"
        }
        define("backgroundobjects") { style in
            let values = themeText(theme, placeholder: nil, type: .footer, level: 0)
            style.graphic.fill = "none"
            style.graphic.stroke = "none"
            style.text = Self.properties(values.text)
            style.paragraph = Self.properties(values.paragraph)
        }
        define("notes") { style in
            let values = themeText(theme, placeholder: nil, type: nil, level: 0)
            style.graphic.fill = "none"
            style.graphic.stroke = "none"
            style.text = Self.properties(values.text)
            style.paragraph = Self.properties(values.paragraph)
        }
        define("title") { style in
            let values = themeText(theme, placeholder: title, type: .title, level: 0)
            style.graphic = placeholderStyle(title, type: .title)
            style.text = Self.properties(values.text)
            style.paragraph = Self.properties(values.paragraph)
        }
        define("subtitle") { style in
            let values = themeText(theme, placeholder: body, parents: subtitleLayout.map { [$0] } ?? [], type: .subtitle, level: 0)
            style.graphic = placeholderStyle(body, type: .subtitle, extra: subtitleLayout.map { [$0] } ?? [])
            style.text = Self.properties(values.text)
            style.paragraph = Self.properties(values.paragraph)
        }
        for level in 0...8 {
            define("outline\(level + 1)", parent: level == 0 ? nil : "outline\(level)") { style in
                let values = themeText(theme, placeholder: body, type: .body, level: level)
                if level == 0 {
                    style.graphic = placeholderStyle(body, type: .body)
                    var list = ODFListStyle()
                    for listLevel in 0...8 {
                        let levelValues = themeText(theme, placeholder: body, type: .body, level: listLevel)
                        guard levelValues.bullet.bullet != Bullet.none else { continue }
                        list[listLevel] = levelValues.bullet.level(margins: (levelValues.paragraph.marginLeft, levelValues.paragraph.indent))
                    }
                    style.listStyle = list
                }
                style.text = Self.properties(values.text)
                style.paragraph = Self.properties(values.paragraph)
                if values.bullet.bullet != Bullet.none {
                    // The level's list style holds the indentation, as in LibreOffice's outline styles.
                    let margins = ODFListLevel.paragraphMargins(left: values.paragraph.marginLeft, indent: values.paragraph.indent)
                    style.paragraph.marginLeft = margins.margin
                    style.paragraph.indent = margins.textIndent
                }
            }
        }
    }

    /// Fill attributes for a fill. Gradients with more than two stops keep their ends, or their middle when the
    /// ends match (an axial gradient); pictures whose image is gone become no fill.
    func fillProperties(_ fill: Fill, colors: ColorScheme) -> ODFGraphicProperties {
        var result = ODFGraphicProperties()
        switch fill {
        case .none:
            result.fill = "none"
        case .solid(let color):
            let resolved = color.resolved(colors)
            result.fill = "solid"
            result.fillColor = resolved.rgb
            if resolved.alpha < 1 { result.opacity = resolved.alpha }
        case .gradient(let gradient):
            let stops = gradient.stops.sorted { $0.position < $1.position }
            guard let first = stops.first, let last = stops.last else {
                result.fill = "none"
                return result
            }
            func rgb(_ stop: GradientStop) -> RGBColor { stop.color.resolved(colors).rgb }
            guard stops.count > 1 else {
                result.fill = "solid"
                result.fillColor = rgb(first)
                return result
            }
            var odf: ODFGradient
            switch gradient.kind {
            case .linear(let angle):
                if stops.count == 3, rgb(first) == rgb(last), abs(stops[1].position - 0.5) < 0.01, first.position < 0.01, last.position > 0.99 {
                    odf = ODFGradient(style: "axial", start: rgb(first), end: rgb(stops[1]), angle: Placement.normalized(90 - angle))
                } else {
                    odf = ODFGradient(style: "linear", start: rgb(first), end: rgb(last), angle: Placement.normalized(90 - angle),
                                      border: min(max(first.position, 0), 1))
                }
            case .radial:
                odf = ODFGradient(style: "radial", start: rgb(last), end: rgb(first), border: min(max(1 - last.position, 0), 1))
            }
            result.fill = "gradient"
            result.gradientName = gradientName(odf)
        case .picture(let picture):
            guard let name = fillImageName(picture.mediaID) else {
                result.fill = "none"
                return result
            }
            result.fill = "bitmap"
            result.imageName = name
            result.repeatMode = picture.stretches ? "stretch" : "repeat"
        }
        return result
    }

    /// Stroke attributes for an outline, with markers for its ends.
    func strokeProperties(_ outline: Outline, colors: ColorScheme) -> ODFGraphicProperties {
        var result = ODFGraphicProperties()
        let color: ColorRef?
        switch outline.fill {
        case .solid(let solid): color = solid
        case .gradient(let gradient): color = gradient.stops.min { $0.position < $1.position }?.color
        case .none, .picture: color = nil
        }
        guard let color, outline.width > 0 else {
            result.stroke = "none"
            return result
        }
        let resolved = color.resolved(colors)
        result.stroke = outline.dash == .solid ? "solid" : "dash"
        if outline.dash != .solid { result.dashName = dashName(outline.dash) }
        result.strokeColor = resolved.rgb
        result.strokeWidth = min(outline.width, 1000)
        if resolved.alpha < 1 { result.strokeOpacity = resolved.alpha }
        let markerWidth = max(outline.width * 3, 4.5)
        if let marker = markerName(outline.head) {
            result.markerStart = marker.name
            result.markerStartWidth = markerWidth
            result.markerStartCenter = marker.centered
        }
        if let marker = markerName(outline.tail) {
            result.markerEnd = marker.name
            result.markerEndWidth = markerWidth
            result.markerEndCenter = marker.centered
        }
        return result
    }

    // MARK: Master pages

    private func writeMasterPages() -> XMLWriter {
        var xml = XMLWriter(fragmentCapacity: 32 * 1024)
        for master in masters {
            let theme = presentation.themes[master.themeIndex]
            var page = ODFStyle(family: "drawing-page")
            page.page.fill = fillProperties(master.layout?.background ?? theme.background, colors: theme.colors)
            let pageStyle = masterStyles.name(page, kind: "dp")
            xml.raw("<style:master-page")
            xml.attribute("style:name", master.name)
            xml.attribute("style:display-name", master.displayName)
            xml.raw(" style:page-layout-name=\"PM1\"")
            xml.attribute("draw:style-name", pageStyle)
            xml.raw(">")
            let shapes = ODPContentWriter(document: self).masterPage(master, theme: theme)
            xml.raw(shapes)
            // The notes page: the slide's thumbnail above the notes.
            let notesFrames = Self.notesFrames(slideSize: presentation.slideSize)
            xml.raw("<presentation:notes style:page-layout-name=\"PM2\">")
            xml.raw("<draw:page-thumbnail draw:layer=\"backgroundobjects\" \(Self.position(notesFrames.thumbnail)) presentation:class=\"page\"/>")
            xml.raw("<draw:frame")
            xml.attribute("presentation:style-name", master.name + "-notes")
            xml.raw(" draw:layer=\"backgroundobjects\" \(Self.position(notesFrames.notes)) presentation:class=\"notes\" presentation:placeholder=\"true\">")
            xml.raw("<draw:text-box/></draw:frame></presentation:notes>")
            xml.raw("</style:master-page>")
        }
        return xml
    }

    static func position(_ frame: SlideRect) -> String {
        "svg:width=\"\(ODFFormat.pt(frame.width))\" svg:height=\"\(ODFFormat.pt(frame.height))\" svg:x=\"\(ODFFormat.pt(frame.x))\" svg:y=\"\(ODFFormat.pt(frame.y))\""
    }

    /// A letter-size notes page: the slide's thumbnail, then the notes.
    static func notesFrames(slideSize: SlideSize) -> (thumbnail: SlideRect, notes: SlideRect) {
        let width = 468.0
        let height = min(width / max(slideSize.aspectRatio, 0.1), 360)
        let thumbnail = SlideRect(x: 72, y: 54, width: width, height: height)
        let top = thumbnail.maxY + 36
        return (thumbnail, SlideRect(x: 72, y: top, width: width, height: max(72, 792 - 54 - top)))
    }
}

extension ODFGraphicProperties {
    /// Takes the text frame properties of `body`.
    mutating func merge(body: ODFGraphicProperties) {
        anchor = body.anchor
        paddingLeft = body.paddingLeft
        paddingTop = body.paddingTop
        paddingRight = body.paddingRight
        paddingBottom = body.paddingBottom
        autoGrowHeight = body.autoGrowHeight
        shrinkToFit = body.shrinkToFit
        fitToSize = body.fitToSize
        wraps = body.wraps
    }
}
