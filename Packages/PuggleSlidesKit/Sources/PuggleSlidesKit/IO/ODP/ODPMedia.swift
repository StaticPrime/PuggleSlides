import Foundation

/// Videos and sounds in OpenDocument presentations, kept as LibreOffice Impress keeps them (xmloff's
/// `XMLShapeExport::ImpExportMediaShape` and `SdXMLPluginShapeContext`): a `draw:frame` holding a `draw:plugin` whose
/// `xlink:href` is the movie or sound in the package's Media folder (stored uncompressed, its type in the manifest), with
/// the `draw:param`s Loop and Mute ("true" or "false") and VolumeDB (whole decibels: 0 is full volume, -40 and less
/// silence, as LibreOffice's players take it), and after the plugin the poster as a `draw:image`, which Impress reads as
/// the media's preview. The plugin's `draw:mime-type` is LibreOffice's generic media type, which every version of Impress
/// reads as media (newer ones also take a media file's own type, and work out the precise type from the file's name).
///
/// Impress plays a media object as its slide appears. Media effects in the slide's timing say otherwise, as Impress
/// writes them (preset class `media-call` holding an `anim:command`): Start (`ooo-media-start`, the play command) as the
/// slide appears or on a click in the main sequence, and Toggle Pause (`ooo-media-toggle-pause`) in a sequence the clip's
/// own click triggers. A clip with no command starts by itself.
///
/// What neither ODF nor Impress has is in PuggleSlides' own attributes on the plugin: the trim (`psext:start`,
/// `psext:end`, in seconds), the exact volume (`psext:volume`, 0 to 1, which VolumeDB rounds), `psext:hides-when-presenting`
/// and `psext:stops-on-slide-change`. LibreOffice ignores them, and drops them when it saves.
enum ODPMedia {
    /// LibreOffice's media type for media objects (`AVMEDIA_MIMETYPE_COMMON`).
    static let pluginType = "application/vnd.sun.star.media"
    static let maxClipSize = 1 << 30
    /// LibreOffice's quietest volume, which its players play silent.
    static let silentDecibels = -40

    /// A plugin type LibreOffice plays as media: its generic type, or a movie's or sound's.
    static func isMedia(_ declared: String) -> Bool {
        let type = declared.lowercased()
        return type == pluginType || type.hasPrefix("video/") || type.hasPrefix("audio/")
    }

    /// A volume from 0 to 1 in whole decibels, -40 to 0.
    static func decibels(_ volume: Double) -> Int {
        guard volume.isFinite, volume > 0 else { return silentDecibels }
        return PPTXValue.clamped(20 * log10(min(volume, 1)), silentDecibels...0)
    }

    static func volume(decibels: Int) -> Double {
        decibels <= silentDecibels ? 0 : min(pow(10, Double(min(decibels, 0)) / 20), 1)
    }
}

// MARK: - Reading

extension ODPElementReader {
    /// A clip from a frame's plugin. Nil when the plugin isn't media, or its media is outside the package, missing or too
    /// large, after noting what's lost. Placeholders' media becomes a clip in their place.
    func clipElement(_ node: ODFNode, plugin: ODFNode, placement: Placement, ids: IDs) -> SlideElement? {
        let declared = (plugin["draw:mime-type"] ?? "").lowercased()
        guard ODPMedia.isMedia(declared) else {
            document.warnings.insert(.embeddedObjects)
            return nil
        }
        let href = plugin["xlink:href"] ?? ""
        let declaredKind: MediaClip.Kind? = declared.hasPrefix("audio/") ? .audio : declared.hasPrefix("video/") ? .video : nil
        guard let mediaID = document.media(at: href, maxSize: ODPMedia.maxClipSize, notesMissing: false) else {
            let kind = declaredKind ?? (PPTXMedia.isAudio(path: href) ? .audio : .video)
            document.warnings.insert(kind == .audio ? .audio : .video)
            return nil
        }
        let item = document.media[mediaID]
        let kind: MediaClip.Kind = item?.isAudio == true ? .audio : item?.isVideo == true ? .video : declaredKind ?? .video
        // Impress plays media as the slide appears, unless the slide's timing says otherwise.
        var clip = MediaClip(kind: kind, mediaID: mediaID, playback: .automatically)
        for param in plugin.children("draw:param") {
            let value = param["draw:value"]?.trimmingCharacters(in: .whitespaces) ?? ""
            switch param["draw:name"] {
            case "Loop": clip.loops = ODFValue.bool(value) ?? false
            case "Mute": clip.isMuted = ODFValue.bool(value) ?? false
            case "VolumeDB": if let decibels = Int(value) ?? Double(value).map({ PPTXValue.clamped($0, -32_768...32_767) }) {
                clip.volume = ODPMedia.volume(decibels: decibels)
            }
            default: continue
            }
        }
        if let volume = plugin["psext:volume"].flatMap(Double.init), volume.isFinite { clip.volume = min(max(volume, 0), 1) }
        if let start = ODFValue.seconds(plugin["psext:start"]), start.isFinite, start > 0 { clip.start = min(start, 1e7) }
        if let end = ODFValue.seconds(plugin["psext:end"]), end.isFinite, end > (clip.start ?? 0) { clip.end = min(end, 1e7) }
        clip.hidesWhenPresenting = ODFValue.bool(plugin["psext:hides-when-presenting"]) ?? false
        clip.stopsOnSlideChange = ODFValue.bool(plugin["psext:stops-on-slide-change"]) ?? true
        // The preview Impress shows until it plays, unless it's the default picture for clips without a poster.
        if let preview = node.elements.first(where: { $0.name == "draw:image" }), let path = preview["xlink:href"],
           document.data(at: path, maxSize: MediaPictures.maxDefaultSize).map(MediaPictures.isDefault) != true {
            clip.posterID = document.media(at: path, maxSize: ODPDocumentReader.maxMediaSize, notesMissing: false)
        }
        return SlideElement(id: ids.own, name: node["draw:name"] ?? "", placement: placement, content: .media(clip))
    }
}

// MARK: - Writing

extension ODPContentWriter {
    /// A clip as Impress writes a media object: a frame with the plugin and its parameters, then the poster.
    func clip(_ element: SlideElement, _ clip: MediaClip, page: Page, into xml: inout XMLWriter) {
        guard let path = document.mediaPath(clip.mediaID) else { return }
        let placement = Self.standardized(page.style(element).placement)
        var own = ODFStyle(family: "graphic", parent: document.themeMasterName(page.themeIndex) + "-other")
        own.graphic = document.strokeProperties(Outline.none, colors: page.theme.colors)
        own.graphic.fill = "none"
        let styleName = page.styles.name(own, kind: "gr")
        var unflipped = placement
        unflipped.flipHorizontal = false
        unflipped.flipVertical = false
        xml.raw("<draw:frame")
        if !element.name.isEmpty { xml.attribute("draw:name", element.name) }
        xml.attribute("draw:style-name", styleName)
        xml.raw(" draw:layer=\"\(page.layer)\"")
        identity(element, page: page, into: &xml)
        Self.geometry(unflipped, into: &xml)
        xml.raw("><draw:plugin")
        xml.attribute("xlink:href", path)
        xml.raw(" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\" draw:mime-type=\"\(ODPMedia.pluginType)\"")
        // PuggleSlides' own settings.
        var settings = XMLWriter(fragmentCapacity: 256)
        if let start = clip.start, start.isFinite, start >= 0.0005 { settings.raw(" psext:start=\"\(ODFFormat.seconds(min(start, 1e7)))\"") }
        if let end = clip.end, end.isFinite, end >= 0.0005 { settings.raw(" psext:end=\"\(ODFFormat.seconds(min(end, 1e7)))\"") }
        let volume = clip.volume.isFinite ? min(max(clip.volume, 0), 1) : 1
        if abs(ODPMedia.volume(decibels: ODPMedia.decibels(volume)) - volume) > 0.000_001 {
            settings.raw(" psext:volume=\"\(ODFFormat.number(volume, decimals: 6))\"")
        }
        if clip.hidesWhenPresenting { settings.raw(" psext:hides-when-presenting=\"true\"") }
        if !clip.stopsOnSlideChange { settings.raw(" psext:stops-on-slide-change=\"false\"") }
        if !settings.bytes.isEmpty {
            xml.raw(" xmlns:psext=\"\(ODPComments.puggleExtension)\"")
            xml.append(settings)
        }
        xml.raw("><draw:param draw:name=\"Loop\" draw:value=\"\(clip.loops)\"/><draw:param draw:name=\"Mute\" draw:value=\"\(clip.isMuted)\"/>")
        xml.raw("<draw:param draw:name=\"VolumeDB\" draw:value=\"\(ODPMedia.decibels(volume))\"/></draw:plugin>")
        if let posterID = clip.posterID, let poster = document.mediaPath(posterID), let item = document.presentation.media[posterID] {
            xml.raw("<draw:image")
            xml.attribute("xlink:href", poster)
            xml.raw(" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"")
            xml.attribute("draw:mime-type", ODPDocumentWriter.mediaType(item.contentType, path: poster))
            xml.raw("/>")
        }
        altText(element, into: &xml)
        xml.raw("</draw:frame>")
    }
}
