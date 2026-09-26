import SwiftUI

struct SchemaBrowserView: View {
    let asset: DatabaseAsset
    let objects: [SchemaObject]
    @State private var selection: SchemaObject?
    @State private var searchText = ""

    private var filteredObjects: [SchemaObject] {
        guard !searchText.isEmpty else { return objects }
        return objects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.kind.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                VaultBackground()

                List(filteredObjects, selection: $selection) { object in
                    SchemaSidebarRow(object: object)
                        .tag(object)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)
                .searchable(text: $searchText, prompt: "Search schema")
            }
            .navigationTitle("Schema")
        } detail: {
            ZStack {
                VaultBackground()
                if let selection {
                    SchemaObjectDetail(asset: asset, object: selection)
                } else {
                    ContentUnavailableView(
                        "Choose a schema object",
                        systemImage: "tablecells",
                        description: Text("Inspect its definition, columns and a protected data preview.")
                    )
                }
            }
        }
    }
}

private struct SchemaSidebarRow: View {
    let object: SchemaObject

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon(for: object.kind))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(object.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(object.kind.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func icon(for kind: SchemaObject.Kind) -> String {
        switch kind {
        case .table: "tablecells"
        case .view: "eye"
        case .index: "list.number"
        case .trigger: "bolt"
        }
    }
}

private struct SchemaObjectDetail: View {
    let asset: DatabaseAsset
    let object: SchemaObject
    @State private var columns: [TableColumn] = []
    @State private var rows: QueryResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    object.name,
                    eyebrow: object.kind.rawValue,
                    subtitle: object.tableName.map { "Attached to \($0)" } ?? "Schema definition"
                )

                SoftPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Definition", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.headline)
                        Text(object.sql ?? "No SQL definition available.")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                }

                if !columns.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Columns", subtitle: "Declared fields and constraints")

                        SoftPanel {
                            VStack(spacing: 0) {
                                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                                    ColumnRow(column: column)
                                    if index < columns.count - 1 {
                                        Divider().padding(.leading, 46)
                                    }
                                }
                            }
                            .padding(18)
                        }
                    }
                }

                if let rows, !rows.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Preview", subtitle: "First 50 rows, read-only")
                        QueryPreview(result: rows)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: object.id) {
            guard object.kind == .table || object.kind == .view else { return }
            columns = (try? SchemaInspector().columns(in: object.name, url: asset.fileURL)) ?? []
            let escaped = object.name.replacingOccurrences(of: "\"", with: "\"\"")
            rows = try? SQLQueryEngine().executeReadOnly(
                sql: "SELECT * FROM \"\(escaped)\" LIMIT 50;",
                databaseURL: asset.fileURL,
                rowLimit: 50
            )
        }
    }
}

private struct ColumnRow: View {
    let column: TableColumn

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: column.primaryKeyPosition > 0 ? "key.fill" : "textformat")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(column.primaryKeyPosition > 0 ? Color.orange : Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(column.name)
                    .font(.subheadline.weight(.semibold))
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }

    private var metadata: String {
        [
            column.declaredType.isEmpty ? "untyped" : column.declaredType,
            column.notNull ? "NOT NULL" : nil,
            column.primaryKeyPosition > 0 ? "PK" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }
}

private struct QueryPreview: View {
    let result: QueryResult

    var body: some View {
        SoftPanel {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(result.columns, id: \.self) { column in
                            Text(column)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 130, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                        }
                    }

                    Divider()

                    ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value ?? "NULL")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(value == nil ? .tertiary : .primary)
                                    .lineLimit(2)
                                    .frame(minWidth: 130, maxWidth: 220, alignment: .leading)
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 8)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
