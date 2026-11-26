import Foundation
import Testing
@testable import PuggleUpdate

/// Version numbers compare part by part, as numbers.
struct AppVersionTests {
    @Test func comparesPartByPart() throws {
        let v = { (text: String) in try #require(AppVersion(text)) }
        #expect(try v("1.10.0") > v("1.9.9"))
        #expect(try v("2.0.0") > v("1.99.99"))
        #expect(try v("1.2.3") < v("1.2.4"))
        #expect(try v("v1.2.0") == v("1.2.0"))
        #expect(try v("14") == v("14.0.0"))
        #expect(try v("14.0") < v("14.0.1"))
        #expect(Set([try v("1.2"), try v("1.2.0")]).count == 1)
        #expect(try v("1.2.3").description == "1.2.3")
    }

    @Test func refusesWhatIsntAVersion() {
        for text in ["", "v", "1..2", "1.2.", "1.2.3-beta", "one", "1.2.3.4.5", "١.٢", "1.2.9999999999"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }
}

/// `update.json` from a release, and what it offers the running copy.
struct UpdateManifestTests {
    static let json = """
    {"version": "1.2.0", "build": 5, "minimumSystemVersion": "14.0",
     "url": "https://github.com/StaticPrime/PuggleDocs/releases/download/v1.2.0/PuggleDocs.pkg",
     "size": 3795190, "sha256": "774C5ABF2F3BC62CAA8EAE525AFEBCD3AD5B8EF8D3340AB0A1CAF832C4931F97"}
    """

    @Test func offersANewerVersion() throws {
        let manifest = try UpdateManifest.decode(Data(Self.json.utf8))
        let update = try #require(try manifest.update(over: AppVersion("1.1.1")!, system: AppVersion("14.5")!))
        #expect(update.version == AppVersion("1.2.0"))
        #expect(update.source == .github(package: manifest.url, size: 3_795_190,
                                         sha256: "774c5abf2f3bc62caa8eae525afebcd3ad5b8ef8d3340ab0a1caf832c4931f97"))
        #expect(!update.isFromAppStore)
    }

    @Test func offersNothingWhenNotNewerOrTheMacIsTooOld() throws {
        let manifest = try UpdateManifest.decode(Data(Self.json.utf8))
        #expect(try manifest.update(over: AppVersion("1.2.0")!, system: AppVersion("15.0")!) == nil)
        #expect(try manifest.update(over: AppVersion("1.3.0")!, system: AppVersion("15.0")!) == nil)
        var needsNewer = manifest
        needsNewer.minimumSystemVersion = "26.0"
        #expect(try needsNewer.update(over: AppVersion("1.1.1")!, system: AppVersion("15.6")!) == nil)
        #expect(try needsNewer.update(over: AppVersion("1.1.1")!, system: AppVersion("26.0")!) != nil)
    }

    @Test func refusesInstallersFromAnywhereButGitHubOverHTTPS() throws {
        var manifest = try UpdateManifest.decode(Data(Self.json.utf8))
        for url in ["http://github.com/a/b.pkg", "https://example.com/b.pkg", "https://github.com.example.com/b.pkg", "file:///tmp/b.pkg"] {
            manifest.url = URL(string: url)!
            #expect(throws: UpdateManifest.Problem.self, "\(url)") { try manifest.update(over: AppVersion("1.0")!) }
        }
        // A test server on this Mac, when it's trusted.
        manifest.url = URL(string: "http://127.0.0.1:8123/PuggleDocs.pkg")!
        #expect(try manifest.update(over: AppVersion("1.0")!, system: AppVersion("15")!, trustedHosts: ["127.0.0.1"]) != nil)
    }

    @Test func refusesBadSizesChecksumsAndVersions() throws {
        let manifest = try UpdateManifest.decode(Data(Self.json.utf8))
        var broken = manifest
        broken.size = 0
        #expect(throws: UpdateManifest.Problem.badSize) { try broken.update(over: AppVersion("1.0")!) }
        broken = manifest
        broken.sha256 = "abc"
        #expect(throws: UpdateManifest.Problem.badChecksum) { try broken.update(over: AppVersion("1.0")!) }
        broken = manifest
        broken.version = "next"
        #expect(throws: UpdateManifest.Problem.badVersion("next")) { try broken.update(over: AppVersion("1.0")!) }
        #expect(throws: UpdateManifest.Problem.unreadable) { try UpdateManifest.decode(Data("<html>Not Found</html>".utf8)) }
    }
}

/// The App Store's answer about an app installed from it.
struct AppStoreLookupTests {
    @Test func readsTheStoresVersion() throws {
        let answer = """
        {"resultCount": 1, "results": [{"kind": "mac-software", "version": "2.4.1", "trackId": 1234567890,
         "minimumOsVersion": "26.0", "trackViewUrl": "https://apps.apple.com/us/app/example/id1234567890?mt=12"}]}
        """
        let release = try #require(try AppStoreLookup.parse(Data(answer.utf8)))
        #expect(release.version == AppVersion("2.4.1"))
        #expect(release.page == URL(string: "macappstore://apps.apple.com/app/id1234567890"))
        let update = try #require(AppStoreLookup.update(from: release, over: AppVersion("2.4.0")!, system: AppVersion("26.0")!))
        #expect(update.isFromAppStore)
        #expect(AppStoreLookup.update(from: release, over: AppVersion("2.4.1")!, system: AppVersion("26.0")!) == nil)
        #expect(AppStoreLookup.update(from: release, over: AppVersion("2.4.0")!, system: AppVersion("15.0")!) == nil)
    }

    @Test func notInTheStore() throws {
        #expect(try AppStoreLookup.parse(Data(#"{"resultCount": 0, "results": []}"#.utf8)) == nil)
        #expect(throws: UpdateManifest.Problem.self) { try AppStoreLookup.parse(Data("nope".utf8)) }
    }

    @Test func asksTheRightStore() {
        let url = AppStoreLookup.url(bundleIdentifier: "com.pugglesoft.PuggleDocs", country: "GB")
        #expect(url.absoluteString == "https://itunes.apple.com/lookup?bundleId=com.pugglesoft.PuggleDocs&country=gb")
        #expect(AppStoreLookup.url(bundleIdentifier: "com.pugglesoft.PuggleDocs", country: "419").query == "bundleId=com.pugglesoft.PuggleDocs")
    }
}

/// What happens as the app opens.
struct UpdatePolicyTests {
    let github = AvailableUpdate(version: AppVersion("1.2.0")!, source: .github(package: URL(string: "https://github.com/a/b.pkg")!, size: 1, sha256: ""))
    let store = AvailableUpdate(version: AppVersion("1.2.0")!, source: .appStore(page: URL(string: "macappstore://apps.apple.com/app/id1")!))

    @Test func installsOnlyWhenAutomaticAndNotDeclined() {
        #expect(UpdatePolicy.action(for: nil, automatic: true, declined: nil) == .none)
        #expect(UpdatePolicy.action(for: github, automatic: true, declined: nil) == .install)
        #expect(UpdatePolicy.action(for: github, automatic: false, declined: nil) == .banner)
        #expect(UpdatePolicy.action(for: github, automatic: true, declined: AppVersion("1.2.0")) == .banner)
        #expect(UpdatePolicy.action(for: github, automatic: true, declined: AppVersion("1.1.9")) == .install)
        // The App Store installs its own updates.
        #expect(UpdatePolicy.action(for: store, automatic: true, declined: nil) == .banner)
    }

    @Test func waitsOnlyForUpdatesItInstallsStraightAway() {
        #expect(UpdatePolicy.waitsForCheck(updatesItself: true, automatic: true))
        #expect(!UpdatePolicy.waitsForCheck(updatesItself: true, automatic: false))
        #expect(!UpdatePolicy.waitsForCheck(updatesItself: false, automatic: true))
        #expect(UpdatePolicy.checkTimeout == 5)
    }
}

/// macOS's installer's progress, as `installer -verboseR` prints it.
struct InstallerProgressTests {
    @Test func followsTheInstaller() {
        var output = """
        installer:PHASE:Preparing for installation…
        installer:STATUS:
        installer:%9.750000
        installer:PHASE:Writing files…
        installer:%62.181818

        """
        var progress = InstallerProgress.parse(output)
        #expect(progress.phase == "Writing files…")
        #expect(abs((progress.fraction ?? 0) - 0.62181818) < 0.000001)
        #expect(!progress.succeeded)
        output += """
        installer:PHASE:Registering updated applications…
        installer:%97.750000
        installer:PHASE:The software was successfully installed.
        installer: The upgrade was successful.

        """
        progress = InstallerProgress.parse(output)
        #expect(progress.succeeded)
        #expect(progress.fraction == 1)
        #expect(progress.errors.isEmpty)
    }

    @Test func notesErrors() {
        let progress = InstallerProgress.parse("installer: Error - the package path specified was invalid: 'x.pkg'.\ninstaller: Cannot install on volume / because it is disabled.\n")
        #expect(progress.errors.count == 2)
        #expect(progress.fraction == nil)
    }

    @Test func neverGoesBackwards() {
        #expect(InstallerProgress.parse("installer:%50\ninstaller:%20\n").fraction == 0.5)
    }
}

/// Who signed an installer package, as `pkgutil --check-signature` says.
struct PackageSignatureTests {
    static let notarized = """
    Package "PuggleDocs.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-11-21 01:27:55 +0000
       Certificate Chain:
        1. Developer ID Installer: Example Developer (ABCDE12345)
           Expires: 2027-12-19 17:39:32 +0000
           SHA256 Fingerprint:
               B2 94 94 87 FC 03 EB 76 D9 F8 22 B0 02 E9 5D 84 C9 10 C6 47 E2 26
               37 76 D1 20 37 1D D3 56 1A 1D
           ------------------------------------------------------------------------
        2. Developer ID Certification Authority
           Expires: 2031-09-17 00:00:00 +0000
        3. Apple Root CA
           Expires: 2035-02-09 21:40:36 +0000

    """

    @Test func readsTheSigner() {
        let signature = PackageSignature.parse(Self.notarized)
        #expect(signature.isSignedForDistribution)
        #expect(signature.isNotarized)
        #expect(signature.signer == "Developer ID Installer: Example Developer (ABCDE12345)")
        #expect(signature.teamID == "ABCDE12345")
        #expect(signature.isFromDeveloper(team: "ABCDE12345"))
        #expect(!signature.isFromDeveloper(team: "ZZZZZ99999"))
    }

    @Test func refusesOtherSignatures() {
        let unsigned = PackageSignature.parse("Package \"x.pkg\":\n   Status: no signature\n")
        #expect(!unsigned.isFromDeveloper(team: "ABCDE12345"))
        let applicationCertificate = PackageSignature.parse(Self.notarized.replacingOccurrences(of: "Developer ID Installer", with: "Developer ID Application"))
        #expect(!applicationCertificate.isFromDeveloper(team: "ABCDE12345"))
        let untrusted = PackageSignature.parse(Self.notarized.replacingOccurrences(of: "issued by Apple for distribution", with: "that is not trusted"))
        #expect(!untrusted.isFromDeveloper(team: "ABCDE12345"))
    }

    @Test func teamIdentifiers() {
        #expect(CodeSigning.isTeamID("ABCDE12345"))
        for text in ["abcde12345", "ABCDE1234", "ABCDE123456", "ABCDE 1234", "ABCDE1234)"] { #expect(!CodeSigning.isTeamID(text), "\(text)") }
    }
}

/// The command that installs an update as root, and the AppleScript that runs it.
struct PrivilegedInstallTests {
    /// What the shell makes of a word.
    private func shell(_ script: String) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    @Test func quotesForTheShell() throws {
        for text in ["plain", "with space", "it's", "'", "a\"b", "$HOME `id` \\n *", "/var/folders/x y/T/Puggle's \"update\".pkg"] {
            #expect(try shell("printf %s \(PrivilegedInstall.shellQuoted(text))").output == text)
        }
    }

    @Test func quotesForAppleScript() throws {
        for text in ["plain", "a \"quoted\" word", #"back\slash"#, #"both \" and \\"#] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "return \(PrivilegedInstall.appleScriptString(text))"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines) == text)
        }
    }

    @Test func refusesUnsafeSettings() {
        #expect(PrivilegedInstall(package: "/tmp/a.pkg", workDirectory: "/private/tmp/x", teamID: "bad", prompt: "") == nil)
        #expect(PrivilegedInstall(package: "a.pkg", workDirectory: "/private/tmp/x", teamID: "ABCDE12345", prompt: "") == nil)
        #expect(PrivilegedInstall(package: "/tmp/a.pkg", workDirectory: "/Users/x/work", teamID: "ABCDE12345", prompt: "") == nil)
        #expect(PrivilegedInstall(package: "/tmp/a.pkg", workDirectory: "/private/tmp/../etc", teamID: "ABCDE12345", prompt: "") == nil)
        let work = PrivilegedInstall.newWorkDirectory(for: "com.pugglesoft.PuggleDocs; rm -rf /")
        #expect(work.hasPrefix("/private/tmp/com.pugglesoft.PuggleDocsrm-rf.update."))
    }

    @Test func theAppleScriptAsksForAnAdministrator() throws {
        let install = try #require(PrivilegedInstall(package: "/tmp/a.pkg", workDirectory: "/private/tmp/w", teamID: "ABCDE12345",
                                                     prompt: "PuggleDocs is updating to version 1.2.0.\nIt’s quick."))
        #expect(install.appleScript.hasPrefix("do shell script \""))
        #expect(install.appleScript.hasSuffix(" with prompt \"PuggleDocs is updating to version 1.2.0. It’s quick.\" with administrator privileges"))
        #expect(install.progressLog == "/private/tmp/w/progress.log")
    }

    /// Run without root, the command gets as far as checking the package, turns down one that isn't signed by the
    /// developer, and leaves nothing behind.
    @Test func turnsDownAPackageItsDeveloperDidntSign() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PuggleUpdateTests-\(UUID().uuidString)")
        let payload = folder.appendingPathComponent("root/Example.app/Contents")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("<plist/>".utf8).write(to: payload.appendingPathComponent("Info.plist"))
        let package = folder.appendingPathComponent("unsigned.pkg")
        let build = try shell("/usr/bin/pkgbuild --quiet --root \(PrivilegedInstall.shellQuoted(folder.appendingPathComponent("root").path)) --identifier com.example.test --version 1.0 --install-location /Applications \(PrivilegedInstall.shellQuoted(package.path))")
        try #require(build.status == 0, "pkgbuild: \(build.error)")

        let work = PrivilegedInstall.newWorkDirectory(for: "com.pugglesoft.Tests")
        let install = try #require(PrivilegedInstall(package: package.path, workDirectory: work, teamID: "ABCDE12345", prompt: ""))
        let result = try shell(install.shellCommand)
        #expect(Int(result.status) == PrivilegedInstall.Exit.notSigned.rawValue, "\(result)")
        #expect(!FileManager.default.fileExists(atPath: work))

        // Something already at the folder's path stops it before anything is copied.
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: work) }
        #expect(Int(try shell(install.shellCommand).status) == PrivilegedInstall.Exit.setUp.rawValue)
    }
}
