import Foundation

struct SQLQueryEngine: Sendable {
    func executeReadOnly(sql: String, databaseURL: URL, rowLimit: Int = 500) throws -> QueryResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return QueryResult(columns: [], rows: [], elapsedMilliseconds: 0, truncated: false) }
        let db = try SQLiteDatabase(url: databaseURL, readOnly: true)
        return try db.query(trimmed, rowLimit: rowLimit)
    }
}
