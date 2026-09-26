import Foundation

struct CrossVaultSearchService: Sendable {
    private let inspector = SchemaInspector()

    func search(
        query rawQuery: String,
        assets: [DatabaseAsset],
        workspace: VaultWorkspace? = nil,
        maxHits: Int = 200
    ) throws -> [GlobalSearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        let allowed = workspace.map { Set($0.databaseFileNames) }
        let candidates = assets.filter { allowed?.contains($0.fileName) ?? true }
        var hits: [GlobalSearchHit] = []

        for asset in candidates {
            if hits.count >= maxHits { break }

            if asset.name.localizedCaseInsensitiveContains(query) || asset.fileName.localizedCaseInsensitiveContains(query) {
                hits.append(GlobalSearchHit(
                    databaseFileName: asset.fileName,
                    databaseName: asset.name,
                    kind: .database,
                    preview: asset.fileName
                ))
            }

            guard let (objects, _) = try? inspector.inspect(url: asset.fileURL) else { continue }
            for object in objects.prefix(80) {
                if hits.count >= maxHits { break }

                if object.name.localizedCaseInsensitiveContains(query) ||
                    (object.sql?.localizedCaseInsensitiveContains(query) ?? false) {
                    hits.append(GlobalSearchHit(
                        databaseFileName: asset.fileName,
                        databaseName: asset.name,
                        kind: .schema,
                        objectName: object.name,
                        preview: object.sql ?? object.kind.rawValue.capitalized
                    ))
                }

                guard object.kind == .table || object.kind == .view else { continue }
                guard let columns = try? inspector.columns(in: object.name, url: asset.fileURL), !columns.isEmpty else { continue }
                let searchable = Array(columns.prefix(24))
                let predicates = searchable.map { column in
                    "instr(lower(CAST(\(quoteIdentifier(column.name)) AS TEXT)), lower(?1)) > 0"
                }
                let sql = "SELECT * FROM \(quoteIdentifier(object.name)) WHERE \(predicates.joined(separator: " OR ")) LIMIT 8;"
                guard let database = try? SQLiteDatabase(url: asset.fileURL),
                      let result = try? database.query(sql, bindings: [query], rowLimit: 8) else { continue }

                for row in result.rows {
                    if hits.count >= maxHits { break }
                    let match = firstMatch(query: query, columns: result.columns, row: row)
                    hits.append(GlobalSearchHit(
                        databaseFileName: asset.fileName,
                        databaseName: asset.name,
                        kind: .row,
                        objectName: object.name,
                        columnName: match?.column,
                        preview: match?.value ?? compactPreview(columns: result.columns, row: row)
                    ))
                }
            }
        }
        return hits
    }

    private func firstMatch(query: String, columns: [String], row: [String?]) -> (column: String, value: String)? {
        for (index, value) in row.enumerated() {
            guard let value, value.localizedCaseInsensitiveContains(query) else { continue }
            return (columns.indices.contains(index) ? columns[index] : "column_\(index)", clipped(value))
        }
        return nil
    }

    private func compactPreview(columns: [String], row: [String?]) -> String {
        row.enumerated().compactMap { index, value in
            guard let value, !value.isEmpty else { return nil }
            let name = columns.indices.contains(index) ? columns[index] : "column_\(index)"
            return "\(name): \(clipped(value, limit: 90))"
        }
        .prefix(3)
        .joined(separator: "  •  ")
    }

    private func clipped(_ value: String, limit: Int = 180) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }

    private func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
