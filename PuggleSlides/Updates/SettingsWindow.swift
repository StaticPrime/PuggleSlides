import AppKit
import SwiftUI

/// PuggleSlides ▸ Settings… (⌘,), also in the Tools menu: how typing behaves, and Automatic Updates. They belong to
/// the person rather than to a presentation, so they're in a window of their own, open with or without a presentation.
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    /// Shows the Settings window, creating it the first time.
    static func show() {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.showWindow(nil)
    }

    /// The window, if it's open (for screenshots).
    static var visibleWindow: NSWindow? { shared?.window?.isVisible == true ? shared?.window : nil }

    private init() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
        let window = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "\(appName) Settings"
        window.isExcludedFromWindowsMenu = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        // Like every PuggleSlides window, it stays light in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingController(rootView: SettingsView(appName: appName, capability: UpdateController.shared.capability))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.setContentSize(host.view.fittingSize)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Esc and ⌘W close it, as they do any settings window.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

struct SettingsView: View {
    let appName: String
    let capability: UpdateController.Capability
    @AppStorage(TypingPreferences.smartQuotesKey) private var smartQuotes = true
    @AppStorage(TypingPreferences.smartDashesKey) private var smartDashes = true
    @AppStorage(TypingPreferences.capitalizesKey) private var capitalize = false
    @AppStorage(TypingPreferences.spellCheckKey) private var spellCheck = true
    @AppStorage(UpdateController.automaticUpdatesKey) private var automaticUpdates = true

    var body: some View {
        Form {
            Section("Typing") {
                Toggle("Use smart quotes", isOn: $smartQuotes)
                Toggle("Use smart dashes", isOn: $smartDashes)
                Toggle("Automatically capitalize words", isOn: $capitalize)
                Toggle("Check spelling as you type", isOn: $spellCheck)
            }
            // Text being typed, and every window's speaker notes, follow a change straight away.
            .onChange(of: [smartQuotes, smartDashes, spellCheck]) { TypingPreferences.applyEverywhere() }
            Section {
                switch capability {
                case .appStore:
                    LabeledContent("Updates") {
                        Text("The App Store keeps \(appName) up to date. When it has a new version, a banner at the top of the window says so.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .none(reason):
                    automaticToggle
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .updatesItself:
                    automaticToggle
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(AboutView.version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var automaticToggle: some View {
        Toggle(isOn: $automaticUpdates) {
            Text("Automatic Updates")
            Text("When \(appName) opens, it checks for a new version. With Automatic Updates on, it downloads the new version and installs it, then opens again. With it off, a banner at the top of the window says when a new version is available.")
        }
    }
}
