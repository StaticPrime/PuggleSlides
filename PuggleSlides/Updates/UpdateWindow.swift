import AppKit
import PuggleUpdate
import SwiftUI

/// What the splash screen shows, and then, while the app updates itself, the update's progress.
@Observable
final class UpdateWindowModel {
    enum Stage: Equatable {
        /// The logo, while the app opens.
        case splash
        /// Downloading the new version: `received` of `total` bytes.
        case downloading
        /// macOS's installer is putting it in place (after asking for an administrator's password).
        case installing
        /// Opening the new version.
        case restarting
    }

    var stage: Stage = .splash
    var version = ""
    var received: Int64 = 0
    var total: Int64 = 0
    /// The installer has started (the password was given): `installFraction` and `phase` come from it.
    var installStarted = false
    var installFraction: Double = 0
    var phase = ""
    var canCancel = false
    var onCancel: () -> Void = {}
}

/// The splash screen: a borderless window with the app's logo, in the middle of the screen while the app opens. When
/// the app updates itself as it opens, the same window says so and shows the download's and then the installation's
/// progress.
final class UpdateWindowController: NSWindowController {
    let model = UpdateWindowModel()
    static let size = NSSize(width: 380, height: 380)
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let window = SplashWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Like every window of the app, it stays light in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        window.level = .floating
        let host = NSHostingView(rootView: UpdateView(model: model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 18
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        window.contentView = host
        super.init(window: window)
        // Above the app's other windows while it's in front, but not over other apps' when it isn't.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { window?.level = .normal }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { window?.level = .floating }
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
        DispatchQueue.main.async { window.invalidateShadow() }
    }

    func fadeOut(then completion: @escaping @MainActor () -> Void) {
        guard let window, window.isVisible else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                completion()
            }
        })
    }
}

/// A borderless window that can still take clicks on its Cancel button.
private final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct UpdateView: View {
    let model: UpdateWindowModel

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }

    private var isSplash: Bool { model.stage == .splash }

    var body: some View {
        VStack(spacing: 0) {
            Image("AboutLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: isSplash ? 240 : 170, height: isSplash ? 240 : 170)
                .accessibilityLabel(appName)
            if isSplash {
                Text(AboutView.version)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 14)
            } else {
                progress
            }
        }
        .padding(.horizontal, 40)
        .frame(width: UpdateWindowController.size.width, height: UpdateWindowController.size.height)
        .background(Color.white)
        .animation(.easeInOut(duration: 0.25), value: model.stage)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(appName) is Updating")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .accessibilityLabel(caption)
            HStack(alignment: .firstTextBaseline) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if model.canCancel {
                    Button("Cancel") { model.onCancel() }
                        .controlSize(.small)
                }
            }
            .frame(height: 22)
            .padding(.top, 6)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 2)
        }
    }

    /// The bar: the download, then the installation.
    private var fraction: Double {
        switch model.stage {
        case .splash: 0
        case .downloading: model.total > 0 ? min(1, Double(model.received) / Double(model.total)) : 0
        case .installing: model.installStarted ? model.installFraction : 0
        case .restarting: 1
        }
    }

    private var caption: String {
        switch model.stage {
        case .splash:
            ""
        case .downloading:
            model.total > 0
                ? "Downloading… \(Self.bytes(model.received)) of \(Self.bytes(model.total))"
                : "Downloading…"
        case .installing:
            "Updating…"
        case .restarting:
            "Opening \(appName) \(model.version)…"
        }
    }

    private var detail: String {
        switch model.stage {
        case .splash, .restarting: ""
        case .downloading: "Version \(model.version)"
        case .installing: model.installStarted ? model.phase : "macOS asks for an administrator’s password to install version \(model.version)."
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// The banner under the toolbar of a presentation's window when there's a newer version: Click Here installs it (or,
/// for a copy from the App Store, opens its page there). Slideshows and presenter view never show it.
struct UpdateBannerView: View {
    let banner: UpdateBanner

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }

    var body: some View {
        if let update = banner.visibleUpdate {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 4)
                Text(update.isFromAppStore
                     ? "A new version of \(appName) (\(update.version.description)) is available on the App Store."
                     : "A new version of \(appName) (\(update.version.description)) is available.")
                    .foregroundStyle(Theme.primaryText)
                Button("Click Here") { UpdateController.shared.installFromBanner() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .help(update.isFromAppStore ? "Open \(appName) in the App Store" : "Download and install version \(update.version.description)")
                Text("to update.")
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Button("Dismiss") { banner.isDismissed = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.activeFill)
        }
    }
}
