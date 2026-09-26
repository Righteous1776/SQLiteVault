import Foundation

struct VaultWorkspace: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var databaseFileNames: [String]
    var category: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        databaseFileNames: [String] = [],
        category: String? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.databaseFileNames = Array(Set(databaseFileNames)).sorted()
        let normalizedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = normalizedCategory?.isEmpty == true ? nil : normalizedCategory
        self.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct VaultCatalog: Hashable, Codable, Sendable {
    var schemaVersion: Int
    var workspaces: [VaultWorkspace]
    var assetMetadata: [String: DatabaseMetadata]
    var updatedAt: Date

    static let empty = VaultCatalog(schemaVersion: 2, workspaces: [], assetMetadata: [:], updatedAt: .now)
}

struct VaultPluginManifest: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var version: String
    var requiredTables: [String]
    var readOnlyQueries: [String: String]
}
