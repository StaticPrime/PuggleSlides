import Foundation

/// A newer version than the one running, and where it comes from.
public struct AvailableUpdate: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// An installer package published in the app's GitHub releases, which the app downloads and installs itself.
        case github(package: URL, size: Int64, sha256: String)
        /// The App Store, which installs it: `page` opens the app's page there.
        case appStore(page: URL)
    }

    public var version: AppVersion
    public var source: Source

    public init(version: AppVersion, source: Source) {
        self.version = version
        self.source = source
    }

    public var isFromAppStore: Bool {
        if case .appStore = source { return true }
        return false
    }
}

/// What a release says about itself for the update check: `update.json`, which the Release workflow publishes next to
/// the installer in every GitHub release. The newest one is always at
/// `https://github.com/<owner>/<repo>/releases/latest/download/update.json`.
///
///     {"version": "1.2.0", "build": 5, "minimumSystemVersion": "14.0",
///      "url": "https://github.com/<owner>/<repo>/releases/download/v1.2.0/<App>.pkg",
///      "size": 3795190, "sha256": "774c5abf…"}
public struct UpdateManifest: Codable, Equatable, Sendable {
    public var version: String
    public var build: Int?
    public var minimumSystemVersion: String?
    public var url: URL
    public var size: Int64
    public var sha256: String

    public init(version: String, build: Int? = nil, minimumSystemVersion: String? = nil, url: URL, size: Int64, sha256: String) {
        self.version = version
        self.build = build
        self.minimumSystemVersion = minimumSystemVersion
        self.url = url
        self.size = size
        self.sha256 = sha256
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case unreadable
        case badVersion(String)
        case untrustedURL(URL)
        case badSize
        case badChecksum

        public var description: String {
            switch self {
            case .unreadable: "The update information couldn’t be read."
            case let .badVersion(version): "The update information names an unreadable version, “\(version)”."
            case let .untrustedURL(url): "The update information points somewhere unexpected (\(url.host() ?? url.absoluteString))."
            case .badSize: "The update information gives no size for the installer."
            case .badChecksum: "The update information has no valid checksum for the installer."
            }
        }
    }

    public static func decode(_ data: Data) throws -> UpdateManifest {
        do {
            return try JSONDecoder().decode(UpdateManifest.self, from: data)
        } catch {
            throw Problem.unreadable
        }
    }

    /// The update this release offers a copy running `current` on macOS `system`: nil when it isn't newer, or needs a
    /// newer macOS. The installer must be downloaded over HTTPS from one of `trustedHosts`.
    public func update(over current: AppVersion, system: AppVersion = .system,
                       trustedHosts: Set<String> = ["github.com"]) throws -> AvailableUpdate? {
        guard let version = AppVersion(version) else { throw Problem.badVersion(self.version) }
        guard let host = url.host()?.lowercased(), trustedHosts.contains(host),
              url.scheme == "https" || (url.scheme == "http" && Self.isLoopback(host)) else { throw Problem.untrustedURL(url) }
        guard size > 0 else { throw Problem.badSize }
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { throw Problem.badChecksum }
        guard version > current else { return nil }
        if let minimum = minimumSystemVersion.flatMap(AppVersion.init), system < minimum { return nil }
        return AvailableUpdate(version: version, source: .github(package: url, size: size, sha256: sha256.lowercased()))
    }

    /// Plain HTTP is only for a test server on this Mac.
    private static func isLoopback(_ host: String) -> Bool { host == "localhost" || host == "127.0.0.1" || host == "::1" }
}
