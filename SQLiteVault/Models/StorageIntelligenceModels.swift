import Foundation

enum CacheBudgetPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case oneGB
    case fiveGB
    case tenGB
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .oneGB: "1 GB"
        case .fiveGB: "5 GB"
        case .tenGB: "10 GB"
        case .unlimited: "Unlimited"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Adapt the local SQLite cache budget to this device's capacity."
        case .oneGB: "Keep up to roughly 1 GB of reclaimable SQLite copies on device."
        case .fiveGB: "Keep up to roughly 5 GB of reclaimable SQLite copies on device."
        case .tenGB: "Keep up to roughly 10 GB of reclaimable SQLite copies on device."
        case .unlimited: "Do not evict files because of a cache budget. Storage-pressure rules still protect the device."
        }
    }

    func byteLimit(totalDeviceBytes: Int64) -> Int64? {
        let gib: Int64 = 1024 * 1024 * 1024
        switch self {
        case .automatic:
            guard totalDeviceBytes > 0 else { return 5 * gib }
            // About 8% of device capacity, bounded so small and large devices behave predictably.
            return min(max(Int64(Double(totalDeviceBytes) * 0.08), 2 * gib), 12 * gib)
        case .oneGB: return gib
        case .fiveGB: return 5 * gib
        case .tenGB: return 10 * gib
        case .unlimited: return nil
        }
    }
}

enum DatabasePreparationPhase: String, Codable, Sendable {
    case idle
    case requestingDownload
    case downloading
    case verifyingHeader
    case integrityCheck
    case ready
    case failed
}

struct DatabasePreparationStatus: Sendable, Equatable {
    var phase: DatabasePreparationPhase = .idle
    var progress: Double = 0
    var message: String = ""
    var updatedAt: Date = .now

    static let idle = DatabasePreparationStatus()

    var isRunning: Bool {
        switch phase {
        case .requestingDownload, .downloading, .verifyingHeader, .integrityCheck: true
        default: false
        }
    }
}

struct StorageOptimizationCandidate: Identifiable, Hashable, Sendable {
    var id: String { fileName }
    let fileName: String
    let sizeBytes: Int64
    let lastOpenedAt: Date?
    let reason: String
}

struct StorageOptimizationPreview: Sendable {
    let candidates: [StorageOptimizationCandidate]
    let reclaimableBytes: Int64
    let protectedFileCount: Int
    let cacheBudgetBytes: Int64?
    let overBudgetBytes: Int64
    let storagePressureBytesNeeded: Int64
    let generatedAt: Date

    static let empty = StorageOptimizationPreview(
        candidates: [],
        reclaimableBytes: 0,
        protectedFileCount: 0,
        cacheBudgetBytes: nil,
        overBudgetBytes: 0,
        storagePressureBytesNeeded: 0,
        generatedAt: .now
    )
}

struct RecoveryPoint: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let reason: String
    let createdAt: Date
    let sizeBytes: Int64
    let snapshotFileName: String
    let a9StateNumber: Int?
    let a9Color: A9HealthColor?
    let schemaFingerprint: SchemaFingerprint?

    init(
        id: UUID,
        fileName: String,
        reason: String,
        createdAt: Date,
        sizeBytes: Int64,
        snapshotFileName: String,
        a9StateNumber: Int? = nil,
        a9Color: A9HealthColor? = nil,
        schemaFingerprint: SchemaFingerprint? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.reason = reason
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.snapshotFileName = snapshotFileName
        self.a9StateNumber = a9StateNumber
        self.a9Color = a9Color
        self.schemaFingerprint = schemaFingerprint
    }

    var displayReason: String { reason.isEmpty ? "Recovery point" : reason }
}

struct TemporaryCacheSnapshot: Sendable {
    let bytes: Int64
    let fileCount: Int

    static let empty = TemporaryCacheSnapshot(bytes: 0, fileCount: 0)
}
