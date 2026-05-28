import Foundation
import CSQLite3
import WordListCoding

/// Builds a SQLite 3 database (one table, one row per `WordListRow`) and
/// returns it as bytes via `sqlite3_serialize`. The whole build happens in
/// `:memory:` — no temp files, journal disabled, single transaction.
///
/// All columns are stored as TEXT (the row model is string-typed); the table
/// gets a non-unique index on the first column so consumer queries by word
/// are fast.
public enum SQLiteWriter {
    public enum Error: Swift.Error, CustomStringConvertible {
        case openFailed(String)
        case prepareFailed(String)
        case execFailed(String)
        case serializeUnavailable
        public var description: String {
            switch self {
            case .openFailed(let m):       return "sqlite_open: \(m)"
            case .prepareFailed(let m):    return "sqlite_prepare: \(m)"
            case .execFailed(let m):       return "sqlite_exec: \(m)"
            case .serializeUnavailable:    return "sqlite3_serialize returned NULL"
            }
        }
    }

    public static func encode(
        rows: [WordListRow],
        columns: [String],
        tableName: String = "words"
    ) throws -> [UInt8] {
        var dbPtr: OpaquePointer?
        guard sqlite3_open(":memory:", &dbPtr) == SQLITE_OK, let db = dbPtr else {
            let msg = String(cString: sqlite3_errmsg(dbPtr))
            sqlite3_close(dbPtr)
            throw Error.openFailed(msg)
        }
        defer { sqlite3_close(db) }

        try exec(db, "PRAGMA journal_mode = OFF;")
        try exec(db, "PRAGMA synchronous = OFF;")

        let tbl = quoteIdent(tableName)
        let colDefs = columns.map { "\(quoteIdent($0)) TEXT" }.joined(separator: ", ")
        try exec(db, "CREATE TABLE \(tbl) (\(colDefs));")
        if let first = columns.first {
            let idxName = quoteIdent("\(tableName)_\(first)_idx")
            try exec(db, "CREATE INDEX \(idxName) ON \(tbl) (\(quoteIdent(first)));")
        }

        try exec(db, "BEGIN;")
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let insertSQL = "INSERT INTO \(tbl) VALUES (\(placeholders));"
        var stmtPtr: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmtPtr, nil) == SQLITE_OK, let stmt = stmtPtr else {
            throw Error.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        for row in rows {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            for (i, col) in columns.enumerated() {
                if let cell = row.cells.first(where: { $0.key == col }) {
                    let rc = cell.value.withCString { cString in
                        sqlite3_bind_text(stmt, Int32(i + 1), cString, -1, SQLITE_TRANSIENT)
                    }
                    if rc != SQLITE_OK {
                        throw Error.execFailed(String(cString: sqlite3_errmsg(db)))
                    }
                } else {
                    sqlite3_bind_null(stmt, Int32(i + 1))
                }
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw Error.execFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        try exec(db, "COMMIT;")

        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(db, "main", &size, 0) else {
            throw Error.serializeUnavailable
        }
        defer { sqlite3_free(bytes) }
        return Array(UnsafeBufferPointer(start: bytes, count: Int(size)))
    }

    // MARK: - Helpers

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw Error.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Quote a SQL identifier with double quotes, escaping any embedded `"`.
    private static func quoteIdent(_ id: String) -> String {
        "\"" + id.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// `SQLITE_TRANSIENT` instructs SQLite to make its own copy of bound bytes,
/// which is what we want since the Swift String's C buffer is only valid for
/// the duration of `withCString`.
private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1)!,
    to: sqlite3_destructor_type.self
)
