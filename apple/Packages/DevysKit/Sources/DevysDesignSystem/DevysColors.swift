public import SwiftUI

/// Devys color tokens (.docs/design/direction): neutrals carry the interface,
/// semantic hues mean an outcome, and the aurora means an agent is acting.
/// Views never construct raw colors; every token adapts to light and dark.
public enum DevysColors {
    /// The window frame: toolbar and rail.
    public static let frame = Color(light: 0xECECEF, dark: 0x141417)
    /// The workspace and page surface.
    public static let sheet = Color(light: 0xFFFFFF, dark: 0x1E1E23)
    /// Sidebar fill and resting cards inside a sheet.
    public static let sheetTint = Color(light: 0xF7F7F9, dark: 0x25252B)
    /// Inset tracks: search, hover fills, chat bubbles.
    public static let track = Color(light: 0xE2E2E7, dark: 0x2A2A31)
    /// The lighter well behind segmented controls.
    public static let well = Color(light: 0xF0F0F3, dark: 0x26262C)
    public static let ink = Color(light: 0x1B1B20, dark: 0xF1F1F4)
    public static let ink2 = Color(light: 0x5D5D68, dark: 0xA9A9B4)
    public static let ink3 = Color(light: 0x9B9BA6, dark: 0x6E6E7A)
    /// The only divider: between workspace panes.
    public static let hairline = Color(light: 0x16162C, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)

    public static let indigo = Color(light: 0x5A68F0, dark: 0x7B87FF)
    public static let amber = Color(light: 0xD99A14, dark: 0xF0B43A)
    public static let green = Color(light: 0x2EA25A, dark: 0x3CC46E)
    public static let red = Color(light: 0xE0564E, dark: 0xFF6B62)
    public static let gray = Color(light: 0xA0A0AA, dark: 0x7A7A86)
    public static let greenTint = Color(light: 0xDCF3E3, dark: 0x1D3526)

    public static let auroraPeach = Color(light: 0xF6B07A, dark: 0xF6B07A)
    public static let auroraRose = Color(light: 0xEC6AA6, dark: 0xEC6AA6)
    public static let auroraIndigo = Color(light: 0x5A68F0, dark: 0x6E7BFF)

    /// The Face's coin.
    public static let avatarTile = sheet
}

/// Reserved for agency: Ask, Approve, Send. At most once per view.
public struct Aurora: View {
    public init() {}

    public var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.45, 0.55], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                DevysColors.auroraPeach, DevysColors.auroraPeach, DevysColors.auroraRose,
                DevysColors.auroraPeach, DevysColors.auroraRose, DevysColors.auroraIndigo,
                DevysColors.auroraRose, DevysColors.auroraIndigo, DevysColors.auroraIndigo
            ]
        )
    }
}

extension Color {
    /// An appearance-adaptive color from two sRGB hex values.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        #if os(macOS)
            self.init(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: dark, alpha: darkAlpha)
                    : NSColor(hex: light, alpha: lightAlpha)
            })
        #else
            self.init(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, alpha: darkAlpha)
                    : UIColor(hex: light, alpha: lightAlpha)
            })
        #endif
    }
}

#if os(macOS)
    extension NSColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }
#else
    extension UIColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }
#endif
