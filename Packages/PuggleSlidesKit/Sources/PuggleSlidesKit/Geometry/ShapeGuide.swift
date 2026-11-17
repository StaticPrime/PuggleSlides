import Foundation

/// The shape-guide formula operators of DrawingML (ECMA-376 Part 1, §20.1.9.11 and §19.5).
/// Angles are in 60000ths of a degree, clockwise with y pointing down.
enum GuideOperator: String, CaseIterable, Sendable {
    /// `*/ x y z` = x · y / z
    case multiplyDivide = "*/"
    /// `+- x y z` = x + y − z
    case addSubtract = "+-"
    /// `+/ x y z` = (x + y) / z
    case addDivide = "+/"
    /// `?: x y z` = y if x > 0, else z
    case ifElse = "?:"
    /// `abs x` = |x|
    case absolute = "abs"
    /// `at2 x y` = the angle of the vector (x, y)
    case arcTangent = "at2"
    /// `cat2 x y z` = x · cos(at2(y, z))
    case cosArcTangent = "cat2"
    /// `cos x y` = x · cos(y)
    case cosine = "cos"
    /// `max x y`
    case maximum = "max"
    /// `min x y`
    case minimum = "min"
    /// `mod x y z` = √(x² + y² + z²)
    case modulus = "mod"
    /// `pin x y z` = y clamped to x…z
    case pin = "pin"
    /// `sat2 x y z` = x · sin(at2(y, z))
    case sinArcTangent = "sat2"
    /// `sin x y` = x · sin(y)
    case sine = "sin"
    /// `sqrt x` = √x
    case squareRoot = "sqrt"
    /// `tan x y` = x · tan(y)
    case tangent = "tan"
    /// `val x` = x
    case value = "val"

    var arity: Int {
        switch self {
        case .absolute, .squareRoot, .value: 1
        case .arcTangent, .cosine, .maximum, .minimum, .sine, .tangent: 2
        default: 3
        }
    }

    /// Radians per DrawingML angle unit (a 60000th of a degree).
    static let radiansPerUnit = Double.pi / 10_800_000

    func apply(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let result: Double
        switch self {
        case .multiplyDivide: result = z == 0 ? 0 : x * y / z
        case .addSubtract: result = x + y - z
        case .addDivide: result = z == 0 ? 0 : (x + y) / z
        case .ifElse: result = x > 0 ? y : z
        case .absolute: result = abs(x)
        case .arcTangent: result = atan2(y, x) / Self.radiansPerUnit
        case .cosArcTangent: result = x * cos(atan2(z, y))
        case .cosine: result = x * cos(y * Self.radiansPerUnit)
        case .maximum: result = max(x, y)
        case .minimum: result = min(x, y)
        case .modulus: result = (x * x + y * y + z * z).squareRoot()
        case .pin: result = y < x ? x : (y > z ? z : y)
        case .sinArcTangent: result = x * sin(atan2(z, y))
        case .sine: result = x * sin(y * Self.radiansPerUnit)
        case .squareRoot: result = x > 0 ? x.squareRoot() : 0
        case .tangent: result = x * tan(y * Self.radiansPerUnit)
        case .value: result = x
        }
        return result.isFinite ? result : 0
    }
}

/// A formula argument: a number, or the value of an earlier guide (by slot).
enum GuideOperand: Hashable, Sendable {
    case constant(Double)
    case slot(Int)

    @inline(__always)
    func value(in values: [Double]) -> Double {
        switch self {
        case .constant(let value): value
        case .slot(let slot): values[slot]
        }
    }

    /// Parses a literal number ("-5400000", "0.5"), or nil for a guide name. Names such as "3cd4", "2a1" or "inf"
    /// aren't numbers here.
    static func number(_ token: Substring) -> Double? {
        var digits = 0
        for (index, character) in token.enumerated() {
            if character == "-" || character == "+" {
                guard index == 0 else { return nil }
            } else if character.isASCII, character.isNumber {
                digits += 1
            } else if character != "." {
                return nil
            }
        }
        return digits > 0 ? Double(token) : nil
    }
}

struct GuideFormula: Hashable, Sendable {
    var op: GuideOperator
    var x: GuideOperand
    var y: GuideOperand
    var z: GuideOperand

    @inline(__always)
    func evaluate(_ values: [Double]) -> Double {
        op.apply(x.value(in: values), y.value(in: values), z.value(in: values))
    }

    /// Parses "op arg…" with `resolve` turning guide names into operands. Missing arguments are 0, extra ones are
    /// ignored (as PowerPoint does).
    static func parse<S: StringProtocol>(_ text: S, resolve: (Substring) -> GuideOperand) -> GuideFormula? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = tokens.first, let op = GuideOperator(rawValue: String(first)) else { return nil }
        var operands: [GuideOperand] = []
        for token in tokens.dropFirst().prefix(op.arity) {
            operands.append(GuideOperand.number(Substring(token)).map(GuideOperand.constant) ?? resolve(Substring(token)))
        }
        while operands.count < 3 { operands.append(.constant(0)) }
        return GuideFormula(op: op, x: operands[0], y: operands[1], z: operands[2])
    }
}

/// The built-in guides every shape can use, computed from the shape's width and height.
enum BuiltInGuides {
    /// In slot order.
    static let names = [
        "w", "h", "l", "t", "r", "b", "hc", "vc", "ss", "ls",
        "wd2", "wd3", "wd4", "wd5", "wd6", "wd8", "wd10", "wd32",
        "hd2", "hd3", "hd4", "hd5", "hd6", "hd7", "hd8", "hd9", "hd10",
        "ssd2", "ssd4", "ssd6", "ssd8", "ssd16", "ssd32",
        "cd2", "cd4", "cd8", "3cd4", "3cd8", "5cd8", "7cd8",
    ]

    static let slots: [String: Int] = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })

    static var count: Int { names.count }

    static func fill(_ values: inout [Double], width w: Double, height h: Double) {
        let ss = min(w, h)
        values[0] = w
        values[1] = h
        values[2] = 0
        values[3] = 0
        values[4] = w
        values[5] = h
        values[6] = w / 2
        values[7] = h / 2
        values[8] = ss
        values[9] = max(w, h)
        values[10] = w / 2
        values[11] = w / 3
        values[12] = w / 4
        values[13] = w / 5
        values[14] = w / 6
        values[15] = w / 8
        values[16] = w / 10
        values[17] = w / 32
        values[18] = h / 2
        values[19] = h / 3
        values[20] = h / 4
        values[21] = h / 5
        values[22] = h / 6
        values[23] = h / 7
        values[24] = h / 8
        values[25] = h / 9
        values[26] = h / 10
        values[27] = ss / 2
        values[28] = ss / 4
        values[29] = ss / 6
        values[30] = ss / 8
        values[31] = ss / 16
        values[32] = ss / 32
        values[33] = 10_800_000
        values[34] = 5_400_000
        values[35] = 2_700_000
        values[36] = 16_200_000
        values[37] = 8_100_000
        values[38] = 13_500_000
        values[39] = 18_900_000
    }
}

/// Evaluates DrawingML shape guides (an avLst or gdLst, as in a file's custGeom) in order, for readers that need
/// the numbers: `define("x1", formula: "*/ w adj 100000")`, then `value(of: "x1")`.
public struct ShapeGuideEvaluator: Sendable {
    private var values: [Double]
    private var slots: [String: Int]

    /// A shape of `width` × `height`, in whatever unit its guides use (EMUs in files).
    public init(width: Double, height: Double) {
        values = [Double](repeating: 0, count: BuiltInGuides.count)
        BuiltInGuides.fill(&values, width: width, height: height)
        slots = BuiltInGuides.slots
    }

    /// Evaluates `formula` ("+- r 0 x1") and stores it as `name`. Unknown names count as 0; a formula that
    /// can't be parsed stores 0.
    @discardableResult
    public mutating func define(_ name: String, formula: String) -> Double {
        let slots = self.slots
        let value = GuideFormula.parse(formula) { token in slots[String(token)].map(GuideOperand.slot) ?? .constant(0) }?
            .evaluate(values) ?? 0
        define(name, value: value)
        return value
    }

    /// Stores a value directly, for an adjust value read from a file.
    public mutating func define(_ name: String, value: Double) {
        slots[name] = values.count
        values.append(value.isFinite ? value : 0)
    }

    /// A number ("21600") or the value of a guide; nil for an unknown name.
    public func value(of token: String) -> Double? {
        if let number = GuideOperand.number(Substring(token)) { return number }
        return slots[token].map { values[$0] }
    }
}
