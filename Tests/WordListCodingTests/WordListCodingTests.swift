import Testing
import Foundation
@testable import WordListCoding

@Suite struct LZ4Tests {
    private func roundTrip(_ s: [UInt8]) -> Bool {
        LZ4.decompressBlockRaw(LZ4.compressBlockRaw(s), expectedSize: s.count) == s
    }

    @Test func edgeCases() {
        #expect(roundTrip([]))
        #expect(roundTrip([42]))
        #expect(roundTrip(Array("abc".utf8)))
        #expect(roundTrip(Array("0123456789AB".utf8)))      // exactly the 12-byte mfLimit
        #expect(roundTrip(Array("0123456789ABCDE".utf8)))
    }

    @Test func repetitiveShrinksAndRoundTrips() {
        let s = Array(String(repeating: "the quick brown fox ", count: 500).utf8)
        #expect(LZ4.compressBlockRaw(s).count < s.count)
        #expect(roundTrip(s))
    }

    @Test func incompressibleRoundTrips() {
        var rng = SystemRandomNumberGenerator()
        let s = (0..<5000).map { _ in UInt8.random(in: 0...255, using: &rng) }
        #expect(roundTrip(s))
    }

    /// Exercise the portable pure-Swift decoder explicitly (the non-Apple path).
    @Test func pureSwiftDecoderMatches() {
        let s = Array(String(repeating: "lexicon entry, see also: ", count: 300).utf8)
        let c = LZ4.compressBlockRaw(s)
        #expect(LZ4.decompressPureSwift(c, expectedSize: s.count) == s)
    }
}

@Suite struct BDEXTests {
    @Test func roundTripsThroughDocument() throws {
        let pos = ["noun", "verb", "adjective"]
        let freq = ["common", "uncommon", "rare"]
        // >256 distinct words/definitions force the STRING+LZ4 path; pos/freq stay DICT8.
        let rows = (0..<400).map { i in
            WordListRow([
                ("word", "headword\(i)"),
                ("definition", "A sample definition number \(i), with commas, and text."),
                ("part_of_speech", pos[i % pos.count]),
                ("frequency", freq[i % freq.count]),
            ])
        }
        let bytes = BDEXEncoder.encode(rows: rows, columns: ["word", "definition", "part_of_speech", "frequency"])

        let doc = try WordListDocument(Data(bytes))
        #expect(doc.rowCount == 400)
        #expect(doc.columnNames == ["word", "definition", "part_of_speech", "frequency"])
        #expect(doc.rows() == rows)                                    // full round-trip
        #expect(doc.column(named: "frequency") == rows.map { $0.cells[3].value })
        #expect(doc.column(named: "nope") == nil)
    }

    @Test func badMagicThrows() {
        #expect(throws: WordListDocument.DecodeError.self) {
            _ = try WordListDocument(Data([0, 1, 2, 3, 4, 5, 6, 7, 8]))
        }
    }
}
