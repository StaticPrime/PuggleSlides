import Foundation

/// One DrawingML preset (presetShapeDefinitions.xml), parsed from its text form with every guide name resolved to a
/// slot in a value array, so evaluating it is a single pass over its formulas.
///
/// The text form has one statement per line:
///
///     av NAME FORMULA          avLst entry: an adjust value and its default ("av adj val 16667")
///     gd NAME FORMULA          gdLst entry ("gd x1 */ ss a 100000")
///     ahXY gdRefX= minX= maxX= gdRefY= minY= maxY= x= y=
///     ahPolar gdRefR= minR= maxR= gdRefAng= minAng= maxAng= x= y=
///     cxn ANGLE X Y            connection site
///     rect L T R B             text rectangle
///     path w= h= fill= stroke= extrusionOk=
///     M x y | L x y | A wR hR stAng swAng | Q x1 y1 x y | C x1 y1 x2 y2 x y | Z
///
/// The PresetShapes+… files hold the standard's 187 presets in this form, with the published file's errata fixed
/// the way PowerPoint and LibreOffice read them: pie's text rectangle (t and r swapped), star24's and star32's
/// handle maximum ("ssd2" for 50000), the circular arrows' "+-" formulas with a stray fourth argument,
/// curvedLeftArrow's connection angle "cd3" (cd2) and rtTriangle's undefined "wd12" (w / 12).
struct PresetShapeDefinition: Sendable {
    struct Adjust: Sendable {
        var name: String
        var slot: Int
        var formula: GuideFormula
    }

    struct Guide: Sendable {
        var slot: Int
        var formula: GuideFormula
    }

    /// What a handle's drag position sets.
    enum AxisRole: Sendable {
        case x, y, radius, angle
    }

    struct HandleAxis: Sendable {
        var role: AxisRole
        /// Index into `adjusts`.
        var adjust: Int
        var minimum: GuideOperand?
        var maximum: GuideOperand?
    }

    struct Handle: Sendable {
        /// x then y for ahXY; angle then radius for ahPolar. Never empty.
        var axes: [HandleAxis]
        var x: GuideOperand
        var y: GuideOperand
    }

    struct ConnectionSite: Sendable {
        var angle: GuideOperand
        var x: GuideOperand
        var y: GuideOperand
    }

    struct TextRect: Sendable {
        var left: GuideOperand
        var top: GuideOperand
        var right: GuideOperand
        var bottom: GuideOperand
    }

    enum Command: Sendable {
        case move(GuideOperand, GuideOperand)
        case line(GuideOperand, GuideOperand)
        case arc(widthRadius: GuideOperand, heightRadius: GuideOperand, start: GuideOperand, sweep: GuideOperand)
        case quadratic(GuideOperand, GuideOperand, GuideOperand, GuideOperand)
        case cubic(GuideOperand, GuideOperand, GuideOperand, GuideOperand, GuideOperand, GuideOperand)
        case close
    }

    struct Path: Sendable {
        /// The path's coordinate space; 0 means shape space.
        var width: Double = 0
        var height: Double = 0
        var fill: PathFillMode = .normal
        var stroke = true
        var commands: [Command] = []
    }

    let name: String
    let slotCount: Int
    let adjusts: [Adjust]
    let guides: [Guide]
    let handles: [Handle]
    let connectionSites: [ConnectionSite]
    let textRect: TextRect?
    let paths: [Path]
    /// Names that didn't resolve and statements that didn't parse; empty for a well-formed definition.
    let problems: [String]
    /// Every guide's slot by name (built-ins, adjust values and gdLst entries).
    let slots: [String: Int]

    init(name: String, source: String) {
        var slotCount = BuiltInGuides.count
        var adjusts: [Adjust] = []
        var guides: [Guide] = []
        var handles: [Handle] = []
        var connectionSites: [ConnectionSite] = []
        var textRect: TextRect?
        var paths: [Path] = []
        var problems: [String] = []
        var symbols = BuiltInGuides.slots
        var adjustIndices: [String: Int] = [:]

        func operand(_ token: Substring) -> GuideOperand {
            if let number = GuideOperand.number(token) { return .constant(number) }
            if let slot = symbols[String(token)] { return .slot(slot) }
            problems.append("unknown guide \(token)")
            return .constant(0)
        }

        for line in source.split(separator: "\n") {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let keyword = tokens.first else { continue }
            let arguments = Array(tokens.dropFirst())
            switch keyword {
            case "av", "gd":
                guard arguments.count >= 2,
                      let formula = GuideFormula.parse(arguments.dropFirst().joined(separator: " "), resolve: operand) else {
                    problems.append("bad guide: \(line)")
                    continue
                }
                let guideName = String(arguments[0])
                let slot = slotCount
                slotCount += 1
                symbols[guideName] = slot
                if keyword == "av" {
                    adjustIndices[guideName] = adjusts.count
                    adjusts.append(Adjust(name: guideName, slot: slot, formula: formula))
                } else {
                    guides.append(Guide(slot: slot, formula: formula))
                }
            case "ahXY", "ahPolar":
                var fields: [String: Substring] = [:]
                for argument in arguments {
                    let parts = argument.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 { fields[String(parts[0])] = parts[1] }
                }
                let specs: [(AxisRole, String, String, String)] = keyword == "ahPolar"
                    ? [(.angle, "gdRefAng", "minAng", "maxAng"), (.radius, "gdRefR", "minR", "maxR")]
                    : [(.x, "gdRefX", "minX", "maxX"), (.y, "gdRefY", "minY", "maxY")]
                var axes: [HandleAxis] = []
                for (role, reference, minimum, maximum) in specs {
                    guard let adjustName = fields[reference] else { continue }
                    guard let index = adjustIndices[String(adjustName)] else {
                        problems.append("handle refers to \(adjustName), which isn't an adjust value")
                        continue
                    }
                    axes.append(HandleAxis(role: role, adjust: index, minimum: fields[minimum].map(operand),
                                           maximum: fields[maximum].map(operand)))
                }
                guard !axes.isEmpty, let x = fields["x"], let y = fields["y"] else {
                    problems.append("bad handle: \(line)")
                    continue
                }
                handles.append(Handle(axes: axes, x: operand(x), y: operand(y)))
            case "cxn":
                guard arguments.count == 3 else {
                    problems.append("bad connection site: \(line)")
                    continue
                }
                connectionSites.append(ConnectionSite(angle: operand(arguments[0]), x: operand(arguments[1]), y: operand(arguments[2])))
            case "rect":
                guard arguments.count == 4 else {
                    problems.append("bad text rectangle: \(line)")
                    continue
                }
                textRect = TextRect(left: operand(arguments[0]), top: operand(arguments[1]), right: operand(arguments[2]),
                                    bottom: operand(arguments[3]))
            case "path":
                var path = Path()
                for argument in arguments {
                    let parts = argument.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    switch parts[0] {
                    case "w": path.width = Double(parts[1]) ?? 0
                    case "h": path.height = Double(parts[1]) ?? 0
                    case "fill": path.fill = PathFillMode(rawValue: String(parts[1])) ?? .normal
                    case "stroke": path.stroke = parts[1] != "false" && parts[1] != "0"
                    default: break
                    }
                }
                paths.append(path)
            default:
                guard !paths.isEmpty else {
                    problems.append("path command outside a path: \(line)")
                    continue
                }
                let values = arguments.map(operand)
                let command: Command?
                switch (keyword, values.count) {
                case ("M", 2): command = .move(values[0], values[1])
                case ("L", 2): command = .line(values[0], values[1])
                case ("A", 4): command = .arc(widthRadius: values[0], heightRadius: values[1], start: values[2], sweep: values[3])
                case ("Q", 4): command = .quadratic(values[0], values[1], values[2], values[3])
                case ("C", 6): command = .cubic(values[0], values[1], values[2], values[3], values[4], values[5])
                case ("Z", 0): command = .close
                default: command = nil
                }
                if let command {
                    paths[paths.count - 1].commands.append(command)
                } else {
                    problems.append("bad statement: \(line)")
                }
            }
        }
        self.name = name
        self.slotCount = slotCount
        self.adjusts = adjusts
        self.guides = guides
        self.handles = handles
        self.connectionSites = connectionSites
        self.textRect = textRect
        self.paths = paths
        self.problems = problems
        self.slots = symbols
    }

    /// The default adjust values, keyed by name.
    var defaultAdjustments: [String: Double] {
        let values = evaluate(width: 0, height: 0, adjustments: [:])
        return Dictionary(uniqueKeysWithValues: adjusts.map { ($0.name, values[$0.slot]) })
    }

    /// Every guide's value for a shape of `width` × `height` with the given adjust values (defaults fill the gaps).
    func evaluate(width: Double, height: Double, adjustments: [String: Double]) -> [Double] {
        var values = [Double](repeating: 0, count: slotCount)
        BuiltInGuides.fill(&values, width: width, height: height)
        for adjust in adjusts {
            if let value = adjustments[adjust.name], value.isFinite {
                values[adjust.slot] = value
            } else {
                values[adjust.slot] = adjust.formula.evaluate(values)
            }
        }
        for guide in guides { values[guide.slot] = guide.formula.evaluate(values) }
        return values
    }

    /// Like `evaluate(width:height:adjustments:)` with the adjust values given in `adjusts` order.
    func evaluate(width: Double, height: Double, adjustValues: [Double]) -> [Double] {
        var values = [Double](repeating: 0, count: slotCount)
        BuiltInGuides.fill(&values, width: width, height: height)
        for (index, adjust) in adjusts.enumerated() { values[adjust.slot] = adjustValues[index] }
        for guide in guides { values[guide.slot] = guide.formula.evaluate(values) }
        return values
    }

    /// The adjust values in `adjusts` order: `adjustments` where given, defaults elsewhere.
    func adjustValues(_ adjustments: [String: Double]) -> [Double] {
        let values = evaluate(width: 0, height: 0, adjustments: adjustments)
        return adjusts.map { values[$0.slot] }
    }
}

/// The text form of every preset, by name (see `PresetShapeDefinition`), gathered from the PresetShapes+… files.
enum PresetShapeSource {
    static let all: [String: String] = {
        var all: [String: String] = [:]
        for group in [basic, arrows, callouts, flowchart, starsAndBanners, actionButtons, connectors] {
            all.merge(group) { first, _ in first }
        }
        return all
    }()
}

/// Parsed presets, kept once parsed.
final class PresetShapeLibrary: @unchecked Sendable {
    static let shared = PresetShapeLibrary()

    private let lock = NSLock()
    private var definitions: [String: PresetShapeDefinition] = [:]

    func definition(named name: String) -> PresetShapeDefinition? {
        lock.lock()
        defer { lock.unlock() }
        if let definition = definitions[name] { return definition }
        guard let source = PresetShapeSource.all[name] else { return nil }
        let definition = PresetShapeDefinition(name: name, source: source)
        definitions[name] = definition
        return definition
    }
}
