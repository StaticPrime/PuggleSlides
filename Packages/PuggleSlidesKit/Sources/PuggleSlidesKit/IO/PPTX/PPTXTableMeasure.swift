import CoreGraphics
import CoreText
import Foundation

/// How tall a table's rows are as PuggleSlides draws them: at least their minimum height, and as tall as their text
/// needs. PowerPoint stores rows at the height they show, so they're written that way.
///
/// Text is measured with Core Text much as the editor lays it out: fonts that aren't installed fall back to Arial,
/// superscript and subscript are two thirds of their size, and paragraphs keep their line spacing, spacing and
/// indents. Rows only grow when the text needs clearly more than the minimum, so tables whose text fits keep exactly
/// the heights they were given.
enum PPTXTableMeasure {
    /// Text that needs no more than this beyond a row's minimum height leaves the row as it is.
    static let tolerance = 0.5

    static func rowHeights(_ table: Table, style: ElementStyle, slideNumber: Int?) -> [Double] {
        var heights = table.rowHeights.map { $0.isFinite ? max(0, $0) : 0 }
        guard table.rowCount > 0, table.columnCount > 0 else { return heights }
        var columnX: [Double] = [0]
        for width in table.columnWidths { columnX.append(columnX[columnX.count - 1] + max(1, width.isFinite ? width : 0)) }
        // Rows grow for their single-row cells first; merged cells then stretch their last row.
        var tall: [(row: Int, span: Int, needed: Double)] = []
        for (row, column) in table.visibleCells {
            let cell = table.cells[row][column]
            guard !cell.text.isEmpty else { continue }
            let width = columnX[min(table.columnCount, column + cell.columnSpan)] - columnX[column]
            let textWidth = max(1, width - cell.insets.left - cell.insets.right)
            let paragraphs = style.resolvedParagraphs(cell.text, slideNumber: slideNumber)
            let needed = height(of: paragraphs, width: textWidth) + cell.insets.top + cell.insets.bottom
            if cell.rowSpan == 1 {
                if needed > heights[row] + tolerance { heights[row] = needed }
            } else {
                tall.append((row, cell.rowSpan, needed))
            }
        }
        for item in tall {
            let rows = item.row..<min(table.rowCount, item.row + item.span)
            let total = rows.map { heights[$0] }.reduce(0, +)
            if item.needed > total + tolerance, let last = rows.last { heights[last] += item.needed - total }
        }
        return heights
    }

    /// The height of laid-out paragraphs at a width. Laying out finds fonts for characters a font lacks, so it's done
    /// through `FontRequests`.
    static func height(of paragraphs: [ResolvedParagraph], width: Double) -> Double {
        FontRequests.shared.one { layOut(paragraphs, width: width) }
    }

    private static func layOut(_ paragraphs: [ResolvedParagraph], width: Double) -> Double {
        let text = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let start = text.length
            for run in paragraph.runs where !run.text.isEmpty {
                text.append(NSAttributedString(string: run.text, attributes: [.init(kCTFontAttributeName as String): font(run.style)]))
            }
            if text.length == start {
                // An empty paragraph is as tall as its paragraph mark.
                text.append(NSAttributedString(string: " ", attributes: [.init(kCTFontAttributeName as String): font(paragraph.endStyle)]))
            }
            if index < paragraphs.count - 1 {
                let end = paragraph.runs.last(where: { !$0.text.isEmpty })?.style ?? paragraph.endStyle
                text.append(NSAttributedString(string: "\n", attributes: [.init(kCTFontAttributeName as String): font(end)]))
            }
            text.addAttribute(.init(kCTParagraphStyleAttributeName as String), value: paragraphStyle(paragraph),
                              range: NSRange(location: start, length: text.length - start))
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
                                                                CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), nil)
        return size.height.isFinite ? Double(size.height) : 0
    }

    private static func paragraphStyle(_ paragraph: ResolvedParagraph) -> CTParagraphStyle {
        let specifiers: [CTParagraphStyleSpecifier] = [.lineHeightMultiple, .paragraphSpacingBefore, .paragraphSpacing, .headIndent,
                                                       .firstLineHeadIndent]
        let values: [CGFloat] = [max(0, paragraph.lineSpacing), max(0, paragraph.spaceBefore), max(0, paragraph.spaceAfter),
                                 max(0, paragraph.marginLeft), max(0, paragraph.marginLeft + paragraph.indent)].map { CGFloat($0.isFinite ? $0 : 0) }
        return values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return CTParagraphStyleCreate(nil, 0) }
            let settings = specifiers.enumerated().map { index, specifier in
                CTParagraphStyleSetting(spec: specifier, valueSize: MemoryLayout<CGFloat>.size, value: base + index)
            }
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }

    /// The font a run shows in, falling back to Arial as the editor does for families that aren't installed.
    private static func font(_ style: ResolvedCharacterStyle) -> CTFont {
        var size = max(1, style.fontSize.isFinite ? style.fontSize : 18)
        if style.baseline != .normal { size *= 2.0 / 3.0 }
        return FontRequests.shared.font(family: style.fontFamily, size: size, bold: style.bold, italic: style.italic)
    }
}
