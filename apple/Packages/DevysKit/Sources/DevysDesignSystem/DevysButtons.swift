public import SwiftUI

/// Aurora sends an agent to work or signs a decision; raised is the default
/// secondary; quiet sits in toolbars; dashed fills a slot that isn't real yet.
public struct DevysButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        case aurora, raised, quiet, dashed
    }

    let kind: Kind
    let compact: Bool

    public init(_ kind: Kind, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        DevysButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

extension ButtonStyle where Self == DevysButtonStyle {
    public static var aurora: DevysButtonStyle { DevysButtonStyle(.aurora) }
    public static var raised: DevysButtonStyle { DevysButtonStyle(.raised) }
    public static var quiet: DevysButtonStyle { DevysButtonStyle(.quiet) }
    public static var dashed: DevysButtonStyle { DevysButtonStyle(.dashed) }
}

private struct DevysButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DevysButtonStyle.Kind
    let compact: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(DevysTypography.control)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 8)
            .background { background }
            .overlay { if kind == .dashed { Capsule().strokeBorder(DevysColors.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
            .contentShape(Capsule())
            .modifier(Lift(active: kind == .raised || kind == .aurora, hovering: hovering && isEnabled))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(DevysMotion.quick, value: configuration.isPressed)
            .animation(DevysMotion.quick, value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .aurora: .white
        case .raised: DevysColors.ink
        case .quiet, .dashed: DevysColors.ink2
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .aurora:
            Aurora()
                .overlay {
                    // One sheen sweep per hover; Reduce Motion skips it.
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 60)
                        .offset(x: hovering && !reduceMotion ? 120 : -120)
                        .animation(hovering ? .easeOut(duration: 0.7) : nil, value: hovering)
                }
                .overlay(alignment: .top) { Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5).blendMode(.plusLighter) }
                .clipShape(Capsule())
                .shadow(color: DevysColors.auroraIndigo.opacity(0.35), radius: 8, y: 4)
        case .raised:
            Capsule().fill(DevysColors.sheet).devysElevation(.resting)
        case .quiet:
            Capsule().fill(hovering ? DevysColors.track : .clear)
        case .dashed:
            Color.clear
        }
    }
}

private struct Lift: ViewModifier {
    let active: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        content.offset(y: active && hovering ? -1 : 0)
    }
}

/// A 30pt square toolbar icon button with a quiet hover fill.
public struct ToolbarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    public init(_ label: String, symbol: String, action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? DevysColors.ink : DevysColors.ink2)
                .frame(width: 30, height: 30)
                .background(hovering ? DevysColors.track : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DevysMotion.quick, value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}
