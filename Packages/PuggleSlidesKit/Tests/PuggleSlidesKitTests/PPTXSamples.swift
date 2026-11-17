import Foundation
@testable import PuggleSlidesKit

/// Presentations that use everything the model can hold, for round trips and for checking files in other apps.
enum PPTXSamples {
    static let photo = PPTXTestImage.gradient(48, from: (0.95, 0.62, 0.22), to: (0.12, 0.35, 0.65))
    static let texture = PPTXTestImage.png(width: 8, height: 8) { x, y in (x + y) % 2 == 0 ? (240, 240, 230) : (200, 190, 170) }

    static func shape(_ name: String, _ frame: SlideRect, rotation: Double = 0, flipH: Bool = false, flipV: Bool = false,
                      _ shape: Shape, title: String? = nil, description: String? = nil) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: frame, rotation: rotation, flipHorizontal: flipH, flipVertical: flipV),
                     content: .shape(shape), altTitle: title, altDescription: description)
    }

    /// Two themes, a custom layout, every kind of element, rich text, links, notes and skipped slides.
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
                         placeholder: PlaceholderRef(type: .picture, index: 13), content: .shape(Shape(text: TextBody()))),
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
            TextRun("whole team", style: CharacterStyle(italic: true, underline: true, color: ColorRef(RGBColor(red: 0x12, green: 0x34, blue: 0x56), alpha: 0.5))),
        ])])

        // 4 is linked from 2, so its id is needed first.
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

        // 2. Title and body: lists, numbering, links, line breaks and every character property.
        var body = presentation.makeSlide(layoutID: layout(.titleAndBody))
        body.elements[0].shape?.text = TextBody("Highlights")
        var sub = TextParagraph("Sub point", level: 1)
        sub.style = ParagraphStyle(alignment: .justified, lineSpacing: 1.5, spaceBefore: 6, spaceAfter: 3, marginLeft: 54, indent: -18,
                                   bullet: .character("–"), bulletFont: "Arial", bulletColor: ColorRef(theme: .accent2), bulletSize: 0.8)
        var roman = TextParagraph("Roman three")
        roman.style.bullet = .number(.romanUcParenR, startAt: 3)
        var letters = TextParagraph("Letter a", level: 2)
        letters.style.bullet = .number(.alphaLcPeriod, startAt: 1)
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
        var empty = TextParagraph()
        empty.endStyle = CharacterStyle(fontSize: 12)
        var bodyText = TextBody(paragraphs: [TextParagraph("First point"), sub, roman, letters, plain, linked, styled, empty],
                                properties: TextBodyProperties(anchor: .middle, insets: TextInsets(left: 10, top: 5, right: 10, bottom: 5),
                                                               autofit: .shrinkOnOverflow, fontScale: 0.625, lineSpacingReduction: 0.2, wraps: true))
        bodyText.listStyle[0] = LevelStyle(character: CharacterStyle(color: ColorRef(.theme(.dark2), lumMod: 0.6, lumOff: 0.4)))
        body.elements[1].shape?.text = bodyText
        body.notes = TextBody("Speak slowly.")

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
            PPTXGroupTransform.group([
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
                      GradientStop(position: 1, color: ColorRef(.theme(.accent3), shade: 0.75)),
                  ])))),
            shape("Rounded", SlideRect(x: 300, y: 40, width: 100, height: 60), flipV: true, Shape(geometry: .preset("roundRect", adjustments: ["adj": 16667]),
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
                  Shape(geometry: .preset("bentConnector3", adjustments: [:]), outline: Outline(fill: .solid(.black), head: .fillDiamond), isConnector: true)),
            shape("Dotted line", SlideRect(x: 500, y: 150, width: 100, height: 20),
                  Shape(geometry: .line, outline: Outline(fill: .solid(ColorRef(theme: .accent1)), width: 3, dash: .dot))),
            SlideElement(name: "Masked photo", placement: Placement(frame: SlideRect(x: 40, y: 210, width: 120, height: 120)),
                         content: .picture(Picture(mediaID: photo, crop: ImageCrop(left: 0.1, top: 0.05, right: 0.2), geometry: .preset("ellipse", adjustments: [:]),
                                                   outline: .solid(ColorRef(theme: .accent1), width: 3))),
                         altDescription: "A gradient photo"),
            shape("Photo fill", SlideRect(x: 180, y: 210, width: 120, height: 80), Shape(fill: .picture(PictureFill(mediaID: photo)))),
            shape("Tiled fill", SlideRect(x: 320, y: 210, width: 120, height: 80),
                  Shape(geometry: .preset("hexagon", adjustments: [:]), fill: .picture(PictureFill(mediaID: texture, stretches: false)))),
            PPTXGroupTransform.group(groupChildren, name: "Outer group", altTitle: "Group", altDescription: "Shapes together"),
            shape("Invisible", SlideRect(x: 40, y: 350, width: 50, height: 20), Shape()),
            shape("Explicitly plain", SlideRect(x: 100, y: 350, width: 50, height: 20), Shape(fill: Fill.none, outline: Outline.none)),
            // Tables, charts, word art and an adjusted picture, alone and grouped.
            Self.table("Sales table", at: SlidePoint(x: 460, y: 210), Self.salesTable(texture: texture), title: "Sales", description: "Sales by region"),
            Self.chart("Sales chart", SlideRect(x: 160, y: 300, width: 240, height: 100), Self.salesChart(.column), description: "Sales by quarter"),
            shape("Word art", SlideRect(x: 420, y: 330, width: 140, height: 50), Shape.wordArt("Puggle\nArt", fontFamily: "Georgia")),
            SlideElement(name: "Adjusted photo", placement: Placement(frame: SlideRect(x: 580, y: 330, width: 60, height: 60)),
                         content: .picture(Picture(mediaID: photo, adjustments: ImageAdjustments(transparency: 0.25, brightness: 0.2, contrast: -0.1,
                                                                                                 recolor: .light(.accent1))))),
            PPTXGroupTransform.group([
                Self.table("Grouped table", at: SlidePoint(x: 600, y: 120), Self.smallTable()),
                Self.chart("Grouped chart", SlideRect(x: 600, y: 180, width: 100, height: 60), Self.salesChart(.donut)),
            ], name: "Data group"),
        ]

        // 5. On the second theme, with a tiled picture background and a slide number.
        var harborSlide = presentation.makeSlide(layoutID: layout(.titleAndBody, in: harbor))
        harborSlide.background = .picture(PictureFill(mediaID: texture, stretches: false))
        harborSlide.elements[0].shape?.text = TextBody("Second theme")
        harborSlide.elements[1].shape?.text = TextBody("Body text\nSecond line")
        harborSlide.notes = TextBody("Remember the demo")

        // 6. The custom layout: a filled and outlined placeholder, and a picture in the picture placeholder.
        var photoSlide = presentation.makeSlide(layoutID: photoLayout.id)
        photoSlide.elements[0].shape?.text = TextBody("Over the photo")
        photoSlide.elements[0].shape?.fill = .solid(ColorRef(RGBColor.white, alpha: 0.8))
        photoSlide.elements[0].shape?.outline = .solid(ColorRef(theme: .dark1), width: 1)
        photoSlide.elements[1] = SlideElement(name: "Picture 2", placement: nil, placeholder: PlaceholderRef(type: .picture, index: 13),
                                              content: .picture(Picture(mediaID: photo, crop: ImageCrop(top: 0.125, bottom: 0.125))))

        // Motion: a transition of each kind somewhere, and animations of every sort of element.
        title.transition = SlideTransition(kind: .fade, duration: 0.7)
        title.animations = [
            SlideAnimation(elementID: title.elements[0].id, effect: .fadeIn),
            SlideAnimation(elementID: title.elements[1].id, effect: .flyInFromBottom, start: .afterPrevious, duration: 0.75, delay: 0.25, byParagraph: true),
        ]
        body.transition = SlideTransition(kind: .slideFromRight)
        body.animations = [SlideAnimation(elementID: body.elements[1].id, effect: .fadeIn, byParagraph: true)]
        shapes.transition = SlideTransition(kind: .cube, duration: 1)
        shapes.animations = [
            SlideAnimation(elementID: shapes.elements[0].id, effect: .spin, duration: 2),
            SlideAnimation(elementID: shapes.elements[1].id, effect: .zoomIn, start: .withPrevious),
            SlideAnimation(elementID: shapes.elements[9].id, effect: .flyInFromLeft, start: .afterPrevious, duration: 1),
            SlideAnimation(elementID: shapes.elements[12].id, effect: .fadeOut, start: .onClick, delay: 0.5),
            SlideAnimation(elementID: shapes.elements[6].id, effect: .disappear, start: .withPrevious),
            // The table, the chart and the word art.
            SlideAnimation(elementID: shapes.elements[15].id, effect: .fadeIn, start: .onClick),
            SlideAnimation(elementID: shapes.elements[16].id, effect: .zoomIn, start: .afterPrevious, duration: 0.75),
            SlideAnimation(elementID: shapes.elements[17].id, effect: .flyInFromTop, start: .withPrevious),
        ]
        skipped.transition = SlideTransition(kind: .dissolve, duration: 0.5)
        harborSlide.transition = SlideTransition(kind: .gallery, duration: 1.5)
        photoSlide.transition = SlideTransition(kind: .flip, duration: 0.8)
        photoSlide.animations = [SlideAnimation(elementID: photoSlide.elements[1].id, effect: .appear),
                                 SlideAnimation(elementID: photoSlide.elements[0].id, effect: .zoomOut, start: .afterPrevious, duration: 0.6)]

        addComments(title: &title, shapes: &shapes, photo: &photoSlide)
        presentation.slides = [title, body, shapes, skipped, harborSlide, photoSlide]
        presentation.setSlideNumbers(true, slideIDs: [harborSlide.id])
        presentation.guides = [Guide(orientation: .vertical, position: 360), Guide(orientation: .horizontal, position: 202.5),
                               Guide(orientation: .vertical, position: 36.125, color: RGBColor(red: 0xFF, green: 0x00, blue: 0x66))]
        return presentation
    }

    // MARK: Tables and charts

    static func table(_ name: String, at origin: SlidePoint, _ table: Table, title: String? = nil, description: String? = nil) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: SlideRect(x: origin.x, y: origin.y, width: table.width, height: table.rowHeights.reduce(0, +))),
                     content: .table(table), altTitle: title, altDescription: description)
    }

    static func chart(_ name: String, _ frame: SlideRect, _ chart: Chart, description: String? = nil) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: frame), content: .chart(chart), altDescription: description)
    }

    /// A header row in the accent color, a merged block, a picture and a gradient fill, padding and anchors of their
    /// own, and borders of every sort: thick outer ones, dashed inner ones and some taken away.
    static func salesTable(texture: MediaID) -> Table {
        var table = Table.make(rows: 4, columns: 3, width: 240)
        let text = [["Region", "Q1", "Q2"], ["North", "12", "19.5"], ["South", "Merged", ""], ["Pictured", "", ""]]
        for row in 0..<4 {
            for column in 0..<3 where !text[row][column].isEmpty {
                let style = row == 0 ? CharacterStyle(bold: true, color: ColorRef(theme: .light1)) : CharacterStyle()
                table.cells[row][column].text.paragraphs = [TextParagraph(text[row][column], style: style)]
            }
        }
        table.cells[1][2].text.paragraphs = [TextParagraph(runs: [TextRun("19"), TextRun(".5", style: CharacterStyle(italic: true))]),
                                             TextParagraph("second line", level: 1)]
        table.setFill(.solid(ColorRef(theme: .accent1)), in: TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: 2))
        table.merge(TableCellRange(firstRow: 2, firstColumn: 1, lastRow: 3, lastColumn: 2))
        table.cells[2][1].anchor = .middle
        table.cells[2][1].fill = .gradient(GradientFill(kind: .linear(angle: 90), stops: [
            GradientStop(position: 0, color: ColorRef(theme: .light2)), GradientStop(position: 1, color: ColorRef(.theme(.accent2), tint: 0.5)),
        ]))
        table.cells[3][0].fill = .picture(PictureFill(mediaID: texture, stretches: false))
        table.cells[3][0].anchor = .bottom
        table.cells[1][0].insets = TextInsets(left: 12, top: 2, right: 4, bottom: 6)
        table.columnWidths = [100, 70, 70]
        // Tall enough for each row's text, so the rows are written at these heights.
        table.rowHeights = [24, 84, 24, 28]
        let all = TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 3, lastColumn: 2)
        table.updateBorders(.outer, in: all) { $0 = Outline(fill: .solid(ColorRef(theme: .dark2)), width: 2) }
        table.updateBorders(.inner, in: all) { $0 = Outline(fill: .solid(ColorRef(RGBColor(red: 0x99, green: 0x99, blue: 0x99))), width: 0.5, dash: .dash) }
        table.updateBorders(.vertical, in: TableCellRange(firstRow: 1, firstColumn: 0, lastRow: 1, lastColumn: 2)) { $0 = nil }
        table.horizontalBorders[4][0] = Outline(fill: .solid(ColorRef(theme: .accent3)), width: 3, dash: .dot)
        return table
    }

    /// A new table, with text.
    static func smallTable() -> Table {
        var table = Table.make(rows: 2, columns: 2, width: 100)
        for row in 0..<2 {
            for column in 0..<2 { table.cells[row][column].text.paragraphs = [TextParagraph("\(row + 1)·\(column + 1)")] }
        }
        return table
    }

    /// Two series over four quarters, with a gap, a color of its own on the second series, and every option set.
    static func salesChart(_ kind: ChartKind) -> Chart {
        let data = ChartData(labelHeading: "Quarter", labels: kind == .scatter ? ["1", "2.5", "4", "-3"] : ["Q1", "Q2", "Q3", "Q4 & <more>"], series: [
            ChartSeries(name: "North", values: [12, 19.5, nil, 30]),
            ChartSeries(name: "South", values: [8, 11, 14.25, 9], color: RGBColor(red: 0x88, green: 0x44, blue: 0xAA)),
        ])
        return Chart(kind: kind, data: data, title: "Sales\nby quarter", horizontalAxisTitle: "Quarter", verticalAxisTitle: "Units", legend: .bottom,
                     showsGridlines: kind != .line, showsDataLabels: kind == .column || kind == .pie, pieHole: 0.35, fontFamily: kind == .bar ? "Georgia" : nil,
                     backgroundColor: kind == .area ? RGBColor(red: 0xFA, green: 0xFA, blue: 0xF0) : nil, verticalMinimum: kind.isPie ? nil : 0,
                     verticalMaximum: kind == .column ? 40 : nil)
    }

    /// One slide per chart kind, a slide of tables, one of word art and one of every recolor, with guides.
    static func objects() -> Presentation {
        var presentation = Presentation.makeDefault()
        let blank = presentation.themes[0].layout(kind: .blank)!.id
        let photo = presentation.addMedia(Self.photo, contentType: "image/png")
        let texture = presentation.addMedia(Self.texture, contentType: "image/png")
        var slides: [Slide] = []
        let legends = ChartLegendPosition.allCases
        for (index, kind) in ChartKind.allCases.enumerated() {
            var slide = presentation.makeSlide(layoutID: blank)
            var chart = Self.salesChart(kind)
            chart.legend = legends[index % legends.count]
            chart.title = index % 3 == 0 ? "" : kind.title
            if index % 4 == 1 { chart.data.series.append(ChartSeries(name: "", values: [1, 2, 3])) }
            slide.elements = [Self.chart(kind.title, SlideRect(x: 60, y: 40, width: 600, height: 320), chart)]
            slides.append(slide)
        }
        var tables = presentation.makeSlide(layoutID: blank)
        var wide = Table.make(rows: 3, columns: 5, width: 500)
        wide.merge(TableCellRange(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: 4))
        wide.merge(TableCellRange(firstRow: 1, firstColumn: 1, lastRow: 2, lastColumn: 1))
        wide.cells[0][0].text.paragraphs = [TextParagraph("A heading across the table")]
        wide.updateBorders(.all, in: TableCellRange(firstRow: 1, firstColumn: 2, lastRow: 2, lastColumn: 4)) { $0 = nil }
        tables.elements = [Self.table("Sales", at: SlidePoint(x: 40, y: 40), Self.salesTable(texture: texture)),
                           Self.table("Wide", at: SlidePoint(x: 40, y: 200), wide),
                           Self.table("Small", at: SlidePoint(x: 400, y: 40), Self.smallTable())]
        slides.append(tables)
        var art = presentation.makeSlide(layoutID: blank)
        var gradient = Shape.wordArt("Gradient", fontFamily: "Arial")
        gradient.fill = .gradient(GradientFill(kind: .linear(angle: 0), stops: [GradientStop(position: 0, color: ColorRef(theme: .accent1)),
                                                                                GradientStop(position: 1, color: ColorRef(theme: .accent2))]))
        gradient.outline = nil
        var plain = Shape.wordArt("No outline")
        plain.outline = Outline.none
        plain.fill = .solid(ColorRef(.theme(.accent4), lumMod: 0.75))
        art.elements = [shape("Default", SlideRect(x: 40, y: 40, width: 300, height: 100), Shape.wordArt("Word art")),
                        shape("Gradient", SlideRect(x: 380, y: 40, width: 300, height: 100), gradient),
                        shape("Plain", SlideRect(x: 40, y: 200, width: 300, height: 100), plain)]
        slides.append(art)
        var recolors = presentation.makeSlide(layoutID: blank)
        let presets = ImageRecolor.presets + [.duotone(ColorRef(theme: .accent5), ColorRef(RGBColor(red: 0xFF, green: 0xEE, blue: 0xCC))), nil]
        recolors.elements = presets.enumerated().map { index, recolor in
            let adjustments = ImageAdjustments(transparency: Double(index % 4) * 0.2, brightness: Double(index % 5) * 0.25 - 0.5,
                                               contrast: Double(index % 3) * 0.333 - 0.333, recolor: recolor)
            return SlideElement(name: "Photo \(index + 1)", placement: Placement(frame: SlideRect(x: 20 + Double(index % 7) * 98, y: 20 + Double(index / 7) * 98,
                                                                                                 width: 90, height: 90)),
                                content: .picture(Picture(mediaID: photo, adjustments: adjustments)))
        }
        slides.append(recolors)
        slides.append(mediaSlide(&presentation, layoutID: blank))
        presentation.slides = slides
        presentation.guides = [Guide(orientation: .horizontal, position: 100), Guide(orientation: .vertical, position: -10.5, color: .black)]
        addObjectComments(&presentation)
        return presentation
    }

    // MARK: Comments

    /// When the sample comments start, with a fraction of a second files don't keep.
    static let commentDate = Date(timeIntervalSince1970: 1_763_370_000.25)

    static func comment(_ author: String, minutes: Double, _ text: String) -> Comment {
        Comment(author: author, date: commentDate.addingTimeInterval(minutes * 60), text: text)
    }

    /// Threads as people leave them: about a placeholder, a picture and a shape in a group, and about the slide; with
    /// replies, resolved, in several scripts and on several lines.
    static func addComments(title: inout Slide, shapes: inout Slide, photo: inout Slide) {
        let heading = title.elements[0]
        title.comments = [
            CommentThread(comments: [comment("Zoë Ångström", minutes: 0, "Ça va ? Le titre est très bien.\nSecond line — ✓"),
                                     comment("田中 太郎", minutes: 5, "同意します 👍")],
                          elementID: heading.id, position: SlidePoint(x: 640.5, y: 40.25)),
            CommentThread(comments: [comment("Ada Lovelace", minutes: 9, "Whole slide: <check> & \"quotes\"")], position: SlidePoint(x: 12, y: 18)),
        ]
        if let group = shapes.elements.first(where: { $0.name == "Outer group" }), let child = group.children?.first {
            let frame = child.placement?.frame ?? .zero
            shapes.comments = [
                CommentThread(comments: [comment("Ada Lovelace", minutes: 20, "Is this square the right size?"),
                                         comment("Zoë Ångström", minutes: 21, "  Indented reply,\n\nwith a blank line  "),
                                         comment("Ada Lovelace", minutes: 30, "Fixed.")],
                              isResolved: true, elementID: child.id, position: SlidePoint(x: frame.maxX, y: frame.minY)),
                CommentThread(comments: [comment("", minutes: 31, "No author")], position: SlidePoint(x: 700, y: 380.75)),
            ]
        }
        if let picture = photo.elements.first(where: { $0.picture != nil }) {
            photo.comments = [CommentThread(comments: [comment("Ada Lovelace", minutes: 40, "Crop tighter?")], elementID: picture.id,
                                            position: SlidePoint(x: 300.5, y: 100))]
        }
    }

    /// A thread about a chart and a resolved one about a table: graphic frames.
    /// Videos and sounds with each kind of playback, posters and none, trims, and animations around them. The media are
    /// tiny generated files: only their headers are real.
    static func mediaSlide(_ presentation: inout Presentation, layoutID: UUID) -> Slide {
        let movie = presentation.addMedia(MediaTestFiles.movie(seconds: 8), contentType: "video/mp4")
        let sound = presentation.addMedia(MediaTestFiles.mp3(seconds: 2), contentType: "audio/mpeg")
        let wave = presentation.addMedia(MediaTestFiles.wave(seconds: 1), contentType: "audio/wav")
        let poster = presentation.addMedia(Self.photo, contentType: "image/png")
        var slide = presentation.makeSlide(layoutID: layoutID)
        func clip(_ name: String, _ frame: SlideRect, _ clip: MediaClip) -> SlideElement {
            SlideElement(name: name, placement: Placement(frame: frame), content: .media(clip), altDescription: "A \(clip.kind.rawValue) clip")
        }
        let caption = shape("Caption", SlideRect(x: 40, y: 330, width: 300, height: 40), Shape(text: TextBody("Press play"), isTextBox: true))
        let trailer = clip("Trailer", SlideRect(x: 40, y: 40, width: 320, height: 180),
                           MediaClip(kind: .video, mediaID: movie, posterID: poster, playback: .onClick, start: 0.5, end: 6, volume: 0.75))
        let teaser = clip("Teaser", SlideRect(x: 400, y: 40, width: 240, height: 135),
                          MediaClip(kind: .video, mediaID: movie, playback: .manually, isMuted: true, loops: true))
        let music = clip("Music", SlideRect(x: 40, y: 260, width: audioIconSize, height: audioIconSize),
                         MediaClip(kind: .audio, mediaID: sound, playback: .automatically, volume: 0.6, loops: true, hidesWhenPresenting: true,
                                   stopsOnSlideChange: false))
        let ding = clip("Ding", SlideRect(x: 100, y: 260, width: audioIconSize, height: audioIconSize),
                        MediaClip(kind: .audio, mediaID: wave, playback: .onClick, end: 0.5))
        slide.elements = [trailer, teaser, music, ding, caption]
        slide.animations = [SlideAnimation(elementID: caption.id, effect: .fadeIn, start: .onClick),
                            SlideAnimation(elementID: teaser.id, effect: .appear, start: .afterPrevious)]
        return slide
    }

    static func addObjectComments(_ presentation: inout Presentation) {
        var chartCommented = false
        for (index, slide) in presentation.slides.enumerated() {
            if !chartCommented, let chart = slide.elements.first(where: { $0.chart != nil }) {
                chartCommented = true
                presentation.slides[index].comments.append(CommentThread(comments: [comment("Ada Lovelace", minutes: 50, "Label the axes.")],
                                                                         elementID: chart.id, position: SlidePoint(x: 400, y: 30)))
            }
            if let table = slide.elements.first(where: { $0.table != nil }), presentation.slides[index].comments.allSatisfy({ $0.elementID != table.id }) {
                presentation.slides[index].comments.append(CommentThread(comments: [comment("田中 太郎", minutes: 55, "表の数字を確認しました")],
                                                                         isResolved: true, elementID: table.id, position: SlidePoint(x: 20, y: 10.5)))
            }
        }
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

    /// Every built-in theme in one deck: a title slide on each.
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

    /// `count` slides of text, shapes and tables, with a chart on every fourth, for timing.
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
            var table = Table.make(rows: 5, columns: 4, width: 400)
            for row in 0..<5 {
                for column in 0..<4 { table.cells[row][column].text.paragraphs = [TextParagraph(row == 0 ? "Head \(column)" : "\(number).\(row).\(column)")] }
            }
            slide.elements.append(Self.table("Table", at: SlidePoint(x: 40, y: 120), table))
            if number % 4 == 0 {
                slide.elements.append(Self.chart("Chart", SlideRect(x: 460, y: 120, width: 220, height: 160), Self.salesChart(ChartKind.allCases[number % ChartKind.allCases.count])))
            }
            slide.notes = TextBody("Notes for slide \(number + 1)")
            slide.transition = SlideTransition(kind: TransitionKind.allCases[number % TransitionKind.allCases.count], duration: 0.75)
            slide.animations = [
                SlideAnimation(elementID: slide.elements[1].id, effect: .fadeIn, byParagraph: true),
                SlideAnimation(elementID: slide.elements[2].id, effect: .flyInFromLeft, start: .afterPrevious),
                SlideAnimation(elementID: slide.elements[3].id, effect: .spin, start: .withPrevious, duration: 1),
            ]
            slides.append(slide)
        }
        presentation.slides = slides
        return presentation
    }
}
