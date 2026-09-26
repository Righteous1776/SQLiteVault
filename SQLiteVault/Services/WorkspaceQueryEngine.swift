import Foundation
import SQLite3

private let SQLITE_TRANSIENT_WORKSPACE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct WorkspaceAttachment: Identifiable, Hashable, Sendable {
    var id: String { alias }
    let alias: String
    let asset: DatabaseAsset
}

struct WorkspaceQueryEngine: Sendable {
    enum WorkspaceQueryError: LocalizedError {
        case open(String)
        case attach(String)
        case prepare(String)
        case step(String)
        case writeBlocked

        var errorDescription: String? {
            switch self {
            case .open(let message): "Unable to create workspace session: \(message)"
            case .attach(let message): "Unable to attach workspace database: \(message)"
            case .prepare(let message): "Unable to prepare workspace SQL: \(message)"
            case .step(let message): "Workspace query failed: \(message)"
            case .writeBlocked: "Workspace SQL is read-only. INSERT, UPDATE, DELETE, ATTACH, DETACH, DDL, and write PRAGMAs are blocked."
            }
        }
    }

    func attachments(for assets: [DatabaseAsset]) -> [WorkspaceAttachment] {
        assets.enumerated().map { offset, asset in
            WorkspaceAttachment(alias: "db\(offset + 1)", asset: asset)
        }
    }

    func executeReadOnly(sql: String, assets: [DatabaseAsset], rowLimit: Int = 500) throws -> QueryResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return QueryResult(columns: [], rows: [], elapsedMilliseconds: 0, truncated: false)
        }
        try SQLReadOnlyPolicy().requireQueryOnly(trimmed)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(":memory:", &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            sqlite3_close(handle)
            throw WorkspaceQueryError.open(message)
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 2_000)

        for attachment in attachments(for: assets) {
            try attach(attachment, to: handle)
        }

        let started = ContinuousClock.now
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, trimmed, -1, &statement, nil) == SQLITE_OK else {
            throw WorkspaceQueryError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_stmt_readonly(statement) != 0 else { throw WorkspaceQueryError.writeBlocked }

        let columnCount = Int(sqlite3_column_count(statement))
        let columns = (0..<columnCount).map { index in
            sqlite3_column_name(statement, Int32(index)).map(String.init(cString:)) ?? "column_\(index)"
        }
        var rows: [[String?]] = []
        var truncated = false

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw WorkspaceQueryError.step(String(cString: sqlite3_errmsg(handle)))
            }
            if rows.count >= rowLimit {
                truncated = true
                break
            }
            rows.append((0..<columnCount).map { index in
                value(statement: statement, index: Int32(index))
            })
        }

        let elapsed = started.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        return QueryResult(columns: columns, rows: rows, elapsedMilliseconds: milliseconds, truncated: truncated)
    }

    private func attach(_ attachment: WorkspaceAttachment, to handle: OpaquePointer) throws {
        var statement: OpaquePointer?
        let sql = "ATTACH DATABASE ?1 AS \"\(attachment.alias)\";"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WorkspaceQueryError.attach(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        var components = URLComponents()
        components.scheme = "file"
        components.path = attachment.asset.fileURL.path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        let uri = components.string ?? attachment.asset.fileURL.absoluteString
        guard sqlite3_bind_text(statement, 1, uri, -1, SQLITE_TRANSIENT_WORKSPACE) == SQLITE_OK else {
            throw WorkspaceQueryError.attach(String(cString: sqlite3_errmsg(handle)))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WorkspaceQueryError.attach(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func value(statement: OpaquePointer?, index: Int32) -> String? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL: nil
        case SQLITE_INTEGER: String(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: String(sqlite3_column_double(statement, index))
        case SQLITE_TEXT: sqlite3_column_text(statement, index).map { String(cString: $0) }
        case SQLITE_BLOB: "<BLOB \(sqlite3_column_bytes(statement, index)) bytes>"
        default: nil
        }
    }
}
