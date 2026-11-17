import Foundation
import Testing
@testable import PuggleSlidesKit

/// Reads the .pptx files in `PUGGLESLIDES_PPTX_INSPECT` (paths separated by ":") and prints their structure:
/// counts, kinds, warnings and timing, never their text. Skipped unless the variable is set.
struct PPTXInspectionTests {
    static let paths = ProcessInfo.processInfo.environment["PUGGLESLIDES_PPTX_INSPECT"]?.split(separator: ":").map(String.init)

    @Test(.enabled(if: paths != nil))
    func inspectFiles() throws {
        var files: [String] = []
        var summaries = 0
        for path in Self.paths ?? [] {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                // A folder: every deck in it, summarized.
                let names = (try FileManager.default.contentsOfDirectory(atPath: path)).filter { $0.hasSuffix(".pptx") }.sorted()
                summaries += 1
                try summarize(names.map { (path as NSString).appendingPathComponent($0) })
            } else {
                files.append(path)
            }
        }
        if summaries > 0, files.isEmpty { return }
        for path in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let clock = ContinuousClock()
            var file: PresentationFile?
            let elapsed = try clock.measure { file = try PresentationIO.read(data, format: .pptx) }
            let presentation = try #require(file).presentation
            print("\(data.count) bytes read in \(elapsed); warnings: \(file!.warnings.map(\.rawValue).sorted())")
            print("slide size \(presentation.slideSize.width) × \(presentation.slideSize.height); title set: \(presentation.title != nil); media: \(presentation.media.count)")
            for theme in presentation.themes {
                print("theme: \(theme.elements.count) elements (\(theme.elements.compactMap(\.placeholder?.type.rawValue))), "
                    + "\(theme.layouts.count) layouts: \(theme.layouts.map(\.kind.rawValue))")
            }
            for (index, slide) in presentation.slides.enumerated() {
                func describe(_ element: SlideElement) -> String {
                    switch element.content {
                    case .shape(let shape):
                        let kind = element.placeholder.map { "ph:\($0.type.rawValue)" } ?? (shape.isConnector ? "connector" : shape.isTextBox ? "textbox" : "shape")
                        let paragraphs = shape.text?.paragraphs.count ?? 0
                        return "\(kind)[\(shape.geometry.presetName ?? "custom"), \(paragraphs)¶\(element.placement == nil ? ", inherits place" : "")]"
                    case .picture: return "picture"
                    case .group(let children): return "group(\(children.map(describe).joined(separator: ", ")))"
                    case .table(let table): return "table[\(table.rowCount)×\(table.columnCount)]"
                    case .chart(let chart): return "chart[\(chart.kind.rawValue)]"
                    case .media(let clip): return "media[\(clip.kind.rawValue)]"
                    }
                }
                print("slide \(index + 1): layout \(presentation.layout(for: slide)?.kind.rawValue ?? "?"), skipped \(slide.isSkipped), "
                    + "notes ¶\(slide.notes.isEmpty ? 0 : slide.notes.paragraphs.count): \(slide.elements.map(describe).joined(separator: ", "))")
                for element in slide.elements {
                    let style = presentation.style(for: element, on: slide)
                    let paragraphs = style.resolvedParagraphs()
                    guard let run = paragraphs.first?.runs.first else { continue }
                    print("   first run: \(run.style.fontFamily) \(run.style.fontSize)pt color \(run.style.color.rgb.hex), autofit \(style.bodyProperties.autofit)")
                }
            }
            // And it writes back.
            let written = try PresentationIO.write(presentation, format: .pptx)
            let again = try PresentationIO.read(written, format: .pptx)
            print("rewritten: \(written.count) bytes, \(again.presentation.slides.count) slides, warnings \(again.warnings.map(\.rawValue).sorted())")
            if let folder = ProcessInfo.processInfo.environment["PUGGLESLIDES_PPTX_SAMPLES"] {
                try written.write(to: URL(fileURLWithPath: folder).appendingPathComponent("inspected-rewrite.pptx"))
            }
        }
    }

    /// Reads, writes and reads again every deck, and prints totals: what read, what was refused, the warnings,
    /// and the motion found.
    private func summarize(_ paths: [String]) throws {
        var read = 0, refused: [String: Int] = [:], warnings: [String: Int] = [:], rewriteFailures = 0
        var transitions: [String: Int] = [:], effects: [String: Int] = [:], starts: [String: Int] = [:]
        var slides = 0, animated = 0, motionLost = 0
        var motionWarnings: [String] = []
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for path in paths {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
                do {
                    let file = try PresentationIO.read(data, format: .pptx)
                    read += 1
                    for warning in file.warnings { warnings[warning.rawValue, default: 0] += 1 }
                    let motion = file.warnings.intersection([.animations, .transitions])
                    if !motion.isEmpty { motionWarnings.append("\((path as NSString).lastPathComponent) \(motion.map(\.rawValue).sorted())") }
                    for slide in file.presentation.slides {
                        slides += 1
                        if let transition = slide.transition { transitions[transition.kind.rawValue, default: 0] += 1 }
                        if !slide.animations.isEmpty { animated += 1 }
                        for animation in slide.animations {
                            effects[animation.effect.rawValue, default: 0] += 1
                            starts[animation.start.rawValue, default: 0] += 1
                        }
                    }
                    do {
                        let again = try PresentationIO.read(try PresentationIO.write(file.presentation, format: .pptx), format: .pptx)
                        if again.presentation.slides.map(\.animations.count) != file.presentation.slides.map(\.animations.count)
                            || again.presentation.slides.map(\.transition) != file.presentation.slides.map(\.transition) {
                            motionLost += 1
                        }
                    } catch {
                        rewriteFailures += 1
                    }
                } catch {
                    refused[(error as? PresentationIOError)?.errorDescription ?? "\(error)", default: 0] += 1
                }
            }
        }
        print("\(paths.count) decks in \(elapsed): \(read) read, refused \(refused), rewrite failures \(rewriteFailures), motion changed on rewrite \(motionLost)")
        print("warnings: \(warnings.sorted { $0.key < $1.key })")
        print("\(slides) slides, \(animated) animated; transitions \(transitions.sorted { $0.key < $1.key })")
        print("effects \(effects.sorted { $0.key < $1.key }); starts \(starts.sorted { $0.key < $1.key })")
        print("motion warnings: \(motionWarnings.joined(separator: ", "))")
    }
}
