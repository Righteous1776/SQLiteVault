import SwiftUI

private extension A9HealthColor {
    var tint: Color {
        switch self {
        case .green: .green
        case .yellow: .orange
        case .red: .red
        }
    }

    var systemImage: String {
        switch self {
        case .green: "checkmark.shield.fill"
        case .yellow: "exclamationmark.shield.fill"
        case .red: "xmark.shield.fill"
        }
    }
}

struct A9HealthConsoleView: View {
    @Environment(VaultStore.self) private var store

    private var orderedDecisions: [A9Decision] {
        store.a9Decisions.values.sorted { lhs, rhs in
            if lhs.color != rhs.color { return lhs.color.latticeIndex > rhs.color.latticeIndex }
            if lhs.level != rhs.level { return lhs.level.rawValue > rhs.level.rawValue }
            return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    summaryGrid
                    latticePrimer
                    lifecycleActivity
                    decisions
                }
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("A9 Health")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.runA9Scan(depth: .fast) }
                } label: {
                    Label("Fast Scan", systemImage: "bolt.fill")
                }
                .buttonStyle(.glass)
                .disabled(store.isA9Scanning)

                Button {
                    Task { await store.runA9Scan(depth: .deep) }
                } label: {
                    if store.isA9Scanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Deep Scan", systemImage: "waveform.path.ecg")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isA9Scanning)
            }
        }
        .task {
            if store.a9Decisions.isEmpty { await store.runA9Scan(depth: .fast) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(store.a9WorstColor.tint.opacity(0.12))
                    .frame(width: 78, height: 78)
                Image(systemName: "cpu")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(store.a9WorstColor.tint)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("DBH-LATTICE-CHIP · A9")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.tint)
                Text("Deterministic database-health arbitration")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("A9 observes SQLite and cloud-health signals, maps them into a 144-state lattice, and produces an advisory P0–P3 / L0–L5 decision. It never repairs, rewrites, freezes, merges, or cuts over a source database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            Spacer(minLength: 10)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            A9Metric(title: "GREEN", value: "\(store.a9GreenCount)", color: .green, icon: "checkmark.shield.fill")
            A9Metric(title: "YELLOW", value: "\(store.a9YellowCount)", color: .orange, icon: "exclamationmark.shield.fill")
            A9Metric(title: "RED", value: "\(store.a9RedCount)", color: .red, icon: "xmark.shield.fill")
            A9Metric(title: "Last pass", value: store.lastA9ScanDepth.title, color: .accentColor, icon: "waveform.path.ecg")
        }
    }

    private var latticePrimer: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("144-state lattice", systemImage: "square.grid.3x3.square")
                        .font(.headline)
                    Spacer()
                    Text("3 × 4 × 6 × 2")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text("Health color × priority × intervention level × persistence/blocker state. RED is latched and is never cleared automatically by A9; an explicit acknowledgement is required after review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    VaultTagChip(text: "P0 → L5", systemImage: "exclamationmark.octagon.fill", emphasized: true)
                    VaultTagChip(text: "RED + Blocker → L4")
                    VaultTagChip(text: "RED → L3")
                    VaultTagChip(text: "YELLOW persistent/P1 → L2")
                }
            }
            .padding(18)
        }
    }

    private var lifecycleActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Lifecycle preflight",
                eyebrow: "A9 evidence journal",
                subtitle: "High-risk database actions are recorded with the A9 state that existed immediately before the action."
            )
            if store.a9Preflights.isEmpty {
                EmptyStatePanel(
                    title: "No lifecycle preflight yet",
                    message: "Import, open, Recovery, conflict capture, eviction and optimization actions will appear here.",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(store.a9Preflights.prefix(10))) { preflight in
                        A9PreflightRow(preflight: preflight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var decisions: some View {
        if orderedDecisions.isEmpty {
            EmptyStatePanel(
                title: "No A9 decisions yet",
                message: "Run a Fast or Deep scan to generate deterministic health decisions for the Vault.",
                systemImage: "cpu"
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Database decisions", eyebrow: "A9 arbitration", subtitle: "Deep scan adds SQLite integrity and foreign-key diagnostics when a local copy is available.")
                LazyVStack(spacing: 12) {
                    ForEach(orderedDecisions) { decision in
                        A9DecisionCard(decision: decision)
                    }
                }
            }
        }
    }
}

struct DatabaseA9HealthView: View {
    @Environment(VaultStore.self) private var store
    let asset: DatabaseAsset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    "A9 database health",
                    eyebrow: "Deterministic lattice",
                    subtitle: "Advisory-only health arbitration. A9 has zero source-database mutation authority."
                )

                if let decision = store.a9Decision(for: asset) {
                    A9DecisionCard(decision: decision)
                    signalList(decision)

                    if decision.redLatched {
                        SoftPanel {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RED latch active")
                                        .font(.headline)
                                    Text("A9 will not silently clear a previous RED decision. Acknowledge only after reviewing the fault and preserving Recovery data.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Acknowledge") {
                                    Task { await store.acknowledgeA9RedLatch(for: asset) }
                                }
                                .buttonStyle(.glass)
                            }
                            .padding(18)
                        }
                    }
                } else {
                    EmptyStatePanel(
                        title: "No A9 decision",
                        message: "Run a Fast scan for lightweight checks or a Deep scan for SQLite integrity and foreign-key diagnostics.",
                        systemImage: "cpu"
                    )
                }

                lifecyclePanel
                schemaFingerprintPanel
                healthHistoryPanel
                preflightHistoryPanel

                HStack(spacing: 10) {
                    Button {
                        Task { await store.runA9Scan(depth: .fast, fileName: asset.fileName, trigger: "Manual fast scan") }
                    } label: {
                        Label("Fast Scan", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.glass)

                    Button {
                        Task { await store.runA9Scan(depth: .deep, fileName: asset.fileName, trigger: "Manual deep scan") }
                    } label: {
                        Label("Deep Scan", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!asset.isLocallyAvailable)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var lifecyclePanel: some View {
        let phase = store.lifecyclePhase(for: asset)
        return SoftPanel {
            HStack(spacing: 14) {
                Image(systemName: phase.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Database lifecycle").font(.headline)
                    Text(phase.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(asset.location == .iCloud ? "iCloud master" : "Local fallback")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private var schemaFingerprintPanel: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Schema fingerprint", systemImage: "number.square.fill")
                    .font(.headline)
                if let fingerprint = store.schemaFingerprint(for: asset) {
                    Text(fingerprint.shortDigest)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("SHA-256 · \(fingerprint.objectCount) schema objects · user_version \(fingerprint.userVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("A9 compares this canonical sqlite_schema fingerprint with the previous trusted sample. Drift becomes an explicit advisory signal; it is never treated as corruption by itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A local copy is required before SQLite Vault can fingerprint sqlite_schema.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private var healthHistoryPanel: some View {
        let history = Array(store.a9History(for: asset).prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Health history", eyebrow: "Trend", subtitle: "Recent A9 decisions are retained locally for lifecycle comparison.")
            if history.isEmpty {
                EmptyStatePanel(title: "No health history", message: "Run an A9 scan to create the first historical sample.", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                SoftPanel {
                    VStack(spacing: 0) {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 12) {
                                Circle().fill(entry.color.tint).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("State \(entry.stateNumber)/144 · \(entry.priority.title) · \(entry.level.title)")
                                        .font(.caption.monospaced().weight(.semibold))
                                    Text("\(entry.trigger) · \(entry.sampledAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Risk \(entry.riskPoints)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            if index < history.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var preflightHistoryPanel: some View {
        let items = Array(store.a9Preflights(for: asset).prefix(6))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lifecycle preflight", eyebrow: "Action journal", subtitle: "A9 records recommendations before high-risk lifecycle transitions without gaining source write authority.")
            if items.isEmpty {
                EmptyStatePanel(title: "No preflight record", message: "Lifecycle actions for this database will be recorded here.", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in A9PreflightRow(preflight: item) }
                }
            }
        }
    }

    private func signalList(_ decision: A9Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Signals", eyebrow: "Evidence", subtitle: decision.signals.isEmpty ? "No advisory signal in this pass." : nil)
            if decision.signals.isEmpty {
                SoftPanel {
                    Label("No fault signal detected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(decision.signals) { signal in
                    SoftPanel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: signal.blocker ? "exclamationmark.octagon.fill" : "waveform.path.ecg")
                                .foregroundStyle(signal.blocker ? .red : .orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(signal.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(signal.priority.title)
                                        .font(.caption.monospaced().weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(signal.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(signal.source) · +\(signal.riskPoints) risk")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

private struct A9PreflightRow: View {
    let preflight: A9PreflightResult

    private var tint: Color {
        switch preflight.disposition {
        case .proceed: .green
        case .review: .orange
        case .stopRecommended: .red
        }
    }

    var body: some View {
        SoftPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: preflight.disposition == .proceed ? "checkmark.circle.fill" : (preflight.disposition == .review ? "exclamationmark.triangle.fill" : "hand.raised.fill"))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preflight.action.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(preflight.disposition.title)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(tint)
                    }
                    Text(preflight.fileName).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(preflight.summary).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let state = preflight.stateNumber { Text("A9 \(state)/144") }
                        Text("Risk \(preflight.riskPoints)")
                        if preflight.schemaDriftDetected { Text("Schema drift") }
                        if preflight.requiresRecovery { Text("Recovery required") }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(15)
        }
    }
}

private struct A9Metric: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct A9DecisionCard: View {
    let decision: A9Decision

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(decision.color.tint.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: decision.color.systemImage)
                            .foregroundStyle(decision.color.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.fileName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("State \(decision.stateNumber)/144 · \(decision.priority.title) · \(decision.level.title) · \(decision.scanDepth.title)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(decision.color.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(decision.color.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(decision.color.tint.opacity(0.10), in: Capsule())
                }

                HStack(spacing: 8) {
                    VaultTagChip(text: "Risk \(decision.riskPoints)", systemImage: "gauge.with.dots.needle.67percent")
                    VaultTagChip(text: "Health \(decision.healthScore)")
                    if decision.persistent { VaultTagChip(text: "Persistent", systemImage: "clock.badge.exclamationmark") }
                    if decision.blocker { VaultTagChip(text: "Blocker", systemImage: "hand.raised.fill", emphasized: true) }
                }

                Text(decision.summary)
                    .font(.subheadline)
                Text(decision.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }
}
