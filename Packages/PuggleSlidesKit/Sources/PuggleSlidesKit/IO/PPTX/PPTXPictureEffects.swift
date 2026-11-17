import Foundation

/// Picture adjustments (transparency, brightness, contrast) and recolors as DrawingML blip effects:
/// `alphaModFix`, `lum`, `grayscl` and `duotone`, which PowerPoint, Keynote and LibreOffice all draw.
enum PPTXPictureEffects {
    /// Recolors are duotones from the color the darkest shade becomes to the color the lightest becomes.
    static func write(_ recolor: ImageRecolor, into xml: inout XMLWriter) {
        let ends: (dark: ColorRef, light: ColorRef)
        switch recolor {
        case .grayscale:
            xml.raw("<a:grayscl/>")
            return
        case .light(let slot): ends = (ColorRef(theme: slot), .white)
        case .dark(let slot): ends = (.black, ColorRef(theme: slot))
        case .negative: ends = (.white, .black)
        case .sepia: ends = (ColorRef(ImageRecolor.sepiaDark), ColorRef(ImageRecolor.sepiaLight))
        case .duotone(let dark, let light): ends = (dark, light)
        }
        xml.raw("<a:duotone>")
        xml.color(ends.dark)
        xml.color(ends.light)
        xml.raw("</a:duotone>")
    }

    /// The adjustments a `blip`'s effects make. Effects without a counterpart here (blur, bi-level, color
    /// changes) are left out; PowerPoint 2010's picture corrections are already in the image it saves.
    static func adjustments(_ blip: XNode?, colors: PPTXColorReader) -> ImageAdjustments {
        guard let blip else { return .none }
        var adjustments = ImageAdjustments()
        for effect in blip.children {
            switch effect.name {
            case "alphaModFix":
                // The opacity, in thousandths of a percent (all of it when left out). Taking the integer from 100000
                // before dividing gives back exactly the transparency that was written: 66700 is 0.333, not 0.33299….
                let transparency: Double
                if let amount = PPTXValue.double(effect["amt"]) {
                    transparency = (100_000 - amount) / 100_000
                } else if let opacity = PPTXValue.fraction(effect["amt"]) {
                    transparency = 1 - opacity
                } else {
                    transparency = 0
                }
                adjustments.transparency = min(max(transparency, 0), 1)
            case "lum":
                adjustments.brightness = min(max(PPTXValue.fraction(effect["bright"]) ?? 0, -1), 1)
                adjustments.contrast = min(max(PPTXValue.fraction(effect["contrast"]) ?? 0, -1), 1)
            case "grayscl":
                adjustments.recolor = .grayscale
            case "duotone":
                let ends = effect.children.compactMap { PPTXColorReader.elementNames.contains($0.name) ? colors.color($0) : nil }
                guard ends.count == 2 else { continue }
                adjustments.recolor = recolor(dark: ends[0], light: ends[1])
            default:
                continue
            }
        }
        return adjustments
    }

    /// The recolors from a duotone's two ends; anything else stays a duotone of those colors.
    static func recolor(dark: ColorRef, light: ColorRef) -> ImageRecolor {
        func isPlain(_ color: ColorRef) -> Bool { !color.hasAdjustments && color.alpha == nil }
        guard isPlain(dark), isPlain(light) else { return .duotone(dark, light) }
        if let slot = dark.themeSlot, ImageRecolor.schemeSlots.contains(slot), light.rgb == .white { return .light(slot) }
        if let slot = light.themeSlot, ImageRecolor.schemeSlots.contains(slot), dark.rgb == .black { return .dark(slot) }
        switch (dark.rgb, light.rgb) {
        case (RGBColor.white?, RGBColor.black?): return .negative
        case (RGBColor.black?, RGBColor.white?): return .grayscale
        case (ImageRecolor.sepiaDark?, ImageRecolor.sepiaLight?): return .sepia
        default: return .duotone(dark, light)
        }
    }
}

extension PPTXPartWriter {
    /// `a:blip` with the picture's adjustments, in the order PuggleSlides applies them: brightness and contrast, then
    /// the recolor, then transparency.
    mutating func blip(_ relationship: String, adjustments: ImageAdjustments) {
        xml.raw("<a:blip r:embed=\"\(relationship)\"")
        let brightness = PPTXValue.clamped(adjustments.brightness * 100_000, -100_000...100_000)
        let contrast = PPTXValue.clamped(adjustments.contrast * 100_000, -100_000...100_000)
        let opacity = PPTXValue.clamped((1 - adjustments.transparency) * 100_000, 0...100_000)
        guard brightness != 0 || contrast != 0 || adjustments.recolor != nil || opacity < 100_000 else {
            xml.raw("/>")
            return
        }
        xml.raw(">")
        if brightness != 0 || contrast != 0 {
            xml.raw("<a:lum")
            if brightness != 0 { xml.attribute("bright", brightness) }
            if contrast != 0 { xml.attribute("contrast", contrast) }
            xml.raw("/>")
        }
        if let recolor = adjustments.recolor { PPTXPictureEffects.write(recolor, into: &xml) }
        if opacity < 100_000 { xml.raw("<a:alphaModFix amt=\"\(opacity)\"/>") }
        xml.raw("</a:blip>")
    }
}
