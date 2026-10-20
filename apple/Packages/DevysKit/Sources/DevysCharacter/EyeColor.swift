/// RGB components of an eye color. Pure values so the dual light/dark
/// mapping stays testable without SwiftUI.
public struct EyeColorRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension AvatarPalette {
    /// The eyes on a light tile: vivid ink, readable on white.
    public var eyeInk: EyeColorRGB {
        switch self {
        case .brown: EyeColorRGB(red: 0.54, green: 0.40, blue: 0.27)
        case .red: EyeColorRGB(red: 0.85, green: 0.31, blue: 0.34)
        case .orange: EyeColorRGB(red: 0.88, green: 0.42, blue: 0.18)
        case .amber: EyeColorRGB(red: 0.85, green: 0.60, blue: 0.15)
        case .green: EyeColorRGB(red: 0.25, green: 0.60, blue: 0.31)
        case .teal: EyeColorRGB(red: 0.18, green: 0.62, blue: 0.55)
        case .blue: EyeColorRGB(red: 0.21, green: 0.47, blue: 0.85)
        case .purple: EyeColorRGB(red: 0.48, green: 0.39, blue: 0.85)
        case .pink: EyeColorRGB(red: 0.85, green: 0.29, blue: 0.54)
        case .gray: EyeColorRGB(red: 0.43, green: 0.45, blue: 0.49)
        }
    }

    /// The eyes on a dark tile: luminous, brightened for the dark coin.
    public var eyeGlow: EyeColorRGB {
        switch self {
        case .brown: EyeColorRGB(red: 0.85, green: 0.66, blue: 0.48)
        case .red: EyeColorRGB(red: 1.0, green: 0.55, blue: 0.55)
        case .orange: EyeColorRGB(red: 1.0, green: 0.62, blue: 0.42)
        case .amber: EyeColorRGB(red: 1.0, green: 0.76, blue: 0.30)
        case .green: EyeColorRGB(red: 0.49, green: 0.91, blue: 0.49)
        case .teal: EyeColorRGB(red: 0.30, green: 0.88, blue: 0.75)
        case .blue: EyeColorRGB(red: 0.55, green: 0.75, blue: 1.0)
        case .purple: EyeColorRGB(red: 0.79, green: 0.66, blue: 1.0)
        case .pink: EyeColorRGB(red: 1.0, green: 0.61, blue: 0.85)
        case .gray: EyeColorRGB(red: 0.80, green: 0.83, blue: 0.86)
        }
    }
}
