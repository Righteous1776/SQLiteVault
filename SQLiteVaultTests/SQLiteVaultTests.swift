import XCTest
@testable import SQLiteVault

final class SQLiteVaultTests: XCTestCase {
    func testWorkspaceManifestRoundTrip() throws {
        let original = VaultWorkspace(
            name: "Novel",
            databaseFileNames: ["canonical.sqlite", "audit.sqlite"],
            category: "Writing",
            tags: ["canonical", "novel"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VaultWorkspace.self, from: encoded)
        XCTAssertEqual(decoded.name, "Novel")
        XCTAssertEqual(decoded.databaseFileNames, ["audit.sqlite", "canonical.sqlite"])
        XCTAssertEqual(decoded.category, "Writing")
        XCTAssertEqual(decoded.tags, ["canonical", "novel"])
    }

    func testCatalogRoundTrip() throws {
        let workspace = VaultWorkspace(name: "Research", databaseFileNames: ["research.sqlite"])
        let catalog = VaultCatalog(
            schemaVersion: 2,
            workspaces: [workspace],
            assetMetadata: [
                "research.sqlite": DatabaseMetadata(category: "Study", tags: ["EJU", "physics"], isFavorite: true)
            ],
            updatedAt: .now
        )
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(VaultCatalog.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.workspaces.count, 1)
        XCTAssertEqual(decoded.assetMetadata["research.sqlite"]?.isFavorite, true)
    }

    func testDatabaseIdentityIsStableByFileName() {
        let asset = DatabaseAsset(
            name: "Canonical",
            fileName: "canonical.sqlite",
            fileURL: URL(fileURLWithPath: "/tmp/canonical.sqlite"),
            sizeBytes: 1,
            modifiedAt: .now,
            location: .localFallback,
            schemaSummary: nil
        )
        XCTAssertEqual(asset.id, "canonical.sqlite")
    }


    func testReadOnlyPolicyAllowsQueriesAndLeadingComments() throws {
        let policy = SQLReadOnlyPolicy()
        XCTAssertNoThrow(try policy.requireQueryOnly("SELECT * FROM chapters"))
        XCTAssertNoThrow(try policy.requireQueryOnly("  -- note\nWITH x AS (SELECT 1) SELECT * FROM x"))
        XCTAssertNoThrow(try policy.requireQueryOnly("/* inspect */ EXPLAIN QUERY PLAN SELECT 1"))
    }

    func testReadOnlyPolicyBlocksConnectionAndWriteControlStatements() {
        let policy = SQLReadOnlyPolicy()
        for sql in [
            "ATTACH DATABASE 'other.sqlite' AS other",
            "DETACH DATABASE db1",
            "PRAGMA writable_schema=ON",
            "BEGIN",
            "INSERT INTO t VALUES (1)",
            "UPDATE t SET a = 1",
            "DELETE FROM t"
        ] {
            XCTAssertThrowsError(try policy.requireQueryOnly(sql), "Expected policy to block: \(sql)")
        }
    }

    func testPluginManifestRoundTrip() throws {
        let manifest = VaultPluginManifest(
            id: "novel",
            name: "Novel Canonical",
            version: "1",
            requiredTables: ["chapters"],
            readOnlyQueries: ["frozen": "SELECT * FROM chapters WHERE status='FROZEN'"]
        )
        XCTAssertNoThrow(try JSONEncoder().encode(manifest))
    }
}

extension SQLiteVaultTests {
    func testEmbeddedFileDetectorRecognizesPDF() {
        let data = Data("%PDF-1.7\nfixture".utf8)
        XCTAssertEqual(EmbeddedFileDetector.detect(data: data, fileName: nil), .pdf)
        XCTAssertEqual(EmbeddedFileDetector.normalizedFileName("Novel Draft", kind: .pdf), "Novel Draft.pdf")
    }

    func testEmbeddedFileDetectorRecognizesDOCXFromContainerNames() {
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(Data(repeating: 0, count: 32))
        data.append(Data("word/document.xml".utf8))
        XCTAssertEqual(EmbeddedFileDetector.detect(data: data, fileName: nil), .wordOpenXML)
    }
}
