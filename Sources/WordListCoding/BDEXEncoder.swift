import Foundation

/// Encodes word-list rows into the BDEX columnar binary format. A column is
/// dictionary-encoded when it has ≤256 distinct values (stored once + a u8 code
/// per row); otherwise it is a UTF-8 blob + u32 offsets, LZ4-compressed when
/// that shrinks it. See ``BDEXFormat`` for the layout.
public enum BDEXEncoder {
    public static func encode(rows: [WordListRow], columns: [String]) -> [UInt8] {
        let colCount = columns.count
        let plans = (0..<colCount).map { c -> ColumnPlan in
            let name = columns[c]
            let values = rows.map { $0.cells.indices.contains(c) ? $0.cells[c].value : "" }
            return Set(values).count <= BDEXFormat.dict8Limit
                ? buildDict8(name: name, values: values)
                : buildString(name: name, values: values)
        }

        var out = [UInt8]()
        out.append(contentsOf: BDEXFormat.magic)         // magic
        appendU16(&out, BDEXFormat.versionMajor)
        appendU16(&out, BDEXFormat.versionMinor)
        out.append(0); out.append(0)                     // endian=LE, reserved
        appendU16(&out, UInt16(colCount))
        appendU32(&out, UInt32(rows.count))
        appendU64(&out, 0)                               // directoryOffset (patched)
        appendU64(&out, 0)                               // reserved

        var dir: [(ColumnPlan, aOff: UInt64, bOff: UInt64)] = []
        for p in plans {
            align8(&out); let aOff = UInt64(out.count); out.append(contentsOf: p.blobA)
            align8(&out); let bOff = UInt64(out.count); out.append(contentsOf: p.blobB)
            dir.append((p, aOff, bOff))
        }

        align8(&out)
        let directoryOffset = UInt64(out.count)
        for (p, aOff, bOff) in dir {
            out.append(p.kind); out.append(p.codec); out.append(0); out.append(0)
            appendU32(&out, 0)
            appendName(&out, p.name)
            appendU64(&out, aOff); appendU64(&out, UInt64(p.blobA.count))
            appendU64(&out, bOff); appendU64(&out, UInt64(p.blobB.count))
            appendU64(&out, p.aux)
        }
        patchU64(&out, at: BDEXFormat.Header.directoryOffset, value: directoryOffset)
        return out
    }

    private struct ColumnPlan {
        let name: String
        let kind: UInt8
        let codec: UInt8
        var blobA: [UInt8] = []
        var blobB: [UInt8] = []
        var aux: UInt64 = 0
    }

    private static func buildString(name: String, values: [String]) -> ColumnPlan {
        var blob = [UInt8]()
        var offsets: [UInt32] = [0]
        offsets.reserveCapacity(values.count + 1)
        var cursor: UInt32 = 0
        for v in values {
            let bytes = Array(v.utf8)
            blob.append(contentsOf: bytes)
            cursor += UInt32(bytes.count)
            offsets.append(cursor)
        }
        let compressed = LZ4.compressBlockRaw(blob)
        let useLZ4 = compressed.count < blob.count
        var p = ColumnPlan(name: name, kind: BDEXFormat.Kind.string,
                           codec: useLZ4 ? BDEXFormat.Codec.lz4 : BDEXFormat.Codec.none)
        p.blobA = useLZ4 ? compressed : blob
        var offBytes = [UInt8](); offBytes.reserveCapacity(offsets.count * 4)
        for o in offsets { appendU32(&offBytes, o) }
        p.blobB = offBytes
        p.aux = UInt64(blob.count)
        return p
    }

    private static func buildDict8(name: String, values: [String]) -> ColumnPlan {
        let distinct = Array(Set(values)).sorted()
        var indexOf = [String: Int](minimumCapacity: distinct.count)
        for (i, s) in distinct.enumerated() { indexOf[s] = i }

        var dictBytes = [UInt8]()
        appendU32(&dictBytes, UInt32(distinct.count))
        var blob = [UInt8]()
        var offs: [UInt32] = [0]
        var cursor: UInt32 = 0
        for s in distinct {
            let b = Array(s.utf8); blob.append(contentsOf: b)
            cursor += UInt32(b.count); offs.append(cursor)
        }
        for o in offs { appendU32(&dictBytes, o) }
        dictBytes.append(contentsOf: blob)

        var p = ColumnPlan(name: name, kind: BDEXFormat.Kind.dict8, codec: BDEXFormat.Codec.none)
        p.blobA = dictBytes
        p.blobB = values.map { UInt8(indexOf[$0] ?? 0) }
        p.aux = UInt64(distinct.count)
        return p
    }

    // MARK: - Little-endian byte helpers

    private static func appendU16(_ a: inout [UInt8], _ v: UInt16) {
        a.append(UInt8(v & 0xFF)); a.append(UInt8((v >> 8) & 0xFF))
    }
    private static func appendU32(_ a: inout [UInt8], _ v: UInt32) {
        for s in stride(from: 0, to: 32, by: 8) { a.append(UInt8((v >> UInt32(s)) & 0xFF)) }
    }
    private static func appendU64(_ a: inout [UInt8], _ v: UInt64) {
        for s in stride(from: 0, to: 64, by: 8) { a.append(UInt8((v >> UInt64(s)) & 0xFF)) }
    }
    private static func align8(_ a: inout [UInt8]) { while a.count % 8 != 0 { a.append(0) } }
    private static func appendName(_ a: inout [UInt8], _ name: String) {
        var b = Array(name.utf8)
        if b.count > BDEXFormat.Entry.nameSize { b = Array(b.prefix(BDEXFormat.Entry.nameSize)) }
        a.append(contentsOf: b)
        a.append(contentsOf: repeatElement(0, count: BDEXFormat.Entry.nameSize - b.count))
    }
    private static func patchU64(_ a: inout [UInt8], at offset: Int, value: UInt64) {
        for s in 0..<8 { a[offset + s] = UInt8((value >> UInt64(s * 8)) & 0xFF) }
    }
}
