public import SwiftUI
public import TerminalSurfaceCore
import TerminalVT

/// A live terminal: the Ghostty host view over a surface runtime, in Devys's sheet colours. The
/// runtime's PTY is whatever the caller gives it; in Devys, a session on the Mac host.
public struct TerminalScreen: View {
    private let runtime: TerminalSurfaceRuntime
    private let focusRequestID: Int
    @Environment(\.colorScheme) private var colorScheme

    public init(runtime: TerminalSurfaceRuntime, focusRequestID: Int = 0) {
        self.runtime = runtime
        self.focusRequestID = focusRequestID
    }

    public var body: some View {
        let appearance = self.appearance
        GhosttyTerminalView(
            renderSession: runtime.renderSession,
            appearance: appearance,
            fontSize: TerminalSurfaceDefaults.fontSize,
            focusRequestID: focusRequestID + runtime.focusGeneration,
            onSelectionBegin: { runtime.selectionBegin(row: $0, col: $1) },
            onSelectionMove: { runtime.selectionMove(row: $0, col: $1) },
            onSelectionEnd: { runtime.selectionEnd() },
            onSelectWord: { runtime.selectWord(row: $0, col: $1) },
            onClearSelection: { runtime.clearSelection() },
            onScroll: { runtime.scroll($0) },
            onSurfaceSizeChange: {
                runtime.updateAppearance(self.appearance)
                runtime.setSurfaceSize($0)
            },
            onInput: { runtime.sendInput($0) },
            selectionTextProvider: { runtime.selectionText() }
        )
        .task {
            runtime.updateAppearance(appearance)
            runtime.startIfNeeded()
        }
        .onChange(of: colorScheme) { runtime.updateAppearance(self.appearance) }
        .background(colorScheme == .dark ? Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x23 / 255) : .white)
    }

    /// The sheet colours of the Devys design system (DevysColors.sheet and ink).
    private var appearance: TerminalAppearance {
        colorScheme == .dark
            ? TerminalSurfaceAppearanceResolver.appearance(
                colorScheme: .dark,
                background: TerminalColor(red: 0x1E, green: 0x1E, blue: 0x23),
                foreground: TerminalColor(red: 0xE8, green: 0xE8, blue: 0xEE)
            )
            : TerminalSurfaceAppearanceResolver.appearance(
                colorScheme: .light,
                background: TerminalColor(red: 0xFF, green: 0xFF, blue: 0xFF),
                foreground: TerminalColor(red: 0x1B, green: 0x1B, blue: 0x20)
            )
    }
}
