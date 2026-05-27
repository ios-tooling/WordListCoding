import Foundation
#if canImport(Compression)
import Compression
#endif

/// LZ4 *raw block* codec (the reference LZ4 block format, no frame). The output
/// is interoperable with Apple's `Compression` framework via
/// `COMPRESSION_LZ4_RAW`, which `decompressBlockRaw` uses when available.
///
/// `compressBlockRaw` favors correctness over speed (encoding speed is
/// irrelevant for offline export): greedy single-candidate matching within the
/// 64 KB window, with conservative end-of-block handling (last 5 bytes are
/// literals; no match starts within the final 12 bytes).
public enum LZ4 {
    private static let minMatch = 4
    private static let mfLimit = 12
    private static let lastLiterals = 5
    private static let hashLog = 16
    private static let maxDistance = 65535

    // MARK: - Encode

    public static func compressBlockRaw(_ input: [UInt8]) -> [UInt8] {
        let count = input.count
        var out = [UInt8]()
        out.reserveCapacity(count)
        if count == 0 { out.append(0); return out }

        var hashTable = [Int](repeating: -1, count: 1 << hashLog)
        var anchor = 0
        var i = 0
        let matchLimit = count - lastLiterals
        let searchEnd = count - mfLimit

        func hash(_ p: Int) -> Int {
            let v = UInt32(input[p]) | (UInt32(input[p + 1]) << 8)
                | (UInt32(input[p + 2]) << 16) | (UInt32(input[p + 3]) << 24)
            return Int((v &* 2654435761) >> (32 - UInt32(hashLog)))
        }
        func appendRemainder(_ value: Int) {
            var v = value
            while v >= 255 { out.append(255); v -= 255 }
            out.append(UInt8(v))
        }
        func emit(literalsEnd: Int, matchLength: Int?, offset: Int?) {
            let litLen = literalsEnd - anchor
            let matchNibble = matchLength.map { min($0 - minMatch, 15) } ?? 0
            out.append(UInt8((min(litLen, 15) << 4) | matchNibble))
            if litLen >= 15 { appendRemainder(litLen - 15) }
            if litLen > 0 { out.append(contentsOf: input[anchor..<literalsEnd]) }
            guard let m = matchLength, let off = offset else { return }
            out.append(UInt8(off & 0xFF)); out.append(UInt8((off >> 8) & 0xFF))
            if m - minMatch >= 15 { appendRemainder(m - minMatch - 15) }
        }

        while i < searchEnd {
            let h = hash(i)
            let cand = hashTable[h]
            hashTable[h] = i
            if cand >= 0, i - cand <= maxDistance,
               input[cand] == input[i], input[cand + 1] == input[i + 1],
               input[cand + 2] == input[i + 2], input[cand + 3] == input[i + 3] {
                var mlen = minMatch
                while i + mlen < matchLimit && input[cand + mlen] == input[i + mlen] { mlen += 1 }
                emit(literalsEnd: i, matchLength: mlen, offset: i - cand)
                i += mlen
                anchor = i
            } else {
                i += 1
            }
        }
        emit(literalsEnd: count, matchLength: nil, offset: nil)
        return out
    }

    // MARK: - Decode

    /// Decodes a raw LZ4 block. On Apple platforms this delegates to the
    /// `Compression` framework (`COMPRESSION_LZ4_RAW`); elsewhere it uses a
    /// portable pure-Swift decoder.
    public static func decompressBlockRaw(_ input: [UInt8], expectedSize: Int) -> [UInt8] {
        if expectedSize == 0 { return [] }
        #if canImport(Compression)
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, expectedSize,
                                          src.baseAddress!, input.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        precondition(written == expectedSize, "LZ4 raw decode size mismatch")
        return dst
        #else
        return decompressPureSwift(input, expectedSize: expectedSize)
        #endif
    }

    static func decompressPureSwift(_ input: [UInt8], expectedSize: Int) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(expectedSize)
        var i = 0
        while i < input.count {
            let token = Int(input[i]); i += 1
            var litLen = token >> 4
            if litLen == 15 {
                while true { let b = Int(input[i]); i += 1; litLen += b; if b != 255 { break } }
            }
            if litLen > 0 { out.append(contentsOf: input[i..<(i + litLen)]); i += litLen }
            if i >= input.count { break }
            let offset = Int(input[i]) | (Int(input[i + 1]) << 8); i += 2
            var mlen = (token & 0xF) + minMatch
            if (token & 0xF) == 15 {
                while true { let b = Int(input[i]); i += 1; mlen += b; if b != 255 { break } }
            }
            let start = out.count - offset
            for k in 0..<mlen { out.append(out[start + k]) }
        }
        return out
    }
}
