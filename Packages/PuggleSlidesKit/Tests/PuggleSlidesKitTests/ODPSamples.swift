import Foundation
@testable import PuggleSlidesKit

/// Presentations that use everything an OpenDocument presentation can hold of the model.
enum ODPSamples {
    static let photo = PPTXTestImage.gradient(48, from: (0.95, 0.62, 0.22), to: (0.12, 0.35, 0.65))
    static let texture = PPTXTestImage.png(width: 8, height: 8) { x, y in (x + y) % 2 == 0 ? (240, 240, 230) : (200, 190, 170) }

    static func shape(_ name: String, _ frame: SlideRect, rotation: Double = 0, flipH: Bool = false, flipV: Bool = false,
                      _ shape: Shape, title: String? = nil, description: String? = nil) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: frame, rotation: rotation, flipHorizontal: flipH, flipVertical: flipV),
                     content: .shape(shape), altTitle: title, altDescription: description)
    }

    /// A group of elements in slide coordinates, placed at their bounding box.
    static func group(_ children: [SlideElement], name: String, title: String? = nil, description: String? = nil) -> SlideElement {
        let bounds = children.compactMap { $0.placement?.boundingBox }.reduce(nil as SlideRect?) { $0?.union($1) ?? $1 } ?? .zero
        return SlideElement(name: name, placement: Placement(frame: bounds), content: .group(children), altTitle: title, altDescription: description)
    }

    /// Two themes, a custom layout with its own look, every kind of element, rich text, lists, links, fields, notes,
    /// a skipped slide, every transition, and every animation effect and start.
    static func rich() -> Presentation {
        var light = BuiltInThemes.simpleLight()
        var harbor = BuiltInThemes.make(BuiltInThemes.designs[3])
        harbor.background = .gradient(GradientFill(kind: .linear(angle: 45), stops: [
            GradientStop(position: 0, color: ColorRef(theme: .light1)),
            GradientStop(position: 1, color: ColorRef(.theme(.light2), lumMod: 0.75)),
        ]))
        var presentation = Presentation(themes: [], defaultTextStyle: BuiltInThemes.defaultTextStyle, title: "Quarterly Review & <Plans> \"2026\"")
        let photo = presentation.addMedia(Self.photo, contentType: "image/png")
        let texture = presentation.addMedia(Self.texture, contentType: "image/png")

        // A layout of its own: a photo backdrop without the theme's decorations, an oval title and a picture placeholder.
        var ovalTitle = BuiltInThemes.placeholder(.title, name: "Title", frame: SlideRect(x: 40, y: 260, width: 640, height: 80), anchor: .middle)
        ovalTitle.shape?.geometry = .preset("ellipse", adjustments: [:])
        let photoLayout = Layout(name: "Photo backdrop", kind: .custom, elements: [
            ovalTitle,
            SlideElement(name: "Picture Placeholder", placement: Placement(frame: SlideRect(x: 400, y: 40, width: 280, height: 200)),
                         placeholder: PlaceholderRef(type: .picture, index: 1), content: .shape(Shape(text: TextBody()))),
        ], background: .picture(PictureFill(mediaID: photo)), showsThemeElements: false)
        light.layouts.append(photoLayout)
        presentation.themes = [light, harbor]

        func layout(_ kind: LayoutKind, in theme: Theme = light) -> UUID { theme.layout(kind: kind)!.id }

        // 1. Title slide: inherited placeholders with rich runs.
        var title = presentation.makeSlide(layoutID: layout(.title))
        title.elements[0].shape?.text = TextBody(paragraphs: [TextParagraph(runs: [
            TextRun("Quarterly ", style: CharacterStyle(bold: true)),
            TextRun("Review", style: CharacterStyle(bold: true, color: ColorRef(.theme(.accent1), lumMod: 0.75))),
        ])])
        title.elements[1].shape?.text = TextBody(paragraphs: [TextParagraph(runs: [
            TextRun("Prepared for the "),
            TextRun("whole team", style: CharacterStyle(italic: true, underline: true, color: ColorRef(RGBColor(red: 0x12, green: 0x34, blue: 0x56)))),
        ])])
        title.transition = SlideTransition(kind: .fade)
        title.animations = [
            SlideAnimation(elementID: title.elements[0].id, effect: .appear, start: .onClick),
            SlideAnimation(elementID: title.elements[1].id, effect: .fadeIn, start: .withPrevious, duration: 1, delay: 0.25),
        ]

        var skipped = presentation.makeSlide(layoutID: layout(.titleOnly))
        skipped.isSkipped = true
        skipped.background = .gradient(GradientFill(kind: .radial, stops: [
            GradientStop(position: 0, color: ColorRef(theme: .light1)),
            GradientStop(position: 1, color: ColorRef(.theme(.accent3), tint: 0.4)),
        ]))
        skipped.elements[0].placement = Placement(frame: SlideRect(x: 36, y: 30, width: 648, height: 60.5))
        skipped.elements[0].shape?.text = TextBody("Backup slide")
        skipped.notes = TextBody(paragraphs: [
            TextParagraph("Only if there are questions."),
            TextParagraph(runs: [TextRun("Mention the "), TextRun("numbers", style: CharacterStyle(bold: true))], level: 1),
        ])
        skipped.transition = SlideTransition(kind: .slideFromLeft, duration: 0.75)

        // 2. Title and body: lists, numbering, links, line breaks, fields and every character property.
        var body = presentation.makeSlide(layoutID: layout(.titleAndBody))
        body.elements[0].shape?.text = TextBody("Highlights")
        var sub = TextParagraph("Sub point", level: 1)
        sub.style = ParagraphStyle(alignment: .justified, lineSpacing: 1.5, spaceBefore: 6, spaceAfter: 3, marginLeft: 54, indent: -18,
                                   bullet: .character("–"), bulletFont: "Arial", bulletColor: ColorRef(theme: .accent2), bulletSize: 0.8)
        var roman = TextParagraph("Roman three")
        roman.style.bullet = .number(.romanUcParenR, startAt: 3)
        var roman2 = TextParagraph("Roman four")
        roman2.style.bullet = .number(.romanUcParenR, startAt: 3)
        var letters = TextParagraph("Letter a", level: 2)
        letters.style.bullet = .number(.alphaLcPeriod, startAt: 1)
        var both = TextParagraph("Arabic (1)", level: 1)
        both.style.bullet = .number(.arabicParenBoth, startAt: 1)
        var plain = TextParagraph("No bullet here")
        plain.style.bullet = Bullet.none
        plain.style.alignment = .center
        let linked = TextParagraph(runs: [
            TextRun("Visit "),
            TextRun("our site", style: CharacterStyle(underline: true, link: .url("https://example.com/a?b=1&c=2"))),
            TextRun(" or jump to the "),
            TextRun("backup slide", style: CharacterStyle(link: .slide(skipped.id))),
        ])
        let styled = TextParagraph(runs: [
            TextRun("Line one\u{2028}Line two", style: CharacterStyle(fontFamily: "Georgia", fontSize: 20.5)),
            TextRun(" E=mc"),
            TextRun("2", style: CharacterStyle(baseline: .superscript)),
            TextRun(" H"),
            TextRun("2", style: CharacterStyle(baseline: .subscript)),
            TextRun("O ", style: CharacterStyle(baseline: .normal)),
            TextRun("struck", style: CharacterStyle(strikethrough: true)),
            TextRun(" marked", style: CharacterStyle(highlight: ColorRef(RGBColor(red: 255, green: 240, blue: 0)))),
            TextRun(" heading font", style: CharacterStyle(fontFamily: "+mj-lt", bold: false, italic: false, underline: false)),
        ])
        let spaced = TextParagraph(runs: [TextRun("  two  spaces\tand a tab  "), TextRun("é 漢字 🐶", style: CharacterStyle(fontSize: 30))])
        let fields = TextParagraph(runs: [TextRun("Slide "), TextRun("‹#›", field: .slideNumber), TextRun(" of the deck, "),
                                          TextRun("1/2/2026", field: .dateTime("datetime1")), TextRun(" "),
                                          TextRun("January 2, 2026", field: .dateTime("datetime4")), TextRun(" "),
                                          TextRun("9:41", field: .dateTime("datetime10"))])
        var empty = TextParagraph()
        empty.endStyle = CharacterStyle(fontSize: 12)
        var bodyText = TextBody(paragraphs: [TextParagraph("First point"), sub, roman, roman2, letters, both, plain, linked, styled, spaced,
                                             fields, empty],
                                properties: TextBodyProperties(anchor: .middle, insets: TextInsets(left: 10, top: 5, right: 10, bottom: 5),
                                                               autofit: .shrinkOnOverflow, wraps: true))
        bodyText.listStyle[0] = LevelStyle(character: CharacterStyle(color: ColorRef(.theme(.dark2), lumMod: 0.6, lumOff: 0.4)))
        body.elements[1].shape?.text = bodyText
        body.notes = TextBody("Speak slowly.")
        body.transition = SlideTransition(kind: .dissolve, duration: 1.2)
        body.animations = [
            SlideAnimation(elementID: body.elements[1].id, effect: .flyInFromLeft, start: .onClick, duration: 0.5, byParagraph: true),
            SlideAnimation(elementID: body.elements[0].id, effect: .zoomIn, start: .afterPrevious, duration: 0.75),
        ]

        // 3. Shapes, lines, pictures and groups on a blank slide.
        var shapes = presentation.makeSlide(layoutID: layout(.blank))
        let outlined = Outline(fill: .solid(ColorRef(theme: .accent1)), width: 2.25, dash: .dash, head: .fillArrow, tail: .strokeArrow)
        var rectangle = Shape(fill: .solid(ColorRef(RGBColor(red: 0xF2, green: 0x9D, blue: 0x38))), outline: outlined, text: TextBody("Shape text"))
        rectangle.text?.properties.anchor = .middle
        let custom = CustomGeometry(paths: [
            CustomPath(width: 100, height: 100, commands: [
                .move(SlidePoint(x: 0, y: 0)), .line(SlidePoint(x: 100, y: 0)),
                .quadratic(control: SlidePoint(x: 100, y: 50), end: SlidePoint(x: 50, y: 100)),
                .cubic(control1: SlidePoint(x: 25, y: 100), control2: SlidePoint(x: 0, y: 75), end: SlidePoint(x: 0, y: 50)),
                .arc(widthRadius: 25, heightRadius: 25, startAngle: 90, sweepAngle: 180), .close,
            ]),
            CustomPath(width: 0, height: 0, fill: .none, stroke: true, commands: [.move(SlidePoint(x: 10.5, y: 10)), .line(SlidePoint(x: 20, y: 30.5))]),
            CustomPath(width: 40, height: 40, fill: .darken, stroke: false, commands: [.move(SlidePoint(x: 0, y: 0)), .line(SlidePoint(x: 40, y: 40)), .close]),
        ], textRect: TextInsetFractions(left: 0.1, top: 0.2, right: 0.1, bottom: 0.2))
        let groupChildren = [
            shape("Grouped square", SlideRect(x: 500, y: 250, width: 40, height: 40), Shape(fill: .solid(ColorRef(theme: .accent4)))),
            group([
                shape("Inner circle", SlideRect(x: 560, y: 270, width: 30, height: 30), rotation: 45,
                      Shape(geometry: .preset("ellipse", adjustments: [:]), fill: .solid(ColorRef(theme: .accent5)))),
                SlideElement(name: "Inner picture", placement: Placement(frame: SlideRect(x: 600, y: 300, width: 50, height: 40)),
                             content: .picture(Picture(mediaID: photo))),
            ], name: "Inner group"),
        ]
        shapes.elements = [
            shape("Rotated rectangle", SlideRect(x: 40, y: 40, width: 120, height: 80), rotation: 30, rectangle,
                  title: "A rectangle", description: "An orange rectangle\nwith a blue border"),
            shape("Oval", SlideRect(x: 180, y: 40, width: 100, height: 60), flipH: true, Shape(geometry: .preset("ellipse", adjustments: [:]),
                  fill: .gradient(GradientFill(kind: .linear(angle: 90), stops: [
                      GradientStop(position: 0, color: ColorRef(.theme(.accent1), tint: 0.5)),
                      GradientStop(position: 0.5, color: ColorRef(theme: .accent2)),
                      GradientStop(position: 1, color: ColorRef(.theme(.accent1), tint: 0.5)),
                  ])))),
            shape("Rounded", SlideRect(x: 300, y: 40, width: 100, height: 60), flipV: true, Shape(geometry: .preset("roundRect", adjustments: ["adj": 30000]),
                  fill: .gradient(GradientFill(kind: .radial, stops: [GradientStop(position: 0, color: .white), GradientStop(position: 1, color: .black)])),
                  outline: Outline(fill: .solid(.black), width: 1, dash: .longDashDot))),
            shape("Arrow", SlideRect(x: 420, y: 40, width: 100, height: 50),
                  Shape(geometry: .preset("rightArrow", adjustments: ["adj1": 50000, "adj2": 50000]), fill: .solid(ColorRef(theme: .accent6)))),
            shape("Freeform", SlideRect(x: 540, y: 40, width: 120, height: 80),
                  Shape(geometry: .custom(custom), fill: .solid(ColorRef(theme: .accent2)), outline: .solid(ColorRef(theme: .dark1)), text: TextBody("Free"))),
            shape("Text box", SlideRect(x: 40, y: 150, width: 200, height: 40),
                  Shape(fill: Fill.none, text: TextBody("Resizes to fit", properties: TextBodyProperties(insets: .standard, autofit: .resizeShape, wraps: false)),
                        isTextBox: true)),
            shape("Connector", SlideRect(x: 260, y: 150, width: 120, height: 0),
                  Shape(geometry: .preset("straightConnector1", adjustments: [:]),
                        outline: Outline(fill: .solid(ColorRef(RGBColor(red: 0x33, green: 0x33, blue: 0x33))), width: 1.5, head: .fillCircle, tail: .fillArrow),
                        isConnector: true)),
            shape("Elbow", SlideRect(x: 400, y: 150, width: 80, height: 40),
                  Shape(geometry: .preset("bentConnector3", adjustments: [:]), outline: Outline(fill: .solid(.black), head: .fillDiamond, tail: .strokeCircle),
                        isConnector: true)),
            shape("Curve", SlideRect(x: 400, y: 200, width: 80, height: 40), flipV: true,
                  Shape(geometry: .preset("curvedConnector3", adjustments: [:]), outline: Outline(fill: .solid(.black), head: .fillSquare, tail: .strokeSquare),
                        isConnector: true)),
            shape("Dotted line", SlideRect(x: 500, y: 150, width: 100, height: 20),
                  Shape(geometry: .line, outline: Outline(fill: .solid(ColorRef(theme: .accent1)), width: 3, dash: .dot, tail: .strokeDiamond))),
            shape("Dash dot line", SlideRect(x: 500, y: 190, width: 100, height: 0),
                  Shape(geometry: .line, outline: Outline(fill: .solid(ColorRef(theme: .accent2)), width: 2, dash: .dashDot))),
            shape("Long dash line", SlideRect(x: 500, y: 200, width: 100, height: 0), flipH: true,
                  Shape(geometry: .line, outline: Outline(fill: .solid(ColorRef(theme: .accent2)), width: 2, dash: .longDash))),
            SlideElement(name: "Cropped photo", placement: Placement(frame: SlideRect(x: 40, y: 210, width: 120, height: 120)),
                         content: .picture(Picture(mediaID: photo, crop: ImageCrop(left: 0.1, top: 0.05, right: 0.2), outline: .solid(ColorRef(theme: .accent1), width: 3))),
                         altDescription: "A gradient photo"),
            SlideElement(name: "Masked photo", placement: Placement(frame: SlideRect(x: 40, y: 340, width: 60, height: 50)),
                         content: .picture(Picture(mediaID: photo, geometry: .preset("ellipse", adjustments: [:])))),
            SlideElement(name: "Mirrored photo", placement: Placement(frame: SlideRect(x: 110, y: 340, width: 60, height: 50), rotation: 10, flipHorizontal: true),
                         content: .picture(Picture(mediaID: photo))),
            shape("Photo fill", SlideRect(x: 180, y: 210, width: 120, height: 80), Shape(fill: .picture(PictureFill(mediaID: photo)))),
            shape("Tiled fill", SlideRect(x: 320, y: 210, width: 120, height: 80),
                  Shape(geometry: .preset("hexagon", adjustments: [:]), fill: .picture(PictureFill(mediaID: texture, stretches: false)))),
            group(groupChildren, name: "Outer group", title: "Group", description: "Shapes together"),
            shape("Star", SlideRect(x: 600, y: 330, width: 60, height: 60), rotation: 200,
                  Shape(geometry: .preset("star5", adjustments: [:]), fill: .solid(ColorRef(theme: .accent4).withAlpha(0.6)),
                        outline: Outline(fill: .solid(ColorRef(.theme(.dark1), alpha: 0.5)), width: 1))),
            shape("Cloud callout", SlideRect(x: 460, y: 330, width: 120, height: 60),
                  Shape(geometry: .preset("cloudCallout", adjustments: ["adj1": 30000, "adj2": -60000]), fill: .solid(ColorRef(theme: .light2)),
                        outline: .solid(ColorRef(theme: .dark2)), text: TextBody("Callout"))),
            shape("Invisible", SlideRect(x: 200, y: 350, width: 50, height: 20), Shape()),
            shape("Explicitly plain", SlideRect(x: 260, y: 350, width: 50, height: 20), Shape(fill: Fill.none, outline: Outline.none)),
        ]
        shapes.transition = SlideTransition(kind: .slideFromRight, duration: 0.4)
        let effects: [(Int, AnimationEffect, AnimationStart)] = [
            (0, .flyInFromRight, .onClick), (1, .flyInFromTop, .withPrevious), (2, .flyInFromBottom, .afterPrevious), (3, .spin, .onClick),
            (4, .disappear, .afterPrevious), (5, .fadeOut, .withPrevious), (9, .flyOutToLeft, .onClick), (12, .flyOutToRight, .afterPrevious),
            (15, .flyOutToTop, .withPrevious), (16, .flyOutToBottom, .onClick), (17, .zoomOut, .afterPrevious),
        ]
        shapes.animations = effects.map { index, effect, start in
            SlideAnimation(elementID: shapes.elements[index].id, effect: effect, start: start, duration: 0.6, delay: index % 2 == 0 ? 0 : 0.5)
        }
        shapes.notes = TextBody(paragraphs: [TextParagraph(runs: [TextRun("Bold notes", style: CharacterStyle(bold: true)), TextRun(" and plain")])])

        // 5. On the second theme, with a tiled picture background and a slide number.
        var harborSlide = presentation.makeSlide(layoutID: layout(.titleAndBody, in: harbor))
        harborSlide.background = .picture(PictureFill(mediaID: texture, stretches: false))
        harborSlide.elements[0].shape?.text = TextBody("Second theme")
        harborSlide.elements[1].shape?.text = TextBody("Body text\nSecond line")
        harborSlide.notes = TextBody("Remember the demo")
        harborSlide.transition = SlideTransition(kind: .flip, duration: 1)

        // 6. The custom layout: a filled and outlined placeholder, and a picture in the picture placeholder.
        var photoSlide = presentation.makeSlide(layoutID: photoLayout.id)
        photoSlide.elements[0].shape?.text = TextBody("Over the photo")
        photoSlide.elements[0].shape?.fill = .solid(ColorRef(RGBColor.white, alpha: 0.8))
        photoSlide.elements[0].shape?.outline = .solid(ColorRef(theme: .dark1), width: 1)
        photoSlide.elements[1] = SlideElement(name: "Picture 2", placement: nil, placeholder: PlaceholderRef(type: .picture, index: 1),
                                              content: .picture(Picture(mediaID: photo, crop: ImageCrop(top: 0.125, bottom: 0.125))))
        photoSlide.transition = SlideTransition(kind: .cube, duration: 2)

        // 7. Harbor's title slide, whose layout has a decoration of its own.
        var harborTitle = presentation.makeSlide(layoutID: layout(.title, in: harbor))
        harborTitle.elements[0].shape?.text = TextBody("Harbor title")
        harborTitle.transition = SlideTransition(kind: .gallery, duration: 0.5)

        PPTXSamples.addComments(title: &title, shapes: &shapes, photo: &photoSlide)
        presentation.slides = [title, body, shapes, skipped, harborSlide, photoSlide, harborTitle]
        presentation.setSlideNumbers(true, slideIDs: [harborSlide.id])
        return presentation
    }

    /// A table with merged cells, every border dash, missing borders, colored and picture cells, padding, alignment and
    /// rich text, in sizes a file keeps exactly.
    static func designedTable(texture: MediaID) -> Table {
        var table = Table.make(rows: 5, columns: 4, width: 400)
        table.columnWidths = [120.5, 80, 100, 99.5]
        table.rowHeights = [30, 24.25, 40, 40, 20]
        for row in 0..<5 {
            for column in 0..<4 { table.cells[row][column].text = TextBody("R\(row + 1)C\(column + 1)", style: CharacterStyle(fontSize: 12)) }
        }
        table.cells[0][0].text = TextBody(paragraphs: [TextParagraph(runs: [
            TextRun("Quarter ", style: CharacterStyle(bold: true, color: .white)),
            TextRun("results", style: CharacterStyle(italic: true, color: ColorRef(RGBColor(red: 0xFF, green: 0xEE, blue: 0x99)))),
        ])])
        table.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: 1))
        table.merge(TableCellRange(firstRow: 2, firstColumn: 2, lastRow: 3, lastColumn: 3))
        var list = TextParagraph("A bullet", level: 0)
        list.style.bullet = .character("•")
        var numbered = TextParagraph("Numbered", level: 1)
        numbered.style.bullet = .number(.arabicPeriod, startAt: 1)
        table.cells[2][2].text = TextBody(paragraphs: [TextParagraph("Merged area"), list, numbered,
                                                       TextParagraph(runs: [TextRun("Link", style: CharacterStyle(link: .url("https://example.com/table")))])])
        table.cells[2][2].anchor = .middle
        table.cells[1][0].text = TextBody(paragraphs: [TextParagraph(runs: [TextRun("Two\u{2028}lines  spaced")], style: ParagraphStyle(alignment: .center))])
        table.cells[1][0].anchor = .bottom
        table.cells[1][0].insets = TextInsets(left: 2, top: 1.5, right: 10, bottom: 0)
        for column in 0..<4 { table.cells[0][column].fill = .solid(ColorRef(theme: .accent1)) }
        table.cells[1][1].fill = .solid(ColorRef(RGBColor(red: 0xF4, green: 0xCC, blue: 0xCC)))
        table.cells[1][2].fill = .picture(PictureFill(mediaID: texture, stretches: false))
        table.cells[4][3].fill = .solid(ColorRef(.theme(.accent2), lumMod: 0.5))
        // A thick red rule under the header, every dash on the second row, and no inner lines in the last row.
        for column in 0..<4 { table.horizontalBorders[1][column] = Outline(fill: .solid(ColorRef(RGBColor(red: 0xCC, green: 0, blue: 0))), width: 2.25) }
        let dashes: [DashStyle] = [.dot, .dash, .longDash, .dashDot, .longDashDot]
        for (column, dash) in dashes.enumerated() {
            table.verticalBorders[1][column] = Outline(fill: .solid(ColorRef(theme: .dark2)), width: 1.5, dash: dash)
        }
        for column in 1..<4 { table.verticalBorders[4][column] = nil }
        table.horizontalBorders[5][3] = nil
        return table
    }

    /// One chart of each kind, with gaps in the numbers, colors of their own, titles, every legend position and the
    /// look options charts keep.
    static func chart(_ kind: ChartKind, index: Int) -> Chart {
        var chart = Chart.sample(kind)
        chart.data.labelHeading = index % 2 == 0 ? "Month" : ""
        chart.data.labels = kind == .scatter ? ["1", "2.5", "4", "7.25"] : ["Jan", "Feb", "Mar & <Apr>", "May"]
        if !kind.isPie {
            chart.data.series.append(ChartSeries(name: "Third  series", values: [5, nil, -3.5, 1e-3]))
            chart.data.series[1].color = RGBColor(red: 0x12, green: 0x34, blue: 0x56)
        }
        chart.title = index % 3 == 0 ? "" : "\(kind.title)\nSecond line"
        chart.horizontalAxisTitle = kind.isPie ? "" : "Across"
        chart.verticalAxisTitle = kind.isPie || index % 2 == 1 ? "" : "Up"
        chart.legend = ChartLegendPosition.allCases[index % ChartLegendPosition.allCases.count]
        chart.showsGridlines = index % 4 != 1
        chart.showsDataLabels = index % 3 == 1
        chart.pieHole = kind == .donut ? 0.6 : 0.5
        chart.fontFamily = index % 2 == 0 ? "Georgia" : nil
        chart.backgroundColor = index % 5 == 2 ? RGBColor(red: 0xFA, green: 0xFA, blue: 0xF0) : nil
        if !kind.isPie, index % 3 == 2 {
            chart.verticalMinimum = -10
            chart.verticalMaximum = 40.5
        }
        return chart
    }

    /// Tables, charts, word art and pictures with adjustments, with guides and animations of tables and charts: what the
    /// newer parts of the model hold, all of it kept exactly by a file.
    static func objects() -> Presentation {
        let light = BuiltInThemes.simpleLight()
        var presentation = Presentation(themes: [light], defaultTextStyle: BuiltInThemes.defaultTextStyle, title: "Objects")
        let photo = presentation.addMedia(Self.photo, contentType: "image/png")
        let texture = presentation.addMedia(Self.texture, contentType: "image/png")
        // A layout whose own look includes a small table and chart, so they're written on a master page.
        var report = Layout(name: "Report", kind: .custom, elements: [
            BuiltInThemes.placeholder(.title, name: "Title", frame: SlideRect(x: 36, y: 20, width: 500, height: 50), anchor: .middle),
        ])
        var corner = Table.make(rows: 1, columns: 2, width: 120)
        corner.cells[0][0].text = TextBody("Draft")
        corner.cells[0][1].fill = .solid(ColorRef(theme: .accent3))
        report.elements.append(SlideElement(name: "Corner table", placement: Placement(frame: SlideRect(x: 580, y: 20, width: 120, height: 25)),
                                            content: .table(corner)))
        report.elements.append(SlideElement(name: "Corner chart", placement: Placement(frame: SlideRect(x: 580, y: 300, width: 120, height: 90)),
                                            content: .chart(Chart.sample(.pie))))
        presentation.themes[0].layouts.append(report)
        let blank = light.layout(kind: .blank)!.id

        // 1. Tables: a new table, and a designed one, rotated a little.
        var tables = presentation.makeSlide(layoutID: blank)
        var plain = presentation.makeTableElement(rows: 3, columns: 4)
        plain.name = "Plain table"
        plain.table?.cells[1][2].text = TextBody("Typed")
        plain.altTitle = "Plain"
        plain.altDescription = "A new table"
        let designed = SlideElement(name: "Designed table", placement: Placement(frame: SlideRect(x: 40, y: 200, width: 400, height: 154.25), rotation: 5),
                                    content: .table(designedTable(texture: texture)))
        tables.elements = [plain, designed]
        tables.animations = [SlideAnimation(elementID: plain.id, effect: .fadeIn), SlideAnimation(elementID: designed.id, effect: .flyInFromLeft, start: .afterPrevious)]

        // 2 and 3. Charts of every kind.
        var charts: [Slide] = []
        for (page, kinds) in [Array(ChartKind.allCases.prefix(7)), Array(ChartKind.allCases.dropFirst(7))].enumerated() {
            var slide = presentation.makeSlide(layoutID: blank)
            for (number, kind) in kinds.enumerated() {
                let index = page * 7 + number
                let frame = SlideRect(x: 20 + Double(number % 4) * 175, y: 20 + Double(number / 4) * 190, width: 165, height: 170)
                slide.elements.append(SlideElement(name: kind.title, placement: Placement(frame: frame), content: .chart(chart(kind, index: index)),
                                                   altDescription: index == 0 ? "Sales by month" : nil))
            }
            charts.append(slide)
        }
        charts[0].animations = [SlideAnimation(elementID: charts[0].elements[0].id, effect: .zoomIn),
                                SlideAnimation(elementID: charts[0].elements[3].id, effect: .spin, start: .withPrevious)]

        // 4. Word art and pictures with adjustments.
        var art = presentation.makeSlide(layoutID: blank)
        var hello = SlideElement(name: "Word art", placement: Placement(frame: SlideRect(x: 40, y: 40, width: 300, height: 100)),
                                 content: .shape(Shape.wordArt("Hello\nWorld")))
        hello.shape?.text?.paragraphs[0].runs[0].style.bold = true
        var styled = Shape.wordArt("Styled", fontFamily: "Georgia")
        styled.fill = .gradient(GradientFill(kind: .linear(angle: 0), stops: [GradientStop(position: 0, color: ColorRef(theme: .accent1)),
                                                                              GradientStop(position: 1, color: ColorRef(theme: .accent2))]))
        styled.outline = Outline(fill: .solid(ColorRef(theme: .accent6)), width: 2)
        let styledArt = SlideElement(name: "Styled word art", placement: Placement(frame: SlideRect(x: 380, y: 40, width: 280, height: 80), rotation: 350,
                                                                                    flipHorizontal: true), content: .shape(styled))
        func picture(_ name: String, x: Double, _ adjustments: ImageAdjustments) -> SlideElement {
            SlideElement(name: name, placement: Placement(frame: SlideRect(x: x, y: 200, width: 100, height: 100)),
                         content: .picture(Picture(mediaID: photo, adjustments: adjustments)))
        }
        art.elements = [
            hello, styledArt,
            picture("Faded", x: 20, ImageAdjustments(transparency: 0.25)),
            picture("Brighter", x: 140, ImageAdjustments(brightness: 0.3, contrast: -0.2)),
            picture("Gray", x: 260, ImageAdjustments(recolor: .grayscale)),
            picture("Negative", x: 380, ImageAdjustments(transparency: 0.5, contrast: 0.45, recolor: .negative)),
            picture("Untouched", x: 500, .none),
        ]
        art.animations = [SlideAnimation(elementID: hello.id, effect: .appear)]

        var reported = presentation.makeSlide(layoutID: report.id)
        reported.elements[0].shape?.text = TextBody("On the report layout")

        let media = PPTXSamples.mediaSlide(&presentation, layoutID: presentation.themes[0].layout(kind: .blank)?.id ?? report.id)
        presentation.slides = [tables] + charts + [art, reported, media]
        presentation.guides = [Guide(orientation: .vertical, position: 360), Guide(orientation: .horizontal, position: 180),
                               Guide(orientation: .vertical, position: 36)]
        PPTXSamples.addObjectComments(&presentation)
        return presentation
    }

    /// One slide per layout of a theme, with text in every placeholder.
    static func themeShowcase(_ design: BuiltInThemes.Design) -> Presentation {
        let theme = BuiltInThemes.make(design)
        var presentation = Presentation(themes: [theme], defaultTextStyle: BuiltInThemes.defaultTextStyle, title: design.name)
        for layout in theme.layouts {
            var slide = presentation.makeSlide(layoutID: layout.id)
            for index in slide.elements.indices {
                let type = slide.elements[index].placeholder?.type
                let text = type?.isTitle == true ? "\(design.name): \(layout.name)" : "First point\nSecond point"
                slide.elements[index].shape?.text = TextBody(text)
            }
            presentation.slides.append(slide)
        }
        return presentation
    }

    /// Every built-in theme in one deck: a title slide and a body slide on each.
    static func allThemes() -> Presentation {
        var presentation = Presentation(themes: BuiltInThemes.designs.map { BuiltInThemes.make($0) }, defaultTextStyle: BuiltInThemes.defaultTextStyle,
                                        title: "All themes")
        for theme in presentation.themes {
            for kind in [LayoutKind.title, .titleAndBody] {
                guard let layout = theme.layout(kind: kind) else { continue }
                var slide = presentation.makeSlide(layoutID: layout.id)
                slide.elements[0].shape?.text = TextBody(kind == .title ? theme.name : "\(theme.name) body")
                if slide.elements.count > 1 { slide.elements[1].shape?.text = TextBody("Fonts \(theme.fonts.major) and \(theme.fonts.minor)\nSecond line") }
                presentation.slides.append(slide)
            }
        }
        return presentation
    }

    /// `count` slides of text and shapes, for timing.
    static func large(slides count: Int) -> Presentation {
        var presentation = Presentation.makeDefault()
        let theme = presentation.themes[0]
        let layout = theme.layout(kind: .titleAndBody)!
        var slides: [Slide] = []
        for number in 0..<count {
            var slide = presentation.makeSlide(layoutID: layout.id)
            slide.elements[0].shape?.text = TextBody("Slide \(number + 1)")
            slide.elements[1].shape?.text = TextBody(paragraphs: (0..<6).map { TextParagraph("Point \($0 + 1) on slide \(number + 1)", level: $0 % 2) })
            for shapeNumber in 0..<8 {
                let frame = SlideRect(x: 40 + Double(shapeNumber) * 80, y: 300, width: 60, height: 40)
                slide.elements.append(shape("Shape \(shapeNumber)", frame, rotation: Double(shapeNumber * 10),
                                            Shape(geometry: .preset(shapeNumber % 2 == 0 ? "rect" : "ellipse", adjustments: [:]),
                                                  fill: .solid(ColorRef(theme: .accent1)), outline: .solid(.black), text: TextBody("\(shapeNumber)"))))
            }
            // A table on every slide, and a chart on every tenth.
            var table = presentation.makeTableElement(rows: 4, columns: 3)
            for row in 0..<4 {
                for column in 0..<3 { table.table?.cells[row][column].text = TextBody("\(row * 3 + column + number)") }
            }
            slide.elements.append(table)
            if number % 10 == 9 { slide.elements.append(presentation.makeChartElement(ChartKind.allCases[number / 10 % ChartKind.allCases.count])) }
            slide.notes = TextBody("Notes for slide \(number + 1)")
            slide.transition = SlideTransition(kind: .fade)
            slide.animations = [SlideAnimation(elementID: slide.elements[1].id, effect: .fadeIn, byParagraph: true)]
            slides.append(slide)
        }
        presentation.slides = slides
        return presentation
    }
}
