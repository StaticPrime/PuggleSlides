import CoreGraphics
import Foundation

/// Shape geometry in OpenDocument: `draw:enhanced-geometry` types, paths and text areas, and the line ends and
/// dash patterns of strokes.
enum ODPGeometry {
    // MARK: Preset names

    /// LibreOffice's own shape types for DrawingML presets that have one. Presets without one are written as
    /// "ooxml-" types, as LibreOffice names the shapes it imports from PowerPoint files.
    static let libreOfficeTypes: [String: String] = [
        "rect": "rectangle", "roundRect": "round-rectangle", "ellipse": "ellipse", "triangle": "isosceles-triangle",
        "rtTriangle": "right-triangle", "diamond": "diamond", "parallelogram": "parallelogram", "pentagon": "pentagon",
        "hexagon": "hexagon", "octagon": "octagon", "plus": "cross", "star4": "star4", "star5": "star5", "star6": "star6",
        "star8": "star8", "star12": "star12", "star24": "star24", "rightArrow": "right-arrow", "leftArrow": "left-arrow",
        "upArrow": "up-arrow", "downArrow": "down-arrow", "leftRightArrow": "left-right-arrow", "upDownArrow": "up-down-arrow",
        "quadArrow": "quad-arrow", "notchedRightArrow": "notched-right-arrow", "stripedRightArrow": "striped-right-arrow",
        "homePlate": "pentagon-right", "chevron": "chevron", "cube": "cube", "can": "can", "donut": "ring", "smileyFace": "smiley",
        "sun": "sun", "moon": "moon", "lightningBolt": "lightning", "heart": "heart", "noSmoking": "forbidden", "blockArc": "block-arc",
        "foldedCorner": "paper", "frame": "frame", "bevel": "quad-bevel", "bracketPair": "bracket-pair", "bracePair": "brace-pair",
        "leftBracket": "left-bracket", "rightBracket": "right-bracket", "leftBrace": "left-brace", "rightBrace": "right-brace",
        "irregularSeal1": "bang", "verticalScroll": "vertical-scroll", "horizontalScroll": "horizontal-scroll",
        "circularArrow": "circular-arrow", "wedgeRectCallout": "rectangular-callout", "wedgeRoundRectCallout": "round-rectangular-callout",
        "wedgeEllipseCallout": "round-callout", "cloudCallout": "cloud-callout", "rightArrowCallout": "right-arrow-callout",
        "leftArrowCallout": "left-arrow-callout", "upArrowCallout": "up-arrow-callout", "downArrowCallout": "down-arrow-callout",
        "leftRightArrowCallout": "left-right-arrow-callout", "upDownArrowCallout": "up-down-arrow-callout",
        "quadArrowCallout": "quad-arrow-callout", "flowChartProcess": "flowchart-process",
        "flowChartAlternateProcess": "flowchart-alternate-process", "flowChartDecision": "flowchart-decision",
        "flowChartInputOutput": "flowchart-data", "flowChartPredefinedProcess": "flowchart-predefined-process",
        "flowChartInternalStorage": "flowchart-internal-storage", "flowChartDocument": "flowchart-document",
        "flowChartMultidocument": "flowchart-multidocument", "flowChartTerminator": "flowchart-terminator",
        "flowChartPreparation": "flowchart-preparation", "flowChartManualInput": "flowchart-manual-input",
        "flowChartManualOperation": "flowchart-manual-operation", "flowChartConnector": "flowchart-connector",
        "flowChartOffpageConnector": "flowchart-off-page-connector", "flowChartPunchedCard": "flowchart-card",
        "flowChartPunchedTape": "flowchart-punched-tape", "flowChartSummingJunction": "flowchart-summing-junction",
        "flowChartOr": "flowchart-or", "flowChartCollate": "flowchart-collate", "flowChartSort": "flowchart-sort",
        "flowChartExtract": "flowchart-extract", "flowChartMerge": "flowchart-merge", "flowChartOnlineStorage": "flowchart-stored-data",
        "flowChartDelay": "flowchart-delay", "flowChartMagneticTape": "flowchart-sequential-access",
        "flowChartMagneticDisk": "flowchart-magnetic-disk", "flowChartMagneticDrum": "flowchart-direct-access-storage",
        "flowChartDisplay": "flowchart-display",
    ]

    /// Presets by LibreOffice type name, including names LibreOffice uses that PuggleSlides doesn't write.
    static let presetsByType: [String: String] = {
        var result: [String: String] = [:]
        for (preset, type) in libreOfficeTypes { result[type] = preset }
        result["circle"] = "ellipse"
        result["square"] = "rect"
        return result
    }()

    private static let knownPresets = Set(PresetGeometry.presetNames)

    /// The order a preset's adjust values take in `draw:modifiers`: adj, adj1 … adjN, then hf and vf, as in the
    /// DrawingML definitions and LibreOffice's "ooxml-" shapes.
    static func adjustNames(_ preset: String) -> [String] {
        PresetGeometry.defaultAdjustments(preset).keys.sorted { a, b in
            func rank(_ name: String) -> (Int, Int, String) {
                if name == "adj" { return (0, 0, name) }
                if name.hasPrefix("adj"), let number = Int(name.dropFirst(3)) { return (1, number, name) }
                if name == "hf" { return (2, 0, name) }
                if name == "vf" { return (3, 0, name) }
                return (4, 0, name)
            }
            return rank(a) < rank(b)
        }
    }

    /// The `draw:type` and `draw:modifiers` for a preset: LibreOffice's own type when its adjust values are the
    /// defaults, else the "ooxml-" type with every adjust value in order.
    static func shapeType(_ preset: String, adjustments: [String: Double]) -> (type: String, modifiers: String?) {
        let name = knownPresets.contains(preset) ? preset : "rect"
        let defaults = PresetGeometry.defaultAdjustments(name)
        let isDefault = adjustments.allSatisfy { key, value in defaults[key].map { abs($0 - value) < 0.5 } ?? true }
        if isDefault, let type = libreOfficeTypes[name] { return (type, nil) }
        let names = adjustNames(name)
        guard !names.isEmpty else { return ("ooxml-" + name, nil) }
        let values = names.map { key in ODFFormat.number((adjustments[key] ?? defaults[key] ?? 0).rounded(), decimals: 0) }
        return ("ooxml-" + name, values.joined(separator: " "))
    }

    /// The preset a `draw:type` names, with its adjust values from `draw:modifiers` for "ooxml-" types.
    static func preset(type: String, modifiers: String?) -> (name: String, adjustments: [String: Double], exact: Bool)? {
        if type.hasPrefix("ooxml-") {
            let name = String(type.dropFirst(6))
            guard knownPresets.contains(name) else { return nil }
            var adjustments: [String: Double] = [:]
            let values = (modifiers ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { ODFValue.double(String($0)) }
            for (key, value) in zip(adjustNames(name), values) where abs(value) < 1e9 { adjustments[key] = value.rounded() }
            return (name, adjustments, true)
        }
        if let name = presetsByType[type] { return (name, [:], false) }
        return nil
    }

    // MARK: Writing paths

    /// An enhanced geometry's view box and path for outlines drawn in a frame of `size` points: coordinates are
    /// hundredths of a point.
    struct EnhancedPath {
        var viewBox: (width: Int, height: Int)
        var path: String
        var textArea: String
    }

    static func viewBoxSize(_ size: SlideSize) -> (width: Int, height: Int, scaleX: Double, scaleY: Double) {
        func clamped(_ value: Double) -> Double { value.isFinite ? min(abs(value), 20_000_000) : 0 }
        let width = clamped(size.width), height = clamped(size.height)
        let boxWidth = max(1, Int((width * 100).rounded()))
        let boxHeight = max(1, Int((height * 100).rounded()))
        return (boxWidth, boxHeight, width > 0 ? Double(boxWidth) / width : 100, height > 0 ? Double(boxHeight) / height : 100)
    }

    /// The outline of `geometry` evaluated in its frame, as an enhanced path any reader draws the same way.
    static func enhancedPath(_ geometry: ShapeGeometry, size: SlideSize) -> EnhancedPath {
        let box = viewBoxSize(size)
        let rect = CGRect(x: 0, y: 0, width: abs(size.width), height: abs(size.height))
        var path = ""
        for part in PresetGeometry.paths(for: geometry, in: rect) {
            var flags = ""
            switch part.fill {
            case .none: flags += "F "
            case .darken: flags += "H "
            case .darkenLess: flags += "I "
            case .lighten: flags += "J "
            case .lightenLess: flags += "K "
            case .normal: break
            }
            if !part.stroke { flags += "S " }
            var commands = ""
            var current = CGPoint.zero
            part.path.applyWithBlock { element in
                let points = element.pointee.points
                func point(_ p: CGPoint) -> String {
                    ODFFormat.number(Double(p.x) * box.scaleX, decimals: 2) + " " + ODFFormat.number(Double(p.y) * box.scaleY, decimals: 2)
                }
                switch element.pointee.type {
                case .moveToPoint:
                    commands += "M " + point(points[0]) + " "
                    current = points[0]
                case .addLineToPoint:
                    commands += "L " + point(points[0]) + " "
                    current = points[0]
                case .addQuadCurveToPoint:
                    // As a cubic, which every reader knows.
                    let c1 = CGPoint(x: current.x + 2 / 3 * (points[0].x - current.x), y: current.y + 2 / 3 * (points[0].y - current.y))
                    let c2 = CGPoint(x: points[1].x + 2 / 3 * (points[0].x - points[1].x), y: points[1].y + 2 / 3 * (points[0].y - points[1].y))
                    commands += "C " + point(c1) + " " + point(c2) + " " + point(points[1]) + " "
                    current = points[1]
                case .addCurveToPoint:
                    commands += "C " + point(points[0]) + " " + point(points[1]) + " " + point(points[2]) + " "
                    current = points[2]
                case .closeSubpath:
                    commands += "Z "
                @unknown default:
                    break
                }
            }
            guard !commands.isEmpty else { continue }
            path += flags + commands + "N "
        }
        let text = PresetGeometry.textRect(for: geometry, in: rect)
        let area = [text.minX * box.scaleX, text.minY * box.scaleY, text.maxX * box.scaleX, text.maxY * box.scaleY]
            .map { ODFFormat.number(Double($0), decimals: 0) }.joined(separator: " ")
        return EnhancedPath(viewBox: (box.width, box.height), path: path.trimmingCharacters(in: .whitespaces), textArea: area)
    }

    // MARK: Reading paths

    static let maxCommands = 100_000
    static let maxEquations = 2_000

    /// Evaluates an enhanced geometry's path into the model's paths, in its view box's own space.
    struct EnhancedGeometryReader {
        var viewBox = CGRect(x: 0, y: 0, width: 21600, height: 21600)
        var modifiers: [Double] = []
        var equations: [String: String] = [:]
        /// The shape's size in hundredths of a millimeter, for "logwidth" and "logheight".
        var logicalSize = CGSize(width: 21600, height: 21600)
        var stretch = CGPoint.zero
        private var cache: [String: Double] = [:]
        private var evaluating: Set<String> = []

        init(node: ODFNode, size: SlideSize) {
            if let box = node["svg:viewBox"] {
                let values = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { ODFValue.double(String($0)) }
                if values.count == 4, values[2] > 0, values[3] > 0 { viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) }
            }
            modifiers = (node["draw:modifiers"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { ODFValue.double(String($0)) }
            for equation in node.children("draw:equation").prefix(ODPGeometry.maxEquations) {
                if let name = equation["draw:name"], let formula = equation["draw:formula"] { equations[name] = formula }
            }
            logicalSize = CGSize(width: max(0, size.width) * 2540 / 72, height: max(0, size.height) * 2540 / 72)
            stretch = CGPoint(x: ODFValue.double(node["draw:path-stretchpoint-x"]) ?? 0, y: ODFValue.double(node["draw:path-stretchpoint-y"]) ?? 0)
        }

        /// A path parameter or formula operand: a number, "?fN", "$N" or a named value.
        mutating func value(_ token: Substring) -> Double {
            if let number = Double(token), number.isFinite { return number }
            if token.hasPrefix("?") { return equation(String(token.dropFirst())) }
            if token.hasPrefix("$") { return Int(token.dropFirst()).flatMap { modifiers.indices.contains($0) ? modifiers[$0] : nil } ?? 0 }
            switch token {
            case "pi": return .pi
            case "left": return Double(viewBox.minX)
            case "top": return Double(viewBox.minY)
            case "right": return Double(viewBox.maxX)
            case "bottom": return Double(viewBox.maxY)
            case "width": return Double(viewBox.width)
            case "height": return Double(viewBox.height)
            case "logwidth": return Double(logicalSize.width)
            case "logheight": return Double(logicalSize.height)
            case "xstretch": return Double(stretch.x)
            case "ystretch": return Double(stretch.y)
            case "hasstroke", "hasfill": return 1
            default: return 0
            }
        }

        mutating func equation(_ name: String) -> Double {
            if let known = cache[name] { return known }
            guard let formula = equations[name], evaluating.count < 64, evaluating.insert(name).inserted else { return 0 }
            var parser = FormulaParser(text: formula)
            let result = parser.expression(&self)
            evaluating.remove(name)
            let value = result.isFinite ? result : 0
            cache[name] = value
            return value
        }

        /// The paths, one per stretch ending in "N", with coordinates relative to the view box's corner.
        mutating func paths(_ text: String) -> [CustomPath] {
            let tokens = Self.tokens(text)
            var paths: [CustomPath] = []
            var commands: [PathCommand] = []
            var fill = PathFillMode.normal
            var stroke = true
            var current = CGPoint.zero
            var subpathStart = CGPoint.zero
            var command: Character = "M"
            var index = 0
            var quadrantX = true
            let origin = viewBox.origin

            func finish() {
                if !commands.isEmpty {
                    paths.append(CustomPath(width: Double(viewBox.width), height: Double(viewBox.height), fill: fill, stroke: stroke, commands: commands))
                }
                commands = []
                fill = .normal
                stroke = true
            }

            while index < tokens.count, commands.count < ODPGeometry.maxCommands {
                let token = tokens[index]
                if token.count == 1, let letter = token.first, letter.isLetter, Self.commandLetters.contains(letter) {
                    command = letter
                    index += 1
                    switch letter {
                    case "Z":
                        commands.append(.close)
                        current = subpathStart
                    case "N": finish()
                    case "F": fill = PathFillMode.none
                    case "S": stroke = false
                    case "H": fill = .darken
                    case "I": fill = .darkenLess
                    case "J": fill = .lighten
                    case "K": fill = .lightenLess
                    case "X": quadrantX = true
                    case "Y": quadrantX = false
                    default: break
                    }
                    continue
                }
                let arity: Int
                switch command {
                case "M", "L", "X", "Y": arity = 2
                case "C": arity = 6
                case "Q": arity = 4
                case "T", "U": arity = 6
                case "A", "B", "W", "V": arity = 8
                case "G": arity = 4
                default:
                    index += 1
                    continue
                }
                guard index + arity <= tokens.count else { break }
                let values = (0..<arity).map { value(tokens[index + $0]) }
                index += arity
                func point(_ i: Int) -> CGPoint { CGPoint(x: values[i] - Double(origin.x), y: values[i + 1] - Double(origin.y)) }
                func slide(_ p: CGPoint) -> SlidePoint { SlidePoint(p) }
                switch command {
                case "M":
                    let p = point(0)
                    commands.append(.move(slide(p)))
                    current = p
                    subpathStart = p
                    command = "L"
                case "L":
                    let p = point(0)
                    commands.append(.line(slide(p)))
                    current = p
                case "C":
                    let end = point(4)
                    commands.append(.cubic(control1: slide(point(0)), control2: slide(point(2)), end: slide(end)))
                    current = end
                case "Q":
                    let end = point(2)
                    commands.append(.quadratic(control: slide(point(0)), end: slide(end)))
                    current = end
                case "X", "Y":
                    let end = point(0)
                    let k = 0.552_284_75
                    let c1: CGPoint, c2: CGPoint
                    if quadrantX {
                        c1 = CGPoint(x: current.x + k * (end.x - current.x), y: current.y)
                        c2 = CGPoint(x: end.x, y: end.y - k * (end.y - current.y))
                    } else {
                        c1 = CGPoint(x: current.x, y: current.y + k * (end.y - current.y))
                        c2 = CGPoint(x: end.x - k * (end.x - current.x), y: end.y)
                    }
                    commands.append(.cubic(control1: slide(c1), control2: slide(c2), end: slide(end)))
                    current = end
                    quadrantX.toggle()
                case "G":
                    let widthRadius = values[0], heightRadius = values[1], start = values[2], sweep = values[3]
                    commands.append(.arc(widthRadius: widthRadius, heightRadius: heightRadius, startAngle: start, sweepAngle: sweep))
                    if widthRadius.isFinite, heightRadius.isFinite, start.isFinite, sweep.isFinite {
                        let a = abs(widthRadius), b = abs(heightRadius)
                        let t0 = ShapePathBuilder.parameter(a, b, start * .pi / 180)
                        let t1 = t0 + ShapePathBuilder.parameterSweep(a, b, start: start * .pi / 180, sweep: sweep * .pi / 180)
                        let center = CGPoint(x: current.x - a * cos(t0), y: current.y - b * sin(t0))
                        current = CGPoint(x: center.x + a * cos(t1), y: center.y + b * sin(t1))
                    }
                case "T", "U":
                    // Center, radii, and angles counterclockwise in degrees.
                    let center = point(0)
                    let rx = abs(values[2]), ry = abs(values[3])
                    var start = values[4], end = values[5]
                    let span = end - start
                    guard span.isFinite, abs(span) < 1e6 else { continue }
                    if span == 0 || abs(span.truncatingRemainder(dividingBy: 360)) < 1e-9 {
                        start = 0
                        end = 360
                    }
                    while end < start { end += 360 }
                    let from = CGPoint(x: center.x + rx * cos(-start * .pi / 180), y: center.y + ry * sin(-start * .pi / 180))
                    if command == "U" || commands.isEmpty { commands.append(.move(slide(from))) } else { commands.append(.line(slide(from))) }
                    current = Self.appendArc(center: center, rx: rx, ry: ry, from: -start * .pi / 180, to: -end * .pi / 180, into: &commands)
                    if command == "U" { subpathStart = from }
                case "A", "B", "W", "V":
                    let clockwise = command == "W" || command == "V"
                    let corner1 = point(0), corner2 = point(2)
                    let rect = CGRect(x: min(corner1.x, corner2.x), y: min(corner1.y, corner2.y),
                                      width: abs(corner2.x - corner1.x), height: abs(corner2.y - corner1.y))
                    let startRay = point(4), endRay = point(6)
                    guard rect.width > 0, rect.height > 0 else { continue }
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let rx = rect.width / 2, ry = rect.height / 2
                    let a0 = atan2((startRay.y - center.y) / ry, (startRay.x - center.x) / rx)
                    var a1 = atan2((endRay.y - center.y) / ry, (endRay.x - center.x) / rx)
                    if clockwise {
                        while a1 <= a0 { a1 += 2 * .pi }
                    } else {
                        while a1 >= a0 { a1 -= 2 * .pi }
                    }
                    let from = CGPoint(x: center.x + rx * cos(a0), y: center.y + ry * sin(a0))
                    if command == "B" || command == "V" || commands.isEmpty {
                        commands.append(.move(slide(from)))
                        subpathStart = from
                    } else {
                        commands.append(.line(slide(from)))
                    }
                    current = Self.appendArc(center: center, rx: rx, ry: ry, from: a0, to: a1, into: &commands)
                default:
                    break
                }
            }
            finish()
            return paths
        }

        static let commandLetters: Set<Character> = ["M", "L", "C", "Z", "N", "F", "S", "T", "U", "A", "B", "W", "V", "X", "Y", "Q", "G", "H", "I", "J", "K"]

        static func tokens(_ text: String) -> [Substring] {
            var result: [Substring] = []
            var start: String.Index?
            var index = text.startIndex
            func flush() {
                if let begin = start { result.append(text[begin..<index]) }
                start = nil
            }
            while index < text.endIndex {
                let character = text[index]
                if character == " " || character == "," || character == "\n" || character == "\t" || character == "\r" {
                    flush()
                } else if character.isLetter, commandLetters.contains(character), start == nil
                            || !(text[start!].isLetter || text[start!] == "?" || text[start!] == "$") {
                    flush()
                    result.append(text[index...index])
                } else if start == nil {
                    start = index
                }
                index = text.index(after: index)
            }
            flush()
            return result
        }

        /// Appends Béziers for the ellipse arc between two parameters (y down); returns the end point.
        static func appendArc(center: CGPoint, rx: Double, ry: Double, from: Double, to: Double, into commands: inout [PathCommand]) -> CGPoint {
            let sweep = to - from
            guard sweep.isFinite, rx.isFinite, ry.isFinite, center.x.isFinite, center.y.isFinite else { return center }
            let segments = max(1, Int(min(abs(sweep) / (.pi / 2) - 1e-9, 63).rounded(.up)))
            let step = sweep / Double(segments)
            let k = 4 / 3 * tan(step / 4)
            var t = from
            var end = CGPoint(x: center.x + rx * cos(from), y: center.y + ry * sin(from))
            for _ in 0..<segments {
                let t1 = t + step
                let start = CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
                end = CGPoint(x: center.x + rx * cos(t1), y: center.y + ry * sin(t1))
                let c1 = CGPoint(x: start.x - k * rx * sin(t), y: start.y + k * ry * cos(t))
                let c2 = CGPoint(x: end.x + k * rx * sin(t1), y: end.y - k * ry * cos(t1))
                commands.append(.cubic(control1: SlidePoint(c1), control2: SlidePoint(c2), end: SlidePoint(end)))
                t = t1
            }
            return end
        }

        /// The first text area, as fractions of the view box.
        mutating func textArea(_ text: String?) -> TextInsetFractions? {
            guard let text else { return nil }
            let tokens = Self.tokens(text)
            guard tokens.count >= 4, viewBox.width > 0, viewBox.height > 0 else { return nil }
            let left = value(tokens[0]), top = value(tokens[1]), right = value(tokens[2]), bottom = value(tokens[3])
            let fractions = TextInsetFractions(left: (left - Double(viewBox.minX)) / Double(viewBox.width),
                                               top: (top - Double(viewBox.minY)) / Double(viewBox.height),
                                               right: (Double(viewBox.maxX) - right) / Double(viewBox.width),
                                               bottom: (Double(viewBox.maxY) - bottom) / Double(viewBox.height))
            let values = [fractions.left, fractions.top, fractions.right, fractions.bottom]
            guard values.allSatisfy({ $0.isFinite && abs($0) < 100 }), values.contains(where: { abs($0) > 1e-6 }) else { return nil }
            return fractions
        }
    }

    /// `draw:formula` expressions: + - * /, parentheses, functions, named values and references.
    struct FormulaParser {
        let scalars: [Character]
        var position = 0
        var depth = 0

        init(text: String) {
            scalars = Array(text)
        }

        mutating func skipSpaces() {
            while position < scalars.count, scalars[position] == " " || scalars[position] == "\t" { position += 1 }
        }

        mutating func expression(_ context: inout EnhancedGeometryReader) -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { return 0 }
            var value = term(&context)
            while true {
                skipSpaces()
                guard position < scalars.count, scalars[position] == "+" || scalars[position] == "-" else { return value }
                let op = scalars[position]
                position += 1
                let rhs = term(&context)
                value = op == "+" ? value + rhs : value - rhs
            }
        }

        mutating func term(_ context: inout EnhancedGeometryReader) -> Double {
            var value = factor(&context)
            while true {
                skipSpaces()
                guard position < scalars.count, scalars[position] == "*" || scalars[position] == "/" else { return value }
                let op = scalars[position]
                position += 1
                let rhs = factor(&context)
                value = op == "*" ? value * rhs : (rhs == 0 ? 0 : value / rhs)
            }
        }

        mutating func factor(_ context: inout EnhancedGeometryReader) -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { return 0 }
            skipSpaces()
            guard position < scalars.count else { return 0 }
            let character = scalars[position]
            if character == "-" {
                position += 1
                return -factor(&context)
            }
            if character == "+" {
                position += 1
                return factor(&context)
            }
            if character == "(" {
                position += 1
                let value = expression(&context)
                skipSpaces()
                if position < scalars.count, scalars[position] == ")" { position += 1 }
                return value
            }
            let start = position
            while position < scalars.count {
                let c = scalars[position]
                if c.isLetter || c.isNumber || c == "." || c == "?" || c == "$" || c == "_" { position += 1 } else { break }
            }
            guard position > start else {
                position += 1
                return 0
            }
            let token = String(scalars[start..<position])
            skipSpaces()
            if position < scalars.count, scalars[position] == "(" {
                position += 1
                var arguments: [Double] = []
                while position < scalars.count {
                    arguments.append(expression(&context))
                    skipSpaces()
                    if position < scalars.count, scalars[position] == "," {
                        position += 1
                        continue
                    }
                    if position < scalars.count, scalars[position] == ")" { position += 1 }
                    break
                }
                func argument(_ index: Int) -> Double { arguments.indices.contains(index) ? arguments[index] : 0 }
                switch token {
                case "abs": return abs(argument(0))
                case "sqrt": return argument(0) > 0 ? argument(0).squareRoot() : 0
                case "sin": return sin(argument(0))
                case "cos": return cos(argument(0))
                case "tan": return tan(argument(0))
                case "atan": return atan(argument(0))
                case "atan2": return atan2(argument(0), argument(1))
                case "min": return min(argument(0), argument(1))
                case "max": return max(argument(0), argument(1))
                case "if": return argument(0) > 0 ? argument(1) : argument(2)
                default: return 0
                }
            }
            return context.value(Substring(token))
        }
    }

    // MARK: SVG paths

    /// Parses SVG path data (`svg:d`) into absolute commands; arcs become Béziers.
    static func svgPath(_ text: String) -> [PathCommand] {
        var commands: [PathCommand] = []
        var command: Character = " "
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuadControl: CGPoint?
        let characters = Array(text)
        var index = 0

        func readNumber() -> Double? {
            while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index].isNewline || characters[index] == "\t" {
                index += 1
            }
            let begin = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var seenDot = false
            while index < characters.count {
                let c = characters[index]
                if c.isNumber {
                    index += 1
                } else if c == ".", !seenDot {
                    seenDot = true
                    index += 1
                } else if c == "e" || c == "E" {
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
                } else {
                    break
                }
            }
            guard index > begin, let value = Double(String(characters[begin..<index])), value.isFinite else { return nil }
            return value
        }

        while index < characters.count, commands.count < maxCommands {
            let character = characters[index]
            if character.isLetter, character != "e", character != "E" {
                command = character
                index += 1
                if character == "Z" || character == "z" {
                    commands.append(.close)
                    current = start
                    lastControl = nil
                    lastQuadControl = nil
                }
                continue
            }
            if character == " " || character == "," || character.isNewline || character == "\t" {
                index += 1
                continue
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: base.x + x, y: base.y + y) }
            switch command.uppercased().first ?? " " {
            case "M":
                guard let x = readNumber(), let y = readNumber() else { return commands }
                current = p(x, y)
                start = current
                commands.append(.move(SlidePoint(current)))
                command = relative ? "l" : "L"
                lastControl = nil
                lastQuadControl = nil
            case "L":
                guard let x = readNumber(), let y = readNumber() else { return commands }
                current = p(x, y)
                commands.append(.line(SlidePoint(current)))
                lastControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = readNumber() else { return commands }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                commands.append(.line(SlidePoint(current)))
                lastControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = readNumber() else { return commands }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                commands.append(.line(SlidePoint(current)))
                lastControl = nil
                lastQuadControl = nil
            case "C":
                guard let x1 = readNumber(), let y1 = readNumber(), let x2 = readNumber(), let y2 = readNumber(),
                      let x = readNumber(), let y = readNumber() else { return commands }
                let c1 = p(x1, y1), c2 = p(x2, y2), end = p(x, y)
                commands.append(.cubic(control1: SlidePoint(c1), control2: SlidePoint(c2), end: SlidePoint(end)))
                current = end
                lastControl = c2
                lastQuadControl = nil
            case "S":
                guard let x2 = readNumber(), let y2 = readNumber(), let x = readNumber(), let y = readNumber() else { return commands }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = p(x2, y2), end = p(x, y)
                commands.append(.cubic(control1: SlidePoint(c1), control2: SlidePoint(c2), end: SlidePoint(end)))
                current = end
                lastControl = c2
                lastQuadControl = nil
            case "Q":
                guard let x1 = readNumber(), let y1 = readNumber(), let x = readNumber(), let y = readNumber() else { return commands }
                let control = p(x1, y1), end = p(x, y)
                commands.append(.quadratic(control: SlidePoint(control), end: SlidePoint(end)))
                current = end
                lastQuadControl = control
                lastControl = nil
            case "T":
                guard let x = readNumber(), let y = readNumber() else { return commands }
                let control = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = p(x, y)
                commands.append(.quadratic(control: SlidePoint(control), end: SlidePoint(end)))
                current = end
                lastQuadControl = control
                lastControl = nil
            case "A":
                guard let rxValue = readNumber(), let ryValue = readNumber(), let rotation = readNumber(), let large = readNumber(),
                      let sweep = readNumber(), let x = readNumber(), let y = readNumber() else { return commands }
                let end = p(x, y)
                appendSVGArc(from: current, to: end, rx: abs(rxValue), ry: abs(ryValue), rotation: rotation, large: large != 0, sweep: sweep != 0,
                             into: &commands)
                current = end
                lastControl = nil
                lastQuadControl = nil
            default:
                index += 1
            }
        }
        return commands
    }

    /// An SVG elliptical arc as Béziers (SVG's endpoint-to-center conversion).
    private static func appendSVGArc(from p0: CGPoint, to p1: CGPoint, rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool,
                                     into commands: inout [PathCommand]) {
        var rx = rx, ry = ry
        guard rx > 0, ry > 0, p0 != p1 else {
            commands.append(.line(SlidePoint(p1)))
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator > 0 ? (numerator / denominator).squareRoot() : 0
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let value = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return value.isFinite ? value : 0
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        guard delta.isFinite, theta.isFinite else {
            commands.append(.line(SlidePoint(p1)))
            return
        }
        let segments = max(1, Int(min(abs(delta) / (.pi / 2) - 1e-9, 63).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4 / 3 * tan(step / 4)
        func point(_ t: Double) -> CGPoint {
            let x = rx * cos(t), y = ry * sin(t)
            return CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y)
        }
        func derivative(_ t: Double) -> CGPoint {
            let x = -rx * sin(t), y = ry * cos(t)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        var t = theta
        for _ in 0..<segments {
            let t1 = t + step
            let a = point(t), b = point(t1), da = derivative(t), db = derivative(t1)
            commands.append(.cubic(control1: SlidePoint(x: a.x + k * da.x, y: a.y + k * da.y),
                                   control2: SlidePoint(x: b.x - k * db.x, y: b.y - k * db.y), end: SlidePoint(b)))
            t = t1
        }
    }

    // MARK: Comparing outlines

    /// Whether two geometries draw (nearly) the same outline in a frame: points along each lie within 2% of the
    /// frame's size of the other.
    static func outlinesMatch(_ a: ShapeGeometry, _ b: ShapeGeometry, size: SlideSize) -> Bool {
        let width = max(abs(size.width), 1), height = max(abs(size.height), 1)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let first = polylines(PresetGeometry.paths(for: a, in: rect).filter(\.stroke).map(\.path))
        let second = polylines(PresetGeometry.paths(for: b, in: rect).filter(\.stroke).map(\.path))
        guard !first.isEmpty, !second.isEmpty else { return first.isEmpty == second.isEmpty }
        let tolerance = 0.02 * max(width, height)
        return within(first, of: second, tolerance) && within(second, of: first, tolerance)
    }

    private static func polylines(_ paths: [CGPath]) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        for path in paths {
            var current: [CGPoint] = []
            var last = CGPoint.zero, start = CGPoint.zero
            path.applyWithBlock { element in
                let points = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint:
                    if current.count > 1 { result.append(current) }
                    current = [points[0]]
                    last = points[0]
                    start = points[0]
                case .addLineToPoint:
                    current.append(points[0])
                    last = points[0]
                case .addQuadCurveToPoint:
                    for step in 1...8 {
                        let t = CGFloat(step) / 8, u = 1 - t
                        current.append(CGPoint(x: u * u * last.x + 2 * u * t * points[0].x + t * t * points[1].x,
                                               y: u * u * last.y + 2 * u * t * points[0].y + t * t * points[1].y))
                    }
                    last = points[1]
                case .addCurveToPoint:
                    for step in 1...8 {
                        let t = CGFloat(step) / 8, u = 1 - t
                        let x = u * u * u * last.x + 3 * u * u * t * points[0].x + 3 * u * t * t * points[1].x + t * t * t * points[2].x
                        let y = u * u * u * last.y + 3 * u * u * t * points[0].y + 3 * u * t * t * points[1].y + t * t * t * points[2].y
                        current.append(CGPoint(x: x, y: y))
                    }
                    last = points[2]
                case .closeSubpath:
                    current.append(start)
                    last = start
                @unknown default:
                    break
                }
            }
            if current.count > 1 { result.append(current) }
        }
        return result
    }

    private static func within(_ lines: [[CGPoint]], of other: [[CGPoint]], _ tolerance: Double) -> Bool {
        for line in lines {
            for point in line {
                var best = Double.infinity
                for candidate in other {
                    for index in 1..<candidate.count {
                        best = min(best, distance(point, candidate[index - 1], candidate[index]))
                        if best <= tolerance { break }
                    }
                    if best <= tolerance { break }
                }
                if best > tolerance { return false }
            }
        }
        return true
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = dx * dx + dy * dy
        var t = length > 0 ? (Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / length : 0
        t = min(max(t, 0), 1)
        let x = Double(a.x) + t * dx - Double(p.x), y = Double(a.y) + t * dy - Double(p.y)
        return (x * x + y * y).squareRoot()
    }

    // MARK: Line ends and dashes

    /// The marker each line end is written as: LibreOffice's name for it and its outline. Outlined ends are rings,
    /// drawn with the inner part winding the other way so it stays empty.
    static func marker(_ end: LineEnd) -> (name: String, marker: ODFMarker, centered: Bool)? {
        let circle = "M10 0C15.52 0 20 4.48 20 10C20 15.52 15.52 20 10 20C4.48 20 0 15.52 0 10C0 4.48 4.48 0 10 0Z"
        let innerCircle = "M10 4C6.69 4 4 6.69 4 10C4 13.31 6.69 16 10 16C13.31 16 16 13.31 16 10C16 6.69 13.31 4 10 4Z"
        switch end {
        case .none: return nil
        case .fillArrow: return ("Arrow", ODFMarker(viewBox: "0 0 20 30", path: "M10 0L20 30L0 30Z"), false)
        case .strokeArrow:
            return ("Line Arrow", ODFMarker(viewBox: "0 0 20 30", path: "M10 0L20 26L16.5 30L10 11L3.5 30L0 26Z"), false)
        case .fillCircle: return ("Circle", ODFMarker(viewBox: "0 0 20 20", path: circle), true)
        case .strokeCircle: return ("Circle unfilled", ODFMarker(viewBox: "0 0 20 20", path: circle + innerCircle), true)
        case .fillSquare: return ("Square", ODFMarker(viewBox: "0 0 20 20", path: "M0 0L20 0L20 20L0 20Z"), true)
        case .strokeSquare:
            return ("Square unfilled", ODFMarker(viewBox: "0 0 20 20", path: "M0 0L20 0L20 20L0 20ZM5 5L5 15L15 15L15 5Z"), true)
        case .fillDiamond: return ("Square 45", ODFMarker(viewBox: "0 0 20 20", path: "M10 0L20 10L10 20L0 10Z"), true)
        case .strokeDiamond:
            return ("Square 45 unfilled", ODFMarker(viewBox: "0 0 20 20", path: "M10 0L20 10L10 20L0 10ZM10 6L6 10L10 14L14 10Z"), true)
        }
    }

    /// The line end a marker stands for, by its name.
    static func lineEnd(markerName: String) -> LineEnd {
        let name = markerName.lowercased()
        let unfilled = name.contains("unfilled") || name.contains("hollow") || name.contains("outline")
        if name.contains("square 45") || name.contains("diamond") { return unfilled ? .strokeDiamond : .fillDiamond }
        if name.contains("square") { return unfilled ? .strokeSquare : .fillSquare }
        if name.contains("circle") || name.contains("oval") || name.contains("dot") { return unfilled ? .strokeCircle : .fillCircle }
        if name.contains("line arrow") || name.contains("open") || name.contains("concave") || name.contains("line end") {
            return .strokeArrow
        }
        return unfilled ? .strokeArrow : .fillArrow
    }

    /// LibreOffice's name for each dash style and its pattern, in line widths.
    static func dash(_ style: DashStyle) -> (name: String, dash: ODFDash)? {
        switch style {
        case .solid: nil
        case .dot: ("Dot", ODFDash(dots1: 1, dots1Length: 1, distance: 1))
        case .dash: ("Dash", ODFDash(dots1: 1, dots1Length: 4, distance: 3))
        case .dashDot: ("Dash Dot", ODFDash(dots1: 1, dots1Length: 4, dots2: 1, dots2Length: 1, distance: 3))
        case .longDash: ("Long Dash", ODFDash(dots1: 1, dots1Length: 8, distance: 3))
        case .longDashDot: ("Long Dash Dot", ODFDash(dots1: 1, dots1Length: 8, dots2: 1, dots2Length: 1, distance: 3))
        }
    }

    /// The dash style closest to a pattern on a line `width` points wide.
    static func dashStyle(_ dash: ODFDash, name: String, width: Double) -> DashStyle {
        for style in DashStyle.allCases {
            if let known = self.dash(style), known.name.caseInsensitiveCompare(name) == .orderedSame { return style }
        }
        let scale = dash.isAbsolute ? 1 / max(width, 0.5) : 1
        let first = dash.dots1Length * scale, second = dash.dots2Length * scale
        let long = max(first, second)
        // Two kinds of dash of about the same length are one dash pattern.
        let mixed = dash.dots1 > 0 && dash.dots2 > 0 && second > 0 && first > 0 && abs(first - second) > 0.25 * long
        if mixed { return long >= 6 ? .longDashDot : .dashDot }
        if long <= 1.5 { return .dot }
        return long >= 6 ? .longDash : .dash
    }
}
