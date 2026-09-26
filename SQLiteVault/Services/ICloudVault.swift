import Foundation

actor ICloudVault {
    enum VaultError: LocalizedError {
        case unsupportedExtension
        case unableToAccessSource
        case destinationUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension: "Only .sqlite, .sqlite3 and .db files are accepted."
            case .unableToAccessSource: "The selected file could not be accessed."
            case .destinationUnavailable: "No writable vault location is available."
            }
        }
    }

    private let fileManager = FileManager.default
    private let iCloudContainerID = "iCloud.com.zeostudio.SQLiteVault"
    private let acceptedExtensions = Set(["sqlite", "sqlite3", "db"])

    func vaultDirectory() throws -> (url: URL, location: DatabaseAsset.StorageLocation) {
        if let container = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerID) {
            let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
            return (documents, .iCloud)
        }

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VaultError.destinationUnavailable
        }
        let fallback = appSupport.appending(path: "SQLiteVault", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return (fallback, .localFallback)
    }

    func listDatabases() throws -> [DatabaseAsset] {
        let destination = try vaultDirectory()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = try fileManager.contentsOfDirectory(
            at: destination.url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            guard acceptedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            return DatabaseAsset(
                name: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent,
                fileURL: url,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                location: destination.location,
                schemaSummary: nil
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
