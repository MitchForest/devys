public import SwiftUI

/// Continuous corners. Controls are capsules; cards 16; the workspace 14.
nonisolated public enum DevysRadius {
    public static let workspace: CGFloat = 14
    public static let card: CGFloat = 16
    public static let sheet: CGFloat = 22
}

nonisolated public enum DevysSpacing {
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let regular: CGFloat = 16
    public static let roomy: CGFloat = 24
    public static let section: CGFloat = 32
    public static let page: CGFloat = 40
}

/// Two elevations only.
public enum DevysElevation {
    /// Pills, hovered cards, the selected tab.
    case resting
    /// Menus, popovers, palettes.
    case raised
}

extension View {
    public func devysElevation(_ level: DevysElevation) -> some View {
        modifier(ElevationModifier(level: level))
    }
}

private struct ElevationModifier: ViewModifier {
    let level: DevysElevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let strength = scheme == .dark ? 4.0 : 1.0
        switch level {
        case .resting:
            content
                .shadow(color: .black.opacity(0.04 * strength), radius: 0.5, y: 1)
                .shadow(color: .black.opacity(0.05 * strength), radius: 4, y: 2)
        case .raised:
            content
                .shadow(color: .black.opacity(0.06 * strength), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.10 * strength), radius: 15, y: 10)
        }
    }
}

/// Spring presets. Components read Reduce Motion and fall back to a crossfade.
public enum DevysMotion {
    /// Sidebar pill and tab thumb: a soft spring with slight overshoot.
    public static let select = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// New content rising into place.
    public static let arrive = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// Panels opening and closing.
    public static let panel = Animation.spring(response: 0.42, dampingFraction: 0.86)
    public static let quick = Animation.easeOut(duration: 0.18)

    public static func select(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : select
    }
}
