import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sqliteVaultDatabase = UTType(importedAs: "com.zeostudio.sqlite-vault.sqlite", conformingTo: .database)
}

private enum SidebarDestination: Hashable {
    case console
    case search
    case binaryAssets
    case a9
    case iCloud
    case workspace(UUID)
    case database(String)
}

private enum RefreshVisualState {
    case idle
    case refreshing
    case success
}

struct RootView: View {
    @Environment(VaultStore.self) private var store
    @Environment(VaultPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: SidebarDestination? = .console
    @State private var showingDocumentPicker = false
    @State private var showingWorkspaceEditor = false
    @State private var showingActionMenu = false
    @State private var showingLanguageDial = false
    @State private var refreshState: RefreshVisualState = .idle

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


                        HStack(spacing: 9) {
                            Label("A9 Health", systemImage: "cpu")
                            Spacer()
                            Circle()
                                .fill(store.a9Decisions.isEmpty ? Color.secondary.opacity(0.55) : (store.a9RedCount > 0 ? Color.red : (store.a9YellowCount > 0 ? Color.orange : Color.green)))
                                .frame(width: 7, height: 7)
                        }
                        .tag(SidebarDestination.a9)

                        HStack(spacing: 9) {
                            Label("iCloud", systemImage: store.cloudStatus.isConnected ? "icloud.fill" : "icloud.slash")
                            Spacer()
                            Circle()
                                .fill(store.cloudStatus.isConnected ? Color.green : Color.secondary.opacity(0.55))
                                .frame(width: 7, height: 7)
                        }
                        .tag(SidebarDestination.iCloud)
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
                    toolbarIcon("plus", accessibility: "Add") {
                        VaultHaptics.press()
                        showingActionMenu = true
                    }

                    toolbarIcon("globe", accessibility: "Interface Language") {
                        VaultHaptics.selection()
                        if reduceMotion {
                            showingLanguageDial = true
                        } else {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                showingLanguageDial = true
                            }
                        }
                    }

                    Button(action: refresh) {
                        refreshIcon
                            .frame(width: 20, height: 20)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .disabled(refreshState == .refreshing)
                    .accessibilityLabel("Refresh")
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
        .sheet(isPresented: $showingDocumentPicker) {
            SQLiteDocumentPicker(
                onPick: { urls in
                    showingDocumentPicker = false
                    importDatabases(urls)
                },
                onCancel: {
                    showingDocumentPicker = false
                }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Add to SQLite Vault", isPresented: $showingActionMenu, titleVisibility: .visible) {
            Button("Import Database") {
                showingDocumentPicker = true
            }
            Button("New Workspace") {
                showingWorkspaceEditor = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("SQLite Vault", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "Unknown error")
        }
        .overlay {
            if showingLanguageDial {
                LanguageGearDialOverlay(
                    language: Binding(
                        get: { preferences.language },
                        set: { newLanguage in
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                preferences.language = newLanguage
                            }
                        }
                    ),
                    isPresented: $showingLanguageDial
                )
                .zIndex(500)
            }
        }
    }

    private func toolbarIcon(_ systemName: String, accessibility: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var refreshIcon: some View {
        switch refreshState {
        case .idle:
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.semibold))
        case .refreshing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func refresh() {
        guard refreshState != .refreshing else { return }
        VaultHaptics.press()
        refreshState = .refreshing

        Task {
            await store.refresh()
            refreshState = .success
            VaultHaptics.success()
            try? await Task.sleep(nanoseconds: 420_000_000)
            if reduceMotion {
                refreshState = .idle
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    refreshState = .idle
                }
            }
        }
    }

    private func importDatabases(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                await store.importDatabase(from: url)
            }
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
        case .a9:
            A9HealthConsoleView()
        case .iCloud:
            ICloudControlCenterView()
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
            Image(systemName: sidebarSymbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metadata.isFavorite ? Color.yellow : (asset.isLocallyAvailable ? Color.accentColor : Color.secondary))
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
                    if asset.location == .iCloud && !asset.isLocallyAvailable {
                        Text("•")
                        Text(asset.localAvailability == .downloading ? "Downloading" : "iCloud Only")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var sidebarSymbol: String {
        if metadata.isFavorite { return "star.fill" }
        if asset.location == .localFallback { return "externaldrive" }
        switch asset.localAvailability {
        case .available: return "externaldrive.fill.badge.icloud"
        case .downloading: return "icloud.and.arrow.down.fill"
        case .remoteOnly: return "icloud.fill"
        }
    }
}
