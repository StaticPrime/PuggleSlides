import Foundation

/// Numbers as Excel writes them in cells and chart caches: whole numbers without a decimal point, others in the
/// shortest form that reads back to the same value.
enum PPTXChartNumber {
    static func string(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    /// The number a label spells exactly as `string` would write it ("1.5", "-3"), so it can be stored as a number
    /// and read back as the same text.
    static func exactValue(_ label: String) -> Double? {
        guard let value = Double(label), value.isFinite, string(value) == label else { return nil }
        return value
    }
}

/// A chart's numbers as they're laid out in its workbook, as PowerPoint lays out a new chart's: the label heading in
/// A1 with the labels below it, and each series in the next column under its name.
struct PPTXChartSheet {
    static let name = "Sheet1"
    /// Excel's grid: 1,048,576 rows (one of them for headings) and 16,384 columns (one of them for labels).
    static let maximumRows = 1_048_575
    static let maximumSeries = 16_383
    /// The most values a chart is written with, once every series is as long as the labels: as many as a chart is read
    /// with, so whatever was read can be saved.
    static let maximumValues = PPTXChartReader.maximumPoints

    /// Every series as long as the labels, within Excel's limits.
    let data: ChartData
    /// A scatter chart's x values, kept as numbers when every label is one.
    let numericLabels: Bool

    init(_ chart: Chart) {
        // Within the grid first, then padded: padding a chart that's far too big would make it bigger still.
        var data = chart.data
        if data.labels.count > Self.maximumRows { data.labels = Array(data.labels.prefix(Self.maximumRows)) }
        if data.series.count > Self.maximumSeries { data.series = Array(data.series.prefix(Self.maximumSeries)) }
        for index in data.series.indices where data.series[index].values.count > Self.maximumRows {
            data.series[index].values = Array(data.series[index].values.prefix(Self.maximumRows))
        }
        let rows = max(1, data.rowCount)
        if data.series.count > Self.maximumValues / rows { data.series = Array(data.series.prefix(max(1, Self.maximumValues / rows))) }
        data = data.padded()
        self.data = data
        numericLabels = chart.kind == .scatter && data.labels.contains { !$0.isEmpty }
            && data.labels.allSatisfy { $0.isEmpty || PPTXChartNumber.exactValue($0) != nil }
    }

    var rowCount: Int { data.labels.count }

    /// "A", "B", … "Z", "AA" for a zero-based column.
    static func columnName(_ index: Int) -> String {
        var number = max(0, index) + 1, name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            number = (number - 1) / 26
        }
        return name
    }

    /// "Sheet1!$B$1": where series `index` is named.
    func nameReference(_ index: Int) -> String {
        "\(Self.name)!$\(Self.columnName(index + 1))$1"
    }

    /// "Sheet1!$A$2:$A$5": the labels; nil when there are none.
    var labelReference: String? { columnReference(0) }

    func valueReference(_ index: Int) -> String? { columnReference(index + 1) }

    private func columnReference(_ column: Int) -> String? {
        guard rowCount > 0 else { return nil }
        let name = Self.columnName(column)
        return "\(Self.name)!$\(name)$2:$\(name)$\(rowCount + 1)"
    }
}

/// A minimal workbook holding a chart's numbers: one sheet, shared strings and the styles Excel requires. PowerPoint
/// opens it in Excel when the chart's data is edited.
enum PPTXWorkbook {
    static let mainContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
    static let worksheetContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
    static let stylesContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"
    static let sharedStringsContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"
    /// Excel's longest cell text.
    static let maximumTextLength = 32_767

    static func write(_ sheet: PPTXChartSheet, date: Date) -> Data {
        var strings = SharedStrings()
        var rows = XMLWriter(fragmentCapacity: min(256 + sheet.rowCount * (sheet.data.series.count + 1) * 32, 16 << 20))
        let data = sheet.data
        var lastColumn = 0
        // Row 1: the headings, where they have text.
        rows.raw("<row r=\"1\">")
        let headings = [data.labelHeading] + data.series.map(\.name)
        for (column, heading) in headings.enumerated() where !heading.isEmpty {
            rows.raw("<c r=\"\(PPTXChartSheet.columnName(column))1\" t=\"s\"><v>\(strings.index(of: heading))</v></c>")
            lastColumn = max(lastColumn, column)
        }
        rows.raw("</row>")
        for row in 0..<sheet.rowCount {
            let number = row + 2
            rows.raw("<row r=\"\(number)\">")
            let label = data.labels[row]
            if !label.isEmpty {
                if sheet.numericLabels, let value = PPTXChartNumber.exactValue(label) {
                    rows.raw("<c r=\"A\(number)\"><v>\(PPTXChartNumber.string(value))</v></c>")
                } else {
                    rows.raw("<c r=\"A\(number)\" t=\"s\"><v>\(strings.index(of: label))</v></c>")
                }
            }
            for (index, series) in data.series.enumerated() {
                guard row < series.values.count, let value = series.values[row], value.isFinite else { continue }
                rows.raw("<c r=\"\(PPTXChartSheet.columnName(index + 1))\(number)\"><v>\(PPTXChartNumber.string(value))</v></c>")
                lastColumn = max(lastColumn, index + 1)
            }
            rows.raw("</row>")
        }
        var worksheet = XMLWriter(reservingCapacity: rows.bytes.count + 512)
        worksheet.raw("<worksheet xmlns=\"\(PPTXNamespace.spreadsheet)\" xmlns:r=\"\(PPTXNamespace.relationships)\">")
        worksheet.raw("<dimension ref=\"A1:\(PPTXChartSheet.columnName(lastColumn))\(sheet.rowCount + 1)\"/>")
        worksheet.raw("<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews><sheetFormatPr defaultRowHeight=\"15\"/><sheetData>")
        worksheet.append(rows)
        worksheet.raw("</sheetData><pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/></worksheet>")

        var zip = ZipWriter(date: date)
        // In-memory parts this small always fit; a failure leaves an empty workbook rather than none.
        try? zip.add("[Content_Types].xml", document(
            "<Types xmlns=\"\(PPTXNamespace.contentTypes)\"><Default Extension=\"rels\" ContentType=\"\(PPTXContentType.relationships)\"/>"
                + "<Default Extension=\"xml\" ContentType=\"\(PPTXContentType.xml)\"/>"
                + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"\(mainContentType)\"/>"
                + "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"\(worksheetContentType)\"/>"
                + "<Override PartName=\"/xl/styles.xml\" ContentType=\"\(stylesContentType)\"/>"
                + "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"\(sharedStringsContentType)\"/></Types>"))
        try? zip.add("_rels/.rels", document(
            "<Relationships xmlns=\"\(PPTXNamespace.packageRelationships)\"><Relationship Id=\"rId1\" "
                + "Type=\"\(PPTXRelationshipType.officeDocument)\" Target=\"xl/workbook.xml\"/></Relationships>"))
        try? zip.add("xl/workbook.xml", document(
            "<workbook xmlns=\"\(PPTXNamespace.spreadsheet)\" xmlns:r=\"\(PPTXNamespace.relationships)\">"
                // The window the sheet's view belongs to.
                + "<bookViews><workbookView xWindow=\"0\" yWindow=\"0\" windowWidth=\"16384\" windowHeight=\"8192\"/></bookViews><sheets>"
                + "<sheet name=\"\(PPTXChartSheet.name)\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"))
        try? zip.add("xl/_rels/workbook.xml.rels", document(
            "<Relationships xmlns=\"\(PPTXNamespace.packageRelationships)\">"
                + "<Relationship Id=\"rId1\" Type=\"\(PPTXRelationshipType.worksheet)\" Target=\"worksheets/sheet1.xml\"/>"
                + "<Relationship Id=\"rId2\" Type=\"\(PPTXRelationshipType.styles)\" Target=\"styles.xml\"/>"
                + "<Relationship Id=\"rId3\" Type=\"\(PPTXRelationshipType.sharedStrings)\" Target=\"sharedStrings.xml\"/></Relationships>"))
        try? zip.add("xl/worksheets/sheet1.xml", worksheet.data)
        try? zip.add("xl/styles.xml", document(
            "<styleSheet xmlns=\"\(PPTXNamespace.spreadsheet)\"><fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
                + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
                + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
                + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
                + "<cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs>"
                + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"))
        try? zip.add("xl/sharedStrings.xml", strings.data())
        return (try? zip.finish()) ?? Data()
    }

    private static func document(_ markup: String) -> Data {
        var xml = XMLWriter(reservingCapacity: markup.utf8.count + 64)
        xml.raw(markup)
        return xml.data
    }

    /// The shared string table: each distinct text once.
    private struct SharedStrings {
        private var indexes: [String: Int] = [:]
        private var strings: [String] = []
        private var references = 0

        mutating func index(of text: String) -> Int {
            references += 1
            if let index = indexes[text] { return index }
            strings.append(text)
            indexes[text] = strings.count - 1
            return strings.count - 1
        }

        func data() -> Data {
            var xml = XMLWriter(reservingCapacity: 128 + strings.count * 24)
            xml.raw("<sst xmlns=\"\(PPTXNamespace.spreadsheet)\" count=\"\(references)\" uniqueCount=\"\(strings.count)\">")
            for text in strings {
                let clipped = PPTXWorkbook.clipped(text)
                let padded = clipped.first.map(\.isWhitespace) == true || clipped.last.map(\.isWhitespace) == true
                xml.raw(padded ? "<si><t xml:space=\"preserve\">" : "<si><t>")
                xml.text(PPTXWorkbook.escaped(clipped))
                xml.raw("</t></si>")
            }
            xml.raw("</sst>")
            return xml.data
        }
    }

    /// Text within Excel's cell limit, cut at a whole character.
    static func clipped(_ text: String) -> String {
        guard text.utf16.count > maximumTextLength else { return text }
        var result = ""
        for character in text {
            guard result.utf16.count + character.utf16.count <= maximumTextLength else { break }
            result.append(character)
        }
        return result
    }

    /// SpreadsheetML spells characters as `_xHHHH_`, so text that already looks like that is escaped by spelling its
    /// underscore `_x005F_`.
    static func escaped(_ text: String) -> String {
        guard text.contains("_x") || text.contains("_X") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        for index in scalars.indices {
            if escapeValue(scalars, at: index) != nil {
                result.append(contentsOf: "_x005F_".unicodeScalars)
            } else {
                result.append(scalars[index])
            }
        }
        return String(result)
    }

    /// Text with SpreadsheetML's `_xHHHH_` escapes turned back into characters.
    static func unescaped(_ text: String) -> String {
        guard text.contains("_x") || text.contains("_X") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if let value = escapeValue(scalars, at: index) {
                if let scalar = UnicodeScalar(value) { result.append(scalar) }
                index += 7
            } else {
                result.append(scalars[index])
                index += 1
            }
        }
        return String(result)
    }

    private static func escapeValue(_ scalars: [Unicode.Scalar], at index: Int) -> UInt32? {
        guard index + 6 < scalars.count, scalars[index] == "_", scalars[index + 1] == "x" || scalars[index + 1] == "X",
              scalars[index + 6] == "_" else { return nil }
        var value: UInt32 = 0
        for offset in 2...5 {
            guard let digit = scalars[index + offset].properties.isASCIIHexDigit ? UInt32(String(scalars[index + offset]), radix: 16) : nil
            else { return nil }
            value = value << 4 | digit
        }
        return value
    }
}

/// A value read from a workbook's cell.
enum PPTXCellValue: Equatable {
    case text(String)
    case number(Double)

    var text: String {
        switch self {
        case .text(let text): text
        case .number(let number): PPTXChartNumber.string(number)
        }
    }

    var number: Double? {
        switch self {
        case .text(let text): Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        case .number(let number): number
        }
    }
}

/// Reads the cells of an embedded workbook, for chart data a chart part doesn't cache. Only what charts refer to is
/// needed: the values of one sheet's cells.
final class PPTXWorkbookReader {
    /// Workbooks embedded in real presentations are small (a few kilobytes); larger ones aren't expanded, and no part
    /// bigger than `partSizeLimit` is parsed.
    static let sizeLimit = 64 << 20
    static let partSizeLimit = 16 << 20

    private let zip: ZipReader
    /// Sheet parts by lowercased name, in workbook order.
    private var sheetPaths: [(name: String, path: String)] = []
    private var sharedStrings: [String] = []
    private var sheets: [String: [PPTXCellAddress: PPTXCellValue]] = [:]

    init?(_ data: Data) {
        guard let zip = try? ZipReader(data: data, sizeLimit: Self.sizeLimit) else { return nil }
        self.zip = zip
        let rootRelationships = relationships(of: "")
        guard let workbookPath = rootRelationships.first("officeDocument")?.target ?? (zip.contains("xl/workbook.xml") ? "xl/workbook.xml" : nil),
              let workbook = xml(workbookPath) else { return nil }
        let workbookRelationships = relationships(of: workbookPath)
        for sheet in workbook.child("sheets")?.children("sheet") ?? [] {
            guard let name = sheet["name"], let relationship = workbookRelationships[sheet["id"]], !relationship.isExternal else { continue }
            sheetPaths.append((name, relationship.target))
        }
        if let stringsPath = workbookRelationships.first("sharedStrings")?.target, let strings = xml(stringsPath) {
            sharedStrings = strings.children("si").map(Self.text)
        }
    }

    private func xml(_ path: String) -> XNode? {
        guard let entry = zip.entry(path), entry.uncompressedSize <= Self.partSizeLimit, let data = try? zip.read(entry) else { return nil }
        return try? PPTXXML.parse(data)
    }

    private func relationships(of part: String) -> PPTXRelationships {
        guard let data = try? zip.read(PPTXPackage.relationshipsPath(for: part)) else { return PPTXRelationships() }
        return (try? PPTXPackage.relationships(data, of: part)) ?? PPTXRelationships()
    }

    /// A string item's text: its `t`, or its rich text runs' together.
    private static func text(_ item: XNode) -> String {
        if let plain = item.child("t") { return PPTXWorkbook.unescaped(plain.text) }
        return PPTXWorkbook.unescaped(item.children("r").map { $0.child("t")?.text ?? "" }.joined())
    }

    /// A cell's value; `sheet` nil is the first sheet.
    func value(sheet: String?, at address: PPTXCellAddress) -> PPTXCellValue? {
        cells(sheet: sheet)[address]
    }

    private func cells(sheet name: String?) -> [PPTXCellAddress: PPTXCellValue] {
        let entry = name.flatMap { wanted in sheetPaths.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame } } ?? sheetPaths.first
        guard let entry else { return [:] }
        let key = entry.name.lowercased()
        if let known = sheets[key] { return known }
        var cells: [PPTXCellAddress: PPTXCellValue] = [:]
        for row in xml(entry.path)?.child("sheetData")?.children("row") ?? [] {
            for cell in row.children("c") {
                guard let reference = cell["r"], let address = PPTXCellAddress(reference) else { continue }
                let raw = cell.child("v")?.text
                switch cell["t"] {
                case "s":
                    if let index = PPTXValue.int(raw), sharedStrings.indices.contains(index) { cells[address] = .text(sharedStrings[index]) }
                case "inlineStr":
                    if let item = cell.child("is") { cells[address] = .text(Self.text(item)) }
                case "str", "e":
                    if let raw { cells[address] = .text(raw) }
                case "b":
                    cells[address] = .number(PPTXValue.bool(raw) == true ? 1 : 0)
                default:
                    if let number = PPTXValue.double(raw) { cells[address] = .number(number) }
                }
            }
        }
        sheets[key] = cells
        return cells
    }

    /// The values of a reference's cells in order ("Sheet1!$B$2:$B$5"), along its one row or column, at most `limit`
    /// of them; nil when it isn't a reference to a single row or column.
    func values(_ formula: String, limit: Int = PPTXCellReference.maximumCells) -> [PPTXCellValue?]? {
        guard let reference = PPTXCellReference(formula) else { return nil }
        return reference.addresses(limit: limit).map { value(sheet: reference.sheet, at: $0) }
    }
}

/// A zero-based cell position.
struct PPTXCellAddress: Hashable {
    var row: Int
    var column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// "B3", "$B$3".
    init?(_ text: String) {
        var column = 0, row = 0, letters = 0, digits = 0
        for scalar in text.unicodeScalars where scalar != "$" {
            switch scalar {
            case "A"..."Z", "a"..."z":
                guard digits == 0, letters < 3 else { return nil }
                let upper = scalar.value >= 97 ? scalar.value - 32 : scalar.value
                column = column * 26 + Int(upper) - 64
                letters += 1
            case "0"..."9":
                guard letters > 0, digits < 7 else { return nil }
                row = row * 10 + Int(scalar.value) - 48
                digits += 1
            default:
                return nil
            }
        }
        guard letters > 0, digits > 0, row > 0 else { return nil }
        self.init(row: row - 1, column: column - 1)
    }
}

/// A chart's reference to a block of one sheet's cells: "Sheet1!$A$2:$A$5", "'My data'!B1".
struct PPTXCellReference {
    /// Nil when the reference names no sheet.
    var sheet: String?
    var first: PPTXCellAddress
    var last: PPTXCellAddress

    /// Charts refer to one row or one column; larger blocks are refused, as are references to whole columns.
    static let maximumCells = 1_048_576

    init?(_ formula: String) {
        var text = formula.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("=") { text.removeFirst() }
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        guard !text.contains(",") else { return nil }
        if let bang = text.lastIndex(of: "!") {
            var name = String(text[..<bang])
            if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 {
                name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            sheet = name
            text = String(text[text.index(after: bang)...])
        }
        let ends = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(ends.count), let first = PPTXCellAddress(String(ends[0])),
              let last = ends.count == 2 ? PPTXCellAddress(String(ends[1])) : first else { return nil }
        self.first = PPTXCellAddress(row: min(first.row, last.row), column: min(first.column, last.column))
        self.last = PPTXCellAddress(row: max(first.row, last.row), column: max(first.column, last.column))
        guard self.first.row == self.last.row || self.first.column == self.last.column,
              max(self.last.row - self.first.row, self.last.column - self.first.column) < Self.maximumCells else { return nil }
    }

    /// How many cells the reference names.
    var count: Int { max(last.row - first.row, last.column - first.column) + 1 }

    /// The cells along the row or column, in order, at most `limit` of them.
    func addresses(limit: Int = PPTXCellReference.maximumCells) -> [PPTXCellAddress] {
        let count = max(0, min(limit, max(last.row - first.row, last.column - first.column) + 1))
        guard count > 0 else { return [] }
        if first.column == last.column { return (0..<count).map { PPTXCellAddress(row: first.row + $0, column: first.column) } }
        return (0..<count).map { PPTXCellAddress(row: first.row, column: first.column + $0) }
    }
}
