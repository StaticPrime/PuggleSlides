import AppKit
import PuggleSlidesKit
import SwiftUI

/// What the slideshow's control bar and the presenter view show.
@Observable
final class SlideshowState {
    var position = 0
    var count = 0
    var showsControls = false
    /// The presenter view's timer, in seconds.
    var elapsed: TimeInterval = 0
    var isTimerPaused = false
    /// Bumped whenever the slide or its animations move on, so the presenter view redraws.
    var revision = 0
}

/// View ▸ Slideshow: the presentation full screen, one slide (and one click of animations) at a time.
@MainActor
final class SlideshowController: NSObject {
    private(set) static var current: SlideshowController?

    let presentation: Presentation
    /// Indexes of the slides shown (skipped slides are left out).
    let order: [Int]
    let state = SlideshowState()
    private let window: SlideshowWindow
    let stage: SlideStageView
    private(set) var presenter: PresenterWindowController?
    private var hasEnded = false
    private var hideTimer: Timer?
    private var frameTimer: Timer?
    private var clockTimer: Timer?
    private var typedNumber = ""
    /// Called with the slide index to show in the editor when the slideshow ends.
    var onEnd: ((Int) -> Void)?

    // Playback of the current slide.
    private(set) var timeline: AnimationTimeline
    /// Groups started so far; group 0 (what plays by itself) starts when the slide appears.
    private(set) var playedGroups = 0
    /// The slides' videos and sounds.
    private(set) lazy var media = SlideshowMedia(presentation: presentation, stage: stage)
    private var groupStart: CFTimeInterval?
    /// A transition in progress, drawn instead of the slide.
    private(set) var transition: (kind: TransitionKind, duration: Double, start: CFTimeInterval, old: CGImage?, new: CGImage, seed: UInt64)?
    /// Debug builds can stop transitions and animations part-way to check them in screenshots.
    var frozenProgress: Double?

    var currentSlideIndex: Int { order.isEmpty ? 0 : order[state.position] }
    var currentSlide: Slide { presentation.slides[currentSlideIndex] }

    /// The next slide the presenter view previews, if any.
    var nextSlideIndex: Int? { state.position + 1 < order.count ? order[state.position + 1] : nil }

    /// Starts presenting from `slideIndex` (or the next slide that isn't skipped).
    @discardableResult
    static func start(_ presentation: Presentation, from slideIndex: Int, on screen: NSScreen?, presenterView: Bool = false) -> SlideshowController? {
        current?.end()
        let order = presentation.slides.indices.filter { !presentation.slides[$0].isSkipped }
        guard !order.isEmpty else {
            NSSound.beep()
            return nil
        }
        // With a second display the audience sees the slides there and the presenter view takes this one.
        let screens = NSScreen.screens
        let audienceScreen = presenterView && screens.count > 1 ? (screens.first { $0 != screen } ?? screen) : screen
        let controller = SlideshowController(presentation: presentation, order: order, screen: audienceScreen ?? NSScreen.main)
        current = controller
        controller.show(at: order.firstIndex { $0 >= slideIndex } ?? order.count - 1)
        if presenterView { controller.showPresenterView(on: screen, overlay: screens.count < 2) }
        return controller
    }

    private init(presentation: Presentation, order: [Int], screen: NSScreen?) {
        self.presentation = presentation
        self.order = order
        timeline = AnimationTimeline(slide: presentation.slides[order[0]], presentation: presentation)
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = SlideshowWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        stage = SlideStageView(frame: NSRect(origin: .zero, size: frame.size))
        super.init()
        state.count = order.count
        stage.controller = self
        stage.isAudience = true
        window.controller = self
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.appearance = NSAppearance(named: .darkAqua)
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        stage.autoresizingMask = [.width, .height]
        container.addSubview(stage)
        let bar = NSHostingView(rootView: SlideshowControls(state: state, controller: self))
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        window.contentView = container
        window.setFrame(frame, display: false)
    }

    private func show(at position: Int) {
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(stage)
        NSCursor.setHiddenUntilMouseMoves(true)
        enter(position, transition: false)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.isTimerPaused else { return }
                self.state.elapsed += 1
            }
        }
    }

    private func showPresenterView(on screen: NSScreen?, overlay: Bool) {
        let presenter = PresenterWindowController(slideshow: self, screen: screen, overlay: overlay)
        self.presenter = presenter
        presenter.showWindow(nil)
        presenter.window?.makeKeyAndOrderFront(nil)
    }

    func end() {
        // Closing the presenter view ends the show too, so this can be reached twice.
        guard !hasEnded else { return }
        hasEnded = true
        if Self.current === self { Self.current = nil }
        hideTimer?.invalidate()
        frameTimer?.invalidate()
        clockTimer?.invalidate()
        media.stopAll()
        NSApp.presentationOptions = []
        let presenter = self.presenter
        self.presenter = nil
        presenter?.close()
        window.orderOut(nil)
        onEnd?(currentSlideIndex)
    }

    // MARK: Moving through the show

    /// Shows a slide: with its transition from the slide before, or at once. Then whatever plays by itself starts.
    private func enter(_ position: Int, transition withTransition: Bool, fullyBuilt: Bool = false) {
        let old = withTransition ? renderFrame() : nil
        state.position = max(0, min(order.count - 1, position))
        timeline = AnimationTimeline(slide: currentSlide, presentation: presentation)
        // Clips that start by themselves wait for the transition.
        let arriving = withTransition && !fullyBuilt ? currentSlide.transition.map { $0.kind == .none ? 0 : max(0.05, $0.duration) } ?? 0 : 0
        media.enter(currentSlide, startAfter: arriving, fullyBuilt: fullyBuilt)
        // VoiceOver reads each slide as it arrives.
        if let text = stage.accessibilityLabel() {
            NSAccessibility.post(element: stage, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        stage.blank = nil
        if fullyBuilt {
            playedGroups = timeline.groups.count
            groupStart = nil
        } else {
            playedGroups = 0
            groupStart = nil
            if withTransition, let kind = currentSlide.transition, kind.kind != .none, let new = renderFrame() {
                transition = (kind.kind, max(0.05, kind.duration), CACurrentMediaTime(), old, new, UInt64(state.position &+ 1) &* 2654435761)
            } else {
                transition = nil
                startGroup()
            }
        }
        changed()
    }

    /// Starts the next group of animations.
    private func startGroup() {
        guard playedGroups < timeline.groups.count else { return }
        playedGroups += 1
        groupStart = timeline.groups[playedGroups - 1].isEmpty ? nil : CACurrentMediaTime()
        changed()
    }

    func next() {
        if stage.blank != nil {
            stage.blank = nil
            changed()
            return
        }
        if transition != nil {
            finishTransition()
            return
        }
        if groupStart != nil {
            groupStart = nil
            changed()
            return
        }
        if playedGroups < timeline.groups.count {
            startGroup()
            return
        }
        // Then the clips that start on click, one per click.
        if media.startNextOnClick() {
            changed()
            return
        }
        guard state.position < order.count - 1 else { return }
        enter(state.position + 1, transition: true)
    }

    func previous() {
        if stage.blank != nil {
            stage.blank = nil
            changed()
            return
        }
        transition = nil
        if playedGroups > 1 {
            playedGroups -= 1
            groupStart = nil
            changed()
            return
        }
        guard state.position > 0 else {
            groupStart = nil
            changed()
            return
        }
        enter(state.position - 1, transition: false, fullyBuilt: true)
    }

    /// Slide numbers count every slide, skipped ones included.
    func go(toSlideNumber number: Int) {
        guard let target = order.firstIndex(where: { $0 >= number - 1 }) else { return }
        go(toPosition: target)
    }

    func go(toPosition position: Int) {
        transition = nil
        enter(position, transition: false)
    }

    private func finishTransition() {
        transition = nil
        startGroup()
        changed()
    }

    // MARK: Frames

    /// The states of the current slide's elements now.
    func currentStates(at now: CFTimeInterval = CACurrentMediaTime()) -> [UUID: AnimationTimeline.State] {
        guard playedGroups > 0 else { return timeline.initialStates }
        var time = Double.infinity
        if let start = groupStart {
            let duration = timeline.duration(ofGroup: playedGroups - 1)
            time = frozenProgress.map { $0 * duration } ?? (now - start)
        }
        return timeline.states(group: playedGroups - 1, time: time)
    }

    /// Progress of the transition in progress, 0...1.
    func transitionProgress(at now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        guard let transition else { return 1 }
        return frozenProgress ?? min(1, (now - transition.start) / transition.duration)
    }

    /// A picture of what the audience sees now, the size of the stage's slide.
    private func renderFrame() -> CGImage? {
        let rect = stage.slideRect
        let scale = window.backingScaleFactor
        let width = Int(rect.width * scale), height = Int(rect.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        SlideRenderer.draw(currentSlide, of: presentation, in: CGRect(origin: .zero, size: rect.size),
                           options: SlideRenderer.Options(slideNumber: currentSlideIndex + 1, states: currentStates(), isPresenting: true))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Redraws, and keeps redrawing while something moves.
    private func changed() {
        state.revision += 1
        stage.needsDisplay = true
        presenter?.refresh()
        let animating = transition != nil || groupStart != nil
        if animating, frameTimer == nil, frozenProgress == nil {
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else if !animating {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let transition, now - transition.start >= transition.duration {
            finishTransition()
            return
        }
        if let start = groupStart, now - start >= timeline.duration(ofGroup: playedGroups - 1) {
            groupStart = nil
            // An "After previous" chain that ends a group may lead straight into nothing else; the next click continues.
            changed()
            return
        }
        stage.needsDisplay = true
        presenter?.refreshStage()
    }

    // MARK: Input

    func mouseMoved() {
        state.showsControls = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.showsControls = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    func toggleBlank(_ color: NSColor) {
        stage.blank = stage.blank == color ? nil : color
        changed()
    }

    func handle(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers, let key = characters.unicodeScalars.first else { return false }
        if stage.blank != nil, Int(key.value) != 27 {
            stage.blank = nil
            changed()
            return true
        }
        switch Int(key.value) {
        case NSRightArrowFunctionKey, NSDownArrowFunctionKey, NSPageDownFunctionKey, 32:
            next()
        case 13, 3:
            if let number = Int(typedNumber) { go(toSlideNumber: number) } else { next() }
            typedNumber = ""
        case NSLeftArrowFunctionKey, NSUpArrowFunctionKey, NSPageUpFunctionKey, 127, 8:
            previous()
        case NSHomeFunctionKey:
            go(toPosition: 0)
        case NSEndFunctionKey:
            go(toPosition: order.count - 1)
        case 27:
            end()
        default:
            switch characters.lowercased() {
            case "n": next()
            case "p": previous()
            case "b", ".": toggleBlank(.black)
            case "w", ",": toggleBlank(.white)
            case let digit where digit.count == 1 && digit.first!.isNumber:
                typedNumber += digit
            default:
                return false
            }
        }
        return true
    }
}

final class SlideshowWindow: NSWindow {
    weak var controller: SlideshowController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if controller?.handle(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.end()
    }
}

/// Draws the slideshow's current frame letterboxed on black: a transition, or the slide with its animations.
final class SlideStageView: NSView {
    weak var controller: SlideshowController?
    /// The audience's view takes clicks and shows transitions; the presenter view's copy shows the slide as it settles.
    var isAudience = false
    /// A blank black or white screen (B and W).
    var blank: NSColor?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isAudience }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        guard isAudience else { return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    /// The largest rectangle with the slide's proportions that fits the view.
    var slideRect: CGRect {
        guard let presentation = controller?.presentation else { return bounds }
        let size = presentation.slideSize
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let controller else { return }
        if isAudience, let blank {
            blank.setFill()
            bounds.fill()
            return
        }
        if isAudience, let transition = controller.transition {
            TransitionRenderer.draw(transition.kind, progress: controller.transitionProgress(), from: transition.old, to: transition.new,
                                    in: slideRect, seed: transition.seed)
            return
        }
        SlideRenderer.draw(controller.currentSlide, of: controller.presentation, in: slideRect,
                           options: SlideRenderer.Options(slideNumber: controller.currentSlideIndex + 1, states: controller.currentStates(),
                                                          isPresenting: true))
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handle(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isAudience, let controller else { return }
        // A click on a video that plays manually starts or pauses it.
        if let point = slidePoint(convert(event.locationInWindow, from: nil)), controller.media.toggleVideo(at: point) { return }
        controller.next()
    }

    override func layout() {
        super.layout()
        if isAudience { controller?.media.layout() }
    }

    /// A point in this view on the slide, in slide points; nil off the slide.
    func slidePoint(_ point: CGPoint) -> SlidePoint? {
        guard let size = controller?.presentation.slideSize, size.width > 0 else { return nil }
        let rect = slideRect
        guard rect.contains(point) else { return nil }
        let scale = rect.width / size.width
        return SlidePoint(x: (point.x - rect.minX) / scale, y: (point.y - rect.minY) / scale)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isAudience else { return }
        controller?.previous()
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.mouseMoved()
    }
}

/// The slideshow toolbar at the bottom left: previous, the slide number, next, and exit.
struct SlideshowControls: View {
    let state: SlideshowState
    /// Weak: the controller owns the window these controls are in.
    weak var controller: SlideshowController?

    var body: some View {
        HStack(spacing: 4) {
            button("chevron.left", help: "Previous") { controller?.previous() }
            Text("\(state.position + 1) / \(state.count)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 54)
            button("chevron.right", help: "Next") { controller?.next() }
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 18).padding(.horizontal, 4)
            Button {
                controller?.end()
            } label: {
                Text("Exit").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 10).frame(height: 30)
            }
            .buttonStyle(.plain)
            .help("Exit (Esc)")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(Capsule().fill(Color(white: 0.16).opacity(0.92)))
        .opacity(state.showsControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.showsControls)
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
