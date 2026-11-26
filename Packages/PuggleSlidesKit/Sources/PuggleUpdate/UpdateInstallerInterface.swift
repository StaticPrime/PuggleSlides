import Foundation

/// The update installer: an XPC service inside the app (Contents/XPCServices/UpdateInstaller.xpc) that installs a
/// downloaded update. The app itself runs in Apple's app sandbox, which can't change anything in /Applications, so the
/// service runs outside it, and does only this. It accepts connections only from the app it's inside.
@objc public protocol UpdateInstalling {
    /// Installs the installer package `package` with an administrator's permission (macOS asks for the password, with
    /// `prompt` under its own words), checking first that the package is signed by the same team as the service and
    /// notarized. Replies with the path of the installed app, or an `UpdateInstallError` code and what went wrong.
    func installPackage(_ package: FileHandle, version: String, appName: String, prompt: String,
                        reply: @escaping @Sendable (_ installedApp: String?, _ error: Int, _ message: String?) -> Void)

    /// Checks `package` as `installPackage` does before asking for a password (signed by the same team as the service,
    /// and notarized), without installing it. Replies with an `UpdateInstallError` code and what's wrong.
    func verifyPackage(_ package: FileHandle, appName: String, reply: @escaping @Sendable (_ error: Int, _ message: String?) -> Void)
}

/// What the app hears from the update installer while it installs.
@objc public protocol UpdateInstallObserving {
    /// `started` is false while macOS is still asking for an administrator's password. `fraction` runs from 0 to 1.
    func installProgressed(_ fraction: Double, phase: String, started: Bool)
}

/// How an installation ended, as the update installer replies.
public enum UpdateInstallError: Int, Sendable {
    case none = 0
    /// The person cancelled the password dialog.
    case cancelled = 1
    /// The package isn't signed by the app's developer, or isn't notarized.
    case untrusted = 2
    /// macOS's installer failed.
    case failed = 3
    /// This copy can't install updates (it isn't signed by a team), or the service couldn't do its part.
    case unavailable = 4
}

public enum UpdateInstallerService {
    /// The service's name (its bundle identifier) inside the app with `appBundleIdentifier`.
    public static func name(forApp appBundleIdentifier: String) -> String { appBundleIdentifier + ".UpdateInstaller" }

    /// The interfaces both ends set up.
    public static var installingInterface: NSXPCInterface { NSXPCInterface(with: UpdateInstalling.self) }
    public static var observingInterface: NSXPCInterface { NSXPCInterface(with: UpdateInstallObserving.self) }
}
