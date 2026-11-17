import Foundation

/// The eleven standard layouts, and custom ones. The raw values are the identifiers files name them by.
public enum LayoutKind: String, Codable, CaseIterable, Sendable {
    case title = "TITLE"
    case sectionHeader = "SECTION_HEADER"
    case titleAndBody = "TITLE_AND_BODY"
    case titleAndTwoColumns = "TITLE_AND_TWO_COLUMNS"
    case titleOnly = "TITLE_ONLY"
    case oneColumnText = "ONE_COLUMN_TEXT"
    case mainPoint = "MAIN_POINT"
    case sectionTitleAndDescription = "SECTION_TITLE_AND_DESCRIPTION"
    case caption = "CAPTION_ONLY"
    case bigNumber = "BIG_NUMBER"
    case blank = "BLANK"
    case custom = "CUSTOM"

    /// The names in the Layout menu.
    public var title: String {
        switch self {
        case .title: "Title slide"
        case .sectionHeader: "Section header"
        case .titleAndBody: "Title and body"
        case .titleAndTwoColumns: "Title and two columns"
        case .titleOnly: "Title only"
        case .oneColumnText: "One column text"
        case .mainPoint: "Main point"
        case .sectionTitleAndDescription: "Section title and description"
        case .caption: "Caption"
        case .bigNumber: "Big number"
        case .blank: "Blank"
        case .custom: "Custom"
        }
    }

    /// PresentationML's layout type (ST_SlideLayoutType) for this layout. Layouts without an
    /// Office equivalent are custom layouts, recognized again by name when read.
    public var fileType: String {
        switch self {
        case .title: "title"
        case .sectionHeader: "secHead"
        case .titleAndBody: "tx"
        case .titleAndTwoColumns: "twoColTx"
        case .titleOnly: "titleOnly"
        case .blank: "blank"
        case .oneColumnText, .mainPoint, .sectionTitleAndDescription, .caption, .bigNumber, .custom: "cust"
        }
    }

    /// Recognizes a layout from its file type and name (its identifier or its display name).
    public init(fileType: String?, name: String?) {
        let key = (name ?? "").uppercased().replacingOccurrences(of: " ", with: "_")
        if let kind = LayoutKind(rawValue: key), kind != .custom {
            self = kind
            return
        }
        if let name, let kind = LayoutKind.allCases.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            self = kind
            return
        }
        switch fileType {
        case "title": self = .title
        case "secHead": self = .sectionHeader
        case "tx", "obj": self = .titleAndBody
        case "twoColTx", "twoObj": self = .titleAndTwoColumns
        case "titleOnly": self = .titleOnly
        case "blank": self = .blank
        default: self = .custom
        }
    }
}

/// The fonts a theme names for headings (major) and body text (minor).
public struct FontScheme: Hashable, Codable, Sendable {
    public var name: String
    public var major: String
    public var minor: String

    public init(name: String, major: String, minor: String) {
        self.name = name
        self.major = major
        self.minor = minor
    }

    /// Turns a theme font reference ("+mj-lt", "+mn-ea" …) into a family name; other names pass through.
    public func resolve(_ family: String) -> String {
        if family.hasPrefix("+mj") { return major }
        if family.hasPrefix("+mn") { return minor }
        return family
    }
}

public struct Layout: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: LayoutKind
    /// Placeholders and decorations, drawn behind a slide's own elements.
    public var elements: [SlideElement]
    /// Nil follows the theme.
    public var background: Fill?
    /// Whether slides using this layout also show the theme's own decorations.
    public var showsThemeElements: Bool

    public init(id: UUID = UUID(), name: String, kind: LayoutKind, elements: [SlideElement] = [], background: Fill? = nil,
                showsThemeElements: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.elements = elements
        self.background = background
        self.showsThemeElements = showsThemeElements
    }
}

/// A theme: colors, fonts, background, text styles, decorations and layouts (a slide master in Office terms).
public struct Theme: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var colors: ColorScheme
    public var fonts: FontScheme
    public var background: Fill
    /// Placeholders and decorations on every slide whose layout shows them.
    public var elements: [SlideElement]
    /// Default formatting for titles, for body placeholders and for all other text.
    public var titleStyle: ListStyle
    public var bodyStyle: ListStyle
    public var otherStyle: ListStyle
    public var layouts: [Layout]

    public init(id: UUID = UUID(), name: String, colors: ColorScheme, fonts: FontScheme, background: Fill,
                elements: [SlideElement] = [], titleStyle: ListStyle = .empty, bodyStyle: ListStyle = .empty,
                otherStyle: ListStyle = .empty, layouts: [Layout] = []) {
        self.id = id
        self.name = name
        self.colors = colors
        self.fonts = fonts
        self.background = background
        self.elements = elements
        self.titleStyle = titleStyle
        self.bodyStyle = bodyStyle
        self.otherStyle = otherStyle
        self.layouts = layouts
    }

    public func layout(id: UUID) -> Layout? { layouts.first { $0.id == id } }
    public func layout(kind: LayoutKind) -> Layout? { layouts.first { $0.kind == kind } }
    public func layoutIndex(id: UUID) -> Int? { layouts.firstIndex { $0.id == id } }
}

public struct Slide: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// A layout in one of the presentation's themes.
    public var layoutID: UUID
    /// In drawing order: later elements are in front.
    public var elements: [SlideElement]
    /// Nil follows the layout and theme.
    public var background: Fill?
    /// Speaker notes.
    public var notes: TextBody
    /// Slide ▸ Skip slide: kept out of slideshows.
    public var isSkipped: Bool
    /// How the slide arrives in a slideshow; nil is no transition.
    public var transition: SlideTransition?
    /// Object animations, in the order they play.
    public var animations: [SlideAnimation]
    /// Comment threads, in the order they were made.
    public var comments: [CommentThread]

    public init(id: UUID = UUID(), layoutID: UUID, elements: [SlideElement] = [], background: Fill? = nil,
                notes: TextBody = .empty, isSkipped: Bool = false, transition: SlideTransition? = nil,
                animations: [SlideAnimation] = [], comments: [CommentThread] = []) {
        self.id = id
        self.layoutID = layoutID
        self.elements = elements
        self.background = background
        self.notes = notes
        self.isSkipped = isSkipped
        self.transition = transition
        self.animations = animations
        self.comments = comments
    }

    private enum CodingKeys: String, CodingKey {
        case id, layoutID, elements, background, notes, isSkipped, transition, animations, comments
    }

    /// Slides copied before transitions, animations and comments existed decode without them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layoutID = try container.decode(UUID.self, forKey: .layoutID)
        elements = try container.decode([SlideElement].self, forKey: .elements)
        background = try container.decodeIfPresent(Fill.self, forKey: .background)
        notes = try container.decode(TextBody.self, forKey: .notes)
        isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        transition = try container.decodeIfPresent(SlideTransition.self, forKey: .transition)
        animations = try container.decodeIfPresent([SlideAnimation].self, forKey: .animations) ?? []
        comments = try container.decodeIfPresent([CommentThread].self, forKey: .comments) ?? []
    }

    public func element(id: UUID) -> SlideElement? { elements.first { $0.id == id } }
    public func elementIndex(id: UUID) -> Int? { elements.firstIndex { $0.id == id } }
}

/// An image or other file a presentation embeds.
public struct MediaItem: Hashable, Codable, Sendable {
    public var data: Data
    /// A MIME type such as "image/png".
    public var contentType: String

    public init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    /// The usual file extension for the content type ("png", "jpeg" …).
    public var fileExtension: String {
        switch contentType {
        case "image/png": "png"
        case "image/jpeg", "image/jpg": "jpeg"
        case "image/gif": "gif"
        case "image/bmp": "bmp"
        case "image/tiff": "tiff"
        case "image/svg+xml": "svg"
        case "image/webp": "webp"
        case "image/x-emf", "image/emf": "emf"
        case "image/x-wmf", "image/wmf": "wmf"
        case "video/mp4": "mp4"
        case "video/quicktime": "mov"
        case "video/x-m4v": "m4v"
        case "video/x-msvideo", "video/avi": "avi"
        case "video/x-ms-wmv": "wmv"
        case "audio/mpeg", "audio/mp3": "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": "m4a"
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/aiff", "audio/x-aiff": "aiff"
        case "audio/aac": "aac"
        case "audio/x-ms-wma": "wma"
        default: "bin"
        }
    }

    public var isVideo: Bool { contentType.hasPrefix("video/") }
    public var isAudio: Bool { contentType.hasPrefix("audio/") }

    /// Recognizes common image, video and sound formats from their first bytes.
    public static func contentType(sniffing data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))
        if let media = mediaType(bytes) { return media }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.starts(with: [0x42, 0x4D]) { return "image/bmp" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        if bytes.count >= 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if let text = String(data: data.prefix(512), encoding: .utf8), text.contains("<svg") { return "image/svg+xml" }
        return nil
    }

    /// MPEG-4 and QuickTime movies and sounds, MP3, WAV and AIFF.
    private static func mediaType(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 12 else { return nil }
        let box = String(decoding: bytes[4..<8], as: UTF8.self)
        if box == "ftyp" {
            switch String(decoding: bytes[8..<12], as: UTF8.self) {
            case "qt  ": return "video/quicktime"
            case "M4A ", "M4B ": return "audio/mp4"
            case "M4V ", "M4VH", "M4VP": return "video/x-m4v"
            // HEIF and AVIF pictures share the box.
            case "heic", "heix", "hevc", "mif1", "msf1", "avif", "avis": return nil
            default: return "video/mp4"
            }
        }
        if ["moov", "mdat", "wide", "pnot"].contains(box) { return "video/quicktime" }
        let first4 = String(decoding: bytes[0..<4], as: UTF8.self), last4 = String(decoding: bytes[8..<12], as: UTF8.self)
        if first4 == "RIFF", last4 == "WAVE" { return "audio/wav" }
        if first4 == "RIFF", last4 == "AVI " { return "video/x-msvideo" }
        if first4 == "FORM", last4 == "AIFF" || last4 == "AIFC" { return "audio/aiff" }
        if bytes.starts(with: Array("ID3".utf8)) { return "audio/mpeg" }
        if bytes[0] == 0xFF, [0xFB, 0xFA, 0xF3, 0xF2].contains(bytes[1]) { return "audio/mpeg" }
        return nil
    }
}

/// A guide line from View ▸ Guides. Guides belong to the presentation and show on every slide.
public struct Guide: Hashable, Codable, Sendable, Identifiable {
    public enum Orientation: String, Codable, Sendable {
        case horizontal, vertical
    }

    public var id: UUID
    public var orientation: Orientation
    /// Points from the slide's left edge (vertical guides) or its top edge (horizontal guides).
    public var position: Double
    /// Nil is the default guide color.
    public var color: RGBColor?

    public init(id: UUID = UUID(), orientation: Orientation, position: Double, color: RGBColor? = nil) {
        self.id = id
        self.orientation = orientation
        self.position = position
        self.color = color
    }
}

public struct Presentation: Hashable, Codable, Sendable {
    public var slideSize: SlideSize
    /// Usually one; files made elsewhere can have several masters.
    public var themes: [Theme]
    public var slides: [Slide]
    public var media: [MediaID: MediaItem]
    /// The presentation-wide text defaults beneath every theme's styles.
    public var defaultTextStyle: ListStyle
    /// The document title stored in the file's properties.
    public var title: String?
    /// View ▸ Guides: lines objects snap to, on every slide.
    public var guides: [Guide]

    public init(slideSize: SlideSize = .widescreen, themes: [Theme], slides: [Slide] = [], media: [MediaID: MediaItem] = [:],
                defaultTextStyle: ListStyle = .empty, title: String? = nil, guides: [Guide] = []) {
        self.slideSize = slideSize
        self.themes = themes
        self.slides = slides
        self.media = media
        self.defaultTextStyle = defaultTextStyle
        self.title = title
        self.guides = guides
    }

    private enum CodingKeys: String, CodingKey {
        case slideSize, themes, slides, media, defaultTextStyle, title, guides
    }

    /// Presentations saved before guides existed decode without them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slideSize = try container.decode(SlideSize.self, forKey: .slideSize)
        themes = try container.decode([Theme].self, forKey: .themes)
        slides = try container.decode([Slide].self, forKey: .slides)
        media = try container.decode([MediaID: MediaItem].self, forKey: .media)
        defaultTextStyle = try container.decodeIfPresent(ListStyle.self, forKey: .defaultTextStyle) ?? .empty
        title = try container.decodeIfPresent(String.self, forKey: .title)
        guides = try container.decodeIfPresent([Guide].self, forKey: .guides) ?? []
    }

    /// What File ▸ New presentation makes: the Simple Light theme and one title slide.
    public static func makeDefault() -> Presentation {
        let theme = BuiltInThemes.simpleLight()
        var presentation = Presentation(themes: [theme], defaultTextStyle: BuiltInThemes.defaultTextStyle)
        if let layout = theme.layout(kind: .title) {
            presentation.slides = [presentation.makeSlide(layoutID: layout.id)]
        }
        return presentation
    }

    // MARK: Lookups

    public func slideIndex(id: UUID) -> Int? { slides.firstIndex { $0.id == id } }

    /// The theme and layout indexes of a layout id.
    public func layoutLocation(_ layoutID: UUID) -> (theme: Int, layout: Int)? {
        for (themeIndex, theme) in themes.enumerated() {
            if let layoutIndex = theme.layoutIndex(id: layoutID) { return (themeIndex, layoutIndex) }
        }
        return nil
    }

    public func layout(id: UUID) -> Layout? {
        layoutLocation(id).map { themes[$0.theme].layouts[$0.layout] }
    }

    /// The theme a slide uses (the first theme if its layout is missing).
    public func theme(for slide: Slide) -> Theme {
        if let location = layoutLocation(slide.layoutID) { return themes[location.theme] }
        return themes.first ?? BuiltInThemes.simpleLight()
    }

    public func layout(for slide: Slide) -> Layout? { layout(id: slide.layoutID) }

    // MARK: Media

    /// Stores media once and returns its id; identical data reuses the existing item.
    public mutating func addMedia(_ data: Data, contentType: String) -> MediaID {
        if let existing = media.first(where: { $0.value.data == data })?.key { return existing }
        let id = UUID().uuidString
        media[id] = MediaItem(data: data, contentType: contentType)
        return id
    }

    /// Every media id slides, layouts, themes and backgrounds still use.
    public var usedMediaIDs: Set<MediaID> {
        var used = Set<MediaID>()
        func add(_ fill: Fill?) { if let id = fill?.mediaID { used.insert(id) } }
        for theme in themes {
            add(theme.background)
            theme.elements.forEach { used.formUnion($0.mediaIDs) }
            for layout in theme.layouts {
                add(layout.background)
                layout.elements.forEach { used.formUnion($0.mediaIDs) }
            }
        }
        for slide in slides {
            add(slide.background)
            slide.elements.forEach { used.formUnion($0.mediaIDs) }
        }
        return used
    }

    /// Drops media nothing uses any more.
    public mutating func removeUnusedMedia() {
        let used = usedMediaIDs
        media = media.filter { used.contains($0.key) }
    }
}
