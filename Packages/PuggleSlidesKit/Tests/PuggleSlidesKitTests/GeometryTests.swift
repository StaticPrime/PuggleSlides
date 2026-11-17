import CoreGraphics
import Foundation
import Testing
@testable import PuggleSlidesKit

/// The connector presets the Line tool and PowerPoint files use.
let connectorPresets = ["line", "straightConnector1", "bentConnector2", "bentConnector3", "bentConnector4", "bentConnector5",
                        "curvedConnector2", "curvedConnector3", "curvedConnector4", "curvedConnector5"]

/// A path's elements as (type, points).
func elements(of path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
    var result: [(type: CGPathElementType, points: [CGPoint])] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        let count = switch element.type {
        case .moveToPoint, .addLineToPoint: 1
        case .addQuadCurveToPoint: 2
        case .addCurveToPoint: 3
        default: 0
        }
        result.append((element.type, (0..<count).map { element.points[$0] }))
    }
    return result
}

/// The end point of every element but closes: a polygon's vertices.
func vertices(of path: CGPath) -> [CGPoint] {
    elements(of: path).compactMap(\.points.last)
}

func close(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 1e-6) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

func close(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 1e-6) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
        && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

@Suite struct GeometryTests {
    // MARK: Definitions and catalog

    @Test func everyPresetShapeTypeIsDefined() throws {
        #expect(PresetGeometry.presetNames.count == 187)
        for name in PresetGeometry.presetNames {
            let definition = try #require(PresetShapeLibrary.shared.definition(named: name))
            #expect(definition.problems.isEmpty, "\(name): \(definition.problems)")
            #expect(!definition.paths.isEmpty, "\(name) has no paths")
            #expect(definition.paths.allSatisfy { !$0.commands.isEmpty }, "\(name) has an empty path")
        }
        for name in ["actionButtonSound", "flowChartOfflineStorage", "lineInv", "swooshArrow", "chartPlus", "gear9",
                     "leftRightCircularArrow", "accentBorderCallout3", "upDownArrowCallout", "nonIsoscelesTrapezoid"] {
            #expect(PresetGeometry.presetNames.contains(name), "\(name) is missing")
        }
    }

    @Test func catalogFollowsTheShapeGallery() {
        let catalog = PresetGeometry.catalog
        #expect(Set(catalog.map(\.name)).count == catalog.count)
        #expect(catalog.allSatisfy { PresetGeometry.presetNames.contains($0.name) && !$0.title.isEmpty })
        let counts = Dictionary(grouping: catalog, by: \.category).mapValues(\.count)
        #expect(counts[.shapes] == 72)
        #expect(counts[.arrows] == 26)
        #expect(counts[.callouts] == 24)
        #expect(counts[.equation] == 12)
        // Each category is one run, in menu order.
        var runs: [ShapeCategory] = []
        for info in catalog where runs.last != info.category { runs.append(info.category) }
        #expect(runs == ShapeCategory.allCases)
        #expect(catalog.prefix(3).map(\.name) == ["rect", "roundRect", "snip1Rect"])
        #expect(catalog.filter { $0.category == .equation }.prefix(6).map(\.name)
            == ["mathPlus", "mathMinus", "mathMultiply", "mathDivide", "mathEqual", "mathNotEqual"])
        #expect(PresetGeometry.info(named: "roundRect")?.title == "Rounded Rectangle")
        #expect(PresetGeometry.info(named: "flowChartInputOutput")?.title == "Flowchart: Data")
        #expect(PresetGeometry.info(named: "homePlate")?.category == .arrows)
        #expect(PresetGeometry.info(named: "star5")?.title == "5-Point Star")
        #expect(PresetGeometry.info(named: "callout1") == nil)
    }

    @Test func defaultAdjustmentsComeFromTheAvLst() {
        #expect(PresetGeometry.defaultAdjustments("roundRect") == ["adj": 16667])
        #expect(PresetGeometry.defaultAdjustments("rightArrow") == ["adj1": 50000, "adj2": 50000])
        #expect(PresetGeometry.defaultAdjustments("blockArc") == ["adj1": 10_800_000, "adj2": 0, "adj3": 25000])
        #expect(PresetGeometry.defaultAdjustments("wedgeRectCallout") == ["adj1": -20833, "adj2": 62500])
        #expect(PresetGeometry.defaultAdjustments("rect").isEmpty)
        #expect(PresetGeometry.defaultAdjustments("noSuchShape").isEmpty)
    }

    // MARK: Paths

    @Test(arguments: [CGSize(width: 120, height: 80), CGSize(width: 50, height: 160), CGSize(width: 200, height: 20)])
    func galleryAndConnectorShapesDrawInsideTheirFrames(size: CGSize) {
        let rect = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
        // Callout tails point outside the frame; the not-equal slash is as wide as the bars are thick, so it pokes out
        // of very tall frames; the heart's and cloud's curves bulge a hair past it.
        let reaching: [String: CGFloat] = ["wedgeRectCallout": 0.2, "wedgeRoundRectCallout": 0.2, "wedgeEllipseCallout": 0.2,
                                           "cloudCallout": 0.2, "mathNotEqual": 0.2]
        for name in PresetGeometry.catalog.map(\.name) + connectorPresets {
            let paths = PresetGeometry.paths(for: .preset(name, adjustments: [:]), in: rect)
            #expect(!paths.isEmpty, "\(name) draws nothing")
            var union = CGRect.null
            for part in paths {
                let box = part.path.boundingBoxOfPath
                #expect(!part.path.isEmpty && !box.isNull, "\(name) has an empty part")
                let finite = [box.minX, box.minY, box.maxX, box.maxY].allSatisfy { $0.isFinite }
                #expect(finite, "\(name) isn't finite")
                union = union.union(box)
            }
            let slack = (reaching[name] ?? 0.01) * max(size.width, size.height)
            #expect(rect.insetBy(dx: -slack, dy: -slack).contains(union), "\(name) at \(size) reaches \(union)")
            #expect(union.width >= size.width * 0.3 || union.height >= size.height * 0.3, "\(name) is too small: \(union)")
        }
    }

    @Test func everyPresetDrawsFinitePathsAtOddSizes() {
        for size in [CGSize(width: 100, height: 100), CGSize(width: 300, height: 7), CGSize(width: 0, height: 40), CGSize(width: 0, height: 0)] {
            let rect = CGRect(origin: CGPoint(x: -5, y: 3), size: size)
            for name in PresetGeometry.presetNames {
                let geometry = ShapeGeometry.preset(name, adjustments: [:])
                for part in PresetGeometry.paths(for: geometry, in: rect) {
                    let box = part.path.boundingBoxOfPath
                    let finite = box.isNull || [box.minX, box.minY, box.maxX, box.maxY].allSatisfy { $0.isFinite }
                    #expect(finite, "\(name) at \(size)")
                }
                let text = PresetGeometry.textRect(for: geometry, in: rect)
                let finite = [text.minX, text.minY, text.width, text.height].allSatisfy { $0.isFinite }
                #expect(finite, "\(name) at \(size)")
            }
        }
    }

    @Test func pathsCarryFillModesAndStrokeFlags() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let can = PresetGeometry.paths(for: .preset("can", adjustments: [:]), in: rect)
        #expect(can.map(\.fill) == [.normal, .lighten, PathFillMode.none])
        #expect(can.map(\.stroke) == [false, false, true])
        let cube = PresetGeometry.paths(for: .preset("cube", adjustments: [:]), in: rect)
        #expect(cube.map(\.fill) == [.normal, .darkenLess, .lightenLess, PathFillMode.none])
        let line = PresetGeometry.paths(for: .line, in: rect)
        #expect(line.count == 1 && line[0].stroke)
        #expect(vertices(of: line[0].path) == [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        // chartPlus lists its lines before its fill; the lines come out last so they're drawn on top.
        let chart = PresetGeometry.paths(for: .preset("chartPlus", adjustments: [:]), in: rect)
        #expect(chart.map(\.fill) == [.normal, PathFillMode.none])
    }

    @Test func unknownPresetsDrawAsRectangles() {
        let rect = CGRect(x: 4, y: 6, width: 90, height: 30)
        let paths = PresetGeometry.paths(for: .preset("notAShape", adjustments: ["adj": 5]), in: rect)
        #expect(paths.count == 1)
        #expect(close(paths[0].path.boundingBoxOfPath, rect))
        #expect(PresetGeometry.textRect(for: .preset("notAShape", adjustments: [:]), in: rect) == rect)
        #expect(PresetGeometry.handles(for: .preset("notAShape", adjustments: [:]), in: rect).isEmpty)
    }

    @Test func ovalsFillTheirFrameExactly() {
        let rect = CGRect(x: 10, y: 20, width: 160, height: 60)
        let path = PresetGeometry.paths(for: .preset("ellipse", adjustments: [:]), in: rect)[0].path
        #expect(close(path.boundingBoxOfPath, rect, within: 1e-6))
        // The first quarter runs clockwise from the left edge's middle to the top's.
        let curve = elements(of: path)[1]
        #expect(curve.type == .addCurveToPoint)
        #expect(close(curve.points[2], CGPoint(x: 90, y: 20)))
    }

    @Test func roundedRectangleCornersFollowTheAdjustValue() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        for (adjust, radius) in [(nil, 16667.0 / 100000 * 100), (30000.0, 30.0), (80000.0, 50.0)] {
            let adjustments = adjust.map { ["adj": $0] } ?? [:]
            let geometry = ShapeGeometry.preset("roundRect", adjustments: adjustments)
            let path = PresetGeometry.paths(for: geometry, in: rect)[0].path
            let parts = elements(of: path)
            #expect(parts[0].type == .moveToPoint && close(parts[0].points[0], CGPoint(x: 0, y: radius)))
            // The top-left corner: a quarter ellipse from (0, r) to (r, 0), then the straight top edge.
            #expect(parts[1].type == .addCurveToPoint && close(parts[1].points[2], CGPoint(x: radius, y: 0)))
            #expect(parts[2].type == .addLineToPoint && close(parts[2].points[0], CGPoint(x: 200 - radius, y: 0)))
            let corner = CGMutablePath()
            corner.move(to: parts[0].points[0])
            corner.addCurve(to: parts[1].points[2], control1: parts[1].points[0], control2: parts[1].points[1])
            #expect(close(corner.boundingBoxOfPath, CGRect(x: 0, y: 0, width: radius, height: radius), within: 1e-6))
            // The handle sits where the corner meets the top edge.
            let handle = PresetGeometry.handles(for: geometry, in: rect)
            #expect(handle.count == 1 && handle[0].name == "adj" && close(handle[0].position, CGPoint(x: radius, y: 0)))
            // Text keeps clear of the corners: 29.289% of the radius in from each side.
            let text = PresetGeometry.textRect(for: geometry, in: rect)
            let inset = radius * 0.29289
            #expect(close(text, CGRect(x: inset, y: inset, width: 200 - 2 * inset, height: 100 - 2 * inset), within: 1e-6))
        }
    }

    @Test func rightArrowHeadAndShaftFollowTheAdjustValues() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        func outline(_ adjustments: [String: Double]) -> [CGPoint] {
            vertices(of: PresetGeometry.paths(for: .preset("rightArrow", adjustments: adjustments), in: rect)[0].path)
        }
        func points(_ pairs: [(CGFloat, CGFloat)]) -> [CGPoint] { pairs.map { CGPoint(x: $0.0, y: $0.1) } }
        // adj1 is the shaft's thickness as a share of the height; adj2 the head's length as a share of the short side.
        #expect(outline([:]) == points([(0, 25), (150, 25), (150, 0), (200, 50), (150, 100), (150, 75), (0, 75)]))
        let thin = outline(["adj1": 30000, "adj2": 70000])
        let expected = points([(0, 35), (130, 35), (130, 0), (200, 50), (130, 100), (130, 65), (0, 65)])
        #expect(zip(thin, expected).allSatisfy { close($0, $1) } && thin.count == expected.count)
        // The head can't be longer than the arrow.
        #expect(outline(["adj2": 500_000])[1] == CGPoint(x: 0, y: 25))
        let text = PresetGeometry.textRect(for: .preset("rightArrow", adjustments: [:]), in: rect)
        #expect(close(text, CGRect(x: 0, y: 25, width: 175, height: 50)))
    }

    @Test func pathsFollowTheFrameOrigin() {
        let size = CGSize(width: 80, height: 50)
        for name in ["star5", "cloud", "curvedRightArrow", "flowChartPunchedTape"] {
            let atZero = PresetGeometry.paths(for: .preset(name, adjustments: [:]), in: CGRect(origin: .zero, size: size))
            let moved = PresetGeometry.paths(for: .preset(name, adjustments: [:]), in: CGRect(origin: CGPoint(x: 30, y: -12), size: size))
            for (a, b) in zip(atZero, moved) {
                #expect(close(a.path.boundingBoxOfPath.offsetBy(dx: 30, dy: -12), b.path.boundingBoxOfPath, within: 1e-9), "\(name)")
            }
        }
    }

    // MARK: Text rectangles

    @Test func textRectanglesAreSensible() {
        for size in [CGSize(width: 120, height: 80), CGSize(width: 60, height: 150)] {
            let rect = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
            for name in PresetGeometry.catalog.map(\.name) {
                let text = PresetGeometry.textRect(for: .preset(name, adjustments: [:]), in: rect)
                #expect(text.width > 0 && text.height > 0, "\(name): \(text)")
                #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(text), "\(name): \(text) leaves \(rect)")
                // The 4-point star's text box, its inner square, is the smallest: about 3% of the frame.
                #expect(text.width * text.height >= rect.width * rect.height * 0.025, "\(name): \(text) is tiny")
            }
        }
        // The right triangle's text sits in its lower-left part: w/12 … 7w/12 across, 7h/12 … 11h/12 down.
        let triangle = PresetGeometry.textRect(for: .preset("rtTriangle", adjustments: [:]), in: CGRect(x: 0, y: 0, width: 120, height: 120))
        #expect(close(triangle, CGRect(x: 10, y: 70, width: 60, height: 40), within: 1e-9))
        // The pie's text rectangle uses the corrected l/t/r/b order (the published file swaps t and r).
        let pie = PresetGeometry.textRect(for: .preset("pie", adjustments: [:]), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(abs(pie.minX - pie.minY) < 1e-9 && abs(pie.width - pie.height) < 1e-9 && pie.width > 60)
    }

    @Test func customTextRectanglesUseFractionsOfTheFrame() {
        let custom = CustomGeometry(paths: [], textRect: TextInsetFractions(left: 0.1, top: 0.2, right: 0.3, bottom: 0.1))
        let text = PresetGeometry.textRect(for: .custom(custom), in: CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(close(text, CGRect(x: 20, y: 20, width: 60, height: 35), within: 1e-9))
        let whole = PresetGeometry.textRect(for: .custom(CustomGeometry(paths: [])), in: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(whole == CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    // MARK: Connection sites

    @Test func connectionSitesComeFromTheCxnLst() {
        let sites = PresetGeometry.connectionSites(for: .rectangle, in: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(sites.map(\.position) == [CGPoint(x: 50, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 50, y: 40), CGPoint(x: 100, y: 20)])
        #expect(sites.map(\.angle) == [270, 180, 90, 0])
        #expect(PresetGeometry.connectionSites(for: .custom(CustomGeometry(paths: [])), in: .zero).isEmpty)
    }

    // MARK: Shape guides

    @Test func formulaOperatorsFollowDrawingML() {
        func evaluate(_ formula: String) -> Double {
            GuideFormula.parse(formula) { _ in .constant(0) }?.evaluate([]) ?? .nan
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 * max(1, abs(b)) }
        #expect(evaluate("*/ 3 4 2") == 6)
        #expect(evaluate("*/ 3 4 0") == 0)
        #expect(evaluate("+- 3 4 2") == 5)
        #expect(evaluate("+/ 3 5 2") == 4)
        #expect(evaluate("?: 1 2 3") == 2)
        #expect(evaluate("?: 0 2 3") == 3)
        #expect(evaluate("?: -1 2 3") == 3)
        #expect(evaluate("abs -5") == 5)
        #expect(near(evaluate("at2 1 1"), 2_700_000))
        #expect(near(evaluate("at2 -1 0"), 10_800_000))
        #expect(near(evaluate("at2 0 -2"), -5_400_000))
        #expect(near(evaluate("cat2 10 1 1"), 10 * cos(Double.pi / 4)))
        #expect(near(evaluate("cat2 10 3 4"), 6))
        #expect(near(evaluate("cos 10 0"), 10))
        #expect(abs(evaluate("cos 10 5400000")) < 1e-9)
        #expect(near(evaluate("cos 10 21600000"), 10))
        #expect(evaluate("max 3 7") == 7)
        #expect(evaluate("min 3 7") == 3)
        #expect(evaluate("mod 3 4 12") == 13)
        #expect(evaluate("pin 0 5 10") == 5)
        #expect(evaluate("pin 0 -5 10") == 0)
        #expect(evaluate("pin 0 15 10") == 10)
        #expect(near(evaluate("sat2 10 3 4"), 8))
        #expect(near(evaluate("sin 10 5400000"), 10))
        #expect(near(evaluate("sin 10 -5400000"), -10))
        #expect(evaluate("sqrt 16") == 4)
        #expect(evaluate("sqrt -4") == 0)
        #expect(near(evaluate("tan 10 2700000"), 10))
        #expect(evaluate("val 42") == 42)
        #expect(evaluate("val -7.5") == -7.5)
        #expect(Set(GuideOperator.allCases.map(\.rawValue)) == ["*/", "+-", "+/", "?:", "abs", "at2", "cat2", "cos", "max", "min",
                                                                 "mod", "pin", "sat2", "sin", "sqrt", "tan", "val"])
        #expect(GuideFormula.parse("nope 1 2") { _ in .constant(0) } == nil)
    }

    @Test func builtInGuidesComeFromTheShapeSize() {
        var guides = ShapeGuideEvaluator(width: 240, height: 120)
        let expected: [String: Double] = [
            "w": 240, "h": 120, "l": 0, "t": 0, "r": 240, "b": 120, "hc": 120, "vc": 60, "ss": 120, "ls": 240,
            "wd2": 120, "wd3": 80, "wd4": 60, "wd5": 48, "wd6": 40, "wd8": 30, "wd10": 24, "wd32": 7.5,
            "hd2": 60, "hd3": 40, "hd4": 30, "hd5": 24, "hd6": 20, "hd8": 15, "hd10": 12,
            "ssd2": 60, "ssd4": 30, "ssd6": 20, "ssd8": 15, "ssd16": 7.5, "ssd32": 3.75,
            "cd2": 10_800_000, "cd4": 5_400_000, "cd8": 2_700_000, "3cd4": 16_200_000, "3cd8": 8_100_000,
            "5cd8": 13_500_000, "7cd8": 18_900_000,
        ]
        for (name, value) in expected {
            let actual = guides.value(of: name)
            #expect(actual.map { abs($0 - value) < 1e-9 } == true, "\(name) = \(String(describing: actual)), expected \(value)")
        }
        // Guides build on earlier ones, as a file's gdLst does.
        guides.define("adj", value: 25000)
        #expect(guides.define("x1", formula: "*/ ss adj 100000") == 30)
        #expect(guides.define("x2", formula: "+- r 0 x1") == 210)
        #expect(guides.value(of: "x2") == 210)
        #expect(guides.value(of: "-12") == -12)
        #expect(guides.value(of: "missing") == nil)
        #expect(guides.define("bad", formula: "+- missing 5 0") == 5)
    }

    // MARK: Arcs

    @Test func arcsContinueFromTheCurrentPoint() {
        // A circle drawn as quarter arcs: each one starts where the last ended.
        let quarters = CustomPath(width: 0, height: 0, commands: [
            .move(SlidePoint(x: 0, y: 50)),
            .arc(widthRadius: 50, heightRadius: 25, startAngle: 180, sweepAngle: 90),
            .arc(widthRadius: 50, heightRadius: 25, startAngle: 270, sweepAngle: 90),
            .arc(widthRadius: 50, heightRadius: 25, startAngle: 0, sweepAngle: 180),
            .close,
        ])
        let path = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [quarters])), in: CGRect(x: 0, y: 0, width: 100, height: 100))[0].path
        let ends = elements(of: path).filter { $0.type == .addCurveToPoint }.map { $0.points[2] }
        #expect(close(ends[0], CGPoint(x: 50, y: 25)))   // clockwise from the left, y down: up to the top
        #expect(close(ends[1], CGPoint(x: 100, y: 50)))
        #expect(close(ends.last!, CGPoint(x: 0, y: 50)))
        #expect(close(path.boundingBoxOfPath, CGRect(x: 0, y: 25, width: 100, height: 50)))

        // Angles are the visual angles of rays from the ellipse's center (as the preset guides compute them).
        let oblique = CustomPath(width: 0, height: 0, fill: .none, commands: [
            .move(SlidePoint(x: 200, y: 100)),
            .arc(widthRadius: 100, heightRadius: 50, startAngle: 45, sweepAngle: 90),
        ])
        let arc = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [oblique])), in: CGRect(x: 0, y: 0, width: 400, height: 400))[0].path
        let start = 45.0 * .pi / 180, t1 = atan2(100 * sin(start), 50 * cos(start))
        let center = CGPoint(x: 200 - 100 * cos(t1), y: 100 - 50 * sin(t1))
        let end = arc.currentPoint
        #expect(abs(atan2(end.y - center.y, end.x - center.x) - 135 * .pi / 180) < 1e-9)
        #expect(abs(pow((end.x - center.x) / 100, 2) + pow((end.y - center.y) / 50, 2) - 1) < 1e-9)

        // Negative sweeps go counterclockwise; a full sweep comes back round.
        let back = CustomPath(width: 0, height: 0, commands: [
            .move(SlidePoint(x: 100, y: 50)), .arc(widthRadius: 50, heightRadius: 50, startAngle: 0, sweepAngle: -90),
        ])
        let backPath = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [back])), in: CGRect(x: 0, y: 0, width: 100, height: 100))[0].path
        #expect(close(backPath.currentPoint, CGPoint(x: 50, y: 0)))
        #expect(close(backPath.boundingBoxOfPath, CGRect(x: 50, y: 0, width: 50, height: 50)))
        let full = CustomPath(width: 0, height: 0, commands: [
            .move(SlidePoint(x: 100, y: 50)), .arc(widthRadius: 50, heightRadius: 30, startAngle: 0, sweepAngle: 360),
        ])
        let fullPath = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [full])), in: CGRect(x: 0, y: 0, width: 100, height: 100))[0].path
        #expect(close(fullPath.currentPoint, CGPoint(x: 100, y: 50)))
        #expect(close(fullPath.boundingBoxOfPath, CGRect(x: 0, y: 20, width: 100, height: 60)))

        // Sweeps of many turns draw one turn and end where the sweep says.
        let spun = CustomPath(width: 0, height: 0, commands: [
            .move(SlidePoint(x: 100, y: 50)), .arc(widthRadius: 50, heightRadius: 50, startAngle: 0, sweepAngle: 3600 + 90),
            .arc(widthRadius: 50, heightRadius: 50, startAngle: 0, sweepAngle: 1e12),
        ])
        let spunPath = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [spun])), in: CGRect(x: 0, y: 0, width: 100, height: 100))[0].path
        let spunParts = elements(of: spunPath)
        #expect(spunParts.count <= 1 + 5 + 8)
        #expect(close(spunParts[5].points[2], CGPoint(x: 50, y: 100)))
        #expect([spunPath.currentPoint.x, spunPath.currentPoint.y].allSatisfy { $0.isFinite })
    }

    @Test func presetArcsMeetTheGuidePointsAfterThem() throws {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        // The arc's outline ends at its second handle (the end angle's point on the ellipse).
        let arc = ShapeGeometry.preset("arc", adjustments: ["adj1": 13_000_000, "adj2": 3_000_000])
        let outline = PresetGeometry.paths(for: arc, in: rect)[1].path
        let handles = PresetGeometry.handles(for: arc, in: rect)
        #expect(close(outline.currentPoint, handles[1].position, within: 1e-9))
        // Each of a block arc's arcs ends exactly where the guides put the next corner.
        let definition = try #require(PresetShapeLibrary.shared.definition(named: "blockArc"))
        for adjustments in [[:], ["adj1": 2_000_000, "adj2": 15_000_000, "adj3": 40000.0]] {
            let values = definition.evaluate(width: 200, height: 100, adjustments: adjustments)
            func guide(_ name: String) throws -> CGPoint {
                CGPoint(x: values[try #require(definition.slots["x\(name)"])], y: values[try #require(definition.slots["y\(name)"])])
            }
            let inner = try guide("2"), outerEnd = try guide("3"), innerEnd = try guide("4")
            let parts = elements(of: PresetGeometry.paths(for: .preset("blockArc", adjustments: adjustments), in: rect)[0].path)
            let line = try #require(parts.firstIndex { $0.type == .addLineToPoint })
            #expect(close(parts[line].points[0], inner))
            // The outer arc ends at (x3, y3), right where the line across the band starts; the inner one at (x4, y4).
            #expect(parts[line - 1].type == .addCurveToPoint && close(parts[line - 1].points[2], outerEnd, within: 1e-9))
            let lastCurve = try #require(parts.last { $0.type == .addCurveToPoint })
            #expect(close(lastCurve.points[2], innerEnd, within: 1e-9))
        }
    }

    // MARK: Custom geometry

    @Test func customPathsScaleToTheFrame() {
        let square = CustomPath(width: 10, height: 10, commands: [
            .move(SlidePoint(x: 0, y: 0)), .line(SlidePoint(x: 10, y: 0)), .line(SlidePoint(x: 10, y: 10)),
            .line(SlidePoint(x: 0, y: 10)), .close,
        ])
        let frame = CGRect(x: 5, y: 5, width: 100, height: 50)
        let scaled = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [square])), in: frame)
        #expect(scaled.count == 1 && close(scaled[0].path.boundingBoxOfPath, frame))
        #expect(vertices(of: scaled[0].path) == [CGPoint(x: 5, y: 5), CGPoint(x: 105, y: 5), CGPoint(x: 105, y: 55), CGPoint(x: 5, y: 55)])

        // A zero width and height mean the coordinates are points.
        let points = CustomPath(width: 0, height: 0, fill: .none, stroke: true, commands: [
            .move(SlidePoint(x: 0, y: 0)), .line(SlidePoint(x: 30, y: 20)),
        ])
        let unscaled = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [points])), in: frame)[0]
        #expect(close(unscaled.path.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 30, height: 20)))
        #expect(unscaled.fill == .none && unscaled.stroke)

        // Arcs scale with the path: a half circle in a 10 × 10 space becomes a half ellipse.
        let dome = CustomPath(width: 10, height: 10, fill: .darken, stroke: false, commands: [
            .move(SlidePoint(x: 0, y: 5)), .arc(widthRadius: 5, heightRadius: 5, startAngle: 180, sweepAngle: 180), .close,
        ])
        let half = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [dome])), in: frame)[0]
        #expect(close(half.path.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 100, height: 25)))
        #expect(half.fill == .darken && !half.stroke)

        // Quadratic and cubic curves, and a mixed scale (width in its own units, height in points).
        let curves = CustomPath(width: 2, height: 0, commands: [
            .move(SlidePoint(x: 0, y: 0)), .quadratic(control: SlidePoint(x: 1, y: 40), end: SlidePoint(x: 2, y: 0)),
            .cubic(control1: SlidePoint(x: 2, y: 10), control2: SlidePoint(x: 0, y: 10), end: SlidePoint(x: 0, y: 0)),
        ])
        let curved = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [curves])), in: frame)[0].path
        let parts = elements(of: curved)
        #expect(parts.map(\.type) == [.moveToPoint, .addQuadCurveToPoint, .addCurveToPoint])
        #expect(parts[1].points == [CGPoint(x: 55, y: 45), CGPoint(x: 105, y: 5)])
        #expect(parts[2].points == [CGPoint(x: 105, y: 15), CGPoint(x: 5, y: 15), CGPoint(x: 5, y: 5)])
    }

    @Test func customPathsWithoutAMoveStartAtTheOrigin() {
        let path = CustomPath(width: 0, height: 0, commands: [.line(SlidePoint(x: 10, y: 10)), .close, .line(SlidePoint(x: 20, y: 0))])
        let drawn = PresetGeometry.paths(for: .custom(CustomGeometry(paths: [path])), in: CGRect(x: 0, y: 0, width: 50, height: 50))[0].path
        #expect(elements(of: drawn).map(\.type) == [.moveToPoint, .addLineToPoint, .closeSubpath, .moveToPoint, .addLineToPoint])
        #expect(vertices(of: drawn) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
    }

    // MARK: Performance

    @Test func evaluatingAShapeIsCheap() {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 100)
        let names = PresetGeometry.catalog.map(\.name)
        for name in names { _ = PresetGeometry.paths(for: .preset(name, adjustments: [:]), in: rect) }
        let clock = ContinuousClock()
        let rounds = 20
        let elapsed = clock.measure {
            for _ in 0..<rounds {
                for name in names { _ = PresetGeometry.paths(for: .preset(name, adjustments: [:]), in: rect) }
            }
        }
        let perShape = elapsed / (rounds * names.count)
        // Release builds take about a microsecond; debug builds and busy machines get plenty of room.
        #expect(perShape < .milliseconds(1), "paths(for:in:) took \(perShape) per shape")
    }
}
