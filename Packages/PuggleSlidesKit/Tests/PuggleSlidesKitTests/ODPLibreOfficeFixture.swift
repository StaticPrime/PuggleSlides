import Foundation
@testable import PuggleSlidesKit

/// A presentation laid out as LibreOffice Impress 7 writes one: a "Default" master with LibreOffice's presentation styles
/// and theme, automatic styles named gr1, pr1, P1, T1 and L1, LibreOffice's own shapes with their equations, shapes
/// imported from PowerPoint ("ooxml-" types), ODF 1.0 shapes, lists, footers, notes, transitions and animations.
enum ODPLibreOfficeFixture {
    static let namespaces = """
        xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" \
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" \
        xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" \
        xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" \
        xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" \
        xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" \
        xmlns:smil="urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0" xmlns:anim="urn:oasis:names:tc:opendocument:xmlns:animation:1.0" \
        xmlns:officeooo="http://openoffice.org/2009/office" xmlns:drawooo="http://openoffice.org/2010/draw" \
        xmlns:loext="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0" office:version="1.3"
        """

    /// 96 × 48 pixels with no resolution stated: 72 × 36 points at 96 per inch.
    static let image = PPTXTestImage.png(width: 96, height: 48) { x, _ in x < 48 ? (200, 40, 40) : (40, 40, 200) }
    static let texture = PPTXTestImage.png(width: 4, height: 4) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }

    static func outlineLevel(_ level: Int, _ bullet: String, space: String, width: String, size: String) -> String {
        """
        <text:list-level-style-bullet text:level="\(level)" text:bullet-char="\(bullet)">\
        <style:list-level-properties text:space-before="\(space)" text:min-label-width="\(width)"/>\
        <style:text-properties fo:font-family="OpenSymbol" style:use-window-font-color="true" fo:font-size="\(size)"/>\
        </text:list-level-style-bullet>
        """
    }

    static var outlineList: String {
        outlineLevel(1, "●", space: "0.3cm", width: "0.9cm", size: "45%") + outlineLevel(2, "–", space: "1.6cm", width: "0.8cm", size: "75%")
            + outlineLevel(3, "●", space: "3cm", width: "0.6cm", size: "45%") + outlineLevel(4, "–", space: "4.2cm", width: "0.6cm", size: "75%")
            + outlineLevel(5, "●", space: "5.4cm", width: "0.6cm", size: "45%") + outlineLevel(6, "●", space: "6.6cm", width: "0.6cm", size: "45%")
            + outlineLevel(7, "●", space: "7.8cm", width: "0.6cm", size: "45%") + outlineLevel(8, "●", space: "9cm", width: "0.6cm", size: "45%")
            + outlineLevel(9, "●", space: "10.2cm", width: "0.6cm", size: "45%")
    }

    static var styles: String {
        let outline = (2...9).map { level -> String in
            let size = level == 2 ? "28pt" : level == 3 ? "24pt" : "20pt"
            return """
                <style:style style:name="Default-outline\(level)" style:family="presentation" style:parent-style-name="Default-outline\(level - 1)">\
                <style:paragraph-properties fo:margin-top="0.4cm" fo:margin-bottom="0cm"/>\
                <style:text-properties fo:font-size="\(size)" style:font-size-asian="\(size)" style:font-size-complex="\(size)"/></style:style>
                """
        }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <office:document-styles \(namespaces)>
            <office:font-face-decls>
            <style:font-face style:name="Liberation Sans" svg:font-family="&apos;Liberation Sans&apos;" style:font-family-generic="roman" style:font-pitch="variable"/>
            <style:font-face style:name="OpenSymbol" svg:font-family="OpenSymbol" style:font-charset="x-symbol"/>
            </office:font-face-decls>
            <office:styles>
            <draw:gradient draw:name="Gradient_20_1" draw:display-name="Gradient 1" draw:style="linear" draw:start-color="#ff0000" draw:end-color="#0000ff" \
            draw:start-intensity="100%" draw:end-intensity="100%" draw:angle="300" draw:border="0%"/>
            <draw:fill-image draw:name="Bitmap_20_1" draw:display-name="Bitmap 1" xlink:href="Pictures/texture.png" xlink:type="simple" xlink:show="embed" \
            xlink:actuate="onLoad"/>
            <draw:marker draw:name="Arrow" svg:viewBox="0 0 20 30" svg:d="M10 0l-10 30h20z"/>
            <draw:marker draw:name="Circle" svg:viewBox="0 0 1131 1131" svg:d="M462 1118l-102-29-102-51-93-72-72-93-51-102-29-102-13-105 13-102 29-106 51-102 72-89 93-72 102-50 102-34 106-9 101 9 106 34 98 50 93 72 72 89 51 102 29 106 13 102-13 105-29 102-51 102-72 93-93 72-98 51-106 29-101 13z"/>
            <draw:stroke-dash draw:name="Fine_20_Dashed" draw:display-name="Fine Dashed" draw:style="rect" draw:dots1="1" draw:dots1-length="0.508cm" \
            draw:dots2="1" draw:dots2-length="0.508cm" draw:distance="0.508cm"/>
            <style:default-style style:family="graphic">
            <style:graphic-properties svg:stroke-color="#3465a4" draw:fill-color="#729fcf" fo:wrap-option="no-wrap"/>
            <style:paragraph-properties style:text-autospace="ideograph-alpha" style:punctuation-wrap="simple" style:line-break="strict" \
            style:writing-mode="lr-tb" style:font-independent-line-spacing="false"><style:tab-stops/></style:paragraph-properties>
            <style:text-properties style:use-window-font-color="true" loext:opacity="0%" fo:font-family="&apos;Liberation Serif&apos;" \
            style:font-family-generic="roman" style:font-pitch="variable" fo:font-size="24pt" fo:language="en" fo:country="US" \
            style:font-size-asian="24pt" style:font-size-complex="24pt"/>
            </style:default-style>
            <style:style style:name="standard" style:family="graphic">
            <style:graphic-properties draw:stroke="solid" svg:stroke-width="0cm" svg:stroke-color="#3465a4" draw:marker-start-width="0.2cm" \
            draw:marker-start-center="false" draw:marker-end-width="0.2cm" draw:marker-end-center="false" draw:fill="solid" draw:fill-color="#729fcf" \
            draw:textarea-horizontal-align="justify" fo:padding-top="0.125cm" fo:padding-bottom="0.125cm" fo:padding-left="0.25cm" \
            fo:padding-right="0.25cm" draw:shadow="hidden" draw:shadow-offset-x="0.2cm" draw:shadow-offset-y="0.2cm" draw:shadow-color="#808080"/>
            <style:paragraph-properties fo:margin-left="0cm" fo:margin-right="0cm" fo:margin-top="0cm" fo:margin-bottom="0cm" fo:line-height="100%" \
            fo:text-indent="0cm"/>
            <style:text-properties fo:font-variant="normal" fo:text-transform="none" style:use-window-font-color="true" loext:opacity="0%" \
            style:text-line-through-style="none" style:font-name="Liberation Sans" fo:font-size="18pt" fo:font-style="normal" fo:text-shadow="none" \
            style:text-underline-style="none" fo:font-weight="normal" style:font-size-asian="18pt" style:font-size-complex="18pt"/>
            </style:style>
            <style:style style:name="objectwithoutfill" style:family="graphic" style:parent-style-name="standard">
            <style:graphic-properties draw:fill="none"/>
            </style:style>
            <style:presentation-page-layout style:name="AL1T0">
            <presentation:placeholder presentation:object="title" svg:x="2.058cm" svg:y="1.743cm" svg:width="23.91cm" svg:height="3.507cm"/>
            <presentation:placeholder presentation:object="subtitle" svg:x="2.058cm" svg:y="5.838cm" svg:width="23.91cm" svg:height="8.13cm"/>
            </style:presentation-page-layout>
            <style:presentation-page-layout style:name="AL2T1">
            <presentation:placeholder presentation:object="title" svg:x="2.058cm" svg:y="1.743cm" svg:width="23.91cm" svg:height="3.507cm"/>
            <presentation:placeholder presentation:object="outline" svg:x="2.058cm" svg:y="5.838cm" svg:width="23.91cm" svg:height="8.13cm"/>
            </style:presentation-page-layout>
            <style:presentation-page-layout style:name="AL3T19">
            <presentation:placeholder presentation:object="title" svg:x="2.058cm" svg:y="1.743cm" svg:width="23.91cm" svg:height="3.507cm"/>
            </style:presentation-page-layout>
            <style:style style:name="Default-background" style:family="presentation">
            <style:graphic-properties draw:stroke="none" draw:fill="none"/>
            <style:text-properties style:letter-kerning="true"/>
            </style:style>
            <style:style style:name="Default-backgroundobjects" style:family="presentation">
            <style:graphic-properties draw:shadow="hidden" draw:shadow-offset-x="0.2cm" draw:shadow-offset-y="0.2cm" draw:shadow-color="#808080"/>
            <style:text-properties style:text-position="0% 100%" style:letter-kerning="true"/>
            </style:style>
            <style:style style:name="Default-notes" style:family="presentation">
            <style:graphic-properties draw:fill="none"/>
            <style:paragraph-properties fo:margin-left="0.6cm" fo:margin-right="0cm" fo:text-indent="-0.6cm"/>
            <style:text-properties style:font-name="Liberation Sans" fo:font-size="20pt" style:font-size-asian="20pt" style:font-size-complex="20pt"/>
            </style:style>
            <style:style style:name="Default-outline1" style:family="presentation">
            <style:graphic-properties draw:stroke="none" draw:fill="none" draw:auto-grow-height="false" fo:min-height="11.411cm">
            <text:list-style style:name="Default-outline1">\(outlineList)</text:list-style>
            </style:graphic-properties>
            <style:paragraph-properties fo:margin-left="0cm" fo:margin-right="0cm" fo:margin-top="0.5cm" fo:margin-bottom="0cm" fo:line-height="100%" \
            fo:text-indent="0cm"/>
            <style:text-properties fo:font-variant="normal" fo:text-transform="none" fo:color="#000000" style:text-line-through-style="none" \
            style:font-name="Liberation Sans" fo:font-size="32pt" fo:font-style="normal" style:text-underline-style="none" fo:font-weight="normal" \
            style:font-size-asian="32pt" style:font-size-complex="32pt"/>
            </style:style>
            \(outline)
            <style:style style:name="Default-subtitle" style:family="presentation">
            <style:graphic-properties draw:stroke="none" draw:fill="none" draw:textarea-vertical-align="middle"/>
            <style:paragraph-properties fo:margin-left="0cm" fo:margin-right="0cm" fo:margin-top="0cm" fo:margin-bottom="0cm" fo:line-height="100%" \
            fo:text-indent="0cm" fo:text-align="center"/>
            <style:text-properties fo:color="#000000" style:font-name="Liberation Sans" fo:font-size="32pt" fo:font-weight="normal" \
            style:font-size-asian="32pt" style:font-size-complex="32pt"/>
            </style:style>
            <style:style style:name="Default-title" style:family="presentation">
            <style:graphic-properties draw:stroke="none" draw:fill="none" draw:textarea-vertical-align="middle"/>
            <style:paragraph-properties fo:text-align="center"/>
            <style:text-properties fo:color="#000000" style:font-name="Liberation Sans" fo:font-size="44pt" fo:font-weight="normal" \
            style:font-size-asian="44pt" style:font-size-complex="44pt"/>
            </style:style>
            </office:styles>
            <office:automatic-styles>
            <style:page-layout style:name="PM0"><style:page-layout-properties fo:margin-top="0cm" fo:margin-bottom="0cm" fo:margin-left="0cm" \
            fo:margin-right="0cm" fo:page-width="21.001cm" fo:page-height="29.7cm" style:print-orientation="portrait"/></style:page-layout>
            <style:page-layout style:name="PM1"><style:page-layout-properties fo:margin-top="0cm" fo:margin-bottom="0cm" fo:margin-left="0cm" \
            fo:margin-right="0cm" fo:page-width="28cm" fo:page-height="15.75cm" style:print-orientation="landscape"/></style:page-layout>
            <style:style style:name="Mdp1" style:family="drawing-page">
            <style:drawing-page-properties draw:background-size="full" draw:fill="solid" draw:fill-color="#fffff0"/>
            </style:style>
            <style:style style:name="Mgr1" style:family="graphic" style:parent-style-name="standard">
            <style:graphic-properties draw:stroke="none" draw:fill-color="#18a303"/>
            </style:style>
            <style:style style:name="Mpr1" style:family="presentation" style:parent-style-name="Default-backgroundobjects">
            <style:graphic-properties draw:stroke="none" draw:fill="none" draw:auto-grow-height="false" fo:min-height="1.448cm"/>
            </style:style>
            <style:style style:name="MP1" style:family="paragraph"><style:text-properties fo:font-size="14pt"/></style:style>
            <style:style style:name="MP2" style:family="paragraph"><style:paragraph-properties fo:text-align="end"/>\
            <style:text-properties fo:font-size="14pt"/></style:style>
            </office:automatic-styles>
            <office:master-styles>
            <draw:layer-set><draw:layer draw:name="layout"/><draw:layer draw:name="background"/><draw:layer draw:name="backgroundobjects"/>\
            <draw:layer draw:name="controls"/><draw:layer draw:name="measurelines"/></draw:layer-set>
            <style:master-page style:name="Default" style:page-layout-name="PM1" draw:style-name="Mdp1">
            <loext:theme loext:name="Office Theme"><loext:theme-colors loext:name="LibreOffice">\
            <loext:color loext:name="dark1" loext:color="#000000"/><loext:color loext:name="light1" loext:color="#ffffff"/>\
            <loext:color loext:name="dark2" loext:color="#000000"/><loext:color loext:name="light2" loext:color="#ffffff"/>\
            <loext:color loext:name="accent1" loext:color="#18a303"/><loext:color loext:name="accent2" loext:color="#0369a3"/>\
            <loext:color loext:name="accent3" loext:color="#a33e03"/><loext:color loext:name="accent4" loext:color="#8e03a3"/>\
            <loext:color loext:name="accent5" loext:color="#c99c00"/><loext:color loext:name="accent6" loext:color="#c9211e"/>\
            <loext:color loext:name="hyperlink" loext:color="#0000ee"/><loext:color loext:name="followed-hyperlink" loext:color="#551a8b"/>\
            </loext:theme-colors></loext:theme>
            <draw:custom-shape draw:name="Stripe" draw:style-name="Mgr1" draw:layer="backgroundobjects" svg:width="28cm" svg:height="0.5cm" svg:x="0cm" \
            svg:y="15.25cm"><draw:enhanced-geometry svg:viewBox="0 0 21600 21600" draw:type="rectangle" draw:enhanced-path="M 0 0 L 21600 0 21600 21600 0 21600 0 0 Z N"/>\
            </draw:custom-shape>
            <draw:frame presentation:style-name="Default-title" draw:layer="backgroundobjects" svg:width="25.199cm" svg:height="2.629cm" svg:x="1.4cm" \
            svg:y="0.628cm" presentation:class="title" presentation:placeholder="true"><draw:text-box/></draw:frame>
            <draw:frame presentation:style-name="Default-outline1" draw:layer="backgroundobjects" svg:width="25.199cm" svg:height="9.134cm" svg:x="1.4cm" \
            svg:y="3.685cm" presentation:class="outline" presentation:placeholder="true"><draw:text-box/></draw:frame>
            <draw:frame presentation:style-name="Mpr1" draw:text-style-name="MP1" draw:layer="backgroundobjects" svg:width="6.523cm" svg:height="1.085cm" \
            svg:x="1.4cm" svg:y="14.348cm" presentation:class="date-time"><draw:text-box><text:p text:style-name="MP1"><presentation:date-time/></text:p>\
            </draw:text-box></draw:frame>
            <draw:frame presentation:style-name="Mpr1" draw:text-style-name="MP1" draw:layer="backgroundobjects" svg:width="8.875cm" svg:height="1.085cm" \
            svg:x="9.576cm" svg:y="14.348cm" presentation:class="footer"><draw:text-box><text:p text:style-name="MP1"><presentation:footer/></text:p>\
            </draw:text-box></draw:frame>
            <draw:frame presentation:style-name="Mpr1" draw:text-style-name="MP2" draw:layer="backgroundobjects" svg:width="6.523cm" svg:height="1.085cm" \
            svg:x="20.076cm" svg:y="14.348cm" presentation:class="page-number"><draw:text-box><text:p text:style-name="MP2">\
            <text:page-number>&lt;number&gt;</text:page-number></text:p></draw:text-box></draw:frame>
            <presentation:notes style:page-layout-name="PM0">
            <draw:page-thumbnail presentation:style-name="Default-title" draw:layer="backgroundobjects" svg:width="13.968cm" svg:height="7.857cm" \
            svg:x="3.517cm" svg:y="2.123cm" presentation:class="page"/>
            <draw:frame presentation:style-name="Default-notes" draw:layer="backgroundobjects" svg:width="17.271cm" svg:height="12.572cm" svg:x="1.866cm" \
            svg:y="10.887cm" presentation:class="notes" presentation:placeholder="true"><draw:text-box/></draw:frame>
            </presentation:notes>
            </style:master-page>
            </office:master-styles>
            </office:document-styles>
            """
    }

    static var content: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content \(namespaces)>
        <office:font-face-decls>
        <style:font-face style:name="Liberation Sans" svg:font-family="&apos;Liberation Sans&apos;" style:font-family-generic="roman" style:font-pitch="variable"/>
        </office:font-face-decls>
        <office:automatic-styles>
        <style:style style:name="dp1" style:family="drawing-page"><style:drawing-page-properties presentation:background-visible="true" \
        presentation:background-objects-visible="true" presentation:display-footer="false" presentation:display-page-number="false" \
        presentation:display-date-time="false"/></style:style>
        <style:style style:name="dp2" style:family="drawing-page"><style:drawing-page-properties presentation:background-visible="true" \
        presentation:background-objects-visible="true" presentation:display-footer="true" presentation:display-page-number="true" \
        presentation:display-date-time="true" smil:type="fade" smil:subtype="crossfade" presentation:transition-speed="medium"/></style:style>
        <style:style style:name="dp3" style:family="drawing-page"><style:drawing-page-properties presentation:background-visible="true" \
        presentation:background-objects-visible="true" presentation:visibility="hidden" smil:type="pushWipe" smil:subtype="fromLeft" \
        presentation:transition-speed="fast"/></style:style>
        <style:style style:name="dp4" style:family="drawing-page"><style:drawing-page-properties draw:fill="gradient" \
        draw:fill-gradient-name="Gradient_20_1" draw:background-size="full" presentation:background-visible="true" \
        presentation:background-objects-visible="false" smil:type="miscShapeWipe" smil:subtype="cornersOut" presentation:transition-speed="slow"/>\
        </style:style>
        <style:style style:name="gr1" style:family="graphic" style:parent-style-name="standard"><style:graphic-properties draw:stroke="solid" \
        svg:stroke-color="#ff0000" svg:stroke-width="0.1cm" draw:fill="solid" draw:fill-color="#ffff00" draw:textarea-horizontal-align="justify" \
        draw:textarea-vertical-align="middle" draw:auto-grow-height="false" fo:min-height="2cm" fo:min-width="3cm"/>\
        <style:paragraph-properties fo:text-align="center"/></style:style>
        <style:style style:name="gr2" style:family="graphic" style:parent-style-name="objectwithoutfill"><style:graphic-properties draw:stroke="dash" \
        draw:stroke-dash="Fine_20_Dashed" svg:stroke-width="0.05cm" svg:stroke-color="#000000" draw:marker-start="Circle" \
        draw:marker-start-width="0.3cm" draw:marker-start-center="true" draw:marker-end="Arrow" draw:marker-end-width="0.3cm"/></style:style>
        <style:style style:name="gr3" style:family="graphic" style:parent-style-name="objectwithoutfill"><style:graphic-properties draw:stroke="none" \
        fo:clip="rect(0cm, 0cm, 0cm, 0.635cm)" style:mirror="horizontal"/></style:style>
        <style:style style:name="gr4" style:family="graphic" style:parent-style-name="objectwithoutfill"><style:graphic-properties draw:stroke="none" \
        draw:auto-grow-height="true" fo:min-height="1cm" fo:wrap-option="wrap"/></style:style>
        <style:style style:name="gr5" style:family="graphic" style:parent-style-name="standard"><style:graphic-properties draw:fill="bitmap" \
        draw:fill-image-name="Bitmap_20_1" style:repeat="repeat" draw:opacity="60%"/></style:style>
        <style:style style:name="pr1" style:family="presentation" style:parent-style-name="Default-title"><style:graphic-properties \
        draw:fill-color="#ffffff" fo:min-height="3.507cm"/></style:style>
        <style:style style:name="pr2" style:family="presentation" style:parent-style-name="Default-subtitle"><style:graphic-properties \
        draw:fill-color="#ffffff" fo:min-height="8.13cm"/></style:style>
        <style:style style:name="pr3" style:family="presentation" style:parent-style-name="Default-outline1"><style:graphic-properties \
        draw:fill-color="#ffffff" fo:min-height="8.13cm"/></style:style>
        <style:style style:name="pr4" style:family="presentation" style:parent-style-name="Default-notes"><style:graphic-properties \
        draw:fill-color="#ffffff" fo:min-height="12.572cm"/></style:style>
        <style:style style:name="P1" style:family="paragraph"><style:paragraph-properties fo:text-align="center"/></style:style>
        <style:style style:name="P2" style:family="paragraph"><style:paragraph-properties fo:margin-left="0cm" fo:text-indent="0cm"/></style:style>
        <style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold" style:font-weight-asian="bold" \
        style:font-weight-complex="bold"/></style:style>
        <style:style style:name="T2" style:family="text"><style:text-properties fo:color="#c9211e" style:text-underline-style="solid" \
        style:text-underline-width="auto" style:text-underline-color="font-color"/></style:style>
        <style:style style:name="T3" style:family="text"><style:text-properties fo:font-style="italic" style:text-position="super 58%"/></style:style>
        <text:list-style style:name="L1">\(outlineList)</text:list-style>
        <text:list-style style:name="L2"><text:list-level-style-number text:level="1" style:num-suffix="." style:num-format="1">\
        <style:list-level-properties text:space-before="0.3cm" text:min-label-width="0.9cm"/>\
        <style:text-properties fo:font-family="Liberation Sans" style:use-window-font-color="true" fo:font-size="100%"/>\
        </text:list-level-style-number><text:list-level-style-number text:level="2" style:num-prefix="(" style:num-suffix=")" style:num-format="a" \
        text:start-value="2"><style:list-level-properties text:space-before="1.6cm" text:min-label-width="0.8cm"/></text:list-level-style-number>\
        </text:list-style>
        </office:automatic-styles>
        <office:body>
        <office:presentation>
        <presentation:footer-decl presentation:name="ftr1">Company confidential</presentation:footer-decl>
        <presentation:date-time-decl presentation:name="dtd1" presentation:source="current-date" style:data-style-name="D3"/>
        <draw:page draw:name="page1" draw:style-name="dp2" draw:master-page-name="Default" presentation:presentation-page-layout-name="AL1T0" \
        presentation:use-footer-name="ftr1" presentation:use-date-time-name="dtd1">
        <draw:frame presentation:style-name="pr1" draw:text-style-name="P1" draw:layer="layout" svg:width="23.91cm" svg:height="3.507cm" \
        svg:x="2.058cm" svg:y="1.743cm" presentation:class="title" presentation:user-transformed="true" draw:id="id1" xml:id="id1">\
        <draw:text-box><text:p>Welcome to <text:span text:style-name="T1">LibreOffice</text:span></text:p></draw:text-box></draw:frame>
        <draw:frame presentation:style-name="pr2" draw:text-style-name="P1" draw:layer="layout" svg:width="23.91cm" svg:height="8.13cm" \
        svg:x="2.058cm" svg:y="5.838cm" presentation:class="subtitle" presentation:user-transformed="true">\
        <draw:text-box><text:p>A subtitle</text:p></draw:text-box></draw:frame>
        <anim:par presentation:node-type="timing-root">\
        <anim:par smil:begin="page1.begin"><anim:transitionFilter smil:dur="2s" smil:type="fade" smil:subtype="crossfade"/></anim:par>\
        <anim:seq presentation:node-type="main-sequence"><anim:par smil:begin="next"><anim:par smil:begin="0s">\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="on-click" presentation:preset-class="entrance" \
        presentation:preset-id="ooo-entrance-appear"><anim:set smil:begin="0s" smil:dur="0.001s" smil:fill="hold" smil:targetElement="id1" \
        smil:attributeName="visibility" smil:to="visible"/></anim:par></anim:par></anim:par></anim:seq></anim:par>
        <presentation:notes draw:style-name="dp1">
        <draw:page-thumbnail draw:layer="layout" svg:width="13.968cm" svg:height="7.857cm" svg:x="3.517cm" svg:y="2.123cm" draw:page-number="1" \
        presentation:class="page"/>
        <draw:frame presentation:style-name="pr4" draw:layer="layout" svg:width="17.271cm" svg:height="12.572cm" svg:x="1.866cm" \
        svg:y="10.887cm" presentation:class="notes" presentation:user-transformed="true"><draw:text-box>\
        <text:p>Remember to <text:span text:style-name="T1">smile</text:span>.</text:p></draw:text-box></draw:frame>
        </presentation:notes>
        </draw:page>
        <draw:page draw:name="page2" draw:style-name="dp1" draw:master-page-name="Default" presentation:presentation-page-layout-name="AL2T1">
        <draw:frame presentation:style-name="pr1" draw:layer="layout" svg:width="23.91cm" svg:height="3.507cm" svg:x="2.058cm" svg:y="1.743cm" \
        presentation:class="title" presentation:user-transformed="true"><draw:text-box><text:p>Lists</text:p></draw:text-box></draw:frame>
        <draw:frame presentation:style-name="pr3" draw:layer="layout" svg:width="23.91cm" svg:height="8.13cm" svg:x="2.058cm" svg:y="5.838cm" \
        presentation:class="outline" presentation:user-transformed="true" draw:id="id2" xml:id="id2"><draw:text-box>\
        <text:list text:style-name="L1"><text:list-item><text:p text:id="id3" xml:id="id3">First   point <text:s text:c="2"/>spaced<text:tab/>tab</text:p>\
        </text:list-item><text:list-item><text:list><text:list-item><text:p text:id="id4" xml:id="id4">Second <text:span text:style-name="T2">\
        level</text:span><text:line-break/>new line</text:p></text:list-item></text:list></text:list-item>\
        <text:list-header><text:p text:style-name="P2">No bullet</text:p></text:list-header></text:list>\
        <text:list text:style-name="L2"><text:list-item><text:p>One</text:p></text:list-item><text:list-item><text:p>Two with \
        <text:a xlink:type="simple" xlink:href="https://www.libreoffice.org/">a link</text:a> and <text:a xlink:type="simple" \
        xlink:href="#page3">a jump</text:a></text:p></text:list-item><text:list-item><text:list><text:list-item><text:p>Sub <text:span \
        text:style-name="T3">b</text:span></text:p></text:list-item></text:list></text:list-item></text:list>\
        </draw:text-box></draw:frame>
        <anim:par presentation:node-type="timing-root"><anim:seq presentation:node-type="main-sequence">\
        <anim:par smil:begin="next"><anim:par smil:begin="0s">\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="on-click" presentation:preset-class="entrance" \
        presentation:preset-id="ooo-entrance-fade-in" presentation:group-id="1"><anim:set smil:begin="0s" smil:dur="0.001s" smil:fill="hold" \
        smil:targetElement="id3" smil:attributeName="visibility" smil:to="visible"/><anim:transitionFilter smil:dur="0.5s" smil:targetElement="id3" \
        smil:type="fade" smil:subtype="crossfade"/></anim:par></anim:par></anim:par>\
        <anim:par smil:begin="next"><anim:par smil:begin="0s">\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="on-click" presentation:preset-class="entrance" \
        presentation:preset-id="ooo-entrance-fade-in" presentation:group-id="1"><anim:set smil:begin="0s" smil:dur="0.001s" smil:fill="hold" \
        smil:targetElement="id4" smil:attributeName="visibility" smil:to="visible"/><anim:transitionFilter smil:dur="0.5s" smil:targetElement="id4" \
        smil:type="fade" smil:subtype="crossfade"/></anim:par></anim:par></anim:par>\
        </anim:seq></anim:par>
        <presentation:notes draw:style-name="dp1"><draw:page-thumbnail draw:layer="layout" svg:width="13.968cm" svg:height="7.857cm" svg:x="3.517cm" \
        svg:y="2.123cm" draw:page-number="2" presentation:class="page"/><draw:frame presentation:style-name="pr4" draw:layer="layout" \
        svg:width="17.271cm" svg:height="12.572cm" svg:x="1.866cm" svg:y="10.887cm" presentation:class="notes" presentation:placeholder="true">\
        <draw:text-box/></draw:frame></presentation:notes>
        </draw:page>
        <draw:page draw:name="page3" draw:style-name="dp3" draw:master-page-name="Default">
        <draw:custom-shape draw:name="Rounded" draw:style-name="gr1" draw:layer="layout" svg:width="4cm" svg:height="4cm" svg:x="1cm" svg:y="1cm" \
        draw:id="id5" xml:id="id5"><text:p>Native</text:p>\
        <draw:enhanced-geometry svg:viewBox="0 0 21600 21600" draw:type="round-rectangle" draw:modifiers="3600" \
        draw:enhanced-path="M ?f7 0 X 0 ?f8 L 0 ?f9 Y ?f7 21600 L ?f10 21600 X 21600 ?f9 L 21600 ?f8 Y ?f10 0 Z N" draw:text-areas="?f3 ?f4 ?f5 ?f6">\
        <draw:equation draw:name="f0" draw:formula="45"/><draw:equation draw:name="f1" draw:formula="$0 *sin(?f0 *(pi/180))"/>\
        <draw:equation draw:name="f2" draw:formula="?f1 *3163/7636"/><draw:equation draw:name="f3" draw:formula="left+?f2 "/>\
        <draw:equation draw:name="f4" draw:formula="top+?f2 "/><draw:equation draw:name="f5" draw:formula="right-?f2 "/>\
        <draw:equation draw:name="f6" draw:formula="bottom-?f2 "/><draw:equation draw:name="f7" draw:formula="left+$0 "/>\
        <draw:equation draw:name="f8" draw:formula="top+$0 "/><draw:equation draw:name="f9" draw:formula="bottom-$0 "/>\
        <draw:equation draw:name="f10" draw:formula="right-$0 "/>\
        <draw:handle draw:handle-position="$0 top" draw:handle-switched="true" draw:handle-range-x-minimum="0" draw:handle-range-x-maximum="10800"/>\
        </draw:enhanced-geometry></draw:custom-shape>
        <draw:custom-shape draw:name="Pill" draw:style-name="gr1" draw:layer="layout" svg:width="6cm" svg:height="2cm" svg:x="6cm" svg:y="1cm">\
        <draw:enhanced-geometry svg:viewBox="0 0 21600 21600" draw:type="round-rectangle" draw:modifiers="10800" \
        draw:enhanced-path="M ?f7 0 X 0 ?f8 L 0 ?f9 Y ?f7 21600 L ?f10 21600 X 21600 ?f9 L 21600 ?f8 Y ?f10 0 Z N">\
        <draw:equation draw:name="f7" draw:formula="left+$0 "/><draw:equation draw:name="f8" draw:formula="top+$0 "/>\
        <draw:equation draw:name="f9" draw:formula="bottom-$0 "/><draw:equation draw:name="f10" draw:formula="right-$0 "/>\
        </draw:enhanced-geometry></draw:custom-shape>
        <draw:custom-shape draw:name="From PowerPoint" draw:style-name="gr1" draw:layer="layout" svg:width="5cm" svg:height="2cm" \
        draw:transform="rotate (0.523598775598299) translate (13cm 3cm)"><draw:enhanced-geometry svg:viewBox="0 0 21600 21600" \
        draw:type="ooxml-wedgeRoundRectCallout" draw:modifiers="-20833 62500 16667" draw:enhanced-path="M 0 0 L 21600 0 21600 21600 0 21600 Z N"/>\
        </draw:custom-shape>
        <draw:custom-shape draw:name="Oval" draw:style-name="gr5" draw:layer="layout" svg:width="3cm" svg:height="2cm" svg:x="20cm" svg:y="1cm">\
        <draw:enhanced-geometry svg:viewBox="0 0 21600 21600" draw:type="ellipse" draw:mirror-vertical="true" \
        draw:enhanced-path="U 10800 10800 10800 10800 0 360 Z N"/></draw:custom-shape>
        <draw:custom-shape draw:name="Freeform" draw:style-name="gr1" draw:layer="layout" svg:width="3cm" svg:height="3cm" svg:x="24cm" svg:y="1cm">\
        <draw:enhanced-geometry svg:viewBox="0 0 100 100" draw:type="non-primitive" draw:text-areas="10 10 90 90" \
        draw:enhanced-path="M 0 100 L 50 0 100 100 Z N F M 0 50 L 100 50 N"/></draw:custom-shape>
        <draw:rect draw:name="Old rectangle" draw:style-name="gr1" draw:layer="layout" svg:width="4cm" svg:height="2cm" svg:x="1cm" svg:y="6cm" \
        draw:corner-radius="0.5cm"/>
        <draw:ellipse draw:name="Pie" draw:style-name="gr1" draw:layer="layout" svg:width="2cm" svg:height="2cm" svg:x="6cm" svg:y="6cm" \
        draw:kind="section" draw:start-angle="0" draw:end-angle="90"/>
        <draw:polygon draw:name="Triangle" draw:style-name="gr1" draw:layer="layout" svg:width="2cm" svg:height="2cm" svg:x="9cm" svg:y="6cm" \
        svg:viewBox="0 0 2000 2000" draw:points="1000,0 2000,2000 0,2000"/>
        <draw:path draw:name="Wave" draw:style-name="gr2" draw:layer="layout" svg:width="4cm" svg:height="1cm" svg:x="12cm" svg:y="6cm" \
        svg:viewBox="0 0 4000 1000" svg:d="M0 500c1000-1000 1000 1000 2000 0s1000-1000 2000 0"/>
        <draw:line draw:name="Arrow line" draw:style-name="gr2" draw:layer="layout" svg:x1="1cm" svg:y1="10cm" svg:x2="8cm" svg:y2="9cm"/>
        <draw:connector draw:name="Elbow" draw:style-name="gr2" draw:layer="layout" draw:type="standard" svg:x1="9cm" svg:y1="9cm" svg:x2="12cm" \
        svg:y2="11cm" svg:viewBox="0 0 3000 2000"/>
        <draw:g draw:name="Pair"><draw:custom-shape draw:style-name="gr1" svg:width="1cm" svg:height="1cm" svg:x="14cm" svg:y="9cm" \
        draw:id="id6" xml:id="id6"><draw:enhanced-geometry svg:viewBox="0 0 21600 21600" draw:type="ellipse"/></draw:custom-shape>\
        <draw:custom-shape draw:style-name="gr1" svg:width="1cm" svg:height="1cm" svg:x="15.5cm" svg:y="9cm"><draw:enhanced-geometry \
        svg:viewBox="0 0 21600 21600" draw:type="rectangle"/></draw:custom-shape></draw:g>
        <draw:frame draw:name="Photo" draw:style-name="gr3" draw:layer="layout" svg:width="2.286cm" svg:height="1.27cm" svg:x="17cm" svg:y="9cm">\
        <draw:image xlink:href="Pictures/photo.png" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad" draw:mime-type="image/png">\
        <text:p/></draw:image><svg:title>Photo</svg:title><svg:desc>Red and blue</svg:desc></draw:frame>
        <draw:frame draw:name="Text box" draw:style-name="gr4" draw:layer="layout" svg:width="6cm" svg:height="1cm" svg:x="20cm" svg:y="9cm">\
        <draw:text-box><text:p>Plain text box</text:p></draw:text-box></draw:frame>
        <draw:frame draw:name="Table" draw:layer="layout" svg:width="6cm" svg:height="2cm" svg:x="1cm" svg:y="12cm"><table:table/></draw:frame>
        <draw:frame draw:name="Chart" draw:layer="layout" svg:width="6cm" svg:height="2cm" svg:x="8cm" svg:y="12cm">\
        <draw:object xlink:href="./Object 1" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/></draw:frame>
        <draw:frame draw:name="Movie" draw:layer="layout" svg:width="6cm" svg:height="2cm" svg:x="15cm" svg:y="12cm">\
        <draw:plugin xlink:href="Media/movie.mp4" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad" draw:mime-type="video/mp4"/></draw:frame>
        <officeooo:annotation><dc:creator>Someone</dc:creator><text:p>A comment</text:p></officeooo:annotation>
        <anim:par presentation:node-type="timing-root"><anim:seq presentation:node-type="main-sequence">\
        <anim:par smil:begin="0s"><anim:par smil:begin="0s">\
        <anim:par smil:begin="0.5s" smil:fill="hold" presentation:node-type="after-previous" presentation:preset-class="entrance" \
        presentation:preset-id="ooo-entrance-fly-in" presentation:preset-sub-type="from-left"><anim:set smil:begin="0s" smil:dur="0.001s" \
        smil:fill="hold" smil:targetElement="id5" smil:attributeName="visibility" smil:to="visible"/><anim:animate smil:dur="1s" smil:fill="hold" \
        smil:targetElement="id5" smil:attributeName="x" smil:values="0-width/2;x" smil:keyTimes="0;1"/><anim:animate smil:dur="1s" smil:fill="hold" \
        smil:targetElement="id5" smil:attributeName="y" smil:values="y;y" smil:keyTimes="0;1"/></anim:par>\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="with-previous" presentation:preset-class="emphasis" \
        presentation:preset-id="ooo-emphasis-spin"><anim:animateTransform smil:dur="2s" smil:fill="hold" smil:targetElement="id6" \
        smil:attributeName="transform" smil:by="360" svg:type="rotate"/></anim:par></anim:par></anim:par>\
        <anim:par smil:begin="next"><anim:par smil:begin="0s">\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="on-click" presentation:preset-class="emphasis" \
        presentation:preset-id="ooo-emphasis-grow-and-shrink"><anim:animateTransform smil:dur="1s" smil:fill="hold" smil:targetElement="id5" \
        smil:attributeName="transform" smil:to="1.5,1.5" svg:type="scale"/></anim:par>\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="with-previous" presentation:preset-class="exit" \
        presentation:preset-id="ooo-exit-fly-out" presentation:preset-sub-type="from-bottom"><anim:animate smil:dur="0.75s" smil:fill="hold" \
        smil:targetElement="id5" smil:attributeName="y" smil:values="y;1+height/2" smil:keyTimes="0;1"/><anim:set smil:begin="0.749s" \
        smil:dur="0.001s" smil:fill="hold" smil:targetElement="id5" smil:attributeName="visibility" smil:to="hidden"/></anim:par>\
        <anim:par smil:begin="0s" smil:fill="hold" presentation:node-type="with-previous" presentation:preset-class="motion-path" \
        presentation:preset-id="ooo-motionpath-circle"><anim:animateMotion smil:dur="2s" smil:fill="hold" smil:targetElement="id6" \
        svg:path="M 0 0 L 0.1 0.1"/></anim:par></anim:par></anim:par>\
        </anim:seq></anim:par>
        </draw:page>
        <draw:page draw:name="page4" draw:style-name="dp4" draw:master-page-name="Default" presentation:presentation-page-layout-name="AL3T19">
        <draw:frame presentation:style-name="pr1" draw:layer="layout" svg:width="23.91cm" svg:height="3.507cm" svg:x="2.058cm" svg:y="1.743cm" \
        presentation:class="title" presentation:user-transformed="true"><draw:text-box><text:p>Title only</text:p></draw:text-box></draw:frame>
        </draw:page>
        </office:presentation>
        </office:body>
        </office:document-content>
        """
    }

    static let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">
        <manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>
        <manifest:file-entry manifest:full-path="Object 1/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.chart"/>
        <manifest:file-entry manifest:full-path="Pictures/photo.png" manifest:media-type="image/png"/>
        <manifest:file-entry manifest:full-path="Pictures/texture.png" manifest:media-type="image/png"/>
        <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
        <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """

    static let meta = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" office:version="1.3"><office:meta>\
        <meta:generator>LibreOffice/7.6.4.1$MacOSX_AARCH64 LibreOffice_project/e19e193f88cd6c0525a17fb7a176ed8e6a3e2aa1</meta:generator>\
        <dc:title>Made in Impress</dc:title></office:meta></office:document-meta>
        """

    static func package(content: String = ODPLibreOfficeFixture.content, styles: String = ODPLibreOfficeFixture.styles) throws -> Data {
        try ODPTestPackage.zip([
            ("content.xml", Data(content.utf8)), ("styles.xml", Data(styles.utf8)), ("meta.xml", Data(meta.utf8)),
            ("Pictures/photo.png", image), ("Pictures/texture.png", texture), ("Object 1/content.xml", Data("<x/>".utf8)),
            ("META-INF/manifest.xml", Data(manifest.utf8)),
        ])
    }
}
