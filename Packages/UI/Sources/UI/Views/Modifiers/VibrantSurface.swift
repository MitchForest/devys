import SwiftUI
import AppKit

private struct VibrantRoundedTreatment: ViewModifier {
    @Environment(\.theme) private var theme
    let elevation: Elevation

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        content
            .background(surfaceBackground)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: Spacing.borderWidth)
            }
            .shadowStyle(shadow)
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        DevysVisualEffectBackground(material: material)
            .background(fillColor.opacity(0.62))
    }

    private var fillColor: Color {
        switch elevation {
        case .base:
            theme.base
        case .card:
            theme.card
        case .popover, .overlay:
            theme.overlay
        }
    }

    private var borderColor: Color {
        elevation == .base ? .clear : theme.border
    }

    private var shadow: ShadowStyle {
        switch elevation {
        case .base:
            ShadowStyle(color: .clear, radius: 0, y: 0)
        case .card:
            Shadows.sm
        case .popover:
            Shadows.md
        case .overlay:
            Shadows.lg
        }
    }

    private var material: NSVisualEffectView.Material {
        .hudWindow
    }
}

private struct VibrantCapsuleTreatment: ViewModifier {
    @Environment(\.theme) private var theme
    let elevation: Elevation

    func body(content: Content) -> some View {
        content
            .background(surfaceBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
            }
            .shadowStyle(elevation == .overlay ? Shadows.md : Shadows.sm)
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        DevysVisualEffectBackground(material: material)
            .background(theme.overlay.opacity(0.62))
    }

    private var material: NSVisualEffectView.Material {
        .hudWindow
    }
}

public extension View {
    func vibrantSurface(_ elevation: Elevation) -> some View {
        modifier(VibrantRoundedTreatment(elevation: elevation))
    }

    func vibrantCapsuleSurface(_ elevation: Elevation) -> some View {
        modifier(VibrantCapsuleTreatment(elevation: elevation))
    }
}

/// A vibrant material covering the entire window background, blended against
/// the content *behind* the window (i.e. the desktop wallpaper / Stage Manager).
///
/// Pair this with `NSWindow.isOpaque = false` and `backgroundColor = .clear` so
/// the desktop shows through any gap not covered by an opaque content view —
/// notably the area around floating cards and through the transparent titlebar.
public struct WindowVibrancyBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = Self.preferredMaterial
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = Self.preferredMaterial
    }

    private static var preferredMaterial: NSVisualEffectView.Material {
        .hudWindow
    }
}

private struct DevysVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
