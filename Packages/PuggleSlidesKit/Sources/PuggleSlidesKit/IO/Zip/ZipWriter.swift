import Foundation

/// Writes a ZIP archive in memory. Entries are deflated unless that doesn't save space.
struct ZipWriter {
    private var archive = Data()
    private var directory = Data()
    private var entryCount = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    /// `date` stamps every entry, in local time as ZIP expects.
    init(date: Date = Date()) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(parts.year ?? 1980, 1980), 2107)
        dosTime = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        dosDate = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
    }

    /// Adds a file. `compress: false` stores it as is; `dataDescriptor` puts the checksum and sizes after
    /// the data instead of in the local header, as streaming writers do.
    mutating func add(_ path: String, _ contents: Data, compress: Bool = true, dataDescriptor: Bool = false) throws {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(contents)
        let deflated = compress ? Deflate.compress(contents) : nil
        let payload = deflated ?? contents
        let method: UInt16 = deflated == nil ? 0 : 8
        // Bit 11: the name is UTF-8. Bit 3: sizes and checksum follow the data.
        let flags: UInt16 = 0x0800 | (dataDescriptor ? 0x0008 : 0)
        let offset = archive.count
        // Without ZIP64, offsets and sizes must fit in 32 bits and the entry count in 16.
        guard entryCount < 0xFFFF, name.count <= 0xFFFF,
              offset + 30 + name.count + payload.count + 16 < 0xFFFF_FFFF else { throw ZipError.tooLarge }

        archive.appendLittleEndian(ZipSignature.localHeader)
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(flags)
        archive.appendLittleEndian(method)
        archive.appendLittleEndian(dosTime)
        archive.appendLittleEndian(dosDate)
        archive.appendLittleEndian(dataDescriptor ? 0 : crc)
        archive.appendLittleEndian(dataDescriptor ? 0 : UInt32(payload.count))
        archive.appendLittleEndian(dataDescriptor ? 0 : UInt32(contents.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0))
        archive.append(name)
        archive.append(payload)
        if dataDescriptor {
            archive.appendLittleEndian(ZipSignature.dataDescriptor)
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(UInt32(payload.count))
            archive.appendLittleEndian(UInt32(contents.count))
        }

        directory.appendLittleEndian(ZipSignature.centralHeader)
        directory.appendLittleEndian(UInt16(20))
        directory.appendLittleEndian(UInt16(20))
        directory.appendLittleEndian(flags)
        directory.appendLittleEndian(method)
        directory.appendLittleEndian(dosTime)
        directory.appendLittleEndian(dosDate)
        directory.appendLittleEndian(crc)
        directory.appendLittleEndian(UInt32(payload.count))
        directory.appendLittleEndian(UInt32(contents.count))
        directory.appendLittleEndian(UInt16(name.count))
        directory.appendLittleEndian(UInt16(0))
        directory.appendLittleEndian(UInt16(0))
        directory.appendLittleEndian(UInt16(0))
        directory.appendLittleEndian(UInt16(0))
        directory.appendLittleEndian(UInt32(0))
        directory.appendLittleEndian(UInt32(offset))
        directory.append(name)
        entryCount += 1
    }

    /// The finished archive: the entries, the central directory and its end record.
    func finish() throws -> Data {
        guard archive.count + directory.count < 0xFFFF_FFFF else { throw ZipError.tooLarge }
        var result = archive
        result.append(directory)
        result.appendLittleEndian(ZipSignature.endOfCentralDirectory)
        result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(UInt16(entryCount))
        result.appendLittleEndian(UInt16(entryCount))
        result.appendLittleEndian(UInt32(directory.count))
        result.appendLittleEndian(UInt32(archive.count))
        result.appendLittleEndian(UInt16(0))
        return result
    }
}

fileprivate extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
