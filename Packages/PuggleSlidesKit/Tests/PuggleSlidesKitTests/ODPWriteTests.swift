import Foundation
import Testing
@testable import PuggleSlidesKit

/// The parts PuggleSlides writes, as LibreOffice Impress expects them.
struct ODPWriteTests {
    static func parts(_ presentation: Presentation) throws -> (package: Data, content: ODFNode, styles: ODFNode) {
        let data = try ODPWriter.write(presentation)
        let parts = try ODPTestPackage.parts(of: data)
        return (data, try ODFXML.parse(parts["content.xml"]!), try ODFXML.parse(parts["styles.xml"]!))
    }

    static func descendants(_ node: ODFNode, _ name: String) -> [ODFNode] {
        var result: [ODFNode] = []
        func walk(_ node: ODFNode) {
            for child in node.elements {
                if child.name == name { result.append(child) }
                walk(child)
            }
        }
        walk(node)
        return result
    }

    @Test func packageStartsWithItsStoredMediaType() throws {
        let data = try ODPWriter.write(ODPSamples.rich())
        let bytes = [UInt8](data)
        // A local file header for "mimetype", stored (method 0), its contents right after the 38-byte header and name.
        #expect(Array(bytes[0..<4]) == [0x50, 0x4B, 0x03, 0x04])
        #expect(bytes[8] == 0 && bytes[9] == 0)
        #expect(bytes[28] == 0 && bytes[29] == 0)
        #expect(String(decoding: bytes[30..<38], as: UTF8.self) == "mimetype")
        let type = "application/vnd.oasis.opendocument.presentation"
        #expect(String(decoding: bytes[38..<(38 + type.utf8.count)], as: UTF8.self) == type)
        // No extra field, so the media type sits at byte 38 as ODF asks.
        #expect(bytes[18..<22] == bytes[22..<26])
        let zip = try ZipReader(data: data)
        #expect(zip.entries.first?.path == "mimetype")
        #expect(zip.entries.first?.method == 0)
    }

    @Test(arguments: ["rich", "objects"])
    func manifestListsEveryPart(_ sample: String) throws {
        let data = try ODPWriter.write(sample == "rich" ? ODPSamples.rich() : ODPSamples.objects())
        let parts = try ODPTestPackage.parts(of: data)
        let manifest = try ODFXML.parse(parts["META-INF/manifest.xml"]!)
        #expect(manifest["manifest:version"] == "1.3")
        var listed: [String: String] = [:]
        for entry in manifest.children("manifest:file-entry") { listed[entry["manifest:full-path"]!] = entry["manifest:media-type"] }
        #expect(listed["/"] == "application/vnd.oasis.opendocument.presentation")
        for path in parts.keys where path != "mimetype" && path != "META-INF/manifest.xml" {
            #expect(listed[path] != nil, "\(path) isn't in the manifest")
        }
        // Everything listed is there, but the folders of chart objects.
        for path in listed.keys where path != "/" && !path.hasSuffix("/") { #expect(parts[path] != nil, "\(path) is listed but missing") }
        #expect(listed["content.xml"] == "text/xml")
        #expect(listed.filter { $0.key.hasPrefix("Pictures/") }.values.allSatisfy { $0 == "image/png" })
        #expect(parts.keys.filter { $0.hasPrefix("Pictures/") }.count == 2)
    }

    @Test func themesAreMastersWithLibreOfficesPresentationStyles() throws {
        let (_, content, styles) = try Self.parts(ODPSamples.rich())
        let masters = Self.descendants(styles, "style:master-page")
        let names = masters.map { $0["style:display-name"] ?? "" }
        // A master per theme, and one for each layout with a look of its own.
        #expect(names == ["Simple Light", "Simple Light: Section title and description", "Simple Light: Photo backdrop", "Harbor",
                          "Harbor: Title slide", "Harbor: Section title and description"])
        #expect(masters[0]["style:name"] == "Simple_20_Light")
        let common = try #require(styles.child("office:styles"))
        let presentationStyles = Set(common.children("style:style").filter { $0["style:family"] == "presentation" }.compactMap { $0["style:name"] })
        for suffix in ["title", "subtitle", "notes", "background", "backgroundobjects"] + (1...9).map({ "outline\($0)" }) {
            #expect(presentationStyles.contains("Simple_20_Light-" + suffix))
            #expect(presentationStyles.contains("Harbor-" + suffix))
        }
        // LibreOffice pairs styles with masters by display name.
        let title = common.children("style:style").first { $0["style:name"] == "Simple_20_Light-title" }
        #expect(title?["style:display-name"] == "Simple Light-title")
        let outline = common.children("style:style").first { $0["style:name"] == "Harbor-outline1" }
        let bullets = outline?.child("style:graphic-properties")?.child("text:list-style")?.elements ?? []
        #expect(bullets.count == 9)
        #expect(bullets.first?["text:bullet-char"] == "●")
        // Page layouts of the slide size, and a presentation page layout for every layout.
        let pageLayout = Self.descendants(styles, "style:page-layout-properties").first
        #expect(pageLayout?["fo:page-width"] == "720pt" && pageLayout?["fo:page-height"] == "405pt")
        #expect(common.children("style:presentation-page-layout").count == 12 + 11)
        // Slides name their master and layout.
        let pages = Self.descendants(content, "draw:page")
        #expect(pages.map { $0["draw:master-page-name"] ?? "" } == ["Simple_20_Light", "Simple_20_Light", "Simple_20_Light", "Simple_20_Light", "Harbor",
                                                                   "Simple_20_Light_3a__20_Photo_20_backdrop", "Harbor_3a__20_Title_20_slide"])
        #expect(pages[0]["presentation:presentation-page-layout-name"] == "Simple_20_Light_3a__20_Title_20_slide")
    }

    @Test func placeholdersAreFramesStatingWhereTheyAre() throws {
        let (_, content, _) = try Self.parts(ODPSamples.rich())
        let frames = Self.descendants(content, "draw:frame").filter { $0["presentation:class"] != nil }
        let classes = Set(frames.compactMap { $0["presentation:class"] })
        #expect(classes.isSuperset(of: ["title", "subtitle", "outline", "graphic", "page-number", "notes"]))
        for frame in frames where frame["presentation:class"] != "notes" {
            #expect(frame["presentation:user-transformed"] == "true")
            #expect(frame["svg:width"] != nil && (frame["svg:x"] != nil || frame["draw:transform"] != nil))
        }
        // The oval title on the custom layout is a custom shape with its master's title style.
        let oval = Self.descendants(content, "draw:custom-shape").first { $0["presentation:style-name"] != nil }
        #expect(oval?.child("draw:enhanced-geometry")?["draw:type"] == "ellipse")
    }

    @Test func shapesNameLibreOfficeTypesAndCarryTheirOutline() throws {
        var presentation = Presentation.makeDefault()
        let layout = presentation.themes[0].layout(kind: .blank)!.id
        var slide = presentation.makeSlide(layoutID: layout)
        let shapes: [(String, [String: Double])] = [("rect", [:]), ("ellipse", [:]), ("roundRect", [:]), ("roundRect", ["adj": 30000]), ("star5", [:]),
                                                   ("rightArrow", ["adj1": 40000]), ("flowChartProcess", [:]), ("cloudCallout", [:]), ("heart", [:]),
                                                   ("gear6", [:]), ("chevron", ["adj": 50000])]
        slide.elements = shapes.enumerated().map { index, shape in
            ODPSamples.shape("Shape \(index)", SlideRect(x: Double(index) * 60, y: 20, width: 50, height: 40),
                             Shape(geometry: .preset(shape.0, adjustments: shape.1), fill: .solid(.black)))
        }
        presentation.slides = [slide]
        let (_, content, _) = try Self.parts(presentation)
        let geometries = Self.descendants(content, "draw:enhanced-geometry")
        #expect(geometries.map { $0["draw:type"] ?? "" } == ["rectangle", "ellipse", "round-rectangle", "ooxml-roundRect", "star5", "ooxml-rightArrow",
                                                              "flowchart-process", "cloud-callout", "heart", "ooxml-gear6", "chevron"])
        #expect(geometries[3]["draw:modifiers"] == "30000")
        #expect(geometries[5]["draw:modifiers"] == "40000 50000")
        #expect(geometries[2]["draw:modifiers"] == nil)
        for geometry in geometries {
            #expect(geometry["svg:viewBox"] == "0 0 5000 4000")
            let path = geometry["draw:enhanced-path"] ?? ""
            #expect(!path.isEmpty)
            #expect(path.allSatisfy { !$0.isLetter || "MLCZNFSHIJK".contains($0) })
            #expect(geometry["draw:text-areas"] != nil)
        }
        // A star is drawn as its outline: five outer and five inner points.
        #expect(geometries[4]["draw:enhanced-path"]?.filter { $0 == "L" }.count == 9)
    }

    @Test func linesConnectorsMarkersAndDashes() throws {
        let (_, content, styles) = try Self.parts(ODPSamples.rich())
        let lines = Self.descendants(content, "draw:line")
        let connectors = Self.descendants(content, "draw:connector")
        #expect(lines.map { $0["draw:name"] ?? "" } == ["Dotted line", "Dash dot line", "Long dash line"])
        #expect(connectors.map { $0["draw:type"] ?? "" } == ["line", "standard", "curve"])
        #expect(lines[2]["svg:x1"] == "600pt" && lines[2]["svg:x2"] == "500pt")
        let markers = Self.descendants(styles, "draw:marker").compactMap { $0["draw:display-name"] }
        #expect(Set(markers) == ["Arrow", "Line Arrow", "Circle", "Circle unfilled", "Square", "Square unfilled", "Square 45", "Square 45 unfilled"])
        let dashes = Self.descendants(styles, "draw:stroke-dash").compactMap { $0["draw:display-name"] }
        #expect(Set(dashes) == ["Dot", "Dash", "Dash Dot", "Long Dash", "Long Dash Dot"])
    }

    @Test func textUsesListsSpansLinksAndFields() throws {
        let data = try ODPWriter.write(ODPSamples.rich())
        let content = try #require(try ODPTestPackage.part("content.xml", of: data))
        for markup in ["<text:list text:style-name=", "<text:list-item>", "<text:list-header>", "<text:span text:style-name=", "<text:line-break/>",
                       "<text:s text:c=\"2\"/>", "<text:tab/>", "<text:a xlink:type=\"simple\" xlink:href=\"https://example.com/a?b=1&amp;c=2\">",
                       "xlink:href=\"#page4\"", "<text:page-number text:select-page=\"current\">2</text:page-number>",
                       "<text:date style:data-style-name=\"datetime4\">January 2, 2026</text:date>", "<text:time style:data-style-name=\"datetime10\">",
                       "text:list-item text:start-value=\"4\"", "style:num-format=\"I\"", "style:num-prefix=\"(\"", "style:text-position=\"super 58%\"",
                       "fo:background-color=\"#fff000\"", "style:text-line-through-style=\"solid\""] {
            #expect(content.contains(markup), "missing \(markup)")
        }
        let styles = try #require(try ODPTestPackage.part("styles.xml", of: data))
        #expect(styles.contains("<number:date-style style:name=\"datetime4\">"))
        #expect(styles.contains("<style:font-face style:name=\"Helvetica Neue\" svg:font-family=\"'Helvetica Neue'\"/>"))
    }

    @Test func picturesCropWithClipAndMirror() throws {
        let (_, content, _) = try Self.parts(ODPSamples.rich())
        let automatic = try #require(content.child("office:automatic-styles"))
        func graphic(of frame: ODFNode) -> ODFNode? {
            let name = frame["draw:style-name"] ?? frame["presentation:style-name"]
            return automatic.children("style:style").first { $0["style:name"] == name }?.child("style:graphic-properties")
        }
        let frames = Self.descendants(content, "draw:frame")
        // The photo is 48 pixels square: 36 points at 96 per inch.
        let cropped = try #require(frames.first { $0["draw:name"] == "Cropped photo" })
        #expect(graphic(of: cropped)?["fo:clip"] == "rect(1.8pt, 7.2pt, 0pt, 3.6pt)")
        #expect(cropped.child("draw:image")?["xlink:href"] == "Pictures/image1.png")
        let mirrored = try #require(frames.first { $0["draw:name"] == "Mirrored photo" })
        #expect(graphic(of: mirrored)?["style:mirror"] == "horizontal")
        #expect(mirrored["draw:transform"]?.hasPrefix("rotate (") == true)
    }

    @Test func notesHiddenSlidesTransitionsAndAnimations() throws {
        let (_, content, _) = try Self.parts(ODPSamples.rich())
        let pages = Self.descendants(content, "draw:page")
        let automatic = try #require(content.child("office:automatic-styles"))
        func pageStyle(_ page: ODFNode) -> ODFNode? {
            automatic.children("style:style").first { $0["style:name"] == page["draw:style-name"] }?.child("style:drawing-page-properties")
        }
        #expect(pages.map { pageStyle($0)?["presentation:visibility"] } == [nil, nil, nil, "hidden", nil, nil, nil])
        #expect(pages.map { pageStyle($0)?["smil:type"] ?? "" } == ["fade", "dissolve", "pushWipe", "pushWipe", "miscShapeWipe", "miscShapeWipe", "slideWipe"])
        #expect(pages.map { pageStyle($0)?["smil:subtype"] ?? "" } == ["crossfade", "", "fromRight", "fromLeft", "topToBottom", "cornersOut", "fromRight"])
        let notes = pages[1].child("presentation:notes")
        #expect(notes?.children("draw:frame").first?["presentation:class"] == "notes")
        #expect(notes?.textContent == "Speak slowly.")
        // The timing root: the transition's exact duration, then the main sequence of LibreOffice's presets.
        let timing = try #require(pages[1].child("anim:par"))
        #expect(timing["presentation:node-type"] == "timing-root")
        #expect(timing.elements.first?.child("anim:transitionFilter")?["smil:dur"] == "1.2s")
        let presets = Self.descendants(content, "anim:par").compactMap { $0["presentation:preset-id"] }
        #expect(Set(presets) == ["ooo-entrance-appear", "ooo-entrance-fade-in", "ooo-entrance-fly-in", "ooo-entrance-zoom", "ooo-emphasis-spin",
                                 "ooo-exit-disappear", "ooo-exit-fade-out", "ooo-exit-fly-out", "ooo-exit-zoom"])
        // Animating by paragraph targets each paragraph by its id.
        let targets = Self.descendants(pages[1], "anim:set").compactMap { $0["smil:targetElement"] }
        #expect(targets.prefix(3) == ["s2e2p1", "s2e2p2", "s2e2p3"])
        #expect(Self.descendants(pages[1], "text:p").contains { $0["xml:id"] == "s2e2p1" })
    }

    @Test func animationsOfElementsThatCantBeWrittenAreLeftOut() throws {
        var presentation = Presentation.makeDefault()
        let lost = SlideElement(name: "Lost", placement: Placement(frame: SlideRect(x: 0, y: 0, width: 10, height: 10)), content: .picture(Picture(mediaID: "gone")))
        presentation.slides[0].elements.append(lost)
        presentation.slides[0].animations = [SlideAnimation(elementID: lost.id, effect: .fadeIn), SlideAnimation(elementID: presentation.slides[0].elements[0].id)]
        let (_, content, _) = try Self.parts(presentation)
        let targets = Set(Self.descendants(content, "anim:set").compactMap { $0["smil:targetElement"] })
        let ids = Set(Self.descendants(content, "draw:frame").compactMap { $0["xml:id"] })
        #expect(targets == ["s1e1"])
        #expect(targets.isSubset(of: ids))
        let read = try PresentationIO.read(try ODPWriter.write(presentation), format: .odp).presentation
        #expect(read.slides[0].animations.map(\.effect) == [.appear])
    }

    @Test func metadataNamesNoOne() throws {
        let data = try ODPWriter.write(ODPSamples.rich(), date: Date(timeIntervalSince1970: 1_800_000_000))
        let meta = try #require(try ODPTestPackage.part("meta.xml", of: data))
        #expect(meta.contains("<meta:generator>PuggleSlides</meta:generator>"))
        #expect(meta.contains("<dc:title>Quarterly Review &amp; &lt;Plans&gt; \"2026\"</dc:title>"))
        #expect(meta.contains("<meta:creation-date>2027-01-15T08:00:00</meta:creation-date>"))
        #expect(!meta.contains("creator"))
    }

    @Test func everyFontIsDeclared() throws {
        let (_, content, styles) = try Self.parts(ODPSamples.rich())
        let objects = try Self.parts(ODPSamples.objects())
        for part in [content, styles, objects.content, objects.styles] {
            let declared = Set(Self.descendants(part, "style:font-face").compactMap { $0["style:name"] })
            var named = Set<String>()
            for properties in Self.descendants(part, "style:text-properties") {
                for key in ["style:font-name", "style:font-name-asian", "style:font-name-complex"] { if let name = properties[key] { named.insert(name) } }
            }
            #expect(!named.isEmpty)
            #expect(named.isSubset(of: declared), "undeclared: \(named.subtracting(declared))")
        }
        let themes = try Self.parts(ODPSamples.allThemes()).styles
        #expect(Set(BuiltInThemes.designs.flatMap { [$0.headingFont, $0.bodyFont] })
            .isSubset(of: Set(Self.descendants(themes, "style:font-face").compactMap { $0["style:name"] })))
    }

    @Test func everyPartIsWellFormed() throws {
        for sample in [ODPSamples.rich(), ODPSamples.objects()] {
            let parts = try ODPTestPackage.parts(of: try ODPWriter.write(sample))
            for (path, data) in parts where path.hasSuffix(".xml") {
                let parser = XMLParser(data: data)
                #expect(parser.parse(), "\(path) isn't well-formed")
            }
        }
    }
}
