import Foundation

/// Reads OpenDocument presentations (.odp and .otp) from LibreOffice Impress, PuggleSlides and other apps.
///
/// Each master page becomes a theme: its presentation styles give the theme's text styles and fonts, its page style the
/// background, its shapes the decorations and placeholders. Masters named "<Theme>: <Layout>" (as PuggleSlides writes
/// a layout with a look of its own) give that layout its decorations and background. Layouts come from the presentation
/// page layouts PuggleSlides writes, or are built from the placeholders slides use, with LibreOffice's basic set
/// (title slide, title and body, two columns, title only, blank) added so other layouts can be applied.
///
/// Tables are read with their cells' own styles over what their table design gives them; chart objects from their
/// own folders, as the nearest supported chart kinds; Fontwork as word art; image properties as picture adjustments; and
/// the view's snap lines as guides.
enum ODPReader {
    static func read(_ data: Data) throws -> PresentationFile {
        do {
            let reader = try ODPDocumentReader(zip: ZipReader(data: data))
            return try reader.read()
        } catch {
            throw ODPMessages.readError(for: error)
        }
    }
}

/// One master page and what it is to the presentation: a theme, or a layout of a theme.
struct ODPMasterPage {
    var name: String
    var displayName: String
    var node: ODFNode
    var page: ODFPageProperties
    /// For a layout's own master: the theme master's name and the layout's name.
    var layoutOf: (master: String, layout: String)?
}

/// What the first pass learns about a slide.
struct ODPSlideOutline {
    var node: ODFNode
    var master: String
    var pageLayout: String?
    var classes: [String]
    /// Each placeholder's frame, when it states one.
    var frames: [SlideRect?]
    /// Each placeholder's own style, which carries what it inherits from its layout.
    var styles: [ODFStyle?]
    var showsBackgroundObjects: Bool
}

final class ODPDocumentReader {
    static let maxXMLPartSize = 64 << 20
    static let maxMediaSize = 256 << 20

    let zip: ZipReader
    var warnings: Set<ImportWarning> = []
    let commonSheet = ODFStyleSheet()
    private(set) var masterSheet: ODFStyleSheet!
    private(set) var contentSheet: ODFStyleSheet!
    private var manifestTypes: [String: String] = [:]

    private(set) var media: [MediaID: MediaItem] = [:]
    private var mediaByPath: [String: MediaID?] = [:]
    private var mediaByData: [Data: MediaID] = [:]

    /// Slide ids by page name, assigned before slides are read so links can point anywhere.
    var slideIDs: [String: UUID] = [:]
    var slideIDsByNumber: [UUID] = []
    var defaultTextStyle = ListStyle.empty
    var footerDeclarations: [String: String] = [:]
    /// Fixed date texts by declaration name; nil for the current date.
    var dateDeclarations: [String: String?] = [:]

    init(zip: ZipReader) throws {
        self.zip = zip
    }

    // MARK: Package

    func xml(_ path: String) throws -> ODFNode? {
        guard let entry = zip.entry(path), !entry.isDirectory else { return nil }
        guard entry.uncompressedSize <= Self.maxXMLPartSize else { throw ZipError.tooLarge }
        return try ODFXML.parse(try zip.read(entry))
    }

    /// The media stored at `href` (a path in the package), read once and shared by every part showing the same bytes.
    func media(at href: String) -> MediaID? {
        media(at: href, maxSize: Self.maxMediaSize, notesMissing: true)
    }

    /// The package path an href names, nil when it's outside the package.
    private func packagePath(_ href: String) -> String? {
        var path = href.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("./") { path.removeFirst(2) }
        if let decoded = path.removingPercentEncoding { path = decoded }
        guard !path.isEmpty, !path.contains("://"), !path.hasPrefix("/") || zip.contains(path) else { return nil }
        return path
    }

    /// Media up to `maxSize`; `notesMissing` warns of media that's missing or outside the package (movies and sounds say
    /// so themselves).
    func media(at href: String, maxSize: Int, notesMissing: Bool) -> MediaID? {
        guard let path = packagePath(href) else {
            if notesMissing { warnings.insert(.otherContent) }
            return nil
        }
        let key = ZipReader.normalized(path).lowercased()
        if let known = mediaByPath[key] { return known }
        var id: MediaID?
        if let entry = zip.entry(path), !entry.isDirectory, entry.uncompressedSize <= maxSize, let data = try? zip.read(entry), !data.isEmpty {
            if let existing = mediaByData[data] {
                id = existing
            } else {
                let newID = UUID().uuidString
                media[newID] = MediaItem(data: data, contentType: contentType(of: path, data: data))
                mediaByData[data] = newID
                id = newID
            }
        }
        if id == nil, notesMissing { warnings.insert(.otherContent) }
        mediaByPath[key] = id
        return id
    }

    /// The bytes at an href without keeping them as media, such as a preview that may be a default picture.
    func data(at href: String, maxSize: Int) -> Data? {
        guard let path = packagePath(href), let entry = zip.entry(path), !entry.isDirectory, entry.uncompressedSize <= maxSize else { return nil }
        return try? zip.read(entry)
    }

    private func contentType(of path: String, data: Data) -> String {
        if let sniffed = MediaItem.contentType(sniffing: data) { return sniffed }
        switch path.split(separator: ".").last?.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "emf": return "image/x-emf"
        case "wmf": return "image/x-wmf"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case let fileExtension?: if let type = PPTXMedia.contentType(forExtension: fileExtension) { return type }
        default: break
        }
        if let declared = manifestTypes[ZipReader.normalized(path).lowercased()], declared.hasPrefix("image/") || PPTXMedia.isTelling(declared) {
            return declared
        }
        return "application/octet-stream"
    }

    /// The media type the manifest gives a path, for telling charts from other embedded objects.
    func manifestType(_ path: String) -> String? {
        var key = path
        if key.hasPrefix("./") { key.removeFirst(2) }
        key = ZipReader.normalized(key).lowercased()
        return manifestTypes[key] ?? manifestTypes[key + "/"]
    }

    // MARK: Document

    func read() throws -> PresentationFile {
        if let mimetype = try? zip.read("mimetype") {
            let type = String(decoding: mimetype, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if type.hasPrefix("application/vnd.oasis.opendocument."), type != ODPMediaType.presentation, type != ODPMediaType.template {
                throw PresentationIOError.unreadable(ODPMessages.otherDocument)
            }
        }
        if let manifest = try? xml("META-INF/manifest.xml") {
            for entry in manifest.children("manifest:file-entry") {
                guard let path = entry["manifest:full-path"] else { continue }
                if let type = entry["manifest:media-type"] { manifestTypes[ZipReader.normalized(path).lowercased()] = type }
                if entry.child("manifest:encryption-data") != nil { throw PresentationIOError.unreadable(ODPMessages.encrypted) }
            }
        }
        guard let content = try xml("content.xml"), content.name == "office:document-content" else {
            throw PresentationIOError.unreadable(ODPMessages.notAPresentation)
        }
        let body = content.child("office:body")
        guard let presentationNode = body?.child("office:presentation") else {
            let isOther = body?.elements.contains { ["office:text", "office:spreadsheet", "office:drawing", "office:chart"].contains($0.name) } ?? false
            throw PresentationIOError.unreadable(isOther ? ODPMessages.otherDocument : ODPMessages.notAPresentation)
        }
        let styles = (try? xml("styles.xml")).flatMap { $0.name == "office:document-styles" ? $0 : nil }

        commonSheet.readFonts(styles?.child("office:font-face-decls"))
        commonSheet.readFonts(content.child("office:font-face-decls"))
        commonSheet.read(styles?.child("office:styles"))
        masterSheet = ODFStyleSheet(fallback: commonSheet)
        masterSheet.read(styles?.child("office:automatic-styles"))
        contentSheet = ODFStyleSheet(fallback: commonSheet)
        contentSheet.read(content.child("office:automatic-styles"))

        // Slide size: the page layout the masters use.
        let masterNodes = styles?.child("office:master-styles")?.children("style:master-page") ?? []
        var slideSize = SlideSize.widescreen
        if let layoutName = masterNodes.first?["style:page-layout-name"], let size = masterSheet.pageSizes[layoutName] ?? commonSheet.pageSizes[layoutName] {
            slideSize = SlideSize(width: min(max(size.width, 72), 4032), height: min(max(size.height, 72), 4032))
        }

        let pages = presentationNode.children("draw:page")
        for declaration in presentationNode.children("presentation:footer-decl") {
            if let name = declaration["presentation:name"] { footerDeclarations[name] = declaration.textContent }
        }
        for declaration in presentationNode.children("presentation:date-time-decl") {
            guard let name = declaration["presentation:name"] else { continue }
            dateDeclarations[name] = declaration["presentation:source"] == "current-date" ? .some(nil) : declaration.textContent
        }
        for page in pages {
            let id = UUID()
            slideIDsByNumber.append(id)
            if let name = page["draw:name"], slideIDs[name] == nil { slideIDs[name] = id }
        }
        if presentationNode.children.contains(where: { $0.name == "table:table" || $0.name == "office:forms" && !$0.elements.isEmpty }) {
            warnings.insert(.otherContent)
        }

        defaultTextStyle = readDefaultTextStyle()
        var masters = masterPages(masterNodes)
        if masters.isEmpty {
            // Every presentation needs a master; files without one get one from what styles they have.
            masters = [ODPMasterPage(name: "", displayName: "Default", node: ODFNode(name: "style:master-page"), page: ODFPageProperties())]
        }
        let outlines = pages.map { page -> ODPSlideOutline in outline(page, masters: masters) }
        let builder = ODPThemeBuilder(document: self, masters: masters, slideSize: slideSize)
        var themes = builder.themes(outlines: outlines)
        if themes.isEmpty {
            warnings.insert(.otherContent)
            themes = [ODPThemeBuilder.ThemeInfo(theme: BuiltInThemes.simpleLight(slideSize: slideSize), master: "", layoutsByPageLayout: [:])]
        }

        var slides: [Slide] = []
        for (index, outline) in outlines.enumerated() {
            if let slide = builder.slide(outline, id: slideIDsByNumber[index], themes: &themes) { slides.append(slide) }
        }
        builder.finish(&themes)

        var title: String?
        if let meta = try? xml("meta.xml"), let text = meta.child("office:meta")?.child("dc:title")?.textContent.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            title = text
        }
        // View ▸ Guides, from the view settings' snap lines.
        let guides = ((try? xml("settings.xml")) ?? nil).map(ODPSettings.guides) ?? []
        let presentation = Presentation(slideSize: slideSize, themes: themes.map(\.theme), slides: slides, media: media,
                                        defaultTextStyle: defaultTextStyle, title: title, guides: guides)
        return PresentationFile(presentation: presentation, warnings: warnings)
    }

    /// The presentation's text defaults: the default drawing style's, at every level.
    private func readDefaultTextStyle() -> ListStyle {
        guard let style = commonSheet.defaultStyle("graphic") else { return .empty }
        let values = ODFTextValues.fallback.applying(style.text)
        var level = LevelStyle(character: ODPDocumentReader.characterStyle(values))
        level.character.highlight = nil
        if style.paragraph.alignment != nil { level.paragraph.alignment = style.paragraph.alignment }
        var result = ListStyle()
        for index in 0...8 { result[index] = level }
        return result
    }

    /// Every property of `values`, as a character style.
    static func characterStyle(_ values: ODFTextValues) -> CharacterStyle {
        CharacterStyle(fontFamily: values.fontFamily, fontSize: values.fontSize, bold: values.bold, italic: values.italic, underline: values.underline,
                       strikethrough: values.strikethrough, color: ColorRef(values.color), highlight: values.highlight.map { ColorRef($0) },
                       baseline: values.baseline)
    }

    // MARK: Masters

    private func masterPages(_ nodes: [ODFNode]) -> [ODPMasterPage] {
        var result: [ODPMasterPage] = []
        var seen = Set<String>()
        for node in nodes {
            guard let name = node["style:name"], seen.insert(name).inserted else { continue }
            let display = node["style:display-name"] ?? ODFFormat.decodedStyleName(name)
            var page = ODFPageProperties()
            if let styleName = node["draw:style-name"] { page = masterSheet.resolved("drawing-page", styleName).page }
            result.append(ODPMasterPage(name: name, displayName: display, node: node, page: page))
        }
        // "<Theme>: <Layout>" masters belong to the theme master with the longest matching name.
        for index in result.indices {
            let display = result[index].displayName
            var best: ODPMasterPage?
            for candidate in result where candidate.name != result[index].name && display.hasPrefix(candidate.displayName + ": ") {
                if best == nil || candidate.displayName.count > best!.displayName.count { best = candidate }
            }
            if let best {
                result[index].layoutOf = (best.name, String(display.dropFirst(best.displayName.count + 2)))
            }
        }
        // A layout's master can't itself own layouts.
        for index in result.indices {
            if let owner = result[index].layoutOf?.master, result.first(where: { $0.name == owner })?.layoutOf != nil { result[index].layoutOf = nil }
        }
        return result
    }

    /// The first look at a slide: its master, layout and placeholders.
    private func outline(_ page: ODFNode, masters: [ODPMasterPage]) -> ODPSlideOutline {
        let masterName = page["draw:master-page-name"].flatMap { name in masters.contains { $0.name == name } ? name : nil } ?? masters[0].name
        var classes: [String] = []
        var frames: [SlideRect?] = []
        var styles: [ODFStyle?] = []
        for child in page.elements {
            guard let type = ODPElementReader.placeholderClass(child, sheet: contentSheet) else { continue }
            classes.append(type)
            frames.append(ODPElementReader.placement(child)?.frame)
            let family = child["presentation:style-name"] != nil ? "presentation" : "graphic"
            styles.append((child["presentation:style-name"] ?? child["draw:style-name"]).flatMap { contentSheet.style(family, $0) })
        }
        // Placeholders that state no place are where the slide's page layout puts them.
        if frames.contains(where: { $0 == nil }), let name = page["presentation:presentation-page-layout-name"],
           let pageLayout = commonSheet.pageLayouts.first(where: { $0.name == name }) {
            var used = Set<Int>()
            for index in frames.indices where frames[index] == nil {
                let wanted = classes[index] == "text" ? "outline" : classes[index]
                guard let match = pageLayout.placeholders.indices.first(where: { !used.contains($0) && pageLayout.placeholders[$0].object == wanted })
                else { continue }
                used.insert(match)
                frames[index] = pageLayout.placeholders[match].frame
            }
        }
        let style = page["draw:style-name"].map { contentSheet.resolved("drawing-page", $0).page } ?? ODFPageProperties()
        return ODPSlideOutline(node: page, master: masterName, pageLayout: page["presentation:presentation-page-layout-name"], classes: classes,
                               frames: frames, styles: styles, showsBackgroundObjects: style.backgroundObjectsVisible ?? true)
    }
}

/// Builds themes from master pages, and slides on them.
final class ODPThemeBuilder {
    struct ThemeInfo {
        var theme: Theme
        var master: String
        /// Layout ids by presentation page layout name.
        var layoutsByPageLayout: [String: UUID]
    }

    let document: ODPDocumentReader
    let masters: [ODPMasterPage]
    let slideSize: SlideSize
    private var themeIndexByMaster: [String: Int] = [:]
    /// Placeholder positions a layout falls back to when no slide shows it, by layout id and element index.
    private var defaultFrames: [UUID: [Int: SlideRect]] = [:]
    /// Layout placeholders that took their text formatting from a slide.
    private var learned = Set<String>()

    init(document: ODPDocumentReader, masters: [ODPMasterPage], slideSize: SlideSize) {
        self.document = document
        self.masters = masters
        self.slideSize = slideSize
    }

    // MARK: Themes

    func themes(outlines: [ODPSlideOutline]) -> [ThemeInfo] {
        var result: [ThemeInfo] = []
        for master in masters where master.layoutOf == nil {
            themeIndexByMaster[master.name] = result.count
            var info = ThemeInfo(theme: theme(master), master: master.name, layoutsByPageLayout: [:])
            let ownOutlines = outlines.filter { ownerMaster($0.master) == master.name }
            layouts(for: &info, master: master, outlines: ownOutlines)
            result.append(info)
        }
        for master in masters where master.layoutOf != nil {
            if let owner = master.layoutOf?.master { themeIndexByMaster[master.name] = themeIndexByMaster[owner] }
        }
        return result
    }

    /// The theme master a master page belongs to: itself, or the theme whose layout it is.
    func ownerMaster(_ name: String) -> String {
        masters.first { $0.name == name }?.layoutOf?.master ?? name
    }

    private func style(_ master: String, _ suffix: String) -> ODFStyle? {
        let name = master + "-" + suffix
        return document.commonSheet.style("presentation", name) != nil ? document.commonSheet.resolved("presentation", name) : nil
    }

    private func theme(_ master: ODPMasterPage) -> Theme {
        let sheet = document.commonSheet
        let defaults = sheet.resolved("graphic", nil)
        let title = style(master.name, "title") ?? defaults
        let outline1 = style(master.name, "outline1") ?? defaults
        let titleValues = ODFTextValues.fallback.applying(title.text)
        let bodyValues = ODFTextValues.fallback.applying(outline1.text)
        let fonts = FontScheme(name: master.displayName, major: titleValues.fontFamily, minor: bodyValues.fontFamily)

        func level(_ style: ODFStyle, list: ODFListLevel?) -> LevelStyle {
            let text = ODFTextValues.fallback.applying(style.text)
            let paragraph = ODFParagraphValues.fallback.applying(style.paragraph, fontSize: text.fontSize)
            let bullet = ODFBulletValues(list)
            let margins = list.map { $0.modelMargins(margin: paragraph.marginLeft, textIndent: paragraph.indent) } ?? (paragraph.marginLeft, paragraph.indent)
            var paragraphStyle = ParagraphStyle(alignment: paragraph.alignment, lineSpacing: paragraph.lineSpacing, spaceBefore: paragraph.spaceBefore,
                                                spaceAfter: paragraph.spaceAfter, marginLeft: margins.0, indent: margins.1, bullet: bullet.bullet)
            if bullet.bullet != Bullet.none {
                paragraphStyle.bulletFont = bullet.font
                paragraphStyle.bulletColor = bullet.color.map { ColorRef($0) }
                paragraphStyle.bulletSize = bullet.size
            }
            var character = ODPDocumentReader.characterStyle(text)
            if text.highlight == nil { character.highlight = nil }
            return LevelStyle(paragraph: paragraphStyle, character: character)
        }
        var titleStyle = ListStyle(), bodyStyle = ListStyle(), otherStyle = ListStyle()
        let other = sheet.style("graphic", master.name + "-other") != nil ? sheet.resolved("graphic", master.name + "-other")
            : sheet.resolved("graphic", sheet.style("graphic", "standard") != nil ? "standard" : nil)
        for index in 0...8 {
            titleStyle[index] = level(title, list: nil)
            let outline = style(master.name, "outline\(index + 1)") ?? outline1
            bodyStyle[index] = level(outline, list: outline.listStyle?[index])
            otherStyle[index] = level(other, list: nil)
        }

        var background = ODPElementReader.fill(master.page.fill, document: document, sheet: document.commonSheet)
        if master.page.fill.fill == nil, let legacy = style(master.name, "background"), legacy.graphic.fill != nil {
            background = ODPElementReader.fill(legacy.graphic, document: document, sheet: document.commonSheet)
        }
        if case .none = background { background = .solid(.white) }
        var theme = Theme(name: master.displayName, colors: Self.colors(master.node, name: master.displayName), fonts: fonts, background: background,
                          titleStyle: titleStyle, bodyStyle: bodyStyle, otherStyle: otherStyle)
        let reader = ODPElementReader(document: document, sheet: document.masterSheet, masterName: master.name, theme: theme, isMaster: true)
        theme.elements = reader.elements(in: master.node, refs: ODPElementReader.themeRefs(master.node, sheet: document.masterSheet))
        // Comments on master pages have no place in the model.
        if !reader.takeAnnotations().isEmpty { document.warnings.insert(.comments) }
        return theme
    }

    /// LibreOffice's theme colors (`loext:theme`), else LibreOffice's default theme.
    static func colors(_ node: ODFNode, name: String) -> ColorScheme {
        var colors: [ThemeColorSlot: RGBColor] = [
            .dark1: .black, .light1: .white, .dark2: .black, .light2: .white,
            .accent1: RGBColor(hex: "18A303")!, .accent2: RGBColor(hex: "0369A3")!, .accent3: RGBColor(hex: "A33E03")!,
            .accent4: RGBColor(hex: "8E03A3")!, .accent5: RGBColor(hex: "C99C00")!, .accent6: RGBColor(hex: "C9211E")!,
            .hyperlink: RGBColor(hex: "0000EE")!, .followedHyperlink: RGBColor(hex: "551A8B")!,
        ]
        let slots: [String: ThemeColorSlot] = [
            "dark1": .dark1, "light1": .light1, "dark2": .dark2, "light2": .light2, "accent1": .accent1, "accent2": .accent2, "accent3": .accent3,
            "accent4": .accent4, "accent5": .accent5, "accent6": .accent6, "hyperlink": .hyperlink, "followed-hyperlink": .followedHyperlink,
        ]
        for color in node.child("loext:theme")?.child("loext:theme-colors")?.children("loext:color") ?? [] {
            if let slot = color["loext:name"].flatMap({ slots[$0] }), let rgb = ODFValue.color(color["loext:color"]) { colors[slot] = rgb }
        }
        return ColorScheme(name: name, colors: colors)
    }

    // MARK: Layouts

    private static func placeholderType(_ className: String, kind: LayoutKind) -> PlaceholderType? {
        switch className {
        case "title": kind == .title ? .centeredTitle : .title
        case "subtitle": .subtitle
        case "outline", "text": .body
        case "graphic": .picture
        case "object": .object
        case "chart": .chart
        case "table": .table
        case "orgchart": .diagram
        case "page-number": .slideNumber
        case "date-time": .date
        case "footer": .footer
        case "header": .header
        default: nil
        }
    }

    /// Placeholders from presentation objects, numbered: the title 0, the others from 1.
    private func placeholders(_ objects: [(String, SlideRect?)], kind: LayoutKind, theme: Theme) -> [SlideElement] {
        var result: [SlideElement] = []
        var next = 1
        for (className, frame) in objects {
            guard let type = Self.placeholderType(className, kind: kind), !type.isFooterKind else { continue }
            let index: Int
            if type.isTitle {
                index = 0
            } else {
                index = next
                next += 1
            }
            let ref = PlaceholderRef(type: type, index: index)
            var body = TextBody()
            if type == .subtitle, let subtitle = subtitleText(theme) { body = subtitle }
            result.append(SlideElement(name: "\(type.defaultName) \(result.count + 1)", placement: frame.map { Placement(frame: $0) }, placeholder: ref,
                                       content: .shape(Shape(text: body))))
        }
        if let number = theme.elements.first(where: { $0.placeholder?.type == .slideNumber })?.placeholder {
            result.append(SlideElement(name: "Slide Number", placement: nil, placeholder: PlaceholderRef(type: .slideNumber, index: number.index),
                                       content: .shape(Shape(text: TextBody()))))
        }
        return result
    }

    /// How the master's subtitle style differs from the theme's body: what a layout's subtitle placeholder gives.
    private func subtitleText(_ theme: Theme) -> TextBody? {
        guard let master = themeMaster(theme), let style = style(master, "subtitle") else { return nil }
        let text = ODFTextValues.fallback.applying(style.text)
        let paragraph = ODFParagraphValues.fallback.applying(style.paragraph, fontSize: text.fontSize)
        let probe = SlideElement(placement: nil, placeholder: PlaceholderRef(type: .subtitle, index: 1), content: .shape(Shape(text: TextBody())))
        let parents = theme.placeholder(matching: PlaceholderRef(type: .body)).map { [$0] } ?? []
        let model = ElementStyle(element: probe, parents: parents, theme: theme, defaultTextStyle: document.defaultTextStyle)
        var body = TextBody()
        body.properties = ODPElementReader.difference(ODPElementReader.bodyProperties(style.graphic), from: model.bodyProperties)
        let modelBase = model.inheritedLevelStyle(0)
        var character = ODPElementReader.difference(text, from: ODFTextValues(model.resolve(modelBase.character)))
        character.link = nil
        let paragraphStyle = ParagraphStyle(alignment: paragraph.alignment, lineSpacing: paragraph.lineSpacing, spaceBefore: paragraph.spaceBefore,
                                            spaceAfter: paragraph.spaceAfter, marginLeft: paragraph.marginLeft, indent: paragraph.indent,
                                            bullet: Bullet.none)
        for level in 0...8 { body.listStyle[level] = LevelStyle(paragraph: paragraphStyle, character: character) }
        return body
    }

    private func themeMaster(_ theme: Theme) -> String? {
        masters.first { $0.layoutOf == nil && themeIndexByMaster[$0.name] != nil && $0.displayName == theme.name }?.name
    }

    /// The classes a slide's placeholders give, without footers, in a stable order.
    private static func signature(_ classes: [String]) -> [String] {
        classes.filter { !["page-number", "date-time", "footer", "header", "notes", "page", "handout"].contains($0) }
            .map { $0 == "text" ? "outline" : $0 }.sorted()
    }

    private func layouts(for info: inout ThemeInfo, master: ODPMasterPage, outlines: [ODPSlideOutline]) {
        let theme = info.theme
        let prefix = master.displayName + ": "
        var layouts: [Layout] = []
        // Layouts PuggleSlides recorded.
        for pageLayout in document.commonSheet.pageLayouts where pageLayout.displayName.hasPrefix(prefix) {
            let name = String(pageLayout.displayName.dropFirst(prefix.count))
            let kind = LayoutKind(fileType: nil, name: name)
            var layout = Layout(name: name, kind: kind, elements: placeholders(pageLayout.placeholders.map { ($0.object, $0.frame) }, kind: kind, theme: theme))
            applyOwnMaster(&layout, theme: theme, themeMaster: master)
            info.layoutsByPageLayout[pageLayout.name] = layout.id
            layouts.append(layout)
        }
        // Layouts with their own master but no page layout.
        for own in masters where own.layoutOf?.master == master.name && !layouts.contains(where: { $0.name == own.layoutOf?.layout }) {
            let name = own.layoutOf?.layout ?? "Custom"
            var layout = Layout(name: name, kind: LayoutKind(fileType: nil, name: name))
            applyOwnMaster(&layout, theme: theme, themeMaster: master)
            layouts.append(layout)
        }
        if layouts.isEmpty {
            layouts = standardLayouts(theme)
        }
        // Slides whose layout isn't known get one matching their placeholders.
        for outline in outlines {
            if let pageLayout = outline.pageLayout, info.layoutsByPageLayout[pageLayout] != nil { continue }
            let signature = Self.signature(outline.classes)
            if layouts.contains(where: { Self.signature($0.elements.compactMap { $0.placeholder.map { ODPDocumentWriter.presentationClass($0.type) } }) == signature }) {
                continue
            }
            let kind: LayoutKind = signature == ["outline", "title"] ? .titleAndBody : signature == ["subtitle", "title"] ? .title
                : signature == ["title"] ? .titleOnly : signature.isEmpty ? .blank : .custom
            let name = kind == .custom ? (layouts.contains { $0.name == "Custom" } ? "Custom \(layouts.count + 1)" : "Custom") : kind.title
            let objects = zip(outline.classes, outline.frames).map { ($0.0, $0.1) }
            layouts.append(Layout(name: name, kind: kind, elements: placeholders(objects, kind: kind, theme: theme)))
        }
        if layouts.isEmpty { layouts = [Layout(name: LayoutKind.blank.title, kind: .blank)] }
        info.theme.layouts = layouts
    }

    /// Decorations, background and whether the theme's decorations show, from a layout's own master.
    private func applyOwnMaster(_ layout: inout Layout, theme: Theme, themeMaster: ODPMasterPage) {
        guard let own = masters.first(where: { $0.layoutOf?.master == themeMaster.name && $0.layoutOf?.layout == layout.name }) else { return }
        let reader = ODPElementReader(document: document, sheet: document.masterSheet, masterName: own.name, theme: theme, isMaster: true)
        let refs = ODPElementReader.themeRefs(own.node, sheet: document.masterSheet)
        var decorations = reader.elements(in: own.node, refs: refs).filter { $0.placeholder == nil }
        if !reader.takeAnnotations().isEmpty { document.warnings.insert(.comments) }
        let themeDecorations = theme.elements.filter { $0.placeholder == nil }
        if themeDecorations.isEmpty {
            layout.showsThemeElements = true
        } else if decorations.count >= themeDecorations.count,
                  zip(decorations, themeDecorations).allSatisfy({ ODPElementReader.sameIgnoringIDs($0.0, $0.1) }) {
            decorations.removeFirst(themeDecorations.count)
            layout.showsThemeElements = true
        } else {
            layout.showsThemeElements = false
        }
        layout.elements.insert(contentsOf: decorations, at: 0)
        let background = ODPElementReader.fill(own.page.fill, document: document, sheet: document.commonSheet)
        if own.page.fill.fill != nil, background != theme.background { layout.background = background }
    }

    /// LibreOffice's basic layouts, placed by the master's title and outline areas.
    private func standardLayouts(_ theme: Theme) -> [Layout] {
        let size = slideSize
        let titleArea = theme.placeholder(matching: PlaceholderRef(type: .title))?.placement?.frame
            ?? SlideRect(x: size.width * 0.05, y: size.height * 0.04, width: size.width * 0.9, height: size.height * 0.17)
        let bodyArea = theme.placeholder(matching: PlaceholderRef(type: .body))?.placement?.frame
            ?? SlideRect(x: size.width * 0.05, y: size.height * 0.25, width: size.width * 0.9, height: size.height * 0.65)
        let gap = bodyArea.width * 0.04
        let column = (bodyArea.width - gap) / 2
        let left = SlideRect(x: bodyArea.x, y: bodyArea.y, width: column, height: bodyArea.height)
        let right = SlideRect(x: bodyArea.x + column + gap, y: bodyArea.y, width: column, height: bodyArea.height)
        func layout(_ kind: LayoutKind, _ objects: [(String, SlideRect?)]) -> Layout {
            let layout = Layout(name: kind.title, kind: kind, elements: placeholders(objects.map { ($0.0, nil) }, kind: kind, theme: theme))
            // Where slides don't say otherwise, placeholders sit in the master's title and outline areas.
            var frames = objects.compactMap(\.1)[...]
            for index in layout.elements.indices where layout.elements[index].placeholder.map({ !$0.type.isFooterKind }) ?? false {
                if let frame = frames.popFirst() { defaultFrames[layout.id, default: [:]][index] = frame }
            }
            return layout
        }
        return [
            layout(.title, [("title", titleArea), ("subtitle", bodyArea)]),
            layout(.titleAndBody, [("title", titleArea), ("outline", bodyArea)]),
            layout(.titleAndTwoColumns, [("title", titleArea), ("outline", left), ("outline", right)]),
            layout(.titleOnly, [("title", titleArea)]),
            layout(.blank, []),
        ]
    }

    /// Text formatting a frame's own style states, as a level style. Margins of outlines are relative to their list
    /// levels, so they stay with the paragraphs.
    static func levelStyle(_ style: ODFStyle, margins: Bool) -> LevelStyle {
        let text = style.text
        var character = CharacterStyle(fontFamily: text.fontFamily, fontSize: text.fontSize, bold: text.bold, italic: text.italic,
                                       underline: text.underline, strikethrough: text.strikethrough, color: text.color.map { ColorRef($0) },
                                       baseline: text.baseline)
        if case .color(let color)? = text.highlight { character.highlight = ColorRef(color) }
        let own = style.paragraph
        var paragraph = ParagraphStyle(alignment: own.alignment, lineSpacing: own.lineSpacing, spaceBefore: own.spaceBefore, spaceAfter: own.spaceAfter)
        if margins {
            paragraph.marginLeft = own.marginLeft
            paragraph.indent = own.indent
        }
        return LevelStyle(paragraph: paragraph, character: character)
    }

    /// Gives layout placeholders no slide placed their master's areas.
    func finish(_ themes: inout [ThemeInfo]) {
        for themeIndex in themes.indices {
            for layoutIndex in themes[themeIndex].theme.layouts.indices {
                let id = themes[themeIndex].theme.layouts[layoutIndex].id
                for (elementIndex, frame) in defaultFrames[id] ?? [:]
                where themes[themeIndex].theme.layouts[layoutIndex].elements[elementIndex].placement == nil {
                    themes[themeIndex].theme.layouts[layoutIndex].elements[elementIndex].placement = Placement(frame: frame)
                }
            }
        }
    }

    // MARK: Slides

    func slide(_ outline: ODPSlideOutline, id: UUID, themes: inout [ThemeInfo]) -> Slide? {
        let themeMaster = ownerMaster(outline.master)
        guard let themeIndex = themeIndexByMaster[themeMaster] ?? (themes.isEmpty ? nil : 0) else { return nil }
        var info = themes[themeIndex]
        let signature = Self.signature(outline.classes)
        var layoutIndex: Int?
        if let name = outline.pageLayout, let layoutID = info.layoutsByPageLayout[name] {
            layoutIndex = info.theme.layoutIndex(id: layoutID)
        }
        if layoutIndex == nil {
            layoutIndex = info.theme.layouts.firstIndex { layout in
                Self.signature(layout.elements.compactMap { $0.placeholder.map { ODPDocumentWriter.presentationClass($0.type) } }) == signature
            }
        }
        var layout = info.theme.layouts[layoutIndex ?? 0]
        // A slide that hides its master's decorations is on a variant of its layout that does.
        if !outline.showsBackgroundObjects, layout.showsThemeElements, info.theme.elements.contains(where: { $0.placeholder == nil }) {
            let name = layout.name + " (no theme graphics)"
            if let existing = info.theme.layouts.first(where: { $0.name == name }) {
                layout = existing
            } else {
                var variant = layout
                variant.id = UUID()
                variant.name = name
                variant.kind = .custom
                variant.showsThemeElements = false
                info.theme.layouts.append(variant)
                layout = variant
            }
        }
        // The layout learns its placeholders' places from the first slide that uses it, when it has none.
        if let index = info.theme.layoutIndex(id: layout.id) {
            var used = Set<Int>()
            for (elementIndex, element) in layout.elements.enumerated() where element.placeholder != nil {
                guard let type = element.placeholder?.type, !type.isFooterKind else { continue }
                let className = ODPDocumentWriter.presentationClass(type)
                guard let position = outline.classes.indices.first(where: { position in
                    !used.contains(position) && (outline.classes[position] == className || (className == "outline" && outline.classes[position] == "text"))
                }) else { continue }
                used.insert(position)
                if element.placement == nil, let frame = outline.frames[position] {
                    info.theme.layouts[index].elements[elementIndex].placement = Placement(frame: frame)
                }
                // The placeholder's own text formatting is what it has from its layout.
                if learned.insert("\(layout.id) \(elementIndex)").inserted, let style = outline.styles[position],
                   !style.text.isEmpty || !style.paragraph.isEmpty, var body = element.shape?.text {
                    let level = Self.levelStyle(style, margins: className != "outline")
                    for listLevel in 0...8 { body.listStyle[listLevel] = level.merged(over: body.listStyle[listLevel]) }
                    info.theme.layouts[index].elements[elementIndex].shape?.text = body
                }
            }
            layout = info.theme.layouts[index]
        }
        themes[themeIndex] = info

        let reader = ODPElementReader(document: document, sheet: document.contentSheet, masterName: outline.master, theme: info.theme, isMaster: false)
        reader.layout = layout
        let refs = ODPElementReader.slideRefs(outline.node, sheet: document.contentSheet, layout: layout)
        var slide = Slide(id: id, layoutID: layout.id, elements: reader.elements(in: outline.node, refs: refs))

        let style = outline.node["draw:style-name"].map { document.contentSheet.resolved("drawing-page", $0).page } ?? ODFPageProperties()
        if style.backgroundVisible == false {
            slide.background = Fill.none
        } else if style.fill.fill != nil, style.fill.fill != "none" {
            slide.background = ODPElementReader.fill(style.fill, document: document, sheet: document.contentSheet)
        }
        slide.isSkipped = style.visible == false
        let timing = outline.node.children.first { $0.name == "anim:par" || $0.name == "anim:seq" }
        slide.transition = ODPMotion.transition(page: style, timing: timing)
        // Clips, at any depth, by the ids their commands name them by.
        var clipIDs = Set<UUID>()
        func findClips(_ elements: [SlideElement], depth: Int) {
            guard depth < ODPElementReader.maxGroupDepth + 1 else { return }
            for element in elements {
                if case .group(let children) = element.content { findClips(children, depth: depth + 1) }
                if element.media != nil { clipIDs.insert(element.id) }
            }
        }
        findClips(slide.elements, depth: 0)
        var playback: [UUID: MediaPlayback] = [:]
        slide.animations = ODPMotion.animations(timing: timing, targets: reader.targets, clips: reader.elementIDs.filter { clipIDs.contains($0.value) },
                                                playback: &playback, warnings: &document.warnings)
        if !playback.isEmpty { ODPDocumentReader.apply(playback, to: &slide.elements, depth: 0) }
        if outline.node.child("presentation:animations") != nil { document.warnings.insert(.animations) }
        slide.pruneAnimations()

        // LibreOffice shows the master's footer fields where a slide's page style asks; they become the slide's own.
        let shown: [(Bool?, PlaceholderType)] = [(style.displayPageNumber, .slideNumber), (style.displayFooter, .footer), (style.displayDateTime, .date)]
        for (display, type) in shown where display == true && !slide.elements.contains(where: { $0.placeholder?.type == type }) {
            guard let master = info.theme.elements.first(where: { $0.placeholder?.type == type }) else { continue }
            var element = SlideElement(name: master.name, placement: nil, placeholder: master.placeholder, content: master.content)
            if type == .footer, let footer = footerText(outline.node, kind: "footer") { element.shape?.text = TextBody(footer) }
            if type == .date, let date = footerText(outline.node, kind: "date-time") { element.shape?.text = TextBody(date) }
            slide.elements.append(element)
        }

        if let notes = outline.node.child("presentation:notes") {
            slide.notes = reader.notes(notes)
        }
        let annotations = reader.takeAnnotations()
        if !annotations.isEmpty {
            let elements = slide.elements
            slide.comments = ODPComments.threads(annotations, elementIDs: reader.elementIDs) { id in
                guard let element = PPTXComments.element(id, in: elements) else { return nil }
                if let placement = element.placement { return placement.frame }
                guard let ref = element.placeholder else { return nil }
                return [layout.placeholder(matching: ref), info.theme.placeholder(matching: ref)].lazy.compactMap { $0?.placement }.first?.frame
            }
        }
        return slide
    }

    /// The text of a page's footer or date declaration; nil for a date that shows the current date.
    private func footerText(_ page: ODFNode, kind: String) -> String? {
        let attribute = kind == "footer" ? "presentation:use-footer-name" : "presentation:use-date-time-name"
        guard let name = page[attribute] else { return nil }
        return kind == "footer" ? document.footerDeclarations[name] : document.dateDeclarations[name] ?? nil
    }
}

extension ODPDocumentReader {
    /// Sets how clips start, wherever they are; a clip the timing doesn't play starts by itself, as Impress plays it.
    static func apply(_ playback: [UUID: MediaPlayback], to elements: inout [SlideElement], depth: Int) {
        guard depth <= ODPElementReader.maxGroupDepth else { return }
        for index in elements.indices {
            switch elements[index].content {
            case .group(var children):
                apply(playback, to: &children, depth: depth + 1)
                elements[index].content = .group(children)
            case .media(var clip):
                guard let mode = playback[elements[index].id] else { continue }
                clip.playback = mode
                elements[index].content = .media(clip)
            default:
                continue
            }
        }
    }
}
