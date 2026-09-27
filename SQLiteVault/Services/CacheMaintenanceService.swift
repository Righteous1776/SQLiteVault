import Foundation

struct CacheMaintenanceService: Sendable {
    private let fileManager = FileManager.default

    private var extractionRoot: URL {
        fileManager.temporaryDirectory.appendingPathComponent("SQLiteVaultExtracted", isDirectory: true)
    }

    func snapshot() -> TemporaryCacheSnapshot {
        guard let enumerator = fileManager.enumerator(
            at: extractionRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return .empty }

        var bytes: Int64 = 0
        var count = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return TemporaryCacheSnapshot(bytes: bytes, fileCount: count)
    }

    @discardableResult
    func purge() throws -> TemporaryCacheSnapshot {
        let before = snapshot()
        if fileManager.fileExists(atPath: extractionRoot.path) {
            try fileManager.removeItem(at: extractionRoot)
        }
        return before
    }

    func purgeFiles(olderThan age: TimeInterval) throws {
        guard let enumerator = fileManager.enumerator(
            at: extractionRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) < cutoff else { continue }
            candidates.append(url)
        }
        for url in candidates { try? fileManager.removeItem(at: url) }
    }
}
