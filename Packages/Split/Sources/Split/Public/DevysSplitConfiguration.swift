import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Controls how tab content views are managed when switching between tabs
public enum ContentViewLifecycle: Sendable {
    /// Only the selected tab's content view is rendered. Other tabs' views are
    /// destroyed and recreated when selected. This is memory efficient but loses
    /// view state like scroll position, @State variables, and focus.
    case recreateOnSwitch

    /// All tab content views are kept in the view hierarchy, with non-selected tabs
    /// hidden. This preserves all view state (scroll position, @State, focus, etc.)
    /// at the cost of higher memory usage.
    case keepAllAlive
}

/// Controls the position where new tabs are created
public enum NewTabPosition: Sendable {
    /// Insert the new tab after the currently focused tab,
    /// or at the end if there are no focused tabs.
    case current

    /// Insert the new tab at the end of the tab list.
    case end
}

/// Configuration for the split tab bar appearance and behavior
public struct DevysSplitConfiguration: Sendable {

    // MARK: - Behavior

    /// Whether to allow creating splits
    public var allowSplits: Bool

    /// Whether to allow closing tabs
    public var allowCloseTabs: Bool

    /// Whether to allow closing the last pane
    public var allowCloseLastPane: Bool

    /// Whether to allow drag & drop reordering of tabs
    public var allowTabReordering: Bool

    /// Whether to allow moving tabs between panes
    public var allowCrossPaneTabMove: Bool

    /// Whether to automatically close empty panes
    public var autoCloseEmptyPanes: Bool

    /// Controls how tab content views are managed when switching tabs
    public var contentViewLifecycle: ContentViewLifecycle

    /// Controls where new tabs are inserted in the tab list
    public var newTabPosition: NewTabPosition

    /// UTTypes accepted for external drag & drop
    public var acceptedDropTypes: [UTType]

    // MARK: - Appearance

    /// Tab bar appearance customization
    public var appearance: Appearance

    /// Color customization
    public var colors: Colors

    // MARK: - Presets

    public static let `default` = DevysSplitConfiguration()

    public static let singlePane = DevysSplitConfiguration(
        allowSplits: false,
        allowCloseLastPane: false
    )

    public static let readOnly = DevysSplitConfiguration(
        allowSplits: false,
        allowCloseTabs: false,
        allowTabReordering: false,
        allowCrossPaneTabMove: false
    )

    // MARK: - Initializer

    public init(
        allowSplits: Bool = true,
        allowCloseTabs: Bool = true,
        allowCloseLastPane: Bool = false,
        allowTabReordering: Bool = true,
        allowCrossPaneTabMove: Bool = true,
        autoCloseEmptyPanes: Bool = true,
        contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch,
        newTabPosition: NewTabPosition = .current,
        acceptedDropTypes: [UTType] = [],
        appearance: Appearance = .default,
        colors: Colors = .default
    ) {
        self.allowSplits = allowSplits
        self.allowCloseTabs = allowCloseTabs
        self.allowCloseLastPane = allowCloseLastPane
        self.allowTabReordering = allowTabReordering
        self.allowCrossPaneTabMove = allowCrossPaneTabMove
        self.autoCloseEmptyPanes = autoCloseEmptyPanes
        self.contentViewLifecycle = contentViewLifecycle
        self.newTabPosition = newTabPosition
        self.acceptedDropTypes = acceptedDropTypes
        self.appearance = appearance
        self.colors = colors
    }
}

// MARK: - Appearance Configuration

public extension DevysSplitConfiguration {
    struct Appearance: Sendable {
        // MARK: - Tab Bar

        /// Height of the tab bar
        var tabBarHeight: CGFloat

        // MARK: - Tabs

        /// Minimum width of a tab
        var tabMinWidth: CGFloat

        /// Maximum width of a tab
        var tabMaxWidth: CGFloat

        /// Spacing between tabs
        var tabSpacing: CGFloat

        // MARK: - Split View

        /// Minimum width of a pane
        var minimumPaneWidth: CGFloat

        /// Minimum height of a pane
        var minimumPaneHeight: CGFloat

        /// Whether to show split buttons in the tab bar
        var showSplitButtons: Bool

        // MARK: - Animations

        /// Duration of animations
        var animationDuration: Double

        /// Whether to enable animations
        var enableAnimations: Bool

        // MARK: - Presets

        public static let `default` = Appearance()

        public static let compact = Appearance(
            tabBarHeight: 28,
            tabMinWidth: 100,
            tabMaxWidth: 160
        )

        public static let spacious = Appearance(
            tabBarHeight: 38,
            tabMinWidth: 160,
            tabMaxWidth: 280,
            tabSpacing: 2
        )

        // MARK: - Initializer

        public init(
            tabBarHeight: CGFloat = 33,
            tabMinWidth: CGFloat = 140,
            tabMaxWidth: CGFloat = 220,
            tabSpacing: CGFloat = 0,
            minimumPaneWidth: CGFloat = 100,
            minimumPaneHeight: CGFloat = 100,
            showSplitButtons: Bool = true,
            animationDuration: Double = 0.15,
            enableAnimations: Bool = true
        ) {
            self.tabBarHeight = tabBarHeight
            self.tabMinWidth = tabMinWidth
            self.tabMaxWidth = tabMaxWidth
            self.tabSpacing = tabSpacing
            self.minimumPaneWidth = minimumPaneWidth
            self.minimumPaneHeight = minimumPaneHeight
            self.showSplitButtons = showSplitButtons
            self.animationDuration = animationDuration
            self.enableAnimations = enableAnimations
        }
    }
}

// MARK: - Color Configuration

public extension DevysSplitConfiguration {
    struct Colors: Sendable {
        /// Accent color for active tab indicator, drop zones, focus rings
        var accent: Color

        /// Tab bar background
        var tabBarBackground: Color

        /// Active tab background
        var activeTabBackground: Color

        /// Inactive tab text
        var inactiveText: Color

        /// Active tab text
        var activeText: Color

        /// Border/separator color
        var separator: Color

        /// Content area background (card surface)
        var contentBackground: Color

        /// Base surface behind pane cards (visible in gaps between panes)
        var baseBackground: Color

        /// Corner radius for pane cards
        var paneCornerRadius: CGFloat

        /// Gap between adjacent pane cards
        var paneGap: CGFloat

        // MARK: - Presets

        public static let `default` = Colors()

        // MARK: - Initializer

        public init(
            accent: Color = .accentColor,
            tabBarBackground: Color = Color(nsColor: .windowBackgroundColor),
            activeTabBackground: Color = Color(nsColor: .controlBackgroundColor),
            inactiveText: Color = .secondary,
            activeText: Color = .primary,
            separator: Color = Color(nsColor: .separatorColor),
            contentBackground: Color = Color(nsColor: .textBackgroundColor),
            baseBackground: Color = Color(nsColor: .windowBackgroundColor),
            paneCornerRadius: CGFloat = 12,
            paneGap: CGFloat = 6
        ) {
            self.accent = accent
            self.tabBarBackground = tabBarBackground
            self.activeTabBackground = activeTabBackground
            self.inactiveText = inactiveText
            self.activeText = activeText
            self.separator = separator
            self.contentBackground = contentBackground
            self.baseBackground = baseBackground
            self.paneCornerRadius = paneCornerRadius
            self.paneGap = paneGap
        }
    }
}
