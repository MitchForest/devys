import GhosttyTerminalCore
import SwiftUI
import UI

struct IOSGhosttyTerminalAccessoryRow: View {
    let isCtrlLatched: Bool
    let isAltLatched: Bool
    let isSelectionMode: Bool
    let onToggleCtrl: () -> Void
    let onToggleAlt: () -> Void
    let onToggleSelectionMode: () -> Void
    let onKeyPress: (GhosttyTerminalSpecialKey) -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onTop: () -> Void
    let onBottom: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.space2) {
                TerminalAccessoryKey(
                    style: .glyph("⌃"),
                    isLatched: isCtrlLatched,
                    action: onToggleCtrl
                )
                TerminalAccessoryKey(
                    style: .glyph("⌥"),
                    isLatched: isAltLatched,
                    action: onToggleAlt
                )
                TerminalAccessoryKey(
                    style: .icon("selection.pin.in.out"),
                    isLatched: isSelectionMode,
                    action: onToggleSelectionMode
                )

                TerminalAccessoryKey(style: .glyph("esc")) { onKeyPress(.escape) }
                TerminalAccessoryKey(style: .icon("arrow.right.to.line.compact")) { onKeyPress(.tab) }
                TerminalAccessoryKey(style: .icon("arrow.up")) { onKeyPress(.up) }
                TerminalAccessoryKey(style: .icon("arrow.down")) { onKeyPress(.down) }
                TerminalAccessoryKey(style: .icon("arrow.left")) { onKeyPress(.left) }
                TerminalAccessoryKey(style: .icon("arrow.right")) { onKeyPress(.right) }
                TerminalAccessoryKey(style: .glyph("pgup")) { onKeyPress(.pageUp) }
                TerminalAccessoryKey(style: .glyph("pgdn")) { onKeyPress(.pageDown) }
                TerminalAccessoryKey(style: .icon("arrow.up.to.line")) { onKeyPress(.home) }
                TerminalAccessoryKey(style: .icon("arrow.down.to.line")) { onKeyPress(.end) }
                TerminalAccessoryKey(style: .glyph("⌃C"), tone: .warning) { onKeyPress(.interrupt) }

                TerminalAccessoryKey(style: .icon("doc.on.doc"), action: onCopy)
                TerminalAccessoryKey(style: .icon("doc.on.clipboard"), action: onPaste)
                TerminalAccessoryKey(style: .icon("chevron.up.2"), action: onTop)
                TerminalAccessoryKey(style: .icon("chevron.down.2"), action: onBottom)
            }
        }
    }
}

struct TerminalAccessoryKey: View {
    enum Style {
        case glyph(String)
        case icon(String)
    }

    enum Tone {
        case standard
        case warning
    }

    @Environment(\.theme) private var theme

    let style: Style
    var isLatched: Bool = false
    var tone: Tone = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(minWidth: 36, minHeight: 30)
                .padding(.horizontal, Spacing.space2)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: Spacing.borderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .glyph(let text):
            Text(text)
                .font(Typography.label.weight(.medium))
                .foregroundStyle(foreground)
        case .icon(let name):
            Icon(name, size: .custom(13), color: foreground)
        }
    }

    private var foreground: Color {
        if tone == .warning { return theme.warning }
        if isLatched { return theme.primaryFillForeground }
        return theme.text
    }

    private var background: Color {
        if isLatched { return theme.accent }
        return theme.overlay
    }

    private var borderColor: Color {
        if isLatched { return theme.accent }
        return theme.border
    }
}
