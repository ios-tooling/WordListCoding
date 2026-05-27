import Foundation

/// On-disk constants shared by the BDEX encoder and decoder so they can never
/// drift. BDEX is a little-endian, 8-byte-aligned columnar layout:
///
///     [ header (32B) ] [ column data sections... ] [ column directory ]
///
/// Each column is DICT8 (≤256 distinct values: stored once + one u8 code per
/// row) or STRING (a UTF-8 blob, optionally LZ4-compressed, + u32 offsets;
/// value i = blob[offsets[i] ..< offsets[i+1]]).
public enum BDEXFormat {
    public static let magic: [UInt8] = Array("BDEX".utf8)
    public static let versionMajor: UInt16 = 1
    public static let versionMinor: UInt16 = 0

    /// A column with at most this many distinct values is dictionary-encoded.
    static let dict8Limit = 256

    enum Kind { static let string: UInt8 = 0; static let dict8: UInt8 = 1 }
    enum Codec { static let none: UInt8 = 0; static let lz4: UInt8 = 1 }

    /// Header field byte offsets.
    enum Header {
        static let size = 32
        static let versionMajor = 4   // u16
        static let versionMinor = 6   // u16
        static let columnCount = 10   // u16
        static let rowCount = 12      // u32
        static let directoryOffset = 16 // u64
    }

    /// Directory-entry field byte offsets (entries are `entrySize` bytes each).
    enum Entry {
        static let size = 72
        static let kind = 0     // u8
        static let codec = 1    // u8
        static let name = 8     // 24 bytes, NUL-padded UTF-8
        static let nameSize = 24
        static let blobAOffset = 32 // u64
        static let blobALength = 40 // u64
        static let blobBOffset = 48 // u64
        static let blobBLength = 56 // u64
        static let aux = 64         // u64 (STRING: uncompressed blob length; DICT8: distinct count)
    }
}
