import Foundation

struct SchemaInspector: Sendable {
    func inspect(url: URL) throws -> ([SchemaObject], SchemaSummary) {
        let db = try SQLiteDatabase(url: url)
        let result = try db.query("""
        SELECT type, name, tbl_name, sql
        FROM sqlite_schema
        WHERE name NOT LIKE 'sqlite_%'
        ORDER BY type, name;
        """, rowLimit: 10_000)

        let objects = result.rows.compactMap { row -> SchemaObject? in
            guard row.count >= 4,
                  let rawType = row[0] ?? nil,
                  let kind = SchemaObject.Kind(rawValue: rawType),
                  let name = row[1] ?? nil else { return nil }
            return SchemaObject(kind: kind, name: name, tableName: row[2] ?? nil, sql: row[3] ?? nil)
        }

        let userVersion = try db.scalarInt("PRAGMA user_version;")
        let summary = SchemaSummary(
            tableCount: objects.filter { $0.kind == .table }.count,
            viewCount: objects.filter { $0.kind == .view }.count,
            indexCount: objects.filter { $0.kind == .index }.count,
            triggerCount: objects.filter { $0.kind == .trigger }.count,
            userVersion: userVersion
        )
        return (objects, summary)
    }

    func columns(in table: String, url: URL) throws -> [TableColumn] {
        let db = try SQLiteDatabase(url: url)
        let escaped = table.replacingOccurrences(of: "'", with: "''")
        let result = try db.query("PRAGMA table_info('\(escaped)');", rowLimit: 5_000)
        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let cidText = row[0] ?? nil,
                  let cid = Int(cidText),
                  let name = row[1] ?? nil else { return nil }
            return TableColumn(
                cid: cid,
                name: name,
                declaredType: row[2] ?? "",
                notNull: (row[3] ?? "0") == "1",
                defaultValue: row[4] ?? nil,
                primaryKeyPosition: Int(row[5] ?? "0") ?? 0
            )
        }
    }
}
