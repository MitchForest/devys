import SwiftUI
import UI

/// Individual tab rendered with the shared shell tab primitive.
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let layoutMetrics: TabBarLayoutMetrics
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        TabPill(
            title: tab.title,
            icon: tab.icon,
            isSelected: isSelected,
            isPreview: tab.isPreview,
            isDirty: tab.isDirty,
            activityStatus: activityStatus,
            minWidth: layoutMetrics.tabMinWidth,
            maxWidth: layoutMetrics.tabMaxWidth,
            height: layoutMetrics.tabHeight,
            onSelect: onSelect,
            onClose: onClose
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if tab.isPreview {
            parts.append("Preview")
        }
        if tab.isDirty {
            parts.append("Modified")
        }
        if let indicator = tab.activityIndicator {
            parts.append(indicator == .busy ? "Working" : "Idle")
        }
        return parts.joined(separator: ", ")
    }

    private var activityStatus: StatusDot.Status? {
        switch tab.activityIndicator {
        case .busy:
            return .running
        case .idle:
            return .idle
        case nil:
            return nil
        }
    }
}
