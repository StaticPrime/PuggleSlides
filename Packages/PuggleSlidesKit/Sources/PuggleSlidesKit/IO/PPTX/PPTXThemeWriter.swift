import Foundation

/// Writes theme parts: a theme's colors and fonts, with Office's standard formatting styles, which the schema
/// requires (three each of fills, lines, effects and background fills).
enum PPTXThemeWriter {
    static func part(name: String, colors: ColorScheme, fonts: FontScheme) -> Data {
        var xml = XMLWriter(reservingCapacity: 8 * 1024)
        xml.raw("<a:theme xmlns:a=\"\(PPTXNamespace.drawing)\"")
        xml.attribute("name", name)
        xml.raw("><a:themeElements><a:clrScheme")
        xml.attribute("name", colors.name.isEmpty ? name : colors.name)
        xml.raw(">")
        for slot in ThemeColorSlot.allCases {
            xml.raw("<a:\(slot.rawValue)><a:srgbClr val=\"\(colors[slot].hex)\"/></a:\(slot.rawValue)>")
        }
        xml.raw("</a:clrScheme><a:fontScheme")
        xml.attribute("name", fonts.name.isEmpty ? name : fonts.name)
        xml.raw(">")
        for (tag, face) in [("a:majorFont", fonts.major), ("a:minorFont", fonts.minor)] {
            xml.raw("<\(tag)><a:latin")
            xml.attribute("typeface", face.isEmpty ? "Arial" : face)
            xml.raw("/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></\(tag)>")
        }
        xml.raw("</a:fontScheme>")
        xml.raw(formatScheme)
        xml.raw("</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>")
        return xml.data
    }

    /// Office's standard formatting styles (as in PowerPoint's Office theme).
    static let formatScheme = """
        <a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0"><a:schemeClr val="phClr"><a:lumMod val="110000"/>\
        <a:satMod val="105000"/><a:tint val="67000"/></a:schemeClr></a:gs><a:gs pos="50000"><a:schemeClr val="phClr">\
        <a:lumMod val="105000"/><a:satMod val="103000"/><a:tint val="73000"/></a:schemeClr></a:gs><a:gs pos="100000">\
        <a:schemeClr val="phClr"><a:lumMod val="105000"/><a:satMod val="109000"/><a:tint val="81000"/></a:schemeClr></a:gs>\
        </a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill><a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0">\
        <a:schemeClr val="phClr"><a:satMod val="103000"/><a:lumMod val="102000"/><a:tint val="94000"/></a:schemeClr></a:gs>\
        <a:gs pos="50000"><a:schemeClr val="phClr"><a:satMod val="110000"/><a:lumMod val="100000"/><a:shade val="100000"/>\
        </a:schemeClr></a:gs><a:gs pos="100000"><a:schemeClr val="phClr"><a:lumMod val="99000"/><a:satMod val="120000"/>\
        <a:shade val="78000"/></a:schemeClr></a:gs></a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill></a:fillStyleLst>\
        <a:lnStyleLst><a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill>\
        <a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="19050" cap="flat"\
         cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/>\
        </a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/>\
        </a:effectStyle><a:effectStyle><a:effectLst><a:outerShdw blurRad="57150" dist="19050" dir="5400000" algn="ctr"\
         rotWithShape="0"><a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr></a:outerShdw></a:effectLst></a:effectStyle>\
        </a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill>\
        <a:schemeClr val="phClr"><a:tint val="95000"/><a:satMod val="170000"/></a:schemeClr></a:solidFill>\
        <a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="93000"/><a:satMod val="150000"/>\
        <a:shade val="98000"/><a:lumMod val="102000"/></a:schemeClr></a:gs><a:gs pos="50000"><a:schemeClr val="phClr">\
        <a:tint val="98000"/><a:satMod val="130000"/><a:shade val="90000"/><a:lumMod val="103000"/></a:schemeClr></a:gs>\
        <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="63000"/><a:satMod val="120000"/></a:schemeClr></a:gs></a:gsLst>\
        <a:lin ang="5400000" scaled="0"/></a:gradFill></a:bgFillStyleLst></a:fmtScheme>
        """
}
