import SwiftUI

struct GlobalSearchView: View {
    @Environment(VaultStore.self) private var store
    let onOpenAsset: (String) -> Void

    var body: some View {
        @Bindable var store = store

        ZStack {
            VaultBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader(
                        "Global Search",
                        eyebrow: "Cross-vault",
                        subtitle: "Search database names, schema definitions and bounded row content across the whole Vault or a single Workspace."
                    )

                    SoftPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)

                                TextField("Search all SQLite databases", text: $store.globalSearchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.search)
                                    .onSubmit { store.runGlobalSearch() }

                                if !store.globalSearchText.isEmpty {
                                    Button {
                                        store.globalSearchText = ""
                                        store.globalSearchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            HStack {
                                Picker("Scope", selection: $store.searchWorkspaceID) {
                                    Text("Entire Vault").tag(UUID?.none)
                                    ForEach(store.workspaces) { workspace in
                                        Text(workspace.name).tag(Optional(workspace.id))
                                    }
                                }
                                .pickerStyle(.menu)

                                Spacer()

                                Button {
                                    store.runGlobalSearch()
                                } label: {
                                    if store.isSearching {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Search", systemImage: "arrow.right")
                                    }
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(store.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || store.isSearching)
                            }
                        }
                        .padding(18)
                    }

                    if store.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        EmptyStatePanel(
                            title: "Type at least two characters",
                            message: "Search is deliberately explicit so large personal databases are not scanned on every keystroke.",
                            systemImage: "magnifyingglass"
                        )
                    } else if store.isSearching {
                        SoftPanel {
                            HStack(spacing: 14) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Searching SQLite Vault")
                                        .font(.headline)
                                    Text("Scanning schema plus bounded row matches without modifying source databases.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(20)
                        }
                    } else if store.globalSearchResults.isEmpty {
                        EmptyStatePanel(
                            title: "No matches",
                            message: "Try a table name, field value, chapter identifier, project code, or another distinctive phrase.",
                            systemImage: "text.magnifyingglass"
                        )
                    } else {
                        results
                    }
                }
                .padding(24)
                .frame(maxWidth: 1050, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Global Search")
        .onChange(of: store.searchWorkspaceID) { _, _ in
            if store.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                store.runGlobalSearch()
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Results", subtitle: "\(store.globalSearchResults.count) matches")
                Spacer()
                if store.globalSearchResults.count >= 200 {
                    VaultTagChip(text: "200 result cap", systemImage: "gauge.with.dots.needle.67percent")
                }
            }

            LazyVStack(spacing: 12) {
                ForEach(store.globalSearchResults) { hit in
                    Button {
                        onOpenAsset(hit.databaseFileName)
                    } label: {
                        SoftPanel {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: icon(for: hit.kind))
                                    .font(.title3.weight(.semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.tint)
                                    .frame(width: 34, height: 34)

                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 8) {
                                        Text(hit.databaseName)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        VaultTagChip(text: hit.kind.rawValue.capitalized)
                                        if let objectName = hit.objectName {
                                            VaultTagChip(text: objectName, systemImage: "tablecells")
                                        }
                                        if let columnName = hit.columnName {
                                            VaultTagChip(text: columnName, systemImage: "textformat")
                                        }
                                    }

                                    Text(hit.preview)
                                        .font(.system(.subheadline, design: hit.kind == .row ? .monospaced : .default))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(18)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func icon(for kind: GlobalSearchHitKind) -> String {
        switch kind {
        case .database: "externaldrive"
        case .schema: "tablecells"
        case .row: "text.page"
        }
    }
}
