import SwiftUI
import UI

struct IOSTerminalAccessoryRow: View {
    @Environment(\.devysTheme) private var theme

    let isCtrlLatched: Bool
    let isAltLatched: Bool
    let onToggleCtrl: () -> Void
    let onToggleAlt: () -> Void
    let onKeyPress: (IOSClientConnectionStore.TerminalSpecialKey) -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onTop: () -> Void
    let onBottom: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DevysSpacing.space2) {
                keyButton(
                    isCtrlLatched ? "[ctrl:on]" : "[ctrl]",
                    tint: isCtrlLatched ? theme.accent : theme.textSecondary,
                    action: onToggleCtrl
                )
                keyButton(
                    isAltLatched ? "[alt:on]" : "[alt]",
                    tint: isAltLatched ? theme.accent : theme.textSecondary,
                    action: onToggleAlt
                )

                specialKeyButton("[esc]", .escape)
                specialKeyButton("[tab]", .tab)
                specialKeyButton("[↑]", .up)
                specialKeyButton("[↓]", .down)
                specialKeyButton("[←]", .left)
                specialKeyButton("[→]", .right)
                specialKeyButton("[pgup]", .pageUp)
                specialKeyButton("[pgdn]", .pageDown)
                specialKeyButton("[home]", .home)
                specialKeyButton("[end]", .end)
                specialKeyButton("[ctrl+c]", .interrupt, tint: DevysColors.warning)

                keyButton("[copy]", action: onCopy)
                keyButton("[paste]", action: onPaste)
                keyButton("[top]", action: onTop)
                keyButton("[bottom]", action: onBottom)
            }
        }
    }

    private func specialKeyButton(
        _ title: String,
        _ key: IOSClientConnectionStore.TerminalSpecialKey,
        tint: Color? = nil
    ) -> some View {
        keyButton(title, tint: tint) {
            onKeyPress(key)
        }
    }

    private func keyButton(_ title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(DevysTypography.xs)
                .foregroundStyle(tint ?? theme.textSecondary)
                .padding(.horizontal, DevysSpacing.space2)
                .padding(.vertical, DevysSpacing.space1)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
