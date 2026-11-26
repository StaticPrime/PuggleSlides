import Foundation
import Security

/// Who signed an installer package, read from what `pkgutil --check-signature` prints:
///
///     Package "PuggleDocs.pkg":
///        Status: signed by a developer certificate issued by Apple for distribution
///        Notarization: trusted by the Apple notary service
///        Signed with a trusted timestamp on: 2026-11-21 01:27:55 +0000
///        Certificate Chain:
///         1. Developer ID Installer: Name (ABCDE12345)
///         …
public struct PackageSignature: Equatable, Sendable {
    /// Signed with a Developer ID certificate that Apple issued, and the signature checks out.
    public var isSignedForDistribution = false
    /// Apple's notary service has checked it.
    public var isNotarized = false
    /// The certificate that signed it ("Developer ID Installer: Name (ABCDE12345)").
    public var signer: String?

    public init() {}

    public static func parse(_ output: String) -> PackageSignature {
        var signature = PackageSignature()
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("Status:") {
                signature.isSignedForDistribution = text == "Status: signed by a developer certificate issued by Apple for distribution"
            } else if text.hasPrefix("Notarization:") {
                signature.isNotarized = text.hasPrefix("Notarization: trusted by the Apple notary service")
            } else if signature.signer == nil, text.hasPrefix("1. ") {
                signature.signer = String(text.dropFirst(3))
            }
        }
        return signature
    }

    /// The team identifier in the signing certificate's name: the last thing in it, in brackets.
    public var teamID: String? {
        guard let signer, signer.hasSuffix(")"), let open = signer.lastIndex(of: "(") else { return nil }
        let team = String(signer[signer.index(after: open)..<signer.index(before: signer.endIndex)])
        return CodeSigning.isTeamID(team) ? team : nil
    }

    /// Signed for distribution with a Developer ID Installer certificate of `team`: an installer its developer made.
    public func isFromDeveloper(team: String) -> Bool {
        isSignedForDistribution && (signer?.hasPrefix("Developer ID Installer: ") ?? false) && teamID == team
    }
}

/// The running program's own signature.
public enum CodeSigning {
    /// The team that signed this program: nil when it's signed only to run on this Mac.
    public static var teamID: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              isTeamID(team) else { return nil }
        return team
    }

    /// Apple's team identifiers are ten capital letters and digits.
    public static func isTeamID(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}
