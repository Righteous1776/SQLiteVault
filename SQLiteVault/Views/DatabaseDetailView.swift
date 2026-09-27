import SwiftUI

struct DatabaseDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case schema = "Schema"
        case files = "Files"
        case health = "A9"
        case sql = "SQL"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: "rectangle.grid.2x2"
            case .schema: "tablecells"
            case .files: "doc.on.doc"
            case .health: "cpu"
            case .sql: "terminal"
            }
        }
    }

    let asset: DatabaseAsset
    @Environment(VaultStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var schemaObjects: [SchemaObject] = []
    @State private var selectedSection: Section = .overview
    @State private var errorText: String?
    @State private var showingMetadataEditor = false
    @Namespace private var sectionGlass

    var body: some View {
        ZStack {
            VaultBackground()

            if asset.isLocallyAvailable {
                VStack(spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    Group {
                        switch selectedSection {
                        case .overview:
                            DatabaseOverviewView(asset: asset)
                        case .schema:
                            SchemaBrowserView(asset: asset, objects: schemaObjects)
                        case .files:
                            DatabaseEmbeddedFilesView(database: asset)
                        case .health:
                            DatabaseA9HealthView(asset: asset)
                        case .sql:
                            SQLConsoleView(asset: asset)
                        }
                    }
                    .id(selectedSection)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                }
            } else {
                RemoteDatabasePlaceholder(asset: asset)
            }
        }
        .navigationTitle(asset.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.createRecoveryPoint(for: asset) }
                } label: {
                    Label("Restore Point", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.glass)
                .disabled(!asset.isLocallyAvailable)

                Button { showingMetadataEditor = true } label: {
                    Label("Organize", systemImage: "tag")
                }
                .buttonStyle(.glass)
            }
        }
        .sheet(isPresented: $showingMetadataEditor) {
            AssetMetadataEditorView(asset: asset)
                .environment(store)
        }
        .task(id: "\(asset.fileURL.path)|\(asset.localAvailability.rawValue)") {
            guard asset.isLocallyAvailable else { return }
            await store.markDatabaseOpened(asset)
            do {
                schemaObjects = try SchemaInspector().inspect(url: asset.fileURL).0
            } catch {
                errorText = error.localizedDescription
            }
        }
        .onDisappear { store.markDatabaseClosed(asset) }
        .alert("Unable to inspect database", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases) { section in
                        Button {
                            VaultHaptics.selection()
                            if reduceMotion {
                                selectedSection = section
                            } else {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    selectedSection = section
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(section.rawValue)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minWidth: 82)
                            .contentShape(Rectangle())
                            .if(section == selectedSection) { view in
                                view
                                    .glassEffect(
                                        .regular.tint(Color.accentColor.opacity(0.22)).interactive(),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .glassEffectID("selected-database-section", in: sectionGlass)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(section == selectedSection ? .primary : .secondary)
                        .accessibilityAddTraits(section == selectedSection ? .isSelected : [])
                    }
                }
            }
            .padding(5)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
    }

}

private struct RemoteDatabasePlaceholder: View {
    @Environment(VaultStore.self) private var store
    let asset: DatabaseAsset

    private var cloudFile: ICloudFileStatus? {
        store.cloudStatus.cloudFiles.first { $0.fileName == asset.fileName }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SoftPanel {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 74, height: 74)
                            Image(systemName: asset.localAvailability == .downloading ? "icloud.and.arrow.down.fill" : "icloud.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.tint)
                        }

                        VStack(spacing: 6) {
                            Text(asset.name)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(asset.localAvailability == .downloading ? "Downloading from iCloud" : "Stored in iCloud")
                                .font(.headline)
                            Text("SQLite Vault keeps the cloud copy visible without forcing it onto this device. Download the database before browsing Schema, SQL, or embedded documents.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 560)
                        }

                        let preparation = store.preparationStatus(for: asset.fileName)
                        if preparation.isRunning {
                            VStack(spacing: 8) {
                                ProgressView(value: preparation.progress, total: 1)
                                    .frame(maxWidth: 380)
                                Text(preparation.message)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        } else if preparation.phase == .failed {
                            VStack(spacing: 10) {
                                Label(preparation.message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                                Button {
                                    Task { await store.prepareDatabaseForOpen(asset) }
                                } label: {
                                    Label("Retry Download & Verify", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.glassProminent)
                            }
                        } else if let cloudFile, cloudFile.isDownloading {
                            ProgressView(value: cloudFile.percentDownloaded, total: 100)
                                .frame(maxWidth: 360)
                            Text("Downloading from iCloud · \(Int(cloudFile.percentDownloaded.rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await store.prepareDatabaseForOpen(asset) }
                            } label: {
                                Label("Download & Verify", systemImage: "icloud.and.arrow.down")
                            }
                            .buttonStyle(.glassProminent)
                        }

                        HStack(spacing: 16) {
                            Label(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file), systemImage: "externaldrive")
                            Label("iCloud master copy", systemImage: "checkmark.icloud.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DatabaseOverviewView: View {
    let asset: DatabaseAsset

    private var summary: SchemaSummary? { asset.schemaSummary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(
                    "Database overview",
                    eyebrow: asset.location == .iCloud ? "iCloud asset" : "Local asset",
                    subtitle: "File metadata, organization and schema health at a glance."
                )

                DatabaseOrganizationStrip(asset: asset)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    MetricTile(
                        title: "Size",
                        value: ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file),
                        icon: "externaldrive",
                        detail: asset.fileName
                    )
                    MetricTile(
                        title: "Tables",
                        value: "\(summary?.tableCount ?? 0)",
                        icon: "tablecells",
                        detail: "Primary schema objects"
                    )
                    MetricTile(
                        title: "Views",
                        value: "\(summary?.viewCount ?? 0)",
                        icon: "eye",
                        detail: "Saved projections"
                    )
                    MetricTile(
                        title: "Indexes",
                        value: "\(summary?.indexCount ?? 0)",
                        icon: "list.number",
                        detail: "Query accelerators"
                    )
                }

                SoftPanel {
                    VStack(spacing: 0) {
                        DetailRow(title: "File", value: asset.fileName, icon: "doc")
                        Divider().padding(.leading, 48)
                        DetailRow(
                            title: "Storage",
                            value: asset.location == .iCloud ? "iCloud Drive" : "Local fallback",
                            icon: asset.location == .iCloud ? "icloud" : "internaldrive"
                        )
                        Divider().padding(.leading, 48)
                        DetailRow(
                            title: "Modified",
                            value: asset.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                            icon: "clock"
                        )
                        Divider().padding(.leading, 48)
                        DetailRow(
                            title: "user_version",
                            value: "\(summary?.userVersion ?? 0)",
                            icon: "number"
                        )
                    }
                    .padding(18)
                }

                SoftPanel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.green)
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Read-only protection is active")
                                .font(.headline)
                            Text("SQLite Vault inspects and queries the copied Vault asset without allowing SQL write statements.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}


private struct DatabaseOrganizationStrip: View {
    @Environment(VaultStore.self) private var store
    let asset: DatabaseAsset

    var body: some View {
        let metadata = store.metadata(for: asset)
        SoftPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: metadata.isFavorite ? "star.fill" : "tag.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(metadata.isFavorite ? Color.yellow : Color.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Organization")
                        .font(.headline)
                    if metadata.category == nil && metadata.tags.isEmpty {
                        Text("No category or tags yet. Use Organize to classify this database for the control plane.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if let category = metadata.category {
                                    VaultTagChip(text: category, systemImage: "folder.fill", emphasized: true)
                                }
                                ForEach(metadata.tags, id: \.self) { tag in
                                    VaultTagChip(text: tag, systemImage: "tag")
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(18)
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 30)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 11)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
