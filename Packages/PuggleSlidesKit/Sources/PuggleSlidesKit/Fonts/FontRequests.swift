import CoreText
import Foundation

/// Everything in the package that makes Core Text ask the system's font service for fonts: making a font of a family
/// or name the process hasn't used yet, and laying out text, which finds fonts for characters a font lacks.
///
/// The service has been seen to stop answering a process for good when that process has many requests waiting at once
/// while another process also asks for fonts (two test runs side by side, or tests beside Quick Look or the app). So
/// requests go through here one thread at a time, fonts are asked for once by family and style and made in other sizes
/// from the font already found, and families that aren't installed are never asked for: Core Text then looks for
/// downloadable fonts, which can block for a long time.
final class FontRequests: @unchecked Sendable {
    static let shared = FontRequests()

    /// Recursive, so work done under it (laying out a table's text) can make the fonts it needs.
    private let lock = NSRecursiveLock()
    private var faces: [Face: CTFont] = [:]
    /// Far more families and styles than real presentations use; damaged files can name any number.
    private let faceLimit = 512

    private struct Face: Hashable {
        var family: String
        var bold: Bool
        var italic: Bool
    }

    /// Runs `body`, which may make Core Text ask for fonts, while no other thread does through here.
    func one<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// The installed font families by their lowercased names, read once. Only ever touched under the lock, so the
    /// lock is always taken before the list is first read, never while it is.
    private static let installedFamilies: [String: String] = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return Dictionary(names.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// `family` as installed, whatever its case; nil when it isn't installed.
    static func installedName(_ family: String) -> String? {
        shared.one { installedFamilies[family.lowercased()] }
    }

    /// `family` at `size`, bold and italic as asked; Arial, as the editor shows them, for families that aren't
    /// installed. The style falls back to the family's regular face when it has no such face.
    func font(family: String, size: Double, bold: Bool, italic: Bool) -> CTFont {
        one {
            let key = Face(family: Self.installedName(family) ?? "Arial", bold: bold, italic: italic)
            let face: CTFont
            if let known = faces[key] {
                face = known
            } else {
                if faces.count >= faceLimit { faces.removeAll() }
                face = Self.face(key)
                faces[key] = face
            }
            return CTFontCreateCopyWithAttributes(face, CGFloat(size), nil, nil)
        }
    }

    private static func face(_ key: Face) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: key.family] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        var traits: CTFontSymbolicTraits = []
        if key.bold { traits.insert(.traitBold) }
        if key.italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return font }
        return CTFontCreateCopyWithSymbolicTraits(font, 12, nil, traits, traits) ?? font
    }
}
