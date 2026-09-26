import Foundation

struct DatabaseAsset: Identifiable, Hashable, Codable, Sendable {
    var id: String { fileName }

    var name: String
    var fileName: String
    var fileURL: URL
    var sizeBytes: Int64
    var modifiedAt: Date
    var location: StorageLocation
    var schemaSummary: SchemaSummary?

    enum StorageLocation: String, Codable, Sendable {
        case iCloud
        case localFallback
    }
}

struct DatabaseMetadata: Hashable, Codable, Sendable {
    var category: String?
    var tags: [String]
    var isFavorite: Bool

    static let empty = DatabaseMetadata(category: nil, tags: [], isFavorite: false)

    init(category: String? = nil, tags: [String] = [], isFavorite: Bool = false) {
        self.category = category?.nilIfBlank
        self.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        self.isFavorite = isFavorite
    }
}

struct SchemaSummary: Hashable, Codable, Sendable {
    let tableCount: Int
    let viewCount: Int
    let indexCount: Int
    let triggerCount: Int
    let userVersion: Int
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
