import CoreGraphics
import Foundation
@testable import PuggleSlidesKit

/// Presentations as they show: every slide's elements, decorations, text and motion with everything inherited
/// resolved, theme colors as RGB and theme fonts as family names. Ids and element names are left out. Two
/// presentations with the same rendering show the same slides.
enum ODPRendering {
    struct Character: Equatable, CustomStringConvertible {
        var font: String
        var size: Double
        var bold, italic, underline, strikethrough: Bool
        var color: String
        var highlight: String?
        var baseline: BaselineShift
        var link: String?

        var description: String {
            "\(font) \(size)\(bold ? " b" : "")\(italic ? " i" : "")\(underline ? " u" : "")\(strikethrough ? " s" : "") \(color)"
                + (highlight.map { " hl \($0)" } ?? "") + (baseline == .normal ? "" : " \(baseline)") + (link.map { " -> \($0)" } ?? "")
        }
    }

    struct Run: Equatable {
        var text: String
        var character: Character
        var isField: Bool
    }

    struct Paragraph: Equatable {
        var level: Int
        var alignment: TextAlignment
        var spacing: [Double]
        var bullet: String?
        var bulletLook: String?
        var runs: [Run]
        var end: Character
    }

    struct Element: Equatable {
        var kind: String
        var placeholder: PlaceholderType?
        var frame: [Double]
        var flips: [Bool]
        var geometry: String
        var fill: String
        var outline: String
        var body: String?
        var text: [Paragraph]?
        var flags: [Bool]
        var picture: String?
        var alt: [String?]
        var children: [Element]
        /// A table's columns, rows, cells and the borders that show; a chart's kind, numbers and look.
        var object: [String] = []
    }

    struct SlideView: Equatable {
        var theme: String
        var layout: String
        var background: String
        var skipped: Bool
        var transition: String
        var animations: [String]
        var notes: [Paragraph]
        var backdrop: [Element]
        var elements: [Element]
        /// Each thread: its element's place among the slide's ("2", "3.1" in a group), resolved, position, and each
        /// comment's author, date to the second and text.
        var comments: [String] = []
    }

    static func comments(_ slide: Slide) -> [String] {
        var places: [UUID: String] = [:]
        func number(_ elements: [SlideElement], prefix: String) {
            for (index, element) in elements.enumerated() {
                places[element.id] = prefix + "\(index + 1)"
                if let children = element.children { number(children, prefix: prefix + "\(index + 1).") }
            }
        }
        number(slide.elements, prefix: "")
        return slide.comments.map { thread in
            let comments = thread.comments.map { "\($0.author)|\(Int($0.date.timeIntervalSince1970.rounded(.down)))|\($0.text)" }
            return "about \(thread.elementID.flatMap { places[$0] } ?? "slide") resolved \(thread.isResolved) at "
                + "\(round(thread.position.x)),\(round(thread.position.y)): " + comments.joined(separator: " / ")
        }
    }

    static func round(_ value: Double, _ step: Double = 0.01) -> Double {
        let result = (value / step).rounded() * step
        return result == 0 ? 0 : result
    }

    static func color(_ resolved: ResolvedColor) -> String {
        resolved.rgb.hex + (resolved.alpha < 0.999 ? String(format: "@%.2f", resolved.alpha) : "")
    }

    static func fill(_ fill: Fill, _ colors: ColorScheme, media: [MediaID: MediaItem]) -> String {
        switch fill {
        case .none: return "none"
        case .solid(let color): return "solid " + self.color(color.resolved(colors))
        case .gradient(let gradient):
            let stops = gradient.stops.sorted { $0.position < $1.position }.map { "\(round($0.position)):\(self.color($0.color.resolved(colors)))" }
            switch gradient.kind {
            case .linear(let angle): return "linear \(round(Placement.normalized(angle), 0.1)) " + stops.joined(separator: " ")
            case .radial: return "radial " + stops.joined(separator: " ")
            }
        case .picture(let picture):
            return "picture \(media[picture.mediaID]?.data.hashValue ?? 0) \(picture.stretches)"
        }
    }

    static func outline(_ outline: Outline, _ colors: ColorScheme, media: [MediaID: MediaItem]) -> String {
        guard outline.isVisible, !(outline.fill.mediaID != nil) else { return "none" }
        var color = "?"
        switch outline.fill {
        case .solid(let solid): color = self.color(solid.resolved(colors))
        case .gradient(let gradient): color = gradient.stops.min { $0.position < $1.position }.map { self.color($0.color.resolved(colors)) } ?? "?"
        default: break
        }
        return "\(color) \(round(outline.width)) \(outline.dash) \(outline.head) \(outline.tail)"
    }

    /// Geometry as presets without default adjust values, or the outline's points.
    static func geometry(_ geometry: ShapeGeometry, size: SlideSize) -> String {
        switch geometry {
        case .preset(let name, let adjustments):
            let defaults = PresetGeometry.defaultAdjustments(name)
            let own = adjustments.filter { entry in defaults[entry.key].map { abs($0 - entry.value) >= 0.5 } ?? true }
            return name + own.keys.sorted().map { " \($0)=\(Int(own[$0]!.rounded()))" }.joined()
        case .custom:
            let rect = CGRect(x: 0, y: 0, width: max(abs(size.width), 1), height: max(abs(size.height), 1))
            var points: [String] = []
            for part in PresetGeometry.paths(for: geometry, in: rect) {
                var description = "[\(part.fill.rawValue) \(part.stroke)"
                var current = CGPoint.zero
                func add(_ point: CGPoint) { description += " \(Int((Double(point.x) * 10).rounded())),\(Int((Double(point.y) * 10).rounded()))" }
                part.path.applyWithBlock { element in
                    let points = element.pointee.points
                    switch element.pointee.type {
                    case .moveToPoint, .addLineToPoint:
                        add(points[0])
                        current = points[0]
                    case .addQuadCurveToPoint:
                        // As the cubic it equals.
                        add(CGPoint(x: current.x + 2 / 3 * (points[0].x - current.x), y: current.y + 2 / 3 * (points[0].y - current.y)))
                        add(CGPoint(x: points[1].x + 2 / 3 * (points[0].x - points[1].x), y: points[1].y + 2 / 3 * (points[0].y - points[1].y)))
                        add(points[1])
                        current = points[1]
                    case .addCurveToPoint:
                        add(points[0])
                        add(points[1])
                        add(points[2])
                        current = points[2]
                    case .closeSubpath:
                        description += " Z"
                    @unknown default:
                        break
                    }
                }
                points.append(description + "]")
            }
            let text = PresetGeometry.textRect(for: geometry, in: rect)
            return "custom " + points.joined() + " text \(Int(text.minX)),\(Int(text.minY)),\(Int(text.width)),\(Int(text.height))"
        }
    }

    static func character(_ style: ResolvedCharacterStyle, slides: [UUID: Int]) -> Character {
        var link: String?
        switch style.link {
        case .url(let address)?: link = address
        case .slide(let id)?: link = "slide \(slides[id] ?? -1)"
        case nil: link = nil
        }
        return Character(font: style.fontFamily, size: round(style.fontSize), bold: style.bold, italic: style.italic, underline: style.underline,
                         strikethrough: style.strikethrough, color: style.color.rgb.hex, highlight: style.highlight?.rgb.hex, baseline: style.baseline,
                         link: link)
    }

    /// Text without the shrink-to-fit scale, which apps work out again when they lay the text out.
    static func unscaled(_ style: ElementStyle) -> ElementStyle {
        func strip(_ element: SlideElement) -> SlideElement {
            var copy = element
            if var text = copy.shape?.text {
                text.properties.fontScale = nil
                text.properties.lineSpacingReduction = nil
                copy.shape?.text = text
            }
            return copy
        }
        return ElementStyle(element: strip(style.element), parents: style.parents.map(strip), theme: style.theme, defaultTextStyle: style.defaultTextStyle)
    }

    static func paragraphs(_ style: ElementStyle, body: TextBody, slides: [UUID: Int]) -> [Paragraph] {
        unscaled(style).resolvedParagraphs(body, slideNumber: 1).map { paragraph in
            var runs: [Run] = []
            for run in paragraph.runs where !run.text.isEmpty || run.field != nil {
                let item = Run(text: run.field == .slideNumber ? "#" : run.text, character: character(run.style, slides: slides), isField: run.field != nil)
                if !item.isField, let last = runs.last, !last.isField, last.character == item.character {
                    runs[runs.count - 1].text += item.text
                } else {
                    runs.append(item)
                }
            }
            let bulletLook = paragraph.bullet.map { "\($0.fontFamily) \(round($0.fontSize)) \($0.color.rgb.hex)" }
            return Paragraph(level: paragraph.level, alignment: paragraph.alignment,
                             spacing: [paragraph.lineSpacing, paragraph.spaceBefore, paragraph.spaceAfter, paragraph.marginLeft, paragraph.indent].map { round($0) },
                             bullet: paragraph.bullet?.text, bulletLook: bulletLook, runs: runs, end: character(paragraph.endStyle, slides: slides))
        }
    }

    /// A table as it shows: its sizes, each visible cell's span, look and text, and every border not inside a merged cell.
    static func table(_ original: Table, style: ElementStyle, presentation: Presentation, slides: [UUID: Int]) -> [String] {
        var table = original
        table.normalize()
        let colors = style.theme.colors
        var lines = ["columns \(table.columnWidths.map { round($0) })", "rows \(table.rowHeights.map { round($0) })"]
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            let textStyle = ODPContentWriter.cellTextStyle(cell, theme: style.theme, defaultTextStyle: presentation.defaultTextStyle)
            let insets = [cell.insets.left, cell.insets.top, cell.insets.right, cell.insets.bottom].map { round($0) }
            lines.append("cell \(row),\(column) span \(cell.rowSpan)x\(cell.columnSpan) fill \(fill(cell.fill, colors, media: presentation.media)) "
                + "\(cell.anchor) \(insets) text \(paragraphs(textStyle, body: cell.text, slides: slides))")
        }
        for row in 0...table.rowCount {
            for column in 0..<table.columnCount where !table.isInsideMergedCell(horizontal: true, row: row, column: column) {
                lines.append("h \(row),\(column) \(outline(table.horizontalBorders[row][column] ?? Outline.none, colors, media: presentation.media))")
            }
        }
        for row in 0..<table.rowCount {
            for column in 0...table.columnCount where !table.isInsideMergedCell(horizontal: false, row: row, column: column) {
                lines.append("v \(row),\(column) \(outline(table.verticalBorders[row][column] ?? Outline.none, colors, media: presentation.media))")
            }
        }
        return lines
    }

    /// A chart as it shows: its kind, the numbers it plots with each series' color, its titles and its look. Pies show
    /// their first series; only doughnuts show their hole.
    static func chart(_ chart: Chart) -> [String] {
        let data = chart.data.padded()
        var lines = ["\(chart.kind) heading \(data.labelHeading) labels \(data.labels)"]
        for (index, series) in data.series.enumerated() where !chart.kind.isPie || index == 0 {
            lines.append("series \(series.name) \(series.values.map { $0.map { round($0, 0.000001) } }) \(chart.color(ofSeries: index).hex)")
        }
        lines.append("title \(chart.title) axes \(chart.horizontalAxisTitle) | \(chart.verticalAxisTitle) legend \(chart.legend)")
        lines.append("grid \(chart.showsGridlines) labels \(chart.showsDataLabels) font \(chart.fontFamily ?? "-") background \((chart.backgroundColor ?? .white).hex)")
        lines.append("range \(chart.verticalMinimum.map { "\($0)" } ?? "-") \(chart.verticalMaximum.map { "\($0)" } ?? "-")")
        if chart.kind == .donut { lines.append("hole \(round(chart.pieHole))") }
        return lines
    }

    static func adjustments(_ adjustments: ImageAdjustments) -> String {
        "t\(round(adjustments.transparency, 0.001)) b\(round(adjustments.brightness, 0.001)) c\(round(adjustments.contrast, 0.001)) "
            + (adjustments.recolor.map { "\($0)" } ?? "-")
    }

    static func element(_ element: SlideElement, style: ElementStyle, presentation: Presentation, slides: [UUID: Int],
                        styleFor: (SlideElement) -> ElementStyle) -> Element {
        let placement = style.placement
        var frame = placement.frame.standardized
        var flipH = placement.flipHorizontal != (placement.frame.width < 0), flipV = placement.flipVertical != (placement.frame.height < 0)
        let colors = style.theme.colors
        var kind = "shape", geometry = "", fill = "none", outline = "none", body: String?, text: [Paragraph]?, picture: String?
        var flags = [false, false, false]
        var children: [Element] = []
        var object: [String] = []
        switch element.content {
        case .shape(let shape):
            geometry = self.geometry(shape.geometry, size: frame.size)
            fill = self.fill(style.fill, colors, media: presentation.media)
            outline = self.outline(style.outline, colors, media: presentation.media)
            flags = [shape.isTextBox, shape.isConnector, shape.isWordArt]
            if shape.geometry.isLine {
                // A line is its two ends.
                let start = placement.slidePoint(fromShape: SlidePoint(x: 0, y: 0))
                let end = placement.slidePoint(fromShape: SlidePoint(x: placement.frame.width, y: placement.frame.height))
                frame = SlideRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
                flipH = false
                flipV = false
                geometry = shape.geometry.presetName.map { $0.hasPrefix("bent") ? "bent" : $0.hasPrefix("curved") ? "curved" : "straight" } ?? "straight"
                flags = [false, false, false]
            }
            if let textBody = shape.text, !textBody.isEmpty || element.placeholder != nil {
                let properties = style.bodyProperties
                body = "\(properties.anchor) \([properties.insets.left, properties.insets.top, properties.insets.right, properties.insets.bottom].map { round($0) }) "
                    + "\(properties.autofit) \(properties.wraps)"
                text = paragraphs(style, body: textBody, slides: slides)
            }
        case .picture(let item):
            let rect = item.geometry == .rectangle || item.geometry.presetName == "rect"
            kind = rect ? "picture" : "shape"
            geometry = self.geometry(item.geometry, size: frame.size)
            if rect {
                picture = "\(presentation.media[item.mediaID]?.data.hashValue ?? 0) \([item.crop.left, item.crop.top, item.crop.right, item.crop.bottom].map { round($0, 0.0001) })"
                    + " " + adjustments(item.adjustments)
            } else {
                fill = "picture \(presentation.media[item.mediaID]?.data.hashValue ?? 0) true"
            }
            outline = self.outline(item.outline ?? Outline.none, colors, media: presentation.media)
        case .group(let items):
            kind = "group"
            children = items.map { self.element($0, style: styleFor($0), presentation: presentation, slides: slides, styleFor: styleFor) }
            frame = .zero
        case .table(let table):
            kind = "table"
            // Tables and charts don't flip.
            (flipH, flipV) = (false, false)
            object = self.table(table, style: style, presentation: presentation, slides: slides)
        case .chart(let chart):
            kind = "chart"
            (flipH, flipV) = (false, false)
            object = self.chart(chart)
        case .media(let clip):
            kind = clip.kind.rawValue
            // The movie or sound and its poster by their bytes, and how it plays.
            let settings = PPTXCanonical.clip(clip) { $0 }
            picture = "\(presentation.media[clip.mediaID]?.data.hashValue ?? 0) \(clip.posterID.flatMap { presentation.media[$0]?.data.hashValue } ?? 0) "
                + "\(settings.playback) \(settings.start ?? 0) \(settings.end ?? -1) \(settings.volume) \(settings.isMuted) \(settings.loops) "
                + "\(settings.hidesWhenPresenting) \(settings.stopsOnSlideChange)"
        }
        return Element(kind: kind, placeholder: element.placeholder?.type, frame: [frame.x, frame.y, frame.width, frame.height].map { round($0) },
                       flips: [flipH, flipV], geometry: geometry + (kind == "group" ? "" : " r\(round(placement.rotation, 0.1))"), fill: fill,
                       outline: outline, body: body, text: text, flags: flags, picture: picture, alt: [element.altTitle, element.altDescription],
                       children: children, object: object)
    }

    static func slides(_ presentation: Presentation) -> [SlideView] {
        var numbers: [UUID: Int] = [:]
        for (index, slide) in presentation.slides.enumerated() { numbers[slide.id] = index }
        return presentation.slides.map { slide in
            let theme = presentation.theme(for: slide)
            let layout = presentation.layout(for: slide)
            let backdrop = presentation.backdropElements(for: slide).map {
                element($0.element, style: $0.style, presentation: presentation, slides: numbers) { presentation.style(forThemeElement: $0, theme: theme) }
            }
            let elements = slide.elements.map {
                element($0, style: presentation.style(for: $0, on: slide), presentation: presentation, slides: numbers) { presentation.style(for: $0, on: slide) }
            }
            let indexes = Dictionary(uniqueKeysWithValues: slide.elements.enumerated().map { ($1.id, $0) })
            let animations = slide.animations.map { animation in
                "\(indexes[animation.elementID] ?? -1) \(animation.effect) \(animation.start) "
                    + (animation.effect.isInstant ? "-" : "\(round(animation.duration))") + " \(round(animation.delay)) \(animation.byParagraph)"
            }
            let transition = slide.transition.map { "\($0.kind) \(round($0.duration))" } ?? "none"
            let notesElement = SlideElement(placement: nil, content: .shape(Shape(text: slide.notes)))
            let notesStyle = ElementStyle(element: notesElement, parents: [], theme: theme, defaultTextStyle: presentation.defaultTextStyle)
            return SlideView(theme: theme.name, layout: "\(layout?.name ?? "?") \(layout?.kind.rawValue ?? "?")",
                             background: fill(presentation.background(for: slide), theme.colors, media: presentation.media), skipped: slide.isSkipped,
                             transition: transition, animations: animations,
                             notes: slide.notes.isEmpty ? [] : paragraphs(notesStyle, body: slide.notes, slides: numbers), backdrop: backdrop, elements: elements,
                             comments: comments(slide))
        }
    }

    /// Where two presentations first show differently; nil when they show the same.
    static func difference(_ a: Presentation, _ b: Presentation) -> String? {
        if abs(a.slideSize.width - b.slideSize.width) > 0.01 || abs(a.slideSize.height - b.slideSize.height) > 0.01 {
            return "slide size \(a.slideSize) \(b.slideSize)"
        }
        if a.title != b.title { return "title \(a.title ?? "-") \(b.title ?? "-")" }
        // Guides keep their places; files have no colors for them.
        let guides = { (presentation: Presentation) in presentation.guides.map { "\($0.orientation) \(round($0.position, 0.05))" } }
        if guides(a) != guides(b) { return "guides \(guides(a)) | \(guides(b))" }
        let x = slides(a), y = slides(b)
        if x.count != y.count { return "slide count \(x.count) \(y.count)" }
        for (index, (p, q)) in zip(x, y).enumerated() where p != q {
            let label = "slide \(index + 1)"
            if p.theme != q.theme { return "\(label) theme: \(p.theme) | \(q.theme)" }
            if p.layout != q.layout { return "\(label) layout: \(p.layout) | \(q.layout)" }
            if p.background != q.background { return "\(label) background: \(p.background) | \(q.background)" }
            if p.skipped != q.skipped { return "\(label) skipped" }
            if p.transition != q.transition { return "\(label) transition: \(p.transition) | \(q.transition)" }
            if p.animations != q.animations { return "\(label) animations:\n  \(p.animations)\n  \(q.animations)" }
            if p.notes != q.notes { return "\(label) notes:\n  \(p.notes)\n  \(q.notes)" }
            if let found = elements(label + " backdrop", p.backdrop, q.backdrop) { return found }
            if let found = elements(label, p.elements, q.elements) { return found }
            if p.comments != q.comments { return "\(label) comments:\n  \(p.comments)\n  \(q.comments)" }
        }
        return nil
    }

    static func elements(_ label: String, _ x: [Element], _ y: [Element]) -> String? {
        if x.count != y.count { return "\(label) element count \(x.count) \(y.count):\n  \(x.map(\.kind))\n  \(y.map(\.kind))" }
        for (index, (p, q)) in zip(x, y).enumerated() where p != q {
            let label = "\(label) element \(index + 1) (\(p.kind) \(p.placeholder.map { "\($0)" } ?? ""))"
            if p.kind != q.kind || p.placeholder != q.placeholder { return "\(label) kind: \(p.kind) \(p.placeholder as Any) | \(q.kind) \(q.placeholder as Any)" }
            if p.frame != q.frame || p.flips != q.flips { return "\(label) frame: \(p.frame) \(p.flips) | \(q.frame) \(q.flips)" }
            if p.geometry != q.geometry { return "\(label) geometry:\n  \(p.geometry)\n  \(q.geometry)" }
            if p.fill != q.fill { return "\(label) fill: \(p.fill) | \(q.fill)" }
            if p.outline != q.outline { return "\(label) outline: \(p.outline) | \(q.outline)" }
            if p.body != q.body { return "\(label) body: \(p.body ?? "-") | \(q.body ?? "-")" }
            if p.flags != q.flags { return "\(label) flags: \(p.flags) | \(q.flags)" }
            if p.picture != q.picture { return "\(label) picture: \(p.picture ?? "-") | \(q.picture ?? "-")" }
            if p.alt != q.alt { return "\(label) alt text: \(p.alt) | \(q.alt)" }
            if let found = elements(label, p.children, q.children) { return found }
            if p.object.count != q.object.count { return "\(label) object: \(p.object.count) lines | \(q.object.count) lines\n  \(p.object)\n  \(q.object)" }
            for (m, n) in zip(p.object, q.object) where m != n { return "\(label) object:\n  \(m)\n  \(n)" }
            let first = p.text ?? [], second = q.text ?? []
            if first.count != second.count { return "\(label) paragraph count \(first.count) \(second.count)" }
            for (number, (m, n)) in zip(first, second).enumerated() where m != n {
                return "\(label) paragraph \(number + 1):\n  \(m)\n  \(n)"
            }
            return "\(label) differs"
        }
        return nil
    }
}

/// Deterministic pseudo-random numbers for tests.
struct ODPTestRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }

    mutating func below(_ bound: Int) -> Int {
        bound <= 0 ? 0 : Int(next() % UInt64(bound))
    }
}

/// Packages and parts for tests.
enum ODPTestPackage {
    static func parts(of package: Data) throws -> [String: Data] {
        let reader = try ZipReader(data: package)
        var result: [String: Data] = [:]
        for entry in reader.entries { result[entry.path] = try reader.read(entry) }
        return result
    }

    static func part(_ path: String, of package: Data) throws -> String? {
        try ZipReader(data: package).read(path).map { String(decoding: $0, as: UTF8.self) }
    }

    /// A package with `mimetype` first and stored, as ODF requires, then the other parts in the order given.
    static func zip(_ parts: [(String, Data)], mimetype: String? = "application/vnd.oasis.opendocument.presentation") throws -> Data {
        var writer = ZipWriter(date: Date(timeIntervalSince1970: 1_700_000_000))
        if let mimetype { try writer.add("mimetype", Data(mimetype.utf8), compress: false) }
        for (path, data) in parts { try writer.add(path, data) }
        return try writer.finish()
    }

    static func zip(_ parts: [String: Data]) throws -> Data {
        var ordered: [(String, Data)] = []
        for path in parts.keys.sorted() where path != "mimetype" { ordered.append((path, parts[path]!)) }
        return try zip(ordered, mimetype: parts["mimetype"].map { String(decoding: $0, as: UTF8.self) })
    }
}

/// The model with ids that can't survive a file renumbered (as `PPTXCanonical` does) and animations pointing at
/// elements by position.
enum ODPModel {
    static func canonical(_ presentation: Presentation) -> Presentation {
        // Table cells' pictures are named by their bytes and their links to slides by the slides' places, as the shared
        // canonical form only renames what shapes and pictures use.
        var source = presentation
        let slideNumbers = Dictionary(presentation.slides.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func cellText(_ body: TextBody) -> TextBody {
            var body = body
            for index in body.paragraphs.indices {
                for run in body.paragraphs[index].runs.indices {
                    if case .slide(let id)? = body.paragraphs[index].runs[run].style.link {
                        body.paragraphs[index].runs[run].style.link = .slide(PPTXCanonical.uuid(10_000 + (slideNumbers[id] ?? 9_999)))
                    }
                }
            }
            return body
        }
        func tables(_ element: SlideElement) -> SlideElement {
            var element = element
            switch element.content {
            case .group(let children):
                element.content = .group(children.map(tables))
            case .table(var table):
                for row in table.cells.indices {
                    for column in table.cells[row].indices {
                        var cell = table.cells[row][column]
                        if case .picture(var fill) = cell.fill {
                            fill.mediaID = "cell-media-\(presentation.media[fill.mediaID]?.data.hashValue ?? 0)"
                            cell.fill = .picture(fill)
                        }
                        cell.text = cellText(cell.text)
                        table.cells[row][column] = cell
                    }
                }
                element.content = .table(table)
            default:
                break
            }
            return element
        }
        for theme in source.themes.indices {
            source.themes[theme].elements = source.themes[theme].elements.map(tables)
            for layout in source.themes[theme].layouts.indices {
                source.themes[theme].layouts[layout].elements = source.themes[theme].layouts[layout].elements.map(tables)
            }
        }
        for slide in source.slides.indices { source.slides[slide].elements = source.slides[slide].elements.map(tables) }
        var result = PPTXCanonical.canonical(source)
        for index in result.guides.indices { result.guides[index].id = PPTXCanonical.uuid(800_000 + index) }
        for (index, slide) in presentation.slides.enumerated() where index < result.slides.count {
            let ids = Dictionary(uniqueKeysWithValues: zip(slide.elements.map(\.id), result.slides[index].elements.map(\.id)))
            result.slides[index].animations = slide.animations.enumerated().map { number, animation in
                var copy = animation
                copy.id = PPTXCanonical.uuid(500_000 + number)
                copy.elementID = ids[animation.elementID] ?? animation.elementID
                return copy
            }
        }
        return result
    }

    static func difference(_ a: Presentation, _ b: Presentation) -> String? {
        let x = canonical(a), y = canonical(b)
        if x == y { return nil }
        for (index, (p, q)) in zip(x.slides, y.slides).enumerated() where p.animations != q.animations {
            return "slide \(index + 1) animations:\n  \(p.animations)\n  \(q.animations)"
        }
        return PPTXCanonical.difference(a, b) ?? "differs somewhere"
    }
}
