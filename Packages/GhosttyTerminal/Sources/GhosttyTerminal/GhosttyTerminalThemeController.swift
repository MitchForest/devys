import Foundation

#if canImport(GhosttyKit) && os(macOS)
@MainActor
public enum GhosttyTerminalThemeController {
    public static func apply(_ appearance: GhosttyTerminalAppearance) {
        GhosttyAppBridge.shared.applyAppearance(appearance)
    }
}
#endif
