import Foundation

enum GlobalSearchHitKind: String, Codable, Sendable {
    case database
    case schema
    case row
}

struct GlobalSearchHit: Identifiable, Hashable, Sendable {
    let id: UUID
    let databaseFileName: String
    let databaseName: String
    let kind: GlobalSearchHitKind
    let objectName: String?
    let columnName: String?
    let preview: String

    init(
        id: UUID = UUID(),
        databaseFileName: String,
        databaseName: String,
        kind: GlobalSearchHitKind,
        objectName: String? = nil,
        columnName: String? = nil,
        preview: String
    ) {
        self.id = id
        self.databaseFileName = databaseFileName
        self.databaseName = databaseName
        self.kind = kind
        self.objectName = objectName
        self.columnName = columnName
        self.preview = preview
    }
}
