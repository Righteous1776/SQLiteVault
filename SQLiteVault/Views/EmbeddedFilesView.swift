import SwiftUI
import UIKit
import QuickLook

struct DatabaseEmbeddedFilesView: View {
    let database: DatabaseAsset
    @State private var files: [EmbeddedBinaryAsset] = []
    @State private var isScanning = false
    @State private var searchText = ""
    @State private var errorText: String?
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var extractingID: EmbeddedBinaryAsset.ID?

    private let service = EmbeddedFileService()

    var body: some View {
        EmbeddedFilesSurface(
            title: "Embedded files",
            subtitle: "SQLite Vault scans BLOB metadata first. Full binary data is extracted only when you preview or export a selected file.",
            files: filteredFiles,
            isScanning: isScanning,
            searchText: $searchText,
            extractingID: extractingID,
            databaseNameVisible: false,
            onRefresh: scan,
            onPreview: { file in extract(file, action: .preview) },
            onExport: { file in extract(file, action: .share) }
        )
        .task(id: database.fileURL) { scan() }
        .quickLookPreview($previewURL)
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityShareView(items: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Embedded file error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "Unknown error")
        }
    }

    private var filteredFiles: [EmbeddedBinaryAsset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.inferredFileName.localizedCaseInsensitiveContains(query)
            || $0.locationDescription.localizedCaseInsensitiveContains(query)
            || $0.kind.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        let snapshot = database
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.scan(database: snapshot)
                }.value
                files = result
                isScanning = false
            } catch {
                isScanning = false
                errorText = error.localizedDescription
            }
        }
    }

    private enum ExtractionAction { case preview, share }

    private func extract(_ file: EmbeddedBinaryAsset, action: ExtractionAction) {
        guard extractingID == nil else { return }
        extractingID = file.id
        let snapshot = database
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try service.materialize(file, from: snapshot)
                }.value
                extractingID = nil
                switch action {
                case .preview: previewURL = url
                case .share: shareURL = url
                }
            } catch {
                extractingID = nil
                errorText = error.localizedDescription
            }
        }
    }
}

struct VaultEmbeddedFilesView: View {
    @Environment(VaultStore.self) private var store
    @State private var files: [EmbeddedBinaryAsset] = []
    @State private var isScanning = false
    @State private var searchText = ""
    @State private var errorText: String?
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var extractingID: EmbeddedBinaryAsset.ID?

    private let service = EmbeddedFileService()

    var body: some View {
        ZStack {
            VaultBackground()
            EmbeddedFilesSurface(
                title: "Binary Assets",
                subtitle: "Find Word, PDF, Office, image, archive and other BLOB-backed files across every SQLite database in the Vault.",
                files: filteredFiles,
                isScanning: isScanning,
                searchText: $searchText,
                extractingID: extractingID,
                databaseNameVisible: true,
                onRefresh: scanAll,
                onPreview: { file in extract(file, action: .preview) },
                onExport: { file in extract(file, action: .share) }
            )
        }
        .navigationTitle("Binary Assets")
        .task { if files.isEmpty { scanAll() } }
        .quickLookPreview($previewURL)
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityShareView(items: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Binary asset error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "Unknown error")
        }
    }

    private var filteredFiles: [EmbeddedBinaryAsset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.inferredFileName.localizedCaseInsensitiveContains(query)
            || $0.databaseFileName.localizedCaseInsensitiveContains(query)
            || $0.locationDescription.localizedCaseInsensitiveContains(query)
            || $0.kind.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private func scanAll() {
        guard !isScanning else { return }
        isScanning = true
        let databases = store.assets
        Task {
            var combined: [EmbeddedBinaryAsset] = []
            var failures: [String] = []
            for database in databases {
                do {
                    let scanned = try await Task.detached(priority: .utility) {
                        try service.scan(database: database)
                    }.value
                    combined.append(contentsOf: scanned)
                } catch {
                    failures.append(database.name)
                }
            }
            files = combined.sorted { $0.inferredFileName.localizedStandardCompare($1.inferredFileName) == .orderedAscending }
            isScanning = false
            if !failures.isEmpty {
                errorText = "Could not scan: \(failures.joined(separator: ", "))"
            }
        }
    }

    private enum ExtractionAction { case preview, share }

    private func extract(_ file: EmbeddedBinaryAsset, action: ExtractionAction) {
        guard extractingID == nil,
              let database = store.assets.first(where: { $0.fileName == file.databaseFileName }) else { return }
        extractingID = file.id
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try service.materialize(file, from: database)
                }.value
                extractingID = nil
                switch action {
                case .preview: previewURL = url
                case .share: shareURL = url
                }
            } catch {
                extractingID = nil
                errorText = error.localizedDescription
            }
        }
    }
}

private struct EmbeddedFilesSurface: View {
    let title: String
    let subtitle: String
    let files: [EmbeddedBinaryAsset]
    let isScanning: Bool
    @Binding var searchText: String
    let extractingID: EmbeddedBinaryAsset.ID?
    let databaseNameVisible: Bool
    let onRefresh: () -> Void
    let onPreview: (EmbeddedBinaryAsset) -> Void
    let onExport: (EmbeddedBinaryAsset) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    SectionHeader(title, eyebrow: "Selective extraction", subtitle: subtitle)
                    Spacer(minLength: 12)
                    Button(action: onRefresh) {
                        Label(isScanning ? "Scanning" : "Rescan", systemImage: isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    }
                    .buttonStyle(VaultFluidButtonStyle())
                    .disabled(isScanning)
                }

                SoftInsetPanel {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter file name, type or table…", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }

                if isScanning && files.isEmpty {
                    SoftPanel {
                        HStack(spacing: 14) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Scanning BLOB metadata")
                                    .font(.headline)
                                Text("The full document contents are not extracted during this pass.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(20)
                    }
                } else if files.isEmpty {
                    ContentUnavailableView(
                        "No embedded files found",
                        systemImage: "doc.badge.magnifyingglass",
                        description: Text("SQLite Vault looks for BLOB-backed file columns and common filename metadata.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    HStack(spacing: 12) {
                        MetricTile(title: "Discovered", value: "\(files.count)", icon: "doc.on.doc", detail: "BLOB assets")
                        MetricTile(
                            title: "Binary size",
                            value: ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.byteCount }, countStyle: .file),
                            icon: "externaldrive.fill.badge.icloud",
                            detail: "Selected files extract on demand"
                        )
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            EmbeddedFileRow(
                                file: file,
                                databaseNameVisible: databaseNameVisible,
                                isExtracting: extractingID == file.id,
                                onPreview: { onPreview(file) },
                                onExport: { onExport(file) }
                            )
                            .staggeredSpring(index)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct EmbeddedFileRow: View {
    let file: EmbeddedBinaryAsset
    let databaseNameVisible: Bool
    let isExtracting: Bool
    let onPreview: () -> Void
    let onExport: () -> Void

    var body: some View {
        SoftPanel {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.11))
                        .frame(width: 52, height: 52)
                    Image(systemName: file.kind.systemImage)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(file.inferredFileName)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text(file.kind.displayName)
                        Text("•")
                        Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                        Text("•")
                        Text(file.locationDescription)
                        if databaseNameVisible {
                            Text("•")
                            Text(file.databaseFileName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isExtracting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 76)
                } else {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(action: onPreview) {
                                Label("Preview", systemImage: "eye")
                            }
                            .buttonStyle(VaultFluidButtonStyle())

                            Button(action: onExport) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(VaultFluidButtonStyle(prominent: true))
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
