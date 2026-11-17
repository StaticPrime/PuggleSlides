import Compression
import Foundation

/// Raw DEFLATE (RFC 1951), the ZIP "deflate" method, through the Compression framework
/// (whose COMPRESSION_ZLIB is raw DEFLATE without the zlib header).
enum Deflate {
    /// The compressed bytes, or nil when compressing doesn't make the data smaller.
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        // A destination as large as the input: anything that doesn't fit isn't worth storing compressed.
        let capacity = data.count
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let target = destination.baseAddress, let input = source.baseAddress else { return 0 }
                return compression_encode_buffer(target.assumingMemoryBound(to: UInt8.self), capacity,
                                                 input.assumingMemoryBound(to: UInt8.self), source.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written
        return output
    }

    /// Inflates `source`, which must expand to exactly `expectedSize` bytes: a stream that would expand
    /// further is refused without being expanded, which keeps lying size fields (zip bombs) harmless.
    static func decompress(_ source: UnsafeRawBufferPointer, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        guard let input = source.baseAddress, !source.isEmpty else { throw ZipError.damaged }
        // One spare byte tells "exactly expectedSize" apart from "more than that".
        let capacity = expectedSize + 1
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            guard let target = destination.baseAddress else { return 0 }
            return compression_decode_buffer(target.assumingMemoryBound(to: UInt8.self), capacity,
                                             input.assumingMemoryBound(to: UInt8.self), source.count,
                                             nil, COMPRESSION_ZLIB)
        }
        guard written == expectedSize else { throw ZipError.damaged }
        output.count = expectedSize
        return output
    }
}
