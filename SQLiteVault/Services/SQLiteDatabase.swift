import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase: @unchecked Sendable {
    enum DatabaseError: LocalizedError {
        case open(String)
        case prepare(String)
        case step(String)
        case unsupportedWrite

        var errorDescription: String? {
            switch self {
            case .open(let message): "Unable to open database: \(message)"
            case .prepare(let message): "Unable to prepare SQL: \(message)"
            case .step(let message): "SQLite execution failed: \(message)"
            case .unsupportedWrite: "SQLite Vault SQL Console is read-only. Write statements are blocked."
            }
        }
    }

    private var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = true) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.open(message)
        }
        sqlite3_busy_timeout(handle, 2_000)
    }

    deinit { sqlite3_close(handle) }

    func integrityCheck() throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.step(errorMessage)
        }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
    }

    func foreignKeyViolationCount(limit: Int = 10_000) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA foreign_key_check", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var count = 0
        while count < limit {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DatabaseError.step(errorMessage) }
            count += 1
        }
        return count
    }

    func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func query(_ sql: String, rowLimit: Int = 500) throws -> QueryResult {
        try query(sql, bindings: [], rowLimit: rowLimit)
    }

    func query(_ sql: String, bindings: [String?], rowLimit: Int = 500) throws -> QueryResult {
        try SQLReadOnlyPolicy().requireQueryOnly(sql)
        let started = ContinuousClock.now
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_stmt_readonly(statement) != 0 else {
            throw DatabaseError.unsupportedWrite
        }

        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            if let value {
                let status = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
                guard status == SQLITE_OK else { throw DatabaseError.prepare(errorMessage) }
            } else {
                let status = sqlite3_bind_null(statement, index)
                guard status == SQLITE_OK else { throw DatabaseError.prepare(errorMessage) }
            }
        }

        let columnCount = Int(sqlite3_column_count(statement))
        let columns = (0..<columnCount).map { index in
            sqlite3_column_name(statement, Int32(index)).map(String.init(cString:)) ?? "column_\(index)"
        }

        var rows: [[String?]] = []
        var truncated = false

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DatabaseError.step(errorMessage) }

            if rows.count >= rowLimit {
                truncated = true
                break
            }

            rows.append((0..<columnCount).map { index in
                value(statement: statement, index: Int32(index))
            })
        }

        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        return QueryResult(columns: columns, rows: rows, elapsedMilliseconds: ms, truncated: truncated)
    }

    private var errorMessage: String {
        handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }

    private func value(statement: OpaquePointer?, index: Int32) -> String? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { String(cString: $0) }
        case SQLITE_BLOB:
            return "<BLOB \(sqlite3_column_bytes(statement, index)) bytes>"
        default:
            return nil
        }
    }
}
