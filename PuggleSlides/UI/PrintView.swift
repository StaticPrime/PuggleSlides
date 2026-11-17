import AppKit
import PuggleSlidesKit
import SwiftUI

/// The print layouts.
enum PrintLayoutKind: Hashable, Identifiable {
    case slides, slidesWithNotes, handout(Int)

    static let all: [PrintLayoutKind] = [.slides, .slidesWithNotes] + [1, 2, 3, 4, 6, 9].map { .handout($0) }

    var id: String { title }

    var title: String {
        switch self {
        case .slides: "1 slide without notes"
        case .slidesWithNotes: "1 slide with notes"
        case .handout(let count): "Handout - \(count) slide\(count == 1 ? "" : "s") per page"
        }
    }

    var isHandout: Bool {
        if case .handout = self { return true }
        return false
    }
}

/// File ▸ Print settings and preview.
struct SlidePrintSettings: Equatable {
    var layout = PrintLayoutKind.slides
    /// Handouts only: slides print on pages of the slide's own shape, and notes pages are portrait.
    var landscape = false
    var hidesBackground = false
    var includesSkipped = false
}

/// Draws printed pages, stacked top to bottom, for the print system, PDFs and the preview.
final class PrintPagesView: NSView {
    let presentation: Presentation
    let settings: SlidePrintSettings
    /// Each page's slides, by index into the presentation.
    let pages: [[Int]]
    let pageSize: CGSize
    private static let letter = CGSize(width: 612, height: 792)

    init(presentation: Presentation, settings: SlidePrintSettings) {
        self.presentation = presentation
        self.settings = settings
        let slides = presentation.slides.indices.filter { settings.includesSkipped || !presentation.slides[$0].isSkipped }
        switch settings.layout {
        case .slides:
            pageSize = presentation.slideSize.cgSize
            pages = slides.map { [$0] }
        case .slidesWithNotes:
            pageSize = Self.letter
            pages = slides.map { [$0] }
        case .handout(let count):
            pageSize = settings.landscape ? CGSize(width: Self.letter.height, height: Self.letter.width) : Self.letter
            pages = stride(from: 0, to: slides.count, by: count).map { Array(slides[$0..<min(slides.count, $0 + count)]) }
        }
        super.init(frame: NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height * CGFloat(max(1, pages.count))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, pages.count))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * pageSize.height, width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let first = max(0, Int(dirtyRect.minY / pageSize.height)), last = min(pages.count - 1, Int((dirtyRect.maxY - 1) / pageSize.height))
        guard first <= last else { return }
        for index in first...last { drawPage(index, in: rectForPage(index + 1)) }
    }

    private func drawSlide(_ index: Int, in rect: CGRect, bordered: Bool) {
        let size = presentation.slideSize
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                            width: size.width * scale, height: size.height * scale)
        SlideRenderer.draw(presentation.slides[index], of: presentation, in: fitted,
                           options: SlideRenderer.Options(slideNumber: index + 1, hidesBackground: settings.hidesBackground))
        if bordered {
            NSColor(white: 0.55, alpha: 1).setStroke()
            let border = NSBezierPath(rect: fitted.insetBy(dx: 0.25, dy: 0.25))
            border.lineWidth = 0.5
            border.stroke()
        }
    }

    /// One page: a slide, a slide with its notes, or a handout of several slides.
    func drawPage(_ index: Int, in page: NSRect) {
        NSColor.white.setFill()
        page.fill()
        guard pages.indices.contains(index) else { return }
        let slides = pages[index]
        switch settings.layout {
        case .slides:
            drawSlide(slides[0], in: page, bordered: false)
        case .slidesWithNotes:
            let margin: CGFloat = 54
            let width = page.width - margin * 2
            let size = presentation.slideSize
            let slideRect = CGRect(x: page.minX + margin, y: page.minY + margin, width: width, height: width * size.height / size.width)
            drawSlide(slides[0], in: slideRect, bordered: true)
            let notes = presentation.slides[slides[0]].notes.plainText
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Arial", size: 12) ?? .systemFont(ofSize: 12),
                                                             .foregroundColor: NSColor.black]
            (notes as NSString).draw(with: CGRect(x: slideRect.minX, y: slideRect.maxY + 24, width: width,
                                                  height: page.maxY - margin - slideRect.maxY - 24),
                                     options: [.usesLineFragmentOrigin], attributes: attributes)
            let number = "\(slides[0] + 1)" as NSString
            let numberAttributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Arial", size: 10) ?? .systemFont(ofSize: 10),
                                                                   .foregroundColor: NSColor.darkGray]
            let numberSize = number.size(withAttributes: numberAttributes)
            number.draw(at: CGPoint(x: page.maxX - margin - numberSize.width, y: page.maxY - margin / 2 - numberSize.height), withAttributes: numberAttributes)
        case .handout(let count):
            let margin: CGFloat = 36
            let area = page.insetBy(dx: margin, dy: margin)
            if count == 3, !settings.landscape {
                // Three slides down the left, with lines for notes beside each.
                let rowHeight = area.height / 3
                for (row, slide) in slides.enumerated() {
                    let cell = CGRect(x: area.minX, y: area.minY + CGFloat(row) * rowHeight, width: area.width * 0.48, height: rowHeight)
                    drawSlide(slide, in: cell.insetBy(dx: 6, dy: 10), bordered: true)
                    NSColor(white: 0.7, alpha: 1).setFill()
                    let linesLeft = area.minX + area.width * 0.54
                    for line in 1...6 {
                        NSRect(x: linesLeft, y: cell.minY + 12 + CGFloat(line) * (rowHeight - 24) / 7, width: area.maxX - linesLeft, height: 0.5).fill()
                    }
                }
                return
            }
            let (columns, rows): (Int, Int) = switch count {
            case 1: (1, 1)
            case 2: settings.landscape ? (2, 1) : (1, 2)
            case 3: (3, 1)
            case 4: (2, 2)
            case 6: settings.landscape ? (3, 2) : (2, 3)
            default: (3, 3)
            }
            let cellWidth = area.width / CGFloat(columns), cellHeight = area.height / CGFloat(rows)
            for (position, slide) in slides.enumerated() {
                let cell = CGRect(x: area.minX + CGFloat(position % columns) * cellWidth, y: area.minY + CGFloat(position / columns) * cellHeight,
                                  width: cellWidth, height: cellHeight)
                drawSlide(slide, in: cell.insetBy(dx: 9, dy: 9), bordered: true)
            }
        }
    }

    /// A picture of one page, for the preview.
    func image(of index: Int, width: CGFloat) -> NSImage {
        let size = CGSize(width: width, height: width * pageSize.height / pageSize.width)
        let scale = width / pageSize.width
        return NSImage(size: size, flipped: true) { [self] bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            drawPage(index, in: CGRect(origin: .zero, size: pageSize))
            _ = bounds
            return true
        }
    }

    /// The pages as a PDF document.
    func pdfData() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        for index in pages.indices {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawPage(index, in: CGRect(origin: .zero, size: mediaBox.size))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Print info that leaves layout to this view: no margins of its own, the page centered, and the paper turned to fit.
    func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.orientation = pageSize.width > pageSize.height ? .landscape : .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        return info
    }
}

/// The print settings and preview: the layout and options across the top, and the pages below.
struct PrintSettingsView: View {
    let presentation: Presentation
    @State var settings: SlidePrintSettings
    /// Called with the settings and whether to download a PDF (true) or print (false); nil cancels.
    let finish: (SlidePrintSettings?, Bool) -> Void

    var body: some View {
        let pages = PrintPagesView(presentation: presentation, settings: settings)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { finish(nil, false) } label: {
                    Label("Close preview", systemImage: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Divider().frame(height: 22)
                Picker("", selection: $settings.layout) {
                    ForEach(PrintLayoutKind.all) { layout in Text(layout.title).tag(layout) }
                }
                .labelsHidden()
                .fixedSize()
                if settings.layout.isHandout {
                    Picker("", selection: $settings.landscape) {
                        Text("Portrait").tag(false)
                        Text("Landscape").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle("Hide background", isOn: $settings.hidesBackground).fixedSize()
                Toggle("Include skipped slides", isOn: $settings.includesSkipped).fixedSize()
                Spacer(minLength: 8)
                PanelButton(title: "Download as PDF", primary: false, isEnabled: !pages.pages.isEmpty) { finish(settings, true) }
                    .fixedSize()
                PanelButton(title: "Print", isEnabled: !pages.pages.isEmpty) { finish(settings, false) }
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 13))
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(pages.pages.indices, id: \.self) { index in
                        Image(nsImage: pages.image(of: index, width: 520))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    if pages.pages.isEmpty {
                        Text("No slides to print").foregroundStyle(Theme.secondaryText).padding(40)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: Theme.canvas))
        }
        .frame(width: 1100, height: 680)
    }
}
