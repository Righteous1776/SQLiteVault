import Foundation

actor A9LifecycleService {
    private let fileManager = FileManager.default
    private var envelope: A9LifecycleEnvelope

    init() {
        envelope = Self.load()
    }

    func snapshot() -> A9LifecycleEnvelope { envelope }

    func previousFingerprint(fileName: String) -> SchemaFingerprint? {
        envelope.fingerprints[fileName]
    }

    func recordDecision(
        _ decision: A9Decision,
        fingerprint: SchemaFingerprint?,
        trigger: String,
        updateTrustedFingerprint: Bool = true
    ) {
        let entry = A9HealthHistoryEntry(
            decision: decision,
            schemaFingerprint: fingerprint,
            trigger: trigger
        )
        envelope.history.insert(entry, at: 0)
        if envelope.history.count > 400 { envelope.history.removeLast(envelope.history.count - 400) }
        if updateTrustedFingerprint, let fingerprint { envelope.fingerprints[decision.fileName] = fingerprint }
        persist()
    }

    func recordPreflight(
        fileName: String,
        action: A9LifecycleAction,
        decision: A9Decision?,
        schemaDriftDetected: Bool,
        hasRecoveryPoint: Bool
    ) -> A9PreflightResult {
        let disposition: A9PreflightDisposition
        if decision?.color == .red || decision?.blocker == true {
            disposition = .stopRecommended
        } else if decision?.color == .yellow || schemaDriftDetected {
            disposition = .review
        } else {
            disposition = .proceed
        }

        let requiresRecovery = action.isDestructive
            && !hasRecoveryPoint
            && (decision?.color != .green || schemaDriftDetected)
        let summary: String
        if requiresRecovery {
            summary = "A recovery snapshot is required before this destructive lifecycle action."
        } else if disposition == .stopRecommended {
            summary = "A9 detected RED/blocker evidence. Preserve Recovery data and review the decision before continuing."
        } else if disposition == .review {
            summary = schemaDriftDetected
                ? "Schema fingerprint changed since the previous trusted sample. Review before continuing."
                : "A9 detected advisory signals that deserve review before this lifecycle action."
        } else {
            summary = "No A9 lifecycle warning was detected for this action."
        }

        let result = A9PreflightResult(
            fileName: fileName,
            action: action,
            disposition: disposition,
            decisionColor: decision?.color,
            stateNumber: decision?.stateNumber,
            riskPoints: decision?.riskPoints ?? 0,
            requiresRecovery: requiresRecovery,
            schemaDriftDetected: schemaDriftDetected,
            summary: summary
        )
        envelope.preflights.insert(result, at: 0)
        if envelope.preflights.count > 250 { envelope.preflights.removeLast(envelope.preflights.count - 250) }
        persist()
        return result
    }

    func forget(fileName: String) {
        envelope.fingerprints.removeValue(forKey: fileName)
        persist()
    }

    private static func url() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SQLiteVaultA9", isDirectory: true)
            .appendingPathComponent("lifecycle-v1.json")
    }

    private static func load() -> A9LifecycleEnvelope {
        guard let url = url(), let data = try? Data(contentsOf: url) else { return A9LifecycleEnvelope() }
        return (try? JSONDecoder().decode(A9LifecycleEnvelope.self, from: data)) ?? A9LifecycleEnvelope()
    }

    private func persist() {
        guard let url = Self.url() else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(envelope).write(to: url, options: [.atomic])
        } catch {
            // Lifecycle history is diagnostic state; it must never prevent database access.
        }
    }
}
