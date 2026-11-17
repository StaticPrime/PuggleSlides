import Foundation

/// The themes in the Themes panel. Simple Light is the default theme; the others are PuggleSlides' own designs
/// on the same layouts.
public enum BuiltInThemes {
    /// What sets one theme apart from another.
    public struct Design: Sendable {
        public var name: String
        public var colors: [ThemeColorSlot: String]
        public var headingFont: String
        public var bodyFont: String
        /// The slide background, as a theme color.
        public var background: ThemeColorSlot
        public var titleColor: ThemeColorSlot
        public var bodyColor: ThemeColorSlot
        public var titleBold: Bool
        /// Alignment of the title slide's and section header's text.
        public var titleSlideAlignment: TextAlignment
        /// A band of color along one edge of every slide, if any.
        public var band: Band?
        /// A color block behind the title slide's title, if any.
        public var titleSlideBlock: ThemeColorSlot?
        /// The panel color on "Section title and description".
        public var panel: ThemeColorSlot

        public enum Band: Sendable {
            case top(height: Double, color: ThemeColorSlot)
            case left(width: Double, color: ThemeColorSlot)
            case bottom(height: Double, color: ThemeColorSlot)
        }
    }

    public static let designs: [Design] = [
        Design(name: "Simple Light",
               colors: [.dark1: "000000", .light1: "FFFFFF", .dark2: "595959", .light2: "EEEEEE", .accent1: "4285F4",
                        .accent2: "212121", .accent3: "78909C", .accent4: "FFAB40", .accent5: "0097A7", .accent6: "EEFF41",
                        .hyperlink: "0097A7", .followedHyperlink: "0097A7"],
               headingFont: "Arial", bodyFont: "Arial", background: .light1, titleColor: .dark1, bodyColor: .dark2,
               titleBold: false, titleSlideAlignment: .center, band: nil, titleSlideBlock: nil, panel: .light2),
        Design(name: "Simple Dark",
               colors: [.dark1: "212121", .light1: "FFFFFF", .dark2: "424242", .light2: "E0E0E0", .accent1: "8AB4F8",
                        .accent2: "FFAB40", .accent3: "4DD0E1", .accent4: "F06292", .accent5: "AED581", .accent6: "FFF176",
                        .hyperlink: "8AB4F8", .followedHyperlink: "8AB4F8"],
               headingFont: "Arial", bodyFont: "Arial", background: .dark1, titleColor: .light1, bodyColor: .light2,
               titleBold: false, titleSlideAlignment: .center, band: nil, titleSlideBlock: nil, panel: .dark2),
        Design(name: "Puggle",
               colors: [.dark1: "3E2723", .light1: "FFFFFF", .dark2: "6D4C41", .light2: "FFF4E0", .accent1: "F29D38",
                        .accent2: "8D6E63", .accent3: "FFCC80", .accent4: "4E9A8E", .accent5: "E57373", .accent6: "FFE082",
                        .hyperlink: "D2691E", .followedHyperlink: "A0522D"],
               headingFont: "Avenir Next", bodyFont: "Avenir Next", background: .light2, titleColor: .dark1, bodyColor: .dark2,
               titleBold: true, titleSlideAlignment: .left, band: .bottom(height: 14, color: .accent1), titleSlideBlock: nil,
               panel: .accent3),
        Design(name: "Harbor",
               colors: [.dark1: "0D2B45", .light1: "FFFFFF", .dark2: "1F4E79", .light2: "E8F1F8", .accent1: "1F8A9E",
                        .accent2: "F2A541", .accent3: "4F6D8A", .accent4: "A3C4DC", .accent5: "E15554", .accent6: "7BC950",
                        .hyperlink: "1F8A9E", .followedHyperlink: "4F6D8A"],
               headingFont: "Helvetica Neue", bodyFont: "Helvetica Neue", background: .light1, titleColor: .dark1, bodyColor: .dark2,
               titleBold: true, titleSlideAlignment: .left, band: .left(width: 18, color: .dark2), titleSlideBlock: .dark1,
               panel: .dark2),
        Design(name: "Meadow",
               colors: [.dark1: "1B3A2B", .light1: "FFFFFF", .dark2: "2E5E45", .light2: "EEF6EC", .accent1: "5A9E6F",
                        .accent2: "E3B23C", .accent3: "8FB996", .accent4: "D96C4F", .accent5: "3D7EA6", .accent6: "C9D97E",
                        .hyperlink: "2E7D5B", .followedHyperlink: "5A9E6F"],
               headingFont: "Georgia", bodyFont: "Avenir Next", background: .light2, titleColor: .dark1, bodyColor: .dark2,
               titleBold: false, titleSlideAlignment: .center, band: .top(height: 10, color: .accent1), titleSlideBlock: nil,
               panel: .accent3),
        Design(name: "Midnight",
               colors: [.dark1: "10172A", .light1: "FFFFFF", .dark2: "1E293B", .light2: "CBD5E1", .accent1: "818CF8",
                        .accent2: "F472B6", .accent3: "34D399", .accent4: "FBBF24", .accent5: "60A5FA", .accent6: "F87171",
                        .hyperlink: "93C5FD", .followedHyperlink: "C4B5FD"],
               headingFont: "Futura", bodyFont: "Helvetica Neue", background: .dark1, titleColor: .light1, bodyColor: .light2,
               titleBold: false, titleSlideAlignment: .left, band: .bottom(height: 8, color: .accent1), titleSlideBlock: nil,
               panel: .dark2),
        Design(name: "Paperback",
               colors: [.dark1: "262626", .light1: "FFFFFF", .dark2: "4A4A4A", .light2: "F7F3EA", .accent1: "B23A48",
                        .accent2: "2F4858", .accent3: "D9B26F", .accent4: "6B8F71", .accent5: "8C5E58", .accent6: "C9C1B1",
                        .hyperlink: "B23A48", .followedHyperlink: "8C5E58"],
               headingFont: "Baskerville", bodyFont: "Baskerville", background: .light2, titleColor: .dark1, bodyColor: .dark2,
               titleBold: false, titleSlideAlignment: .center, band: nil, titleSlideBlock: nil, panel: .accent2),
        Design(name: "Citrus",
               colors: [.dark1: "1F2937", .light1: "FFFFFF", .dark2: "374151", .light2: "FFFBEB", .accent1: "F59E0B",
                        .accent2: "10B981", .accent3: "EF4444", .accent4: "3B82F6", .accent5: "8B5CF6", .accent6: "FCD34D",
                        .hyperlink: "D97706", .followedHyperlink: "B45309"],
               headingFont: "Gill Sans", bodyFont: "Gill Sans", background: .light1, titleColor: .dark1, bodyColor: .dark2,
               titleBold: true, titleSlideAlignment: .left, band: .top(height: 24, color: .accent1), titleSlideBlock: .accent1,
               panel: .accent6),
    ]

    public static func simpleLight(slideSize: SlideSize = .widescreen) -> Theme { make(designs[0], slideSize: slideSize) }
    public static func simpleDark(slideSize: SlideSize = .widescreen) -> Theme { make(designs[1], slideSize: slideSize) }

    /// The presentation-wide default text style: the body font at 14 points.
    public static let defaultTextStyle: ListStyle = {
        var style = ListStyle()
        for level in 0...8 {
            style[level] = LevelStyle(character: CharacterStyle(fontFamily: "+mn-lt", fontSize: 14, color: ColorRef(theme: .dark1)))
        }
        return style
    }()

    // MARK: Building

    /// Positions in the default 16:9 page, in EMU (9,144,000 × 5,143,500), scaled to `slideSize`.
    private struct Scaler {
        let size: SlideSize

        func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> SlideRect {
            let sx = size.width / 720, sy = size.height / 405
            return SlideRect(x: EMU.points(x) * sx, y: EMU.points(y) * sy, width: EMU.points(width) * sx, height: EMU.points(height) * sy)
        }
    }

    static func placeholder(_ type: PlaceholderType, index: Int = 0, name: String, frame: SlideRect, anchor: VerticalAnchor,
                            autofit: Autofit = .shrinkOnOverflow, level: LevelStyle = .empty, text: TextBody? = nil) -> SlideElement {
        var body = text ?? TextBody()
        body.properties = TextBodyProperties(anchor: anchor, insets: .standard, autofit: autofit, wraps: true)
        if !level.isEmpty { body.listStyle[0] = level }
        return SlideElement(name: name, placement: Placement(frame: frame), placeholder: PlaceholderRef(type: type, index: index),
                            content: .shape(Shape(text: body)))
    }

    static func decoration(_ name: String, frame: SlideRect, color: ThemeColorSlot) -> SlideElement {
        SlideElement(name: name, placement: Placement(frame: frame),
                     content: .shape(Shape(fill: .solid(ColorRef(theme: color)), outline: Outline.none)))
    }

    /// Bullets for nine levels: ●, ○, ■ repeating, each level indented another half inch.
    static func bodyListStyle(color: ThemeColorSlot) -> ListStyle {
        var style = ListStyle()
        let characters = ["●", "○", "■"]
        for level in 0...8 {
            style[level] = LevelStyle(
                paragraph: ParagraphStyle(alignment: .left, lineSpacing: 1.15, spaceBefore: level == 0 ? 0 : 0, spaceAfter: 0,
                                          marginLeft: 36 * Double(level + 1), indent: level == 0 ? -27 : -25,
                                          bullet: .character(characters[level % 3])),
                character: CharacterStyle(fontFamily: "+mn-lt", fontSize: level == 0 ? 18 : 14, color: ColorRef(theme: color)))
        }
        return style
    }

    public static func make(_ design: Design, slideSize: SlideSize = .widescreen) -> Theme {
        let s = Scaler(size: slideSize)
        var scheme: [ThemeColorSlot: RGBColor] = [:]
        for (slot, hex) in design.colors { scheme[slot] = RGBColor(hex: hex) }
        let titleCharacter = CharacterStyle(fontFamily: "+mj-lt", fontSize: 28, bold: design.titleBold ? true : nil,
                                            color: ColorRef(theme: design.titleColor))
        var titleStyle = ListStyle()
        for level in 0...8 {
            titleStyle[level] = LevelStyle(paragraph: ParagraphStyle(alignment: .left, lineSpacing: 1, spaceBefore: 0, spaceAfter: 0,
                                                                     marginLeft: 0, indent: 0, bullet: Bullet.none),
                                           character: titleCharacter)
        }
        let bodyStyle = bodyListStyle(color: design.bodyColor)
        var otherStyle = ListStyle()
        for level in 0...8 {
            otherStyle[level] = LevelStyle(paragraph: ParagraphStyle(alignment: .left, lineSpacing: 1, bullet: Bullet.none),
                                           character: CharacterStyle(fontFamily: "+mn-lt", fontSize: 18, color: ColorRef(theme: design.titleColor)))
        }

        let titleFrame = s.rect(311700, 445025, 8520600, 572700)
        let bodyFrame = s.rect(311700, 1152475, 8520600, 3416400)
        let numberFrame = s.rect(8472458, 4663217, 548700, 393600)
        func slideNumber() -> SlideElement {
            var paragraph = TextParagraph(runs: [TextRun("‹#›", field: .slideNumber)])
            paragraph.style.alignment = .right
            return placeholder(.slideNumber, index: 12, name: "Slide Number", frame: numberFrame, anchor: .middle, autofit: .none,
                               level: LevelStyle(paragraph: ParagraphStyle(alignment: .right),
                                                 character: CharacterStyle(fontSize: 10, color: ColorRef(theme: design.bodyColor))),
                               text: TextBody(paragraphs: [paragraph]))
        }

        var themeElements: [SlideElement] = []
        if let band = design.band {
            switch band {
            case .top(let height, let color):
                themeElements.append(decoration("Band", frame: SlideRect(x: 0, y: 0, width: slideSize.width, height: height), color: color))
            case .left(let width, let color):
                themeElements.append(decoration("Band", frame: SlideRect(x: 0, y: 0, width: width, height: slideSize.height), color: color))
            case .bottom(let height, let color):
                themeElements.append(decoration("Band", frame: SlideRect(x: 0, y: slideSize.height - height, width: slideSize.width, height: height),
                                                color: color))
            }
        }
        themeElements += [
            placeholder(.title, name: "Title", frame: titleFrame, anchor: .top),
            placeholder(.body, index: 1, name: "Text", frame: bodyFrame, anchor: .top),
            slideNumber(),
        ]

        func level(size: Double, alignment: TextAlignment? = nil, bullet: Bool = false, color: ThemeColorSlot? = nil,
                   bold: Bool? = nil) -> LevelStyle {
            LevelStyle(paragraph: ParagraphStyle(alignment: alignment, lineSpacing: bullet ? nil : 1, marginLeft: bullet ? nil : 0,
                                                 indent: bullet ? nil : 0, bullet: bullet ? nil : Bullet.none),
                       character: CharacterStyle(fontSize: size, bold: bold, color: color.map { ColorRef(theme: $0) }))
        }
        let titleAlign = design.titleSlideAlignment
        let onBlock: ThemeColorSlot? = design.titleSlideBlock == nil ? nil : .light1

        var titleSlideElements: [SlideElement] = []
        if let block = design.titleSlideBlock {
            titleSlideElements.append(decoration("Title block", frame: SlideRect(x: 0, y: 0, width: slideSize.width, height: slideSize.height * 0.55),
                                                 color: block))
        }
        titleSlideElements += [
            placeholder(.centeredTitle, name: "Title", frame: s.rect(311700, 744575, 8520600, 2052600), anchor: .bottom,
                        level: level(size: 52, alignment: titleAlign, color: onBlock)),
            placeholder(.subtitle, index: 1, name: "Subtitle", frame: s.rect(311700, 2834125, 8520600, 792600), anchor: .top,
                        level: level(size: 28, alignment: titleAlign)),
            slideNumber(),
        ]

        var sectionElements: [SlideElement] = [
            placeholder(.title, name: "Title", frame: s.rect(311700, 2150850, 8520600, 841800), anchor: .middle,
                        level: level(size: 36, alignment: titleAlign)),
            slideNumber(),
        ]
        if design.band == nil, design.titleSlideBlock != nil {
            sectionElements.insert(decoration("Rule", frame: s.rect(311700, 3053650, 1200000, 45720), color: .accent1), at: 1)
        }

        let layouts: [Layout] = [
            Layout(name: LayoutKind.title.title, kind: .title, elements: titleSlideElements),
            Layout(name: LayoutKind.sectionHeader.title, kind: .sectionHeader, elements: sectionElements),
            Layout(name: LayoutKind.titleAndBody.title, kind: .titleAndBody, elements: [
                placeholder(.title, name: "Title", frame: titleFrame, anchor: .top),
                placeholder(.body, index: 1, name: "Text", frame: bodyFrame, anchor: .top),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.titleAndTwoColumns.title, kind: .titleAndTwoColumns, elements: [
                placeholder(.title, name: "Title", frame: titleFrame, anchor: .top),
                placeholder(.body, index: 1, name: "Text", frame: s.rect(311700, 1152475, 3999900, 3416400), anchor: .top),
                placeholder(.body, index: 2, name: "Text", frame: s.rect(4832400, 1152475, 3999900, 3416400), anchor: .top),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.titleOnly.title, kind: .titleOnly, elements: [
                placeholder(.title, name: "Title", frame: titleFrame, anchor: .top),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.oneColumnText.title, kind: .oneColumnText, elements: [
                placeholder(.title, name: "Title", frame: s.rect(311700, 555600, 3000000, 755700), anchor: .bottom,
                            level: level(size: 24)),
                placeholder(.body, index: 1, name: "Text", frame: s.rect(311700, 1389600, 3000000, 3179400), anchor: .top),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.mainPoint.title, kind: .mainPoint, elements: [
                placeholder(.title, name: "Title", frame: s.rect(490250, 450150, 8222100, 4091100), anchor: .middle,
                            level: level(size: 48)),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.sectionTitleAndDescription.title, kind: .sectionTitleAndDescription, elements: [
                decoration("Panel", frame: SlideRect(x: slideSize.width / 2, y: 0, width: slideSize.width / 2, height: slideSize.height),
                           color: design.panel),
                placeholder(.title, name: "Title", frame: s.rect(265500, 1233175, 4045200, 1482300), anchor: .bottom,
                            level: level(size: 42)),
                placeholder(.subtitle, index: 1, name: "Subtitle", frame: s.rect(265500, 2803075, 4045200, 1235100), anchor: .top,
                            level: level(size: 21)),
                placeholder(.body, index: 2, name: "Text", frame: s.rect(4939500, 724075, 3837000, 3695100), anchor: .middle),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.caption.title, kind: .caption, elements: [
                placeholder(.body, index: 1, name: "Text", frame: s.rect(311700, 4230575, 5998800, 605100), anchor: .middle,
                            level: level(size: 12)),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.bigNumber.title, kind: .bigNumber, elements: [
                placeholder(.title, name: "Title", frame: s.rect(311700, 1106125, 8520600, 1963500), anchor: .bottom,
                            level: level(size: 120, alignment: .center, bold: design.titleBold ? true : nil)),
                placeholder(.body, index: 1, name: "Text", frame: s.rect(311700, 3152225, 8520600, 1300800), anchor: .top,
                            level: level(size: 18, alignment: .center)),
                slideNumber(),
            ]),
            Layout(name: LayoutKind.blank.title, kind: .blank, elements: [slideNumber()]),
        ]

        return Theme(name: design.name, colors: ColorScheme(name: design.name, colors: scheme),
                     fonts: FontScheme(name: design.name, major: design.headingFont, minor: design.bodyFont),
                     background: .solid(ColorRef(theme: design.background)), elements: themeElements,
                     titleStyle: titleStyle, bodyStyle: bodyStyle, otherStyle: otherStyle, layouts: layouts)
    }
}
