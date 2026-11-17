import AppKit
import PuggleSlidesKit
import SwiftUI

/// The Motion panel: the slide's transition, then its object animations.
struct MotionPanel: View {
    let state: EditorState
    let actions: SidebarActions
    @State private var expanded: UUID?

    private var controller: PresentationController { actions.controller }

    var body: some View {
        let _ = state.revision
        let transition = controller.currentTransition
        VStack(alignment: .leading, spacing: 4) {
            PanelSection(title: "Slide transition") {
                Picker("", selection: Binding(get: { transition.kind }, set: { kind in
                    controller.setTransition(SlideTransition(kind: kind, duration: transition.duration))
                })) {
                    ForEach(TransitionKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                .labelsHidden()
                if transition.kind != .none {
                    DurationSlider(seconds: transition.duration) { seconds in
                        controller.setTransition(SlideTransition(kind: transition.kind, duration: seconds))
                    }
                    PanelButton(title: "Apply to all slides", primary: false) { controller.applyTransitionToAllSlides() }
                }
            }
            Divider().padding(.bottom, 12)
            PanelSection(title: "Object animations") {
                ForEach(Array(controller.currentAnimations.enumerated()), id: \.element.id) { index, animation in
                    card(animation, index: index)
                }
                Button {
                    if let id = controller.addAnimation() { expanded = id }
                } label: {
                    Label("Add animation", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(controller.selectedElementIDs.isEmpty ? Theme.secondaryText : Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(controller.selectedElementIDs.isEmpty)
                .help(controller.selectedElementIDs.isEmpty ? "Select an object to animate" : "Animate the selected object")
                if controller.selectedElementIDs.isEmpty, controller.currentAnimations.isEmpty {
                    Text("Select an object to animate it.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
            }
            Divider().padding(.bottom, 12)
            HStack {
                PanelButton(title: "Play") { (actions as? DocumentWindowController)?.playMotionPreview() }
                Spacer()
            }
        }
        .onChange(of: controller.currentSlideID) { _, _ in expanded = nil }
    }

    private func card(_ animation: SlideAnimation, index: Int) -> some View {
        let isOpen = expanded == animation.id
        let element = controller.currentSlide?.element(id: animation.elementID)
        let paragraphs = element?.shape?.text?.paragraphs.filter { !$0.isEmpty }.count ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded = isOpen ? nil : animation.id
                controller.selectElements([animation.elementID])
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(Theme.secondaryText).font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(animation.effect.title) (\(animation.start.title))").font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                        Text(controller.displayName(of: animation.elementID)).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                Picker("", selection: Binding(get: { animation.effect }, set: { effect in
                    controller.updateAnimation(animation.id) { $0.effect = effect }
                })) {
                    ForEach(AnimationEffect.allCases, id: \.self) { effect in Text(effect.title).tag(effect) }
                }
                .labelsHidden()
                Picker("", selection: Binding(get: { animation.start }, set: { start in
                    controller.updateAnimation(animation.id) { $0.start = start }
                })) {
                    ForEach(AnimationStart.allCases, id: \.self) { start in Text(start.title).tag(start) }
                }
                .labelsHidden()
                if paragraphs > 1 {
                    Toggle("By paragraph", isOn: Binding(get: { animation.byParagraph }, set: { on in
                        controller.updateAnimation(animation.id) { $0.byParagraph = on }
                    }))
                    .font(.system(size: 13))
                }
                if !animation.effect.isInstant {
                    DurationSlider(seconds: animation.duration) { seconds in
                        controller.updateAnimation(animation.id) { $0.duration = seconds }
                    }
                }
                HStack {
                    Spacer()
                    ToolbarIconButton(symbol: "trash", help: "Delete animation") {
                        expanded = nil
                        controller.deleteAnimation(animation.id)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(isOpen ? Theme.activeFill.opacity(0.45) : Color.black.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider.opacity(0.7)))
        .draggable(animation.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)), dragged != animation.id else { return false }
            controller.moveAnimation(dragged, to: index)
            return true
        }
    }
}

/// An animation's duration, from slow to fast.
struct DurationSlider: View {
    let seconds: Double
    let commit: (Double) -> Void
    @State private var value: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Slow").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(String(format: "%.1f s", value)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("Fast").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            Slider(value: Binding(get: { 5.1 - value }, set: { value = ((5.1 - $0) * 10).rounded() / 10 }), in: 0.1...5.0) { editing in
                if !editing { commit(value) }
            }
        }
        .onAppear { value = seconds }
        .onChange(of: seconds) { _, newValue in value = newValue }
    }
}

/// The Motion panel's Play: the current slide's transition and animations, played on the canvas.
final class MotionPreviewView: NSView {
    private let presentation: Presentation
    private let slideIndex: Int
    private let timeline: AnimationTimeline
    private let transition: SlideTransition?
    private var old: CGImage?
    private var new: CGImage?
    private var start = CACurrentMediaTime()
    private var timer: Timer?
    private let slideFrame: CGRect
    /// Called when the preview has played.
    var onFinish: (() -> Void)?
    private let pause = 0.3

    init(frame: CGRect, slideFrame: CGRect, presentation: Presentation, slideIndex: Int) {
        self.presentation = presentation
        self.slideIndex = slideIndex
        self.slideFrame = slideFrame
        let slide = presentation.slides[slideIndex]
        timeline = AnimationTimeline(slide: slide, presentation: presentation)
        transition = slide.transition
        super.init(frame: frame)
        if let transition, transition.kind != .none {
            old = slideIndex > 0 ? image(presentation.slides[slideIndex - 1], states: [:]) : nil
            new = image(slide, states: timeline.initialStates)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func image(_ slide: Slide, states: [UUID: AnimationTimeline.State]) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int(slideFrame.width * scale), height = Int(slideFrame.height * scale)
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        SlideRenderer.draw(slide, of: presentation, in: CGRect(origin: .zero, size: slideFrame.size),
                           options: SlideRenderer.Options(slideNumber: slideIndex + 1, states: states))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// The transition first, then each group of animations in turn, with a short pause between groups.
    private var phases: [(group: Int?, length: Double)] {
        var result: [(Int?, Double)] = []
        if let transition, transition.kind != .none { result.append((nil, transition.duration)) }
        for index in timeline.groups.indices where !timeline.groups[index].isEmpty {
            result.append((index, timeline.duration(ofGroup: index) + pause))
        }
        return result
    }

    private func tick() {
        needsDisplay = true
        let total = phases.reduce(0) { $0 + $1.length }
        if CACurrentMediaTime() - start > total + 0.4 {
            timer?.invalidate()
            onFinish?()
        }
    }

    func stop() {
        timer?.invalidate()
        removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        var elapsed = CACurrentMediaTime() - start
        for phase in phases {
            if elapsed < phase.length {
                if let group = phase.group {
                    SlideRenderer.draw(presentation.slides[slideIndex], of: presentation, in: slideFrame,
                                       options: SlideRenderer.Options(slideNumber: slideIndex + 1, states: timeline.states(group: group, time: elapsed)))
                } else if let transition, let new {
                    TransitionRenderer.draw(transition.kind, progress: elapsed / max(0.05, transition.duration), from: old, to: new,
                                            in: slideFrame, seed: 7)
                }
                return
            }
            elapsed -= phase.length
        }
        SlideRenderer.draw(presentation.slides[slideIndex], of: presentation, in: slideFrame,
                           options: SlideRenderer.Options(slideNumber: slideIndex + 1,
                                                          states: timeline.states(group: timeline.groups.count - 1, time: .infinity)))
    }
}
