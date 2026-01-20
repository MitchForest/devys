import SwiftUI

// MARK: - Theme Colors

/// Centralized color definitions for consistent styling across the app.
public enum Theme {
    // MARK: Canvas

    /// Background color for the infinite canvas
    public static let canvasBackground = Color(nsColor: .windowBackgroundColor)

    /// Color for the dot grid on the canvas
    public static let dotColor = Color.gray.opacity(0.3)

    // MARK: Panes

    /// Background color for pane content areas
    public static let paneBackground = Color(nsColor: .controlBackgroundColor)

    /// Background color for pane title bars
    public static let paneTitleBar = Color(nsColor: .windowBackgroundColor)

    /// Border color for unselected panes
    public static let paneBorder = Color.gray.opacity(0.3)

    /// Border color for selected panes
    public static let paneBorderSelected = Color.accentColor

    /// Shadow color for panes
    public static let paneShadow = Color.black.opacity(0.15)

    // MARK: Connectors

    /// Default color for connectors between panes
    public static let connectorColor = Color.blue

    /// Color for connector being drawn
    public static let connectorPending = Color.blue.opacity(0.5)

    // MARK: Snap Guides

    /// Color for snap guide lines
    public static let snapGuide = Color.accentColor.opacity(0.8)

    // MARK: Groups

    /// Default color for group backgrounds
    public static let groupBackground = Color.accentColor.opacity(0.1)

    /// Border color for groups
    public static let groupBorder = Color.accentColor.opacity(0.3)

    // MARK: Resize Handles

    /// Color for resize handles
    public static let resizeHandle = Color.accentColor.opacity(0.6)

    /// Color for resize handles when hovered/active
    public static let resizeHandleActive = Color.accentColor
}

// MARK: - Layout Constants

/// Centralized layout constants for consistent sizing across the app.
public enum Layout {
    // MARK: Canvas

    /// Spacing between dots in the canvas grid (in canvas coordinates)
    public static let dotSpacing: CGFloat = 20

    /// Radius of each dot in the grid
    public static let dotRadius: CGFloat = 1.5

    /// Minimum zoom level
    public static let minScale: CGFloat = 0.1

    /// Maximum zoom level
    public static let maxScale: CGFloat = 4.0

    /// Default zoom level
    public static let defaultScale: CGFloat = 1.0

    // MARK: Panes

    /// Height of pane title bars
    public static let paneTitleBarHeight: CGFloat = 30

    /// Corner radius for pane containers
    public static let paneCornerRadius: CGFloat = 8

    /// Minimum pane width
    public static let paneMinWidth: CGFloat = 200

    /// Minimum pane height
    public static let paneMinHeight: CGFloat = 100

    /// Default pane width
    public static let paneDefaultWidth: CGFloat = 400

    /// Default pane height
    public static let paneDefaultHeight: CGFloat = 300

    /// Shadow radius for panes
    public static let paneShadowRadius: CGFloat = 4

    /// Shadow offset Y for panes
    public static let paneShadowOffsetY: CGFloat = 2

    // MARK: Snapping

    /// Distance threshold for edge snapping (in screen points)
    public static let snapThreshold: CGFloat = 8

    // MARK: Resize Handles

    /// Size of corner resize handle hit areas
    public static let resizeHandleSize: CGFloat = 8

    /// Thickness of edge resize handles
    public static let resizeEdgeThickness: CGFloat = 4

    // MARK: Pane Size Limits

    /// Maximum pane width
    public static let paneMaxWidth: CGFloat = 2000

    /// Maximum pane height
    public static let paneMaxHeight: CGFloat = 1500

    // MARK: Connection Handles

    /// Radius of connection handle circles
    public static let connectionHandleRadius: CGFloat = 6

    // MARK: Animation

    /// Standard animation duration
    public static let animationDuration: Double = 0.2
}

// MARK: - Typography

/// Centralized typography definitions.
public enum Typography {
    /// Font for pane titles
    public static let paneTitle = Font.system(size: 12, weight: .medium)

    /// Font for zoom indicator
    public static let zoomIndicator = Font.caption

    /// Font for code editor
    public static func codeEditor(size: CGFloat = 12) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
