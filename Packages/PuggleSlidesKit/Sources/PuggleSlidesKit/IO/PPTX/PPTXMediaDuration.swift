import Foundation

/// How long a movie or sound plays, from its container's headers: MPEG-4 and QuickTime (the movie header, `mvhd`), WAV and
/// AVI (RIFF), AIFF, Windows Media (ASF) and MP3. PowerPoint trims a clip's end by how much is cut off it ([MS-PPTX]
/// 2.3.3.18), so a clip's end time becomes a trim, and back, only knowing its length. Nil when the format isn't one of
/// these or the file is damaged. Only headers are read, and every walk through boxes, chunks or objects is bounded.
enum PPTXMediaDuration {
    static func seconds(of data: Data) -> Double? {
        data.withUnsafeBytes { raw -> Double? in
            let bytes = Bytes(buffer: raw)
            let seconds = movie(bytes) ?? riff(bytes) ?? aiff(bytes) ?? asf(bytes) ?? mpegAudio(bytes)
            guard let seconds, seconds.isFinite, seconds >= 0, seconds < 1e7 else { return nil }
            return seconds
        }
    }

    /// Bounds-checked big- and little-endian reads.
    private struct Bytes {
        let buffer: UnsafeRawBufferPointer
        var count: Int { buffer.count }

        func byte(_ offset: Int) -> UInt8? { offset >= 0 && offset < count ? buffer[offset] : nil }

        func bigEndian(_ offset: Int, _ length: Int) -> UInt64? {
            guard offset >= 0, length <= 8, offset <= count - length else { return nil }
            return (0..<length).reduce(UInt64(0)) { $0 << 8 | UInt64(buffer[offset + $1]) }
        }

        func littleEndian(_ offset: Int, _ length: Int) -> UInt64? {
            guard offset >= 0, length <= 8, offset <= count - length else { return nil }
            return (0..<length).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64(buffer[offset + $1]) }
        }

        func tag(_ offset: Int, _ length: Int = 4) -> String? {
            guard offset >= 0, offset <= count - length else { return nil }
            return String(decoding: UnsafeRawBufferPointer(rebasing: buffer[offset..<(offset + length)]), as: UTF8.self)
        }
    }

    // MARK: MPEG-4 and QuickTime

    private static let movieBoxes: Set<String> = ["ftyp", "moov", "mdat", "wide", "free", "skip", "pnot", "uuid"]

    private static func movie(_ bytes: Bytes) -> Double? {
        guard let first = bytes.tag(4), movieBoxes.contains(first), let moov = box("moov", in: bytes, from: 0, to: bytes.count),
              let header = box("mvhd", in: bytes, from: moov.start, to: moov.end), let version = bytes.byte(header.start) else { return nil }
        // Version 1 has 64-bit times and duration; version 0, 32-bit.
        let wide = version == 1
        guard let timescale = bytes.bigEndian(header.start + (wide ? 20 : 12), 4), timescale > 0,
              let duration = bytes.bigEndian(header.start + (wide ? 24 : 16), wide ? 8 : 4),
              duration != (wide ? UInt64.max : UInt64(UInt32.max)) else { return nil }
        return Double(duration) / Double(timescale)
    }

    /// The contents of the first box of a type between two offsets.
    private static func box(_ type: String, in bytes: Bytes, from start: Int, to end: Int) -> (start: Int, end: Int)? {
        var cursor = start
        var visited = 0
        while cursor <= end - 8, visited < 4096 {
            visited += 1
            guard let size32 = bytes.bigEndian(cursor, 4), let name = bytes.tag(cursor + 4) else { return nil }
            var header = 8
            var size: Int
            if size32 == 1 {
                guard let large = bytes.bigEndian(cursor + 8, 8), large <= UInt64(Int.max) else { return nil }
                size = Int(large)
                header = 16
            } else if size32 == 0 {
                size = end - cursor
            } else {
                size = Int(size32)
            }
            guard size >= header, size <= end - cursor else { return nil }
            if name == type { return (cursor + header, cursor + size) }
            cursor += size
        }
        return nil
    }

    // MARK: WAV and AVI

    private static func riff(_ bytes: Bytes) -> Double? {
        guard bytes.tag(0) == "RIFF", let form = bytes.tag(8) else { return nil }
        var cursor = 12
        var visited = 0
        var byteRate: UInt64?
        var dataSize: UInt64?
        var dataStart = 0
        while cursor <= bytes.count - 8, visited < 1024 {
            visited += 1
            guard let id = bytes.tag(cursor), let size = bytes.littleEndian(cursor + 4, 4) else { return nil }
            switch (form, id) {
            case ("WAVE", "fmt "):
                byteRate = bytes.littleEndian(cursor + 16, 4)
            case ("WAVE", "data"):
                dataSize = size
                dataStart = cursor + 8
            case ("AVI ", "LIST") where bytes.tag(cursor + 8) == "hdrl" && bytes.tag(cursor + 12) == "avih":
                // The main AVI header: microseconds per frame, then (after two more fields) the number of frames.
                guard let perFrame = bytes.littleEndian(cursor + 20, 4), let frames = bytes.littleEndian(cursor + 36, 4) else { return nil }
                return Double(perFrame) * Double(frames) / 1_000_000
            default:
                break
            }
            if dataSize != nil, byteRate != nil { break }
            cursor += 8 + Int(size) + Int(size & 1)
        }
        guard let byteRate, byteRate > 0, var dataSize else { return nil }
        // Streamed files leave the size open.
        if dataSize == 0 || dataSize == UInt64(UInt32.max) { dataSize = UInt64(max(0, bytes.count - dataStart)) }
        return Double(dataSize) / Double(byteRate)
    }

    // MARK: AIFF

    private static func aiff(_ bytes: Bytes) -> Double? {
        guard bytes.tag(0) == "FORM", bytes.tag(8) == "AIFF" || bytes.tag(8) == "AIFC" else { return nil }
        var cursor = 12
        var visited = 0
        while cursor <= bytes.count - 8, visited < 1024 {
            visited += 1
            guard let id = bytes.tag(cursor), let size = bytes.bigEndian(cursor + 4, 4) else { return nil }
            if id == "COMM" {
                // Channels, sample frames, sample size, then the sample rate as an 80-bit extended float.
                guard let frames = bytes.bigEndian(cursor + 10, 4), let exponentWord = bytes.bigEndian(cursor + 16, 2),
                      let mantissa = bytes.bigEndian(cursor + 18, 8) else { return nil }
                let exponent = Int(exponentWord & 0x7FFF) - 16383 - 63
                let rate = Double(mantissa) * pow(2, Double(exponent))
                guard rate.isFinite, rate > 0 else { return nil }
                return Double(frames) / rate
            }
            cursor += 8 + Int(size) + Int(size & 1)
        }
        return nil
    }

    // MARK: Windows Media

    private static let asfHeader: [UInt8] = [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C]
    private static let asfFileProperties: [UInt8] = [0xA1, 0xDC, 0xAB, 0x8C, 0x47, 0xA9, 0xCF, 0x11, 0x8E, 0xE4, 0x00, 0xC0, 0x0C, 0x20, 0x53, 0x65]

    private static func asf(_ bytes: Bytes) -> Double? {
        guard bytes.count >= 30, (0..<16).allSatisfy({ bytes.byte($0) == asfHeader[$0] }),
              let objects = bytes.littleEndian(24, 4) else { return nil }
        var cursor = 30
        for _ in 0..<min(Int(objects), 256) {
            guard let size = bytes.littleEndian(cursor + 16, 8), size >= 24, size <= UInt64(bytes.count - cursor) else { return nil }
            if (0..<16).allSatisfy({ bytes.byte(cursor + $0) == asfFileProperties[$0] }) {
                // The play duration in 100-nanosecond units, less the preroll in milliseconds.
                guard let play = bytes.littleEndian(cursor + 64, 8), let preroll = bytes.littleEndian(cursor + 80, 8) else { return nil }
                return max(0, Double(play) / 10_000_000 - Double(preroll) / 1000)
            }
            cursor += Int(size)
        }
        return nil
    }

    // MARK: MP3

    private static let bitrates: [[Int]] = [
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448], // MPEG-1 layer I
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384], // MPEG-1 layer II
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], // MPEG-1 layer III
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256], // MPEG-2 and 2.5 layer I
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160], // MPEG-2 and 2.5 layers II and III
    ]

    private struct Frame {
        var bitrate: Int
        var sampleRate: Int
        var samples: Int
        var sideInfo: Int
    }

    /// An MPEG audio frame header at `offset`, if it is a valid one.
    private static func frame(_ bytes: Bytes, at offset: Int) -> Frame? {
        guard let b0 = bytes.byte(offset), let b1 = bytes.byte(offset + 1), let b2 = bytes.byte(offset + 2), let b3 = bytes.byte(offset + 3),
              b0 == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
        let version = Int(b1 >> 3) & 3, layer = Int(b1 >> 1) & 3
        let bitrateIndex = Int(b2 >> 4), rateIndex = Int(b2 >> 2) & 3
        guard version != 1, layer != 0, bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3 else { return nil }
        let mpeg1 = version == 3
        let table = mpeg1 ? 3 - layer : (layer == 3 ? 3 : 4)
        let rates = mpeg1 ? [44_100, 48_000, 32_000] : version == 2 ? [22_050, 24_000, 16_000] : [11_025, 12_000, 8_000]
        let samples = layer == 3 ? 384 : (layer == 2 || mpeg1) ? 1152 : 576
        let mono = b3 >> 6 == 3
        return Frame(bitrate: bitrates[table][bitrateIndex] * 1000, sampleRate: rates[rateIndex], samples: samples,
                     sideInfo: mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17))
    }

    private static func mpegAudio(_ bytes: Bytes) -> Double? {
        // An MP3 file starts with a tag or a frame; anything else isn't searched for one.
        guard bytes.tag(0, 3) == "ID3" || frame(bytes, at: 0) != nil else { return nil }
        var start = 0
        // An ID3v2 tag first: its size is four 7-bit bytes, plus a footer when flagged.
        if bytes.tag(0, 3) == "ID3", let flags = bytes.byte(5), let size = bytes.bigEndian(6, 4) {
            let tag = Int((size >> 24 & 0x7F) << 21 | (size >> 16 & 0x7F) << 14 | (size >> 8 & 0x7F) << 7 | (size & 0x7F))
            start = 10 + tag + (flags & 0x10 != 0 ? 10 : 0)
        }
        var cursor = start
        let limit = min(bytes.count - 4, start + 64 * 1024)
        var header: Frame?
        while cursor < limit {
            if let found = frame(bytes, at: cursor) {
                header = found
                break
            }
            cursor += 1
        }
        guard let header else { return nil }
        func length(frames: UInt64) -> Double { Double(frames) * Double(header.samples) / Double(header.sampleRate) }
        // A Xing or Info header (variable bit rate) after the side information, or a VBRI header, gives the frame count.
        let xing = cursor + 4 + header.sideInfo
        if bytes.tag(xing) == "Xing" || bytes.tag(xing) == "Info", let flags = bytes.bigEndian(xing + 4, 4), flags & 1 != 0,
           let frames = bytes.bigEndian(xing + 8, 4) {
            return length(frames: frames)
        }
        if bytes.tag(cursor + 36) == "VBRI", let frames = bytes.bigEndian(cursor + 36 + 14, 4) {
            return length(frames: frames)
        }
        // Otherwise a constant bit rate over the audio, without an ID3v1 tag at the end.
        var end = bytes.count
        if bytes.tag(end - 128, 3) == "TAG" { end -= 128 }
        return Double(max(0, end - cursor)) * 8 / Double(header.bitrate)
    }
}
