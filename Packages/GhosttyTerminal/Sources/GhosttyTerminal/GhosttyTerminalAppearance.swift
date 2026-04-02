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
        background: GhosttyTerminalColor(hex: "#000000"),
        foreground: GhosttyTerminalColor(hex: "#EFEFEF"),
        cursorColor: GhosttyTerminalColor(hex: "#EFEFEF"),
        cursorText: .black,
        selectionBackground: GhosttyTerminalColor(hex: "#2E2E2E"),
        selectionForeground: GhosttyTerminalColor(hex: "#EFEFEF"),
        palette: [
            GhosttyTerminalColor(hex: "#121212"),
            GhosttyTerminalColor(hex: "#E06C75"),
            GhosttyTerminalColor(hex: "#98C379"),
            GhosttyTerminalColor(hex: "#E5C07B"),
            GhosttyTerminalColor(hex: "#61AFEF"),
            GhosttyTerminalColor(hex: "#C678DD"),
            GhosttyTerminalColor(hex: "#56B6C2"),
            GhosttyTerminalColor(hex: "#A0A0A0"),
            GhosttyTerminalColor(hex: "#666666"),
            GhosttyTerminalColor(hex: "#FF8A93"),
            GhosttyTerminalColor(hex: "#B4E28F"),
            GhosttyTerminalColor(hex: "#FFD08A"),
            GhosttyTerminalColor(hex: "#7BC3FF"),
            GhosttyTerminalColor(hex: "#D19AEE"),
            GhosttyTerminalColor(hex: "#7BDFF2"),
            GhosttyTerminalColor(hex: "#EFEFEF"),
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
