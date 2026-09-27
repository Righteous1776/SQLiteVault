import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let storageModeKey = "SQLiteVault.optimizedStorageMode"
    private static let cacheBudgetKey = "SQLiteVault.cacheBudgetPreset"

    var assets: [DatabaseAsset] = []
    var selectedAssetID: DatabaseAsset.ID?
    var catalog: VaultCatalog = .empty
    var isBusy = false
    var lastError: String?

    var cloudStatus: ICloudVaultStatus = .checking
    var isCloudRefreshing = false
    var lastCloudAction: String?

    var storageMode: OptimizedStorageMode
    var cacheBudgetPreset: CacheBudgetPreset
    var storageOptimizationStatus: StorageOptimizationStatus = .empty
    var optimizationPreview: StorageOptimizationPreview = .empty
    var isOptimizingStorage = false
    var activeDatabaseFileName: String?
    var preparationStatusByFileName: [String: DatabasePreparationStatus] = [:]
    var recoveryPoints: [RecoveryPoint] = []
    var isRestoringRecovery = false

    var a9Decisions: [String: A9Decision] = [:]
    var a9History: [A9HealthHistoryEntry] = []
    var a9Preflights: [A9PreflightResult] = []
    var schemaFingerprints: [String: SchemaFingerprint] = [:]
    var isA9Scanning = false
    var lastA9ScanDepth: A9ScanDepth = .fast

    var globalSearchText = ""
    var globalSearchResults: [GlobalSearchHit] = []
    var isSearching = false
    var searchWorkspaceID: UUID?

    @ObservationIgnored private let vault = ICloudVault()
    @ObservationIgnored private let inspector = SchemaInspector()
    @ObservationIgnored private let catalogStore = VaultCatalogStore()
    @ObservationIgnored private let searchService = CrossVaultSearchService()
    @ObservationIgnored private let cacheMaintenance = CacheMaintenanceService()
    @ObservationIgnored private let recoveryService = RecoveryService()
    @ObservationIgnored private let a9HealthService = A9DatabaseHealthService()
    @ObservationIgnored private let a9LifecycleService = A9LifecycleService()
    @ObservationIgnored private let schemaFingerprintService = SchemaFingerprintService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageModeKey)
        storageMode = OptimizedStorageMode(rawValue: saved ?? "") ?? .optimized
        let budget = UserDefaults.standard.string(forKey: Self.cacheBudgetKey)
        cacheBudgetPreset = CacheBudgetPreset(rawValue: budget ?? "") ?? .automatic
    }

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

    var a9GreenCount: Int { a9Decisions.values.filter { $0.color == .green }.count }
    var a9YellowCount: Int { a9Decisions.values.filter { $0.color == .yellow }.count }
    var a9RedCount: Int { a9Decisions.values.filter { $0.color == .red }.count }

    var a9WorstColor: A9HealthColor {
        if a9RedCount > 0 { return .red }
        if a9YellowCount > 0 { return .yellow }
        return .green
    }

    func a9Decision(for asset: DatabaseAsset) -> A9Decision? {
        a9Decisions[asset.fileName]
    }

    func a9History(for asset: DatabaseAsset) -> [A9HealthHistoryEntry] {
        a9History.filter { $0.fileName == asset.fileName }
    }

    func a9Preflights(for asset: DatabaseAsset) -> [A9PreflightResult] {
        a9Preflights.filter { $0.fileName == asset.fileName }
    }

    func schemaFingerprint(for asset: DatabaseAsset) -> SchemaFingerprint? {
        schemaFingerprints[asset.fileName]
    }

    func lifecyclePhase(for asset: DatabaseAsset) -> DatabaseLifecyclePhase {
        if cloudStatus.cloudFiles.first(where: { $0.fileName == asset.fileName })?.hasUnresolvedConflicts == true {
            return .conflict
        }
        if activeDatabaseFileName == asset.fileName { return .active }
        let preparation = preparationStatus(for: asset.fileName)
        switch preparation.phase {
        case .requestingDownload, .downloading: return .downloading
        case .verifyingHeader, .integrityCheck: return .validating
        default: break
        }
        return asset.isLocallyAvailable ? .ready : .cloudOnly
    }

    func bootstrap() async {
        do {
            catalog = try await catalogStore.load()
        } catch {
            lastError = "Metadata catalog: \(error.localizedDescription)"
        }
        try? cacheMaintenance.purgeFiles(olderThan: 24 * 60 * 60)
        await refreshRecoveryPoints()
        await refreshA9LifecycleState()
        await refresh()
    }

    func refreshCloudStatus() async {
        cloudStatus = await vault.statusSnapshot()
        var protectedForStatus = protectedFileNames
        if let activeDatabaseFileName { protectedForStatus.insert(activeDatabaseFileName) }
        let device = await vault.deviceStorageSnapshot()
        let budgetBytes = cacheBudgetPreset.byteLimit(totalDeviceBytes: device.totalBytes)
        let temporaryCache = cacheMaintenance.snapshot()
        storageOptimizationStatus = await vault.optimizationStatus(
            pinnedFileNames: pinnedFileNames,
            protectedFileNames: protectedForStatus,
            cacheBudgetBytes: budgetBytes,
            temporaryCache: temporaryCache
        )
        optimizationPreview = (try? await vault.optimizationPreview(
            pinnedFileNames: pinnedFileNames,
            protectedFileNames: protectedForStatus,
            lastOpenedAt: lastOpenedSnapshot,
            cacheBudgetBytes: budgetBytes
        )) ?? .empty

        let cloudByName = Dictionary(uniqueKeysWithValues: cloudStatus.cloudFiles.map { ($0.fileName, $0) })
        for index in assets.indices where assets[index].location == .iCloud {
            guard let cloudFile = cloudByName[assets[index].fileName] else { continue }
            let availability: DatabaseAsset.LocalAvailability
            if cloudFile.isDownloaded { availability = .available }
            else if cloudFile.isDownloading { availability = .downloading }
            else { availability = .remoteOnly }

            let becameAvailable = assets[index].localAvailability != .available && availability == .available
            assets[index].localAvailability = availability
            assets[index].sizeBytes = cloudFile.sizeBytes
            assets[index].modifiedAt = cloudFile.modifiedAt
            if availability != .available {
                assets[index].schemaSummary = nil
            } else if becameAvailable, let summary = try? inspector.inspect(url: assets[index].fileURL).1 {
                assets[index].schemaSummary = summary
            }
        }
    }

    func setCacheBudgetPreset(_ preset: CacheBudgetPreset) async {
        cacheBudgetPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: Self.cacheBudgetKey)
        lastCloudAction = preset == .unlimited
            ? "Local SQLite cache budget disabled."
            : "Local SQLite cache budget set to \(preset.title)."
        await refreshCloudStatus()
        if storageMode == .optimized { await optimizeStorageNow(automatic: true) }
    }

    func setStorageMode(_ mode: OptimizedStorageMode) async {
        guard storageMode != mode else { return }
        storageMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.storageModeKey)

        switch mode {
        case .keepDownloaded:
            do {
                try await vault.requestDownloadAll()
                lastCloudAction = "Keep All Downloaded enabled. Requested every remote SQLite database."
            } catch {
                lastError = "iCloud: \(error.localizedDescription)"
            }
            await refresh()
        case .optimized:
            lastCloudAction = "Optimize Device Storage enabled. iCloud remains the master copy."
            await optimizeStorageNow(automatic: true)
        case .manual:
            lastCloudAction = "Manual storage management enabled."
            await refreshCloudStatus()
        }
    }

    func syncICloudNow() async {
        guard !isCloudRefreshing else { return }
        isCloudRefreshing = true
        defer { isCloudRefreshing = false }
        do {
            if storageMode == .keepDownloaded {
                try await vault.requestDownloadAll()
                lastCloudAction = "Requested all remote SQLite files from iCloud."
            } else {
                lastCloudAction = "Refreshed iCloud file and transfer status."
            }
            await refresh()
        } catch {
            lastError = "iCloud: \(error.localizedDescription)"
            await refreshCloudStatus()
        }
    }

    func requestICloudDownload(_ file: ICloudFileStatus) async {
        do {
            try await vault.requestDownload(fileName: file.fileName)
            lastCloudAction = "Download requested: \(file.fileName)"
            if let index = assets.firstIndex(where: { $0.fileName == file.fileName }) {
                assets[index].localAvailability = .downloading
            }
            await refreshCloudStatus()
        } catch {
            lastError = "iCloud: \(error.localizedDescription)"
        }
    }

    func requestDatabaseDownload(_ asset: DatabaseAsset) async {
        guard asset.location == .iCloud else { return }
        do {
            try await vault.requestDownload(fileName: asset.fileName)
            lastCloudAction = "Download requested: \(asset.fileName)"
            if let index = assets.firstIndex(where: { $0.fileName == asset.fileName }) {
                assets[index].localAvailability = .downloading
            }
            await refreshCloudStatus()
        } catch {
            lastError = "iCloud: \(error.localizedDescription)"
        }
    }

    func preparationStatus(for fileName: String) -> DatabasePreparationStatus {
        preparationStatusByFileName[fileName] ?? .idle
    }

    func prepareDatabaseForOpen(_ asset: DatabaseAsset) async {
        guard asset.location == .iCloud, !asset.isLocallyAvailable else { return }
        guard preparationStatus(for: asset.fileName).isRunning == false else { return }
        _ = await runA9Preflight(action: .prepareForOpen, asset: asset)

        preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
            phase: .requestingDownload, progress: 0.02, message: "Requesting iCloud download…", updatedAt: .now
        )
        do {
            try await vault.requestDownload(fileName: asset.fileName)
            if let index = assets.firstIndex(where: { $0.fileName == asset.fileName }) {
                assets[index].localAvailability = .downloading
            }

            var downloaded = false
            for _ in 0..<180 {
                try Task.checkCancellation()
                let snapshot = await vault.statusSnapshot()
                guard let file = snapshot.cloudFiles.first(where: { $0.fileName == asset.fileName }) else {
                    throw ICloudVault.VaultError.cloudItemNotFound
                }
                if file.isDownloaded {
                    downloaded = true
                    break
                }
                preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
                    phase: .downloading,
                    progress: min(max(file.percentDownloaded / 100.0, 0.03), 0.92),
                    message: "Downloading from iCloud · \(Int(file.percentDownloaded.rounded()))%",
                    updatedAt: .now
                )
                try await Task.sleep(for: .milliseconds(500))
            }
            guard downloaded else {
                throw NSError(domain: "SQLiteVault.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "The iCloud download did not finish in time."])
            }

            preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
                phase: .verifyingHeader, progress: 0.94, message: "Verifying SQLite header…", updatedAt: .now
            )
            try await Task.sleep(for: .milliseconds(70))
            preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
                phase: .integrityCheck, progress: 0.97, message: "Running SQLite integrity check…", updatedAt: .now
            )
            try await vault.validateSQLiteFile(fileName: asset.fileName)
            preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
                phase: .ready, progress: 1, message: "Database ready", updatedAt: .now
            )
            activeDatabaseFileName = asset.fileName
            var metadata = catalog.assetMetadata[asset.fileName] ?? .empty
            metadata.lastOpenedAt = .now
            catalog.assetMetadata[asset.fileName] = metadata
            await saveCatalogReportingErrors()
            lastCloudAction = "Downloaded and verified: \(asset.fileName)"
            await refresh()
            await runA9Scan(depth: .deep, fileName: asset.fileName, trigger: "Post-download verification")
        } catch is CancellationError {
            preparationStatusByFileName[asset.fileName] = .idle
        } catch {
            preparationStatusByFileName[asset.fileName] = DatabasePreparationStatus(
                phase: .failed, progress: 0, message: error.localizedDescription, updatedAt: .now
            )
            lastError = "Prepare database: \(error.localizedDescription)"
            await refreshCloudStatus()
        }
    }

    func runA9Scan(
        depth: A9ScanDepth = .fast,
        fileName: String? = nil,
        trigger: String = "Manual scan"
    ) async {
        guard !isA9Scanning else { return }
        isA9Scanning = true
        lastA9ScanDepth = depth
        defer { isA9Scanning = false }

        let targets = fileName.map { name in assets.filter { $0.fileName == name } } ?? assets
        let cloudByName = Dictionary(uniqueKeysWithValues: cloudStatus.cloudFiles.map { ($0.fileName, $0) })

        for asset in targets {
            // A lightweight pass must never erase a stronger Deep finding.
            // Yellow/RED Deep decisions remain authoritative until another Deep pass is requested.
            if depth == .fast,
               let existing = a9Decisions[asset.fileName],
               existing.scanDepth == .deep,
               existing.color != .green {
                continue
            }

            let previousFingerprint = await a9LifecycleService.previousFingerprint(fileName: asset.fileName)
            let currentFingerprint = asset.isLocallyAvailable
                ? (try? schemaFingerprintService.fingerprint(url: asset.fileURL))
                : nil
            let schemaDrift = previousFingerprint != nil
                && currentFingerprint != nil
                && previousFingerprint?.digest != currentFingerprint?.digest

            let decision = await a9HealthService.scan(
                asset: asset,
                cloudFile: cloudByName[asset.fileName],
                preparation: preparationStatus(for: asset.fileName),
                depth: depth,
                schemaDriftDetected: schemaDrift
            )
            a9Decisions[asset.fileName] = decision
            let nonDriftFaults = decision.signals.filter { $0.id != "schema-fingerprint-drift" && ($0.riskPoints > 0 || $0.blocker) }
            let deepConfirmedDrift = schemaDrift && depth == .deep && nonDriftFaults.isEmpty
            let updateTrustedFingerprint = !schemaDrift || deepConfirmedDrift
            await a9LifecycleService.recordDecision(
                decision,
                fingerprint: currentFingerprint,
                trigger: trigger,
                updateTrustedFingerprint: updateTrustedFingerprint
            )
            if updateTrustedFingerprint, let currentFingerprint {
                schemaFingerprints[asset.fileName] = currentFingerprint
            }
        }

        let existing = Set(assets.map(\.fileName))
        a9Decisions = a9Decisions.filter { existing.contains($0.key) }
        await refreshA9LifecycleState()
    }

    @discardableResult
    private func runA9Preflight(
        action: A9LifecycleAction,
        asset: DatabaseAsset,
        preferDeep: Bool = false
    ) async -> A9PreflightResult {
        let depth: A9ScanDepth = preferDeep && asset.isLocallyAvailable ? .deep : .fast
        await runA9Scan(depth: depth, fileName: asset.fileName, trigger: "Preflight · \(action.title)")

        let drift = a9Decisions[asset.fileName]?.signals.contains(where: { $0.id == "schema-fingerprint-drift" }) == true
        let hasRecovery = recoveryPoints.contains { $0.fileName == asset.fileName }
        let result = await a9LifecycleService.recordPreflight(
            fileName: asset.fileName,
            action: action,
            decision: a9Decisions[asset.fileName],
            schemaDriftDetected: drift,
            hasRecoveryPoint: hasRecovery
        )
        await refreshA9LifecycleState()
        return result
    }

    private func refreshA9LifecycleState() async {
        let snapshot = await a9LifecycleService.snapshot()
        a9History = snapshot.history
        a9Preflights = snapshot.preflights
        schemaFingerprints = snapshot.fingerprints
    }

    func acknowledgeA9RedLatch(for asset: DatabaseAsset) async {
        await a9HealthService.acknowledgeRedLatch(fileName: asset.fileName)
        await runA9Scan(depth: .deep, fileName: asset.fileName)
        lastCloudAction = "A9 RED latch acknowledged for \(asset.fileName). A fresh Deep decision was generated."
    }

    func setKeepDownloaded(_ keep: Bool, for fileName: String) async {
        var metadata = catalog.assetMetadata[fileName] ?? .empty
        metadata.retentionPolicy = keep ? .keepDownloaded : .automatic
        catalog.assetMetadata[fileName] = metadata
        await saveCatalogReportingErrors()

        if keep {
            do {
                try await vault.requestDownload(fileName: fileName)
                lastCloudAction = "Pinned for offline use: \(fileName)"
            } catch {
                lastError = "iCloud: \(error.localizedDescription)"
            }
        } else {
            lastCloudAction = "Returned to automatic storage management: \(fileName)"
        }
        await refreshCloudStatus()
    }

    func removeLocalCopy(fileName: String) async {
        guard activeDatabaseFileName != fileName else {
            lastError = "Close this database before removing its local copy."
            return
        }
        if catalog.assetMetadata[fileName]?.isFavorite == true {
            lastError = "Favorite databases are protected from local eviction. Remove the favorite first or use another file."
            return
        }

        do {
            if let asset = assets.first(where: { $0.fileName == fileName }) {
                let preflight = await runA9Preflight(action: .evictLocalCopy, asset: asset, preferDeep: true)
                if preflight.requiresRecovery, asset.isLocallyAvailable {
                    _ = try await recoveryService.createRecoveryPoint(
                        sourceURL: asset.fileURL,
                        fileName: asset.fileName,
                        reason: "Before local eviction · A9 \(preflight.disposition.title)",
                        a9Decision: a9Decisions[fileName],
                        schemaFingerprint: schemaFingerprints[fileName]
                    )
                    await refreshRecoveryPoints()
                }
            }
            let bytes = try await vault.evictLocalCopy(fileName: fileName, pinnedFileNames: pinnedFileNames)
            if bytes > 0 {
                lastCloudAction = "Freed \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) from this device. The iCloud copy remains."
                if let index = assets.firstIndex(where: { $0.fileName == fileName }) {
                    assets[index].localAvailability = .remoteOnly
                    assets[index].schemaSummary = nil
                }
            } else {
                lastCloudAction = "This file is not currently safe to evict."
            }
            await refreshCloudStatus()
        } catch {
            lastError = "Optimize storage: \(error.localizedDescription)"
        }
    }

    func optimizeStorageNow(automatic: Bool = false) async {
        guard storageMode == .optimized || !automatic, !isOptimizingStorage else { return }
        guard cloudStatus.isConnected else {
            if !automatic { lastError = "iCloud must be connected before optimizing local copies." }
            return
        }
        isOptimizingStorage = true
        defer { isOptimizingStorage = false }

        await runA9Scan(depth: .fast, trigger: "Preflight · Optimize storage")
        let favoriteNames = Set(catalog.assetMetadata.compactMap { $0.value.isFavorite ? $0.key : nil })
        var protected = favoriteNames
        protected.formUnion(a9Decisions.compactMap { key, decision in decision.color == .green ? nil : key })
        if let activeDatabaseFileName { protected.insert(activeDatabaseFileName) }

        for asset in assets where asset.location == .iCloud && asset.isLocallyAvailable {
            let hasRecovery = recoveryPoints.contains { $0.fileName == asset.fileName }
            let drift = a9Decisions[asset.fileName]?.signals.contains(where: { $0.id == "schema-fingerprint-drift" }) == true
            _ = await a9LifecycleService.recordPreflight(
                fileName: asset.fileName,
                action: .optimizeStorage,
                decision: a9Decisions[asset.fileName],
                schemaDriftDetected: drift,
                hasRecoveryPoint: hasRecovery
            )
        }
        await refreshA9LifecycleState()
        let lastOpened = Dictionary(uniqueKeysWithValues: catalog.assetMetadata.compactMap { key, value in
            value.lastOpenedAt.map { (key, $0) }
        })

        do {
            let result = try await vault.optimizeLocalCopies(
                pinnedFileNames: pinnedFileNames,
                protectedFileNames: protected,
                lastOpenedAt: lastOpened,
                force: !automatic,
                cacheBudgetBytes: cacheBudgetPreset.byteLimit(totalDeviceBytes: storageOptimizationStatus.device.totalBytes)
            )
            for fileName in result.evictedFileNames {
                if let index = assets.firstIndex(where: { $0.fileName == fileName }) {
                    assets[index].localAvailability = .remoteOnly
                    assets[index].schemaSummary = nil
                }
            }

            if result.evictedFileNames.isEmpty {
                if !automatic {
                    lastCloudAction = "No safe local database copies are currently reclaimable."
                }
            } else {
                let size = ByteCountFormatter.string(fromByteCount: result.reclaimedBytes, countStyle: .file)
                lastCloudAction = "Optimized \(result.evictedFileNames.count) database(s) and freed \(size). iCloud copies remain intact."
            }
            await refreshCloudStatus()
        } catch {
            lastError = "Optimize storage: \(error.localizedDescription)"
        }
    }

    func markDatabaseOpened(_ asset: DatabaseAsset) async {
        _ = await runA9Preflight(action: .prepareForOpen, asset: asset)
        activeDatabaseFileName = asset.fileName
        var metadata = catalog.assetMetadata[asset.fileName] ?? .empty
        metadata.lastOpenedAt = .now
        catalog.assetMetadata[asset.fileName] = metadata
        await saveCatalogReportingErrors()
    }

    func markDatabaseClosed(_ asset: DatabaseAsset) {
        if activeDatabaseFileName == asset.fileName { activeDatabaseFileName = nil }
    }

    func migrateLocalFallbackToICloud() async {
        guard !isCloudRefreshing else { return }
        isCloudRefreshing = true
        defer { isCloudRefreshing = false }
        do {
            let count = try await vault.migrateLocalFallbackDatabasesToICloud()
            lastCloudAction = count == 0 ? "No local fallback databases to migrate." : "Moved \(count) local database(s) into iCloud Drive."
            await refresh()
        } catch {
            lastError = "iCloud migration: \(error.localizedDescription)"
            await refreshCloudStatus()
        }
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            var discovered = try await vault.listDatabases()
            for index in discovered.indices where discovered[index].isLocallyAvailable {
                if let summary = try? inspector.inspect(url: discovered[index].fileURL).1 {
                    discovered[index].schemaSummary = summary
                }
            }
            assets = discovered
            if let selectedAssetID, !assets.contains(where: { $0.id == selectedAssetID }) {
                self.selectedAssetID = nil
            }
            await refreshCloudStatus()
            if storageMode == .optimized, cloudStatus.isConnected {
                await optimizeStorageNow(automatic: true)
            }
            await runA9Scan(depth: .fast)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importDatabase(from url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let importDecision = await a9HealthService.scanImportSource(url: url)
            _ = await a9LifecycleService.recordPreflight(
                fileName: url.lastPathComponent,
                action: .importDatabase,
                decision: importDecision,
                schemaDriftDetected: false,
                hasRecoveryPoint: true
            )
            await refreshA9LifecycleState()
            try await vault.validateImportSource(url)
            let importedURL = try await vault.importDatabase(from: url)
            lastCloudAction = cloudStatus.isConnected
                ? "Database passed import preflight and was copied into the iCloud Vault."
                : "Database passed import preflight and was copied into local fallback storage."
            await refresh()
            if let imported = assets.first(where: { $0.fileName == importedURL.lastPathComponent }) {
                _ = await runA9Preflight(action: .importDatabase, asset: imported, preferDeep: true)
            }
        } catch {
            lastError = "Import preflight: \(error.localizedDescription)"
        }
    }

    func delete(_ asset: DatabaseAsset) async {
        guard activeDatabaseFileName != asset.fileName else {
            lastError = "Close this database before deleting it."
            return
        }
        guard asset.isLocallyAvailable else {
            lastError = "Download & Verify this database before deletion so SQLite Vault can preserve a Recovery snapshot and A9 evidence."
            return
        }
        do {
            let preflight = await runA9Preflight(action: .deleteDatabase, asset: asset, preferDeep: true)
            if asset.isLocallyAvailable {
                _ = try await recoveryService.createRecoveryPoint(
                    sourceURL: asset.fileURL,
                    fileName: asset.fileName,
                    reason: "Before deletion · A9 \(preflight.disposition.title)",
                    a9Decision: a9Decisions[asset.fileName],
                    schemaFingerprint: schemaFingerprints[asset.fileName]
                )
                await refreshRecoveryPoints()
            }
            try await vault.delete(asset)
            lastCloudAction = asset.location == .iCloud ? "Removed database from the iCloud Vault." : "Removed database from local fallback storage."
            if selectedAssetID == asset.id { selectedAssetID = nil }
            catalog.assetMetadata.removeValue(forKey: asset.fileName)
            a9Decisions.removeValue(forKey: asset.fileName)
            await a9HealthService.forget(fileName: asset.fileName)
            await a9LifecycleService.forget(fileName: asset.fileName)
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
        let existing = catalog.assetMetadata[asset.fileName] ?? .empty
        catalog.assetMetadata[asset.fileName] = DatabaseMetadata(
            category: category,
            tags: tags,
            isFavorite: isFavorite,
            retentionPolicy: existing.retentionPolicy,
            lastOpenedAt: existing.lastOpenedAt
        )
        await saveCatalogReportingErrors()
        await refreshCloudStatus()
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

    func purgeTemporaryPreviewCache() async {
        do {
            let purged = try cacheMaintenance.purge()
            if purged.bytes > 0 {
                lastCloudAction = "Cleared \(ByteCountFormatter.string(fromByteCount: purged.bytes, countStyle: .file)) of temporary document previews."
            } else {
                lastCloudAction = "Temporary document preview cache is already empty."
            }
            await refreshCloudStatus()
        } catch {
            lastError = "Temporary cache: \(error.localizedDescription)"
        }
    }

    func refreshRecoveryPoints() async {
        recoveryPoints = (try? await recoveryService.listRecoveryPoints()) ?? []
    }

    func createRecoveryPoint(for asset: DatabaseAsset, reason: String = "Manual restore point") async {
        guard asset.isLocallyAvailable else {
            lastError = "Download this database before creating a restore point."
            return
        }
        do {
            _ = await runA9Preflight(action: .createRecovery, asset: asset, preferDeep: true)
            let point = try await recoveryService.createRecoveryPoint(
                sourceURL: asset.fileURL,
                fileName: asset.fileName,
                reason: reason,
                a9Decision: a9Decisions[asset.fileName],
                schemaFingerprint: schemaFingerprints[asset.fileName]
            )
            lastCloudAction = "Created restore point for \(point.fileName) with A9 lifecycle metadata."
            await refreshRecoveryPoints()
        } catch {
            lastError = "Recovery: \(error.localizedDescription)"
        }
    }

    func captureConflictRecovery(fileName: String) async {
        do {
            if let asset = assets.first(where: { $0.fileName == fileName }) {
                _ = await runA9Preflight(action: .captureConflict, asset: asset)
            }
            let urls = try await vault.unresolvedConflictVersionURLs(fileName: fileName)
            guard !urls.isEmpty else {
                lastCloudAction = "No unresolved conflict versions were available to capture."
                return
            }
            for (index, url) in urls.enumerated() {
                _ = try await recoveryService.createRecoveryPoint(
                    sourceURL: url,
                    fileName: fileName,
                    reason: "iCloud conflict copy \(index + 1)",
                    a9Decision: a9Decisions[fileName],
                    schemaFingerprint: schemaFingerprints[fileName]
                )
            }
            lastCloudAction = "Captured \(urls.count) iCloud conflict version(s) into Recovery."
            await refreshRecoveryPoints()
        } catch {
            lastError = "Conflict recovery: \(error.localizedDescription)"
        }
    }

    func restoreRecoveryPoint(_ point: RecoveryPoint) async {
        guard !isRestoringRecovery else { return }
        guard activeDatabaseFileName != point.fileName else {
            lastError = "Close the active database before restoring a recovery point."
            return
        }
        isRestoringRecovery = true
        defer { isRestoringRecovery = false }
        do {
            if let existing = assets.first(where: { $0.fileName == point.fileName }) {
                _ = await runA9Preflight(action: .restoreRecovery, asset: existing, preferDeep: true)
            }
            let snapshotURL = try await recoveryService.snapshotURL(for: point)
            _ = try await vault.restoreDatabase(from: snapshotURL, preferredFileName: point.fileName)
            lastCloudAction = "Restored \(point.fileName) from \(point.createdAt.formatted(date: .abbreviated, time: .shortened))."
            await refresh()
            if let restored = assets.first(where: { $0.fileName == point.fileName || $0.name.hasPrefix((point.fileName as NSString).deletingPathExtension) }) {
                await runA9Scan(depth: .deep, fileName: restored.fileName, trigger: "Post-recovery restore")
            }
        } catch {
            lastError = "Recovery restore: \(error.localizedDescription)"
        }
    }

    func deleteRecoveryPoint(_ point: RecoveryPoint) async {
        do {
            try await recoveryService.delete(point)
            await refreshRecoveryPoints()
        } catch {
            lastError = "Recovery: \(error.localizedDescription)"
        }
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

    private var protectedFileNames: Set<String> {
        Set(catalog.assetMetadata.compactMap { key, value in
            value.isFavorite ? key : nil
        })
    }

    private var lastOpenedSnapshot: [String: Date] {
        Dictionary(uniqueKeysWithValues: catalog.assetMetadata.compactMap { key, value in
            value.lastOpenedAt.map { (key, $0) }
        })
    }

    private var pinnedFileNames: Set<String> {
        Set(catalog.assetMetadata.compactMap { key, value in
            value.retentionPolicy == .keepDownloaded ? key : nil
        })
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
