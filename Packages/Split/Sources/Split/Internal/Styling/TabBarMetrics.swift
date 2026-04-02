import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
enum TabBarMetrics {
    static let barPadding: CGFloat = 0

    // MARK: - Individual Tabs

    static let tabCornerRadius: CGFloat = 0
    static let tabHorizontalPadding: CGFloat = 12
    static let activeIndicatorHeight: CGFloat = 2

    // MARK: - Tab Content

    static let iconSize: CGFloat = 14
    static let titleFontSize: CGFloat = 12
    static let closeButtonSize: CGFloat = 16
    static let closeIconSize: CGFloat = 9
    static let dirtyIndicatorSize: CGFloat = 8
    static let activityIndicatorSize: CGFloat = 6
    static let contentSpacing: CGFloat = 6

    // MARK: - Drop Indicator

    static let dropIndicatorWidth: CGFloat = 2
    static let dropIndicatorHeight: CGFloat = 20

    // MARK: - Animations

    static let selectionDuration: Double = 0.15
    static let closeDuration: Double = 0.2
    static let reorderDuration: Double = 0.3
    static let reorderBounce: Double = 0.15
    static let hoverDuration: Double = 0.1

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
