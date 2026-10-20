public import TerminalCore

public enum TerminalSurfaceInputCommand: Sendable, Equatable {
    case key(GhosttyTerminalKeyEvent)
    case paste(String)
    case submitText(String)
}
