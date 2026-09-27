import SwiftUI

struct ICloudControlCenterView: View {
    @Environment(VaultStore.self) private var store
    @State private var showingOptimizationPreview = false

    var body: some View {
        ZStack {
            VaultBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    cloudHero
                    optimizedStoragePanel
                    metricGrid
                    if store.cloudStatus.localFallbackFileCount > 0 {
                        migrationPanel
                    }
                    cloudFilesSection
                    recoveryPanel
                    diagnosticsPanel
                }
                .padding(24)
                .frame(maxWidth: 1050, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .refreshable { await store.refreshCloudStatus() }
        }
        .navigationTitle("iCloud")
        .sheet(isPresented: $showingOptimizationPreview) {
            optimizationPreviewSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await store.refreshCloudStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await store.refreshCloudStatus()
            }
        }
    }

    private var cloudHero: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(statusTint.opacity(0.13))
                            .frame(width: 66, height: 66)
                        Image(systemName: statusSymbol)
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(statusTint)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("iCloud Vault")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            statusPill
                        }
                        Text(store.cloudStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Task { await store.syncICloudNow() }
                    } label: {
                        if store.isCloudRefreshing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Syncing…")
                            }
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!store.cloudStatus.isConnected || store.isCloudRefreshing)

                    Button {
                        Task { await store.refreshCloudStatus() }
                    } label: {
                        Label("Check Status", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isCloudRefreshing)
                }

                if let action = store.lastCloudAction {
                    Label(action, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var optimizedStoragePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Device Storage",
                eyebrow: "Optimized Storage",
                subtitle: "iCloud remains the master copy. SQLite Vault can keep only the local database copies you need."
            )

            SoftPanel {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(OptimizedStorageMode.allCases) { mode in
                        Button {
                            Task { await store.setStorageMode(mode) }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(store.storageMode == mode ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: mode.symbol)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(store.storageMode == mode ? Color.accentColor : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey(mode.title))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(LocalizedStringKey(mode.detail))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 12)
                                Image(systemName: store.storageMode == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(store.storageMode == mode ? Color.accentColor : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if mode != OptimizedStorageMode.allCases.last {
                            Divider().padding(.leading, 60)
                        }
                    }

                    Divider()

                    cacheBudgetSelector

                    Divider()

                    storageUsageStrip

                    HStack(spacing: 10) {
                        Button {
                            showingOptimizationPreview = true
                        } label: {
                            if store.isOptimizingStorage {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Optimizing…")
                                }
                            } else {
                                Label("Review Optimization", systemImage: "wand.and.rays")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!store.cloudStatus.isConnected || store.isOptimizingStorage)

                        Text("Only fully uploaded, conflict-free databases can be evicted. Favorites, pinned files, and the database currently in use are protected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
        }
    }

    private var cacheBudgetSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Cache Budget").font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(store.cacheBudgetPreset.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Menu {
                    ForEach(CacheBudgetPreset.allCases) { preset in
                        Button { Task { await store.setCacheBudgetPreset(preset) } } label: {
                            if store.cacheBudgetPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(store.cacheBudgetPreset.title).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }

            if store.storageOptimizationStatus.overBudgetBytes > 0 {
                Label(
                    "Cache is \(ByteCountFormatter.string(fromByteCount: store.storageOptimizationStatus.overBudgetBytes, countStyle: .file)) over budget",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
    }

    private var storageUsageStrip: some View {
        let status = store.storageOptimizationStatus
        return VStack(spacing: 12) {
            HStack(spacing: 18) {
                StorageStat(
                    title: "On Device",
                    value: ByteCountFormatter.string(fromByteCount: status.downloadedCloudBytes, countStyle: .file),
                    symbol: "internaldrive.fill"
                )
                StorageStat(
                    title: "Reclaimable",
                    value: ByteCountFormatter.string(fromByteCount: status.reclaimableBytes, countStyle: .file),
                    symbol: "arrow.down.to.line.compact"
                )
                StorageStat(
                    title: "Free Space",
                    value: ByteCountFormatter.string(fromByteCount: status.device.availableBytes, countStyle: .file),
                    symbol: "gauge.with.dots.needle.33percent"
                )
            }

            if status.device.totalBytes > 0 {
                ProgressView(value: Double(status.device.usedBytes), total: Double(status.device.totalBytes))
                    .tint(.accentColor)
            }

            HStack {
                Label("\(status.pinnedFileCount) kept downloaded", systemImage: "pin.fill")
                Spacer()
                Label("\(status.remoteOnlyFileCount) cloud-only", systemImage: "icloud")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(
                    "Preview cache \(ByteCountFormatter.string(fromByteCount: status.temporaryCacheBytes, countStyle: .file))",
                    systemImage: "doc.on.doc"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if status.temporaryCacheBytes > 0 {
                    Button("Clear") { Task { await store.purgeTemporaryPreviewCache() } }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
            MetricTile(title: "Cloud Databases", value: "\(store.cloudStatus.cloudFileCount)", icon: "externaldrive.fill.badge.icloud", detail: "Visible in the iCloud container")
            MetricTile(title: "Cloud Storage", value: ByteCountFormatter.string(fromByteCount: store.cloudStatus.cloudBytes, countStyle: .file), icon: "icloud.fill", detail: "SQLite data in this Vault")
            MetricTile(title: "Remote Only", value: "\(store.cloudStatus.filesNeedingDownload)", icon: "icloud.and.arrow.down", detail: "Not occupying a full local copy")
            MetricTile(title: "Conflicts", value: "\(store.cloudStatus.conflictCount)", icon: "exclamationmark.icloud.fill", detail: store.cloudStatus.conflictCount == 0 ? "No unresolved conflicts" : "Needs attention")
        }
    }

    private var migrationPanel: some View {
        SoftPanel {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.13)).frame(width: 48, height: 48)
                    Image(systemName: "internaldrive.fill").font(.title3.weight(.semibold)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local fallback data found").font(.headline)
                    Text("\(store.cloudStatus.localFallbackFileCount) database(s) · \(ByteCountFormatter.string(fromByteCount: store.cloudStatus.localFallbackBytes, countStyle: .file)) remain in local Application Support.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await store.migrateLocalFallbackToICloud() }
                } label: {
                    Label("Move to iCloud", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .disabled(!store.cloudStatus.isConnected || store.isCloudRefreshing)
            }
            .padding(18)
        }
    }

    private var cloudFilesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Cloud Files",
                eyebrow: "iCloud Master Copies",
                subtitle: "Downloaded files are a local cache. Removing a local copy never deletes the iCloud master copy."
            )

            if !store.cloudStatus.isConnected {
                EmptyStatePanel(title: connectionEmptyTitle, message: store.cloudStatus.detail, systemImage: statusSymbol)
            } else if store.cloudStatus.cloudFiles.isEmpty {
                EmptyStatePanel(title: "No databases in iCloud yet", message: "Import a SQLite database while iCloud is connected and it will be copied into the SQLite Vault iCloud Documents container.", systemImage: "icloud.and.arrow.up")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.cloudStatus.cloudFiles) { file in
                        cloudFileRow(file)
                    }
                }
            }
        }
    }

    private func cloudFileRow(_ file: ICloudFileStatus) -> some View {
        let metadata = store.catalog.assetMetadata[file.fileName] ?? .empty
        let pinned = metadata.retentionPolicy == .keepDownloaded
        let favorite = metadata.isFavorite

        return SoftPanel {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(fileTint(file).opacity(0.11))
                        .frame(width: 50, height: 50)
                    Image(systemName: fileSymbol(file))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(fileTint(file))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(file.fileName).font(.headline).lineLimit(1)
                        if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint) }
                        if favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    }

                    HStack(spacing: 7) {
                        Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                        Text("•")
                        Text(transferLabel(file))
                        if let lastOpened = metadata.lastOpenedAt {
                            Text("•")
                            Text("Used \(lastOpened.formatted(.relative(presentation: .named)))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if file.isDownloading {
                        ProgressView(value: file.percentDownloaded, total: 100).tint(.blue)
                    } else if file.isUploading {
                        ProgressView(value: file.percentUploaded, total: 100).tint(.cyan)
                    }
                }

                Spacer(minLength: 12)

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await store.setKeepDownloaded(!pinned, for: file.fileName) }
                        } label: {
                            Image(systemName: pinned ? "pin.fill" : "pin")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(pinned ? "Stop Keeping Downloaded" : "Always Keep Downloaded")

                        if !file.isDownloaded && !file.isDownloading {
                            Button {
                                Task { await store.requestICloudDownload(file) }
                            } label: {
                                Image(systemName: "icloud.and.arrow.down").frame(width: 28, height: 28)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Download from iCloud")
                        } else if file.isDownloaded && store.storageMode != .keepDownloaded && !pinned && !favorite && !file.isUploading && !file.hasUnresolvedConflicts {
                            Button {
                                Task { await store.removeLocalCopy(fileName: file.fileName) }
                            } label: {
                                Image(systemName: "internaldrive.badge.minus").frame(width: 28, height: 28)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Remove Local Copy")
                        } else if file.hasUnresolvedConflicts {
                            Button {
                                Task { await store.captureConflictRecovery(fileName: file.fileName) }
                            } label: {
                                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Capture Conflict Copies")
                        } else {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundStyle(.green)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                "Recovery",
                eyebrow: "Safety Net",
                subtitle: "SQLite Vault creates local restore points before destructive deletion and can capture unresolved iCloud conflict versions."
            )

            if store.recoveryPoints.isEmpty {
                EmptyStatePanel(
                    title: "No recovery points yet",
                    message: "Create a restore point from a database, or SQLite Vault will create one automatically before deleting a locally available database.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.recoveryPoints.prefix(12)) { point in
                        SoftPanel {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.11))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.tint)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.fileName).font(.headline).lineLimit(1)
                                    Text("\(point.displayReason) · \(point.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        Text(ByteCountFormatter.string(fromByteCount: point.sizeBytes, countStyle: .file))
                                        if let state = point.a9StateNumber { Text("A9 \(state)/144") }
                                        if let fingerprint = point.schemaFingerprint { Text("Schema \(fingerprint.shortDigest)") }
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 12)
                                HStack(spacing: 8) {
                                    Button { Task { await store.restoreRecoveryPoint(point) } } label: {
                                        Image(systemName: "arrow.uturn.backward.circle.fill").frame(width: 26, height: 26)
                                    }
                                    .buttonStyle(.glassProminent)
                                    .disabled(store.isRestoringRecovery)
                                    .accessibilityLabel("Restore Recovery Point")

                                    Button(role: .destructive) {
                                        Task { await store.deleteRecoveryPoint(point) }
                                    } label: {
                                        Image(systemName: "trash").frame(width: 26, height: 26)
                                    }
                                    .buttonStyle(.glass)
                                    .accessibilityLabel("Delete Recovery Point")
                                }
                            }
                            .padding(15)
                        }
                    }
                }
            }
        }
    }

    private var optimizationPreviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let preview = store.optimizationPreview
                    SoftPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Optimization Preview", systemImage: "internaldrive.fill.badge.icloud")
                                .font(.title3.weight(.bold))
                            Text("\(preview.candidates.count) safe local database copies can release up to \(ByteCountFormatter.string(fromByteCount: preview.reclaimableBytes, countStyle: .file)). Nothing is removed from iCloud.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                if preview.overBudgetBytes > 0 {
                                    Label("Over budget \(ByteCountFormatter.string(fromByteCount: preview.overBudgetBytes, countStyle: .file))", systemImage: "gauge.with.dots.needle.67percent")
                                }
                                if preview.storagePressureBytesNeeded > 0 {
                                    Label("Free-space target \(ByteCountFormatter.string(fromByteCount: preview.storagePressureBytesNeeded, countStyle: .file))", systemImage: "internaldrive")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(18)
                    }

                    ForEach(preview.candidates) { candidate in
                        SoftPanel {
                            HStack(spacing: 12) {
                                Image(systemName: "externaldrive.fill.badge.icloud").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.fileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Optimize Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingOptimizationPreview = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Optimize") {
                        showingOptimizationPreview = false
                        Task { await store.optimizeStorageNow() }
                    }
                    .disabled(store.optimizationPreview.candidates.isEmpty || store.isOptimizingStorage)
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Cloud Diagnostics", systemImage: "stethoscope").font(.headline)
                CloudDiagnosticRow(title: "Container", value: store.cloudStatus.containerIdentifier)
                CloudDiagnosticRow(title: "Connection", value: connectionLabel)
                CloudDiagnosticRow(title: "Storage mode", value: store.storageMode.title)
                CloudDiagnosticRow(title: "Cache budget", value: store.cacheBudgetPreset.title)
                CloudDiagnosticRow(title: "Last checked", value: store.cloudStatus.lastCheckedAt.formatted(date: .abbreviated, time: .standard))
                if let path = store.cloudStatus.containerPath { CloudDiagnosticRow(title: "Documents path", value: path) }
                Text("Automatic eviction is conservative: SQLite Vault only evicts fully uploaded, conflict-free iCloud files that are not pinned, favorite, or currently in use. The installed app still requires a signed entitlement for this exact iCloud container.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            }
            .padding(18)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(statusTint).frame(width: 7, height: 7)
            Text(connectionLabel).font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusTint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(statusTint.opacity(0.10), in: Capsule())
    }

    private var connectionLabel: String {
        switch store.cloudStatus.connection {
        case .checking: "Checking"
        case .connected: "Connected"
        case .signedOut: "iCloud unavailable"
        case .containerUnavailable: "Container unavailable"
        case .error: "Error"
        }
    }

    private var connectionEmptyTitle: String {
        switch store.cloudStatus.connection {
        case .signedOut: "iCloud is not available"
        case .containerUnavailable: "iCloud container unavailable"
        case .error: "Unable to read iCloud"
        default: "Checking iCloud"
        }
    }

    private var statusSymbol: String {
        switch store.cloudStatus.connection {
        case .connected: "checkmark.icloud.fill"
        case .signedOut: "icloud.slash.fill"
        case .containerUnavailable: "exclamationmark.icloud.fill"
        case .error: "xmark.icloud.fill"
        case .checking: "icloud"
        }
    }

    private var statusTint: Color {
        switch store.cloudStatus.connection {
        case .connected: .green
        case .checking: .blue
        case .signedOut: .secondary
        case .containerUnavailable, .error: .orange
        }
    }

    private func fileSymbol(_ file: ICloudFileStatus) -> String {
        if file.hasUnresolvedConflicts { return "exclamationmark.icloud.fill" }
        if file.isDownloading { return "icloud.and.arrow.down.fill" }
        if file.isUploading { return "icloud.and.arrow.up.fill" }
        if !file.isDownloaded { return "icloud.fill" }
        return "externaldrive.fill.badge.icloud"
    }

    private func fileTint(_ file: ICloudFileStatus) -> Color {
        if file.hasUnresolvedConflicts { return .orange }
        if file.isDownloading || file.isUploading { return .blue }
        if !file.isDownloaded { return .secondary }
        return .green
    }

    private func transferLabel(_ file: ICloudFileStatus) -> String {
        switch file.transferState {
        case .current: "On Device"
        case .downloading: "Downloading \(Int(file.percentDownloaded.rounded()))%"
        case .uploading: "Uploading \(Int(file.percentUploaded.rounded()))%"
        case .remoteOnly: "iCloud Only"
        case .conflict: "Conflict"
        case .unknown: "Pending"
        }
    }
}

private struct StorageStat: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CloudDiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
