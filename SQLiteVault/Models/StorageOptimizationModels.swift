import Foundation

enum OptimizedStorageMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case optimized
    case keepDownloaded
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optimized: "Optimize Device Storage"
        case .keepDownloaded: "Keep All Downloaded"
        case .manual: "Manual"
        }
    }

    var detail: String {
        switch self {
        case .optimized:
            "Keep iCloud as the master copy and reclaim safe local copies when device storage is under pressure."
        case .keepDownloaded:
            "Request every SQLite database from iCloud and keep it available for offline use."
        case .manual:
            "Never automatically download or evict databases. You decide file by file."
        }
    }

    var symbol: String {
        switch self {
        case .optimized: "internaldrive.fill.badge.icloud"
        case .keepDownloaded: "arrow.down.circle.fill"
        case .manual: "hand.tap.fill"
        }
    }
}

enum LocalRetentionPolicy: String, Codable, Sendable, Hashable {
    case automatic
    case keepDownloaded
}

struct DeviceStorageSnapshot: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var freeRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(availableBytes) / Double(totalBytes)
    }
}

struct StorageOptimizationStatus: Sendable {
    let device: DeviceStorageSnapshot
    let downloadedCloudBytes: Int64
    let reclaimableBytes: Int64
    let reclaimableFileCount: Int
    let pinnedFileCount: Int
    let remoteOnlyFileCount: Int
    let cacheBudgetBytes: Int64?
    let overBudgetBytes: Int64
    let temporaryCacheBytes: Int64
    let temporaryCacheFileCount: Int
    let lastEvaluatedAt: Date

    static let empty = StorageOptimizationStatus(
        device: DeviceStorageSnapshot(totalBytes: 0, availableBytes: 0),
        downloadedCloudBytes: 0,
        reclaimableBytes: 0,
        reclaimableFileCount: 0,
        pinnedFileCount: 0,
        remoteOnlyFileCount: 0,
        cacheBudgetBytes: nil,
        overBudgetBytes: 0,
        temporaryCacheBytes: 0,
        temporaryCacheFileCount: 0,
        lastEvaluatedAt: .now
    )
}

struct StorageOptimizationResult: Sendable {
    let evictedFileNames: [String]
    let reclaimedBytes: Int64
    let skippedFileNames: [String]
    let automatic: Bool
}
