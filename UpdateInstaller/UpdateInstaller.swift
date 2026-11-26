import Foundation
import os
import PuggleUpdate
import Security

/// What the service did, in the Mac's log under the app's subsystem (category Updates).
let log = Logger(subsystem: Bundle.main.bundleIdentifier.map { $0.replacingOccurrences(of: ".UpdateInstaller", with: "") } ?? "com.pugglesoft",
                 category: "Updates")

/// The security session the service runs in. macOS asks for an administrator's password only from a session that can
/// show windows. An XPC service gets a session of its own that can't, unless its Info.plist has it join its app's
/// (XPCService ▸ JoinExistingSession); from one that can't, macOS refuses at once, with no dialog, and AppleScript says
/// the password was wrong.
enum SecuritySession {
    static var canShowDialogs: Bool {
        var session = SecuritySessionId()
        var attributes = SessionAttributeBits()
        guard SessionGetInfo(callerSecuritySession, &session, &attributes) == 0 else { return false }
        return attributes.contains(.sessionHasGraphicAccess)
    }
}

/// The update installer: an XPC service inside the app, outside its sandbox, that installs an update the app has
/// downloaded (see `UpdateInstalling`). It accepts connections only from the app it's inside, signed by the same team.
final class UpdateInstallerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let team = CodeSigning.teamID, let service = Bundle.main.bundleIdentifier {
            let app = service.hasSuffix(".UpdateInstaller") ? String(service.dropLast(".UpdateInstaller".count)) : service
            connection.setCodeSigningRequirement(#"identifier "\#(app)" and anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#)
        }
        connection.exportedInterface = UpdateInstallerService.installingInterface
        connection.remoteObjectInterface = UpdateInstallerService.observingInterface
        connection.exportedObject = PackageInstaller(connection: connection)
        connection.resume()
        log.info("Update installer: in a session that \(SecuritySession.canShowDialogs ? "can" : "can’t", privacy: .public) show macOS’s password dialog")
        return true
    }
}

/// Installs one update at a time.
final class PackageInstaller: NSObject, UpdateInstalling, @unchecked Sendable {
    private weak var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "com.pugglesoft.UpdateInstaller.install")
    private let lock = NSLock()
    private var isInstalling = false

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func installPackage(_ package: FileHandle, version: String, appName: String, prompt: String,
                        reply: @escaping @Sendable (String?, Int, String?) -> Void) {
        let observer = Observer(connection?.remoteObjectProxyWithErrorHandler { _ in } as? UpdateInstallObserving)
        lock.lock()
        let busy = isInstalling
        isInstalling = true
        lock.unlock()
        guard !busy else {
            reply(nil, UpdateInstallError.unavailable.rawValue, "An update is already being installed.")
            return
        }
        queue.async { [self] in
            let (installed, error, message) = install(package, version: version, appName: appName, prompt: prompt, observer: observer)
            lock.lock()
            isInstalling = false
            lock.unlock()
            reply(installed, error.rawValue, message)
        }
    }

    func verifyPackage(_ package: FileHandle, appName: String, reply: @escaping @Sendable (Int, String?) -> Void) {
        queue.async {
            let folder = Self.newFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            switch Self.checkedCopy(of: package, in: folder, appName: appName) {
            case .success: reply(UpdateInstallError.none.rawValue, nil)
            case let .failure(problem): reply(problem.error.rawValue, problem.message)
            }
        }
    }

    private struct Problem: Error {
        let error: UpdateInstallError
        let message: String
    }

    /// A folder of this user's that nobody else can read or change, for a copy of the package.
    private static func newFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UpdateInstaller-\(UUID().uuidString)", isDirectory: true)
    }

    /// Copies the package into `folder` and checks it's signed by this service's team and notarized. That's checked
    /// here first so a package that won't be installed never asks for a password; the command that installs it checks
    /// again, as root, on a copy only root can change.
    private static func checkedCopy(of package: FileHandle, in folder: URL, appName: String) -> Result<(copy: URL, team: String), Problem> {
        guard let team = CodeSigning.teamID else {
            return .failure(Problem(error: .unavailable, message: "This copy of \(appName) isn’t signed by its developer, so it can’t install updates."))
        }
        let copy = folder.appendingPathComponent("update.pkg")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Self.copy(package, to: copy)
        } catch {
            return .failure(Problem(error: .unavailable, message: "The downloaded update couldn’t be read."))
        }
        let signature = PackageSignature.parse(run("/usr/sbin/pkgutil", ["--check-signature", copy.path]).output)
        log.info("Update installer: package signed by \(signature.signer ?? "nobody", privacy: .public), for distribution \(signature.isSignedForDistribution), notarized \(signature.isNotarized)")
        guard signature.isFromDeveloper(team: team) else {
            return .failure(Problem(error: .untrusted, message: "The update isn’t signed by \(appName)’s developer, so it wasn’t installed."))
        }
        guard run("/usr/sbin/spctl", ["--assess", "--type", "install", copy.path]).status == 0 else {
            return .failure(Problem(error: .untrusted, message: "macOS didn’t accept the update’s signature, so it wasn’t installed."))
        }
        return .success((copy, team))
    }

    private func install(_ package: FileHandle, version: String, appName: String, prompt: String,
                         observer: Observer) -> (String?, UpdateInstallError, String?) {
        guard !appName.isEmpty, !appName.contains("/"), !appName.hasPrefix("."), AppVersion(version) != nil else {
            return (nil, .unavailable, "The update couldn’t be installed.")
        }
        let folder = Self.newFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy: URL, team: String
        switch Self.checkedCopy(of: package, in: folder, appName: appName) {
        case let .success(checked): (copy, team) = checked
        case let .failure(problem): return (nil, problem.error, problem.message)
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.pugglesoft.UpdateInstaller"
        guard let command = PrivilegedInstall(package: copy.path, workDirectory: PrivilegedInstall.newWorkDirectory(for: bundleIdentifier),
                                              teamID: team, prompt: prompt) else {
            return (nil, .unavailable, "The update couldn’t be installed.")
        }
        let watcher = ProgressWatcher(command: command, observer: observer)
        watcher.start()
        log.info("Update installer: asking for an administrator’s password to install \(version, privacy: .public)")
        let outcome = Self.runAsAdministrator(command.appleScript)
        watcher.stop()
        log.info("Update installer: the command ended with \(outcome.number.map(String.init) ?? "success", privacy: .public) \(outcome.message ?? "", privacy: .public)")

        if let number = outcome.number {
            switch number {
            case -128:
                return (nil, .cancelled, nil)
            case PrivilegedInstall.Exit.notSigned.rawValue:
                return (nil, .untrusted, "The update isn’t signed by \(appName)’s developer, so it wasn’t installed.")
            case PrivilegedInstall.Exit.rejected.rawValue:
                return (nil, .untrusted, "macOS didn’t accept the update’s signature, so it wasn’t installed.")
            case PrivilegedInstall.Exit.installFailed.rawValue:
                let said = InstallerProgress.parse(outcome.message ?? "").errors.first ?? outcome.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (nil, .failed, "macOS’s installer couldn’t install the update." + (said.map { " It said: \($0)" } ?? ""))
            default:
                // AppleScript's own words would say the password was wrong, though no one was asked for it.
                guard SecuritySession.canShowDialogs else {
                    return (nil, .failed, "macOS couldn’t ask for an administrator’s password, so the update wasn’t installed.")
                }
                return (nil, .failed, "The update couldn’t be installed." + (outcome.message.map { " \($0)" } ?? ""))
            }
        }

        // The installer puts the app in /Applications. Make sure it's the version that was meant to be installed, so
        // the app never opens itself again and again over a release that doesn't hold what it says.
        let installed = "/Applications/\(appName).app"
        let found = NSDictionary(contentsOfFile: installed + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
        guard let found, AppVersion(found) == AppVersion(version) else {
            return (nil, .failed, "The installer finished, but the \(appName) in Applications is version \(found ?? "unknown"), not \(version).")
        }
        return (installed, .none, nil)
    }

    private static func copy(_ handle: FileHandle, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try handle.seek(toOffset: 0)
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Runs AppleScript's `do shell script … with administrator privileges`, which asks for an administrator's
    /// password and then runs the command as root. AppleScript runs on the main thread; this one waits for it.
    private static func runAsAdministrator(_ source: String) -> (number: Int?, message: String?) {
        let result = Outcome()
        DispatchQueue.main.sync {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                result.number = -1
                return
            }
            script.executeAndReturnError(&error)
            if let error {
                result.number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                result.message = error[NSAppleScript.errorMessage] as? String
                log.info("Update installer: AppleScript reported \(error.description, privacy: .public)")
            }
        }
        return (result.number, result.message)
    }

    private final class Outcome: @unchecked Sendable {
        var number: Int?
        var message: String?
    }
}

/// The app's end of the connection, for progress reports.
struct Observer: @unchecked Sendable {
    let proxy: (any UpdateInstallObserving)?
    init(_ proxy: (any UpdateInstallObserving)?) { self.proxy = proxy }
}

/// Reports the installer's progress to the app while the command runs: nothing while macOS asks for the password,
/// then, once the command's folder is there, how far the installer's log says it's got.
final class ProgressWatcher {
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.pugglesoft.UpdateInstaller.progress"))

    /// What was last reported. Only the timer's queue touches it.
    private final class Reported: @unchecked Sendable {
        var progress: InstallerProgress?
    }

    init(command: PrivilegedInstall, observer: Observer) {
        let reported = Reported()
        timer.setEventHandler {
            guard FileManager.default.fileExists(atPath: command.workDirectory) else { return }
            let log = FileManager.default.contents(atPath: command.progressLog).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let progress = InstallerProgress.parse(log)
            guard progress != reported.progress else { return }
            reported.progress = progress
            observer.proxy?.installProgressed(progress.fraction ?? 0, phase: progress.phase ?? "", started: true)
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
    }

    func start() { timer.resume() }

    func stop() { timer.cancel() }
}
