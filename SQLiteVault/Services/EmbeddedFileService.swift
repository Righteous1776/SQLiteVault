import Foundation
import SQLite3

struct EmbeddedFileService: Sendable {
    enum EmbeddedFileError: LocalizedError {
        case open(String)
        case prepare(String)
        case blobUnavailable

        var errorDescription: String? {
            switch self {
            case .open(let message): "Unable to open SQLite file: \(message)"
            case .prepare(let message): "Unable to inspect embedded files: \(message)"
            case .blobUnavailable: "The selected embedded file is no longer available."
            }
        }
    }

    private struct ColumnInfo {
        let name: String
        let declaredType: String
        let primaryKeyOrder: Int
    }

    func scan(database: DatabaseAsset, perColumnLimit: Int = 5_000) throws -> [EmbeddedBinaryAsset] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.fileURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw EmbeddedFileError.open(message)
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 2_000)

        let tables = try tableNames(handle: handle)
        var results: [EmbeddedBinaryAsset] = []

        for table in tables {
            let columns = try columns(handle: handle, table: table)
            let blobCandidates = columns.filter { column in
                let type = column.declaredType.uppercased()
                let name = column.name.lowercased()
                return type.contains("BLOB") || ["blob", "data", "content", "binary", "attachment", "document", "file", "body"].contains { name.contains($0) }
            }
            guard !blobCandidates.isEmpty else { continue }

            let filenameCandidates = columns.filter { column in
                let name = column.name.lowercased()
                let type = column.declaredType.uppercased()
                let nameMatch = ["filename", "file_name", "name", "path", "title", "original_name", "document_name", "attachment_name", "mime", "type"].contains { name.contains($0) }
                return nameMatch && !type.contains("BLOB")
            }.prefix(6)

            for blobColumn in blobCandidates {
                let scanned = try scanColumn(
                    handle: handle,
                    database: database,
                    table: table,
                    blobColumn: blobColumn,
                    filenameCandidates: Array(filenameCandidates),
                    allColumns: columns,
                    limit: perColumnLimit
                )
                results.append(contentsOf: scanned)
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.databaseFileName != rhs.databaseFileName { return lhs.databaseFileName.localizedStandardCompare(rhs.databaseFileName) == .orderedAscending }
            return lhs.inferredFileName.localizedStandardCompare(rhs.inferredFileName) == .orderedAscending
        }
    }

    func materialize(_ asset: EmbeddedBinaryAsset, from database: DatabaseAsset) throws -> URL {
        let data = try loadData(asset, from: database)
        let finalKind = EmbeddedFileDetector.detect(data: data, fileName: asset.inferredFileName)
        let fileName = EmbeddedFileDetector.normalizedFileName(asset.inferredFileName, kind: finalKind)

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteVaultExtracted", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func loadData(_ asset: EmbeddedBinaryAsset, from database: DatabaseAsset) throws -> Data {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.fileURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw EmbeddedFileError.open(message)
        }
        defer { sqlite3_close(handle) }

        let table = quoteIdentifier(asset.tableName)
        let column = quoteIdentifier(asset.columnName)
        let predicate: String
        switch asset.locator {
        case .rowID(let rowID):
            predicate = "rowid = \(rowID)"
        case .primaryKey(let keyColumn, let literal):
            predicate = "\(quoteIdentifier(keyColumn)) = \(literal)"
        }

        let sql = "SELECT \(column) FROM \(table) WHERE \(predicate) LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EmbeddedFileError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, 0) else {
            throw EmbeddedFileError.blobUnavailable
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    private func tableNames(handle: OpaquePointer) throws -> [String] {
        let sql = "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EmbeddedFileError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { names.append(String(cString: text)) }
        }
        return names
    }

    private func columns(handle: OpaquePointer, table: String) throws -> [ColumnInfo] {
        let sql = "PRAGMA table_info(\(quoteIdentifier(table)))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EmbeddedFileError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var values: [ColumnInfo] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let type = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let pk = Int(sqlite3_column_int(statement, 5))
            values.append(ColumnInfo(name: name, declaredType: type, primaryKeyOrder: pk))
        }
        return values
    }

    private func scanColumn(
        handle: OpaquePointer,
        database: DatabaseAsset,
        table: String,
        blobColumn: ColumnInfo,
        filenameCandidates: [ColumnInfo],
        allColumns: [ColumnInfo],
        limit: Int
    ) throws -> [EmbeddedBinaryAsset] {
        let rowIDSQL = "rowid"
        let candidateSQL = filenameCandidates.map { quoteIdentifier($0.name) }.joined(separator: ", ")
        let extras = candidateSQL.isEmpty ? "" : ", \(candidateSQL)"
        let blob = quoteIdentifier(blobColumn.name)
        let tableSQL = quoteIdentifier(table)
        let sql = "SELECT \(rowIDSQL), length(\(blob)), substr(\(blob),1,4096), substr(\(blob),-65536)\(extras) FROM \(tableSQL) WHERE typeof(\(blob))='blob' AND length(\(blob)) > 0 LIMIT \(max(1, limit))"

        do {
            return try executeScan(
                handle: handle,
                sql: sql,
                database: database,
                table: table,
                blobColumn: blobColumn.name,
                filenameCandidates: filenameCandidates,
                locatorBuilder: { statement in .rowID(sqlite3_column_int64(statement, 0)) }
            )
        } catch {
            let primaryKeys = allColumns.filter { $0.primaryKeyOrder > 0 }.sorted { $0.primaryKeyOrder < $1.primaryKeyOrder }
            guard primaryKeys.count == 1 else { return [] }
            let primaryKey = primaryKeys[0]
            let pk = quoteIdentifier(primaryKey.name)
            let fallbackSQL = "SELECT quote(\(pk)), length(\(blob)), substr(\(blob),1,4096), substr(\(blob),-65536)\(extras) FROM \(tableSQL) WHERE typeof(\(blob))='blob' AND length(\(blob)) > 0 LIMIT \(max(1, limit))"
            return try executeScan(
                handle: handle,
                sql: fallbackSQL,
                database: database,
                table: table,
                blobColumn: blobColumn.name,
                filenameCandidates: filenameCandidates,
                locatorBuilder: { statement in
                    let literal = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "NULL"
                    return .primaryKey(column: primaryKey.name, sqlLiteral: literal)
                }
            )
        }
    }

    private func executeScan(
        handle: OpaquePointer,
        sql: String,
        database: DatabaseAsset,
        table: String,
        blobColumn: String,
        filenameCandidates: [ColumnInfo],
        locatorBuilder: (OpaquePointer?) -> EmbeddedRowLocator
    ) throws -> [EmbeddedBinaryAsset] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EmbeddedFileError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        var results: [EmbeddedBinaryAsset] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw EmbeddedFileError.prepare(String(cString: sqlite3_errmsg(handle)))
            }

            let byteCount = sqlite3_column_int64(statement, 1)
            let head = data(statement: statement, index: 2)
            let tail = data(statement: statement, index: 3)
            let hint = filenameHint(statement: statement, startIndex: 4, candidates: filenameCandidates)
            let kind = EmbeddedFileDetector.detect(head: head, tail: tail, fileName: hint)
            let locator = locatorBuilder(statement)
            let fallbackSuffix: String
            switch locator {
            case .rowID(let value): fallbackSuffix = "rowid_\(value)"
            case .primaryKey(let column, let literal):
                let compact = literal.replacingOccurrences(of: "'", with: "").prefix(32)
                fallbackSuffix = "\(column)_\(compact)"
            }
            let fallbackBase = "\(table)_\(blobColumn)_\(fallbackSuffix)"
            let fileName = EmbeddedFileDetector.normalizedFileName(hint ?? fallbackBase, kind: kind)

            results.append(EmbeddedBinaryAsset(
                databaseFileName: database.fileName,
                tableName: table,
                columnName: blobColumn,
                locator: locator,
                byteCount: byteCount,
                inferredFileName: fileName,
                kind: kind
            ))
        }
        return results
    }

    private func filenameHint(statement: OpaquePointer?, startIndex: Int32, candidates: [ColumnInfo]) -> String? {
        var fallback: String?
        for offset in candidates.indices {
            let index = startIndex + Int32(offset)
            guard sqlite3_column_type(statement, index) == SQLITE_TEXT,
                  let raw = sqlite3_column_text(statement, index) else { continue }
            let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 512 else { continue }
            let columnName = candidates[offset].name.lowercased()
            if columnName.contains("filename") || columnName.contains("file_name") || columnName.contains("path") || columnName.contains("original_name") || columnName.contains("document_name") || columnName.contains("attachment_name") {
                return value
            }
            if fallback == nil, columnName == "name" || columnName.contains("title") { fallback = value }
        }
        return fallback
    }

    private func data(statement: OpaquePointer?, index: Int32) -> Data {
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum EmbeddedFileDetector {
    static func detect(data: Data, fileName: String?) -> EmbeddedFileKind {
        detect(head: data.prefix(4096), tail: data.suffix(65536), fileName: fileName)
    }

    static func detect(head: Data, tail: Data, fileName: String?) -> EmbeddedFileKind {
        let extensionHint = URL(fileURLWithPath: fileName ?? "").pathExtension.lowercased()
        if let byExtension = kind(forExtension: extensionHint), byExtension != .genericBinary { return byExtension }

        let prefix = [UInt8](head.prefix(16))
        if prefix.starts(with: Array("%PDF-".utf8)) { return .pdf }
        if prefix.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if prefix.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if prefix.starts(with: Array("GIF87a".utf8)) || prefix.starts(with: Array("GIF89a".utf8)) { return .gif }
        if prefix.starts(with: [0x49, 0x49, 0x2A, 0x00]) || prefix.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if prefix.starts(with: Array("{\\rtf".utf8)) { return .richText }
        if prefix.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return .wordLegacy }
        if prefix.starts(with: [0x50, 0x4B, 0x03, 0x04]) || prefix.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            let names = String(decoding: tail, as: UTF8.self).lowercased()
            if names.contains("word/document.xml") || names.contains("word/") { return .wordOpenXML }
            if names.contains("xl/workbook.xml") || names.contains("xl/") { return .excelOpenXML }
            if names.contains("ppt/presentation.xml") || names.contains("ppt/") { return .powerpointOpenXML }
            return .zip
        }
        if prefix.count >= 12 {
            let ascii = String(decoding: prefix, as: UTF8.self)
            if ascii.contains("ftypheic") || ascii.contains("ftypheix") || ascii.contains("ftyphevc") || ascii.contains("ftypmif1") { return .heic }
        }
        return .genericBinary
    }

    static func normalizedFileName(_ raw: String, kind: EmbeddedFileKind) -> String {
        var value = raw.replacingOccurrences(of: "\\", with: "/")
        value = value.split(separator: "/").last.map(String.init) ?? value
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        value = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "_")
        if value.isEmpty { value = "embedded_file" }
        if URL(fileURLWithPath: value).pathExtension.isEmpty {
            value += ".\(kind.preferredExtension)"
        }
        return String(value.prefix(180))
    }

    private static func kind(forExtension ext: String) -> EmbeddedFileKind? {
        switch ext {
        case "pdf": .pdf
        case "docx": .wordOpenXML
        case "doc": .wordLegacy
        case "xlsx": .excelOpenXML
        case "pptx": .powerpointOpenXML
        case "rtf": .richText
        case "txt", "md", "csv", "json", "xml": .plainText
        case "png": .png
        case "jpg", "jpeg": .jpeg
        case "gif": .gif
        case "tif", "tiff": .tiff
        case "heic", "heif": .heic
        case "zip": .zip
        default: nil
        }
    }
}
