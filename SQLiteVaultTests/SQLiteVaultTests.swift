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

extension SQLiteVaultTests {
    func testICloudStatusAggregatesTransfersAndConflicts() {
        let files = [
            ICloudFileStatus(
                fileName: "a.sqlite",
                fileURL: URL(fileURLWithPath: "/tmp/a.sqlite"),
                sizeBytes: 100,
                modifiedAt: .now,
                isDownloaded: true,
                isUploaded: true,
                isDownloading: false,
                isUploading: false,
                percentDownloaded: 100,
                percentUploaded: 100,
                hasUnresolvedConflicts: false,
                transferState: .current
            ),
            ICloudFileStatus(
                fileName: "b.sqlite",
                fileURL: URL(fileURLWithPath: "/tmp/b.sqlite"),
                sizeBytes: 200,
                modifiedAt: .now,
                isDownloaded: false,
                isUploaded: true,
                isDownloading: true,
                isUploading: false,
                percentDownloaded: 35,
                percentUploaded: 100,
                hasUnresolvedConflicts: true,
                transferState: .conflict
            )
        ]
        let status = ICloudVaultStatus(
            connection: .connected,
            containerIdentifier: "iCloud.com.zeostudio.SQLiteVault",
            containerPath: "/tmp/Documents",
            cloudFiles: files,
            localFallbackFileCount: 1,
            localFallbackBytes: 50,
            lastCheckedAt: .now,
            detail: "Connected"
        )
        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.cloudFileCount, 2)
        XCTAssertEqual(status.cloudBytes, 300)
        XCTAssertEqual(status.filesNeedingDownload, 1)
        XCTAssertEqual(status.activeTransfers, 1)
        XCTAssertEqual(status.conflictCount, 1)
    }
}


extension SQLiteVaultTests {
    func testOptimizedStorageModeRoundTrip() throws {
        let data = try JSONEncoder().encode(OptimizedStorageMode.optimized)
        XCTAssertEqual(try JSONDecoder().decode(OptimizedStorageMode.self, from: data), .optimized)
    }

    func testDatabaseMetadataPersistsRetentionAndLastOpened() throws {
        let opened = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = DatabaseMetadata(
            category: "Novel",
            tags: ["canonical"],
            isFavorite: false,
            retentionPolicy: .keepDownloaded,
            lastOpenedAt: opened
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(DatabaseMetadata.self, from: data)
        XCTAssertEqual(decoded.retentionPolicy, .keepDownloaded)
        XCTAssertEqual(decoded.lastOpenedAt, opened)
    }

    func testRemoteOnlyAssetIsNotLocallyAvailable() {
        let asset = DatabaseAsset(
            name: "Cloud",
            fileName: "cloud.sqlite",
            fileURL: URL(fileURLWithPath: "/tmp/cloud.sqlite"),
            sizeBytes: 100,
            modifiedAt: .now,
            location: .iCloud,
            schemaSummary: nil,
            localAvailability: .remoteOnly
        )
        XCTAssertFalse(asset.isLocallyAvailable)
    }
}

extension SQLiteVaultTests {
    func testAutomaticCacheBudgetIsBounded() {
        let gib: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(CacheBudgetPreset.automatic.byteLimit(totalDeviceBytes: 16 * gib), 2 * gib)
        XCTAssertEqual(CacheBudgetPreset.automatic.byteLimit(totalDeviceBytes: 256 * gib), 12 * gib)
        XCTAssertNil(CacheBudgetPreset.unlimited.byteLimit(totalDeviceBytes: 256 * gib))
    }

    func testDatabasePreparationRunningPhases() {
        XCTAssertTrue(DatabasePreparationStatus(phase: .downloading, progress: 0.4, message: "", updatedAt: .now).isRunning)
        XCTAssertTrue(DatabasePreparationStatus(phase: .integrityCheck, progress: 0.9, message: "", updatedAt: .now).isRunning)
        XCTAssertFalse(DatabasePreparationStatus(phase: .ready, progress: 1, message: "", updatedAt: .now).isRunning)
        XCTAssertFalse(DatabasePreparationStatus(phase: .failed, progress: 0, message: "", updatedAt: .now).isRunning)
    }

    func testRecoveryPointRoundTrip() throws {
        let point = RecoveryPoint(
            id: UUID(),
            fileName: "canonical.sqlite",
            reason: "Before deletion",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sizeBytes: 1234,
            snapshotFileName: "snapshot.sqlite"
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(RecoveryPoint.self, from: data)
        XCTAssertEqual(decoded.fileName, point.fileName)
        XCTAssertEqual(decoded.reason, "Before deletion")
        XCTAssertEqual(decoded.sizeBytes, 1234)
    }
}

extension SQLiteVaultTests {
    func testA9LatticeHasExactly144UniqueStates() {
        var states = Set<Int>()
        for color in A9HealthColor.allCases {
            for priority in A9Priority.allCases {
                for level in A9Level.allCases {
                    for persistent in [false, true] {
                        states.insert(A9Lattice.stateIndex(
                            color: color,
                            priority: priority,
                            level: level,
                            persistentOrBlocker: persistent
                        ))
                    }
                }
            }
        }
        XCTAssertEqual(states.count, 144)
        XCTAssertEqual(states.min(), 0)
        XCTAssertEqual(states.max(), 143)
    }

    func testA9ArbitrationRules() {
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .green, priority: .p3, blocker: false, persistent: false), .l0)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .yellow, priority: .p2, blocker: false, persistent: false), .l1)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .yellow, priority: .p1, blocker: false, persistent: false), .l2)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .yellow, priority: .p2, blocker: false, persistent: true), .l2)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .red, priority: .p2, blocker: false, persistent: false), .l3)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .red, priority: .p1, blocker: true, persistent: true), .l4)
        XCTAssertEqual(A9Lattice.arbitrationLevel(color: .red, priority: .p0, blocker: true, persistent: true), .l5)
    }

    func testA9CanonicalThresholds() {
        XCTAssertEqual(A9Lattice.persistentYellowThreshold, 3)
        XCTAssertEqual(A9Lattice.redRiskThreshold, 28)
    }
}

extension SQLiteVaultTests {
    func testA9LifecycleActionDestructiveClassification() {
        XCTAssertTrue(A9LifecycleAction.deleteDatabase.isDestructive)
        XCTAssertTrue(A9LifecycleAction.evictLocalCopy.isDestructive)
        XCTAssertTrue(A9LifecycleAction.optimizeStorage.isDestructive)
        XCTAssertFalse(A9LifecycleAction.importDatabase.isDestructive)
        XCTAssertFalse(A9LifecycleAction.prepareForOpen.isDestructive)
        XCTAssertFalse(A9LifecycleAction.restoreRecovery.isDestructive)
    }

    func testA9PreflightRoundTrip() throws {
        let result = A9PreflightResult(
            fileName: "canonical.sqlite",
            action: .deleteDatabase,
            disposition: .review,
            decisionColor: .yellow,
            stateNumber: 73,
            riskPoints: 12,
            requiresRecovery: true,
            schemaDriftDetected: true,
            summary: "Review"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(A9PreflightResult.self, from: data)
        XCTAssertEqual(decoded.action, .deleteDatabase)
        XCTAssertEqual(decoded.disposition, .review)
        XCTAssertTrue(decoded.schemaDriftDetected)
        XCTAssertTrue(decoded.requiresRecovery)
    }

    func testRecoveryPointPersistsA9LifecycleMetadata() throws {
        let fingerprint = SchemaFingerprint(
            digest: String(repeating: "a", count: 64),
            objectCount: 14,
            userVersion: 7,
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let point = RecoveryPoint(
            id: UUID(),
            fileName: "canonical.sqlite",
            reason: "Before eviction",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            sizeBytes: 2048,
            snapshotFileName: "snapshot.sqlite",
            a9StateNumber: 101,
            a9Color: .red,
            schemaFingerprint: fingerprint
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(RecoveryPoint.self, from: data)
        XCTAssertEqual(decoded.a9StateNumber, 101)
        XCTAssertEqual(decoded.a9Color, .red)
        XCTAssertEqual(decoded.schemaFingerprint?.shortDigest, String(repeating: "a", count: 12))
    }

    func testDatabaseLifecyclePhaseLabels() {
        XCTAssertEqual(DatabaseLifecyclePhase.cloudOnly.title, "Cloud only")
        XCTAssertEqual(DatabaseLifecyclePhase.active.title, "Active")
        XCTAssertEqual(DatabaseLifecyclePhase.conflict.title, "Conflict")
    }
}
