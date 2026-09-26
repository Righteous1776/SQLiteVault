import Foundation

struct SchemaObject: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case table
        case view
        case index
        case trigger
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let tableName: String?
    let sql: String?
}

struct TableColumn: Identifiable, Hashable, Sendable {
    let id = UUID()
    let cid: Int
    let name: String
    let declaredType: String
    let notNull: Bool
    let defaultValue: String?
    let primaryKeyPosition: Int
}

struct QueryResult: Sendable {
    let columns: [String]
    let rows: [[String?]]
    let elapsedMilliseconds: Double
    let truncated: Bool
}
