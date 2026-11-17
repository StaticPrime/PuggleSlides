import Foundation

/// Writes PowerPoint presentations (.pptx) laid out like a minimal PowerPoint-made package, which PowerPoint,
/// Keynote and LibreOffice open without repairs: one master and theme part per theme, a layout part
/// per layout, slides, a notes master, notes slides for slides with notes, and media.
enum PPTXWriter {
    static func write(_ presentation: Presentation) throws -> Data {
        try write(presentation, date: Date())
    }

    static func write(_ presentation: Presentation, date: Date) throws -> Data {
        do {
            var writer = PackageWriter(presentation: normalized(presentation), date: date)
            return try writer.write()
        } catch let error as PresentationIOError {
            throw error
        } catch {
            throw PresentationIOError.unwritable(PPTXMessages.tooLargeToSave)
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
        return result
    }

    private struct PackageWriter {
        let presentation: Presentation
        let date: Date
        let state: PPTXWriteState
        /// Parts in the order they go into the archive, with content types for those that need an override.
        private var parts: [(path: String, data: Data, contentType: String?)] = []

        init(presentation: Presentation, date: Date) {
            self.presentation = presentation
            self.date = date
            state = PPTXWriteState(media: presentation.media, date: date)
        }

        private mutating func add(_ path: String, _ data: Data, contentType: String?) {
            parts.append((path, data, contentType))
        }

        private mutating func add(_ part: PPTXPartWriter, contentType: String) {
            add(part.path, part.xml.data, contentType: contentType)
            if !part.relationships.isEmpty {
                add(PPTXPackage.relationshipsPath(for: part.path), part.relationships.data(), contentType: nil)
            }
        }

        mutating func write() throws -> Data {
            let themeCount = presentation.themes.count
            // Parts are numbered by position; a slide whose layout id appears twice uses the first.
            var layoutPaths: [[String]] = []
            var layoutPathsByID: [UUID: String] = [:]
            var layoutNumber = 0
            for theme in presentation.themes {
                layoutPaths.append(theme.layouts.map { layout in
                    layoutNumber += 1
                    let path = "ppt/slideLayouts/slideLayout\(layoutNumber).xml"
                    if layoutPathsByID[layout.id] == nil { layoutPathsByID[layout.id] = path }
                    return path
                })
            }
            for (index, slide) in presentation.slides.enumerated() where state.slidePaths[slide.id] == nil {
                state.slidePaths[slide.id] = "ppt/slides/slide\(index + 1).xml"
            }

            // Masters and their layouts. Master and layout ids share one range, from 2147483648.
            var nextMasterID = 2_147_483_648
            var masterIDs: [Int] = []
            for (index, theme) in presentation.themes.enumerated() {
                let masterPath = "ppt/slideMasters/slideMaster\(index + 1).xml"
                let themePath = "ppt/theme/theme\(index + 1).xml"
                masterIDs.append(nextMasterID)
                nextMasterID += 1
                var master = PPTXPartWriter(path: masterPath, state: state)
                var layoutEntries: [(id: Int, relationship: String)] = []
                for layoutPath in layoutPaths[index] {
                    layoutEntries.append((nextMasterID, master.relationship(type: PPTXRelationshipType.slideLayout, to: layoutPath)))
                    nextMasterID += 1
                }
                _ = master.relationship(type: PPTXRelationshipType.theme, to: themePath)
                writeMaster(theme, layouts: layoutEntries, into: &master)
                add(master, contentType: PPTXContentType.slideMaster)
                add(themePath, PPTXThemeWriter.part(name: theme.name, colors: theme.colors, fonts: theme.fonts), contentType: PPTXContentType.theme)
                for (layout, layoutPath) in zip(theme.layouts, layoutPaths[index]) {
                    var part = PPTXPartWriter(path: layoutPath, state: state)
                    _ = part.relationship(type: PPTXRelationshipType.slideMaster, to: masterPath)
                    let presentation = presentation
                    part.measureRows = { table, element in
                        PPTXTableMeasure.rowHeights(table, style: presentation.style(for: element, inLayout: layout, theme: theme), slideNumber: nil)
                    }
                    writeLayout(layout, into: &part)
                    add(part, contentType: PPTXContentType.slideLayout)
                }
            }

            // The notes master, with a theme of its own.
            let notesMasterPath = "ppt/notesMasters/notesMaster1.xml"
            let notesThemePath = "ppt/theme/theme\(themeCount + 1).xml"
            var notesMaster = PPTXPartWriter(path: notesMasterPath, state: state)
            _ = notesMaster.relationship(type: PPTXRelationshipType.theme, to: notesThemePath)
            writeNotesMaster(into: &notesMaster)
            add(notesMaster, contentType: PPTXContentType.notesMaster)
            let firstTheme = presentation.themes[0]
            add(notesThemePath, PPTXThemeWriter.part(name: firstTheme.name, colors: firstTheme.colors, fonts: firstTheme.fonts),
                contentType: PPTXContentType.theme)

            // Slides, and notes slides for those with notes. Slides with comments relate to a comment part each, and
            // the presentation to the authors of every comment.
            var notesCount = 0
            let commentAuthors = PPTXComments.AuthorList(presentation)
            var commentIDs = Set<UUID>(), slideCreationIDs = Set<UInt32>()
            for (index, slide) in presentation.slides.enumerated() {
                let slidePath = "ppt/slides/slide\(index + 1).xml"
                var part = PPTXPartWriter(path: slidePath, state: state)
                part.slideNumber = index + 1
                let presentation = presentation
                part.measureRows = { table, element in
                    PPTXTableMeasure.rowHeights(table, style: presentation.style(for: element, on: slide), slideNumber: index + 1)
                }
                _ = part.relationship(type: PPTXRelationshipType.slideLayout, to: layoutPathsByID[slide.layoutID] ?? "ppt/slideLayouts/slideLayout1.xml")
                if !slide.notes.isEmpty {
                    notesCount += 1
                    let notesPath = "ppt/notesSlides/notesSlide\(notesCount).xml"
                    _ = part.relationship(type: PPTXRelationshipType.notesSlide, to: notesPath)
                    var notes = PPTXPartWriter(path: notesPath, state: state)
                    _ = notes.relationship(type: PPTXRelationshipType.notesMaster, to: notesMasterPath)
                    _ = notes.relationship(type: PPTXRelationshipType.slide, to: slidePath)
                    writeNotes(slide.notes, into: &notes)
                    add(notes, contentType: PPTXContentType.notesSlide)
                }
                let threads = slide.comments.filter { !$0.comments.isEmpty }
                var comments: (path: String, relationship: String, creationID: UInt32)?
                if !threads.isEmpty {
                    var creationID = PPTXComments.slideCreationID(slide.id)
                    while !slideCreationIDs.insert(creationID).inserted { creationID = creationID == UInt32.max ? 1 : creationID + 1 }
                    let path = "ppt/comments/modernComment_\(String(256 + index, radix: 16, uppercase: true))_"
                        + "\(String(creationID, radix: 16, uppercase: true)).xml"
                    comments = (path, part.relationship(type: PPTXRelationshipType.modernComments, to: path), creationID)
                    part.commentAnchors = Set(threads.compactMap(\.elementID))
                }
                writeSlide(slide, comments: comments.map { ($0.relationship, $0.creationID) }, into: &part)
                add(part, contentType: PPTXContentType.slide)
                if let comments {
                    // Positions are measured from each object's frame as written: groups' are their children's bounds.
                    var frames: [UUID: SlideRect] = [:]
                    for id in part.commentAnchors {
                        guard let element = PPTXComments.element(id, in: slide.elements) else { continue }
                        var frame = presentation.placement(of: element, on: slide).frame
                        if let children = element.children, let bounds = PPTXGroupTransform.bounds(of: children.filter(part.isWritable)) { frame = bounds }
                        frames[id] = frame.standardized
                    }
                    let target = PPTXComments.SlideTarget(slideID: 256 + index, creationID: comments.creationID, shapes: part.writtenShapes, frames: frames)
                    add(comments.path, PPTXComments.commentsPart(threads, target: target, authors: commentAuthors, usedIDs: &commentIDs),
                        contentType: PPTXContentType.modernComments)
                }
            }
            if !commentAuthors.isEmpty {
                add("ppt/authors.xml", PPTXComments.authorsPart(commentAuthors), contentType: PPTXContentType.authors)
            }

            // The presentation part and its relationships.
            var main = PPTXPartWriter(path: "ppt/presentation.xml", state: state)
            let masterRelationships = presentation.themes.indices.map {
                main.relationship(type: PPTXRelationshipType.slideMaster, to: "ppt/slideMasters/slideMaster\($0 + 1).xml")
            }
            let notesMasterRelationship = main.relationship(type: PPTXRelationshipType.notesMaster, to: notesMasterPath)
            let slideRelationships = presentation.slides.indices.map {
                main.relationship(type: PPTXRelationshipType.slide, to: "ppt/slides/slide\($0 + 1).xml")
            }
            _ = main.relationship(type: PPTXRelationshipType.presProps, to: "ppt/presProps.xml")
            _ = main.relationship(type: PPTXRelationshipType.viewProps, to: "ppt/viewProps.xml")
            _ = main.relationship(type: PPTXRelationshipType.theme, to: "ppt/theme/theme1.xml")
            _ = main.relationship(type: PPTXRelationshipType.tableStyles, to: "ppt/tableStyles.xml")
            if !commentAuthors.isEmpty { _ = main.relationship(type: PPTXRelationshipType.authors, to: "ppt/authors.xml") }
            main.xml.raw("<p:presentation\(PPTXNamespace.presentationRoot) saveSubsetFonts=\"1\"><p:sldMasterIdLst>")
            for (id, relationship) in zip(masterIDs, masterRelationships) {
                main.xml.raw("<p:sldMasterId id=\"\(id)\" r:id=\"\(relationship)\"/>")
            }
            main.xml.raw("</p:sldMasterIdLst><p:notesMasterIdLst><p:notesMasterId r:id=\"\(notesMasterRelationship)\"/></p:notesMasterIdLst>")
            if !slideRelationships.isEmpty {
                main.xml.raw("<p:sldIdLst>")
                for (index, relationship) in slideRelationships.enumerated() {
                    main.xml.raw("<p:sldId id=\"\(256 + index)\" r:id=\"\(relationship)\"/>")
                }
                main.xml.raw("</p:sldIdLst>")
            }
            let size = Self.slideSizeEMU(presentation.slideSize)
            main.xml.raw("<p:sldSz cx=\"\(size.width)\" cy=\"\(size.height)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>")
            if !presentation.defaultTextStyle.isEmpty { main.listStyle("p:defaultTextStyle", presentation.defaultTextStyle) }
            PPTXGuides.write(presentation.guides, into: &main.xml)
            main.xml.raw("</p:presentation>")
            add(main, contentType: PPTXContentType.presentation)

            add("ppt/presProps.xml", Self.document("<p:presentationPr\(PPTXNamespace.presentationRoot)/>"), contentType: PPTXContentType.presProps)
            add("ppt/viewProps.xml", Self.document("<p:viewPr\(PPTXNamespace.presentationRoot)><p:normalViewPr><p:restoredLeft sz=\"15620\"/>"
                + "<p:restoredTop sz=\"94660\"/></p:normalViewPr><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"),
                contentType: PPTXContentType.viewProps)
            add("ppt/tableStyles.xml", Self.document("<a:tblStyleLst xmlns:a=\"\(PPTXNamespace.drawing)\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"),
                contentType: PPTXContentType.tableStyles)
            add("docProps/core.xml", coreProperties(), contentType: PPTXContentType.coreProperties)
            add("docProps/app.xml", applicationProperties(notes: notesCount), contentType: PPTXContentType.extendedProperties)

            // Charts, each with the workbook holding its numbers.
            for chart in state.chartParts {
                add(chart.chartPath, chart.chart, contentType: PPTXContentType.chart)
                add(PPTXPackage.relationshipsPath(for: chart.chartPath), chart.relationships, contentType: nil)
                add(chart.workbookPath, chart.workbook, contentType: nil)
            }

            var root = PPTXRelationshipsWriter()
            _ = root.add(type: PPTXRelationshipType.officeDocument, target: "ppt/presentation.xml")
            _ = root.add(type: PPTXRelationshipType.coreProperties, target: "docProps/core.xml")
            _ = root.add(type: PPTXRelationshipType.extendedProperties, target: "docProps/app.xml")

            // Media, one part per picture, movie or sound used, typed by extension.
            var defaults: [String: String] = ["rels": PPTXContentType.relationships, "xml": PPTXContentType.xml]
            if !state.chartParts.isEmpty { defaults["xlsx"] = PPTXContentType.workbook }
            var mediaOverrides: [(path: String, type: String)] = []
            for (path, item) in state.mediaParts {
                let fileExtension = String(path[path.index(after: path.lastIndex(of: ".") ?? path.startIndex)...])
                let known = PPTXContentType.image(forExtension: fileExtension) ?? PPTXMedia.contentType(forExtension: fileExtension)
                let type = known ?? PPTXContentType.canonical(item.contentType)
                if defaults[fileExtension] == nil, known != nil {
                    defaults[fileExtension] = type
                } else if defaults[fileExtension] != type {
                    mediaOverrides.append((path, type))
                }
                add(path, item.data, contentType: nil)
            }

            var zip = ZipWriter(date: date)
            try zip.add("[Content_Types].xml", contentTypes(defaults: defaults, mediaOverrides: mediaOverrides))
            try zip.add("_rels/.rels", root.data())
            let compressedFormats: Set<String> = ["png", "jpeg", "gif", "webp", "xlsx", "mp4", "m4v", "mov", "wmv", "avi", "mp3", "m4a", "aac", "wma"]
            for part in parts {
                // Most images, movies and sounds, and workbooks, are compressed already.
                let fileExtension = part.path.split(separator: ".").last.map(String.init) ?? ""
                try zip.add(part.path, part.data, compress: !compressedFormats.contains(fileExtension))
            }
            return try zip.finish()
        }

        static func slideSizeEMU(_ size: SlideSize) -> (width: Int, height: Int) {
            // PowerPoint's limits: 1 to 56 inches.
            let range = 914_400...51_206_400
            return (PPTXValue.clamped(size.width * EMU.perPoint, range, fallback: 9_144_000),
                    PPTXValue.clamped(size.height * EMU.perPoint, range, fallback: 5_143_500))
        }

        static func document(_ markup: String) -> Data {
            var xml = XMLWriter(reservingCapacity: markup.utf8.count + 64)
            xml.raw(markup)
            return xml.data
        }

        // MARK: Parts

        private func writeMaster(_ theme: Theme, layouts: [(id: Int, relationship: String)], into part: inout PPTXPartWriter) {
            let presentation = presentation
            part.measureRows = { table, element in
                PPTXTableMeasure.rowHeights(table, style: presentation.style(forThemeElement: element, theme: theme), slideNumber: nil)
            }
            part.xml.raw("<p:sldMaster\(PPTXNamespace.presentationRoot)><p:cSld>")
            part.background(theme.background)
            part.shapeTree(theme.elements)
            part.xml.raw("</p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" "
                + "accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>")
            part.xml.raw("<p:sldLayoutIdLst>")
            for layout in layouts { part.xml.raw("<p:sldLayoutId id=\"\(layout.id)\" r:id=\"\(layout.relationship)\"/>") }
            part.xml.raw("</p:sldLayoutIdLst><p:txStyles>")
            part.listStyle("p:titleStyle", theme.titleStyle)
            part.listStyle("p:bodyStyle", theme.bodyStyle)
            part.listStyle("p:otherStyle", theme.otherStyle)
            part.xml.raw("</p:txStyles></p:sldMaster>")
        }

        private func writeLayout(_ layout: Layout, into part: inout PPTXPartWriter) {
            part.xml.raw("<p:sldLayout\(PPTXNamespace.presentationRoot)")
            if !layout.showsThemeElements { part.xml.raw(" showMasterSp=\"0\"") }
            part.xml.raw(" type=\"\(layout.kind.fileType)\" preserve=\"1\"><p:cSld")
            part.xml.attribute("name", layout.name)
            part.xml.raw(">")
            if let background = layout.background { part.background(background) }
            part.shapeTree(layout.elements)
            part.xml.raw("</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>")
        }

        /// A slide. One with comments names its creation id, which the comments' slide moniker names too, and its comment
        /// part, as PowerPoint does.
        private func writeSlide(_ slide: Slide, comments: (relationship: String, creationID: UInt32)?, into part: inout PPTXPartWriter) {
            part.xml.raw("<p:sld\(PPTXNamespace.presentationRoot)")
            if slide.isSkipped { part.xml.raw(" show=\"0\"") }
            part.xml.raw("><p:cSld>")
            if let background = slide.background { part.background(background) }
            part.shapeTree(slide.elements)
            if let comments {
                part.xml.raw("<p:extLst><p:ext uri=\"\(PPTXComments.slideCreationIDExtension)\"><p14:creationId xmlns:p14=\"\(PPTXNamespace.powerPoint2010)\"")
                part.xml.raw(" val=\"\(comments.creationID)\"/></p:ext></p:extLst>")
            }
            part.xml.raw("</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>")
            // Then the transition, the timing and the extensions, in the schema's order.
            if let transition = slide.transition { PPTXTransitions.write(transition, into: &part.xml) }
            PPTXAnimationWriter.write(slide, shapes: part.writtenShapes, clips: part.writtenClips, into: &part.xml)
            if let comments {
                part.xml.raw("<p:extLst><p:ext uri=\"\(PPTXComments.commentRelationshipExtension)\"><p188:commentRel xmlns:p188=\"\(PPTXNamespace.powerPoint2018)\"")
                part.xml.raw(" r:id=\"\(comments.relationship)\"/></p:ext></p:extLst>")
            }
            part.xml.raw("</p:sld>")
        }

        private func writeNotes(_ notes: TextBody, into part: inout PPTXPartWriter) {
            part.xml.raw("<p:notes\(PPTXNamespace.presentationRoot)><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/>")
            part.xml.raw("<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/>")
            part.xml.raw("<a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>")
            part.xml.raw("<p:sp><p:nvSpPr><p:cNvPr id=\"\(part.takeShapeID())\" name=\"Slide Image Placeholder 1\"/>")
            part.xml.raw("<p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr>")
            part.xml.raw("</p:nvSpPr><p:spPr/></p:sp>")
            part.xml.raw("<p:sp><p:nvSpPr><p:cNvPr id=\"\(part.takeShapeID())\" name=\"Notes Placeholder 2\"/>")
            part.xml.raw("<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/>")
            part.textBody(notes, tag: "p:txBody")
            part.xml.raw("</p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>")
        }

        /// PowerPoint's notes master: header, date, slide image, notes, footer and slide number on a portrait page.
        private func writeNotesMaster(into part: inout PPTXPartWriter) {
            part.xml.raw("<p:notesMaster\(PPTXNamespace.presentationRoot)><p:cSld><p:bg><p:bgPr><a:solidFill><a:schemeClr val=\"lt1\"/>")
            part.xml.raw("</a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/>")
            part.xml.raw("<p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/>")
            part.xml.raw("<a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>")
            // The slide image keeps the slide's proportions inside the space PowerPoint gives it.
            let slide = Self.slideSizeEMU(presentation.slideSize)
            let box = (x: 685_800.0, y: 1_143_000.0, width: 5_486_400.0, height: 3_086_100.0)
            let scale = min(box.width / Double(slide.width), box.height / Double(slide.height))
            let imageWidth = (Double(slide.width) * scale).rounded(), imageHeight = (Double(slide.height) * scale).rounded()
            let image = (x: Int(box.x + (box.width - imageWidth) / 2), y: Int(box.y + (box.height - imageHeight) / 2),
                         width: Int(imageWidth), height: Int(imageHeight))
            let placeholders: [(name: String, type: String, index: Int, frame: (Int, Int, Int, Int), anchor: String?, align: String?)] = [
                ("Header Placeholder 1", "hdr", 0, (0, 0, 2_971_800, 458_788), nil, "l"),
                ("Date Placeholder 2", "dt", 1, (3_884_613, 0, 2_971_800, 458_788), nil, "r"),
                ("Slide Image Placeholder 3", "sldImg", 2, (image.x, image.y, image.width, image.height), nil, nil),
                ("Notes Placeholder 4", "body", 3, (685_800, 4_400_550, 5_486_400, 3_600_450), nil, nil),
                ("Footer Placeholder 5", "ftr", 4, (0, 8_685_213, 2_971_800, 458_787), "b", "l"),
                ("Slide Number Placeholder 6", "sldNum", 5, (3_884_613, 8_685_213, 2_971_800, 458_787), "b", "r"),
            ]
            for placeholder in placeholders {
                part.xml.raw("<p:sp><p:nvSpPr><p:cNvPr id=\"\(part.takeShapeID())\" name=\"\(placeholder.name)\"/><p:cNvSpPr>")
                part.xml.raw(placeholder.type == "sldImg" ? "<a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/>" : "<a:spLocks noGrp=\"1\"/>")
                part.xml.raw("</p:cNvSpPr><p:nvPr><p:ph type=\"\(placeholder.type)\"")
                if placeholder.index != 0 { part.xml.raw(" idx=\"\(placeholder.index)\"") }
                let (x, y, width, height) = placeholder.frame
                part.xml.raw("/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm>")
                part.xml.raw("<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>")
                if placeholder.type == "sldImg" {
                    part.xml.raw("<a:noFill/><a:ln w=\"12700\"><a:solidFill><a:prstClr val=\"black\"/></a:solidFill></a:ln></p:spPr></p:sp>")
                    continue
                }
                part.xml.raw("</p:spPr><p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\"")
                if let anchor = placeholder.anchor { part.xml.raw(" anchor=\"\(anchor)\"") }
                part.xml.raw("/><a:lstStyle>")
                if let align = placeholder.align { part.xml.raw("<a:lvl1pPr algn=\"\(align)\"><a:defRPr sz=\"1200\"/></a:lvl1pPr>") }
                part.xml.raw("</a:lstStyle><a:p>")
                switch placeholder.type {
                case "sldNum": part.xml.raw("<a:fld id=\"{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}\" type=\"slidenum\"><a:t>‹#›</a:t></a:fld>")
                case "body": part.xml.raw("<a:r><a:t>Click to edit Master text styles</a:t></a:r>")
                default: break
                }
                part.xml.raw("</a:p></p:txBody></p:sp>")
            }
            part.xml.raw("</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" ")
            part.xml.raw("accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>")
            part.xml.raw("<p:notesStyle>")
            for level in 0...8 {
                part.xml.raw("<a:lvl\(level + 1)pPr marL=\"\(level * 457_200)\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" ")
                part.xml.raw("latinLnBrk=\"0\" hangingPunct=\"1\"><a:defRPr sz=\"1200\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/>")
                part.xml.raw("</a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr>")
                part.xml.raw("</a:lvl\(level + 1)pPr>")
            }
            part.xml.raw("</p:notesStyle></p:notesMaster>")
        }

        // MARK: Document properties

        /// The title, and PuggleSlides as the creator: never anyone's name.
        private func coreProperties() -> Data {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(identifier: "UTC")
            let stamp = formatter.string(from: date)
            var xml = XMLWriter(reservingCapacity: 1024)
            xml.raw("<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
                + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" "
                + "xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">")
            if let title = presentation.title, !title.isEmpty {
                xml.raw("<dc:title>")
                xml.text(title)
                xml.raw("</dc:title>")
            }
            xml.raw("<dc:creator>PuggleSlides</dc:creator><cp:lastModifiedBy>PuggleSlides</cp:lastModifiedBy><cp:revision>1</cp:revision>")
            xml.raw("<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:created>")
            xml.raw("<dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:modified></cp:coreProperties>")
            return xml.data
        }

        private func applicationProperties(notes: Int) -> Data {
            var xml = XMLWriter(reservingCapacity: 512)
            xml.raw("<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" "
                + "xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">")
            xml.raw("<Application>PuggleSlides</Application><Slides>\(presentation.slides.count)</Slides><Notes>\(notes)</Notes>")
            xml.raw("<HiddenSlides>\(presentation.slides.filter(\.isSkipped).count)</HiddenSlides></Properties>")
            return xml.data
        }

        private func contentTypes(defaults: [String: String], mediaOverrides: [(path: String, type: String)]) -> Data {
            var xml = XMLWriter(reservingCapacity: 4096)
            xml.raw("<Types xmlns=\"\(PPTXNamespace.contentTypes)\">")
            for (fileExtension, type) in defaults.sorted(by: { $0.key < $1.key }) {
                xml.raw("<Default")
                xml.attribute("Extension", fileExtension)
                xml.attribute("ContentType", type)
                xml.raw("/>")
            }
            for part in parts {
                guard let type = part.contentType else { continue }
                xml.raw("<Override")
                xml.attribute("PartName", "/" + part.path)
                xml.attribute("ContentType", type)
                xml.raw("/>")
            }
            for media in mediaOverrides {
                xml.raw("<Override")
                xml.attribute("PartName", "/" + media.path)
                xml.attribute("ContentType", media.type)
                xml.raw("/>")
            }
            xml.raw("</Types>")
            return xml.data
        }
    }
}
