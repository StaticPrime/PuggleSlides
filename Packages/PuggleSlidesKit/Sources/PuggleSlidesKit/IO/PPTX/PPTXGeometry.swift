import Foundation

/// DrawingML shape geometry: presets with their adjust values, and custom paths with guide formulas.
enum PPTXGeometry {
    /// Every DrawingML preset (ST_ShapeType). Anything else would make Office repair the file.
    static let presetNames: Set<String> = [
        "line", "lineInv", "triangle", "rtTriangle", "rect", "diamond", "parallelogram", "trapezoid", "nonIsoscelesTrapezoid",
        "pentagon", "hexagon", "heptagon", "octagon", "decagon", "dodecagon", "star4", "star5", "star6", "star7", "star8", "star10",
        "star12", "star16", "star24", "star32", "roundRect", "round1Rect", "round2SameRect", "round2DiagRect", "snipRoundRect",
        "snip1Rect", "snip2SameRect", "snip2DiagRect", "plaque", "ellipse", "teardrop", "homePlate", "chevron", "pieWedge", "pie",
        "blockArc", "donut", "noSmoking", "rightArrow", "leftArrow", "upArrow", "downArrow", "stripedRightArrow", "notchedRightArrow",
        "bentUpArrow", "leftRightArrow", "upDownArrow", "leftUpArrow", "leftRightUpArrow", "quadArrow", "leftArrowCallout",
        "rightArrowCallout", "upArrowCallout", "downArrowCallout", "leftRightArrowCallout", "upDownArrowCallout", "quadArrowCallout",
        "bentArrow", "uturnArrow", "circularArrow", "leftCircularArrow", "leftRightCircularArrow", "curvedRightArrow",
        "curvedLeftArrow", "curvedUpArrow", "curvedDownArrow", "swooshArrow", "cube", "can", "lightningBolt", "heart", "sun", "moon",
        "smileyFace", "irregularSeal1", "irregularSeal2", "foldedCorner", "bevel", "frame", "halfFrame", "corner", "diagStripe",
        "chord", "arc", "leftBracket", "rightBracket", "leftBrace", "rightBrace", "bracketPair", "bracePair", "straightConnector1",
        "bentConnector2", "bentConnector3", "bentConnector4", "bentConnector5", "curvedConnector2", "curvedConnector3",
        "curvedConnector4", "curvedConnector5", "callout1", "callout2", "callout3", "accentCallout1", "accentCallout2",
        "accentCallout3", "borderCallout1", "borderCallout2", "borderCallout3", "accentBorderCallout1", "accentBorderCallout2",
        "accentBorderCallout3", "wedgeRectCallout", "wedgeRoundRectCallout", "wedgeEllipseCallout", "cloudCallout", "cloud", "ribbon",
        "ribbon2", "ellipseRibbon", "ellipseRibbon2", "leftRightRibbon", "verticalScroll", "horizontalScroll", "wave", "doubleWave",
        "plus", "flowChartProcess", "flowChartDecision", "flowChartInputOutput", "flowChartPredefinedProcess",
        "flowChartInternalStorage", "flowChartDocument", "flowChartMultidocument", "flowChartTerminator", "flowChartPreparation",
        "flowChartManualInput", "flowChartManualOperation", "flowChartConnector", "flowChartPunchedCard", "flowChartPunchedTape",
        "flowChartSummingJunction", "flowChartOr", "flowChartCollate", "flowChartSort", "flowChartExtract", "flowChartMerge",
        "flowChartOfflineStorage", "flowChartOnlineStorage", "flowChartMagneticTape", "flowChartMagneticDisk",
        "flowChartMagneticDrum", "flowChartDisplay", "flowChartDelay", "flowChartAlternateProcess", "flowChartOffpageConnector",
        "actionButtonBlank", "actionButtonHome", "actionButtonHelp", "actionButtonInformation", "actionButtonForwardNext",
        "actionButtonBackPrevious", "actionButtonEnd", "actionButtonBeginning", "actionButtonReturn", "actionButtonDocument",
        "actionButtonSound", "actionButtonMovie", "gear6", "gear9", "funnel", "mathPlus", "mathMinus", "mathMultiply", "mathDivide",
        "mathEqual", "mathNotEqual", "cornerTabs", "squareTabs", "plaqueTabs", "chartX", "chartStar", "chartPlus",
    ]

    /// Each preset's adjust values when a file states none (from ECMA-376's presetShapeDefinitions.xml).
    /// Values equal to these aren't written: Office leaves them out, and some importers mishandle them.
    static let defaultAdjustments: [String: [String: Double]] = [
        "accentBorderCallout1": ["adj1": 18750, "adj2": -8333, "adj3": 112500, "adj4": -38333],
        "accentBorderCallout2": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 112500, "adj6": -46667],
        "accentBorderCallout3": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 100000, "adj6": -16667, "adj7": 112963, "adj8": -8333],
        "accentCallout1": ["adj1": 18750, "adj2": -8333, "adj3": 112500, "adj4": -38333],
        "accentCallout2": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 112500, "adj6": -46667],
        "accentCallout3": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 100000, "adj6": -16667, "adj7": 112963, "adj8": -8333],
        "arc": ["adj1": 16200000, "adj2": 0],
        "bentArrow": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 43750],
        "bentConnector3": ["adj1": 50000],
        "bentConnector4": ["adj1": 50000, "adj2": 50000],
        "bentConnector5": ["adj1": 50000, "adj2": 50000, "adj3": 50000],
        "bentUpArrow": ["adj1": 25000, "adj2": 25000, "adj3": 25000],
        "bevel": ["adj": 12500],
        "blockArc": ["adj1": 10800000, "adj2": 0, "adj3": 25000],
        "borderCallout1": ["adj1": 18750, "adj2": -8333, "adj3": 112500, "adj4": -38333],
        "borderCallout2": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 112500, "adj6": -46667],
        "borderCallout3": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 100000, "adj6": -16667, "adj7": 112963, "adj8": -8333],
        "bracePair": ["adj": 8333],
        "bracketPair": ["adj": 16667],
        "callout1": ["adj1": 18750, "adj2": -8333, "adj3": 112500, "adj4": -38333],
        "callout2": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 112500, "adj6": -46667],
        "callout3": ["adj1": 18750, "adj2": -8333, "adj3": 18750, "adj4": -16667, "adj5": 100000, "adj6": -16667, "adj7": 112963, "adj8": -8333],
        "can": ["adj": 25000],
        "chevron": ["adj": 50000],
        "chord": ["adj1": 2700000, "adj2": 16200000],
        "circularArrow": ["adj1": 12500, "adj2": 1142319, "adj3": 20457681, "adj4": 10800000, "adj5": 12500],
        "cloudCallout": ["adj1": -20833, "adj2": 62500],
        "corner": ["adj1": 50000, "adj2": 50000],
        "cube": ["adj": 25000],
        "curvedConnector3": ["adj1": 50000],
        "curvedConnector4": ["adj1": 50000, "adj2": 50000],
        "curvedConnector5": ["adj1": 50000, "adj2": 50000, "adj3": 50000],
        "curvedDownArrow": ["adj1": 25000, "adj2": 50000, "adj3": 25000],
        "curvedLeftArrow": ["adj1": 25000, "adj2": 50000, "adj3": 25000],
        "curvedRightArrow": ["adj1": 25000, "adj2": 50000, "adj3": 25000],
        "curvedUpArrow": ["adj1": 25000, "adj2": 50000, "adj3": 25000],
        "decagon": ["vf": 105146],
        "diagStripe": ["adj": 50000],
        "donut": ["adj": 25000],
        "doubleWave": ["adj1": 6250, "adj2": 0],
        "downArrow": ["adj1": 50000, "adj2": 50000],
        "downArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 64977],
        "ellipseRibbon": ["adj1": 25000, "adj2": 50000, "adj3": 12500],
        "ellipseRibbon2": ["adj1": 25000, "adj2": 50000, "adj3": 12500],
        "foldedCorner": ["adj": 16667],
        "frame": ["adj1": 12500],
        "gear6": ["adj1": 15000, "adj2": 3526],
        "gear9": ["adj1": 10000, "adj2": 1763],
        "halfFrame": ["adj1": 33333, "adj2": 33333],
        "heptagon": ["hf": 102572, "vf": 105210],
        "hexagon": ["adj": 25000, "vf": 115470],
        "homePlate": ["adj": 50000],
        "horizontalScroll": ["adj": 12500],
        "leftArrow": ["adj1": 50000, "adj2": 50000],
        "leftArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 64977],
        "leftBrace": ["adj1": 8333, "adj2": 50000],
        "leftBracket": ["adj": 8333],
        "leftCircularArrow": ["adj1": 12500, "adj2": -1142319, "adj3": 1142319, "adj4": 10800000, "adj5": 12500],
        "leftRightArrow": ["adj1": 50000, "adj2": 50000],
        "leftRightArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 48123],
        "leftRightCircularArrow": ["adj1": 12500, "adj2": 1142319, "adj3": 20457681, "adj4": 11942319, "adj5": 12500],
        "leftRightRibbon": ["adj1": 50000, "adj2": 50000, "adj3": 16667],
        "leftRightUpArrow": ["adj1": 25000, "adj2": 25000, "adj3": 25000],
        "leftUpArrow": ["adj1": 25000, "adj2": 25000, "adj3": 25000],
        "mathDivide": ["adj1": 23520, "adj2": 5880, "adj3": 11760],
        "mathEqual": ["adj1": 23520, "adj2": 11760],
        "mathMinus": ["adj1": 23520],
        "mathMultiply": ["adj1": 23520],
        "mathNotEqual": ["adj1": 23520, "adj2": 6600000, "adj3": 11760],
        "mathPlus": ["adj1": 23520],
        "moon": ["adj": 50000],
        "nonIsoscelesTrapezoid": ["adj1": 25000, "adj2": 25000],
        "noSmoking": ["adj": 18750],
        "notchedRightArrow": ["adj1": 50000, "adj2": 50000],
        "octagon": ["adj": 29289],
        "parallelogram": ["adj": 25000],
        "pentagon": ["hf": 105146, "vf": 110557],
        "pie": ["adj1": 0, "adj2": 16200000],
        "plaque": ["adj": 16667],
        "plus": ["adj": 25000],
        "quadArrow": ["adj1": 22500, "adj2": 22500, "adj3": 22500],
        "quadArrowCallout": ["adj1": 18515, "adj2": 18515, "adj3": 18515, "adj4": 48123],
        "ribbon": ["adj1": 16667, "adj2": 50000],
        "ribbon2": ["adj1": 16667, "adj2": 50000],
        "rightArrow": ["adj1": 50000, "adj2": 50000],
        "rightArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 64977],
        "rightBrace": ["adj1": 8333, "adj2": 50000],
        "rightBracket": ["adj": 8333],
        "round1Rect": ["adj": 16667],
        "round2DiagRect": ["adj1": 16667, "adj2": 0],
        "round2SameRect": ["adj1": 16667, "adj2": 0],
        "roundRect": ["adj": 16667],
        "smileyFace": ["adj": 4653],
        "snip1Rect": ["adj": 16667],
        "snip2DiagRect": ["adj1": 0, "adj2": 16667],
        "snip2SameRect": ["adj1": 16667, "adj2": 0],
        "snipRoundRect": ["adj1": 16667, "adj2": 16667],
        "star10": ["adj": 42533, "hf": 105146],
        "star12": ["adj": 37500],
        "star16": ["adj": 37500],
        "star24": ["adj": 37500],
        "star32": ["adj": 37500],
        "star4": ["adj": 12500],
        "star5": ["adj": 19098, "hf": 105146, "vf": 110557],
        "star6": ["adj": 28868, "hf": 115470],
        "star7": ["adj": 34601, "hf": 102572, "vf": 105210],
        "star8": ["adj": 37500],
        "stripedRightArrow": ["adj1": 50000, "adj2": 50000],
        "sun": ["adj": 25000],
        "swooshArrow": ["adj1": 25000, "adj2": 16667],
        "teardrop": ["adj": 100000],
        "trapezoid": ["adj": 25000],
        "triangle": ["adj": 50000],
        "upArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 64977],
        "upDownArrow": ["adj1": 50000, "adj2": 50000],
        "upDownArrowCallout": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 48123],
        "uturnArrow": ["adj1": 25000, "adj2": 25000, "adj3": 25000, "adj4": 43750, "adj5": 75000],
        "verticalScroll": ["adj": 12500],
        "wave": ["adj1": 12500, "adj2": 0],
        "wedgeEllipseCallout": ["adj1": -20833, "adj2": 62500],
        "wedgeRectCallout": ["adj1": -20833, "adj2": 62500],
        "wedgeRoundRectCallout": ["adj1": -20833, "adj2": 62500, "adj3": 16667],
    ]

    static let maxPaths = 256
    static let maxCommands = 200_000
    static let maxGuides = 2_000

    // MARK: Reading

    /// The geometry in a shape's `spPr`, or nil when it states none. `size` is the shape's size in points, when known.
    static func read(_ spPr: XNode?, size: SlideSize?) -> ShapeGeometry? {
        guard let spPr else { return nil }
        if let preset = spPr.child("prstGeom") {
            let name = preset["prst"] ?? "rect"
            var adjustments: [String: Double] = [:]
            for guide in preset.child("avLst")?.children("gd") ?? [] {
                guard let key = guide["name"], let value = adjustValue(guide["fmla"]) else { continue }
                adjustments[key] = value
            }
            return .preset(name.isEmpty ? "rect" : name, adjustments: adjustments)
        }
        if let node = spPr.child("custGeom") {
            return customGeometry(node, size: size)
        }
        return nil
    }

    /// "val 16667" → 16667.
    static func adjustValue(_ formula: String?) -> Double? {
        guard let formula else { return nil }
        let parts = formula.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0] == "val" else { return nil }
        return PPTXValue.double(String(parts[1]))
    }

    private static func customGeometry(_ node: XNode, size: SlideSize?) -> ShapeGeometry {
        // Guides are measured in the shape's own EMU space; without a size, a nominal one keeps fractions right.
        var width = (size?.width ?? 0) * EMU.perPoint, height = (size?.height ?? 0) * EMU.perPoint
        if !(width > 0) || !width.isFinite { width = 1_000_000 }
        if !(height > 0) || !height.isFinite { height = 1_000_000 }
        var guides = Guides(width: width, height: height)
        var guideCount = 0
        for list in [node.child("avLst"), node.child("gdLst")] {
            for guide in list?.children("gd") ?? [] {
                guideCount += 1
                guard guideCount <= maxGuides, let name = guide["name"], let formula = guide["fmla"] else { continue }
                guides.define(name, formula)
            }
        }

        var paths: [CustomPath] = []
        var commandCount = 0
        for path in node.child("pathLst")?.children("path").prefix(maxPaths) ?? [] {
            let pathWidth = max(0, PPTXValue.emu(path["w"]) ?? 0), pathHeight = max(0, PPTXValue.emu(path["h"]) ?? 0)
            // Without a path size, coordinates are EMU in the shape's space; the model keeps those in points.
            let xScale = pathWidth > 0 ? 1 : 1 / EMU.perPoint, yScale = pathHeight > 0 ? 1 : 1 / EMU.perPoint
            func point(_ node: XNode?) -> SlidePoint {
                SlidePoint(x: guides.value(node?["x"]) * xScale, y: guides.value(node?["y"]) * yScale)
            }
            var commands: [PathCommand] = []
            for command in path.children {
                guard commandCount < maxCommands else { break }
                let points = command.children("pt")
                switch command.name {
                case "moveTo":
                    commands.append(.move(point(points.first)))
                case "lnTo":
                    commands.append(.line(point(points.first)))
                case "arcTo":
                    commands.append(.arc(widthRadius: guides.value(command["wR"]) * xScale, heightRadius: guides.value(command["hR"]) * yScale,
                                         startAngle: guides.value(command["stAng"]) / 60_000, sweepAngle: guides.value(command["swAng"]) / 60_000))
                case "quadBezTo":
                    guard points.count >= 2 else { continue }
                    commands.append(.quadratic(control: point(points[0]), end: point(points[1])))
                case "cubicBezTo":
                    guard points.count >= 3 else { continue }
                    commands.append(.cubic(control1: point(points[0]), control2: point(points[1]), end: point(points[2])))
                case "close":
                    commands.append(.close)
                default:
                    continue
                }
                commandCount += 1
            }
            paths.append(CustomPath(width: pathWidth, height: pathHeight, fill: PathFillMode(rawValue: path["fill"] ?? "norm") ?? .normal,
                                    stroke: PPTXValue.bool(path["stroke"]) ?? true, commands: commands))
        }

        var textRect: TextInsetFractions?
        if let rect = node.child("rect") {
            let left = guides.value(rect["l"]), top = guides.value(rect["t"])
            let right = guides.value(rect["r"]), bottom = guides.value(rect["b"])
            let fractions = TextInsetFractions(left: left / width, top: top / height, right: (width - right) / width, bottom: (height - bottom) / height)
            let values = [fractions.left, fractions.top, fractions.right, fractions.bottom]
            if values.allSatisfy(\.isFinite), values.contains(where: { abs($0) > 1e-9 }) { textRect = fractions }
        }
        return .custom(CustomGeometry(paths: paths, textRect: textRect))
    }

    /// DrawingML's shape guides: built-in names for the shape's size, and formulas defined in order.
    struct Guides {
        private var values: [String: Double]

        init(width w: Double, height h: Double) {
            let ss = min(w, h), ls = max(w, h)
            values = ["w": w, "h": h, "l": 0, "t": 0, "r": w, "b": h, "hc": w / 2, "vc": h / 2, "ss": ss, "ls": ls,
                      "cd2": 10_800_000, "cd4": 5_400_000, "cd8": 2_700_000, "3cd4": 16_200_000, "3cd8": 8_100_000,
                      "5cd8": 13_500_000, "7cd8": 18_900_000]
            for divisor in [2, 3, 4, 5, 6, 8, 10, 12, 16, 32] {
                values["wd\(divisor)"] = w / Double(divisor)
                values["hd\(divisor)"] = h / Double(divisor)
                values["ssd\(divisor)"] = ss / Double(divisor)
            }
        }

        /// A number, or the value of a guide; anything unknown is 0.
        func value(_ token: String?) -> Double {
            guard let token else { return 0 }
            if let number = PPTXValue.double(token) { return number }
            return values[token] ?? 0
        }

        mutating func define(_ name: String, _ formula: String) {
            let parts = formula.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let operation = parts.first else { return }
            let x = parts.count > 1 ? value(parts[1]) : 0
            let y = parts.count > 2 ? value(parts[2]) : 0
            let z = parts.count > 3 ? value(parts[3]) : 0
            let radians = Double.pi / 180 / 60_000
            let result: Double = switch operation {
            case "val": x
            case "*/": z == 0 ? 0 : x * y / z
            case "+-": x + y - z
            case "+/": z == 0 ? 0 : (x + y) / z
            case "?:": x > 0 ? y : z
            case "abs": abs(x)
            case "at2": atan2(y, x) / radians
            case "cat2": x * cos(atan2(z, y))
            case "sat2": x * sin(atan2(z, y))
            case "cos": x * cos(y * radians)
            case "sin": x * sin(y * radians)
            case "tan": x * tan(y * radians)
            case "max": max(x, y)
            case "min": min(x, y)
            case "mod": (x * x + y * y + z * z).squareRoot()
            case "pin": y < x ? x : (y > z ? z : y)
            case "sqrt": x > 0 ? x.squareRoot() : 0
            default: 0
            }
            values[name] = result.isFinite ? result : 0
        }
    }

    // MARK: Writing

    /// A preset name Office accepts.
    static func validPreset(_ name: String) -> String {
        presetNames.contains(name) ? name : "rect"
    }
}

extension XMLWriter {
    /// `prstGeom` or `custGeom` for `geometry`. `frame` is the shape's size in points, when it has its own.
    mutating func geometry(_ geometry: ShapeGeometry, frame: SlideSize?) {
        switch geometry {
        case .preset(let name, let adjustments):
            let preset = PPTXGeometry.validPreset(name)
            let defaults = PPTXGeometry.defaultAdjustments[preset] ?? [:]
            // Guide names are tokens; values equal to the preset's defaults are left out, as Office does.
            let written = adjustments.keys.sorted().compactMap { key -> (String, Int)? in
                guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), let value = adjustments[key] else { return nil }
                let rounded = PPTXValue.clamped(value, -2_000_000_000...2_000_000_000)
                return defaults[key] == Double(rounded) ? nil : (key, rounded)
            }
            raw("<a:prstGeom")
            attribute("prst", preset)
            guard !written.isEmpty else {
                raw("><a:avLst/></a:prstGeom>")
                return
            }
            raw("><a:avLst>")
            for (key, value) in written {
                raw("<a:gd")
                attribute("name", key)
                attribute("fmla", "val \(value)")
                raw("/>")
            }
            raw("</a:avLst></a:prstGeom>")
        case .custom(let custom):
            customGeometry(custom, frame: frame)
        }
    }

    private mutating func customGeometry(_ geometry: CustomGeometry, frame: SlideSize?) {
        raw("<a:custGeom><a:avLst/>")
        if let text = geometry.textRect {
            func scaled(_ fraction: Double) -> Int { PPTXValue.clamped(fraction * 1_000_000, -100_000_000...100_000_000) }
            raw("<a:gdLst>")
            raw("<a:gd name=\"textLeft\" fmla=\"*/ w \(scaled(text.left)) 1000000\"/>")
            raw("<a:gd name=\"textTop\" fmla=\"*/ h \(scaled(text.top)) 1000000\"/>")
            raw("<a:gd name=\"textRight\" fmla=\"*/ w \(scaled(1 - text.right)) 1000000\"/>")
            raw("<a:gd name=\"textBottom\" fmla=\"*/ h \(scaled(1 - text.bottom)) 1000000\"/>")
            raw("</a:gdLst><a:ahLst/><a:cxnLst/><a:rect l=\"textLeft\" t=\"textTop\" r=\"textRight\" b=\"textBottom\"/>")
        } else {
            raw("<a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"l\" t=\"t\" r=\"r\" b=\"b\"/>")
        }
        raw("<a:pathLst>")
        for path in geometry.paths { customPath(path, frame: frame) }
        raw("</a:pathLst></a:custGeom>")
    }

    /// One path, in the shape's own EMU space where its size is known, as PowerPoint writes freeforms (some
    /// importers ignore a path's size and read coordinates as EMU). Otherwise coordinates stay in the path's
    /// space, at a finer scale when they have fractions, since they must be whole numbers; a dimension of 0
    /// (the shape's own size, in points) is written in EMU.
    private mutating func customPath(_ path: CustomPath, frame: SlideSize?) {
        var numbers: [Double] = [path.width, path.height]
        for command in path.commands {
            switch command {
            case .move(let point), .line(let point): numbers += [point.x, point.y]
            case .quadratic(let control, let end): numbers += [control.x, control.y, end.x, end.y]
            case .cubic(let control1, let control2, let end): numbers += [control1.x, control1.y, control2.x, control2.y, end.x, end.y]
            case .arc(let widthRadius, let heightRadius, _, _): numbers += [widthRadius, heightRadius]
            case .close: break
            }
        }
        let whole = numbers.allSatisfy { $0.isFinite && abs($0 - $0.rounded()) < 1e-6 }
        let refine: Double = whole ? 1 : 1000
        let limit = -27_273_042_316_900...27_273_042_316_900
        /// The scale from the path's space to the written one, and the written size, for one dimension.
        func axis(_ size: Double, frame points: Double?) -> (scale: Double, size: Int?) {
            let size = size > 0 && size.isFinite ? size : 0
            let frameEMU = points.map { PPTXValue.clamped($0 * EMU.perPoint, 0...27_273_042_316_900) } ?? 0
            if frameEMU > 0 { return (size > 0 ? Double(frameEMU) / size : EMU.perPoint, frameEMU) }
            if size > 0 { return (refine, PPTXValue.clamped(size * refine, limit)) }
            return (EMU.perPoint, nil)
        }
        let (xScale, width) = axis(path.width, frame: frame.map { abs($0.width) })
        let (yScale, height) = axis(path.height, frame: frame.map { abs($0.height) })
        func x(_ value: Double) -> Int { PPTXValue.clamped(value * xScale, limit) }
        func y(_ value: Double) -> Int { PPTXValue.clamped(value * yScale, limit) }
        func point(_ point: SlidePoint) -> String { "<a:pt x=\"\(x(point.x))\" y=\"\(y(point.y))\"/>" }

        raw("<a:path")
        if let width { attribute("w", width) }
        if let height { attribute("h", height) }
        if path.fill != .normal { attribute("fill", path.fill.rawValue) }
        if !path.stroke { raw(" stroke=\"0\"") }
        raw(">")
        for command in path.commands {
            switch command {
            case .move(let target): raw("<a:moveTo>\(point(target))</a:moveTo>")
            case .line(let target): raw("<a:lnTo>\(point(target))</a:lnTo>")
            case .quadratic(let control, let end): raw("<a:quadBezTo>\(point(control))\(point(end))</a:quadBezTo>")
            case .cubic(let control1, let control2, let end): raw("<a:cubicBezTo>\(point(control1))\(point(control2))\(point(end))</a:cubicBezTo>")
            case .arc(let widthRadius, let heightRadius, let start, let sweep):
                let angles = -2_000_000_000...2_000_000_000
                raw("<a:arcTo wR=\"\(x(widthRadius))\" hR=\"\(y(heightRadius))\" stAng=\"\(PPTXValue.clamped(start * 60_000, angles))\" "
                    + "swAng=\"\(PPTXValue.clamped(sweep * 60_000, angles))\"/>")
            case .close: raw("<a:close/>")
            }
        }
        raw("</a:path>")
    }
}
