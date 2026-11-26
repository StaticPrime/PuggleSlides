import Foundation

/// What an app does about updates as it opens.
public enum UpdatePolicy {
    /// How long the update check may take as the app opens. When GitHub or the App Store hasn't answered by then, the
    /// app opens without it.
    public static let checkTimeout: TimeInterval = 5

    public enum Action: Equatable, Sendable {
        /// Nothing to do: there's no newer version.
        case none
        /// Say there's a newer version (a banner at the top of the window), and install it only when asked.
        case banner
        /// Download and install it now, then open the new version.
        case install
    }

    /// Whether opening waits for the update check (up to `checkTimeout`): only when a newer version would be installed
    /// straight away, that is, when the app updates itself and Automatic Updates is on.
    public static func waitsForCheck(updatesItself: Bool, automatic: Bool) -> Bool { updatesItself && automatic }

    /// What to do about `update` as the app opens. A version the person stopped installing (or that failed to install)
    /// isn't installed again by itself: the banner offers it instead, until a newer one comes out.
    public static func action(for update: AvailableUpdate?, automatic: Bool, declined: AppVersion?) -> Action {
        guard let update else { return .none }
        guard !update.isFromAppStore, automatic else { return .banner }
        if let declined, declined >= update.version { return .banner }
        return .install
    }
}
