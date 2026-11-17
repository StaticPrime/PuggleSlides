import AppKit
import SwiftUI

/// PuggleSlides ▸ About PuggleSlides: the logo, the version and the copyright line from the app's Info.plist.
final class AboutWindowController: NSWindowController {
    private static var shared: AboutWindowController?

    /// Shows the About window, creating it the first time.
    static func show() {
        let controller = shared ?? AboutWindowController()
        shared = controller
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.showWindow(nil)
    }

    private init() {
        let window = AboutWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "About PuggleSlides"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isExcludedFromWindowsMenu = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        // Like every PuggleSlides window, it stays light in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingController(rootView: AboutView())
        window.contentViewController = host
        window.setContentSize(host.view.fittingSize)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Esc closes the window, as it does the standard About panel.
private final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

struct AboutView: View {
    /// "Version 0.1.0 (1)", as the standard About panel writes it.
    static var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty || build == marketing ? "Version \(marketing)" : "Version \(marketing) (\(build))"
    }

    /// The copyright line, one sentence per line.
    static var copyright: String {
        (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
            .replacingOccurrences(of: ". ", with: ".\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("AboutLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 240, height: 240)
                .accessibilityLabel("PuggleSlides")
            Text(Self.version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 10)
            Text(Self.copyright)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 0, leading: 30, bottom: 24, trailing: 30))
        .fixedSize()
    }
}
