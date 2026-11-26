import Foundation

/// Asking the App Store which version of an app it has, for a copy installed from the App Store (which the App Store
/// updates, so the app only says when there's a new version).
public enum AppStoreLookup {
    /// Apple's public lookup for an app by its bundle identifier, in the store of `country` (a two-letter region code).
    public static func url(bundleIdentifier: String, country: String?) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        var items = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let country, country.count == 2, country.allSatisfy({ $0.isASCII && $0.isLetter }) {
            items.append(URLQueryItem(name: "country", value: country.lowercased()))
        }
        components.queryItems = items
        return components.url!
    }

    /// The App Store's answer: its newest version and the page to open, or nil if the store doesn't have the app.
    public struct Release: Equatable, Sendable {
        public var version: AppVersion
        public var trackID: Int
        public var minimumSystemVersion: AppVersion?

        /// The app's page in the App Store app.
        public var page: URL { URL(string: "macappstore://apps.apple.com/app/id\(trackID)")! }
    }

    public static func parse(_ data: Data) throws -> Release? {
        struct Answer: Decodable {
            struct Result: Decodable {
                var version: String?
                var trackId: Int?
                var minimumOsVersion: String?
            }
            var results: [Result]
        }
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw UpdateManifest.Problem.unreadable
        }
        guard let result = answer.results.first, let version = result.version.flatMap(AppVersion.init),
              let trackID = result.trackId else { return nil }
        return Release(version: version, trackID: trackID, minimumSystemVersion: result.minimumOsVersion.flatMap(AppVersion.init))
    }

    /// The update the App Store offers a copy running `current` on macOS `system`, if it has a newer version.
    public static func update(from release: Release?, over current: AppVersion, system: AppVersion = .system) -> AvailableUpdate? {
        guard let release, release.version > current else { return nil }
        if let minimum = release.minimumSystemVersion, system < minimum { return nil }
        return AvailableUpdate(version: release.version, source: .appStore(page: release.page))
    }
}
