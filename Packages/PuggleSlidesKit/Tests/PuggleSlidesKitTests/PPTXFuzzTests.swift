import Foundation
import Testing
@testable import PuggleSlidesKit

/// Damaged files either read or fail with a message; they never crash. What does read also writes.
struct PPTXFuzzTests {
    /// Reads `data`; returns whether it read. Anything thrown must be a friendly error.
    @discardableResult
    static func survives(_ data: Data) -> Bool {
        do {
            let file = try PresentationIO.read(data, format: .pptx)
            // Whatever was read can be saved again.
            _ = try PresentationIO.write(file.presentation, format: .pptx)
            return true
        } catch let error as PresentationIOError {
            #expect(!(error.errorDescription ?? "").isEmpty)
            return false
        } catch {
            Issue.record("unexpected error \(error)")
            return false
        }
    }

    @Test func survivesRandomByteDamageAndTruncation() throws {
        let original = try PPTXWriter.write(PPTXSamples.rich())
        var random = PPTXTestRandom(seed: 2026)
        for _ in 0..<300 {
            var damaged = original
            for _ in 0..<(1 + random.below(8)) {
                damaged[random.below(damaged.count)] = UInt8(truncatingIfNeeded: random.next())
            }
            if random.below(4) == 0 { damaged = Data(damaged.prefix(random.below(damaged.count))) }
            Self.survives(damaged)
        }
    }

    /// Damage inside the XML of each kind of part, with fragments chosen to reach awkward corners of the reader.
    @Test func survivesDamagedXML() throws {
        let fragments = [
            "<p:sp>", "</p:sp>", "<p:grpSp>", "</p:grpSp>", "<a:xfrm rot=\"99999999999999\" flipH=\"maybe\">", "<a:off x=\"99999999999999999999\" y=\"-1e308\"/>",
            "<a:ext cx=\"NaN\" cy=\"inf\"/>", "<a:chExt cx=\"0\" cy=\"1\"/>", "<a:chOff x=\"1e300\" y=\"0\"/>", "<a:gd name=\"adj\" fmla=\"*/ w 0 0\"/>",
            "<a:arcTo wR=\"1e308\" hR=\"-1e308\" stAng=\"nan\" swAng=\"1e400\"/>", "<a:path w=\"-5\" h=\"1e30\">", "<p:ph type=\"bogus\" idx=\"-5\"/>",
            "<a:schemeClr val=\"phClr\"><a:lumMod val=\"1e308\"/><a:lumMod val=\"1e308\"/><a:lumMod val=\"0\"/></a:schemeClr>",
            "<a:hslClr hue=\"1e30\" sat=\"-5\" lum=\"NaN\"/>", "<a:scrgbClr r=\"1e9\" g=\"-1\" b=\"x\"/>", "<a:prstClr val=\"medPurple\"/>",
            "<a:fillRef idx=\"99999999999\"><a:schemeClr val=\"accent1\"/></a:fillRef>", "<a:lnRef idx=\"-3\"/>", "<p:bg><p:bgRef idx=\"1001\"/></p:bg>",
            "r:id=\"rId1\"", "r:embed=\"rId1\"", "<p:sldId id=\"256\" r:id=\"rId1\"/>", "<p:sldMasterId id=\"1\" r:id=\"rId2\"/>",
            "<mc:AlternateContent xmlns:mc=\"urn:mc\"><mc:Choice><p:sp/></mc:Choice></mc:AlternateContent>", "<a:buAutoNum type=\"x\" startAt=\"-99999999999\"/>",
            "<a:spcPct val=\"1e308\"/>", "<a:rPr sz=\"-5\" baseline=\"nan\"/>", "&amp;", "<![CDATA[x]]>", "<a:pPr lvl=\"99999\"/>", "<a:srcRect l=\"1e30\"/>",
            "<p:clrMapOvr><a:overrideClrMapping bg1=\"tx1\" tx1=\"dk1\"/></p:clrMapOvr>", "<p:clrMap bg1=\"dk1\" tx1=\"lt1\"/>", "<a:hlinkClick r:id=\"rId2\" action=\"ppaction://hlinksldjump\"/>",
            "<a:fld type=\"slidenum\"><a:t>9</a:t></a:fld>", "<a:normAutofit fontScale=\"-1\" lnSpcReduction=\"1e9\"/>", "<p:timing><p:childTnLst><p:par/></p:childTnLst></p:timing>",
            "<p:graphicFrame><a:graphic><a:graphicData uri=\"x\"/></a:graphic></p:graphicFrame>", "<p:contentPart/>", "<a:gradFill><a:gsLst/></a:gradFill>",
            // Motion.
            "<p:par><p:cTn id=\"9\" presetID=\"99999999999\" presetClass=\"entr\" presetSubtype=\"-3\" nodeType=\"afterEffect\">", "</p:cTn></p:par>",
            "<p:pRg st=\"-5\" end=\"99999999999\"/>", "<p:cond delay=\"1e308\"/>", "<p:cond evt=\"onBegin\" delay=\"indefinite\"/>",
            "<p:seq><p:cTn nodeType=\"interactiveSeq\">", "<p:spTgt spid=\"2\"><p:txEl><p:charRg st=\"0\" end=\"2\"/></p:txEl></p:spTgt>",
            "<p:animRot by=\"NaN\"><p:cBhvr><p:cTn dur=\"-1\"/></p:cBhvr></p:animRot>", "<p:set><p:to><p:strVal val=\"hidden\"/></p:to></p:set>",
            "<p:transition spd=\"warp\" p14:dur=\"-99\" advTm=\"x\"><p14:prism dir=\"z\"/></p:transition>", "<p15:prstTrans prst=\"\"/>",
            "<p:bldP spid=\"2\" grpId=\"0\" build=\"p\" bldLvl=\"999\"/>", "<p:subTnLst><p:audio/></p:subTnLst>",
            // Tables, charts, word art, picture effects and guides.
            "<a:tbl>", "</a:tbl>", "<a:tr h=\"1e308\">", "</a:tr>", "<a:tc gridSpan=\"99999999\" rowSpan=\"-1\" hMerge=\"1\" vMerge=\"maybe\">", "</a:tc>",
            "<a:gridCol w=\"-5\"/>", "<a:tcPr marL=\"nan\" anchor=\"sideways\"><a:lnL w=\"-1\"/></a:tcPr>", "<a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId>",
            "<a:tblPr firstRow=\"1\" lastRow=\"1\" bandRow=\"1\" bandCol=\"1\" firstCol=\"1\" lastCol=\"1\">", "<c:ser>", "</c:ser>",
            "<c:pt idx=\"99999999\"><c:v>x</c:v></c:pt>", "<c:pt idx=\"-3\"><c:v>1e400</c:v></c:pt>", "<c:ptCount val=\"999999999\"/>", "<c:holeSize val=\"-4\"/>",
            "<c:f>'Sheet''1'!$ZZZZ$0:$A$99999999</c:f>", "<c:barDir val=\"diagonal\"/>", "<c:grouping val=\"percentStacked\"/>", "<c:radarChart>", "</c:lineChart>",
            "<c:formatCode>[Red]#,##0.00;(0.0%)</c:formatCode>", "<c:formatCode>dddd mmmm yyyy</c:formatCode>", "<c:legendPos val=\"x\"/>",
            "<p15:guide pos=\"nan\" orient=\"x\"/>", "<a:duotone><a:prstClr val=\"black\"/></a:duotone>", "<a:alphaModFix amt=\"-5\"/>",
            "<a:lum bright=\"1e9\" contrast=\"-1e9\"/>", "<a:prstTxWarp prst=\"textArchUp\"/>", "fromWordArt=\"1\"",
        ]
        var random = PPTXTestRandom(seed: 99)
        func mutated(_ text: String) -> String {
            var scalars = Array(text.unicodeScalars)
            for _ in 0..<(1 + random.below(4)) {
                let position = random.below(scalars.count + 1)
                switch random.below(3) {
                case 0:
                    let length = min(random.below(30), scalars.count - position)
                    scalars.removeSubrange(position..<(position + length))
                case 1:
                    scalars.insert(contentsOf: fragments[random.below(fragments.count)].unicodeScalars, at: position)
                default:
                    let length = min(random.below(60), scalars.count - position)
                    scalars.insert(contentsOf: scalars[position..<(position + length)], at: position)
                }
            }
            return String(String.UnicodeScalarView(scalars))
        }
        let original = try PPTXTestPackage.parts(of: try PPTXWriter.write(PPTXSamples.rich()))
        let targets = ["ppt/slides/slide2.xml", "ppt/slides/slide3.xml", "ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml",
                       "ppt/theme/theme1.xml", "ppt/presentation.xml", "ppt/slides/_rels/slide3.xml.rels", "[Content_Types].xml",
                       "ppt/notesSlides/notesSlide1.xml", "ppt/_rels/presentation.xml.rels", "ppt/charts/chart1.xml", "ppt/charts/chart2.xml",
                       "ppt/charts/_rels/chart1.xml.rels", "ppt/charts/_rels/chart2.xml.rels"]
        var readable = 0
        for iteration in 0..<400 {
            var parts = original
            let target = targets[iteration % targets.count]
            parts[target] = Data(mutated(String(decoding: original[target]!, as: UTF8.self)).utf8)
            if Self.survives(try PPTXTestPackage.zip(parts)) { readable += 1 }
        }
        // Some damage is harmless (inside text, or in parts read leniently).
        #expect(readable > 0)
    }

    /// Damaged chart workbooks, table styles and hostile sizes: what can be read is, quickly, and the rest warns.
    @Test func survivesDamagedChartsTablesAndWorkbooks() throws {
        let original = try PPTXTestPackage.parts(of: try PPTXWriter.write(PPTXSamples.objects()))
        var random = PPTXTestRandom(seed: 7)
        // Workbooks with random damage, cut short, or replaced by something else, with the charts' caches gone so the
        // workbook is all there is.
        let workbook = try #require(original["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"])
        let chart = String(decoding: try #require(original["ppt/charts/chart1.xml"]), as: UTF8.self)
        let uncached = chart.replacingOccurrences(of: #"<c:(str|num)Cache>.*?</c:(str|num)Cache>"#, with: "", options: .regularExpression)
        for iteration in 0..<60 {
            var parts = original
            var damaged = workbook
            for _ in 0..<(1 + random.below(6)) { damaged[random.below(damaged.count)] = UInt8(truncatingIfNeeded: random.next()) }
            if iteration % 3 == 0 { damaged = Data(damaged.prefix(random.below(damaged.count))) }
            if iteration % 10 == 0 { damaged = Data("<html>not a workbook</html>".utf8) }
            parts["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"] = damaged
            parts["ppt/charts/chart1.xml"] = Data(uncached.utf8)
            Self.survives(try PPTXTestPackage.zip(parts))
        }
        // A workbook whose sheet claims cells far away, and a chart claiming a million points per series in many series.
        var parts = original
        let points = String(repeating: "<c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:val><c:numLit><c:ptCount val=\"1048575\"/>"
            + "<c:pt idx=\"1048574\"><c:v>1</c:v></c:pt></c:numLit></c:val></c:ser>", count: 40)
        parts["ppt/charts/chart2.xml"] = Data(chart.replacingOccurrences(of: "<c:barChart>", with: "<c:barChart>" + points).utf8)
        let clock = ContinuousClock()
        var file: PresentationFile?
        let elapsed = try clock.measure { file = try PresentationIO.read(try PPTXTestPackage.zip(parts), format: .pptx) }
        #expect(elapsed < .seconds(20))
        let hostile = try #require(file?.presentation.slides[1].elements.first?.chart)
        #expect(hostile.data.series.map(\.values.count).reduce(0, +) <= PPTXChartReader.maximumPoints + PPTXChartSheet.maximumRows)
        #expect(file?.warnings.contains(.charts) == true)
        // A table styles part that isn't one, and a table naming a style that isn't anywhere.
        parts = try PPTXTestPackage.parts(of: try PPTXTestPackage(slides: [PPTXTestPackage.Slide(xml: PPTXTestPackage.slide(PPTXTestPackage.graphicFrame(
            4, "T", uri: PPTXTestPackage.tableURI, content: "<a:tbl><a:tblPr firstRow=\"1\"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>"
                + "<a:tblGrid><a:gridCol w=\"100\"/></a:tblGrid><a:tr h=\"100\"><a:tc><a:tcPr/></a:tc></a:tr></a:tbl>")))]).data())
        parts["ppt/tableStyles.xml"] = Data("<garbage".utf8)
        #expect(Self.survives(try PPTXTestPackage.zip(parts)))
    }

    /// Charts and tables that claim far more than they hold read and save in bounded time and memory.
    @Test func hostileChartsAndTablesStayCheap() throws {
        typealias Package = PPTXTestPackage
        let axes = "<c:axId val=\"10\"/><c:axId val=\"20\"/>"
        let clock = ContinuousClock()
        // A point at the largest index there is.
        let overflow = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:val><c:numRef><c:f>x</c:f>"
            + "<c:numCache><c:ptCount val=\"1\"/><c:pt idx=\"9223372036854775807\"><c:v>1</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>\(axes)</c:barChart>")
        // Caches claiming a million points they don't have, shared by eight frames; names claiming a million cells.
        let claimed = "<c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:tx><c:strRef><c:f>Sheet1!$B$1:$B$1048576</c:f><c:strCache><c:ptCount val=\"1048575\"/>"
            + "</c:strCache></c:strRef></c:tx><c:cat><c:strRef><c:f>x</c:f><c:strCache><c:ptCount val=\"1048575\"/></c:strCache></c:strRef></c:cat>"
            + "<c:val><c:numRef><c:f>x</c:f><c:numCache><c:ptCount val=\"1048575\"/></c:numCache></c:numRef></c:val></c:ser>"
        let empty = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/>" + String(repeating: claimed, count: 400) + "\(axes)</c:barChart>")
        let names = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/>" + String(repeating: "<c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:tx><c:strRef>"
            + "<c:f>Sheet1!$B$1:$B$1048576</c:f></c:strRef></c:tx></c:ser>", count: 40) + "\(axes)</c:barChart>")
        // Thousands of labels with points, and hundreds of empty series that saving would make as long.
        let labels = (0..<5_000).map { "<c:pt idx=\"\($0)\"><c:v>L\($0)</c:v></c:pt>" }.joined()
        let wide = Package.chartSpace("<c:barChart><c:barDir val=\"col\"/><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:cat><c:strRef><c:f>x</c:f>"
            + "<c:strCache><c:ptCount val=\"5000\"/>\(labels)</c:strCache></c:strRef></c:cat></c:ser>"
            + String(repeating: "<c:ser><c:idx val=\"1\"/><c:order val=\"1\"/></c:ser>", count: 400) + "\(axes)</c:barChart>")
        let workbook = PPTXWorkbook.write(PPTXChartSheet(Chart.sample(.column)), date: Date(timeIntervalSince1970: 0))
        var package = PPTXChartTests.package([overflow, empty, names, wide], workbooks: [2: workbook])
        package.slides[0].xml = package.slides[0].xml.replacingOccurrences(of: "</p:spTree>", with:
            (0..<7).map { Package.chartFrame(100 + $0, "Shared \($0)", relationship: "rId21") }.joined() + "</p:spTree>")
        var file: PresentationFile?
        let reading = try clock.measure { file = try PresentationIO.read(try package.data(), format: .pptx) }
        #expect(reading < .seconds(20))
        let charts = try #require(file?.presentation.slides[0].elements).compactMap(\.chart)
        // Four charts, and the second shown seven more times.
        #expect(charts.count == 11)
        #expect(charts[4...].allSatisfy { $0 == charts[1] })
        for chart in charts {
            let padded = chart.data.padded()
            #expect(padded.series.count * max(1, padded.rowCount) <= PPTXChartReader.maximumPoints)
        }
        // The cache claims become short gaps, not a million points each.
        #expect(charts[1].data.labels.count <= PPTXChartReader.maximumTrailingGap)
        #expect(charts[3].data.labels.count == 5_000 && charts[3].data.series.count <= 200)
        #expect(file?.warnings == [.charts])
        var written = Data()
        let writing = try clock.measure { written = try PresentationIO.write(try #require(file).presentation, format: .pptx) }
        #expect(writing < .seconds(30))
        #expect(!written.isEmpty)

        // A doughnut's hole that's absurd but finite.
        var donut = Chart.sample(.donut)
        donut.pieHole = 1e300
        let part = try #require(try Package.writtenParts(PPTXChartTests.deck([donut]))["ppt/charts/chart1.xml"])
        #expect(part.contains("<c:holeSize val=\"90\"/>"))

        // Long merged rows write in time proportional to their size.
        var cells = [Array(repeating: TableCell(), count: 20_000)]
        cells[0][0].columnSpan = 20_000
        let table = Table(columnWidths: Array(repeating: 1, count: 20_000), rowHeights: [20], cells: cells)
        let element = SlideElement(name: "T", placement: Placement(frame: SlideRect(x: 0, y: 0, width: 20_000, height: 20)), content: .table(table))
        #expect(try clock.measure { _ = try PPTXWriter.write(PPTXTableTests.deck([element])) } < .seconds(10))
        // A merge across the whole second row, into the half of it a merge from the first row already took: evened out
        // in time proportional to the table's size, not its square.
        let first = String(repeating: "<a:tc><a:tcPr/></a:tc>", count: 20_000) + "<a:tc gridSpan=\"20000\" rowSpan=\"2\"><a:tcPr/></a:tc>"
            + String(repeating: "<a:tc hMerge=\"1\"><a:tcPr/></a:tc>", count: 19_999)
        let second = "<a:tc gridSpan=\"40000\"><a:tcPr/></a:tc>" + String(repeating: "<a:tc hMerge=\"1\"><a:tcPr/></a:tc>", count: 39_999)
        let overlapping = "<a:tbl><a:tblPr/><a:tblGrid>" + String(repeating: "<a:gridCol w=\"100\"/>", count: 40_000) + "</a:tblGrid>"
            + "<a:tr h=\"100\">\(first)</a:tr><a:tr h=\"100\">\(second)</a:tr></a:tbl>"
        var tables = Package()
        tables.slides = [Package.Slide(xml: Package.slide(Package.graphicFrame(4, "Wide", uri: Package.tableURI, content: overlapping)))]
        var tableFile: PresentationFile?
        let tableReading = try clock.measure { tableFile = try PresentationIO.read(try tables.data(), format: .pptx) }
        #expect(tableReading < .seconds(20))
        let wideTable = try #require(tableFile?.presentation.slides[0].elements.first?.table)
        #expect(wideTable.cells[1][0].columnSpan == 20_000 && wideTable.cells[0][20_000].columnSpan == 20_000 && wideTable.cells[1][20_000].isCovered)
    }

    @Test func deeplyNestedPartsAreRefusedWithoutCrashing() throws {
        var parts = try PPTXTestPackage.parts(of: try PPTXWriter.write(Presentation.makeDefault()))
        let depth = 100_000
        let nested = String(repeating: "<p:grpSp>", count: depth) + String(repeating: "</p:grpSp>", count: depth)
        let slide = String(decoding: parts["ppt/slides/slide1.xml"]!, as: UTF8.self).replacingOccurrences(of: "</p:spTree>", with: nested + "</p:spTree>")
        parts["ppt/slides/slide1.xml"] = Data(slide.utf8)
        #expect(throws: PresentationIOError.unreadable(PPTXMessages.damaged)) {
            try PresentationIO.read(try PPTXTestPackage.zip(parts), format: .pptx)
        }

        // Groups nested deeper than any real deck, but within what XML allows, are cut off with a warning.
        var groups = try PPTXTestPackage.parts(of: try PPTXWriter.write(Presentation.makeDefault()))
        let shape = "<p:sp><p:nvSpPr><p:cNvPr id=\"99\" name=\"Deep\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"10\" cy=\"10\"/></a:xfrm></p:spPr></p:sp>"
        let group = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"98\" name=\"G\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>"
        let deep = String(repeating: group, count: 60) + shape + String(repeating: "</p:grpSp>", count: 60)
        let text = String(decoding: groups["ppt/slides/slide1.xml"]!, as: UTF8.self).replacingOccurrences(of: "</p:spTree>", with: deep + "</p:spTree>")
        groups["ppt/slides/slide1.xml"] = Data(text.utf8)
        let file = try PresentationIO.read(try PPTXTestPackage.zip(groups), format: .pptx)
        #expect(file.warnings == [.otherContent])
    }
}
