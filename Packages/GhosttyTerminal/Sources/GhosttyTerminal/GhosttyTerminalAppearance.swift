import Foundation

#if canImport(GhosttyKit) && os(macOS)
import GhosttyKit

public enum GhosttyTerminalColorScheme: Sendable, Equatable {
    case light
    case dark

    var ghosttyValue: ghostty_color_scheme_e {
        switch self {
        case .light:
            GHOSTTY_COLOR_SCHEME_LIGHT
        case .dark:
            GHOSTTY_COLOR_SCHEME_DARK
        }
    }
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

    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public func blended(over background: GhosttyTerminalColor, opacity: Double) -> GhosttyTerminalColor {
        let clampedOpacity = min(max(opacity, 0), 1)
        let inverseOpacity = 1 - clampedOpacity
        let redValue = blendedComponent(
            foreground: red,
            background: background.red,
            opacity: clampedOpacity,
            inverseOpacity: inverseOpacity
        )
        let greenValue = blendedComponent(
            foreground: green,
            background: background.green,
            opacity: clampedOpacity,
            inverseOpacity: inverseOpacity
        )
        let blueValue = blendedComponent(
            foreground: blue,
            background: background.blue,
            opacity: clampedOpacity,
            inverseOpacity: inverseOpacity
        )

        return GhosttyTerminalColor(
            red: redValue,
            green: greenValue,
            blue: blueValue
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
    public let cursorText: GhosttyTerminalColor
    public let selectionBackground: GhosttyTerminalColor
    public let selectionForeground: GhosttyTerminalColor
    public let palette: [GhosttyTerminalColor]

    public init(
        colorScheme: GhosttyTerminalColorScheme,
        background: GhosttyTerminalColor,
        foreground: GhosttyTerminalColor,
        cursorColor: GhosttyTerminalColor,
        cursorText: GhosttyTerminalColor,
        selectionBackground: GhosttyTerminalColor,
        selectionForeground: GhosttyTerminalColor,
        palette: [GhosttyTerminalColor]
    ) {
        precondition(palette.count == 16, "Ghostty terminal palette must contain exactly 16 colors.")
        self.colorScheme = colorScheme
        self.background = background
        self.foreground = foreground
        self.cursorColor = cursorColor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.palette = palette
    }

    public static let defaultDark = GhosttyTerminalAppearance(
        colorScheme: .dark,
        background: GhosttyTerminalColor(red: 0, green: 0, blue: 0),
        foreground: GhosttyTerminalColor(red: 239, green: 239, blue: 239),
        cursorColor: GhosttyTerminalColor(red: 239, green: 239, blue: 239),
        cursorText: .black,
        selectionBackground: GhosttyTerminalColor(red: 46, green: 46, blue: 46),
        selectionForeground: GhosttyTerminalColor(red: 239, green: 239, blue: 239),
        palette: [
            GhosttyTerminalColor(red: 18, green: 18, blue: 18),
            GhosttyTerminalColor(red: 224, green: 108, blue: 117),
            GhosttyTerminalColor(red: 152, green: 195, blue: 121),
            GhosttyTerminalColor(red: 229, green: 192, blue: 123),
            GhosttyTerminalColor(red: 97, green: 175, blue: 239),
            GhosttyTerminalColor(red: 198, green: 120, blue: 221),
            GhosttyTerminalColor(red: 86, green: 182, blue: 194),
            GhosttyTerminalColor(red: 160, green: 160, blue: 160),
            GhosttyTerminalColor(red: 102, green: 102, blue: 102),
            GhosttyTerminalColor(red: 255, green: 138, blue: 147),
            GhosttyTerminalColor(red: 180, green: 226, blue: 143),
            GhosttyTerminalColor(red: 255, green: 208, blue: 138),
            GhosttyTerminalColor(red: 123, green: 195, blue: 255),
            GhosttyTerminalColor(red: 209, green: 154, blue: 238),
            GhosttyTerminalColor(red: 123, green: 223, blue: 242),
            GhosttyTerminalColor(red: 239, green: 239, blue: 239),
        ]
    )

    var configText: String {
        var lines = palette.enumerated().map { index, color in
            "palette = \(index)=\(color.hexString)"
        }
        lines.append("background = \(background.hexString)")
        lines.append("foreground = \(foreground.hexString)")
        lines.append("cursor-color = \(cursorColor.hexString)")
        lines.append("cursor-text = \(cursorText.hexString)")
        lines.append("selection-background = \(selectionBackground.hexString)")
        lines.append("selection-foreground = \(selectionForeground.hexString)")
        return lines.joined(separator: "\n") + "\n"
    }
}

#endif
