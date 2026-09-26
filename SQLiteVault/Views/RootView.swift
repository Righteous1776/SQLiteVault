import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sqliteVaultDatabase = UTType(importedAs: "com.zeostudio.sqlite-vault.sqlite", conformingTo: .database)
}

private enum SidebarDestination: Hashable {
    case console
    case search
    case binaryAssets
    case workspace(UUID)
    case database(String)
}

struct RootView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SidebarDestination? = .console
    @State private var showingImporter = false
    @State private var showingWorkspaceEditor = false
    @State private var refreshPulse = false

    var body: some View {
        NavigationSplitView {
            ZStack {
                VaultBackground()

                List(selection: $selection) {
                    Section("Control Plane") {
                        Label("Console", systemImage: "square.grid.2x2")
                            .fontWeight(.semibold)
                            .tag(SidebarDestination.console)

                        Label("Global Search", systemImage: "magnifyingglass")
                            .tag(SidebarDestination.search)

                        Label("Binary Assets", systemImage: "doc.on.doc.fill")
                            .tag(SidebarDestination.binaryAssets)
                    }

                    Section {
                        ForEach(store.workspaces) { workspace in
                            WorkspaceSidebarRow(workspace: workspace, count: store.assets(in: workspace).count)
                                .tag(SidebarDestination.workspace(workspace.id))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await store.deleteWorkspace(workspace) }
                                    } label: {
                                        Label("Delete Workspace", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("Workspaces")
                            Spacer()
                            Text("\(store.workspaces.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        ForEach(sortedAssets) { asset in
                            DatabaseSidebarRow(asset: asset, metadata: store.metadata(for: asset))
                                .tag(SidebarDestination.database(asset.id))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await store.delete(asset) }
                                    } label: {
                                        Label("Delete from Vault", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("Databases")
                            Spacer()
                            Text("\(store.assets.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)
            }
            .navigationTitle("SQLite Vault")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingWorkspaceEditor = true
                    } label: {
                        Label("New Workspace", systemImage: "square.stack.3d.up.badge.plus")
                    }
                    .buttonStyle(.glass)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        guard !store.isBusy else { return }
                        if !reduceMotion {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                refreshPulse.toggle()
                            }
                        } else {
                            refreshPulse.toggle()
                        }
                        Task { await store.refresh() }
                    } label: {
                        MorphingSymbol(
                            primary: "arrow.clockwise",
                            alternate: "checkmark",
                            alternateState: refreshPulse && !store.isBusy,
                            font: .body.weight(.semibold)
                        )
                        .accessibilityLabel("Refresh")
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isBusy)
                }
            }
        } detail: {
            detail
        }
        .background(VaultBackground())
        .sheet(isPresented: $showingWorkspaceEditor) {
            WorkspaceEditorView(workspace: nil)
                .environment(store)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.sqliteVaultDatabase, .database],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls { await store.importDatabase(from: url) }
            }
        }
        .alert("SQLite Vault", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .console {
        case .console:
            VaultDashboardView(
                onOpenWorkspace: { selection = .workspace($0) },
                onOpenSearch: { selection = .search }
            )
        case .search:
            GlobalSearchView { fileName in
                selection = .database(fileName)
            }
        case .binaryAssets:
            VaultEmbeddedFilesView()
        case .workspace(let id):
            WorkspaceDetailView(
                workspaceID: id,
                onOpenAsset: { selection = .database($0) },
                onOpenSearch: {
                    store.searchWorkspaceID = id
                    selection = .search
                }
            )
        case .database(let id):
            if let asset = store.assets.first(where: { $0.id == id }) {
                DatabaseDetailView(asset: asset)
            } else {
                ContentUnavailableView("Database unavailable", systemImage: "externaldrive.badge.questionmark")
            }
        }
    }

    private var sortedAssets: [DatabaseAsset] {
        store.assets.sorted { lhs, rhs in
            let leftFavorite = store.metadata(for: lhs).isFavorite
            let rightFavorite = store.metadata(for: rhs).isFavorite
            if leftFavorite != rightFavorite { return leftFavorite && !rightFavorite }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }
}

private struct WorkspaceSidebarRow: View {
    let workspace: VaultWorkspace
    let count: Int

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "square.stack.3d.up.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(count) databases")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DatabaseSidebarRow: View {
    let asset: DatabaseAsset
    let metadata: DatabaseMetadata

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: metadata.isFavorite ? "star.fill" : (asset.location == .iCloud ? "externaldrive.connected.to.line.below" : "externaldrive"))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metadata.isFavorite ? Color.yellow : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let category = metadata.category {
                        Text(category)
                        Text("•")
                    }
                    Text(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
