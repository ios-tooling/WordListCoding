import Foundation

/// Reads a BDEX file. Pass a memory-mapped `Data`
/// (`Data(contentsOf: url, options: .mappedIfSafe)`) for the fastest load:
/// everything except the per-string-column LZ4 pass is offset arithmetic over
/// the mapped pages.
public struct WordListDocument {
    public enum DecodeError: Error {
        case badMagic
        case unsupportedVersion(major: Int, minor: Int)
        case truncated
    }

    private let bytes: [UInt8]
    public let rowCount: Int
    public let columnNames: [String]
    private let columns: [Column]

    private struct Column {
        let name: String
        let kind: UInt8
        let codec: UInt8
        let aOff: Int, aLen: Int
        let bOff: Int, bLen: Int
        let aux: Int
    }

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        guard b.count >= BDEXFormat.Header.size else { throw DecodeError.truncated }
        guard Array(b[0..<4]) == BDEXFormat.magic else { throw DecodeError.badMagic }
        let major = Int(WordListDocument.u16(b, BDEXFormat.Header.versionMajor))
        let minor = Int(WordListDocument.u16(b, BDEXFormat.Header.versionMinor))
        guard major == Int(BDEXFormat.versionMajor) else {
            throw DecodeError.unsupportedVersion(major: major, minor: minor)
        }
        let colCount = Int(WordListDocument.u16(b, BDEXFormat.Header.columnCount))
        let rows = Int(WordListDocument.u32(b, BDEXFormat.Header.rowCount))
        let dir = WordListDocument.u64(b, BDEXFormat.Header.directoryOffset)

        var cols: [Column] = []
        cols.reserveCapacity(colCount)
        for c in 0..<colCount {
            let e = dir + c * BDEXFormat.Entry.size
            guard e + BDEXFormat.Entry.size <= b.count else { throw DecodeError.truncated }
            let nameBytes = b[(e + BDEXFormat.Entry.name)..<(e + BDEXFormat.Entry.name + BDEXFormat.Entry.nameSize)]
            let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            cols.append(Column(
                name: name,
                kind: b[e + BDEXFormat.Entry.kind],
                codec: b[e + BDEXFormat.Entry.codec],
                aOff: WordListDocument.u64(b, e + BDEXFormat.Entry.blobAOffset),
                aLen: WordListDocument.u64(b, e + BDEXFormat.Entry.blobALength),
                bOff: WordListDocument.u64(b, e + BDEXFormat.Entry.blobBOffset),
                bLen: WordListDocument.u64(b, e + BDEXFormat.Entry.blobBLength),
                aux: WordListDocument.u64(b, e + BDEXFormat.Entry.aux)
            ))
        }
        self.bytes = b
        self.rowCount = rows
        self.columns = cols
        self.columnNames = cols.map(\.name)
    }

    /// All values for a named column, in row order, or nil if no such column.
    public func column(named name: String) -> [String]? {
        guard let col = columns.first(where: { $0.name == name }) else { return nil }
        return values(of: col)
    }

    /// Materializes every row as a ``WordListRow`` (columns in file order).
    public func rows() -> [WordListRow] {
        let perColumn = columns.map { values(of: $0) }
        return (0..<rowCount).map { r in
            WordListRow(cells: columns.indices.map {
                WordListRow.Cell(key: columns[$0].name, value: perColumn[$0][r])
            })
        }
    }

    // MARK: - Column decoding

    private func values(of col: Column) -> [String] {
        col.kind == BDEXFormat.Kind.dict8 ? dictValues(col) : stringValues(col)
    }

    private func stringValues(_ col: Column) -> [String] {
        let raw = Array(bytes[col.aOff..<(col.aOff + col.aLen)])
        let blob = col.codec == BDEXFormat.Codec.lz4
            ? LZ4.decompressBlockRaw(raw, expectedSize: col.aux)
            : raw
        return (0..<rowCount).map { r in
            let s = Int(WordListDocument.u32(bytes, col.bOff + r * 4))
            let e = Int(WordListDocument.u32(bytes, col.bOff + (r + 1) * 4))
            return String(decoding: blob[s..<e], as: UTF8.self)
        }
    }

    private func dictValues(_ col: Column) -> [String] {
        let count = Int(WordListDocument.u32(bytes, col.aOff))
        let offBase = col.aOff + 4
        let strBase = offBase + (count + 1) * 4
        var dict: [String] = []
        dict.reserveCapacity(count)
        for i in 0..<count {
            let s = strBase + Int(WordListDocument.u32(bytes, offBase + i * 4))
            let e = strBase + Int(WordListDocument.u32(bytes, offBase + (i + 1) * 4))
            dict.append(String(decoding: bytes[s..<e], as: UTF8.self))
        }
        return (0..<rowCount).map { dict[Int(bytes[col.bOff + $0])] }
    }

    // MARK: - Little-endian readers

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        var v: UInt32 = 0
        for s in 0..<4 { v |= UInt32(b[o + s]) << (8 * UInt32(s)) }
        return v
    }
    private static func u64(_ b: [UInt8], _ o: Int) -> Int {
        var v = 0
        for s in 0..<8 { v |= Int(b[o + s]) << (8 * s) }
        return v
    }
}
