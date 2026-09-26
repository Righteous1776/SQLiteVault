import SwiftUI

struct VaultDashboardView: View {
    @Environment(VaultStore.self) private var store
    let onOpenWorkspace: (UUID) -> Void
    let onOpenSearch: () -> Void

    private var totalBytes: Int64 {
        store.assets.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalTables: Int {
        store.assets.compactMap(\.schemaSummary).reduce(0) { $0 + $1.tableCount }
    }

    private var favoriteCount: Int {
        store.assets.filter { store.metadata(for: $0).isFavorite }.count
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 175), spacing: 16)]
    }

    var body: some View {
        ZStack {
            VaultBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero

                    LazyVGrid(columns: columns, spacing: 16) {
                        MetricTile(
                            title: "Databases",
                            value: "\(store.assets.count)",
                            icon: "cylinder.split.1x2",
                            detail: "Independent SQLite assets"
                        )
                        MetricTile(
                            title: "Workspaces",
                            value: "\(store.workspaces.count)",
                            icon: "square.stack.3d.up.fill",
                            detail: "Logical multi-database groups"
                        )
                        MetricTile(
                            title: "Tables",
                            value: "\(totalTables)",
                            icon: "tablecells",
                            detail: "Across inspected schemas"
                        )
                        MetricTile(
                            title: "Storage",
                            value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file),
                            icon: "icloud",
                            detail: "\(favoriteCount) favorites"
                        )
                    }

                    workspaceSection
                    organizationSection
                    capabilitiesSection
                }
                .padding(24)
                .frame(maxWidth: 1050, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Console")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("PERSONAL DATA CONTROL PLANE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.tint)

            Text("Many databases.\nOne control plane.")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(-1.3)
                .lineSpacing(-2)

            Text("Group independent SQLite files into logical Workspaces, classify them, query several databases in one read-only session, and search across the Vault without flattening their boundaries.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            Button(action: onOpenSearch) {
                Label("Search the entire Vault", systemImage: "magnifyingglass")
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Workspaces",
                eyebrow: "Logical composition",
                subtitle: "A Workspace groups SQLite files without physically merging them."
            )

            if store.workspaces.isEmpty {
                EmptyStatePanel(
                    title: "Create your first Workspace",
                    message: "Use New Workspace in the toolbar to combine related databases into one logical console.",
                    systemImage: "square.stack.3d.up.badge.plus"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach(store.workspaces.prefix(6)) { workspace in
                        Button {
                            onOpenWorkspace(workspace.id)
                        } label: {
                            SoftPanel {
                                VStack(alignment: .leading, spacing: 13) {
                                    HStack {
                                        Image(systemName: "square.stack.3d.up.fill")
                                            .font(.title3.weight(.semibold))
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(.tint)
                                        Spacer()
                                        Text("\(store.assets(in: workspace).count)")
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(workspace.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 7) {
                                        if let category = workspace.category {
                                            VaultTagChip(text: category, systemImage: "folder.fill", emphasized: true)
                                        }
                                        ForEach(workspace.tags.prefix(2), id: \.self) { tag in
                                            VaultTagChip(text: tag)
                                        }
                                    }
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Organization",
                eyebrow: "Catalog",
                subtitle: "Categories and tags are stored in the iCloud control metadata, not injected into source databases."
            )

            SoftPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Categories", systemImage: "folder.fill")
                            .font(.headline)
                        Spacer()
                        Text("\(store.allCategories.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if store.allCategories.isEmpty && store.allTags.isEmpty {
                        Text("Organize a database or Workspace to build your reusable classification vocabulary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.allCategories, id: \.self) { category in
                                    VaultTagChip(text: category, systemImage: "folder.fill", emphasized: true)
                                }
                                ForEach(store.allTags, id: \.self) { tag in
                                    VaultTagChip(text: tag, systemImage: "tag")
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Control plane status",
                eyebrow: "V0.2",
                subtitle: "The app has moved beyond a single-database viewer."
            )

            SoftPanel {
                VStack(spacing: 0) {
                    StatusRow(title: "iCloud Vault", subtitle: "Cloud assets with local fallback", icon: "icloud")
                    Divider().padding(.leading, 49)
                    StatusRow(title: "Workspace catalog", subtitle: "Persistent logical database groups", icon: "square.stack.3d.up")
                    Divider().padding(.leading, 49)
                    StatusRow(title: "Cross-database SQL", subtitle: "Read-only ATTACH aliases db1, db2, …", icon: "link")
                    Divider().padding(.leading, 49)
                    StatusRow(title: "Categories & tags", subtitle: "Cloud metadata independent of source schema", icon: "tag")
                    Divider().padding(.leading, 49)
                    StatusRow(title: "Global search", subtitle: "Schema and bounded row search across Vault", icon: "magnifyingglass")
                }
                .padding(18)
            }
        }
    }
}
