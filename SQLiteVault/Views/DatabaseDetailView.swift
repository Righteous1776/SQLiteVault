import SwiftUI

struct DatabaseDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case schema = "Schema"
        case files = "Files"
        case sql = "SQL"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: "rectangle.grid.2x2"
            case .schema: "tablecells"
            case .files: "doc.on.doc"
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
                    case .sql:
                        SQLConsoleView(asset: asset)
                    }
                }
                .id(selectedSection)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .navigationTitle(asset.name)
        .toolbar {
            ToolbarItem {
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
        .task(id: asset.fileURL) {
            do {
                schemaObjects = try SchemaInspector().inspect(url: asset.fileURL).0
            } catch {
                errorText = error.localizedDescription
            }
        }
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
                        .frame(maxWidth: .infinity)
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
