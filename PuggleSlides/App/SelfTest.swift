#if DEBUG
import AppKit
import PuggleSlidesKit

/// `-PPSelfTest YES`: drives a real presentation window and prints SELFTEST PASS/FAIL lines.
/// Each step runs in its own turn of the run loop, so each is its own undo step, as for a person.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "PPSelfTest") else { return }
        if UserDefaults.standard.string(forKey: "PPSelfTestSuite") == "collaboration" {
            CollaborationSelfTest.run()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
    }

    private static var failures = 0
    private static var steps: [() -> Void] = []

    static func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("SELFTEST PASS: \(name)")
        } else {
            failures += 1
            print("SELFTEST FAIL: \(name) — \(detail())")
        }
        fflush(stdout)
    }

    static func step(_ body: @escaping () -> Void) { steps.append(body) }

    /// Holds the next step until `condition` holds or `timeout` seconds pass, for work that finishes later.
    private static var holding: (condition: () -> Bool, deadline: Date)?

    static func wait(upTo timeout: Double = 5, until condition: @escaping () -> Bool) {
        holding = (condition, Date().addingTimeInterval(timeout))
    }

    private static func continueSteps(from index: Int) {
        if let hold = holding, !hold.condition(), Date() < hold.deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { continueSteps(from: index) }
            return
        }
        holding = nil
        runSteps(from: index)
    }

    private static func runSteps(from index: Int = 0) {
        guard index < steps.count else {
            print(failures == 0 ? "SELFTEST DONE: all passed" : "SELFTEST DONE: \(failures) failed")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        steps[index]()
        // Steps run from timers, not events, and AppKit closes the undo group an edit opened only after
        // handling an event. An empty application event ends the step as a key press or click would.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { continueSteps(from: index + 1) }
    }

    /// Types into whatever has keyboard focus with real key events, as a person would.
    static func type(_ text: String, into window: NSWindow?, modifiers: NSEvent.ModifierFlags = []) {
        for character in text {
            let string = String(character)
            let code: UInt16 = character == "\r" ? 36 : (character == "\t" ? 48 : (character == "\u{1B}" ? 53 : 0))
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                               windowNumber: window?.windowNumber ?? 0, context: nil,
                                               characters: string, charactersIgnoringModifiers: string,
                                               isARepeat: false, keyCode: code) else { continue }
            window?.firstResponder?.keyDown(with: event)
        }
    }

    static func key(_ scalar: Int, modifiers: NSEvent.ModifierFlags = [], to responder: NSResponder?, window: NSWindow?) {
        let string = String(UnicodeScalar(UInt32(scalar))!)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                           windowNumber: window?.windowNumber ?? 0, context: nil, characters: string,
                                           charactersIgnoringModifiers: string, isARepeat: false, keyCode: 0) else { return }
        responder?.keyDown(with: event)
    }

    /// Sends a mouse event to the canvas at a slide point.
    static func mouse(_ type: NSEvent.EventType, at point: SlidePoint, in window: DocumentWindowController,
                              clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        let canvas = window.canvas
        let location = canvas.convert(canvas.viewPoint(point), to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: 0,
                                             windowNumber: window.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                                             clickCount: clickCount, pressure: 1) else { return }
        switch type {
        case .leftMouseDown: canvas.mouseDown(with: event)
        case .leftMouseDragged: canvas.mouseDragged(with: event)
        case .leftMouseUp: canvas.mouseUp(with: event)
        default: break
        }
    }

    static func drag(from start: SlidePoint, to end: SlidePoint, in window: DocumentWindowController, modifiers: NSEvent.ModifierFlags = []) {
        mouse(.leftMouseDown, at: start, in: window, modifiers: modifiers)
        for step in 1...4 {
            let t = Double(step) / 4
            mouse(.leftMouseDragged, at: SlidePoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), in: window, modifiers: modifiers)
        }
        mouse(.leftMouseUp, at: end, in: window, modifiers: modifiers)
    }

    private static func run() {
        // A fresh presentation of its own, so documents macOS restored at launch are left alone.
        let existing = Set(NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }.map(ObjectIdentifier.init))
        NSDocumentController.shared.newDocument(nil)
        guard let window = NSApp.windows.compactMap({ $0.windowController as? DocumentWindowController })
            .first(where: { !existing.contains(ObjectIdentifier($0)) }) else {
            print("SELFTEST FAIL: no presentation window")
            exit(1)
        }
        let controller = window.controller
        let canvas = window.canvas
        window.window?.makeKeyAndOrderFront(nil)
        window.window?.makeFirstResponder(canvas)
        var presentation: Presentation { controller.presentation }
        var slide: Slide { controller.currentSlide! }
        func text(_ index: Int) -> String { slide.elements[index].shape?.text?.plainText ?? "<none>" }
        func placement(_ element: SlideElement) -> Placement { controller.placement(of: element) }

        // A new presentation starts with one title slide, with a title and a subtitle.
        step {
            check(presentation.slides.count == 1 && presentation.layout(for: slide)?.kind == .title, "a new presentation has one title slide")
            check(slide.elements.compactMap(\.placeholder?.type) == [.centeredTitle, .subtitle], "the title slide has a title and a subtitle",
                  "\(slide.elements.compactMap(\.placeholder?.type))")
            check(window.state.title.hasPrefix("Untitled presentation"), "the header says Untitled presentation", window.state.title)
            // Clicking an empty placeholder goes straight into its text.
            let title = placement(slide.elements[0]).frame
            mouse(.leftMouseDown, at: title.center, in: window)
            mouse(.leftMouseUp, at: title.center, in: window)
        }
        step {
            check(canvas.editor?.elementID == slide.elements[0].id, "a click in the title starts editing it")
            type("Hello, slides", into: window.window)
        }
        step {
            canvas.endEditing()
            check(text(0) == "Hello, slides", "typing fills the title", text(0))
            check(slide.elements[0].placement == nil, "the title keeps the layout's position")
            check(slide.elements[0].shape?.text?.paragraphs.first?.runs.first?.style == CharacterStyle(), "typed text inherits its look",
                  "\(String(describing: slide.elements[0].shape?.text?.paragraphs.first?.runs.first?.style))")
            controller.undoManager?.undo()
        }
        step {
            check(text(0).isEmpty, "undo removes the typing", text(0))
            controller.undoManager?.redo()
        }
        step {
            check(text(0) == "Hello, slides", "redo puts it back", text(0))
            // New slide (⌃M) after a title slide uses "Title and body".
            window.ppNewSlide(nil)
        }
        step {
            check(presentation.slides.count == 2, "New slide adds a slide", "\(presentation.slides.count)")
            check(presentation.layout(for: slide)?.kind == .titleAndBody, "after a title slide the new slide is Title and body",
                  "\(String(describing: presentation.layout(for: slide)?.kind))")
            check(controller.currentSlideIndex == 1, "the new slide is current")
            canvas.beginEditing(slide.elements[1].id, at: nil)
            type("Walks\rNaps", into: window.window)
        }
        step {
            guard let editor = canvas.editor else { return check(false, "editing the body") }
            editor.textView.setSelectedRange(NSRange(location: 0, length: 5))
            window.toggleBold()
            check(editor.selectedEffectiveStyles.allSatisfy { $0.bold == true }, "bold applies to selected text while editing")
            editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
            editor.indentIfList(by: 1) ? () : check(false, "Tab indents a list paragraph")
        }
        step {
            canvas.endEditing()
            let body = slide.elements[1].shape?.text
            check(body?.paragraphs.map(\.text) == ["Walks", "Naps"], "Return makes a new paragraph", "\(body?.paragraphs.map(\.text) ?? [])")
            check(body?.paragraphs.first?.runs.first?.style.bold == true, "bold is stored on the run")
            check(body?.paragraphs.last?.level == 1, "the second paragraph is indented one level", "\(body?.paragraphs.last?.level ?? -1)")
            let resolved = presentation.style(for: slide.elements[1], on: slide).resolvedParagraphs()
            check(resolved.map(\.bullet?.text) == ["●", "○"], "body text is bulleted by level", "\(resolved.map(\.bullet?.text))")
        }

        // Shapes: draw one with the Shape tool, then move, resize, rotate and color it.
        step {
            window.setTool(.shape("rect"))
            drag(from: SlidePoint(x: 100, y: 200), to: SlidePoint(x: 220, y: 280), in: window)
        }
        step {
            let shape = slide.elements.last
            check(shape?.shape?.geometry.presetName == "rect", "the Shape tool draws a rectangle")
            let frame = shape.map { placement($0).frame } ?? .zero
            check(abs(frame.x - 100) < 0.01 && abs(frame.y - 200) < 0.01 && abs(frame.width - 120) < 0.01 && abs(frame.height - 80) < 0.01,
                  "the shape spans the drag", "\(frame)")
            check(controller.selectedElementIDs == [shape!.id], "the new shape is selected")
            check(window.state.tool == .select, "the tool goes back to Select")
            drag(from: SlidePoint(x: 160, y: 240), to: SlidePoint(x: 200, y: 260), in: window)
        }
        step {
            let frame = placement(slide.elements.last!).frame
            check(abs(frame.x - 140) < 0.01 && abs(frame.y - 220) < 0.01, "dragging moves the shape", "\(frame)")
            controller.undoManager?.undo()
        }
        step {
            check(abs(placement(slide.elements.last!).frame.x - 100) < 0.01, "undo moves it back")
            // The bottom-right handle resizes.
            drag(from: SlidePoint(x: 220, y: 280), to: SlidePoint(x: 260, y: 300), in: window)
        }
        step {
            let frame = placement(slide.elements.last!).frame
            check(abs(frame.width - 160) < 0.01 && abs(frame.height - 100) < 0.01, "a corner handle resizes", "\(frame)")
            key(NSRightArrowFunctionKey, modifiers: .option, to: canvas, window: window.window)
        }
        step {
            check(placement(slide.elements.last!).rotation == 15, "⌥→ rotates by 15°", "\(placement(slide.elements.last!).rotation)")
            window.applyColor(ColorRef(theme: .accent4), to: .fill)
            window.ppBorderWeight(NSMenuItem(title: "", action: nil, keyEquivalent: "").withTag(4))
        }
        step {
            let shape = slide.elements.last?.shape
            check(shape?.fill == .solid(ColorRef(theme: .accent4)), "fill color takes a theme color")
            check(shape?.outline?.width == 3, "border weight is in pixels (4 px = 3 pt)", "\(shape?.outline?.width ?? 0)")
            key(NSRightArrowFunctionKey, to: canvas, window: window.window)
        }
        step {
            check(abs(placement(slide.elements.last!).frame.x - 100.75) < 0.01, "arrow keys nudge by one pixel", "\(placement(slide.elements.last!).frame.x)")
            // Typing with a shape selected starts editing its text.
            type("Hi", into: window.window)
        }
        step {
            canvas.endEditing()
            check(slide.elements.last?.shape?.text?.plainText == "Hi", "typing on a selected shape edits its text",
                  slide.elements.last?.shape?.text?.plainText ?? "")
            let resolved = presentation.style(for: slide.elements.last!, on: slide).resolvedParagraphs()
            check(resolved.first?.alignment == .center && resolved.first?.runs.first?.style.fontSize == 14, "shape text is centered at 14 pt")
        }

        // The rotation handle turns a shape; Shift snaps it to 15°.
        step {
            let shape = slide.elements.last!
            controller.selectElements([shape.id])
            guard let handle = canvas.handles().first(where: { $0.0 == .rotate })?.1 else { return check(false, "a rotation handle") }
            let center = placement(shape).frame.center
            // A quarter turn clockwise from the handle, about the center.
            let dx = handle.x - center.x, dy = handle.y - center.y
            let target = SlidePoint(x: center.x - dy, y: center.y + dx)
            drag(from: SlidePoint(handle), to: target, in: window, modifiers: .shift)
        }
        step {
            let rotation = placement(slide.elements.last!).rotation
            check(abs(rotation - 105) < 0.01, "dragging the rotation handle turns the shape, in 15° steps with Shift", "\(rotation)")
            window.ppRotate(NSMenuItem().withTag(-105))
        }

        // Yellow handles adjust a shape: a rounded rectangle's corners.
        step {
            window.setTool(.shape("roundRect"))
            drag(from: SlidePoint(x: 450, y: 250), to: SlidePoint(x: 600, y: 350), in: window)
        }
        step {
            let shape = slide.elements.last!
            let before = (shape.shape?.geometry).flatMap { if case .preset(_, let values) = $0 { values["adj"] } else { nil } } ?? 16667
            guard let handle = canvas.handles().first(where: { if case .adjust = $0.0 { true } else { false } })?.1 else {
                return check(false, "a rounded rectangle has a yellow handle")
            }
            drag(from: SlidePoint(handle), to: SlidePoint(x: handle.x + 30, y: handle.y), in: window)
            let after = (slide.elements.last?.shape?.geometry).flatMap { if case .preset(_, let values) = $0 { values["adj"] } else { nil } } ?? before
            check(after > before + 1000, "dragging the yellow handle rounds the corners more", "\(before) → \(after)")
            controller.deleteSelectedElements()
        }

        // Text boxes grow to fit their text.
        step {
            window.setTool(.textBox)
            mouse(.leftMouseDown, at: SlidePoint(x: 400, y: 60), in: window)
            mouse(.leftMouseUp, at: SlidePoint(x: 400, y: 60), in: window)
        }
        step {
            check(canvas.editor != nil, "a click with the Text box tool starts a text box")
            type("One\rTwo\rThree", into: window.window)
        }
        step {
            let box = slide.elements.last!
            canvas.endEditing()
            let frame = placement(slide.elements.last!).frame
            check(box.shape?.isTextBox == true && frame.height > 60, "a text box grows as lines are added", "\(frame)")
            // An empty new text box disappears.
            let count = slide.elements.count
            window.setTool(.textBox)
            mouse(.leftMouseDown, at: SlidePoint(x: 500, y: 300), in: window)
            mouse(.leftMouseUp, at: SlidePoint(x: 500, y: 300), in: window)
            canvas.endEditing()
            check(slide.elements.count == count, "an empty new text box is removed", "\(slide.elements.count) vs \(count)")
        }

        // Copy, paste, duplicate, group and order.
        step {
            let shapeID = slide.elements.first { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" && $0.shape?.isTextBox == false }!.id
            controller.selectElements([shapeID])
            window.window?.makeFirstResponder(canvas)
            window.copy(nil)
            let count = slide.elements.count
            window.paste(nil)
            check(slide.elements.count == count + 1, "copy and paste adds a shape")
            let pasted = placement(slide.elements.last!).frame, original = placement(slide.element(id: shapeID)!).frame
            check(abs(pasted.x - original.x - 9) < 0.01 && slide.elements.last?.shape?.geometry.presetName == "rect", "the copy is offset",
                  "\(pasted) vs \(original), \(slide.elements.last?.name ?? "")")
            window.ppDuplicate(nil)
            check(slide.elements.count == count + 2, "⌘D duplicates the shape")
            let two = Array(slide.elements.suffix(2).map(\.id))
            controller.selectElements(two)
            window.ppGroup(nil)
            check(slide.elements.last?.children?.count == 2, "Group combines the selection")
            window.ppUngroup(nil)
            check(slide.elements.suffix(2).allSatisfy { $0.children == nil } && controller.selectedElementIDs.count == 2, "Ungroup releases them")
            controller.selectElements([slide.elements.last!.id])
            let last = slide.elements.last!.id
            window.ppOrder(NSMenuItem().withTag(3))
            check(slide.elements.first?.id == last, "Send to back moves it behind everything")
        }

        // Slides: duplicate, move, skip and delete.
        step {
            window.window?.makeFirstResponder(window.filmstrip)
            window.ppDuplicateSlide(nil)
            check(presentation.slides.count == 3 && controller.currentSlideIndex == 2, "Duplicate slide adds a copy after it")
        }
        step {
            window.ppMoveSlide(NSMenuItem().withTag(0))
            check(controller.currentSlideIndex == 0, "Move slide to beginning")
        }
        step {
            window.ppSkipSlide(nil)
            check(slide.isSkipped, "Skip slide")
        }
        step {
            window.ppDeleteSlide(nil)
            check(presentation.slides.count == 2, "Delete slide")
        }
        step {
            controller.undoManager?.undo()
            check(presentation.slides.count == 3, "undo brings the slide back", "\(presentation.slides.count)")
        }

        // Speaker notes.
        step {
            controller.selectSlide(presentation.slides[0].id)
            window.window?.makeFirstResponder(window.notes.textView)
            type("Remember the treats", into: window.window)
            window.window?.makeFirstResponder(canvas)
            check(presentation.slides[0].notes.plainText == "Remember the treats", "speaker notes are saved",
                  presentation.slides[0].notes.plainText)
        }

        // Layouts and themes.
        step {
            controller.selectSlide(presentation.slides[2].id)
            let titleOnly = presentation.theme(for: slide).layout(kind: .titleOnly)!.id
            window.controller.applyLayout(titleOnly)
            check(presentation.layout(for: slide)?.kind == .titleOnly, "Apply layout")
            check(slide.elements.contains { $0.placeholder == nil && $0.shape?.text?.plainText == "Walks\nNaps" },
                  "text from a placeholder the layout lacks stays as a text box")
            controller.applyTheme(BuiltInThemes.simpleDark())
            check(presentation.themes.count == 1 && presentation.themes[0].name == "Simple Dark", "Change theme")
            check(presentation.layout(for: slide)?.kind == .titleOnly, "slides keep their layout kind in the new theme")
        }

        // Typing, then picking another slide in the filmstrip, saves the text on the slide it was typed on.
        step {
            controller.selectSlide(presentation.slides[0].id)
            canvas.beginEditing(slide.elements[1].id, at: nil)
            type("Subtitle here", into: window.window)
        }
        step {
            controller.selectSlide(presentation.slides[1].id)
            check(presentation.slides[0].elements[1].shape?.text?.plainText == "Subtitle here", "switching slides keeps text being typed",
                  presentation.slides[0].elements[1].shape?.text?.plainText ?? "")
            check(controller.undoManager?.undoActionName == "Typing", "a finished edit is one Typing step", controller.undoManager?.undoActionName ?? "")
            check(canvas.editor == nil && controller.currentSlideIndex == 1, "editing ends on the old slide")
        }

        // Paint format, align, lists, backgrounds and slide numbers.
        step {
            controller.selectSlide(presentation.slides[2].id)
            let shapes = slide.elements.filter { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" }
            guard shapes.count >= 2 else { return check(false, "two rectangles to work with", "\(shapes.count)") }
            controller.selectElements([shapes[0].id])
            window.applyColor(ColorRef(theme: .accent6), to: .fill)
        }
        step {
            let shapes = slide.elements.filter { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" }
            controller.selectElements([shapes[0].id])
            window.togglePaintFormat()
            check(window.state.isPaintFormatActive, "Paint format picks up a shape's look")
            mouse(.leftMouseDown, at: placement(shapes[1]).frame.center, in: window)
            mouse(.leftMouseUp, at: placement(shapes[1]).frame.center, in: window)
        }
        step {
            let shapes = slide.elements.filter { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" }
            check(shapes[1].shape?.fill == .solid(ColorRef(theme: .accent6)), "Paint format gives the next shape clicked the same fill")
            check(!window.state.isPaintFormatActive, "Paint format turns off after one use")
            controller.selectElements(shapes.map(\.id))
            window.ppArrangeAlign(NSMenuItem().withTag(0))
        }
        step {
            let shapes = slide.elements.filter { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" }
            let lefts = shapes.map { placement($0).boundingBox.minX }
            check(lefts.allSatisfy { abs($0 - lefts[0]) < 0.01 }, "Align ▸ Left lines up the selection's left edges", "\(lefts)")
            controller.selectElements([shapes[0].id])
            window.toggleList(numbered: true)
        }
        step {
            let shapes = slide.elements.filter { $0.placeholder == nil && $0.shape?.geometry.presetName == "rect" }
            let resolved = presentation.style(for: shapes[0], on: slide).resolvedParagraphs()
            check(resolved.first?.bullet?.text == "1.", "the numbered list button numbers a selected shape's text", resolved.first?.bullet?.text ?? "nil")
            window.controller.setBackground(.solid(ColorRef(theme: .accent3)))
            window.controller.setSlideNumbers(true, skipTitleSlides: true, onlySelected: false)
        }
        step {
            check(presentation.background(for: slide) == .solid(ColorRef(theme: .accent3)), "Change background colors the slide")
            check(presentation.slides.map { $0.elements.contains { $0.placeholder?.type == .slideNumber } }
                  == presentation.slides.map { presentation.layout(for: $0)?.kind != .title }, "slide numbers skip title slides")
            controller.setSlideSize(.standard)
            check(presentation.slideSize == .standard, "Page setup changes the slide size")
            let size = presentation.slideSize
            check(slide.elements.allSatisfy { placement($0).boundingBox.maxX <= size.width + 1 }, "elements scale with the page")
        }
        step {
            controller.undoManager?.undo()
            check(presentation.slideSize == .widescreen, "undo restores the page size")
            let count = slide.elements.count
            _ = controller.insertImage(data: SampleContent.sampleImage())
            check(slide.elements.count == count + 1 && slide.elements.last?.picture != nil, "Insert ▸ Image adds a picture")
            check(presentation.media.count == 1, "the image is stored once")
        }

        // Slideshow.
        step {
            window.startSlideshow(fromBeginning: true)
            guard let show = SlideshowController.current else { return check(false, "the slideshow starts") }
            check(show.order.count == 2, "skipped slides are left out of the slideshow", "\(show.order)")
            show.next()
            check(show.currentSlideIndex == 2, "next goes to the following slide that isn't skipped", "\(show.currentSlideIndex)")
            show.next()
            check(show.currentSlideIndex == 2, "next stays on the last slide")
            show.end()
            check(controller.currentSlideIndex == 2 && SlideshowController.current == nil, "ending the slideshow shows its slide")
        }

        // Zoom.
        step {
            window.setZoom(2)
            check(abs(window.canvasScroll.magnification - 2 * Theme.baseMagnification) < 0.01, "zoom 200% is twice a browser's 100%")
            window.setZoom(nil)
            check(window.state.zoomIsFit, "Fit")
        }
        step { runPPTXChecks(window) }
        addMotionSteps(window)
        addOutputSteps(window)
        addPhase3Steps(window)
        addPhase4Steps(window)
        addPhase5Steps(window)
        addTypingSteps(window)

        DispatchQueue.main.async { runSteps() }
    }

    /// Transitions, animations, the slideshow that plays them, presenter view and grid view.
    private static func addMotionSteps(_ window: DocumentWindowController) {
        let controller = window.controller
        var slide: Slide { controller.currentSlide! }
        var animationIDs: [UUID] = []
        step {
            let theme = controller.presentation.theme(for: slide)
            controller.newSlide(layoutID: theme.layout(kind: .titleAndBody)?.id)
            controller.setTransition(SlideTransition(kind: .cube, duration: 1.2))
            check(slide.transition == SlideTransition(kind: .cube, duration: 1.2), "Motion sets the slide's transition")
            check(controller.presentation.slides.filter { $0.transition != nil }.count == 1, "the transition is only on the selected slide")
        }
        step {
            controller.applyTransitionToAllSlides()
            check(controller.presentation.slides.allSatisfy { $0.transition?.kind == .cube }, "Apply to all slides")
        }
        step {
            controller.undoManager?.undo()
            check(controller.presentation.slides.filter { $0.transition != nil }.count == 1, "undo takes back Apply to all slides")
            controller.setTransition(SlideTransition(kind: .none))
        }
        step {
            check(slide.transition == nil, "No transition removes it")
            controller.undoManager?.undo()
        }
        step {
            check(slide.transition?.kind == .cube, "undo brings the transition back")
            controller.selectElements([slide.elements[0].id])
            if let id = controller.addAnimation() { animationIDs.append(id) }
            check(slide.animations.count == 1 && slide.animations[0].effect == .appear && slide.animations[0].start == .onClick,
                  "Insert ▸ Animation adds Appear on click", "\(slide.animations)")
            check(controller.hasMotion(slide), "the filmstrip marks a slide with motion")
        }
        step {
            controller.updateAnimation(animationIDs[0]) { $0.effect = .fadeIn; $0.start = .afterPrevious; $0.duration = 0.8 }
            check(slide.animations[0].effect == .fadeIn && slide.animations[0].start == .afterPrevious && slide.animations[0].duration == 0.8,
                  "the Motion panel changes an animation")
            if let id = controller.addAnimation(for: slide.elements[1].id) { animationIDs.append(id) }
        }
        step {
            controller.moveAnimation(animationIDs[1], to: 0)
            check(slide.animations.map(\.id) == [animationIDs[1], animationIDs[0]], "dragging reorders animations")
            controller.selectElements([slide.elements[1].id])
            controller.deleteSelectedElements()
        }
        step {
            check(slide.animations.map(\.id) == [animationIDs[0]], "deleting an object deletes its animations", "\(slide.animations.count)")
            controller.undoManager?.undo()
        }
        step {
            check(slide.animations.count == 2, "undo brings the object's animation back")
            controller.deleteAnimation(animationIDs[0])
            check(slide.animations.map(\.id) == [animationIDs[1]], "an animation's delete button")
        }

        // The animation timeline: what comes before the first click plays by itself.
        step {
            let sample = SampleContent.make()
            let timeline = AnimationTimeline(slide: sample.slides[1], presentation: sample)
            let title = sample.slides[1].elements[0].id, body = sample.slides[1].elements[1].id
            let paragraphs = sample.slides[1].elements[1].shape?.text?.paragraphs.count ?? 0
            check(timeline.groups.count == 1 + paragraphs, "by paragraph, each paragraph waits for its own click", "\(timeline.groups.count)")
            check(timeline.initialStates[title]?.isHidden == true, "an entrance hides its object until it plays")
            check(timeline.initialStates[body]?.paragraphs?.allSatisfy(\.isHidden) == true, "paragraphs start hidden")
            let opened = timeline.states(group: 0, time: .infinity)
            check(opened[title]?.isHidden == false && opened[title]?.opacity == 1, "After previous plays as the slide opens")
            let flying = timeline.states(group: 1, time: 0.2)
            check((flying[body]?.paragraphs?[0].offset.width ?? 0) < 0, "Fly in from left starts off to the left")
            check(flying[body]?.paragraphs?[1].isHidden == true, "the next paragraph waits")
            let landed = timeline.states(group: 1, time: .infinity)
            check(landed[body]?.paragraphs?[0].offset == .zero && landed[body]?.paragraphs?[0].isHidden == false, "a paragraph lands in place")

            // A slideshow of the sample deck: Next finishes what's playing, then starts the next click.
            guard let show = SlideshowController.start(sample, from: 1, on: NSScreen.main) else { return check(false, "the sample slideshow starts") }
            check(show.playedGroups == 1, "the opening group plays by itself")
            show.next()
            check(show.playedGroups == 1 && show.currentStates()[title]?.opacity == 1, "Next finishes the opening animation")
            show.next()
            check(show.playedGroups == 2, "Next starts the next click's animation")
            for _ in 0..<(paragraphs * 2) { show.next() }
            check(show.currentSlideIndex == 2, "after the last click, Next goes to the next slide", "\(show.currentSlideIndex)")
            show.previous()
            check(show.currentSlideIndex == 1 && show.playedGroups == show.timeline.groups.count, "Previous shows the slide fully built")
            show.end()
        }
        step {
            let sample = SampleContent.make()
            guard let show = SlideshowController.start(sample, from: 2, on: NSScreen.main) else { return check(false, "the sample slideshow starts") }
            show.next()
            check(show.transition?.kind == .cube && show.currentSlideIndex == 3, "moving to a slide plays its transition")
            show.next()
            check(show.transition == nil, "Next finishes a transition")
            show.end()
        }
        weak var endedShow: SlideshowController?
        weak var endedPresenter: PresenterWindowController?
        step {
            guard let show = SlideshowController.start(SampleContent.make(), from: 0, on: NSScreen.main, presenterView: true) else {
                return check(false, "presenter view starts")
            }
            check(show.presenter?.window?.isVisible == true, "Presenter view opens its window")
            show.next()
            check(show.state.position == 1, "the presenter view follows the show")
            endedShow = show
            endedPresenter = show.presenter
            show.end()
            check(NSApp.windows.allSatisfy { !($0 is PresenterPanel) || !$0.isVisible }, "ending the show closes presenter view")
        }
        step {
            // A finished show lets go of its copy of the presentation, pictures and all.
            check(endedShow == nil, "a finished slideshow is released")
            check(endedPresenter == nil, "a closed presenter view is released")
        }
        step {
            window.setGridView(true)
            check(window.isGridView && window.grid.columns > 1, "Grid view shows slides in columns", "\(window.grid.columns)")
            window.setGridView(false)
            check(!window.isGridView, "Grid view closes")
        }
    }

    /// Printing and File ▸ Download.
    private static func addOutputSteps(_ window: DocumentWindowController) {
        step {
            let sample = SampleContent.make()
            let shown = sample.slides.filter { !$0.isSkipped }.count
            check(PrintPagesView(presentation: sample, settings: SlidePrintSettings()).pages.count == shown, "printing leaves out skipped slides")
            var settings = SlidePrintSettings()
            settings.includesSkipped = true
            check(PrintPagesView(presentation: sample, settings: settings).pages.count == sample.slides.count, "Include skipped slides")
            settings.layout = .handout(6)
            check(PrintPagesView(presentation: sample, settings: settings).pages.count == (sample.slides.count + 5) / 6, "handouts of 6 per page")
            settings.layout = .slidesWithNotes
            check(PrintPagesView(presentation: sample, settings: settings).pageSize == CGSize(width: 612, height: 792), "notes pages are letter size")
            let pdf = PrintPagesView(presentation: sample, settings: SlidePrintSettings()).pdfData()
            let document = CGDataProvider(data: pdf as CFData).flatMap(CGPDFDocument.init)
            check(document?.numberOfPages == shown, "a PDF has a page per slide", "\(document?.numberOfPages ?? -1)")
            check(sample.plainText.contains("Highlights\nWalks are up 24% since spring"), "Plain text lists each slide's text")
            let svg = SVGExport.svg(for: sample.slides[3], number: 4, in: sample)
            check(XMLParser(data: Data(svg.utf8)).parse(), "an SVG slide is well-formed XML")
            check(svg.contains(">Shapes and lines</text>") && svg.contains("<path"), "an SVG slide has its text and shapes")
            do {
                // The sample deck's motion survives PowerPoint.
                func motion(_ presentation: Presentation) -> [[String]] {
                    presentation.slides.map { slide in
                        slide.animations.map { "\($0.effect) \($0.start) \($0.duration) \($0.byParagraph)" }
                    }
                }
                let reopened = try PresentationIO.read(try PresentationIO.write(sample, format: .pptx), format: .pptx).presentation
                check(reopened.slides.map(\.transition) == sample.slides.map(\.transition), "a PowerPoint file keeps transitions")
                check(motion(reopened) == motion(sample), "a PowerPoint file keeps animations", "\(motion(reopened))")
                // And OpenDocument.
                func texts(_ presentation: Presentation) -> [[String]] {
                    presentation.slides.map { $0.elements.filter { $0.placeholder?.type != .slideNumber }.compactMap { $0.shape?.text?.plainText } }
                }
                let odp = try PresentationIO.read(try PresentationIO.write(sample, format: .odp), format: .odp)
                check(odp.warnings.isEmpty, "an OpenDocument file reads back without warnings", "\(odp.warnings)")
                check(texts(odp.presentation) == texts(sample), "an OpenDocument file keeps every slide's text")
                check(odp.presentation.slides.map(\.notes.plainText) == sample.slides.map(\.notes.plainText)
                      && odp.presentation.slides.map(\.isSkipped) == sample.slides.map(\.isSkipped), "an OpenDocument file keeps notes and skipped slides")
                check(odp.presentation.slides.map(\.transition) == sample.slides.map(\.transition), "an OpenDocument file keeps transitions")
                check(motion(odp.presentation) == motion(sample), "an OpenDocument file keeps animations", "\(motion(odp.presentation))")
                check(odp.presentation.slides.map { $0.elements.count } == sample.slides.map { $0.elements.count }, "an OpenDocument file keeps every object")
                let png = try window.downloadData(.png)
                check(NSBitmapImageRep(data: png)?.pixelsWide == 1600, "a PNG slide is 1600 pixels wide")
                let jpeg = try window.downloadData(.jpg)
                check(jpeg.starts(with: [0xFF, 0xD8]), "a JPEG slide")
            } catch {
                check(false, "picture downloads", "\(error)")
            }
        }
    }

    /// Saving and reopening as PowerPoint.
    private static func runPPTXChecks(_ window: DocumentWindowController) {
        let original = window.controller.presentation
        do {
            let data = try PresentationIO.write(original, format: .pptx)
            let file = try PresentationIO.read(data, format: .pptx)
            check(file.presentation.slides.count == original.slides.count, "a PowerPoint file keeps every slide")
            // Slide number fields store the number they show, as PowerPoint does, so they're left out here.
            func texts(_ presentation: Presentation) -> [[String]] {
                presentation.slides.map { $0.elements.filter { $0.placeholder?.type != .slideNumber }.compactMap { $0.shape?.text?.plainText } }
            }
            let differences = zip(texts(file.presentation), texts(original)).enumerated().filter { $0.element.0 != $0.element.1 }
            check(differences.isEmpty, "a PowerPoint file keeps the text", "\(differences.prefix(2))")
            check(file.presentation.slides.map(\.isSkipped) == original.slides.map(\.isSkipped), "a PowerPoint file keeps skipped slides")
            check(file.presentation.slides.map(\.notes.plainText) == original.slides.map(\.notes.plainText), "a PowerPoint file keeps speaker notes")
        } catch {
            check(false, "PowerPoint round trip", "\(error)")
        }
    }
}

extension NSMenuItem {
    /// A menu item with a tag, for calling menu actions directly.
    func withTag(_ tag: Int) -> NSMenuItem {
        self.tag = tag
        return self
    }
}
#endif
