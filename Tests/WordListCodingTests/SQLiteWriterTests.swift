import Testing
import Foundation
import CSQLite3
@testable import WordListCoding
@testable import WordListCodingSQLite

@Suite struct SQLiteWriterTests {

    private func deserialize(_ bytes: [UInt8]) -> OpaquePointer {
        var dbPtr: OpaquePointer?
        precondition(sqlite3_open(":memory:", &dbPtr) == SQLITE_OK)
        let db = dbPtr!
        // sqlite3_deserialize takes ownership of the buffer when SQLITE_DESERIALIZE_FREEONCLOSE
        // is set; we copy into sqlite3_malloc'd memory so the buffer is freed on close.
        let mem = sqlite3_malloc64(sqlite3_uint64(bytes.count))!
        _ = bytes.withUnsafeBufferPointer { src in
            memcpy(mem, src.baseAddress, bytes.count)
        }
        let rc = sqlite3_deserialize(
            db, "main",
            mem.assumingMemoryBound(to: UInt8.self),
            sqlite3_int64(bytes.count),
            sqlite3_int64(bytes.count),
            UInt32(SQLITE_DESERIALIZE_FREEONCLOSE)
        )
        precondition(rc == SQLITE_OK)
        return db
    }

    private func queryString(_ db: OpaquePointer, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    private func queryInt(_ db: OpaquePointer, _ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    @Test func roundTripsAndPassesIntegrityCheck() throws {
        let rows: [WordListRow] = [
            WordListRow([("word", "alpha"), ("definition", "first letter"), ("part_of_speech", "noun")]),
            WordListRow([("word", "beta"),  ("definition", "second letter, of the Greeks"), ("part_of_speech", "noun")]),
            WordListRow([("word", "gamma"), ("definition", ""), ("part_of_speech", "noun")]),
        ]
        let bytes = try SQLiteWriter.encode(
            rows: rows,
            columns: ["word", "definition", "part_of_speech"]
        )
        // The 16-byte SQLite magic header.
        #expect(String(decoding: bytes.prefix(15), as: UTF8.self) == "SQLite format 3")

        let db = deserialize(bytes)
        defer { sqlite3_close(db) }

        #expect(queryString(db, "PRAGMA integrity_check;") == "ok")
        #expect(queryInt(db, "SELECT count(*) FROM words;") == 3)
        #expect(queryString(db, "SELECT definition FROM words WHERE word = 'beta';")
                == "second letter, of the Greeks")
        // Empty values come back as empty strings (we bind text, not NULL, for empty cells).
        #expect(queryString(db, "SELECT definition FROM words WHERE word = 'gamma';") == "")
    }

    @Test func largerVolumeRoundTrips() throws {
        let rows: [WordListRow] = (0..<500).map { i in
            WordListRow([
                ("word", "term\(i)"),
                ("definition", "A sample definition for term number \(i), with punctuation: \"x\"; y!"),
            ])
        }
        let bytes = try SQLiteWriter.encode(rows: rows, columns: ["word", "definition"])
        let db = deserialize(bytes)
        defer { sqlite3_close(db) }

        #expect(queryString(db, "PRAGMA integrity_check;") == "ok")
        #expect(queryInt(db, "SELECT count(*) FROM words;") == 500)
        #expect(queryString(db, "SELECT definition FROM words WHERE word = 'term137';")
                == "A sample definition for term number 137, with punctuation: \"x\"; y!")
    }
}
