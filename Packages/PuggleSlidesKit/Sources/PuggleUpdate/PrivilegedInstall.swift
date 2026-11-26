import Foundation

/// Installing an update package with an administrator's permission. The apps are installed in /Applications for every
/// user of the Mac, so changing them takes an administrator: macOS asks for one's password, and the shell command below
/// then runs as root.
///
/// The command trusts nothing it's handed. It copies the package into a folder of its own that only root can change
/// (so nothing can swap it once checked), checks that the copy is signed with a Developer ID Installer certificate of
/// the same team as the app and that Gatekeeper accepts it (it's notarized), and only then installs it with macOS's
/// installer, whose progress goes to a log the update service reads as it goes.
public struct PrivilegedInstall: Sendable {
    /// How the command ends when it stops early.
    public enum Exit: Int, Sendable {
        /// Its folder couldn't be made, or the package couldn't be copied into it.
        case setUp = 64
        /// The package isn't signed by the app's own developer.
        case notSigned = 65
        /// Gatekeeper turns the package down.
        case rejected = 66
        /// macOS's installer failed: what it said is the command's error output.
        case installFailed = 67
    }

    /// The downloaded package.
    public let package: String
    /// The folder the command makes for its copy and the installer's log.
    public let workDirectory: String
    /// The team whose Developer ID Installer certificate must have signed the package.
    public let teamID: String
    /// What the password dialog says, under macOS's own "… wants to make changes".
    public let prompt: String

    public init?(package: String, workDirectory: String, teamID: String, prompt: String) {
        guard CodeSigning.isTeamID(teamID), package.hasPrefix("/"), workDirectory.hasPrefix("/private/tmp/"),
              !workDirectory.contains(".."), !package.contains("\0"), !workDirectory.contains("\0") else { return nil }
        self.package = package
        self.workDirectory = workDirectory
        self.teamID = teamID
        self.prompt = prompt
    }

    /// A new folder name for `bundleIdentifier`'s update, in /private/tmp (which root can write to, and where nobody
    /// else can remove a folder of root's).
    public static func newWorkDirectory(for bundleIdentifier: String) -> String {
        let name = bundleIdentifier.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return "/private/tmp/\(name).update.\(UUID().uuidString)"
    }

    /// Where the installer's progress goes while it runs.
    public var progressLog: String { workDirectory + "/progress.log" }

    /// The command, for `/bin/sh -c`. `mkdir` fails if anything is already at the folder's path, so the folder is
    /// always root's own; it's removed when the command ends.
    public var shellCommand: String {
        let signer = #"^ *1\. Developer ID Installer: .* \("# + teamID + #"\)$"#
        return [
            "umask 022",
            "work=\(Self.shellQuoted(workDirectory))",
            #"/bin/mkdir -m 755 "$work" || exit 64"#,
            #"trap '/bin/rm -rf "$work"' EXIT"#,
            #"/bin/cp \#(Self.shellQuoted(package)) "$work/update.pkg" || exit 64"#,
            #"/usr/sbin/pkgutil --check-signature "$work/update.pkg" | /usr/bin/grep -Eq \#(Self.shellQuoted(signer)) || exit 65"#,
            #"/usr/sbin/spctl --assess --type install "$work/update.pkg" > /dev/null 2>&1 || exit 66"#,
            #"/usr/sbin/installer -pkg "$work/update.pkg" -target / -verboseR > "$work/progress.log" 2>&1 || { /usr/bin/tail -n 5 "$work/progress.log" >&2; exit 67; }"#,
        ].joined(separator: "; ")
    }

    /// The AppleScript that runs the command as root, once macOS has asked for an administrator's password.
    public var appleScript: String {
        let prompt = prompt.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return "do shell script \(Self.appleScriptString(shellCommand)) with prompt \(Self.appleScriptString(prompt)) with administrator privileges"
    }

    /// `text` as one word for the shell, in single quotes.
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// `text` as an AppleScript string literal.
    public static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
