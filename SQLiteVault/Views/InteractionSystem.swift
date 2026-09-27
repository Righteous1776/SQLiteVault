import SwiftUI
import UIKit

// MARK: - Haptics

enum VaultHaptics {
    static func press() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.62)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A very short rigid pulse used as a single "gear tooth" while dragging.
    static func gearTick() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.30)
    }

    /// Stronger detent feedback when the control crosses one of the three languages.
    static func gearDetent() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.82)
    }
}

// MARK: - Buttons

struct VaultFluidButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        VaultFluidButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct VaultFluidButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.primary.opacity(0.075))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(configuration.isPressed ? 0.04 : 0.24), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(
                        color: configuration.isPressed ? .black.opacity(0.20) : Color.accentColor.opacity(prominent ? 0.28 : 0.08),
                        radius: configuration.isPressed ? 2 : 10,
                        x: 0,
                        y: configuration.isPressed ? 1 : 5
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.27, dampingFraction: 0.78),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { VaultHaptics.press() }
            }
    }
}

// MARK: - Scroll-safe tactile panels

/// V0.3.1 deliberately does not install any drag recognizer on content cards.
/// The previous minimumDistance: 0 tilt recognizer competed with ScrollView/List.
/// Pointer hover can still lift the card on iPad without stealing touch scrolling.
struct InteractiveTiltPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous))
            .hoverEffect(.lift)
    }
}

// MARK: - Ambient effects

struct DynamicGlowBorder<S: Shape>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    let shape: S

    var body: some View {
        shape
            .stroke(
                AngularGradient(
                    colors: [.cyan, .blue, .indigo, .purple, .cyan],
                    center: .center,
                    angle: .degrees(angle)
                ),
                lineWidth: 1.1
            )
            .shadow(color: .cyan.opacity(0.22), radius: 8)
            .shadow(color: .indigo.opacity(0.14), radius: 16)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .allowsHitTesting(false)
    }
}

struct StaggeredSpring: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .scaleEffect(appeared ? 1 : 0.975)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.78).delay(Double(index) * 0.045)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    func staggeredSpring(_ index: Int) -> some View {
        modifier(StaggeredSpring(index: index))
    }
}

// MARK: - Dashboard chart

struct MagneticMetricChart: View {
    let labels: [LocalizedStringKey]
    let values: [Int]
    @State private var selectedIndex = 0

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(labels[safe: selectedIndex] ?? "Databases")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(values[safe: selectedIndex] ?? 0)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .contentTransition(.numericText(value: Double(values[safe: selectedIndex] ?? 0)))
                }

                GeometryReader { proxy in
                    let points = chartPoints(in: proxy.size)
                    ZStack {
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                        }
                        .stroke(
                            LinearGradient(colors: [Color.accentColor, .indigo], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )

                        ForEach(points.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedIndex ? Color.accentColor : VaultDesign.panel)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: index == selectedIndex ? 15 : 10, height: index == selectedIndex ? 15 : 10)
                                .shadow(color: Color.accentColor.opacity(index == selectedIndex ? 0.38 : 0), radius: 8)
                                .position(points[index])
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                guard !values.isEmpty else { return }
                                let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
                                let nearest = min(max(Int((value.location.x / max(step, 1)).rounded()), 0), values.count - 1)
                                if nearest != selectedIndex {
                                    selectedIndex = nearest
                                    VaultHaptics.selection()
                                }
                            }
                    )
                }
                .frame(height: 120)
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxValue = max(values.max() ?? 1, 1)
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(value) / CGFloat(maxValue)) * (size.height - 18) - 9
            )
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Language gear dial

struct LanguageGearDialOverlay: View {
    @Binding var language: VaultLanguage
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @State private var knobOffset: CGFloat = 0
    @State private var gestureStartOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var lastTooth = Int.min

    private let detentSpacing: CGFloat = 104
    private let trackWidth: CGFloat = 152
    private let trackHeight: CGFloat = 360
    private let knobSize: CGFloat = 104
    private let gearPitch: CGFloat = 9
    private let magneticRadius: CGFloat = 34

    var body: some View {
        ZStack {
            backgroundScrim

            VStack(spacing: 24) {
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55))
                            .frame(width: 58, height: 58)
                            .glassEffect(reduceTransparency ? .identity : .regular, in: Circle())
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 23, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text("Interface Language")
                        .font(.headline)
                    Text("Drag through the three tactile detents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GlassEffectContainer(spacing: 14) {
                    ZStack {
                        track
                        detentLabels
                        knob
                    }
                    .frame(width: trackWidth, height: trackHeight)
                }

                Text("\(language.nativeName) · \(language.shortName)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .ignoresSafeArea()
        .onAppear {
            knobOffset = detentOffset(for: language)
        }
        .onChange(of: language) { _, newValue in
            guard !isDragging else { return }
            snap(to: newValue)
        }
        .accessibilityElement(children: .contain)
    }

    private var backgroundScrim: some View {
        ZStack {
            Rectangle()
                .fill(reduceTransparency ? Color(uiColor: .systemBackground) : Color.clear)
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }

    private var track: some View {
        RoundedRectangle(cornerRadius: 76, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.58),
                        Color.accentColor.opacity(colorScheme == .dark ? 0.05 : 0.045),
                        Color.black.opacity(colorScheme == .dark ? 0.12 : 0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 76, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.70), lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.13), radius: 24, x: 0, y: 16)
            .shadow(color: .white.opacity(colorScheme == .dark ? 0.025 : 0.70), radius: 14, x: -7, y: -8)
            .glassEffect(
                reduceTransparency ? .identity : .regular.tint(Color.accentColor.opacity(0.035)),
                in: RoundedRectangle(cornerRadius: 76, style: .continuous)
            )
    }

    private var detentLabels: some View {
        ZStack {
            ForEach(VaultLanguage.allCases) { item in
                Text(item == language ? "" : item.nativeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(item == language ? 0 : 0.72)
                    .offset(y: detentOffset(for: item))
            }

            VStack {
                Spacer()
                Divider().opacity(0.16)
                Spacer()
                Divider().opacity(0.16)
                Spacer()
            }
            .padding(.vertical, 74)
            .allowsHitTesting(false)
        }
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.95),
                            Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.18),
                            Color.blue.opacity(colorScheme == .dark ? 0.16 : 0.09)
                        ],
                        center: .topLeading,
                        startRadius: 6,
                        endRadius: knobSize
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.28 : 0.88), lineWidth: 1.2)
                }
                .shadow(color: Color.accentColor.opacity(isDragging ? 0.34 : 0.18), radius: isDragging ? 18 : 11)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.16), radius: 12, x: 0, y: 8)
                .glassEffect(
                    reduceTransparency ? .identity : .regular.tint(Color.accentColor.opacity(isDragging ? 0.18 : 0.10)).interactive(),
                    in: Circle()
                )

            VStack(spacing: 3) {
                Text(language.nativeName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(language.shortName)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: knobSize, height: knobSize)
        .scaleEffect(isDragging ? 1.045 : 1)
        .offset(y: knobOffset)
        .contentShape(Circle())
        .gesture(dragGesture)
        .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.22, dampingFraction: 0.78), value: isDragging)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    gestureStartOffset = detentOffset(for: language)
                    lastTooth = Int((gestureStartOffset / gearPitch).rounded())
                    VaultHaptics.press()
                }

                let raw = clamp(gestureStartOffset + value.translation.height)
                let tooth = Int((raw / gearPitch).rounded())
                if tooth != lastTooth {
                    lastTooth = tooth
                    VaultHaptics.gearTick()
                }

                let nearestIndex = nearestDetentIndex(for: raw)
                let nearestLanguage = VaultLanguage.language(at: nearestIndex)
                if nearestLanguage != language {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        language = nearestLanguage
                    }
                    VaultHaptics.gearDetent()
                }

                knobOffset = magnetized(raw)
            }
            .onEnded { value in
                isDragging = false
                let projected = clamp(gestureStartOffset + value.predictedEndTranslation.height)
                let target = VaultLanguage.language(at: nearestDetentIndex(for: projected))

                if target != language {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        language = target
                    }
                    VaultHaptics.gearDetent()
                }
                snap(to: target)
            }
    }

    private func detentOffset(for language: VaultLanguage) -> CGFloat {
        CGFloat(language.index - 1) * detentSpacing
    }

    private func nearestDetentIndex(for value: CGFloat) -> Int {
        let normalized = value / detentSpacing + 1
        return min(max(Int(normalized.rounded()), 0), 2)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -detentSpacing), detentSpacing)
    }

    private func magnetized(_ raw: CGFloat) -> CGFloat {
        let target = detentOffset(for: VaultLanguage.language(at: nearestDetentIndex(for: raw)))
        let delta = raw - target
        guard abs(delta) < magneticRadius else { return raw }
        let normalized = abs(delta) / magneticRadius
        let resistance = 0.28 + 0.72 * normalized * normalized
        return target + delta * resistance
    }

    private func snap(to target: VaultLanguage) {
        let destination = detentOffset(for: target)
        if reduceMotion {
            knobOffset = destination
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.70, blendDuration: 0.08)) {
                knobOffset = destination
            }
        }
    }

    private func dismiss() {
        if reduceMotion {
            isPresented = false
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isPresented = false
            }
        }
    }
}
