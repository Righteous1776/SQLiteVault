import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    var assets: [DatabaseAsset] = []
    var selectedAssetID: DatabaseAsset.ID?
    var catalog: VaultCatalog = .empty
    var isBusy = false
    var lastError: String?

    var globalSearchText = ""
    var globalSearchResults: [GlobalSearchHit] = []
    var isSearching = false
    var searchWorkspaceID: UUID?

    @ObservationIgnored private let vault = ICloudVault()
    @ObservationIgnored private let inspector = SchemaInspector()
    @ObservationIgnored private let catalogStore = VaultCatalogStore()
    @ObservationIgnored private let searchService = CrossVaultSearchService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var workspaces: [VaultWorkspace] {
        catalog.workspaces.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var allCategories: [String] {
        let workspaceCategories = catalog.workspaces.compactMap(\.category)
        let databaseCategories = catalog.assetMetadata.values.compactMap(\.category)
        return Array(Set(workspaceCategories + databaseCategories)).sorted()
    }

    var allTags: [String] {
        let workspaceTags = catalog.workspaces.flatMap(\.tags)
        let databaseTags = catalog.assetMetadata.values.flatMap(\.tags)
        return Array(Set(workspaceTags + databaseTags)).sorted()
    }

    func bootstrap() async {
        do {
            catalog = try await catalogStore.load()
        } catch {
            lastError = "Metadata catalog: \(error.localizedDescription)"
        }
        await refresh()
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            var discovered = try await vault.listDatabases()
            for index in discovered.indices {
                if let summary = try? inspector.inspect(url: discovered[index].fileURL).1 {
                    discovered[index].schemaSummary = summary
                }
            }
            assets = discovered
            if let selectedAssetID, !assets.contains(where: { $0.id == selectedAssetID }) {
                self.selectedAssetID = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importDatabase(from url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await vault.importDatabase(from: url)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ asset: DatabaseAsset) async {
        do {
            try await vault.delete(asset)
            if selectedAssetID == asset.id { selectedAssetID = nil }
            catalog.assetMetadata.removeValue(forKey: asset.fileName)
            catalog.workspaces = catalog.workspaces.map { workspace in
                var copy = workspace
                copy.databaseFileNames.removeAll { $0 == asset.fileName }
                if copy.databaseFileNames != workspace.databaseFileNames { copy.updatedAt = .now }
                return copy
            }
            try await persistCatalog()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func metadata(for asset: DatabaseAsset) -> DatabaseMetadata {
        catalog.assetMetadata[asset.fileName] ?? .empty
    }

    func updateMetadata(for asset: DatabaseAsset, category: String?, tags: [String], isFavorite: Bool) async {
        catalog.assetMetadata[asset.fileName] = DatabaseMetadata(category: category, tags: tags, isFavorite: isFavorite)
        await saveCatalogReportingErrors()
    }

    func createWorkspace(name: String, databaseFileNames: [String], category: String?, tags: [String]) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        catalog.workspaces.append(VaultWorkspace(
            name: trimmed,
            databaseFileNames: databaseFileNames,
            category: category,
            tags: tags
        ))
        await saveCatalogReportingErrors()
    }

    func updateWorkspace(_ workspace: VaultWorkspace, name: String, databaseFileNames: [String], category: String?, tags: [String]) async {
        guard let index = catalog.workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = VaultWorkspace(
            id: workspace.id,
            name: name,
            databaseFileNames: databaseFileNames,
            category: category,
            tags: tags,
            createdAt: workspace.createdAt,
            updatedAt: .now
        )
        if updated.name.isEmpty { updated.name = workspace.name }
        catalog.workspaces[index] = updated
        await saveCatalogReportingErrors()
    }

    func deleteWorkspace(_ workspace: VaultWorkspace) async {
        catalog.workspaces.removeAll { $0.id == workspace.id }
        if searchWorkspaceID == workspace.id { searchWorkspaceID = nil }
        await saveCatalogReportingErrors()
    }

    func workspace(id: UUID) -> VaultWorkspace? {
        catalog.workspaces.first { $0.id == id }
    }

    func assets(in workspace: VaultWorkspace) -> [DatabaseAsset] {
        let names = Set(workspace.databaseFileNames)
        return assets.filter { names.contains($0.fileName) }
    }

    func runGlobalSearch() {
        searchTask?.cancel()
        let query = globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            globalSearchResults = []
            isSearching = false
            return
        }

        let snapshotAssets = assets
        let workspace = searchWorkspaceID.flatMap { id in catalog.workspaces.first { $0.id == id } }
        isSearching = true

        searchTask = Task { [searchService] in
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    try searchService.search(query: query, assets: snapshotAssets, workspace: workspace)
                }.value
                guard !Task.isCancelled, query == self.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.globalSearchResults = results
                self.isSearching = false
            } catch is CancellationError {
                self.isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                self.globalSearchResults = []
                self.isSearching = false
                self.lastError = "Global search: \(error.localizedDescription)"
            }
        }
    }

    private func persistCatalog() async throws {
        catalog.updatedAt = .now
        try await catalogStore.save(catalog)
    }

    private func saveCatalogReportingErrors() async {
        do { try await persistCatalog() }
        catch { lastError = "Metadata catalog: \(error.localizedDescription)" }
    }
}
