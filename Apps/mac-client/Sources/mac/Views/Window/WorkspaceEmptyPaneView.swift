import Split
import SwiftUI
import UI

struct WorkspaceEmptyPaneView: View {
    @Environment(\.devysTheme) private var theme

    let paneID: PaneID
    let onFocusPane: (PaneID) -> Void
    let onOpenTerminal: (PaneID) -> Void
    let onOpenAgent: (PaneID) -> Void
    let onOpenFile: (PaneID) -> Void

    var body: some View {
        VStack(spacing: DevysSpacing.space5) {
            Image(systemName: "sparkles")
                .font(DevysTypography.display.weight(.light))
                .foregroundStyle(theme.textTertiary)

            VStack(spacing: DevysSpacing.space2) {
                Text("Open a file, start a terminal, or launch an agent")
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: DevysSpacing.space2) {
                ActionButton("Terminal", icon: "terminal", style: .primary) {
                    onFocusPane(paneID)
                    onOpenTerminal(paneID)
                }

                ActionButton("Agent", icon: "sparkles", style: .ghost) {
                    onFocusPane(paneID)
                    onOpenAgent(paneID)
                }

                ActionButton("Open File", icon: "doc", style: .ghost) {
                    onFocusPane(paneID)
                    onOpenFile(paneID)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocusPane(paneID)
        }
    }
}
