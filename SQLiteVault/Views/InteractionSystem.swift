import SwiftUI
import UIKit

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
}

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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.28, dampingFraction: configuration.isPressed ? 0.86 : 0.58),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { VaultHaptics.press() }
            }
    }
}

struct InteractiveTiltPanel<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pitch = 0.0
    @State private var yaw = 0.0
    @State private var touch = UnitPoint.center
    @State private var pressed = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        content = content()
    }

    var body: some View {
        content
            .overlay {
                RadialGradient(
                    colors: [.white.opacity(pressed ? 0.34 : 0.08), .clear],
                    center: touch,
                    startRadius: 0,
                    endRadius: 210
                )
                .clipShape(RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .scaleEffect(pressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        if !pressed { VaultHaptics.press() }
                        pressed = true
                        let nx = min(max(value.location.x / 260, 0), 1)
                        let ny = min(max(value.location.y / 150, 0), 1)
                        touch = UnitPoint(x: nx, y: ny)
                        yaw = (nx - 0.5) * 8
                        pitch = (0.5 - ny) * 8
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.46, dampingFraction: 0.56)) {
                            pitch = 0
                            yaw = 0
                            touch = .center
                            pressed = false
                        }
                    }
            )
    }
}

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
                lineWidth: 1.25
            )
            .shadow(color: .cyan.opacity(0.30), radius: 10)
            .shadow(color: .indigo.opacity(0.20), radius: 20)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
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
            .offset(y: appeared ? 0 : 22)
            .scaleEffect(appeared ? 1 : 0.965)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.70).delay(Double(index) * 0.055)) {
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
                        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: selectedIndex)
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
                                .shadow(color: Color.accentColor.opacity(index == selectedIndex ? 0.45 : 0), radius: 8)
                                .position(points[index])
                                .animation(.spring(response: 0.30, dampingFraction: 0.62), value: selectedIndex)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
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
        .overlay { DynamicGlowBorder(shape: RoundedRectangle(cornerRadius: VaultDesign.cardRadius, style: .continuous)) }
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

struct VaultBottomDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    let content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 14) {
                    Capsule()
                        .fill(.secondary.opacity(0.42))
                        .frame(width: 42, height: 5)
                        .padding(.top, 10)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay { DynamicGlowBorder(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)) }
                .padding(.horizontal, 12)
                .offset(y: rubberBandedOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = value.translation.height }
                        .onEnded { value in
                            if value.predictedEndTranslation.height > 150 || value.translation.height > 90 {
                                dismiss()
                            } else {
                                VaultHaptics.selection()
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.66)) { dragOffset = 0 }
                            }
                        }
                )
            }
            .zIndex(100)
        }
    }

    private var rubberBandedOffset: CGFloat {
        dragOffset >= 0 ? dragOffset : -sqrt(abs(dragOffset)) * 4
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.78)) {
            dragOffset = 0
            isPresented = false
        }
    }
}
