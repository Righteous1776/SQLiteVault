import Foundation
import UniformTypeIdentifiers

enum EmbeddedFileKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pdf
    case wordOpenXML
    case wordLegacy
    case excelOpenXML
    case powerpointOpenXML
    case richText
    case plainText
    case png
    case jpeg
    case gif
    case tiff
    case heic
    case zip
    case genericBinary

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .wordOpenXML: "Word Document"
        case .wordLegacy: "Word Document (Legacy)"
        case .excelOpenXML: "Excel Workbook"
        case .powerpointOpenXML: "PowerPoint Presentation"
        case .richText: "Rich Text"
        case .plainText: "Text"
        case .png: "PNG Image"
        case .jpeg: "JPEG Image"
        case .gif: "GIF Image"
        case .tiff: "TIFF Image"
        case .heic: "HEIC Image"
        case .zip: "ZIP Archive"
        case .genericBinary: "Binary Data"
        }
    }

    var preferredExtension: String {
        switch self {
        case .pdf: "pdf"
        case .wordOpenXML: "docx"
        case .wordLegacy: "doc"
        case .excelOpenXML: "xlsx"
        case .powerpointOpenXML: "pptx"
        case .richText: "rtf"
        case .plainText: "txt"
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .tiff: "tiff"
        case .heic: "heic"
        case .zip: "zip"
        case .genericBinary: "bin"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext.fill"
        case .wordOpenXML, .wordLegacy: "doc.text.fill"
        case .excelOpenXML: "tablecells.fill"
        case .powerpointOpenXML: "rectangle.on.rectangle.angled"
        case .richText, .plainText: "doc.plaintext.fill"
        case .png, .jpeg, .gif, .tiff, .heic: "photo.fill"
        case .zip: "archivebox.fill"
        case .genericBinary: "shippingbox.fill"
        }
    }

    var uniformType: UTType {
        switch self {
        case .pdf: .pdf
        case .wordOpenXML: UTType(filenameExtension: "docx") ?? .data
        case .wordLegacy: UTType(filenameExtension: "doc") ?? .data
        case .excelOpenXML: UTType(filenameExtension: "xlsx") ?? .data
        case .powerpointOpenXML: UTType(filenameExtension: "pptx") ?? .data
        case .richText: .rtf
        case .plainText: .plainText
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .tiff: .tiff
        case .heic: .heic
        case .zip: .zip
        case .genericBinary: .data
        }
    }
}

enum EmbeddedRowLocator: Hashable, Codable, Sendable {
    case rowID(Int64)
    case primaryKey(column: String, sqlLiteral: String)
}

struct EmbeddedBinaryAsset: Identifiable, Hashable, Codable, Sendable {
    let databaseFileName: String
    let tableName: String
    let columnName: String
    let locator: EmbeddedRowLocator
    let byteCount: Int64
    let inferredFileName: String
    let kind: EmbeddedFileKind

    var id: String {
        "\(databaseFileName)|\(tableName)|\(columnName)|\(locator.descriptionKey)"
    }

    var locationDescription: String {
        "\(tableName).\(columnName)"
    }
}

private extension EmbeddedRowLocator {
    var descriptionKey: String {
        switch self {
        case .rowID(let value): "rowid:\(value)"
        case .primaryKey(let column, let literal): "pk:\(column):\(literal)"
        }
    }
}
