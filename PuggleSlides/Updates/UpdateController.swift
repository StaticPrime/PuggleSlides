import AppKit
import CryptoKit
import os
import PuggleUpdate

/// Keeps the app up to date.
///
/// As the app opens it shows its splash screen while it asks GitHub whether there's a newer version (a copy from the
/// App Store asks the App Store instead), giving up after five seconds. With Automatic Updates on (the default), a newer
/// version is downloaded and installed straight away, with its progress in the splash screen's place, and the new
/// version opens in place of this one. With it off, or for a copy from the App Store (which installs its own updates),
/// a banner at the top of each window says there's a newer version, and installs it when clicked.
///
/// Presentations, invitation links and notifications that ask the app to open something while it's still opening wait
/// until it has (`whenLaunched`), and are handed to the new version if it restarts to finish updating first.
final class UpdateController {
    static let shared = UpdateController()

    /// The setting, on by default.
    static let automaticUpdatesKey = "AutomaticUpdates"
    /// A version whose installation the person stopped, or that failed to install: it isn't installed again by itself.
    private static let declinedKey = "UpdateDeclinedVersion"
    /// What the old copy asked the new one to open after restarting to finish updating.
    private static let handoffsKey = "UpdateHandoffs"
    /// How long the splash screen stays up, at least, so it never just flickers.
    private static let minimumSplash: TimeInterval = 0.8

    /// What this copy can do about updates.
    enum Capability {
        /// It downloads and installs its own updates, described by the release's `update.json` at `manifest`.
        case updatesItself(manifest: URL, trustedHosts: Set<String>)
        /// It came from the App Store, which updates it.
        case appStore(bundleIdentifier: String)
        /// It doesn't update itself, for this reason.
        case none(String)
    }

    let capability: Capability
    /// The banner each presentation's window shows when there's a newer version.
    let banner = UpdateBanner()

    /// Performs something a previous copy handed over (see `whenLaunched`), once this one has opened. Set by the app.
    var onHandoff: ((String) -> Void)?
    /// What to hand over for open presentations that have no file of their own (those someone else shares, say), should
    /// the app restart to finish updating. Set by the app.
    var handoffsForOpenDocuments: (() -> [String])?

    var automaticUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: Self.automaticUpdatesKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticUpdatesKey) }
    }

    /// The app was opened by itself, not to open presentations or bring back windows: it opens with an untitled
    /// presentation. AppKit doesn't open one while the splash screen is up, so this does once it's gone. Set by the
    /// app.
    var launchIsDefault = false

    /// True while macOS's installer may be changing the app: the app mustn't quit then.
    private(set) var isInstalling = false
    /// The app has finished opening: the splash screen is gone and what waited for it has happened.
    private(set) var hasLaunched = false

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pugglesoft", category: "Updates")
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    private let currentVersion = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion("0")!
    private var startedAt = Date()
    private var isFinishingLaunch = false
    private var waitsForCheck = false
    private var waiting: [() -> Void] = []
    private var waitingURLs: [URL] = []
    private var waitingHandoffs: [String] = []
    private var window: UpdateWindowController?
    private var download: PackageDownload?
    private var connection: NSXPCConnection?
    private var installReplied = false
    private var updating: (update: AvailableUpdate, automatic: Bool)?

    private init() {
        capability = Self.findCapability()
    }

    // MARK: Opening

    /// Called as the app starts, before it opens any windows.
    func start() {
        UserDefaults.standard.register(defaults: [Self.automaticUpdatesKey: true])
        startedAt = Date()
        removeOldDownloads()
        if let handoffs = UserDefaults.standard.stringArray(forKey: Self.handoffsKey) {
            UserDefaults.standard.removeObject(forKey: Self.handoffsKey)
            // Kept as handoffs, should this copy restart to finish updating too.
            for handoff in handoffs { whenLaunched(handoff: handoff) { [weak self] in self?.onHandoff?(handoff) } }
        }
        #if DEBUG
        if let demo = UserDefaults.standard.string(forKey: "UpdateDemo") {
            startDemo(demo)
            return
        }
        #endif
        let showsSplash = Self.showsSplash
        if showsSplash { showSplash() }
        switch capability {
        case let .updatesItself(manifest, trustedHosts):
            waitsForCheck = showsSplash && UpdatePolicy.waitsForCheck(updatesItself: true, automatic: automaticUpdates)
            checkGitHub(manifest, trustedHosts: trustedHosts)
            if waitsForCheck {
                DispatchQueue.main.asyncAfter(deadline: .now() + UpdatePolicy.checkTimeout + 0.2) { [weak self] in
                    guard let self, waitsForCheck, updating == nil else { return }
                    log.info("No answer from GitHub in time: opening without it")
                    finishLaunch()
                }
            } else {
                finishLaunch()
            }
        case let .appStore(bundleIdentifier):
            checkAppStore(bundleIdentifier)
            finishLaunch()
        case let .none(reason):
            log.info("\(reason, privacy: .public)")
            finishLaunch()
        }
    }

    /// Runs `action` once the app has finished opening: at once if it has, otherwise after the splash screen. Should the
    /// app restart to finish updating first, `handoff` (if any) is given to the new copy's `onHandoff` instead.
    func whenLaunched(handoff: String? = nil, _ action: @escaping () -> Void) {
        if hasLaunched {
            action()
            return
        }
        waiting.append(action)
        if let handoff { waitingHandoffs.append(handoff) }
    }

    /// Opens presentations once the app has finished opening, or in the new copy if it restarts to finish updating
    /// first.
    func whenLaunched(opening urls: [URL]) {
        if !hasLaunched { waitingURLs += urls }
        whenLaunched {
            for url in urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error, (error as? CocoaError)?.code != .userCancelled { NSApp.presentError(error) }
                }
            }
        }
    }

    /// Opens an untitled presentation once the app has finished opening, unless one is already waiting.
    private var untitledWaiting = false
    func whenLaunchedOpenUntitled() {
        guard !untitledWaiting else { return }
        untitledWaiting = !hasLaunched
        whenLaunched { [weak self] in
            self?.untitledWaiting = false
            _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        }
    }

    /// Takes the splash screen away (once it's been up long enough) and lets what waited happen.
    private func finishLaunch() {
        guard !hasLaunched, !isFinishingLaunch else { return }
        isFinishingLaunch = true
        waitsForCheck = false
        let remaining = Self.minimumSplash - Date().timeIntervalSince(startedAt)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, window == nil ? 0 : remaining)) { [weak self] in
            guard let self else { return }
            let open = { [self] in
                hasLaunched = true
                isFinishingLaunch = false
                let opensUntitled = launchIsDefault && !untitledWaiting && waitingURLs.isEmpty && waitingHandoffs.isEmpty
                let actions = waiting
                waiting = []
                waitingURLs = []
                waitingHandoffs = []
                actions.forEach { $0() }
                if opensUntitled, NSDocumentController.shared.documents.isEmpty {
                    _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                }
            }
            if let window, updating == nil {
                self.window = nil
                window.fadeOut { open() }
            } else {
                open()
            }
        }
    }

    private static var showsSplash: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "ShowsSplash") != nil, !defaults.bool(forKey: "ShowsSplash") { return false }
        #if DEBUG
        // Automated runs (the self-tests, screenshots, the benchmark) open straight away.
        if defaults.bool(forKey: "PPSelfTest") || defaults.string(forKey: "PPSnapshot") != nil || defaults.bool(forKey: "PPBenchmark") {
            return false
        }
        #endif
        return true
    }

    private func showSplash() {
        let window = UpdateWindowController()
        self.window = window
        window.present()
    }

    // MARK: Checking

    private static func findCapability() -> Capability {
        let bundle = Bundle.main
        #if DEBUG
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: "UpdateAppStoreBundleID") { return .appStore(bundleIdentifier: identifier) }
        if let feed = defaults.string(forKey: "UpdateFeedURL").flatMap(URL.init(string:)), let host = feed.host() {
            return .updatesItself(manifest: feed, trustedHosts: [host.lowercased(), "github.com"])
        }
        #endif
        if let receipt = bundle.appStoreReceiptURL, FileManager.default.fileExists(atPath: receipt.path) {
            return .appStore(bundleIdentifier: bundle.bundleIdentifier ?? "")
        }
        #if DEBUG
        return .none("Copies built for debugging don’t update themselves.")
        #else
        guard CodeSigning.teamID != nil else { return .none("This copy wasn’t signed by its developer, so it doesn’t update itself.") }
        guard let feed = (bundle.object(forInfoDictionaryKey: "PuggleUpdateURL") as? String).flatMap(URL.init(string:)) else {
            return .none("This copy doesn’t know where its updates come from.")
        }
        return .updatesItself(manifest: feed, trustedHosts: ["github.com"])
        #endif
    }

    /// A session that gives up after the check's five seconds, keeping nothing (no cache, no cookies).
    private lazy var checkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = UpdatePolicy.checkTimeout
        configuration.timeoutIntervalForResource = UpdatePolicy.checkTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private func checkGitHub(_ manifest: URL, trustedHosts: Set<String>) {
        let current = currentVersion
        let log = log
        checkSession.dataTask(with: manifest) { @Sendable [weak self] data, response, error in
            var update: AvailableUpdate?
            let status = (response as? HTTPURLResponse)?.statusCode
            if let data, status == 200 {
                do {
                    update = try UpdateManifest.decode(data).update(over: current, trustedHosts: trustedHosts)
                } catch {
                    log.error("Update information unusable: \(String(describing: error), privacy: .public)")
                }
            } else {
                log.info("No update information (\(error?.localizedDescription ?? "HTTP \(status ?? 0)", privacy: .public))")
            }
            DispatchQueue.main.async { self?.checked(update) }
        }.resume()
    }

    private func checkAppStore(_ bundleIdentifier: String) {
        let url = AppStoreLookup.url(bundleIdentifier: bundleIdentifier, country: Locale.current.region?.identifier)
        let current = currentVersion
        checkSession.dataTask(with: url) { @Sendable [weak self] data, response, _ in
            let release = (response as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap { try? AppStoreLookup.parse($0) } : nil
            let update = AppStoreLookup.update(from: release, over: current)
            DispatchQueue.main.async { self?.checked(update) }
        }.resume()
    }

    private func checked(_ update: AvailableUpdate?) {
        if let update { log.info("Version \(update.version.description, privacy: .public) is available") }
        let declined = UserDefaults.standard.string(forKey: Self.declinedKey).flatMap(AppVersion.init)
        let action = UpdatePolicy.action(for: update, automatic: automaticUpdates, declined: declined)
        if action == .install, waitsForCheck, let update {
            waitsForCheck = false
            begin(update, automatic: true)
            return
        }
        // Too late to install it as the app opens (or not wanted now): the banner says it's there.
        if action != .none, let update { banner.show(update) }
        if waitsForCheck { finishLaunch() }
    }

    // MARK: Updating

    /// The banner's Click Here: installs the newer version, or opens its page in the App Store.
    func installFromBanner() {
        guard let update = banner.update, updating == nil else { return }
        switch update.source {
        case let .appStore(page):
            NSWorkspace.shared.open(page)
        case .github:
            begin(update, automatic: false)
        }
    }

    private func begin(_ update: AvailableUpdate, automatic: Bool) {
        guard case let .github(package, size, sha256) = update.source else { return }
        log.info("Updating to \(update.version.description, privacy: .public)")
        updating = (update, automatic)
        banner.isBusy = true
        let window = window ?? UpdateWindowController()
        self.window = window
        window.model.version = update.version.description
        window.model.total = size
        window.model.received = 0
        window.model.stage = .downloading
        window.model.canCancel = true
        window.model.onCancel = { [weak self] in self?.cancel() }
        window.present()

        let destination = Self.downloadsFolder.appendingPathComponent("\(update.version).pkg")
        // Only this version's download is worth keeping.
        for file in (try? FileManager.default.contentsOfDirectory(at: Self.downloadsFolder, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent != destination.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
        if PackageDownload.matches(destination, size: size, sha256: sha256) {
            window.model.received = size
            install(destination, update: update)
            return
        }
        download = PackageDownload(from: package, to: destination, size: size, sha256: sha256, progress: { [weak window] received in
            window?.model.received = received
        }, completion: { [weak self] result in
            guard let self, updating?.update == update else { return }
            download = nil
            switch result {
            case let .success(file):
                install(file, update: update)
            case let .failure(error):
                failed("\(appName) couldn’t download the update. \(error.localizedDescription)", decline: false)
            }
        })
        download?.start()
    }

    private func cancel() {
        guard let updating, !isInstalling else { return }
        log.info("Update to \(updating.update.version.description, privacy: .public) cancelled")
        download?.cancel()
        download = nil
        stopped(declining: updating.automatic)
    }

    private func install(_ file: URL, update: AvailableUpdate) {
        guard let window else { return }
        window.model.stage = .installing
        window.model.canCancel = false
        window.model.installStarted = false
        window.model.installFraction = 0
        isInstalling = true
        installReplied = false

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            installFinished(nil, error: UpdateInstallError.unavailable.rawValue, message: "The downloaded update couldn’t be read.")
            return
        }
        let service = UpdateInstallerService.name(forApp: Bundle.main.bundleIdentifier ?? "")
        let connection = NSXPCConnection(serviceName: service)
        connection.remoteObjectInterface = UpdateInstallerService.installingInterface
        connection.exportedInterface = UpdateInstallerService.observingInterface
        connection.exportedObject = InstallObserver { [weak self] fraction, phase, started in
            DispatchQueue.main.async { self?.installProgressed(fraction, phase: phase, started: started) }
        }
        let lost: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.async {
                self?.installFinished(nil, error: UpdateInstallError.unavailable.rawValue, message: "The update installer stopped unexpectedly.")
            }
        }
        connection.interruptionHandler = lost
        connection.invalidationHandler = lost
        connection.resume()
        self.connection = connection
        let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
            let message = error.localizedDescription
            DispatchQueue.main.async {
                self.installFinished(nil, error: UpdateInstallError.unavailable.rawValue, message: "The update installer couldn’t be reached. \(message)")
            }
        } as? UpdateInstalling
        guard let proxy else {
            installFinished(nil, error: UpdateInstallError.unavailable.rawValue, message: "The update installer couldn’t be reached.")
            return
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "UpdateDryRun") {
            proxy.verifyPackage(handle, appName: appName) { @Sendable error, message in
                DispatchQueue.main.async { self.dryRunVerified(error: error, message: message) }
            }
            return
        }
        #endif
        let prompt = "\(appName) is updating to version \(update.version). Enter an administrator’s password to install it."
        proxy.installPackage(handle, version: update.version.description, appName: appName, prompt: prompt) { @Sendable installed, error, message in
            DispatchQueue.main.async { self.installFinished(installed, error: error, message: message) }
        }
    }

    private func installProgressed(_ fraction: Double, phase: String, started: Bool) {
        guard isInstalling, let window else { return }
        window.model.installStarted = started
        window.model.installFraction = max(window.model.installFraction, fraction)
        if !phase.isEmpty { window.model.phase = phase }
    }

    private func installFinished(_ installed: String?, error: Int, message: String?) {
        guard isInstalling, !installReplied, let updating else { return }
        installReplied = true
        isInstalling = false
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        let code = UpdateInstallError(rawValue: error) ?? .failed
        if code == .none, let installed {
            log.info("Installed \(updating.update.version.description, privacy: .public) at \(installed, privacy: .public)")
            try? FileManager.default.removeItem(at: Self.downloadsFolder)
            restart(into: URL(fileURLWithPath: installed), version: updating.update.version)
        } else if code == .cancelled {
            log.info("Administrator’s password not given: update not installed")
            stopped(declining: updating.automatic)
        } else {
            log.error("Update not installed: \(message ?? "no reason given", privacy: .public)")
            failed(message ?? "The update couldn’t be installed.", decline: true)
        }
    }

    /// The update didn't go ahead: the app carries on as it is, and the banner offers the update again.
    private func stopped(declining: Bool) {
        guard let updating else { return }
        if declining { UserDefaults.standard.set(updating.update.version.description, forKey: Self.declinedKey) }
        self.updating = nil
        banner.isBusy = false
        banner.show(updating.update)
        if let window {
            self.window = nil
            window.fadeOut {}
        }
        finishLaunch()
    }

    private func failed(_ message: String, decline: Bool) {
        let alert = NSAlert()
        alert.messageText = "\(appName) couldn’t be updated"
        alert.informativeText = message + (hasLaunched ? "" : " \(appName) opens as it is.")
        alert.addButton(withTitle: "OK")
        window?.window?.orderOut(nil)
        alert.runModal()
        stopped(declining: decline && updating?.automatic == true)
    }

    /// Opens the new version in place of this one: presentations that are open close (saving as they do, and ending a
    /// slideshow), and open again in the new copy, as do any that were waiting.
    private func restart(into app: URL, version: AppVersion) {
        guard let window else { return }
        window.model.stage = .restarting
        let documents = NSDocumentController.shared.documents
        let handoffs = waitingHandoffs + (handoffsForOpenDocuments?() ?? [])
        let waitingURLs = waitingURLs
        DocumentCloser.closeAll { [weak self] closed in
            guard let self else { return }
            guard closed else {
                // Someone kept a presentation open: the new version is installed, and opens next time.
                updating = nil
                banner.isBusy = false
                self.window = nil
                window.fadeOut {}
                let alert = NSAlert()
                alert.messageText = "\(appName) \(version) is installed"
                alert.informativeText = "It opens the next time you open \(appName)."
                alert.runModal()
                finishLaunch()
                return
            }
            let urls = waitingURLs + documents.compactMap(\.fileURL)
            UserDefaults.standard.set(handoffs, forKey: Self.handoffsKey)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = true
            let appName = appName
            let opened: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { _, error in
                let problem = error?.localizedDescription
                DispatchQueue.main.async {
                    if let problem {
                        let alert = NSAlert()
                        alert.messageText = "\(appName) \(version) is installed"
                        alert.informativeText = "It couldn’t be opened just now (\(problem)). Open \(appName) again to use it."
                        alert.runModal()
                    }
                    NSApp.terminate(nil)
                }
            }
            if urls.isEmpty {
                NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: opened)
            } else {
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration, completionHandler: opened)
            }
        }
    }

    // MARK: Downloads

    /// Where downloaded updates are kept until they're installed (in the app's own container).
    static var downloadsFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Updates", isDirectory: true)
    }

    /// Downloads for this version or older are no longer needed.
    private func removeOldDownloads() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.downloadsFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let version = AppVersion(file.deletingPathExtension().lastPathComponent)
            if version == nil || version! <= currentVersion { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: Demo

    #if DEBUG
    /// `-UpdateDryRun YES` (with `-UpdateFeedURL`): the update installer only checks the downloaded package, the way it
    /// does before asking for a password. Then the installation is acted out, without the password dialog: the steps
    /// macOS's installer goes through, at about its pace, with nothing installed. The app then finishes as it does after
    /// a real update, opening a new copy of itself (the same version, here) and quitting.
    private func dryRunVerified(error: Int, message: String?) {
        guard isInstalling else { return }
        log.info("Dry run: the update installer answered \(error) \(message ?? "", privacy: .public)")
        guard error == UpdateInstallError.none.rawValue else {
            installFinished(nil, error: error, message: message)
            return
        }
        let steps: [(at: Double, fraction: Double, phase: String)] = [
            (1.5, 0.00, "Preparing for installation…"),
            (2.0, 0.04, "Preparing the disk…"),
            (2.4, 0.07, "Preparing \(appName)…"),
            (2.8, 0.09, "Waiting for other installations to complete…"),
            (3.2, 0.11, "Configuring the installation…"),
            (3.6, 0.22, "Writing files…"),
            (4.0, 0.39, "Writing files…"),
            (4.4, 0.56, "Writing files…"),
            (4.8, 0.73, "Writing files…"),
            (5.2, 0.86, "Writing files…"),
            (5.6, 0.93, "Registering updated applications…"),
            (6.0, 0.97, "Finishing the Installation…"),
            (6.4, 1.00, "The software was successfully installed."),
        ]
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.at) { [weak self] in
                self?.installProgressed(step.fraction, phase: step.phase, started: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.2) { [weak self] in
            self?.log.info("Dry run: acting as if it installed, so opening a new copy of this one")
            self?.installFinished(Bundle.main.bundlePath, error: UpdateInstallError.none.rawValue, message: nil)
        }
    }

    /// `-UpdateDemo splash|downloading|waiting|installing|restarting|banner|appstore` shows that part of updating with
    /// made-up values and no network, for screenshots. `-UpdateDemo relaunch` opens a new copy of the app and quits
    /// this one, as the end of an update does.
    private func startDemo(_ demo: String) {
        let update = AvailableUpdate(version: AppVersion("1.2.0")!, source: .github(package: URL(string: "https://github.com/")!, size: 3_795_190, sha256: ""))
        switch demo {
        case "banner":
            banner.show(update)
        case "appstore":
            banner.show(AvailableUpdate(version: AppVersion("1.2.0")!, source: .appStore(page: URL(string: "macappstore://apps.apple.com/")!)))
        case "relaunch":
            finishLaunch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { @Sendable app, error in
                    print("UpdateDemo relaunch: \(app?.processIdentifier ?? 0) \(error?.localizedDescription ?? "ok")")
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            }
            return
        default:
            let window = UpdateWindowController()
            self.window = window
            window.model.version = "1.2.0"
            window.model.total = 3_795_190
            switch demo {
            case "downloading":
                window.model.stage = .downloading
                window.model.received = 1_482_000
                window.model.canCancel = true
            case "installing":
                window.model.stage = .installing
                window.model.installStarted = true
                window.model.installFraction = 0.62
                window.model.phase = "Writing files…"
            case "waiting":
                window.model.stage = .installing
            case "restarting":
                window.model.stage = .restarting
            default:
                break
            }
            window.present()
        }
        hasLaunched = true
        waiting.forEach { $0() }
        waiting = []
        // With the demo's window up, AppKit opens no untitled presentation.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty { _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) }
        }
    }
    #endif
}

/// The banner each presentation's window shows when there's a newer version.
@Observable
final class UpdateBanner {
    private(set) var update: AvailableUpdate?
    var isDismissed = false
    /// An update is underway (in its own window), so the banner keeps out of the way.
    var isBusy = false

    var visibleUpdate: AvailableUpdate? { isDismissed || isBusy ? nil : update }

    func show(_ update: AvailableUpdate) {
        self.update = update
        isDismissed = false
    }
}

/// Downloads an update's installer package, reporting how much has arrived, and checks it's the file the release
/// describes before it's used.
nonisolated final class PackageDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let source: URL
    private let destination: URL
    private let size: Int64
    private let sha256: String
    private let progress: @MainActor (Int64) -> Void
    private let completion: @MainActor (Result<URL, Error>) -> Void
    private var session: URLSession?
    private var lastReport = Date.distantPast
    /// Set once, by whichever ends it first: the download (on its queue) or Cancel (on the main thread).
    private let lock = NSLock()
    private var finished = false

    init(from source: URL, to destination: URL, size: Int64, sha256: String,
         progress: @escaping @MainActor (Int64) -> Void, completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        self.source = source
        self.destination = destination
        self.size = size
        self.sha256 = sha256
        self.progress = progress
        self.completion = completion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: source).resume()
    }

    func cancel() {
        lock.withLock { finished = true }
        session?.invalidateAndCancel()
    }

    /// The file at `url` is the package described: the right size, with the right checksum.
    static func matches(_ url: URL, size: Int64, sha256: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.size] as? NSNumber)?.int64Value == size,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() == sha256.lowercased()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.05 else { return }
        lastReport = now
        let progress = progress
        DispatchQueue.main.async { progress(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            finish(.failure(DownloadProblem("GitHub answered with an error (HTTP \(status)).")))
            return
        }
        // The file at `location` goes when this returns, so it's moved first.
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finish(.failure(error))
            return
        }
        let progress = progress, size = size
        DispatchQueue.main.async { progress(size) }
        if Self.matches(destination, size: size, sha256: sha256) {
            finish(.success(destination))
        } else {
            try? FileManager.default.removeItem(at: destination)
            finish(.failure(DownloadProblem("The download wasn’t the file it should have been.")))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)) }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<URL, Error>) {
        let first = lock.withLock {
            defer { finished = true }
            return !finished
        }
        guard first else { return }
        let completion = completion
        DispatchQueue.main.async { completion(result) }
    }

    struct DownloadProblem: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

/// Receives the update installer's progress reports.
nonisolated final class InstallObserver: NSObject, UpdateInstallObserving, @unchecked Sendable {
    private let report: @Sendable (Double, String, Bool) -> Void

    init(_ report: @escaping @Sendable (Double, String, Bool) -> Void) {
        self.report = report
    }

    func installProgressed(_ fraction: Double, phase: String, started: Bool) {
        report(fraction, phase, started)
    }
}

/// Closes every open presentation as quitting would (saving them, or asking about those that can't be), then says
/// whether they all closed.
final class DocumentCloser: NSObject {
    private static var current: DocumentCloser?
    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func closeAll(completion: @escaping (Bool) -> Void) {
        let closer = DocumentCloser(completion: completion)
        current = closer
        NSDocumentController.shared.closeAllDocuments(withDelegate: closer, didCloseAllSelector: #selector(documentController(_:didCloseAll:contextInfo:)),
                                                      contextInfo: nil)
    }

    @objc private func documentController(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Self.current = nil
        completion(didCloseAll)
    }
}
