import Foundation

enum ICloudConnectionState: String, Sendable {
    case checking
    case connected
    case signedOut
    case containerUnavailable
    case error

    var isConnected: Bool { self == .connected }
}

enum ICloudFileTransferState: String, Sendable {
    case current
    case downloading
    case uploading
    case remoteOnly
    case conflict
    case unknown
}

struct ICloudFileStatus: Identifiable, Hashable, Sendable {
    var id: String { fileName }

    let fileName: String
    let fileURL: URL
    let sizeBytes: Int64
    let modifiedAt: Date
    let isDownloaded: Bool
    let isUploaded: Bool
    let isDownloading: Bool
    let isUploading: Bool
    let percentDownloaded: Double
    let percentUploaded: Double
    let hasUnresolvedConflicts: Bool
    let transferState: ICloudFileTransferState
}

struct ICloudVaultStatus: Sendable {
    let connection: ICloudConnectionState
    let containerIdentifier: String
    let containerPath: String?
    let cloudFiles: [ICloudFileStatus]
    let localFallbackFileCount: Int
    let localFallbackBytes: Int64
    let lastCheckedAt: Date
    let detail: String

    static let checking = ICloudVaultStatus(
        connection: .checking,
        containerIdentifier: "iCloud.com.zeostudio.SQLiteVault",
        containerPath: nil,
        cloudFiles: [],
        localFallbackFileCount: 0,
        localFallbackBytes: 0,
        lastCheckedAt: .now,
        detail: "Checking iCloud…"
    )

    var isConnected: Bool { connection.isConnected }
    var cloudFileCount: Int { cloudFiles.count }
    var cloudBytes: Int64 { cloudFiles.reduce(0) { $0 + $1.sizeBytes } }
    var filesNeedingDownload: Int { cloudFiles.filter { !$0.isDownloaded }.count }
    var activeTransfers: Int { cloudFiles.filter { $0.isDownloading || $0.isUploading }.count }
    var conflictCount: Int { cloudFiles.filter(\.hasUnresolvedConflicts).count }
}
