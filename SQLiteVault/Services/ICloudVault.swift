import Foundation

actor ICloudVault {
    enum VaultError: LocalizedError {
        case unsupportedExtension
        case unableToAccessSource
        case destinationUnavailable
        case iCloudSignedOut
        case iCloudContainerUnavailable
        case cloudItemNotFound
        case invalidSQLiteHeader
        case integrityCheckFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension: "Only .sqlite, .sqlite3 and .db files are accepted."
            case .unableToAccessSource: "The selected file could not be accessed."
            case .destinationUnavailable: "No writable vault location is available."
            case .iCloudSignedOut: "iCloud is not available for this device or account."
            case .iCloudContainerUnavailable: "The SQLite Vault iCloud container is unavailable. Check the app signature and iCloud capability."
            case .cloudItemNotFound: "The selected iCloud item could not be found."
            case .invalidSQLiteHeader: "The downloaded file does not contain a valid SQLite header."
            case .integrityCheckFailed(let message): "SQLite integrity check failed: \(message)"
            }
        }
    }

    private let fileManager = FileManager.default
    let iCloudContainerID = "iCloud.com.zeostudio.SQLiteVault"
    private let acceptedExtensions = Set(["sqlite", "sqlite3", "db"])

    // MARK: - Active storage

    func vaultDirectory() throws -> (url: URL, location: DatabaseAsset.StorageLocation) {
        if let documents = try cloudDocumentsDirectoryIfAvailable(create: true) {
            return (documents, .iCloud)
        }
        return (try localFallbackDirectory(create: true), .localFallback)
    }

    func listDatabases() throws -> [DatabaseAsset] {
        let destination = try vaultDirectory()
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: destination.url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url -> DatabaseAsset? in
            guard acceptedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }

            let availability: DatabaseAsset.LocalAvailability
            if destination.location == .iCloud, values.isUbiquitousItem == true {
                if values.ubiquitousItemDownloadingStatus == .current { availability = .available }
                else { availability = .remoteOnly }
            } else {
                availability = .available
            }

            return DatabaseAsset(
                name: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent,
                fileURL: url,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                location: destination.location,
                schemaSummary: nil,
                localAvailability: availability
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func metadataDirectory() throws -> URL {
        let root = try vaultDirectory().url
        let directory = root.appending(path: ".SQLiteVault", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func catalogURL() throws -> URL {
        try metadataDirectory().appending(path: "catalog-v2.json")
    }

    // MARK: - Cloud observability

    func statusSnapshot() -> ICloudVaultStatus {
        let localSummary = localFallbackSummary()

        guard fileManager.ubiquityIdentityToken != nil else {
            return ICloudVaultStatus(
                connection: .signedOut,
                containerIdentifier: iCloudContainerID,
                containerPath: nil,
                cloudFiles: [],
                localFallbackFileCount: localSummary.count,
                localFallbackBytes: localSummary.bytes,
                lastCheckedAt: .now,
                detail: "iCloud account is unavailable. SQLite Vault is using local fallback storage."
            )
        }

        guard let container = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerID) else {
            return ICloudVaultStatus(
                connection: .containerUnavailable,
                containerIdentifier: iCloudContainerID,
                containerPath: nil,
                cloudFiles: [],
                localFallbackFileCount: localSummary.count,
                localFallbackBytes: localSummary.bytes,
                lastCheckedAt: .now,
                detail: "Signed into iCloud, but the SQLite Vault container is unavailable. Verify the signed app's iCloud capability and provisioning profile."
            )
        }

        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
            let files = try scanCloudFiles(in: documents)
            return ICloudVaultStatus(
                connection: .connected,
                containerIdentifier: iCloudContainerID,
                containerPath: documents.path,
                cloudFiles: files,
                localFallbackFileCount: localSummary.count,
                localFallbackBytes: localSummary.bytes,
                lastCheckedAt: .now,
                detail: "Connected to iCloud Drive. SQLite files in this container are uploaded and downloaded by iCloud Documents."
            )
        } catch {
            return ICloudVaultStatus(
                connection: .error,
                containerIdentifier: iCloudContainerID,
                containerPath: documents.path,
                cloudFiles: [],
                localFallbackFileCount: localSummary.count,
                localFallbackBytes: localSummary.bytes,
                lastCheckedAt: .now,
                detail: error.localizedDescription
            )
        }
    }

    func requestDownload(fileName: String) throws {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let url = documents.appending(path: fileName)
        guard fileManager.fileExists(atPath: url.path) else { throw VaultError.cloudItemNotFound }
        try fileManager.startDownloadingUbiquitousItem(at: url)
    }

    func requestDownloadAll() throws {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let urls = try fileManager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls where acceptedExtensions.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey])
            guard values?.isRegularFile == true, values?.ubiquitousItemDownloadingStatus != .current else { continue }
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
    }

    @discardableResult
    func migrateLocalFallbackDatabasesToICloud() throws -> Int {
        guard let cloud = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let local = try localFallbackDirectory(create: false)
        guard fileManager.fileExists(atPath: local.path) else { return 0 }

        let urls = try fileManager.contentsOfDirectory(
            at: local,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var migrated = 0
        for source in urls where acceptedExtensions.contains(source.pathExtension.lowercased()) {
            let target = uniqueDestination(for: source.lastPathComponent, in: cloud)
            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
                do { try fileManager.copyItem(at: readableURL, to: target) }
                catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            try fileManager.removeItem(at: source)
            migrated += 1
        }
        return migrated
    }


    // MARK: - Optimized storage

    func deviceStorageSnapshot() -> DeviceStorageSnapshot {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return DeviceStorageSnapshot(totalBytes: total, availableBytes: free)
        } catch {
            return DeviceStorageSnapshot(totalBytes: 0, availableBytes: 0)
        }
    }

    func optimizationStatus(
        pinnedFileNames: Set<String>,
        protectedFileNames: Set<String>,
        cacheBudgetBytes: Int64?,
        temporaryCache: TemporaryCacheSnapshot
    ) -> StorageOptimizationStatus {
        let cloud = statusSnapshot()
        let downloaded = cloud.cloudFiles.filter(\.isDownloaded).reduce(Int64(0)) { $0 + $1.sizeBytes }
        let eligible = cloud.cloudFiles.filter { file in
            !protectedFileNames.contains(file.fileName)
                && isSafeEvictionCandidate(file, pinnedFileNames: pinnedFileNames)
        }
        let overBudget = cacheBudgetBytes.map { max(Int64(0), downloaded - $0) } ?? 0
        return StorageOptimizationStatus(
            device: deviceStorageSnapshot(),
            downloadedCloudBytes: downloaded,
            reclaimableBytes: eligible.reduce(0) { $0 + $1.sizeBytes },
            reclaimableFileCount: eligible.count,
            pinnedFileCount: cloud.cloudFiles.filter { pinnedFileNames.contains($0.fileName) }.count,
            remoteOnlyFileCount: cloud.filesNeedingDownload,
            cacheBudgetBytes: cacheBudgetBytes,
            overBudgetBytes: overBudget,
            temporaryCacheBytes: temporaryCache.bytes,
            temporaryCacheFileCount: temporaryCache.fileCount,
            lastEvaluatedAt: .now
        )
    }

    func optimizationPreview(
        pinnedFileNames: Set<String>,
        protectedFileNames: Set<String>,
        lastOpenedAt: [String: Date],
        cacheBudgetBytes: Int64?
    ) throws -> StorageOptimizationPreview {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let device = deviceStorageSnapshot()
        let cloudFiles = try scanCloudFiles(in: documents)
        let downloaded = cloudFiles.filter(\.isDownloaded).reduce(Int64(0)) { $0 + $1.sizeBytes }
        let overBudget = cacheBudgetBytes.map { max(Int64(0), downloaded - $0) } ?? 0
        let targetFree = max(Int64(Double(device.totalBytes) * 0.18), 8 * 1024 * 1024 * 1024)
        let pressureNeeded = max(Int64(0), targetFree - device.availableBytes)

        let safe = cloudFiles.filter { file in
            !protectedFileNames.contains(file.fileName)
                && isSafeEvictionCandidate(file, pinnedFileNames: pinnedFileNames)
        }
        .sorted { lhs, rhs in
            let leftOpened = lastOpenedAt[lhs.fileName] ?? .distantPast
            let rightOpened = lastOpenedAt[rhs.fileName] ?? .distantPast
            if leftOpened == rightOpened { return lhs.sizeBytes > rhs.sizeBytes }
            return leftOpened < rightOpened
        }

        let candidates = safe.map { file in
            let lastUse = lastOpenedAt[file.fileName]
            let reason: String
            if overBudget > 0 && pressureNeeded > 0 {
                reason = "LRU candidate · cache budget and device free-space target"
            } else if overBudget > 0 {
                reason = "LRU candidate · local cache is over budget"
            } else if pressureNeeded > 0 {
                reason = "LRU candidate · device storage pressure"
            } else {
                reason = "Safe cloud-backed local copy"
            }
            return StorageOptimizationCandidate(
                fileName: file.fileName,
                sizeBytes: file.sizeBytes,
                lastOpenedAt: lastUse,
                reason: reason
            )
        }

        return StorageOptimizationPreview(
            candidates: candidates,
            reclaimableBytes: candidates.reduce(0) { $0 + $1.sizeBytes },
            protectedFileCount: cloudFiles.count - safe.count,
            cacheBudgetBytes: cacheBudgetBytes,
            overBudgetBytes: overBudget,
            storagePressureBytesNeeded: pressureNeeded,
            generatedAt: .now
        )
    }

    func evictLocalCopy(fileName: String, pinnedFileNames: Set<String>) throws -> Int64 {
        guard !pinnedFileNames.contains(fileName) else { return 0 }
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        guard let file = try scanCloudFiles(in: documents).first(where: { $0.fileName == fileName }) else {
            throw VaultError.cloudItemNotFound
        }
        guard isSafeEvictionCandidate(file, pinnedFileNames: pinnedFileNames) else { return 0 }
        try fileManager.evictUbiquitousItem(at: file.fileURL)
        return file.sizeBytes
    }

    func optimizeLocalCopies(
        pinnedFileNames: Set<String>,
        protectedFileNames: Set<String>,
        lastOpenedAt: [String: Date],
        force: Bool,
        cacheBudgetBytes: Int64?
    ) throws -> StorageOptimizationResult {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }

        let device = deviceStorageSnapshot()
        let pressureThreshold = max(Int64(Double(device.totalBytes) * 0.12), 5 * 1024 * 1024 * 1024)
        let targetFree = max(Int64(Double(device.totalBytes) * 0.18), 8 * 1024 * 1024 * 1024)
        let files = try scanCloudFiles(in: documents)
        let downloadedBytes = files.filter(\.isDownloaded).reduce(Int64(0)) { $0 + $1.sizeBytes }
        let overBudget = cacheBudgetBytes.map { max(Int64(0), downloadedBytes - $0) } ?? 0
        let storagePressure = device.availableBytes < pressureThreshold
        if !force, !storagePressure, overBudget == 0 {
            return StorageOptimizationResult(evictedFileNames: [], reclaimedBytes: 0, skippedFileNames: [], automatic: true)
        }

        let candidates = files.filter { file in
            guard !protectedFileNames.contains(file.fileName),
                  isSafeEvictionCandidate(file, pinnedFileNames: pinnedFileNames) else { return false }
            if !force, let lastUse = lastOpenedAt[file.fileName], Date().timeIntervalSince(lastUse) < 30 * 60 {
                return false
            }
            return true
        }
        .sorted { lhs, rhs in
            let leftOpened = lastOpenedAt[lhs.fileName] ?? .distantPast
            let rightOpened = lastOpenedAt[rhs.fileName] ?? .distantPast
            if leftOpened == rightOpened { return lhs.sizeBytes > rhs.sizeBytes }
            return leftOpened < rightOpened
        }

        var reclaimed: Int64 = 0
        var evicted: [String] = []
        var skipped: [String] = []
        var projectedFree = device.availableBytes
        var projectedDownloaded = downloadedBytes

        for file in candidates {
            if !force {
                let freeTargetMet = !storagePressure || projectedFree >= targetFree
                let budgetTargetMet = cacheBudgetBytes.map { projectedDownloaded <= $0 } ?? true
                if freeTargetMet && budgetTargetMet { break }
            }
            do {
                try fileManager.evictUbiquitousItem(at: file.fileURL)
                reclaimed += file.sizeBytes
                projectedFree += file.sizeBytes
                projectedDownloaded = max(0, projectedDownloaded - file.sizeBytes)
                evicted.append(file.fileName)
            } catch {
                skipped.append(file.fileName)
            }
        }

        return StorageOptimizationResult(
            evictedFileNames: evicted,
            reclaimedBytes: reclaimed,
            skippedFileNames: skipped,
            automatic: !force
        )
    }

    func validateSQLiteFile(fileName: String) throws {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let url = documents.appending(path: fileName)
        guard fileManager.fileExists(atPath: url.path) else { throw VaultError.cloudItemNotFound }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        guard header == Data("SQLite format 3\0".utf8) else { throw VaultError.invalidSQLiteHeader }
        let database = try SQLiteDatabase(url: url)
        let result = try database.integrityCheck()
        guard result.caseInsensitiveCompare("ok") == .orderedSame else {
            throw VaultError.integrityCheckFailed(result)
        }
    }

    func unresolvedConflictVersionURLs(fileName: String) throws -> [URL] {
        guard let documents = try cloudDocumentsDirectoryIfAvailable(create: true) else {
            throw fileManager.ubiquityIdentityToken == nil ? VaultError.iCloudSignedOut : VaultError.iCloudContainerUnavailable
        }
        let url = documents.appending(path: fileName)
        return NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.map(\.url) ?? []
    }

    func restoreDatabase(from snapshotURL: URL, preferredFileName: String) throws -> URL {
        let destination = try vaultDirectory().url
        let target = uniqueDestination(for: preferredFileName, in: destination)
        try fileManager.copyItem(at: snapshotURL, to: target)
        return target
    }

    private func isSafeEvictionCandidate(_ file: ICloudFileStatus, pinnedFileNames: Set<String>) -> Bool {
        file.isDownloaded
            && !file.isDownloading
            && !file.isUploading
            && !file.hasUnresolvedConflicts
            && file.isUploaded
            && file.percentUploaded >= 99.9
            && pinnedFileNames.contains(file.fileName) == false
    }

    // MARK: - Mutations

    func validateImportSource(_ source: URL) throws {
        guard acceptedExtensions.contains(source.pathExtension.lowercased()) else {
            throw VaultError.unsupportedExtension
        }
        let gotAccess = source.startAccessingSecurityScopedResource()
        defer { if gotAccess { source.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else { throw VaultError.unableToAccessSource }

        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        guard header == Data("SQLite format 3\0".utf8) else { throw VaultError.invalidSQLiteHeader }
        let database = try SQLiteDatabase(url: source)
        let result = try database.integrityCheck()
        guard result.caseInsensitiveCompare("ok") == .orderedSame else {
            throw VaultError.integrityCheckFailed(result)
        }
    }

    func importDatabase(from source: URL) throws -> URL {
        guard acceptedExtensions.contains(source.pathExtension.lowercased()) else {
            throw VaultError.unsupportedExtension
        }

        let gotAccess = source.startAccessingSecurityScopedResource()
        defer { if gotAccess { source.stopAccessingSecurityScopedResource() } }

        guard fileManager.fileExists(atPath: source.path) else { throw VaultError.unableToAccessSource }
        let destination = try vaultDirectory().url
        let target = uniqueDestination(for: source.lastPathComponent, in: destination)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do { try fileManager.copyItem(at: readableURL, to: target) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return target
    }

    func delete(_ asset: DatabaseAsset) throws {
        var coordinationError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: asset.fileURL, options: .forDeleting, error: &coordinationError) { url in
            do { try fileManager.removeItem(at: url) }
            catch { deleteError = error }
        }
        if let coordinationError { throw coordinationError }
        if let deleteError { throw deleteError }
    }

    // MARK: - Paths / scanning

    private func cloudDocumentsDirectoryIfAvailable(create: Bool) throws -> URL? {
        guard fileManager.ubiquityIdentityToken != nil else { return nil }
        guard let container = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerID) else { return nil }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        if create { try fileManager.createDirectory(at: documents, withIntermediateDirectories: true) }
        return documents
    }

    private func localFallbackDirectory(create: Bool) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VaultError.destinationUnavailable
        }
        let fallback = appSupport.appending(path: "SQLiteVault", directoryHint: .isDirectory)
        if create { try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true) }
        return fallback
    }

    private func localFallbackSummary() -> (count: Int, bytes: Int64) {
        guard let local = try? localFallbackDirectory(create: false), fileManager.fileExists(atPath: local.path),
              let urls = try? fileManager.contentsOfDirectory(
                at: local,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return (0, 0) }

        var count = 0
        var bytes: Int64 = 0
        for url in urls where acceptedExtensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (count, bytes)
    }

    private func scanCloudFiles(in directory: URL) throws -> [ICloudFileStatus] {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url -> ICloudFileStatus? in
            guard acceptedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }

            let downloaded = values.ubiquitousItemDownloadingStatus == .current || values.isUbiquitousItem != true
            let uploaded = values.ubiquitousItemIsUploaded ?? (values.isUbiquitousItem != true)
            let downloading = values.ubiquitousItemIsDownloading ?? false
            let uploading = values.ubiquitousItemIsUploading ?? false
            let conflict = values.ubiquitousItemHasUnresolvedConflicts ?? false
            let state: ICloudFileTransferState
            if conflict { state = .conflict }
            else if downloading { state = .downloading }
            else if uploading { state = .uploading }
            else if !downloaded { state = .remoteOnly }
            else { state = .current }

            return ICloudFileStatus(
                fileName: url.lastPathComponent,
                fileURL: url,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                isDownloaded: downloaded,
                isUploaded: uploaded,
                isDownloading: downloading,
                isUploading: uploading,
                percentDownloaded: downloaded ? 100 : (downloading ? 1 : 0),
                percentUploaded: uploaded ? 100 : (uploading ? 1 : 0),
                hasUnresolvedConflicts: conflict,
                transferState: state
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let original = directory.appending(path: fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appending(path: candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
