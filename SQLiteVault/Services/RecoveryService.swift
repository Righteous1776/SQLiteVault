import Foundation

actor RecoveryService {
    enum RecoveryError: LocalizedError {
        case sourceUnavailable
        case pointUnavailable
        case destinationUnavailable

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable: "The database is not available locally, so a recovery point cannot be created."
            case .pointUnavailable: "The selected recovery point is no longer available."
            case .destinationUnavailable: "Recovery storage is unavailable."
            }
        }
    }

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    private func rootDirectory() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RecoveryError.destinationUnavailable
        }
        let root = appSupport.appendingPathComponent("SQLiteVaultRecovery", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func createRecoveryPoint(
        sourceURL: URL,
        fileName: String,
        reason: String,
        a9Decision: A9Decision? = nil,
        schemaFingerprint: SchemaFingerprint? = nil
    ) throws -> RecoveryPoint {
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw RecoveryError.sourceUnavailable }

        let id = UUID()
        let directory = try rootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = (fileName as NSString).pathExtension
        let snapshotName = ext.isEmpty ? "snapshot.sqlite" : "snapshot.\(ext)"
        let snapshotURL = directory.appendingPathComponent(snapshotName)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readableURL in
            do { try fileManager.copyItem(at: readableURL, to: snapshotURL) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }

        let size = (try? snapshotURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let point = RecoveryPoint(
            id: id,
            fileName: fileName,
            reason: reason,
            createdAt: .now,
            sizeBytes: size,
            snapshotFileName: snapshotName,
            a9StateNumber: a9Decision?.stateNumber,
            a9Color: a9Decision?.color,
            schemaFingerprint: schemaFingerprint
        )
        try encoder.encode(point).write(to: directory.appendingPathComponent("metadata.json"), options: [.atomic])
        try prune(maxCount: 20, maxBytes: 4 * 1024 * 1024 * 1024)
        return point
    }

    func listRecoveryPoints() throws -> [RecoveryPoint] {
        let root = try rootDirectory()
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: directory.appendingPathComponent("metadata.json")),
                  let point = try? decoder.decode(RecoveryPoint.self, from: data) else { return nil }
            return point
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func snapshotURL(for point: RecoveryPoint) throws -> URL {
        let url = try rootDirectory()
            .appendingPathComponent(point.id.uuidString, isDirectory: true)
            .appendingPathComponent(point.snapshotFileName)
        guard fileManager.fileExists(atPath: url.path) else { throw RecoveryError.pointUnavailable }
        return url
    }

    func delete(_ point: RecoveryPoint) throws {
        let directory = try rootDirectory().appendingPathComponent(point.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    private func prune(maxCount: Int, maxBytes: Int64) throws {
        var points = try listRecoveryPoints()
        var total = points.reduce(Int64(0)) { $0 + $1.sizeBytes }
        while points.count > maxCount || total > maxBytes {
            guard let oldest = points.last else { break }
            try delete(oldest)
            total -= oldest.sizeBytes
            points.removeLast()
        }
    }
}
