import CoreGraphics
import Foundation
import Testing
@testable import PuggleSlidesKit

@Suite struct GeometryHandleTests {
    let wide = CGRect(x: 0, y: 0, width: 200, height: 100)

    func drag(_ name: String, _ adjustments: [String: Double] = [:], in rect: CGRect? = nil, handle: String,
              to x: CGFloat, _ y: CGFloat) -> [String: Double] {
        PresetGeometry.adjustments(for: .preset(name, adjustments: adjustments), in: rect ?? wide, dragging: handle,
                                   to: CGPoint(x: x, y: y))
    }

    @Test func handlesAreNamedAfterDistinctAdjustValues() throws {
        for name in PresetGeometry.presetNames {
            let definition = try #require(PresetShapeLibrary.shared.definition(named: name))
            let names = PresetGeometry.handles(for: .preset(name, adjustments: [:]), in: wide).map(\.name)
            #expect(names.count == definition.handles.count)
            #expect(Set(names).count == names.count, "\(name) has handles \(names)")
            #expect(names.allSatisfy { PresetGeometry.defaultAdjustments(name)[$0] != nil }, "\(name): \(names)")
        }
        #expect(PresetGeometry.handles(for: .rectangle, in: wide).isEmpty)
        #expect(PresetGeometry.handles(for: .custom(CustomGeometry(paths: [])), in: wide).isEmpty)
    }

    @Test func draggingAHandleToItsOwnPositionKeepsTheAdjustments() {
        let rect = CGRect(x: 10, y: 20, width: 160, height: 100)
        for name in PresetGeometry.presetNames {
            let defaults = PresetGeometry.defaultAdjustments(name)
            let nudged = defaults.mapValues { $0 == 0 ? 1000 : ($0 * 0.8).rounded() }
            for adjustments in [[:], defaults, nudged] {
                let geometry = ShapeGeometry.preset(name, adjustments: adjustments)
                for handle in PresetGeometry.handles(for: geometry, in: rect) {
                    let result = PresetGeometry.adjustments(for: geometry, in: rect, dragging: handle.name, to: handle.position)
                    #expect(result == adjustments, "\(name) \(handle.name) moved \(adjustments) to \(result)")
                }
            }
        }
    }

    @Test func draggingMovesHandlesTowardThePointerWithinTheirLimits() throws {
        let rect = CGRect(x: 10, y: 20, width: 160, height: 100)
        let offsets = [CGSize(width: 9, height: 0), CGSize(width: -9, height: 0), CGSize(width: 0, height: 9),
                       CGSize(width: 0, height: -9), CGSize(width: 14, height: -11)]
        for name in PresetGeometry.catalog.map(\.name) + connectorPresets {
            let definition = try #require(PresetShapeLibrary.shared.definition(named: name))
            let geometry = ShapeGeometry.preset(name, adjustments: [:])
            let handles = PresetGeometry.handles(for: geometry, in: rect)
            for (index, handle) in handles.enumerated() {
                let axes = definition.handles[index].axes
                for offset in offsets {
                    let target = CGPoint(x: handle.position.x + offset.width, y: handle.position.y + offset.height)
                    let result = PresetGeometry.adjustments(for: geometry, in: rect, dragging: handle.name, to: target)
                    let moved = PresetGeometry.handles(for: .preset(name, adjustments: result), in: rect)[index].position
                    let values = definition.evaluate(width: rect.width, height: rect.height, adjustments: result)
                    let center = (x: Double(rect.width / 2), y: Double(rect.height / 2))
                    for axis in axes {
                        let adjust = definition.adjusts[axis.adjust]
                        let value = values[adjust.slot]
                        #expect(value == value.rounded(), "\(name) \(adjust.name) = \(value)")
                        // A changed value stays within the handle's limits. (Some defaults start outside them, such as
                        // mathDivide's adj2, and a drag that doesn't move along the axis leaves them be.)
                        if result[adjust.name] != nil {
                            if let minimum = axis.minimum?.value(in: values) { #expect(value >= minimum - 1, "\(name) \(adjust.name)") }
                            if let maximum = axis.maximum?.value(in: values) { #expect(value <= maximum + 1, "\(name) \(adjust.name)") }
                        }
                        guard axes.count == 1 else { continue }
                        // Along the handle's own axis, it ends up no farther from the pointer than it started.
                        func miss(_ point: CGPoint) -> Double {
                            let local = (x: Double(point.x - rect.minX), y: Double(point.y - rect.minY))
                            let goal = (x: Double(target.x - rect.minX), y: Double(target.y - rect.minY))
                            return abs(AdjustHandleSolver.difference(axis.role, AdjustHandleSolver.measure(axis.role, local, center: center),
                                                                     AdjustHandleSolver.measure(axis.role, goal, center: center)))
                        }
                        #expect(miss(moved) <= miss(handle.position) + 1e-3, "\(name) \(adjust.name) \(offset)")
                    }
                    if axes.count == 2 {
                        #expect(hypot(moved.x - target.x, moved.y - target.y) <= hypot(handle.position.x - target.x, handle.position.y - target.y) + 1e-3,
                                "\(name) \(handle.name) \(offset)")
                    }
                }
            }
        }
    }

    @Test func roundedRectangleHandleSlidesAlongTheTopEdge() {
        // The radius is adj% of the short side (100): x = 30 is adj 30000. Only x counts, and the value stays in 0…50000.
        #expect(drag("roundRect", handle: "adj", to: 30, 0) == ["adj": 30000])
        #expect(drag("roundRect", handle: "adj", to: 30, 40) == ["adj": 30000])
        #expect(drag("roundRect", handle: "adj", to: 10, -5) == ["adj": 10000])
        #expect(drag("roundRect", handle: "adj", to: 500, 0) == ["adj": 50000])
        #expect(drag("roundRect", handle: "adj", to: -40, 0) == ["adj": 0])
        #expect(drag("roundRect", ["adj": 5000], handle: "adj", to: 25, 0) == ["adj": 25000])
        // An unknown handle or custom geometry changes nothing.
        #expect(drag("roundRect", ["adj": 5000], handle: "adj9", to: 25, 0) == ["adj": 5000])
        #expect(PresetGeometry.adjustments(for: .custom(CustomGeometry(paths: [])), in: wide, dragging: "adj", to: .zero).isEmpty)
    }

    @Test func rightArrowHandlesSetTheShaftAndHead() {
        let handles = PresetGeometry.handles(for: .preset("rightArrow", adjustments: [:]), in: wide)
        #expect(handles.map(\.name) == ["adj1", "adj2"])
        #expect(handles.map(\.position) == [CGPoint(x: 0, y: 25), CGPoint(x: 150, y: 0)])
        // Up 10 thickens the centered shaft by 20 (of 100); left 20 lengthens the head by 20 (of the short side, 100).
        #expect(drag("rightArrow", handle: "adj1", to: 0, 15) == ["adj1": 70000])
        #expect(drag("rightArrow", handle: "adj2", to: 130, 0) == ["adj2": 70000])
        #expect(drag("rightArrow", handle: "adj2", to: 175, 60) == ["adj2": 25000])
        // Limits: the shaft can't get thinner than nothing; the head can't outgrow the arrow (maxAdj2 = 100000 · w / ss).
        #expect(drag("rightArrow", handle: "adj1", to: 0, 80) == ["adj1": 0])
        #expect(drag("rightArrow", handle: "adj2", to: -100, 0) == ["adj2": 200000])
        // The other value is kept.
        #expect(drag("rightArrow", ["adj1": 40000, "adj2": 30000], handle: "adj2", to: 150, 0) == ["adj1": 40000, "adj2": 50000])
    }

    @Test func calloutTailsFollowBothAxes() {
        let handles = PresetGeometry.handles(for: .preset("wedgeRectCallout", adjustments: [:]), in: wide)
        #expect(handles.map(\.name) == ["adj1"])
        #expect(close(handles[0].position, CGPoint(x: 100 - 41.666, y: 112.5)))
        // The tip is (hc + w · adj1, vc + h · adj2) in 100000ths, with no practical limits.
        #expect(drag("wedgeRectCallout", handle: "adj1", to: 250, -30) == ["adj1": 75000, "adj2": -80000])
        #expect(drag("wedgeEllipseCallout", handle: "adj1", to: 100, 150) == ["adj1": 0, "adj2": 100000])
        #expect(drag("cloudCallout", handle: "adj1", to: 0, 0) == ["adj1": -50000, "adj2": -50000])
    }

    @Test func polarHandlesFollowTheAngleAndTheRadius() {
        // The arc's ends: only the angle around the center counts, in 60000ths of a degree clockwise.
        #expect(drag("arc", handle: "adj1", to: -50, 50) == ["adj1": 10_800_000])
        #expect(drag("arc", handle: "adj2", to: 130, 80) == ["adj2": 2_700_000])
        #expect(drag("arc", handle: "adj2", to: 100, 0) == ["adj2": 16_200_000])
        // A block arc's inner handle sets the angle and the thickness (adj3, as a share of the short side).
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(drag("blockArc", in: square, handle: "adj2", to: 50, 80) == ["adj2": 5_400_000, "adj3": 20000])
        #expect(drag("blockArc", in: square, handle: "adj2", to: 50, 52) == ["adj2": 5_400_000, "adj3": 48000])
        #expect(drag("blockArc", in: square, handle: "adj2", to: 50, 200) == ["adj2": 5_400_000, "adj3": 0])
        #expect(drag("blockArc", in: square, handle: "adj1", to: 0, 0) == ["adj1": 13_500_000])
        // The pie's angles wrap around: up and to the left is 225°.
        #expect(drag("pie", handle: "adj2", to: 50, 0) == ["adj2": 13_500_000])
    }
}
