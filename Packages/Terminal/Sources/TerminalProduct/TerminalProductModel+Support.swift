import Foundation
import TerminalComposer
import TerminalVT
import UI

extension TerminalProductModel {
    static func defaultWindowTitle() -> String {
        let basename = defaultWorkingDirectoryURL().lastPathComponent
        return basename.isEmpty ? "~" : basename
    }

    static func defaultWorkingDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    static func defaultWorkingDirectoryBasename() -> String {
        workingDirectoryBasename(for: defaultWorkingDirectoryURL())
    }

    static func workingDirectoryBasename(for url: URL) -> String {
        let basename = url.standardizedFileURL.lastPathComponent
        return basename.isEmpty ? "~" : basename
    }

    static func normalizedWorkingDirectoryURL(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/"),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func normalizedForegroundProcessName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else { return nil }

        let lowercasedName = trimmedName.lowercased()
        if Self.shellProcessNames.contains(lowercasedName) {
            return nil
        }

        return trimmedName
    }

    static func defaultComposerMetadata() -> TerminalComposerTargetMetadata {
        TerminalComposerTargetMetadata(cwdBasename: defaultWorkingDirectoryBasename())
    }

    static var defaultTerminalAppearance: TerminalAppearance {
        terminalAppearance(for: Theme(isDark: true))
    }

    func applyTheme(_ theme: Theme) {
        updateAppearance(Self.terminalAppearance(for: theme))
    }

    func applyTheme(isDark: Bool) {
        applyTheme(Theme(isDark: isDark))
    }

    static func terminalAppearance(for theme: Theme) -> TerminalAppearance {
        let background = theme.isDark
            ? TerminalColor(red: 28, green: 27, blue: 25)
            : TerminalColor(red: 255, green: 255, blue: 255)
        let foreground = theme.isDark
            ? TerminalColor(red: 255, green: 255, blue: 255)
            : TerminalColor(red: 0, green: 0, blue: 0)
        let fallbackSelection = theme.isDark
            ? TerminalColor(red: 34, green: 33, blue: 32)
            : TerminalColor(red: 228, green: 225, blue: 220)
        let accent = TerminalColor(hex: theme.accentColor.rawValue)

        let cursorColor = accent.contrastRatio(with: background) >= 2.5 ? accent : foreground
        let selectionCandidate = accent.blended(
            over: background,
            opacity: theme.isDark ? 0.22 : 0.18
        )
        let selectionBackground = selectionCandidate.contrastRatio(with: background) >= 1.12
            ? selectionCandidate
            : fallbackSelection

        return TerminalAppearance(
            colorScheme: theme.isDark ? .dark : .light,
            background: background,
            foreground: foreground,
            cursorColor: cursorColor,
            selectionBackground: selectionBackground,
            palette: theme.isDark
                ? TerminalAppearance.terminalDarkPalette
                : TerminalAppearance.terminalLightPalette,
            backgroundOpacity: 0
        )
    }

    func setWindowFocused(_ isFocused: Bool) {
        isTerminalWindowFocused = isFocused
        if isFocused {
            focusTerminal()
        }
    }

    func activateTerminalTarget() {
        guard !hasTerminalExited else { return }
        composer.setVisibleTargetIDs([terminalTargetID])
        composer.activateTarget(terminalTargetID)
    }

    func markTerminalExited() {
        hasTerminalExited = true
        closeRisk = nil
        composer.setVisibleTargetIDs([])
        if agentContext.match != nil {
            agentContext.activity = .exited
        }
        stopForegroundProbe()
    }

    private static let shellProcessNames: Set<String> = [
        "bash",
        "csh",
        "fish",
        "login",
        "sh",
        "tcsh",
        "zsh",
    ]

}

struct TerminalViewport: Equatable {
    var cols: Int
    var rows: Int
    var cellWidthPx: Int
    var cellHeightPx: Int
}
