import SwiftUI

public enum LiquidGlassSurfaceShape: Sendable {
    case roundedRectangle
    case capsule
}

public enum LiquidGlassSurfaceProminence: Sendable {
    case regular
    case prominent
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme

    let shape: LiquidGlassSurfaceShape
    let prominence: LiquidGlassSurfaceProminence
    let isInteractive: Bool

    func body(content: Content) -> some View {
        glassContent(content)
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
        switch shape {
        case .roundedRectangle:
            content
                .glassEffect(glass, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        case .capsule:
            content
                .glassEffect(glass, in: Capsule())
        }
    }

    private var glass: Glass {
        let base: Glass
        switch prominence {
        case .regular:
            base = .regular
        case .prominent:
            base = .regular.tint(theme.accent)
        }
        return base.interactive(isInteractive)
    }
}

/// Groups child glass surfaces so they morph fluidly into one another.
///
/// Use this around composers, button clusters, and any region where adjacent
/// glass elements should read as a single volume.
public struct DevysGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

public extension View {
    func liquidGlassSurface(
        shape: LiquidGlassSurfaceShape = .roundedRectangle,
        prominence: LiquidGlassSurfaceProminence = .regular,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                shape: shape,
                prominence: prominence,
                isInteractive: isInteractive
            )
        )
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
