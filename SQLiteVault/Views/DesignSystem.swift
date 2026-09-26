import SwiftUI

// MARK: - SQLite Vault visual language
// Apple-style hierarchy + restrained Neumorphism for content surfaces.
// Liquid Glass is reserved for floating controls and primary actions.

enum VaultDesign {
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18
    static let spacing: CGFloat = 16

    static let background = Color(uiColor: .systemGroupedBackground)
    static let panel = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)

    static let shadowDark = Color.black.opacity(0.12)
    static let shadowLight = Color.white.opacity(0.72)
}

struct VaultBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VaultDesign.background

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    .clear,
                    Color.indigo.opacity(colorScheme == .dark ? 0.08 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct SoftPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous)
                    .fill(VaultDesign.panel)
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.34) : VaultDesign.shadowDark,
                        radius: 14,
                        x: 8,
                        y: 8
                    )
                    .shadow(
                        color: colorScheme == .dark ? .white.opacity(0.035) : VaultDesign.shadowLight,
                        radius: 12,
                        x: -7,
                        y: -7
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.06 : 0.035), lineWidth: 0.8)
            }
    }
}

struct SoftInsetPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VaultDesign.controlRadius, style: .continuous)
                    .fill(VaultDesign.inset)
                    .shadow(
                        color: colorScheme == .dark ? .white.opacity(0.03) : .white.opacity(0.85),
                        radius: 5,
                        x: 3,
                        y: 3
                    )
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.34) : .black.opacity(0.10),
                        radius: 6,
                        x: -3,
                        y: -3
                    )
            )
    }
}

struct MorphingSymbol: View {
    let primary: String
    let alternate: String
    let alternateState: Bool
    var font: Font = .body

    var body: some View {
        Image(systemName: alternateState ? alternate : primary)
            .font(font)
            .contentTransition(.symbolEffect(.replace))
    }
}

struct VaultGlassIconButton: View {
    let title: String
    let systemImage: String
    var alternateImage: String? = nil
    var alternateState: Bool = false
    var isProminent = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if isProminent {
            button
                .buttonStyle(.glassProminent)
        } else {
            button
                .buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let alternateImage {
                    MorphingSymbol(
                        primary: systemImage,
                        alternate: alternateImage,
                        alternateState: alternateState,
                        font: .body.weight(.semibold)
                    )
                } else {
                    Image(systemName: systemImage)
                }
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let detail: String?

    init(title: String, value: String, icon: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.detail = detail
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .padding(18)
        }
    }
}

struct StatusRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    var completed = true

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(completed ? Color.green.opacity(0.12) : Color.secondary.opacity(0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: completed ? "checkmark" : icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(completed ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.tint)
            }
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .tracking(-0.4)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct VaultTagChip: View {
    let text: String
    var systemImage: String? = nil
    var emphasized = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(emphasized ? Color.accentColor : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            emphasized ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.055),
            in: Capsule()
        )
    }
}

struct EmptyStatePanel: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        SoftPanel {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
        }
    }
}
