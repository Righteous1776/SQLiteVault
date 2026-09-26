import SwiftUI

struct AssetMetadataEditorView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let asset: DatabaseAsset
    @State private var category: String
    @State private var tagsText: String
    @State private var isFavorite: Bool

    init(asset: DatabaseAsset) {
        self.asset = asset
        _category = State(initialValue: "")
        _tagsText = State(initialValue: "")
        _isFavorite = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Database") {
                    LabeledContent("File", value: asset.fileName)
                    Toggle("Favorite", isOn: $isFavorite)
                }

                Section("Organization") {
                    TextField("Category", text: $category)
                    TextField("Tags, comma separated", text: $tagsText)
                }

                if !store.allCategories.isEmpty || !store.allTags.isEmpty {
                    Section("Existing vocabulary") {
                        if !store.allCategories.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(store.allCategories, id: \.self) { value in
                                        Button(value) { category = value }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        if !store.allTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(store.allTags, id: \.self) { value in
                                        Button(value) { appendTag(value) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Organize Database")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let metadata = store.metadata(for: asset)
                category = metadata.category ?? ""
                tagsText = metadata.tags.joined(separator: ", ")
                isFavorite = metadata.isFavorite
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.updateMetadata(
                                for: asset,
                                category: category,
                                tags: parseTags(tagsText),
                                isFavorite: isFavorite
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func parseTags(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func appendTag(_ tag: String) {
        var tags = parseTags(tagsText)
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        tagsText = tags.joined(separator: ", ")
    }
}
