import Foundation

actor VaultCatalogStore {
    private let vault = ICloudVault()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() async throws -> VaultCatalog {
        let url = try await vault.catalogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }

        var coordinationError: NSError?
        var payload: Data?
        var readError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do { payload = try Data(contentsOf: coordinatedURL) }
            catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let payload else { return .empty }
        return try decoder.decode(VaultCatalog.self, from: payload)
    }

    func save(_ catalog: VaultCatalog) async throws {
        let url = try await vault.catalogURL()
        let data = try encoder.encode(catalog)
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        let options: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path) ? .forReplacing : []
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do { try data.write(to: coordinatedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
