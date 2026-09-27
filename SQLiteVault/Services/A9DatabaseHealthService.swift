import Foundation

actor A9DatabaseHealthService {
    private let fileManager = FileManager.default
    private var persistence: A9PersistenceEnvelope

    init() {
        persistence = Self.loadPersistence()
    }

    func scan(
        asset: DatabaseAsset,
        cloudFile: ICloudFileStatus?,
        preparation: DatabasePreparationStatus,
        depth: A9ScanDepth,
        schemaDriftDetected: Bool = false
    ) -> A9Decision {
        var signals: [A9Signal] = []

        if let cloudFile, cloudFile.hasUnresolvedConflicts {
            signals.append(A9Signal(
                id: "icloud-conflict",
                title: "Unresolved iCloud conflict",
                detail: "Multiple unresolved file versions exist. Capture them into Recovery before choosing a winner.",
                riskPoints: 24,
                priority: .p1,
                blocker: true,
                source: "iCloud"
            ))
        }

        if schemaDriftDetected {
            signals.append(A9Signal(
                id: "schema-fingerprint-drift",
                title: "Schema fingerprint changed",
                detail: "The canonical sqlite_schema fingerprint differs from the previous trusted sample.",
                riskPoints: 12,
                priority: .p2,
                source: "Schema"
            ))
        }

        if preparation.phase == .failed {
            signals.append(A9Signal(
                id: "preparation-failed",
                title: "Database preparation failed",
                detail: preparation.message.isEmpty ? "The most recent download or verification pass failed." : preparation.message,
                riskPoints: 18,
                priority: .p1,
                source: "Preparation"
            ))
        }

        if !asset.isLocallyAvailable {
            signals.append(A9Signal(
                id: "cloud-only",
                title: "Deep inspection deferred",
                detail: "The SQLite file is currently cloud-only. A9 can observe cloud state, but file-level checks require a local copy.",
                riskPoints: 0,
                priority: .p3,
                source: "Availability"
            ))
            return makeDecision(fileName: asset.fileName, signals: signals, depth: depth)
        }

        if asset.sizeBytes <= 0 {
            signals.append(A9Signal(
                id: "empty-file",
                title: "Empty database file",
                detail: "The selected database reports zero bytes.",
                riskPoints: 70,
                priority: .p0,
                blocker: true,
                source: "File"
            ))
            return makeDecision(fileName: asset.fileName, signals: signals, depth: depth)
        }

        do {
            let header = try sqliteHeader(at: asset.fileURL)
            if header != "SQLite format 3\0" {
                signals.append(A9Signal(
                    id: "sqlite-header",
                    title: "Invalid SQLite header",
                    detail: "The file does not begin with the canonical SQLite format header.",
                    riskPoints: 80,
                    priority: .p0,
                    blocker: true,
                    source: "SQLite"
                ))
                return makeDecision(fileName: asset.fileName, signals: signals, depth: depth)
            }
        } catch {
            signals.append(A9Signal(
                id: "file-read",
                title: "Database file cannot be read",
                detail: error.localizedDescription,
                riskPoints: 55,
                priority: .p0,
                blocker: true,
                source: "File"
            ))
            return makeDecision(fileName: asset.fileName, signals: signals, depth: depth)
        }

        if depth == .deep {
            do {
                let db = try SQLiteDatabase(url: asset.fileURL)
                let integrity = try db.integrityCheck()
                if integrity.lowercased() != "ok" {
                    signals.append(A9Signal(
                        id: "integrity-check",
                        title: "SQLite integrity check failed",
                        detail: integrity,
                        riskPoints: 68,
                        priority: .p0,
                        blocker: true,
                        source: "SQLite"
                    ))
                }

                let foreignKeyViolations = try db.foreignKeyViolationCount(limit: 10_000)
                if foreignKeyViolations > 0 {
                    signals.append(A9Signal(
                        id: "foreign-key",
                        title: "Foreign-key violations",
                        detail: "SQLite reported \(foreignKeyViolations) foreign-key violation(s).",
                        riskPoints: min(26, 10 + foreignKeyViolations),
                        priority: .p1,
                        source: "SQLite"
                    ))
                }
            } catch {
                signals.append(A9Signal(
                    id: "deep-scan-error",
                    title: "Deep database scan failed",
                    detail: error.localizedDescription,
                    riskPoints: 34,
                    priority: .p0,
                    blocker: true,
                    source: "SQLite"
                ))
            }
        }

        return makeDecision(fileName: asset.fileName, signals: signals, depth: depth)
    }

    func scanImportSource(url: URL) -> A9Decision {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        let temporaryKey = "__import__::\(UUID().uuidString)"
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let asset = DatabaseAsset(
            name: url.deletingPathExtension().lastPathComponent,
            fileName: temporaryKey,
            fileURL: url,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .now,
            location: .localFallback,
            schemaSummary: nil,
            localAvailability: .available
        )
        let raw = scan(
            asset: asset,
            cloudFile: nil,
            preparation: .idle,
            depth: .deep,
            schemaDriftDetected: false
        )
        persistence.records.removeValue(forKey: temporaryKey)
        savePersistence()
        return A9Decision(
            fileName: url.lastPathComponent,
            color: raw.color,
            priority: raw.priority,
            level: raw.level,
            riskPoints: raw.riskPoints,
            persistent: raw.persistent,
            blocker: raw.blocker,
            redLatched: raw.redLatched,
            stateIndex: raw.stateIndex,
            scanDepth: raw.scanDepth,
            sampledAt: raw.sampledAt,
            signals: raw.signals,
            summary: raw.summary,
            recommendation: raw.recommendation
        )
    }

    func acknowledgeRedLatch(fileName: String) {
        var record = persistence.records[fileName] ?? A9PersistenceRecord()
        record.redLatched = false
        record.yellowStreak = 0
        persistence.records[fileName] = record
        savePersistence()
    }

    func forget(fileName: String) {
        persistence.records.removeValue(forKey: fileName)
        savePersistence()
    }

    private func makeDecision(fileName: String, signals initialSignals: [A9Signal], depth: A9ScanDepth) -> A9Decision {
        var signals = initialSignals
        let rawRisk = min(100, signals.reduce(0) { $0 + $1.riskPoints })
        let blocker = signals.contains(where: \.blocker)
        let effectiveSignals = signals.filter { $0.riskPoints > 0 || $0.blocker }
        let priority = effectiveSignals.map(\.priority).min() ?? .p3

        let rawColor: A9HealthColor
        if blocker || priority == .p0 || rawRisk >= A9Lattice.redRiskThreshold {
            rawColor = .red
        } else if rawRisk > 0 {
            rawColor = .yellow
        } else {
            rawColor = .green
        }

        var record = persistence.records[fileName] ?? A9PersistenceRecord()
        switch rawColor {
        case .yellow:
            record.yellowStreak += 1
        case .red:
            record.yellowStreak = 0
            record.redLatched = true
        case .green:
            record.yellowStreak = 0
        }
        persistence.records[fileName] = record
        savePersistence()

        if record.redLatched, rawColor != .red {
            signals.append(A9Signal(
                id: "red-latch",
                title: "RED latch is still active",
                detail: "A9 does not clear a previous RED state automatically. Review the database, then acknowledge the latch explicitly.",
                riskPoints: 0,
                priority: .p1,
                source: "A9"
            ))
        }

        let finalColor: A9HealthColor = record.redLatched ? .red : rawColor
        let persistent = record.yellowStreak >= A9Lattice.persistentYellowThreshold || record.redLatched || blocker
        let risk = record.redLatched ? max(rawRisk, A9Lattice.redRiskThreshold) : rawRisk
        let level = A9Lattice.arbitrationLevel(color: finalColor, priority: priority, blocker: blocker, persistent: persistent)
        let stateIndex = A9Lattice.stateIndex(color: finalColor, priority: priority, level: level, persistentOrBlocker: persistent || blocker)
        let text = summary(color: finalColor, priority: priority, level: level, blocker: blocker, signals: signals)

        return A9Decision(
            fileName: fileName,
            color: finalColor,
            priority: priority,
            level: level,
            riskPoints: risk,
            persistent: persistent,
            blocker: blocker,
            redLatched: record.redLatched,
            stateIndex: stateIndex,
            scanDepth: depth,
            sampledAt: .now,
            signals: signals,
            summary: text.summary,
            recommendation: text.recommendation
        )
    }

    private func summary(
        color: A9HealthColor,
        priority: A9Priority,
        level: A9Level,
        blocker: Bool,
        signals: [A9Signal]
    ) -> (summary: String, recommendation: String) {
        switch color {
        case .green:
            return (
                "No actionable database-health fault was detected by this A9 pass.",
                "Continue normal read-only inspection. Run a Deep scan after imports, restores, or suspected corruption."
            )
        case .yellow:
            return (
                "A9 detected advisory database-health signals that deserve review.",
                priority == .p1 || level.rawValue >= A9Level.l2.rawValue
                    ? "Review the listed signals before relying on this database for critical work. A9 will not modify the source file."
                    : "Monitor the signal and run a Deep scan if it persists."
            )
        case .red:
            return (
                blocker ? "A9 detected a blocker or critical database-health condition." : "A9 risk crossed the RED arbitration threshold.",
                "Stop write-side workflows outside SQLite Vault, preserve a Recovery copy, investigate the listed signals, and acknowledge the RED latch only after the condition is understood."
            )
        }
    }

    private func sqliteHeader(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 16) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func stateURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SQLiteVaultA9", isDirectory: true)
            .appendingPathComponent("state-v1.json")
    }

    private static func loadPersistence() -> A9PersistenceEnvelope {
        guard let url = stateURL(), let data = try? Data(contentsOf: url) else { return A9PersistenceEnvelope() }
        return (try? JSONDecoder().decode(A9PersistenceEnvelope.self, from: data)) ?? A9PersistenceEnvelope()
    }

    private func savePersistence() {
        guard let url = Self.stateURL() else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(persistence).write(to: url, options: [.atomic])
        } catch {
            // Advisory state persistence must never block database access.
        }
    }
}
