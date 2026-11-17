import Foundation
@testable import PuggleSlidesKit

/// Packages laid out as LibreOffice Impress 7 writes tables, charts, Fontwork, picture adjustments and snap lines: one
/// "Default" master, the slide's shapes and automatic styles given by each test, and LibreOffice's table designs in
/// styles.xml (cells filled through graphic properties, bordered through paragraph properties, as Impress writes them).
enum ODPObjectFixture {
    static let namespaces = ODPLibreOfficeFixture.namespaces
        + " xmlns:chartooo=\"http://openoffice.org/2010/chart\" xmlns:dr3d=\"urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0\""

    /// LibreOffice's "default" table design: gray header, banded rows, white lines between cells.
    static let tableDesign = """
        <style:style style:name="default" style:family="table-cell">
        <style:graphic-properties draw:fill="solid" draw:fill-color="#ccccff" draw:textarea-horizontal-align="justify" \
        draw:textarea-vertical-align="middle" fo:padding-top="0.13cm" fo:padding-bottom="0.13cm" fo:padding-left="0.25cm" fo:padding-right="0.25cm"/>
        <style:paragraph-properties fo:border="0.51pt solid #ffffff"/>
        <style:text-properties fo:color="#000000" fo:font-size="18pt" style:font-name="Liberation Sans"/>
        </style:style>
        <style:style style:name="gray1" style:family="table-cell" style:parent-style-name="default">
        <style:graphic-properties draw:fill-color="#808080"/>
        <style:text-properties fo:color="#ffffff" fo:font-weight="bold"/>
        </style:style>
        <style:style style:name="gray2" style:family="table-cell" style:parent-style-name="default">
        <style:graphic-properties draw:fill-color="#b3b3b3"/>
        </style:style>
        <style:style style:name="gray3" style:family="table-cell" style:parent-style-name="default">
        <style:graphic-properties draw:fill-color="#e6e6e6"/>
        </style:style>
        <table:table-template text:style-name="default">
        <table:first-row table:style-name="gray1"/>
        <table:last-row table:style-name="gray1"/>
        <table:first-column table:style-name="gray1"/>
        <table:last-column table:style-name="gray1"/>
        <table:body table:style-name="gray3"/>
        <table:odd-rows table:style-name="gray2"/>
        <table:odd-columns table:style-name="gray2"/>
        </table:table-template>
        """

    static func styles(_ common: String = tableDesign) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-styles \(namespaces)>
        <office:font-face-decls><style:font-face style:name="Liberation Sans" svg:font-family="&apos;Liberation Sans&apos;"/></office:font-face-decls>
        <office:styles>
        <style:default-style style:family="graphic"><style:text-properties style:font-name="Liberation Sans" fo:font-size="18pt"/></style:default-style>
        <style:style style:name="standard" style:family="graphic"><style:graphic-properties draw:stroke="solid" svg:stroke-color="#3465a4" \
        draw:fill="solid" draw:fill-color="#729fcf"/></style:style>
        <style:style style:name="objectwithoutfill" style:family="graphic" style:parent-style-name="standard">\
        <style:graphic-properties draw:fill="none"/></style:style>
        \(common)
        </office:styles>
        <office:automatic-styles>
        <style:page-layout style:name="PM1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm"/></style:page-layout>
        </office:automatic-styles>
        <office:master-styles><style:master-page style:name="Default" style:page-layout-name="PM1"/></office:master-styles>
        </office:document-styles>
        """
    }

    static func content(styles: String, shapes: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content \(namespaces)>
        <office:automatic-styles>
        <style:style style:name="gr1" style:family="graphic" style:parent-style-name="objectwithoutfill"><style:graphic-properties \
        draw:stroke="none"/></style:style>
        \(styles)
        </office:automatic-styles>
        <office:body><office:presentation>
        <draw:page draw:name="page1" draw:master-page-name="Default">\(shapes)</draw:page>
        </office:presentation></office:body>
        </office:document-content>
        """
    }

    /// A package with a slide of `shapes`, and any further parts (chart objects, settings) listed in the manifest.
    static func package(styles automatic: String = "", shapes: String, common: String = tableDesign, parts: [(String, String)] = [],
                        objects: [String] = [], images: [String: Data] = [:]) throws -> Data {
        var entries = "<manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.presentation\"/>"
        for object in objects {
            entries += "<manifest:file-entry manifest:full-path=\"\(object)/\" manifest:media-type=\"application/vnd.oasis.opendocument.chart\"/>"
        }
        let manifest = "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\">\(entries)</manifest:manifest>"
        var all: [(String, Data)] = [("content.xml", Data(content(styles: automatic, shapes: shapes).utf8)), ("styles.xml", Data(styles(common).utf8))]
        all += parts.map { ($0.0, Data($0.1.utf8)) }
        all += images.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        all.append(("META-INF/manifest.xml", Data(manifest.utf8)))
        return try ODPTestPackage.zip(all)
    }

    // MARK: Charts

    /// A chart object's content.xml as LibreOffice writes it: its styles, then the chart with LibreOffice's coordinate
    /// region, axes and series pointing into the local table, which holds `rows` under `header`.
    static func chart(class chartClass: String, plot: String = "", styles: String = "", body: String, header: [String], rows: [[String]]) -> String {
        func cell(_ text: String) -> String {
            if text.isEmpty { return "<table:table-cell><text:p/></table:table-cell>" }
            if text == "NaN" { return "<table:table-cell office:value-type=\"float\" office:value=\"NaN\"><text:p>1.#NAN</text:p></table:table-cell>" }
            if Double(text) != nil {
                return "<table:table-cell office:value-type=\"float\" office:value=\"\(text)\"><text:p>\(text)</text:p></table:table-cell>"
            }
            return "<table:table-cell office:value-type=\"string\"><text:p>\(text)</text:p></table:table-cell>"
        }
        let table = """
            <table:table table:name="local-table"><table:table-header-columns><table:table-column/></table:table-header-columns>\
            <table:table-columns><table:table-column table:number-columns-repeated="\(max(header.count - 1, 1))"/></table:table-columns>\
            <table:table-header-rows><table:table-row>\(header.map(cell).joined())</table:table-row></table:table-header-rows>\
            <table:table-rows>\(rows.map { "<table:table-row>\($0.map(cell).joined())</table:table-row>" }.joined())</table:table-rows></table:table>
            """
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <office:document-content \(namespaces)>
            <office:automatic-styles>
            <number:number-style style:name="N0"><number:number number:min-integer-digits="1"/></number:number-style>
            <style:style style:name="ch1" style:family="chart"><style:graphic-properties draw:stroke="none"/></style:style>
            <style:style style:name="ch4" style:family="chart"><style:chart-properties chart:include-hidden-cells="false" chart:auto-position="true" \
            chart:auto-size="true" chart:treat-empty-cells="leave-gap" chart:right-angled-axes="true" \(plot)/></style:style>
            <style:style style:name="ch5" style:family="chart" style:data-style-name="N0"><style:chart-properties chart:display-label="true" \
            chart:logarithmic="false" chart:reverse-direction="false" text:line-break="false" loext:try-staggering-first="false"/>\
            <style:graphic-properties svg:stroke-color="#b3b3b3"/><style:text-properties fo:font-size="10pt"/></style:style>
            \(styles)
            </office:automatic-styles>
            <office:body><office:chart>
            <chart:chart svg:width="16cm" svg:height="9cm" xlink:href="." xlink:type="simple" chart:class="\(chartClass)" chart:style-name="ch1">
            \(body)
            \(table)
            </chart:chart>
            </office:chart></office:body>
            </office:document-content>
            """
    }

    /// A frame holding chart object `name`, with LibreOffice's replacement image.
    static func chartFrame(_ name: String, object: String, replacement: Bool = true) -> String {
        """
        <draw:frame draw:name="\(name)" draw:style-name="gr1" draw:layer="layout" svg:width="16cm" svg:height="9cm" svg:x="1cm" svg:y="1cm">\
        <draw:object draw:notify-on-update-of-ranges="local-table.$A$1:.$D$5" xlink:href="./\(object)" xlink:type="simple" xlink:show="embed" \
        xlink:actuate="onLoad"><loext:p text:style-name="P1"/></draw:object>\
        \(replacement ? "<draw:image xlink:href=\"./ObjectReplacements/\(object)\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>" : "")\
        </draw:frame>
        """
    }

    /// LibreOffice's default chart data: four rows of three columns.
    static let defaultHeader = ["", "Column 1", "Column 2", "Column 3"]
    static let defaultRows = [["Row 1", "9.1", "3.2", "4.54"], ["Row 2", "2.4", "8.8", "9.65"], ["Row 3", "3.1", "1.5", "3.7"], ["Row 4", "4.3", "9.02", "6.2"]]

    /// LibreOffice's series colors, in its order.
    static let seriesColors = ["#004586", "#ff420e", "#ffd320"]

    /// Three series in columns B to D, colored as LibreOffice colors them, with the categories down column A.
    static func seriesAndAxes(seriesClass: String, labels: Bool = false, xTitle: String = "", yTitle: String = "", grid: Bool = true) -> (styles: String, body: String) {
        var styles = ""
        var series = ""
        for index in 0..<3 {
            let column = ["B", "C", "D"][index]
            styles += "<style:style style:name=\"ch\(10 + index)\" style:family=\"chart\" style:data-style-name=\"N0\"><style:chart-properties "
                + (labels ? "chart:data-label-number=\"value\" " : "") + "chart:link-data-style-to-source=\"true\"/><style:graphic-properties "
                + "svg:stroke-color=\"\(seriesColors[index])\" draw:fill-color=\"\(seriesColors[index])\" dr3d:edge-rounding=\"5%\"/></style:style>"
            series += "<chart:series chart:style-name=\"ch\(10 + index)\" chart:values-cell-range-address=\"local-table.$\(column)$2:.$\(column)$5\" "
                + "chart:label-cell-address=\"local-table.$\(column)$1\" chart:class=\"\(seriesClass)\"><chart:data-point chart:repeated=\"4\"/></chart:series>"
        }
        func title(_ text: String) -> String { text.isEmpty ? "" : "<chart:title><text:p>\(text)</text:p></chart:title>" }
        let body = """
            <chart:plot-area chart:style-name="ch4" table:cell-range-address="local-table.$A$1:.$D$5" chart:data-source-has-labels="both" \
            svg:x="0.5cm" svg:y="0.5cm" svg:width="12cm" svg:height="8cm"><chartooo:coordinate-region svg:x="1cm" svg:y="0.6cm" svg:width="11cm" \
            svg:height="7cm"/><chart:axis chart:dimension="x" chart:name="primary-x" chart:style-name="ch5" loext:axis-type="text">\(title(xTitle))\
            <chart:categories table:cell-range-address="local-table.$A$2:.$A$5"/></chart:axis><chart:axis chart:dimension="y" chart:name="primary-y" \
            chart:style-name="ch5">\(title(yTitle))\(grid ? "<chart:grid chart:style-name=\"ch5\" chart:class=\"major\"/>" : "")</chart:axis>\(series)\
            <chart:wall chart:style-name="ch1"/><chart:floor chart:style-name="ch1"/></chart:plot-area>
            """
        return (styles, body)
    }
}
