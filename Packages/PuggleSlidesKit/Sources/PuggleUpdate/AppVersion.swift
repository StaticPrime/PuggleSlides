import Foundation

/// A version number as the apps write it, MAJOR.MINOR.FIX ("1.2.3"), compared part by part, so 1.10.0 comes after
/// 1.9.0. A leading "v", as release tags have, is allowed, and missing parts count as 0, so 14.0 is the same as 14.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = Substring(text.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 9, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(piece) else { return nil }
            parts.append(value)
        }
        self.parts = parts
    }

    public init(_ version: OperatingSystemVersion) {
        parts = [version.majorVersion, version.minorVersion, version.patchVersion]
    }

    /// The running copy of macOS.
    public static var system: AppVersion { AppVersion(ProcessInfo.processInfo.operatingSystemVersion) }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// The parts without trailing zeros, which don't change the version.
    private var significantParts: ArraySlice<Int> {
        var parts = parts[...]
        while parts.count > 1, parts.last == 0 { parts = parts.dropLast() }
        return parts
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.significantParts == rhs.significantParts }

    public func hash(into hasher: inout Hasher) { hasher.combine(Array(significantParts)) }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
