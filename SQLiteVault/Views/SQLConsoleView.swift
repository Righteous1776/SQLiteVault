import SwiftUI

struct SQLConsoleView: View {
    let asset: DatabaseAsset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sql = "SELECT name, type FROM sqlite_schema ORDER BY type, name LIMIT 100;"
    @State private var result: QueryResult?
    @State private var errorText: String?
    @State private var isRunning = false
    @State private var runState = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    SectionHeader(
                        "SQL Console",
                        eyebrow: "Read-only",
                        subtitle: "Query safely against the selected Vault copy."
                    )
                    Spacer(minLength: 16)
                    Button {
                        run()
                    } label: {
                        HStack(spacing: 8) {
                            MorphingSymbol(
                                primary: "play.fill",
                                alternate: "checkmark",
                                alternateState: runState && !isRunning,
                                font: .body.weight(.bold)
                            )
                            Text(isRunning ? "Running" : "Run")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isRunning || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                SoftInsetPanel {
                    TextEditor(text: $sql)
                        .font(.system(.body, design: .monospaced))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150, maxHeight: 240)
                        .padding(14)
                }

                if let result {
                    resultHeader(result)
                    QueryResultTable(result: result)
                } else {
                    SoftPanel {
                        ContentUnavailableView(
                            "Ready for a query",
                            systemImage: "terminal",
                            description: Text("Write statements are rejected by sqlite3_stmt_readonly before execution.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 210)
                        .padding(18)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert("SQL Error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    @ViewBuilder
    private func resultHeader(_ result: QueryResult) -> some View {
        HStack(spacing: 10) {
            Label("\(result.rows.count) rows", systemImage: "list.bullet.rectangle")
            Text("•")
                .foregroundStyle(.tertiary)
            Label(String(format: "%.2f ms", result.elapsedMilliseconds), systemImage: "timer")
            if result.truncated {
                Text("Truncated")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func run() {
        isRunning = true
        runState = false

        do {
            result = try SQLQueryEngine().executeReadOnly(sql: sql, databaseURL: asset.fileURL)
            errorText = nil
            if reduceMotion {
                runState = true
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    runState = true
                }
            }
        } catch {
            errorText = error.localizedDescription
        }

        isRunning = false
    }
}

private struct QueryResultTable: View {
    let result: QueryResult

    var body: some View {
        SoftPanel {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        ForEach(result.columns, id: \.self) { column in
                            Text(column)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 3)
                        }
                    }

                    Divider()

                    ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value ?? "NULL")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(value == nil ? .tertiary : .primary)
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .frame(minHeight: 220, maxHeight: 520)
        }
    }
}
