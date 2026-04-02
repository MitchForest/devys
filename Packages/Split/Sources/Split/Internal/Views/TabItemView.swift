import SwiftUI

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    @Environment(\.splitColors) private var colors
    
    let tab: TabItem
    let isSelected: Bool
    let layoutMetrics: TabBarLayoutMetrics
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: TabBarMetrics.contentSpacing) {
            // Icon
            if let iconName = tab.icon {
                Image(systemName: iconName)
                    .font(.system(size: TabBarMetrics.iconSize))
                    .foregroundStyle(isSelected ? colors.activeText : colors.inactiveText)
            }

            // Title
            Text(tab.title)
                .font(.system(size: TabBarMetrics.titleFontSize))
                .lineLimit(1)
                .foregroundStyle(isSelected ? colors.activeText : colors.inactiveText)

            if let indicator = tab.activityIndicator {
                Circle()
                    .fill(activityIndicatorColor(indicator))
                    .frame(width: TabBarMetrics.activityIndicatorSize, height: TabBarMetrics.activityIndicatorSize)
                    .accessibilityLabel(indicator == .busy ? "Working" : "Idle")
            }

            Spacer(minLength: 4)

            // Close button or dirty indicator
            closeOrDirtyIndicator
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .offset(y: isSelected ? 0.5 : 0)
        .frame(
            minWidth: layoutMetrics.tabMinWidth,
            maxWidth: layoutMetrics.tabMaxWidth,
            minHeight: layoutMetrics.tabHeight,
            maxHeight: layoutMetrics.tabHeight
        )
        .padding(.bottom, isSelected ? 1 : 0)
        .background(tabBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: TabBarMetrics.hoverDuration)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            // Background fill
            if isSelected {
                Rectangle()
                    .fill(colors.activeTabBackground)
            } else if isHovered {
                Rectangle()
                    .fill(colors.activeTabBackground.opacity(0.5))
            } else {
                Color.clear
            }

            // Top accent indicator for selected tab
            if isSelected {
                Rectangle()
                    .fill(colors.accent)
                    .frame(height: TabBarMetrics.activeIndicatorHeight)
            }

            // Right border separator
            HStack {
                Spacer()
                Rectangle()
                    .fill(colors.separator)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Close Button / Dirty Indicator

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        ZStack {
            // Dirty indicator (shown when dirty and not hovering)
            if tab.isDirty && !isHovered && !isCloseHovered {
                Circle()
                    .fill(colors.activeText.opacity(0.6))
                    .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
            }

            // Close button (shown on hover)
            if isHovered || isCloseHovered {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                        .foregroundStyle(isCloseHovered ? colors.activeText : colors.inactiveText)
                        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                        .background(
                            Circle()
                                .fill(isCloseHovered ? colors.activeTabBackground.opacity(0.5) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCloseHovered = hovering
                }
            }
        }
        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isHovered)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isCloseHovered)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if tab.isDirty {
            parts.append("Modified")
        }
        if let indicator = tab.activityIndicator {
            parts.append(indicator == .busy ? "Working" : "Idle")
        }
        return parts.joined(separator: ", ")
    }

    private func activityIndicatorColor(_ indicator: TabActivityIndicator) -> Color {
        switch indicator {
        case .busy:
            return colors.accent
        case .idle:
            return colors.inactiveText.opacity(0.5)
        }
    }
}
