public import TerminalVT

/// Resolves a terminal appearance from host theme primitives. The host
/// layer (DevysPackage) maps its design-system tokens to packed terminal
/// colors before calling in; ComputerKit stays design-system-neutral
/// (the P0-013 rule: colors are packed RGB from TerminalVT).
public enum TerminalSurfaceAppearanceResolver {
    public static func appearance(
        colorScheme: TerminalColorScheme,
        background: TerminalColor,
        foreground requestedForeground: TerminalColor
    ) -> TerminalAppearance {
        let defaults = colorScheme == .dark
            ? TerminalAppearance.defaultDark
            : TerminalAppearance.defaultLight
        let foreground = readableForeground(
            requestedForeground,
            background: background,
            colorScheme: colorScheme
        )

        return TerminalAppearance(
            colorScheme: colorScheme,
            background: background,
            foreground: foreground,
            cursorColor: foreground,
            selectionBackground: selectionBackground(for: colorScheme),
            palette: defaults.palette,
            backgroundOpacity: 0
        )
    }

    private static func readableForeground(
        _ foreground: TerminalColor,
        background: TerminalColor,
        colorScheme: TerminalColorScheme
    ) -> TerminalColor {
        guard foreground.contrastRatio(with: background) < 7 else {
            return foreground
        }

        switch colorScheme {
        case .dark:
            return .white
        case .light:
            return .black
        }
    }

    private static func selectionBackground(
        for colorScheme: TerminalColorScheme
    ) -> TerminalColor {
        switch colorScheme {
        case .dark:
            TerminalColor(red: 42, green: 96, blue: 154)
        case .light:
            TerminalColor(red: 178, green: 212, blue: 255)
        }
    }
}
