import Foundation

/// Reads PowerPoint presentations (.pptx, and .potx, .ppsx and .pptm, which share the format; transitional and
/// strict). Masters become themes, layouts layouts and slides slides, keeping what the file states and leaving
/// the rest to inherit as it does in PowerPoint.
enum PPTXReader {
    static func read(_ data: Data) throws -> PresentationFile {
        // Encrypted presentations and .ppt files are OLE compound documents.
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            throw PresentationIOError.unreadable(PPTXMessages.legacyOrEncrypted)
        }
        do {
            let package = try PPTXPackageReader(zip: ZipReader(data: data))
            var reader = PPTXDocumentReader(package: package)
            return try reader.read()
        } catch {
            throw PPTXMessages.readError(for: error)
        }
    }
}

/// The package being read, and what its parts share: media, warnings, slide ids for links.
final class PPTXPackageReader {
    /// No XML part of a real presentation comes near this; bigger ones are refused before they're expanded.
    static let maxXMLPartSize = 64 << 20
    static let maxMediaSize = 256 << 20

    let zip: ZipReader
    let contentTypes: PPTXContentTypes
    var warnings: Set<ImportWarning> = []
    private(set) var media: [MediaID: MediaItem] = [:]
    private var mediaByPath: [String: MediaID?] = [:]
    private var mediaByData: [Data: MediaID] = [:]
    /// Each slide part's id, assigned before any slide is read so links can point anywhere.
    var slideIDs: [String: UUID] = [:]
    /// Placeholders' list styles and style font references on masters and layouts, as found, by element id.
    var listStyleNodes: [UUID: XNode] = [:]
    var fontReferenceNodes: [UUID: XNode] = [:]
    /// Each element's `cNvPr` id, which animations target.
    var shapeIDs: [UUID: String] = [:]
    /// Each element's creation id (`a16:creationId`), braces stripped and uppercased, which modern comments name.
    var creationIDs: [UUID: String] = [:]
    /// The table styles part, which tables name their style from.
    var tableStylesPath: String?
    private var tableStyles: [String: XNode]?
    /// Embedded packages (charts' workbooks) are small; bigger ones aren't read.
    static let maxEmbeddedSize = 64 << 20
    /// Charts already read, by part and the colors they were read with: frames sharing a chart read it once.
    var charts: [PPTXChartKey: PPTXChartReader.Result] = [:]
    /// Word art PowerPoint warped whose letters take the text color they inherit, filled in once everything is read.
    var wordArtWithInheritedColor: Set<UUID> = []

    init(zip: ZipReader) throws {
        self.zip = zip
        contentTypes = PPTXContentTypes(try? zip.read("[Content_Types].xml"))
    }

    /// Part names are case-insensitive.
    static func key(_ path: String) -> String {
        ZipReader.normalized(path).lowercased()
    }

    /// The entry for a part, trying the name as written and percent-decoded.
    private func entry(_ path: String) -> ZipEntry? {
        if let entry = zip.entry(path) { return entry }
        if let decoded = path.removingPercentEncoding, decoded != path { return zip.entry(decoded) }
        return nil
    }

    /// A part parsed as XML; nil when the package has no such part. Throws when it's malformed or absurdly large.
    func xml(_ path: String) throws -> XNode? {
        guard let entry = entry(path) else { return nil }
        guard entry.uncompressedSize <= Self.maxXMLPartSize else { throw ZipError.tooLarge }
        return try PPTXXML.parse(try zip.read(entry))
    }

    /// The relationships of a part ("" for the package); empty when it has none.
    func relationships(of part: String) throws -> PPTXRelationships {
        guard let entry = entry(PPTXPackage.relationshipsPath(for: part)) else { return PPTXRelationships() }
        guard entry.uncompressedSize <= Self.maxXMLPartSize else { throw ZipError.tooLarge }
        return try PPTXPackage.relationships(try zip.read(entry), of: part)
    }

    /// Lenient: a part whose relationships are damaged has none.
    func relationshipsIfReadable(of part: String) -> PPTXRelationships {
        (try? relationships(of: part)) ?? PPTXRelationships()
    }

    /// The media stored at `path`, read once and shared with every other part showing the same bytes. Pictures are read
    /// up to `maxMediaSize`; movies and sounds may be given more.
    func media(at path: String, maxSize: Int = PPTXPackageReader.maxMediaSize) -> MediaID? {
        let key = Self.key(path)
        if let known = mediaByPath[key] { return known }
        var id: MediaID?
        if let entry = entry(path), !entry.isDirectory, entry.uncompressedSize <= maxSize, let data = try? zip.read(entry), !data.isEmpty {
            if let existing = mediaByData[data] {
                id = existing
            } else {
                let newID = UUID().uuidString
                media[newID] = MediaItem(data: data, contentType: contentType(of: path, data: data))
                mediaByData[data] = newID
                id = newID
            }
        }
        mediaByPath[key] = id
        return id
    }

    /// A table style by id: the package's own definition, else PowerPoint's built-in one where it's known.
    func tableStyle(id: String) -> XNode? {
        if tableStyles == nil {
            var styles: [String: XNode] = [:]
            if let path = tableStylesPath, let root = try? xml(path) {
                for style in root.children("tblStyle") {
                    guard let key = style["styleId"]?.trimmingCharacters(in: .whitespaces).uppercased(), styles[key] == nil else { continue }
                    styles[key] = style
                }
            }
            tableStyles = styles
        }
        let key = id.uppercased()
        if let style = tableStyles?[key] { return style }
        guard let definition = PPTXTableStyles.builtIn(key), let style = try? PPTXXML.parse(Data(definition.utf8)) else { return nil }
        tableStyles?[key] = style
        return style
    }

    /// The bytes of a part without keeping them as media, such as a picture that may turn out to be a default one; nil
    /// when it's missing or too large.
    func data(at path: String, maxSize: Int) -> Data? {
        guard let entry = entry(path), !entry.isDirectory, entry.uncompressedSize <= maxSize else { return nil }
        return try? zip.read(entry)
    }

    /// The bytes of an embedded package, such as a chart's workbook; nil when it's missing or too large.
    func embeddedPackage(at path: String) -> Data? {
        guard let entry = entry(path), !entry.isDirectory, entry.uncompressedSize <= Self.maxEmbeddedSize else { return nil }
        return try? zip.read(entry)
    }

    private func contentType(of path: String, data: Data) -> String {
        if let sniffed = MediaItem.contentType(sniffing: data) { return sniffed }
        let fileExtension = path.split(separator: ".").last.map(String.init) ?? ""
        if let type = PPTXContentType.image(forExtension: fileExtension) ?? PPTXMedia.contentType(forExtension: fileExtension) { return type }
        if let declared = contentTypes.type(of: path), declared.hasPrefix("image/") || PPTXMedia.isTelling(declared) {
            return PPTXContentType.canonical(declared)
        }
        return "application/octet-stream"
    }
}

/// Walks a package from its presentation part down to masters, layouts, slides and notes.
struct PPTXDocumentReader {
    let package: PPTXPackageReader
    private var themes: [Theme] = []
    private var themeData: [UUID: PPTXThemeData] = [:]
    /// Layout parts by key: the layout's id and its theme's.
    private var layoutsByPath: [String: (layout: UUID, theme: UUID)] = [:]
    private var sources = PPTXColorMapSources()
    private var notesMaps: [String: PPTXColorMap] = [:]
    /// Comment authors, read before the slides; comment ids already given, which stay unique.
    private var commentAuthors = PPTXComments.Authors()
    private var commentIDs = Set<UUID>()

    init(package: PPTXPackageReader) {
        self.package = package
    }

    mutating func read() throws -> PresentationFile {
        let rootRelationships = package.relationshipsIfReadable(of: "")
        var mainPath = rootRelationships.first("officeDocument")?.target
        if mainPath == nil, package.zip.contains("ppt/presentation.xml") { mainPath = "ppt/presentation.xml" }
        guard let mainPath, let root = try package.xml(mainPath), root.name == "presentation" else {
            throw PresentationIOError.unreadable(PPTXMessages.notAPresentation)
        }
        let relationships = try package.relationships(of: mainPath)
        package.tableStylesPath = relationships.first("tableStyles")?.target

        var slideSize = SlideSize.standard
        if let size = root.child("sldSz"), let width = PPTXValue.points(size["cx"]), let height = PPTXValue.points(size["cy"]) {
            // PowerPoint's limits: 1 to 56 inches.
            slideSize = SlideSize(width: min(max(width, 72), 4032), height: min(max(height, 72), 4032))
        }

        // Slides get ids first, so links between them can be read in any order.
        var slidePaths: [String] = []
        for node in root.child("sldIdLst")?.children("sldId") ?? [] {
            guard let relationship = relationships[node["id"]], relationship.hasType("slide"), !relationship.isExternal else { continue }
            let key = PPTXPackageReader.key(relationship.target)
            guard package.slideIDs[key] == nil else { continue }
            package.slideIDs[key] = UUID()
            slidePaths.append(relationship.target)
        }

        var masterPaths = (root.child("sldMasterIdLst")?.children("sldMasterId") ?? []).compactMap { node -> String? in
            guard let relationship = relationships[node["id"]], relationship.hasType("slideMaster"), !relationship.isExternal else { return nil }
            return relationship.target
        }
        if masterPaths.isEmpty { masterPaths = relationships.all("slideMaster").filter { !$0.isExternal }.map(\.target) }
        var seenMasters = Set<String>()
        for path in masterPaths where seenMasters.insert(PPTXPackageReader.key(path)).inserted {
            try readMaster(path)
        }
        if themes.isEmpty {
            // Every presentation needs a master; files without one get PuggleSlides' default.
            package.warnings.insert(.otherContent)
            let theme = BuiltInThemes.simpleLight(slideSize: slideSize)
            themes.append(theme)
            themeData[theme.id] = PPTXThemeData.fallback
        }

        // The presentation's text defaults are read with the first master's color map.
        sources.defaultMap = sources.masters[themes[0].id]?.map ?? .standard
        sources.defaultTextStyle = root.child("defaultTextStyle")
        let defaultTextStyle = root.child("defaultTextStyle").map {
            PPTXTextReader(colors: PPTXColorReader(map: sources.defaultMap)) { _ in nil }.listStyle($0)
        } ?? .empty

        commentAuthors = PPTXComments.authors(package, relationships: relationships)
        var slides: [Slide] = []
        for path in slidePaths {
            if let slide = try readSlide(path) { slides.append(slide) }
        }

        var title: String?
        if let core = rootRelationships.first("core-properties")?.target, let properties = try? package.xml(core),
           let text = properties.child("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            title = text
        }

        // Guides: PowerPoint 2013's in the presentation part, else older ones in the view properties.
        let viewProperties = relationships.first("viewProps").flatMap { try? package.xml($0.target) }
        let guides = PPTXGuides.read(root, viewProperties: viewProperties, colors: themes[0].colors)

        var presentation = Presentation(slideSize: slideSize, themes: themes, slides: slides, media: package.media,
                                        defaultTextStyle: defaultTextStyle, title: title, guides: guides)
        PPTXColorMapFixes(sources: sources, listStyles: package.listStyleNodes, fontReferences: package.fontReferenceNodes,
                          themes: themeData).apply(to: &presentation)
        if !package.wordArtWithInheritedColor.isEmpty { fillWordArt(&presentation) }
        return PresentationFile(presentation: presentation, warnings: package.warnings)
    }

    /// Word art paints its letters with the shape's fill. Text PowerPoint warped without a color of its own shows in
    /// the color it inherits, so that becomes the fill, or the letters wouldn't show.
    private func fillWordArt(_ presentation: inout Presentation) {
        let ids = package.wordArtWithInheritedColor
        func filled(_ elements: [SlideElement], style: (SlideElement) -> ElementStyle) -> [SlideElement] {
            elements.map { element in
                var element = element
                if case .group(let children) = element.content {
                    element.content = .group(filled(children, style: style))
                    return element
                }
                guard ids.contains(element.id), var shape = element.shape, shape.fill == nil else { return element }
                let level = shape.text?.paragraphs.first?.level ?? 0
                shape.fill = .solid(style(element).levelStyle(level).character.color ?? ColorRef(theme: .dark1))
                element.content = .shape(shape)
                return element
            }
        }
        let snapshot = presentation
        for themeIndex in presentation.themes.indices {
            let theme = snapshot.themes[themeIndex]
            presentation.themes[themeIndex].elements = filled(theme.elements) { snapshot.style(forThemeElement: $0, theme: theme) }
            for layoutIndex in theme.layouts.indices {
                let layout = theme.layouts[layoutIndex]
                presentation.themes[themeIndex].layouts[layoutIndex].elements = filled(layout.elements) {
                    snapshot.style(for: $0, inLayout: layout, theme: theme)
                }
            }
        }
        for index in presentation.slides.indices {
            let slide = snapshot.slides[index]
            presentation.slides[index].elements = filled(slide.elements) { snapshot.style(for: $0, on: slide) }
        }
    }

    // MARK: Masters and layouts

    private mutating func readMaster(_ path: String) throws {
        guard let root = try package.xml(path), root.name == "sldMaster" else { return }
        let relationships = package.relationshipsIfReadable(of: path)
        if PPTXAnimationReader.animates(root) { package.warnings.insert(.animations) }
        var data = PPTXThemeData.fallback
        if let themePath = relationships.first("theme")?.target, let themeRoot = try? package.xml(themePath) {
            data = PPTXThemeData(themeRoot)
            let themeRelationships = package.relationshipsIfReadable(of: themePath)
            let package = package
            data.media = { id in
                guard let relationship = themeRelationships[id], !relationship.isExternal else { return nil }
                return package.media(at: relationship.target)
            }
        }
        let map = root.child("clrMap").map { PPTXColorMap(node: $0) } ?? .standard
        var context = PPTXPartContext(package: package, path: path, relationships: relationships, map: map, theme: data)
        context.recordsListStyles = true
        let slideData = root.child("cSld")
        let background = context.fills().background(slideData?.child("bg")) ?? .solid(ColorRef(theme: map.slot("bg1") ?? .light1))
        let elements = context.elements(in: slideData?.child("spTree"))
        let styles = root.child("txStyles")
        let text = context.text
        let id = UUID()
        var theme = Theme(id: id, name: data.name, colors: data.colors, fonts: data.fonts, background: background, elements: elements,
                          titleStyle: styles?.child("titleStyle").map(text.listStyle) ?? .empty,
                          bodyStyle: styles?.child("bodyStyle").map(text.listStyle) ?? .empty,
                          otherStyle: styles?.child("otherStyle").map(text.listStyle) ?? .empty)
        sources.masters[id] = PPTXColorMapSources.Master(
            map: map, title: styles?.child("titleStyle"), body: styles?.child("bodyStyle"), other: styles?.child("otherStyle"),
            background: slideData?.child("bg").map { PPTXColorMapSources.Background(node: $0, relationships: relationships) })
        themeData[id] = data

        var layoutPaths = (root.child("sldLayoutIdLst")?.children("sldLayoutId") ?? []).compactMap { node -> String? in
            guard let relationship = relationships[node["id"]], relationship.hasType("slideLayout"), !relationship.isExternal else { return nil }
            return relationship.target
        }
        if layoutPaths.isEmpty { layoutPaths = relationships.all("slideLayout").filter { !$0.isExternal }.map(\.target) }
        for layoutPath in layoutPaths where layoutsByPath[PPTXPackageReader.key(layoutPath)] == nil {
            guard let layout = try readLayout(layoutPath, theme: theme, data: data, masterMap: map) else { continue }
            layoutsByPath[PPTXPackageReader.key(layoutPath)] = (layout.id, id)
            theme.layouts.append(layout)
        }
        if theme.layouts.isEmpty {
            theme.layouts.append(Layout(name: LayoutKind.blank.title, kind: .blank))
        }
        themes.append(theme)
    }

    private mutating func readLayout(_ path: String, theme: Theme, data: PPTXThemeData, masterMap: PPTXColorMap) throws -> Layout? {
        guard let root = try package.xml(path), root.name == "sldLayout" else { return nil }
        let relationships = package.relationshipsIfReadable(of: path)
        if PPTXAnimationReader.animates(root) { package.warnings.insert(.animations) }
        let map = masterMap.overridden(by: root.child("clrMapOvr"))
        var context = PPTXPartContext(package: package, path: path, relationships: relationships, map: map, theme: data)
        context.recordsListStyles = true
        context.parentGeometry = { ref in theme.placeholder(matching: ref)?.shape?.geometry }
        let slideData = root.child("cSld")
        let fileName = slideData?["name"].flatMap { $0.isEmpty ? nil : $0 }
        let matchingName = root["matchingName"].flatMap { $0.isEmpty ? nil : $0 }
        // Some apps name layouts by identifier ("TITLE") and keep the display name in matchingName.
        var kind = LayoutKind(fileType: nil, name: fileName)
        if kind == .custom { kind = LayoutKind(fileType: nil, name: matchingName) }
        if kind == .custom { kind = LayoutKind(fileType: root["type"], name: nil) }
        let layout = Layout(name: matchingName ?? fileName ?? kind.title, kind: kind, elements: context.elements(in: slideData?.child("spTree")),
                            background: context.fills().background(slideData?.child("bg")),
                            showsThemeElements: PPTXValue.bool(root["showMasterSp"]) ?? true)
        sources.layouts[layout.id] = PPTXColorMapSources.Part(
            map: map, background: slideData?.child("bg").map { PPTXColorMapSources.Background(node: $0, relationships: relationships) })
        return layout
    }

    // MARK: Slides

    private mutating func readSlide(_ path: String) throws -> Slide? {
        guard let id = package.slideIDs[PPTXPackageReader.key(path)] else { return nil }
        guard let root = try package.xml(path), root.name == "sld" else {
            package.warnings.insert(.otherContent)
            return nil
        }
        let relationships = package.relationshipsIfReadable(of: path)

        var themeIndex = 0
        var layout = themes[0].layouts[0]
        if let target = relationships.first("slideLayout")?.target, let found = layoutsByPath[PPTXPackageReader.key(target)],
           let index = themes.firstIndex(where: { $0.id == found.theme }), let match = themes[index].layout(id: found.layout) {
            themeIndex = index
            layout = match
        }
        let theme = themes[themeIndex]
        let masterMap = sources.masters[theme.id]?.map ?? .standard
        let map = masterMap.overridden(by: root.child("clrMapOvr"))
        var context = PPTXPartContext(package: package, path: path, relationships: relationships, map: map,
                                      theme: themeData[theme.id] ?? PPTXThemeData.fallback)
        context.parentGeometry = { ref in
            (layout.placeholder(matching: ref) ?? theme.placeholder(matching: ref))?.shape?.geometry
        }
        let slideData = root.child("cSld")
        var slide = Slide(id: id, layoutID: layout.id, elements: context.elements(in: slideData?.child("spTree")),
                          background: context.fills().background(slideData?.child("bg")),
                          isSkipped: PPTXValue.bool(root["show"]) == false)
        sources.slides[id] = PPTXColorMapSources.Part(map: map, background: nil)
        readMotion(root, into: &slide)
        if relationships.all.contains(where: { $0.hasType("comments") }) {
            // A placeholder that sits where its layout's (or master's) does is placed from there.
            let context = PPTXComments.SlideContext(elements: slide.elements, package: package) { element in
                if let placement = element.placement { return placement.frame.standardized }
                guard let ref = element.placeholder else { return .zero }
                return [layout.placeholder(matching: ref), theme.placeholder(matching: ref)].lazy.compactMap { $0?.placement }.first?.frame.standardized ?? .zero
            }
            slide.comments = PPTXComments.threads(relationships: relationships, context: context, authors: commentAuthors, package: package,
                                                  usedIDs: &commentIDs)
        }
        if let notesPath = relationships.first("notesSlide")?.target { slide.notes = notes(notesPath) }
        return slide
    }

    /// The slide's transition and animations, mapped to the supported ones, and how its clips play; what can't be kept
    /// leaves a warning.
    private func readMotion(_ root: XNode, into slide: inout Slide) {
        let transition = PPTXTransitions.read(root)
        slide.transition = transition.transition
        if transition.hasUnsupported { package.warnings.insert(.transitions) }
        var elements: [String: SlideElement] = [:]
        for element in slide.elements {
            if let id = package.shapeIDs[element.id], elements[id] == nil { elements[id] = element }
        }
        var clips: [String: UUID] = [:]
        func findClips(_ elements: [SlideElement]) {
            for element in elements {
                if case .group(let children) = element.content { findClips(children) }
                guard element.media != nil, let id = package.shapeIDs[element.id], clips[id] == nil else { continue }
                clips[id] = element.id
            }
        }
        findClips(slide.elements)
        let motion = PPTXAnimationReader.read(root, elements: elements, clips: clips)
        slide.animations = motion.animations
        if motion.hasUnsupported { package.warnings.insert(.animations) }
        guard !clips.isEmpty else { return }
        // A clip with no play command plays only when it's clicked.
        func apply(_ elements: inout [SlideElement]) {
            for index in elements.indices {
                switch elements[index].content {
                case .group(var children):
                    apply(&children)
                    elements[index].content = .group(children)
                case .media(var clip):
                    let id = elements[index].id
                    if let node = motion.mediaNodes[id] { PPTXMedia.apply(mediaNode: node, to: &clip) }
                    clip.playback = motion.playback[id] ?? .manually
                    elements[index].content = .media(clip)
                default:
                    continue
                }
            }
        }
        apply(&slide.elements)
    }

    /// The text of a notes slide's body placeholder, read with the notes master's color map.
    private mutating func notes(_ path: String) -> TextBody {
        guard let root = try? package.xml(path), root.name == "notes" else { return .empty }
        let relationships = package.relationshipsIfReadable(of: path)
        var map = PPTXColorMap.standard
        if let masterPath = relationships.first("notesMaster")?.target {
            let key = PPTXPackageReader.key(masterPath)
            if let known = notesMaps[key] {
                map = known
            } else {
                map = (try? package.xml(masterPath))?.child("clrMap").map { PPTXColorMap(node: $0) } ?? .standard
                notesMaps[key] = map
            }
        }
        map = map.overridden(by: root.child("clrMapOvr"))
        let context = PPTXPartContext(package: package, path: path, relationships: relationships, map: map, theme: PPTXThemeData.fallback)
        func body(in container: XNode?, depth: Int) -> XNode? {
            guard let container, depth < 8 else { return nil }
            for child in container.children {
                if child.name == "sp", PPTXPartContext.placeholder(child.child("nvSpPr")?.child("nvPr"))?.type == .body {
                    return child.child("txBody")
                }
                if child.name == "grpSp", let found = body(in: child, depth: depth + 1) { return found }
            }
            return nil
        }
        guard let txBody = body(in: root.child("cSld")?.child("spTree"), depth: 0) else { return .empty }
        return context.text.body(txBody)
    }
}
