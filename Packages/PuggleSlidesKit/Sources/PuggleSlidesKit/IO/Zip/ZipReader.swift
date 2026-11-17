import Foundation

/// Why a ZIP archive couldn't be read or written.
enum ZipError: Error, Equatable {
    /// Not a ZIP archive at all.
    case notAZip
    /// A ZIP archive with a broken structure, bad compressed data or a wrong checksum.
    case damaged
    /// ZIP64, encryption, or a compression method other than stored and deflate.
    case unsupported
    /// Expanding the entries would exceed the size limit, or the archive would need ZIP64.
    case tooLarge
}

enum ZipSignature {
    static let localHeader: UInt32 = 0x0403_4B50
    static let centralHeader: UInt32 = 0x0201_4B50
    static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    static let dataDescriptor: UInt32 = 0x0807_4B50
}

/// One file in a ZIP archive, as the central directory describes it.
struct ZipEntry: Hashable, Sendable {
    var path: String
    var method: UInt16
    var flags: UInt16
    var crc32: UInt32
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int

    var isDirectory: Bool { path.hasSuffix("/") }
    var isEncrypted: Bool { flags & 1 != 0 }
}

/// Reads an in-memory ZIP archive (stored and deflated entries, no ZIP64). Sizes and checksums come
/// from the central directory, so entries written with data descriptors read fine. Every entry read
/// counts against `sizeLimit`, which stops archives that expand to absurd sizes (zip bombs).
final class ZipReader {
    static let defaultSizeLimit = 1 << 30

    /// Entries in central-directory order.
    let entries: [ZipEntry]
    private let data: Data
    private let exactPaths: [String: Int]
    private let foldedPaths: [String: Int]
    private var remainingSize: Int

    init(data: Data, sizeLimit: Int = ZipReader.defaultSizeLimit) throws {
        self.data = data
        remainingSize = sizeLimit
        let entries = try data.withUnsafeBytes { try ZipReader.centralDirectory(in: $0) }
        self.entries = entries
        var exact: [String: Int] = [:]
        var folded: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            if exact[entry.path] == nil { exact[entry.path] = index }
            let key = entry.path.lowercased()
            if folded[key] == nil { folded[key] = index }
        }
        exactPaths = exact
        foldedPaths = folded
    }

    /// Looks a path up exactly, then ignoring case (package part names are case-insensitive).
    func entry(_ path: String) -> ZipEntry? {
        let key = ZipReader.normalized(path)
        guard let index = exactPaths[key] ?? foldedPaths[key.lowercased()] else { return nil }
        return entries[index]
    }

    func contains(_ path: String) -> Bool { entry(path) != nil }

    /// The contents of the file at `path`, or nil when the archive has no such file.
    func read(_ path: String) throws -> Data? {
        guard let entry = entry(path) else { return nil }
        return try read(entry)
    }

    func read(_ entry: ZipEntry) throws -> Data {
        guard !entry.isEncrypted, entry.method == 0 || entry.method == 8 else { throw ZipError.unsupported }
        guard entry.uncompressedSize <= remainingSize else { throw ZipError.tooLarge }
        remainingSize -= entry.uncompressedSize
        let contents = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Data in
            let header = entry.localHeaderOffset
            guard header >= 0, header <= bytes.count - 30, bytes.zipUInt32(at: header) == ZipSignature.localHeader else {
                throw ZipError.damaged
            }
            // The local header's name and extra field may differ in length from the central directory's.
            let start = header + 30 + Int(bytes.zipUInt16(at: header + 26)) + Int(bytes.zipUInt16(at: header + 28))
            guard start <= bytes.count, entry.compressedSize <= bytes.count - start else { throw ZipError.damaged }
            let payload = UnsafeRawBufferPointer(rebasing: bytes[start..<(start + entry.compressedSize)])
            if entry.method == 0 {
                guard entry.compressedSize == entry.uncompressedSize else { throw ZipError.damaged }
                return Data(payload)
            }
            return try Deflate.decompress(payload, expectedSize: entry.uncompressedSize)
        }
        guard CRC32.checksum(contents) == entry.crc32 else { throw ZipError.damaged }
        return contents
    }

    /// Forward slashes and no leading slash, as part names appear in relationships.
    static func normalized(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    private static func centralDirectory(in bytes: UnsafeRawBufferPointer) throws -> [ZipEntry] {
        let count = bytes.count
        guard count >= 22 else { throw ZipError.notAZip }
        // The end-of-central-directory record closes the archive, before a comment of up to 64 KB.
        var end = -1
        var position = count - 22
        let lowest = max(0, count - 22 - 0xFFFF)
        while position >= lowest {
            if bytes.zipUInt32(at: position) == ZipSignature.endOfCentralDirectory {
                end = position
                break
            }
            position -= 1
        }
        guard end >= 0 else { throw ZipError.notAZip }
        let entryCount = Int(bytes.zipUInt16(at: end + 10))
        let directorySize = Int(bytes.zipUInt32(at: end + 12))
        let directoryOffset = Int(bytes.zipUInt32(at: end + 16))
        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipError.unsupported
        }
        guard directoryOffset <= end, directorySize <= end - directoryOffset else { throw ZipError.damaged }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard cursor <= end - 46, bytes.zipUInt32(at: cursor) == ZipSignature.centralHeader else { throw ZipError.damaged }
            let compressedSize = bytes.zipUInt32(at: cursor + 20)
            let uncompressedSize = bytes.zipUInt32(at: cursor + 24)
            let localHeaderOffset = bytes.zipUInt32(at: cursor + 42)
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                throw ZipError.unsupported
            }
            let nameLength = Int(bytes.zipUInt16(at: cursor + 28))
            let extraLength = Int(bytes.zipUInt16(at: cursor + 30))
            let commentLength = Int(bytes.zipUInt16(at: cursor + 32))
            let nameStart = cursor + 46
            guard nameLength <= end - nameStart else { throw ZipError.damaged }
            let name = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[nameStart..<(nameStart + nameLength)]), as: UTF8.self)
            entries.append(ZipEntry(path: normalized(name), method: bytes.zipUInt16(at: cursor + 10), flags: bytes.zipUInt16(at: cursor + 8),
                                    crc32: bytes.zipUInt32(at: cursor + 16), compressedSize: Int(compressedSize),
                                    uncompressedSize: Int(uncompressedSize), localHeaderOffset: Int(localHeaderOffset)))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }
}

extension UnsafeRawBufferPointer {
    func zipUInt16(at offset: Int) -> UInt16 {
        UInt16(littleEndian: loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }

    func zipUInt32(at offset: Int) -> UInt32 {
        UInt32(littleEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
