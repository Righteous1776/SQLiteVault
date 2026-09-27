import SwiftUI

struct WorkspaceDetailView: View {
    @Environment(VaultStore.self) private var store
    let workspaceID: UUID
    let onOpenAsset: (String) -> Void
    let onOpenSearch: () -> Void

    @State private var showingEditor = false
    @State private var sql = ""
    @State private var queryResult: QueryResult?
    @State private var queryError: String?
    @State private var isRunning = false
    @State private var didSeedSQL = false

    private let engine = WorkspaceQueryEngine()

    var body: some View {
        ZStack {
            VaultBackground()

            if let workspace = store.workspace(id: workspaceID) {
                let assets = store.assets(in: workspace)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header(workspace: workspace, assets: assets)
                        databaseSection(workspace: workspace, assets: assets)
                        logicalSessionSection(assets: assets)
                    }
                    .padding(24)
                    .frame(maxWidth: 1050, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .navigationTitle(workspace.name)
                .toolbar {
                    ToolbarItemGroup {
                        Button(action: onOpenSearch) {
                            Label("Search Workspace", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.glass)

                        Button { showingEditor = true } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.glass)
                    }
                }
                .sheet(isPresented: $showingEditor) {
                    WorkspaceEditorView(workspace: workspace)
                        .environment(store)
                }
                .task(id: workspace.databaseFileNames) {
                    guard !didSeedSQL else { return }
                    sql = seedSQL(for: assets)
                    didSeedSQL = true
                }
            } else {
                ContentUnavailableView("Workspace unavailable", systemImage: "square.stack.3d.up.slash")
            }
        }
    }

    private func header(workspace: VaultWorkspace, assets: [DatabaseAsset]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOGICAL WORKSPACE")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.tint)

            HStack(alignment: .firstTextBaseline) {
                Text(workspace.name)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-1)
                Spacer()
                Text("\(assets.count) / \(workspace.databaseFileNames.count) online")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("A logical composition layer. Databases stay independent on disk but can be searched and queried together through read-only aliases.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let category = workspace.category {
                        VaultTagChip(text: category, systemImage: "folder.fill", emphasized: true)
                    }
                    ForEach(workspace.tags, id: \.self) { tag in
                        VaultTagChip(text: tag, systemImage: "tag")
                    }
                }
            }
        }
    }

    private func databaseSection(workspace: VaultWorkspace, assets: [DatabaseAsset]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Databases",
                eyebrow: "Composition",
                subtitle: "Files referenced by this Workspace. Missing iCloud files remain listed in metadata and reconnect when available."
            )

            if workspace.databaseFileNames.isEmpty {
                EmptyStatePanel(
                    title: "No databases yet",
                    message: "Edit this Workspace and select one or more SQLite files.",
                    systemImage: "square.stack.3d.up.badge.plus"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(Array(engine.attachments(for: assets))) { attachment in
                        Button {
                            onOpenAsset(attachment.asset.fileName)
                        } label: {
                            SoftPanel {
                                VStack(alignment: .leading, spacing: 13) {
                                    HStack {
                                        Image(systemName: "cylinder.split.1x2")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(.tint)
                                        Spacer()
                                        Text(attachment.alias)
                                            .font(.caption.monospaced().weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.primary.opacity(0.055), in: Capsule())
                                    }

                                    Text(attachment.asset.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(attachment.asset.schemaSummary?.tableCount ?? 0) tables • \(ByteCountFormatter.string(fromByteCount: attachment.asset.sizeBytes, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func logicalSessionSection(assets: [DatabaseAsset]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Workspace SQL",
                eyebrow: "ATTACH session",
                subtitle: "Each database is attached read-only as db1, db2, … for cross-database SELECT, JOIN and UNION queries."
            )

            SoftPanel {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(engine.attachments(for: assets)) { attachment in
                                VaultTagChip(text: "\(attachment.alias) · \(attachment.asset.name)", systemImage: "link")
                            }
                        }
                    }

                    SoftInsetPanel {
                        TextEditor(text: $sql)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(14)
                    }

                    HStack {
                        Text("Read-only logical session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            VaultHaptics.press()
                            runWorkspaceQuery(assets: assets)
                        } label: {
                            if isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Run", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isRunning || assets.isEmpty || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18)
            }

            if let queryError {
                Text(queryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let queryResult {
                WorkspaceQueryResultView(result: queryResult)
            }
        }
    }

    private func runWorkspaceQuery(assets: [DatabaseAsset]) {
        isRunning = true
        queryError = nil
        do {
            queryResult = try engine.executeReadOnly(sql: sql, assets: assets)
        } catch {
            queryResult = nil
            queryError = error.localizedDescription
        }
        isRunning = false
    }

    private func seedSQL(for assets: [DatabaseAsset]) -> String {
        let attachments = engine.attachments(for: assets)
        guard !attachments.isEmpty else { return "" }
        let selects = attachments.map { attachment in
            "SELECT '\(attachment.alias)' AS source, type, name FROM \(attachment.alias).sqlite_schema WHERE name NOT LIKE 'sqlite_%'"
        }
        return selects.joined(separator: "\nUNION ALL\n") + "\nORDER BY source, type, name;"
    }
}

struct WorkspaceEditorView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let workspace: VaultWorkspace?
    @State private var name: String
    @State private var category: String
    @State private var tagsText: String
    @State private var selectedFiles: Set<String>

    init(workspace: VaultWorkspace?) {
        self.workspace = workspace
        _name = State(initialValue: workspace?.name ?? "")
        _category = State(initialValue: workspace?.category ?? "")
        _tagsText = State(initialValue: workspace?.tags.joined(separator: ", ") ?? "")
        _selectedFiles = State(initialValue: Set(workspace?.databaseFileNames ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Name", text: $name)
                    TextField("Category", text: $category)
                    TextField("Tags, comma separated", text: $tagsText)
                }

                Section {
                    ForEach(store.assets) { asset in
                        Toggle(isOn: binding(for: asset.fileName)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.name)
                                Text("\(asset.schemaSummary?.tableCount ?? 0) tables • \(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Databases")
                } footer: {
                    Text("Logical grouping only. Source SQLite files are not merged or rewritten.")
                }
            }
            .navigationTitle(workspace == nil ? "New Workspace" : "Edit Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let tags = parseTags(tagsText)
                        Task {
                            if let workspace {
                                await store.updateWorkspace(
                                    workspace,
                                    name: name,
                                    databaseFileNames: Array(selectedFiles),
                                    category: category,
                                    tags: tags
                                )
                            } else {
                                await store.createWorkspace(
                                    name: name,
                                    databaseFileNames: Array(selectedFiles),
                                    category: category,
                                    tags: tags
                                )
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func binding(for fileName: String) -> Binding<Bool> {
        Binding(
            get: { selectedFiles.contains(fileName) },
            set: { enabled in
                if enabled { selectedFiles.insert(fileName) }
                else { selectedFiles.remove(fileName) }
            }
        )
    }

    private func parseTags(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct WorkspaceQueryResultView: View {
    let result: QueryResult

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(result.rows.count) rows", systemImage: "tablecells")
                    Spacer()
                    Text(String(format: "%.1f ms", result.elapsedMilliseconds))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 16)

                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            ForEach(result.columns, id: \.self) { column in
                                Text(column)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    Text(value ?? "NULL")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(value == nil ? .tertiary : .primary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .frame(minHeight: 180, maxHeight: 480)
            }
        }
    }
}
