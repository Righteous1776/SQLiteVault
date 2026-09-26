import Foundation

enum A9LifecycleAction: String, CaseIterable, Codable, Sendable {
    case importDatabase
    case prepareForOpen
    case createRecovery
    case restoreRecovery
    case deleteDatabase
    case evictLocalCopy
    case optimizeStorage
    case captureConflict

    var title: String {
        switch self {
        case .importDatabase: "Import"
        case .prepareForOpen: "Open"
        case .createRecovery: "Recovery snapshot"
        case .restoreRecovery: "Restore"
        case .deleteDatabase: "Delete"
        case .evictLocalCopy: "Evict local copy"
        case .optimizeStorage: "Optimize storage"
        case .captureConflict: "Capture conflict"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .deleteDatabase, .evictLocalCopy, .optimizeStorage: true
        default: false
        }
    }
}

enum A9PreflightDisposition: String, Codable, Sendable {
    case proceed
    case review
    case stopRecommended

    var title: String {
        switch self {
        case .proceed: "PROCEED"
        case .review: "REVIEW"
        case .stopRecommended: "STOP RECOMMENDED"
        }
    }
}

struct SchemaFingerprint: Codable, Hashable, Sendable {
    let digest: String
    let objectCount: Int
    let userVersion: Int
    let sampledAt: Date

    var shortDigest: String { String(digest.prefix(12)) }
}

struct A9PreflightResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let action: A9LifecycleAction
    let disposition: A9PreflightDisposition
    let decisionColor: A9HealthColor?
    let stateNumber: Int?
    let riskPoints: Int
    let requiresRecovery: Bool
    let schemaDriftDetected: Bool
    let summary: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        action: A9LifecycleAction,
        disposition: A9PreflightDisposition,
        decisionColor: A9HealthColor?,
        stateNumber: Int?,
        riskPoints: Int,
        requiresRecovery: Bool,
        schemaDriftDetected: Bool,
        summary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.fileName = fileName
        self.action = action
        self.disposition = disposition
        self.decisionColor = decisionColor
        self.stateNumber = stateNumber
        self.riskPoints = riskPoints
        self.requiresRecovery = requiresRecovery
        self.schemaDriftDetected = schemaDriftDetected
        self.summary = summary
        self.createdAt = createdAt
    }
}

struct A9HealthHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let color: A9HealthColor
    let priority: A9Priority
    let level: A9Level
    let stateNumber: Int
    let riskPoints: Int
    let scanDepth: A9ScanDepth
    let schemaFingerprint: SchemaFingerprint?
    let trigger: String
    let sampledAt: Date

    init(
        id: UUID = UUID(),
        decision: A9Decision,
        schemaFingerprint: SchemaFingerprint?,
        trigger: String
    ) {
        self.id = id
        self.fileName = decision.fileName
        self.color = decision.color
        self.priority = decision.priority
        self.level = decision.level
        self.stateNumber = decision.stateNumber
        self.riskPoints = decision.riskPoints
        self.scanDepth = decision.scanDepth
        self.schemaFingerprint = schemaFingerprint
        self.trigger = trigger
        self.sampledAt = decision.sampledAt
    }
}

struct A9LifecycleEnvelope: Codable, Sendable {
    var schemaVersion: Int = 1
    var history: [A9HealthHistoryEntry] = []
    var preflights: [A9PreflightResult] = []
    var fingerprints: [String: SchemaFingerprint] = [:]
}

enum DatabaseLifecyclePhase: String, Codable, Sendable {
    case cloudOnly
    case downloading
    case validating
    case ready
    case active
    case conflict

    var title: String {
        switch self {
        case .cloudOnly: "Cloud only"
        case .downloading: "Downloading"
        case .validating: "Validating"
        case .ready: "Ready"
        case .active: "Active"
        case .conflict: "Conflict"
        }
    }

    var systemImage: String {
        switch self {
        case .cloudOnly: "icloud"
        case .downloading: "icloud.and.arrow.down"
        case .validating: "checkmark.shield"
        case .ready: "checkmark.circle"
        case .active: "bolt.circle.fill"
        case .conflict: "exclamationmark.icloud.fill"
        }
    }
}
