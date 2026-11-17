import Foundation

/// CRC-32 with the IEEE 802.3 polynomial, as ZIP uses it, computed eight bytes at a time.
enum CRC32 {
    /// Eight 256-entry lookup tables, one after another, for slicing-by-8.
    private static let tables: [UInt32] = {
        var tables = [UInt32](repeating: 0, count: 8 * 256)
        for index in 0..<256 {
            var crc = UInt32(index)
            for _ in 0..<8 { crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
            tables[index] = crc
        }
        for index in 0..<256 {
            var crc = tables[index]
            for slice in 1..<8 {
                crc = tables[Int(crc & 0xFF)] ^ (crc >> 8)
                tables[slice * 256 + index] = crc
            }
        }
        return tables
    }()

    static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        tables.withUnsafeBufferPointer { table in
            let count = bytes.count
            var offset = 0
            while count - offset >= 8 {
                let low = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) ^ crc
                let high = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                crc = table[7 * 256 + Int(low & 0xFF)] ^ table[6 * 256 + Int((low >> 8) & 0xFF)]
                    ^ table[5 * 256 + Int((low >> 16) & 0xFF)] ^ table[4 * 256 + Int(low >> 24)]
                    ^ table[3 * 256 + Int(high & 0xFF)] ^ table[2 * 256 + Int((high >> 8) & 0xFF)]
                    ^ table[256 + Int((high >> 16) & 0xFF)] ^ table[Int(high >> 24)]
                offset += 8
            }
            while offset < count {
                crc = table[Int((crc ^ UInt32(bytes[offset])) & 0xFF)] ^ (crc >> 8)
                offset += 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { checksum($0) }
    }
}
