import Foundation
import simd

public enum GhosttyTerminalColorScheme: Sendable, Equatable {
    case light
    case dark
}

public struct GhosttyTerminalColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6, let value = UInt32(normalized, radix: 16) else {
            self = .black
            return
        }

        self.init(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    public static let black = GhosttyTerminalColor(red: 0, green: 0, blue: 0)
    public static let white = GhosttyTerminalColor(red: 255, green: 255, blue: 255)

    public var packedRGB: UInt32 {
        (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }

    public func blended(
        over background: GhosttyTerminalColor,
        opacity: Double
    ) -> GhosttyTerminalColor {
        let clampedOpacity = min(max(opacity, 0), 1)
        let inverseOpacity = 1 - clampedOpacity
        return GhosttyTerminalColor(
            red: blendedComponent(
                foreground: red,
                background: background.red,
                opacity: clampedOpacity,
                inverseOpacity: inverseOpacity
            ),
            green: blendedComponent(
                foreground: green,
                background: background.green,
                opacity: clampedOpacity,
                inverseOpacity: inverseOpacity
            ),
            blue: blendedComponent(
                foreground: blue,
                background: background.blue,
                opacity: clampedOpacity,
                inverseOpacity: inverseOpacity
            )
        )
    }

    public func contrastRatio(with other: GhosttyTerminalColor) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public func idealTextColor(
        light: GhosttyTerminalColor = .white,
        dark: GhosttyTerminalColor = .black
    ) -> GhosttyTerminalColor {
        contrastRatio(with: dark) >= contrastRatio(with: light) ? dark : light
    }

    public func linearRGBA(alpha: Float = 1) -> SIMD4<Float> {
        SIMD4<Float>(
            srgbToLinear(Float(red) / 255),
            srgbToLinear(Float(green) / 255),
            srgbToLinear(Float(blue) / 255),
            alpha
        )
    }

    private var relativeLuminance: Double {
        componentLuminance(red) * 0.2126
            + componentLuminance(green) * 0.7152
            + componentLuminance(blue) * 0.0722
    }

    private func componentLuminance(_ component: UInt8) -> Double {
        let normalized = Double(component) / 255
        if normalized <= 0.03928 {
            return normalized / 12.92
        }

        return pow((normalized + 0.055) / 1.055, 2.4)
    }

    private func blendedComponent(
        foreground: UInt8,
        background: UInt8,
        opacity: Double,
        inverseOpacity: Double
    ) -> UInt8 {
        let mixed = (Double(foreground) * opacity) + (Double(background) * inverseOpacity)
        return UInt8(clamping: Int(mixed.rounded()))
    }
}

public struct GhosttyTerminalAppearance: Sendable, Equatable {
    public let colorScheme: GhosttyTerminalColorScheme
    public let background: GhosttyTerminalColor
    public let foreground: GhosttyTerminalColor
    public let cursorColor: GhosttyTerminalColor
    public let selectionBackground: GhosttyTerminalColor
    public let palette: [GhosttyTerminalColor]

    public init(
        colorScheme: GhosttyTerminalColorScheme,
        background: GhosttyTerminalColor,
        foreground: GhosttyTerminalColor,
        cursorColor: GhosttyTerminalColor,
        selectionBackground: GhosttyTerminalColor,
        palette: [GhosttyTerminalColor]? = nil
    ) {
        if let palette {
            precondition(
                palette.count == 16,
                "Ghostty terminal ANSI palette must contain exactly 16 colors."
            )
        }
        self.colorScheme = colorScheme
        self.background = background
        self.foreground = foreground
        self.cursorColor = cursorColor
        self.selectionBackground = selectionBackground
        self.palette = palette ?? Self.defaultPalette(for: colorScheme)
    }

    public static let defaultDark = GhosttyTerminalAppearance(
        colorScheme: .dark,
        background: .rgb(40, 44, 52),
        foreground: .rgb(255, 255, 255),
        cursorColor: .rgb(255, 255, 255),
        selectionBackground: .rgb(63, 99, 139)
    )

    public static let defaultLight = GhosttyTerminalAppearance(
        colorScheme: .light,
        background: .rgb(254, 255, 255),
        foreground: .rgb(0, 0, 0),
        cursorColor: .rgb(0, 0, 0),
        selectionBackground: .rgb(171, 216, 255)
    )

    public static let ghosttyDarkPalette: [GhosttyTerminalColor] = [
        .rgb(29, 31, 33),
        .rgb(204, 102, 102),
        .rgb(181, 189, 104),
        .rgb(240, 198, 116),
        .rgb(129, 162, 190),
        .rgb(178, 148, 187),
        .rgb(138, 190, 183),
        .rgb(197, 200, 198),
        .rgb(102, 102, 102),
        .rgb(213, 78, 83),
        .rgb(185, 202, 74),
        .rgb(231, 197, 71),
        .rgb(122, 166, 218),
        .rgb(195, 151, 216),
        .rgb(112, 192, 177),
        .rgb(234, 234, 234),
    ]

    public static let ghosttyLightPalette: [GhosttyTerminalColor] = [
        .rgb(26, 26, 26),
        .rgb(204, 55, 46),
        .rgb(38, 164, 57),
        .rgb(205, 172, 8),
        .rgb(8, 105, 203),
        .rgb(150, 71, 191),
        .rgb(71, 158, 194),
        .rgb(152, 152, 157),
        .rgb(70, 70, 70),
        .rgb(255, 69, 58),
        .rgb(50, 215, 75),
        .rgb(229, 188, 0),
        .rgb(10, 132, 255),
        .rgb(191, 90, 242),
        .rgb(105, 201, 242),
        .rgb(255, 255, 255),
    ]

    private static func defaultPalette(
        for colorScheme: GhosttyTerminalColorScheme
    ) -> [GhosttyTerminalColor] {
        switch colorScheme {
        case .dark:
            ghosttyDarkPalette
        case .light:
            ghosttyLightPalette
        }
    }
}

private extension GhosttyTerminalColor {
    static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> GhosttyTerminalColor {
        GhosttyTerminalColor(red: red, green: green, blue: blue)
    }
}

private func srgbToLinear(_ value: Float) -> Float {
    if value <= 0.04045 {
        return value / 12.92
    }
    return pow((value + 0.055) / 1.055, 2.4)
}
