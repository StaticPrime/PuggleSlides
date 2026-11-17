#if DEBUG
import AppKit
import PuggleSlidesKit

/// A sample deck for `-PPSampleDocument YES`: every layout kind, lists, shapes, lines, an image and notes.
enum SampleContent {
    static func make() -> Presentation {
        var presentation = Presentation.makeDefault()
        let theme = presentation.themes[0]
        func layout(_ kind: LayoutKind) -> UUID { theme.layout(kind: kind)!.id }
        func slide(_ kind: LayoutKind, texts: [TextBody], notes: String = "") -> Slide {
            var slide = presentation.makeSlide(layoutID: layout(kind))
            for (index, text) in texts.enumerated() where index < slide.elements.count { slide.elements[index].shape?.text = text }
            if !notes.isEmpty { slide.notes = TextBody(notes) }
            return slide
        }
        func bullets(_ items: [(String, Int)]) -> TextBody {
            TextBody(paragraphs: items.map { TextParagraph($0.0, level: $0.1) })
        }

        var slides: [Slide] = []
        slides.append(slide(.title, texts: [TextBody("Quarterly Puggle Review"), TextBody("Treats, walks and naps · Q3 2026")],
                            notes: "Welcome everyone. Keep it short: there are treats at the end."))
        slides.append(slide(.titleAndBody, texts: [TextBody("Highlights"), bullets([
            ("Walks are up 24% since spring", 0), ("Morning walks now 30 minutes", 1), ("Evening walks unchanged", 1),
            ("Nap quality reached a record high", 0), ("New squeaky toy adopted by the whole pack", 0),
        ])], notes: "Mention the new park route."))
        var steps = slide(.titleAndTwoColumns, texts: [TextBody("Before and after"),
                                                       bullets([("Leash pulling", 0), ("Barking at the mail", 0), ("Shoe chewing", 0)]),
                                                       bullets([("Calm walks", 0), ("Polite greetings", 0), ("Chews only toys", 0)])])
        if var body = steps.elements[2].shape?.text {
            for index in body.paragraphs.indices { body.paragraphs[index].style.bullet = .number(.arabicPeriod, startAt: 1) }
            steps.elements[2].shape?.text = body
        }
        slides.append(steps)

        var shapes = slide(.titleOnly, texts: [TextBody("Shapes and lines")])
        func shape(_ preset: String, _ frame: SlideRect, fill: ColorRef, text: String = "") -> SlideElement {
            var body = TextBody(properties: TextBodyProperties(anchor: .middle, insets: .standard, autofit: Autofit.none, wraps: true))
            body.listStyle[0] = LevelStyle(paragraph: ParagraphStyle(alignment: .center),
                                           character: CharacterStyle(fontSize: 14, color: ColorRef(theme: .light1)))
            if !text.isEmpty { body.paragraphs = [TextParagraph(text)] }
            return SlideElement(name: preset, placement: Placement(frame: frame),
                                content: .shape(Shape(geometry: .preset(preset, adjustments: PresetGeometry.defaultAdjustments(preset)),
                                                      fill: .solid(fill), outline: Outline(fill: .solid(ColorRef(theme: .dark2)), width: 0.75), text: body)))
        }
        shapes.elements += [
            shape("roundRect", SlideRect(x: 40, y: 120, width: 150, height: 90), fill: ColorRef(theme: .accent1), text: "Plan"),
            shape("ellipse", SlideRect(x: 280, y: 120, width: 150, height: 90), fill: ColorRef(theme: .accent4), text: "Walk"),
            shape("star5", SlideRect(x: 530, y: 110, width: 110, height: 110), fill: ColorRef(theme: .accent5)),
            SlideElement(name: "Arrow 1", placement: Placement(frame: SlideRect(x: 195, y: 165, width: 80, height: 0)),
                         content: .shape(Shape(geometry: .preset("straightConnector1", adjustments: [:]),
                                               outline: Outline(fill: .solid(ColorRef(theme: .dark2)), width: 2, tail: .fillArrow), isConnector: true))),
            SlideElement(name: "Arrow 2", placement: Placement(frame: SlideRect(x: 435, y: 165, width: 90, height: 0)),
                         content: .shape(Shape(geometry: .preset("straightConnector1", adjustments: [:]),
                                               outline: Outline(fill: .solid(ColorRef(theme: .dark2)), width: 2, dash: .dash, tail: .strokeArrow),
                                               isConnector: true))),
            shape("rightArrow", SlideRect(x: 60, y: 260, width: 180, height: 70), fill: ColorRef(theme: .accent3), text: "Next steps"),
            shape("rect", SlideRect(x: 300, y: 262, width: 140, height: 66), fill: ColorRef(theme: .accent2), text: "Rotated"),
        ]
        shapes.elements[shapes.elements.count - 1].placement?.rotation = 12
        var note = TextBody("A text box with bold and colored words.", properties: TextBodyProperties(anchor: .top, insets: .standard, autofit: .resizeShape, wraps: true))
        note.paragraphs[0].runs = [TextRun("A text box with "), TextRun("bold", style: CharacterStyle(bold: true)), TextRun(" and "),
                                   TextRun("colored", style: CharacterStyle(color: ColorRef(theme: .accent1))), TextRun(" words.")]
        shapes.elements.append(SlideElement(name: "TextBox", placement: Placement(frame: SlideRect(x: 480, y: 270, width: 200, height: 50)),
                                            content: .shape(Shape(text: note, isTextBox: true))))
        slides.append(shapes)

        slides.append(slide(.sectionHeader, texts: [TextBody("Looking ahead")]))
        slides.append(slide(.bigNumber, texts: [TextBody("87%"), TextBody("of walks ended in a nap")]))
        slides.append(slide(.mainPoint, texts: [TextBody("Every dog deserves a good slide deck.")]))

        var picture = slide(.caption, texts: [TextBody("A generated picture, cropped a little at the sides")])
        let image = sampleImage()
        let mediaID = presentation.addMedia(image, contentType: "image/png")
        picture.elements.insert(SlideElement(name: "Picture", placement: Placement(frame: SlideRect(x: 160, y: 30, width: 400, height: 280)),
                                             content: .picture(Picture(mediaID: mediaID, crop: ImageCrop(left: 0.05, right: 0.05),
                                                                       outline: Outline(fill: .solid(ColorRef(theme: .dark2)), width: 1)))), at: 0)
        slides.append(picture)
        // A table with a header row and a merged cell.
        var tableSlide = slide(.titleOnly, texts: [TextBody("Walks by month")])
        var tableElement = presentation.makeTableElement(rows: 4, columns: 3)
        if var table = tableElement.table {
            let rows = [["Month", "Walks", "Naps"], ["July", "42", "61"], ["August", "47", "58"], ["September", "51", "64"]]
            for (row, values) in rows.enumerated() {
                for (column, value) in values.enumerated() {
                    table.cells[row][column].text.paragraphs = [TextParagraph(value)]
                    if column > 0 { table.cells[row][column].text.paragraphs[0].style.alignment = .center }
                }
            }
            for column in 0..<3 {
                table.cells[0][column].fill = .solid(ColorRef(theme: .accent1))
                table.cells[0][column].text.paragraphs[0].runs = table.cells[0][column].text.paragraphs[0].runs.map {
                    TextRun($0.text, style: CharacterStyle(bold: true, color: ColorRef(theme: .light1)))
                }
            }
            table.insertRows(at: 4)
            table.cells[4][0].text.paragraphs = [TextParagraph("Every walk ended in a nap.", style: CharacterStyle(italic: true))]
            table.merge(TableCellRange(firstRow: 4, firstColumn: 0, lastRow: 4, lastColumn: 2))
            tableElement.table = table
            tableElement.placement?.frame.y = 110
        }
        tableSlide.elements.append(tableElement)
        slides.append(tableSlide)

        // A chart of its own numbers.
        var chartSlide = slide(.titleOnly, texts: [TextBody("Treats per week")])
        var chartElement = presentation.makeChartElement(.column)
        chartElement.chart = Chart(kind: .column, data: ChartData(labelHeading: "Week", labels: ["Week 1", "Week 2", "Week 3", "Week 4"], series: [
            ChartSeries(name: "Biscuits", values: [12, 15, 11, 18]), ChartSeries(name: "Chews", values: [5, 7, 9, 6]),
        ]), title: "Treats per week", verticalAxisTitle: "Treats")
        chartElement.placement?.frame.y = 100
        chartSlide.elements.append(chartElement)
        slides.append(chartSlide)

        // Word art, and pictures recolored and faded.
        var art = slide(.blank, texts: [])
        art.elements.append(SlideElement(name: "Word Art", placement: Placement(frame: SlideRect(x: 160, y: 40, width: 400, height: 110)),
                                         content: .shape(Shape.wordArt("Good dogs!", fontFamily: "Arial"))))
        for (index, adjustments) in [ImageAdjustments(recolor: .grayscale), ImageAdjustments(recolor: .dark(.accent1)),
                                     ImageAdjustments(transparency: 0.5, brightness: 0.2), ImageAdjustments(recolor: .sepia)].enumerated() {
            art.elements.append(SlideElement(name: "Picture \(index + 1)", placement: Placement(frame: SlideRect(x: 40 + Double(index) * 165, y: 200,
                                                                                                                  width: 150, height: 100)),
                                             content: .picture(Picture(mediaID: mediaID, adjustments: adjustments))))
        }
        slides.append(art)

        // A video that plays when the slide appears, and a sound that waits for a click.
        var clips = slide(.titleOnly, texts: [TextBody("A day at the park")], notes: "The video plays by itself; click for the sound.")
        let movieID = presentation.addMedia(sampleMovie(), contentType: "video/mp4")
        let posterID = presentation.addMedia(samplePoster(), contentType: "image/png")
        let soundID = presentation.addMedia(sampleSound(), contentType: "audio/wav")
        clips.elements.append(SlideElement(name: "Video 1", placement: Placement(frame: SlideRect(x: 200, y: 110, width: 320, height: 180)),
                                           content: .media(MediaClip(kind: .video, mediaID: movieID, posterID: posterID, playback: .automatically))))
        clips.elements.append(SlideElement(name: "Audio 1", placement: Placement(frame: SlideRect(x: 560, y: 266, width: audioIconSize, height: audioIconSize)),
                                           content: .media(MediaClip(kind: .audio, mediaID: soundID)), altDescription: "A short tone"))
        slides.append(clips)

        var skipped = slide(.blank, texts: [], notes: "This slide is skipped in slideshows.")
        skipped.isSkipped = true
        slides.append(skipped)

        // Motion: the highlights fade in point by point, the shapes arrive on a cube and zoom and spin in.
        slides[1].transition = SlideTransition(kind: .fade, duration: 0.6)
        slides[1].animations = [
            SlideAnimation(elementID: slides[1].elements[0].id, effect: .fadeIn, start: .afterPrevious, duration: 0.6),
            SlideAnimation(elementID: slides[1].elements[1].id, effect: .flyInFromLeft, start: .onClick, duration: 0.6, byParagraph: true),
        ]
        slides[3].transition = SlideTransition(kind: .cube, duration: 1)
        let shapeIDs = slides[3].elements.filter { $0.placeholder == nil }.map(\.id)
        slides[3].animations = [
            SlideAnimation(elementID: shapeIDs[0], effect: .zoomIn, start: .onClick, duration: 0.5),
            SlideAnimation(elementID: shapeIDs[1], effect: .zoomIn, start: .afterPrevious, duration: 0.5),
            SlideAnimation(elementID: shapeIDs[2], effect: .spin, start: .afterPrevious, duration: 1),
        ]
        slides[4].transition = SlideTransition(kind: .slideFromRight, duration: 0.5)
        slides[5].transition = SlideTransition(kind: .dissolve, duration: 0.8)
        slides[6].transition = SlideTransition(kind: .flip, duration: 0.8)

        // Comments: a discussion about the highlights, and one already resolved.
        let day: TimeInterval = 86_400
        slides[1].comments = [
            CommentThread(comments: [
                Comment(author: "Alex Kim", date: Date().addingTimeInterval(-2 * day), text: "Can we add last year’s numbers to compare?"),
                Comment(author: "Jordan Lee", date: Date().addingTimeInterval(-day), text: "Good idea. I’ll add them next to each point."),
            ], elementID: slides[1].elements[1].id, position: SlidePoint(x: 660, y: 110)),
        ]
        slides[5].comments = [
            CommentThread(comments: [Comment(author: "Jordan Lee", date: Date().addingTimeInterval(-3 * day), text: "Is 87% the final figure?")],
                          isResolved: true, position: SlidePoint(x: 8, y: 8)),
        ]

        presentation.slides = slides
        presentation.setSlideNumbers(true, slideIDs: Set(slides.dropFirst().map(\.id)))
        return presentation
    }

    /// A two-second movie, 160 × 90 in H.264: a white ball rolling across an amber background.
    static func sampleMovie() -> Data {
        let text = """
        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\
        AAAYc3RjbwAAAAAAAAACAAAALAAAA8c=
        """
        return Data(base64Encoded: text) ?? Data()
    }

    /// The movie's first frame, as its poster.
    static func samplePoster() -> Data {
        let image = NSImage(size: NSSize(width: 320, height: 180), flipped: false) { rect in
            NSColor(srgbRed: 0.98, green: 0.74, blue: 0.2, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 320, height: 44).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 16, y: 44, width: 48, height: 48)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }

    /// A second of a soft 440 Hz tone: 8 kHz, 16-bit mono WAV.
    static func sampleSound() -> Data {
        let rate = 8000, count = 8000
        var data = Data()
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(UInt32(36 + count * 2))
        append("WAVEfmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(rate))
        append32(UInt32(rate * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(count * 2))
        for index in 0..<count {
            // Fades in and out so it doesn't click.
            let envelope = min(1, Double(index) / 400, Double(count - index) / 400)
            let sample = sin(Double(index) * 2 * .pi * 440 / Double(rate)) * envelope * 0.3
            append16(UInt16(bitPattern: Int16(sample * Double(Int16.max))))
        }
        return data
    }

    /// A small landscape: sky, sun and hills, as PNG data.
    static func sampleImage() -> Data {
        let size = NSSize(width: 480, height: 320)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.78, blue: 0.98, alpha: 1), ending: NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 1))!
                .draw(in: rect, angle: 90)
            NSColor(srgbRed: 1, green: 0.78, blue: 0.25, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 330, y: 200, width: 80, height: 80)).fill()
            NSColor(srgbRed: 0.35, green: 0.62, blue: 0.4, alpha: 1).setFill()
            let hill = NSBezierPath()
            hill.move(to: .zero)
            hill.curve(to: NSPoint(x: 480, y: 70), controlPoint1: NSPoint(x: 160, y: 190), controlPoint2: NSPoint(x: 300, y: 40))
            hill.line(to: NSPoint(x: 480, y: 0))
            hill.close()
            hill.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
#endif
