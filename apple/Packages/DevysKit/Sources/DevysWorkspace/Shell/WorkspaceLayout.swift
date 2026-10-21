package import CoreGraphics

/// Column widths for the workspace, computed from the space actually available, exactly as the
/// web's `layout`. The conversation keeps its minimum; the right panel takes its preferred width
/// within its range, or everything else when widened, and lies over the conversation when the
/// window is too narrow for both.
package struct WorkspaceLayout: Equatable, Sendable {
    package static let minimumConversation: CGFloat = 420
    package static let panelRange: ClosedRange<CGFloat> = 360...720
    package static let defaultPanel: CGFloat = 440
    package static let handle: CGFloat = 9
    package static let hairline: CGFloat = 1

    package let sidebar: CGFloat
    package let conversation: CGFloat
    package let panel: CGFloat
    /// The panel lies over the conversation instead of beside it.
    package let overlay: Bool
    package let showsHandle: Bool

    /// - Parameters:
    ///   - width: the workspace's own width, excluding the business strip and gutter.
    ///   - preferredPanel: the width the owner dragged the panel to.
    package init(width: CGFloat, sidebarWidth: CGFloat, sidebarVisible: Bool, panelOpen: Bool, wide: Bool, preferredPanel: CGFloat) {
        sidebar = sidebarVisible ? sidebarWidth : 0
        let content = max(0, width - (sidebarVisible ? sidebarWidth + Self.hairline : 0))
        if !panelOpen {
            (conversation, panel, overlay, showsHandle) = (content, 0, false, false)
        } else if content < Self.minimumConversation + Self.handle + Self.panelRange.lowerBound {
            (conversation, panel, overlay, showsHandle) = (content, min(content, Self.defaultPanel), true, false)
        } else {
            let largest = content - Self.minimumConversation - Self.handle
            let panel = wide ? largest : min(max(preferredPanel, Self.panelRange.lowerBound), min(Self.panelRange.upperBound, largest))
            (conversation, self.panel, overlay, showsHandle) = (content - panel - Self.handle, panel, false, !wide)
        }
    }
}
