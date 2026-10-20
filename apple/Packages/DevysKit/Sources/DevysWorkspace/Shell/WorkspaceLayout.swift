package import CoreGraphics

/// Column widths for the workspace, computed from the space actually available,
/// so no page, tab row or panel can push the shell wider than the window.
package struct WorkspaceLayout: Equatable, Sendable {
    package static let minimumPage: CGFloat = 420
    package static let inspectorRange: ClosedRange<CGFloat> = 280...640
    package static let handle: CGFloat = 9
    package static let hairline: CGFloat = 1

    package let sidebar: CGFloat
    package let page: CGFloat
    package let inspector: CGFloat
    package let showsHandle: Bool

    package var showsInspector: Bool { inspector > 0 }

    /// - Parameters:
    ///   - width: the workspace's own width, excluding the rail and gutter.
    ///   - preferredInspector: the width the owner dragged the panel to.
    package init(width: CGFloat, sidebarWidth: CGFloat, sidebarVisible: Bool, inspectorVisible: Bool, preferredInspector: CGFloat) {
        sidebar = sidebarVisible ? sidebarWidth : 0
        let content = max(0, width - (sidebarVisible ? sidebarWidth + Self.hairline : 0))
        if inspectorVisible, content >= Self.minimumPage + Self.handle + Self.inspectorRange.lowerBound {
            let largest = min(Self.inspectorRange.upperBound, content - Self.minimumPage - Self.handle)
            inspector = min(max(preferredInspector, Self.inspectorRange.lowerBound), largest)
            page = content - inspector - Self.handle
            showsHandle = true
        } else {
            // Too narrow for both: the page wins and the panel steps aside.
            inspector = 0
            page = content
            showsHandle = false
        }
    }
}
