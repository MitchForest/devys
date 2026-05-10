import SwiftUI
import UI
import UniformTypeIdentifiers

enum TerminalComposerLayout {
    static let maxWidth: CGFloat = 720
    static let iconSize: CGFloat = 28
    static let minTextHeight: CGFloat = 28
    static let maxTextHeight: CGFloat = 168
    /// Match `TextEditor`'s internal NSTextContainer `lineFragmentPadding` so the
    /// placeholder sits over the same baseline glyph origin as the caret.
    static let textEditorLeadingInset: CGFloat = 5
    /// `TextEditor` adds ~1pt vertical inset before the first glyph on macOS.
    static let textEditorTopInset: CGFloat = 1
}

struct TerminalComposerKeyboardHint: Identifiable {
    let key: String
    let label: String
    var id: String { "\(key)·\(label)" }
}

struct ComposerIconButton: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var systemName: String
    var accessibilityLabel: String
    var isActive = false
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.body.weight(.medium))
                .foregroundStyle(isActive || isHovered ? theme.text : theme.textSecondary)
                .frame(width: TerminalComposerLayout.iconSize, height: TerminalComposerLayout.iconSize)
                .modifier(ComposerIconButtonBackground(isActive: isActive))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .onHover { hovering in
            withAnimation(Animations.micro) {
                isHovered = hovering
            }
        }
    }
}

private struct ComposerIconButtonBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let isActive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: Capsule())
    }

    private var glass: Glass {
        if isActive {
            return Glass.regular.tint(theme.accent).interactive(true)
        }
        return Glass.regular.interactive(true)
    }
}

struct TerminalComposerInlineWaveformView: View {
    @Environment(\.theme) private var theme

    var level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(theme.text.opacity(0.40 + barHeight(index: index, time: time) * 0.42))
                        .frame(width: 2, height: 6 + barHeight(index: index, time: time) * 14)
                }
            }
            .frame(height: TerminalComposerLayout.iconSize)
            .accessibilityLabel("Dictation audio level")
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> Double {
        let phase = time * 8.0 + Double(index) * 0.72
        let wave = (sin(phase) + 1) * 0.5
        return min(max(0.15 + level * (0.25 + wave * 0.75), 0), 1)
    }
}

enum TerminalComposerDropTypes {
    static let all: [UTType] = [.fileURL, .image, .text, .utf8PlainText]
}

struct TerminalComposerDropHighlight: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        shape
            .fill(theme.accentSubtle)
            .overlay {
                shape.strokeBorder(
                    theme.accent,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
