import SwiftUI
import UI

/// Preview shown during tab drag operations.
struct TabDragPreview: View {
    let tab: TabItem
    let layoutMetrics: TabBarLayoutMetrics

    var body: some View {
        DragPreview(
            title: tab.title,
            icon: tab.icon,
            minWidth: layoutMetrics.tabMinWidth,
            maxWidth: layoutMetrics.tabMaxWidth,
            height: layoutMetrics.tabHeight
        )
    }
}
