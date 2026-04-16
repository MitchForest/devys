import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
enum TabBarMetrics {
    static let barPadding: CGFloat = 0

    // MARK: - Animations

    static let selectionDuration: Double = 0.15
    static let closeDuration: Double = 0.2
    static let reorderDuration: Double = 0.3
    static let reorderBounce: Double = 0.15
}

struct TabBarLayoutMetrics {
    let barHeight: CGFloat
    let tabHeight: CGFloat
    let tabMinWidth: CGFloat
    let tabMaxWidth: CGFloat
    let tabSpacing: CGFloat
    let minimumPaneWidth: CGFloat
    let minimumPaneHeight: CGFloat
}

extension DevysSplitConfiguration.Appearance {
    var layoutMetrics: TabBarLayoutMetrics {
        let barHeight = tabBarHeight
        let tabHeight = max(1, tabBarHeight - 1)
        return TabBarLayoutMetrics(
            barHeight: barHeight,
            tabHeight: tabHeight,
            tabMinWidth: tabMinWidth,
            tabMaxWidth: tabMaxWidth,
            tabSpacing: tabSpacing,
            minimumPaneWidth: minimumPaneWidth,
            minimumPaneHeight: minimumPaneHeight
        )
    }
}
