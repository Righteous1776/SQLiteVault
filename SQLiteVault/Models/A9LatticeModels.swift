import Foundation

enum A9HealthColor: String, CaseIterable, Codable, Sendable {
    case green
    case yellow
    case red

    var title: String { rawValue.uppercased() }
    var latticeIndex: Int {
        switch self {
        case .green: 0
        case .yellow: 1
        case .red: 2
        }
    }
}

enum A9Priority: Int, CaseIterable, Codable, Sendable, Comparable {
    case p0 = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3

    static func < (lhs: A9Priority, rhs: A9Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String { "P\(rawValue)" }
}

enum A9Level: Int, CaseIterable, Codable, Sendable {
    case l0 = 0
    case l1 = 1
    case l2 = 2
    case l3 = 3
    case l4 = 4
    case l5 = 5

    var title: String { "L\(rawValue)" }
}

enum A9ScanDepth: String, CaseIterable, Codable, Sendable {
    case fast
    case deep

    var title: String {
        switch self {
        case .fast: "Fast"
        case .deep: "Deep"
        }
    }
}

enum A9Lattice {
    static let stateCount = 144
    static let persistentYellowThreshold = 3
    static let redRiskThreshold = 28

    static func arbitrationLevel(
        color: A9HealthColor,
        priority: A9Priority,
        blocker: Bool,
        persistent: Bool
    ) -> A9Level {
        if priority == .p0 { return .l5 }
        if color == .red, blocker { return .l4 }
        if color == .red { return .l3 }
        if color == .yellow, priority == .p1 || persistent { return .l2 }
        if color == .yellow { return .l1 }
        return .l0
    }

    static func stateIndex(
        color: A9HealthColor,
        priority: A9Priority,
        level: A9Level,
        persistentOrBlocker: Bool
    ) -> Int {
        // 3 health colors × 4 priorities × 6 levels × 2 persistence/blocker states = 144.
        color.latticeIndex * 48
            + priority.rawValue * 12
            + level.rawValue * 2
            + (persistentOrBlocker ? 1 : 0)
    }
}

struct A9Signal: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let detail: String
    let riskPoints: Int
    let priority: A9Priority
    let blocker: Bool
    let source: String

    init(
        id: String,
        title: String,
        detail: String,
        riskPoints: Int,
        priority: A9Priority,
        blocker: Bool = false,
        source: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.riskPoints = max(0, riskPoints)
        self.priority = priority
        self.blocker = blocker
        self.source = source
    }
}

struct A9Decision: Identifiable, Hashable, Codable, Sendable {
    var id: String { fileName }

    let fileName: String
    let color: A9HealthColor
    let priority: A9Priority
    let level: A9Level
    let riskPoints: Int
    let persistent: Bool
    let blocker: Bool
    let redLatched: Bool
    let stateIndex: Int
    let scanDepth: A9ScanDepth
    let sampledAt: Date
    let signals: [A9Signal]
    let summary: String
    let recommendation: String

    /// Canonical A9 state number in the 144-state lattice (1...144).
    var stateNumber: Int { stateIndex + 1 }
    var healthScore: Int { max(0, 100 - min(riskPoints, 100)) }
}

struct A9PersistenceRecord: Codable, Hashable, Sendable {
    var yellowStreak: Int = 0
    var redLatched: Bool = false
}

struct A9PersistenceEnvelope: Codable, Sendable {
    var schemaVersion: Int = 1
    var records: [String: A9PersistenceRecord] = [:]
}
