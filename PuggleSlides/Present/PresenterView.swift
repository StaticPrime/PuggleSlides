import AppKit
import PuggleSlidesKit
import SwiftUI

/// What the presenter view shows beside the current slide.
@Observable
final class PresenterModel {
    var notes = ""
    var nextSlide: NSImage?
    var notesSize: CGFloat = 18
}

/// The presenter view: the current slide, the next one, speaker notes, a timer and the controls.
@MainActor
final class PresenterWindowController: NSWindowController, NSWindowDelegate {
    weak var slideshow: SlideshowController?
    let stage = SlideStageView(frame: .zero)
    let model = PresenterModel()

    init(slideshow: SlideshowController, screen: NSScreen?, overlay: Bool) {
        self.slideshow = slideshow
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window: NSWindow
        if overlay {
            // One display: the presenter view opens in its own panel over the slideshow.
            let size = NSSize(width: min(1000, visible.width * 0.8), height: min(640, visible.height * 0.8))
            let panel = PresenterPanel(contentRect: NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                                           width: size.width, height: size.height),
                                       styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            window = panel
        } else {
            window = PresenterPanel(contentRect: visible, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        }
        window.title = "Presenter view"
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        (window as? PresenterPanel)?.presenter = self
        stage.controller = slideshow
        window.contentView = NSHostingView(rootView: PresenterView(state: slideshow.state, model: model, stage: stage, actions: self))
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The slide changed: new notes and a new preview of what comes next.
    func refresh() {
        guard let slideshow else { return }
        model.notes = slideshow.currentSlide.notes.plainText
        if let next = slideshow.nextSlideIndex {
            let slide = slideshow.presentation.slides[next]
            let size = slideshow.presentation.slideSize
            model.nextSlide = SlideRenderer.image(of: slide, in: slideshow.presentation, size: CGSize(width: 320, height: 320 * size.height / size.width),
                                                  slideNumber: next + 1)
        } else {
            model.nextSlide = nil
        }
        stage.needsDisplay = true
    }

    func refreshStage() {
        stage.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the presenter view ends the show.
        if let slideshow, SlideshowController.current === slideshow { slideshow.end() }
    }

    // Actions from the view.
    func previous() { slideshow?.previous() }
    func next() { slideshow?.next() }
    func end() { slideshow?.end() }
    func toggleTimer() { slideshow?.state.isTimerPaused.toggle() }
    func resetTimer() { slideshow?.state.elapsed = 0 }
    func handle(_ event: NSEvent) -> Bool { slideshow?.handle(event) ?? false }
}

/// The presenter view's window passes the slideshow's keys on.
final class PresenterPanel: NSPanel {
    weak var presenter: PresenterWindowController?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if presenter?.handle(event) != true { super.keyDown(with: event) }
    }
}

/// Puts the presenter's copy of the slideshow stage in SwiftUI.
struct StageView: NSViewRepresentable {
    let stage: SlideStageView

    func makeNSView(context: Context) -> SlideStageView { stage }
    func updateNSView(_ nsView: SlideStageView, context: Context) {}
}

struct PresenterView: View {
    let state: SlideshowState
    let model: PresenterModel
    let stage: SlideStageView
    /// Weak: the window controller owns the window this view is in.
    weak var actions: PresenterWindowController?

    private var time: String {
        let total = Int(state.elapsed)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { actions?.previous() } label: { Label("Previous", systemImage: "chevron.left") }
                Text("Slide \(state.position + 1) of \(state.count)").font(.system(size: 13, weight: .medium)).monospacedDigit()
                Button { actions?.next() } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                Spacer()
                Text(time).font(.system(size: 15, weight: .medium, design: .monospaced))
                Button(state.isTimerPaused ? "Resume" : "Pause") { actions?.toggleTimer() }
                Button("Reset") { actions?.resetTimer() }
                Spacer()
                Button("End show") { actions?.end() }.keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .padding(12)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                StageView(stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next slide").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    if let image = model.nextSlide {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .overlay(Rectangle().stroke(Color(nsColor: Theme.slideBorder)))
                    } else {
                        Text("End of presentation").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.05)))
                    }
                    HStack {
                        Text("Speaker notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Button { model.notesSize = max(10, model.notesSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                            .help("Smaller notes")
                        Button { model.notesSize = min(48, model.notesSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                            .help("Bigger notes")
                    }
                    .buttonStyle(.borderless)
                    ScrollView {
                        Text(model.notes.isEmpty ? "No speaker notes" : model.notes)
                            .font(.system(size: model.notesSize))
                            .foregroundStyle(model.notes.isEmpty ? Theme.secondaryText : Theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(width: 320)
            }
            .padding(16)
        }
        .background(Color.white)
        .onChange(of: state.revision) { _, _ in stage.needsDisplay = true }
    }
}
