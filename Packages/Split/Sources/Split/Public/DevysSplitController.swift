import Foundation
import SwiftUI

/// Main controller for the split tab bar system
@MainActor
@Observable
public final class DevysSplitController {

    // MARK: - Delegate

    /// Delegate for receiving callbacks about tab bar events
    public weak var delegate: DevysSplitDelegate?

    // MARK: - Configuration

    /// Configuration for behavior and appearance
    public var configuration: DevysSplitConfiguration

    // MARK: - Internal State

    internal var internalController: SplitViewController

    /// Observable colors for theming (injected into view hierarchy)
    var splitColors: SplitColors
    
    /// Tracks which tabs are welcome tabs (for auto-close behavior)
    internal var welcomeTabIds: Set<UUID> = []

    // MARK: - Initialization

    /// Create a new controller with the specified configuration
    public init(configuration: DevysSplitConfiguration = .default) {
        self.configuration = configuration
        self.internalController = SplitViewController()
        self.splitColors = SplitColors()
        self.splitColors.update(from: configuration.colors)
    }

    /// Update colors dynamically (e.g., when theme changes)
    public func updateColors(_ colors: DevysSplitConfiguration.Colors) {
        self.configuration.colors = colors
        self.splitColors.update(from: colors)
    }
    
    /// Check if a tab is a welcome tab
    public func isWelcomeTab(_ tabId: TabID) -> Bool {
        welcomeTabIds.contains(tabId.id)
    }
}

public extension DevysSplitController {

    // MARK: - Tab Operations

    /// Create a new tab in the focused pane (or specified pane)
    /// - Parameters:
    ///   - title: The tab title
    ///   - icon: Optional SF Symbol name for the tab icon
    ///   - isDirty: Whether the tab shows a dirty indicator
    ///   - pane: Optional pane to add the tab to (defaults to focused pane)
    /// - Returns: The TabID of the created tab, or nil if creation was vetoed by delegate
    @discardableResult
    func createTab(
        title: String,
        icon: String? = "doc.text",
        isDirty: Bool = false,
        activityIndicator: TabActivityIndicator? = nil,
        inPane pane: PaneID? = nil
    ) -> TabID? {
        let tabId = TabID()
        let tab = Tab(
            id: tabId,
            title: title,
            icon: icon,
            isDirty: isDirty,
            activityIndicator: activityIndicator
        )
        guard let defaultPaneId = internalController.rootNode.allPaneIds.first?.id else {
            return nil
        }
        let targetPane = pane ?? focusedPaneId ?? PaneID(id: defaultPaneId)

        // Check with delegate
        if delegate?.splitTabBar(self, shouldCreateTab: tab, inPane: targetPane) == false {
            return nil
        }

        // Calculate insertion index based on configuration
        let insertIndex: Int?
        switch configuration.newTabPosition {
        case .current:
            // Insert after the currently selected tab
            if let paneState = internalController.rootNode.findPane(PaneID(id: targetPane.id)),
               let selectedTabId = paneState.selectedTabId,
               let currentIndex = paneState.tabs.firstIndex(where: { $0.id == selectedTabId }) {
                insertIndex = currentIndex + 1
            } else {
                // No selected tab, append to end
                insertIndex = nil
            }
        case .end:
            insertIndex = nil
        }

        // Create internal TabItem
        let tabItem = TabItem(
            id: tabId.id,
            title: title,
            icon: icon,
            isDirty: isDirty,
            activityIndicator: activityIndicator
        )
        internalController.addTab(tabItem, toPane: PaneID(id: targetPane.id), atIndex: insertIndex)

        // Notify delegate
        delegate?.splitTabBar(self, didCreateTab: tab, inPane: targetPane)

        return tabId
    }

    /// Update an existing tab's metadata
    /// - Parameters:
    ///   - tabId: The tab to update
    ///   - title: New title (pass nil to keep current)
    ///   - icon: New icon (pass nil to keep current, pass .some(nil) to remove icon)
    ///   - isDirty: New dirty state (pass nil to keep current)
    func updateTab(
        _ tabId: TabID,
        title: String? = nil,
        icon: String?? = nil,
        isDirty: Bool? = nil,
        activityIndicator: TabActivityIndicator?? = nil
    ) {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return }

        if let title = title {
            pane.tabs[tabIndex].title = title
        }
        if let icon = icon {
            pane.tabs[tabIndex].icon = icon
        }
        if let isDirty = isDirty {
            pane.tabs[tabIndex].isDirty = isDirty
        }
        if let activityIndicator = activityIndicator {
            pane.tabs[tabIndex].activityIndicator = activityIndicator
        }
    }

    /// Close a tab by ID
    /// - Parameter tabId: The tab to close
    /// - Returns: true if the tab was closed, false if vetoed by delegate
    @discardableResult
    func closeTab(_ tabId: TabID) -> Bool {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return false }
        return closeTab(tabId, with: tabIndex, in: pane)
    }
    
    /// Close a tab by ID in a specific pane.
    /// - Parameter tabId: The tab to close
    /// - Parameter paneId: The pane in which to close the tab
    func closeTab(_ tabId: TabID, inPane paneId: PaneID) -> Bool {
        guard let pane = internalController.rootNode.findPane(paneId),
              let tabIndex = pane.tabs.firstIndex(where: { $0.id == tabId.id }) else {
            return false
        }
        
        return closeTab(tabId, with: tabIndex, in: pane)
    }
    
    /// Internal helper to close a tab given its index in a pane
    /// - Parameter tabId: The tab to close
    /// - Parameter tabIndex: The position of the tab within the pane
    /// - Parameter pane: The pane in which to close the tab
    private func closeTab(_ tabId: TabID, with tabIndex: Int, in pane: PaneState) -> Bool {
        let tabItem = pane.tabs[tabIndex]
        let tab = Tab(from: tabItem)
        let paneId = pane.id
        
        // Check if this is a welcome tab
        let isWelcome = welcomeTabIds.contains(tabId.id)
            || (delegate?.splitView(self, isWelcomeTab: tabId, inPane: paneId) ?? false)

        // Check with delegate
        if delegate?.splitTabBar(self, shouldCloseTab: tab, inPane: paneId) == false {
            return false
        }

        internalController.closeTab(tabId.id, inPane: pane.id)
        
        // Remove from welcome tab tracking
        welcomeTabIds.remove(tabId.id)

        // Notify delegate
        delegate?.splitTabBar(self, didCloseTab: tabId, fromPane: paneId)
        
        // If this was a welcome tab and behavior is autoCreateAndClosePane, close the pane
        if isWelcome
            && configuration.welcomeTabBehavior == .autoCreateAndClosePane
            && pane.tabs.isEmpty
            && internalController.rootNode.allPaneIds.count > 1 {
            // Close the now-empty pane
            _ = closePane(paneId)
        }

        return true
    }

    /// Select a tab by ID
    /// - Parameter tabId: The tab to select
    func selectTab(_ tabId: TabID) {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return }

        pane.selectTab(tabId.id)
        internalController.focusPane(pane.id)

        // Notify delegate
        let tab = Tab(from: pane.tabs[tabIndex])
        delegate?.splitTabBar(self, didSelectTab: tab, inPane: pane.id)
    }

    /// Move to previous tab in focused pane
    func selectPreviousTab() {
        internalController.selectPreviousTab()
        notifyTabSelection()
    }

    /// Move to next tab in focused pane
    func selectNextTab() {
        internalController.selectNextTab()
        notifyTabSelection()
    }

}

public extension DevysSplitController {

    // MARK: - Split Operations

    /// Split the focused pane (or specified pane)
    /// - Parameters:
    ///   - paneId: Optional pane to split (defaults to focused pane)
    ///   - orientation: Direction to split (horizontal = side-by-side, vertical = stacked)
    ///   - tab: Optional tab to add to the new pane
    /// - Returns: The new pane ID, or nil if vetoed by delegate
    @discardableResult
    func splitPane(
        _ paneId: PaneID? = nil,
        orientation: SplitOrientation,
        withTab tab: Tab? = nil
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return nil }

        // Check with delegate
        if delegate?.splitTabBar(self, shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        let internalTab: TabItem?
        if let tab {
            internalTab = TabItem(
                id: tab.id.id,
                title: tab.title,
                icon: tab.icon,
                isDirty: tab.isDirty,
                activityIndicator: tab.activityIndicator
            )
        } else {
            internalTab = nil
        }

        let preSplitPaneIds = Set(internalController.rootNode.allPaneIds.map(\.id))

        // Perform split
        internalController.splitPane(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            with: internalTab
        )
        let postSplitPaneIds = Set(internalController.rootNode.allPaneIds.map(\.id))
        let createdPaneId = postSplitPaneIds.subtracting(preSplitPaneIds).first
        let newPaneId = createdPaneId.map(PaneID.init(id:)) ?? focusedPaneId
        guard let resolvedPaneId = newPaneId else { return nil }

        // Notify delegate
        delegate?.splitTabBar(self, didSplitPane: targetPaneId, newPane: resolvedPaneId, orientation: orientation)

        // If no tab was provided and welcome tab behavior is enabled, create a welcome tab
        if tab == nil && configuration.welcomeTabBehavior != .none {
            createWelcomeTabIfNeeded(inPane: resolvedPaneId)
        }

        return resolvedPaneId
    }
    
    /// Create a welcome tab in the pane if delegate provides one
    private func createWelcomeTabIfNeeded(inPane paneId: PaneID) {
        guard configuration.welcomeTabBehavior != .none,
              let pane = internalController.rootNode.findPane(paneId),
              pane.tabs.isEmpty else {
            return
        }
        
        // Ask delegate for welcome tab
        if let welcomeTab = delegate?.splitView(self, welcomeTabForPane: paneId) {
            // Create the tab internally
            let tabItem = TabItem(
                id: welcomeTab.id.id,
                title: welcomeTab.title,
                icon: welcomeTab.icon,
                isDirty: welcomeTab.isDirty,
                activityIndicator: welcomeTab.activityIndicator
            )
            internalController.addTab(tabItem, toPane: paneId, atIndex: nil)
            
            // Track as welcome tab
            welcomeTabIds.insert(welcomeTab.id.id)
            
            // Notify delegate
            delegate?.splitTabBar(self, didCreateTab: welcomeTab, inPane: paneId)
        }
    }
    
    /// Create welcome tabs for all empty panes.
    /// Call this after operations that may leave panes empty (like opening a new folder).
    func populateEmptyPanesWithWelcomeTabs() {
        guard configuration.welcomeTabBehavior != .none else { return }
        
        for paneId in allPaneIds {
            createWelcomeTabIfNeeded(inPane: paneId)
        }
    }

    /// Close a specific pane
    /// - Parameter paneId: The pane to close
    /// - Returns: true if the pane was closed, false if vetoed by delegate
    @discardableResult
    func closePane(_ paneId: PaneID) -> Bool {
        // Don't close if it's the last pane and not allowed
        if !configuration.allowCloseLastPane && internalController.rootNode.allPaneIds.count <= 1 {
            return false
        }

        // Check with delegate
        if delegate?.splitTabBar(self, shouldClosePane: paneId) == false {
            return false
        }

        internalController.closePane(PaneID(id: paneId.id))

        // Notify delegate
        delegate?.splitTabBar(self, didClosePane: paneId)

        return true
    }

}

public extension DevysSplitController {

    // MARK: - Focus Management

    /// Currently focused pane ID
    var focusedPaneId: PaneID? {
        guard let internalId = internalController.focusedPaneId else { return nil }
        return internalId
    }

    /// Focus a specific pane
    func focusPane(_ paneId: PaneID) {
        internalController.focusPane(PaneID(id: paneId.id))
        delegate?.splitTabBar(self, didFocusPane: paneId)
    }

    /// Navigate focus in a direction
    func navigateFocus(direction: NavigationDirection) {
        internalController.navigateFocus(direction: direction)
        if let focusedPaneId {
            delegate?.splitTabBar(self, didFocusPane: focusedPaneId)
        }
    }

}

public extension DevysSplitController {

    // MARK: - Query Methods

    /// Get all tab IDs
    var allTabIds: [TabID] {
        internalController.rootNode.allPanes.flatMap { pane in
            pane.tabs.map { TabID(id: $0.id) }
        }
    }

    /// Get all pane IDs
    var allPaneIds: [PaneID] {
        internalController.rootNode.allPaneIds
    }

    /// Get tab metadata by ID
    func tab(_ tabId: TabID) -> Tab? {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return nil }
        return Tab(from: pane.tabs[tabIndex])
    }

    /// Get tabs in a specific pane
    func tabs(inPane paneId: PaneID) -> [Tab] {
        guard let pane = internalController.rootNode.findPane(PaneID(id: paneId.id)) else {
            return []
        }
        return pane.tabs.map { Tab(from: $0) }
    }

    /// Get selected tab in a pane
    func selectedTab(inPane paneId: PaneID) -> Tab? {
        guard let pane = internalController.rootNode.findPane(PaneID(id: paneId.id)),
              let selected = pane.selectedTab else {
            return nil
        }
        return Tab(from: selected)
    }

}

public extension DevysSplitController {

    // MARK: - Tree Snapshot API

    /// Get full tree structure for external consumption
    func treeSnapshot() -> ExternalTreeNode {
        let containerFrame = internalController.containerFrame
        return buildExternalTree(from: internalController.rootNode, containerFrame: containerFrame)
    }

    private func buildExternalTree(
        from node: SplitNode,
        containerFrame: CGRect,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> ExternalTreeNode {
        switch node {
        case .pane(let paneState):
            return .pane(externalPaneNode(
                for: paneState,
                bounds: bounds,
                containerFrame: containerFrame
            ))

        case .split(let splitState):
            return .split(externalSplitNode(
                for: splitState,
                bounds: bounds,
                containerFrame: containerFrame
            ))
        }
    }

    private func externalPaneNode(
        for paneState: PaneState,
        bounds: CGRect,
        containerFrame: CGRect
    ) -> ExternalPaneNode {
        let pixelFrame = PixelRect(
            x: Double(bounds.minX * containerFrame.width + containerFrame.origin.x),
            y: Double(bounds.minY * containerFrame.height + containerFrame.origin.y),
            width: Double(bounds.width * containerFrame.width),
            height: Double(bounds.height * containerFrame.height)
        )
        let tabs = paneState.tabs.map { ExternalTab(id: $0.id.uuidString, title: $0.title) }
        return ExternalPaneNode(
            id: paneState.id.id.uuidString,
            frame: pixelFrame,
            tabs: tabs,
            selectedTabId: paneState.selectedTabId?.uuidString
        )
    }

    private func externalSplitNode(
        for splitState: SplitState,
        bounds: CGRect,
        containerFrame: CGRect
    ) -> ExternalSplitNode {
        let (firstBounds, secondBounds) = splitChildBounds(
            for: splitState,
            in: bounds
        )
        return ExternalSplitNode(
            id: splitState.id.uuidString,
            orientation: splitState.orientation == .horizontal ? "horizontal" : "vertical",
            dividerPosition: Double(splitState.dividerPosition),
            first: buildExternalTree(
                from: splitState.first,
                containerFrame: containerFrame,
                bounds: firstBounds
            ),
            second: buildExternalTree(
                from: splitState.second,
                containerFrame: containerFrame,
                bounds: secondBounds
            )
        )
    }

    private func splitChildBounds(
        for splitState: SplitState,
        in bounds: CGRect
    ) -> (CGRect, CGRect) {
        let dividerPos = splitState.dividerPosition
        switch splitState.orientation {
        case .horizontal:
            let first = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width * dividerPos,
                height: bounds.height
            )
            let second = CGRect(
                x: bounds.minX + bounds.width * dividerPos,
                y: bounds.minY,
                width: bounds.width * (1 - dividerPos),
                height: bounds.height
            )
            return (first, second)
        case .vertical:
            let first = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: bounds.height * dividerPos
            )
            let second = CGRect(
                x: bounds.minX,
                y: bounds.minY + bounds.height * dividerPos,
                width: bounds.width,
                height: bounds.height * (1 - dividerPos)
            )
            return (first, second)
        }
    }

}

public extension DevysSplitController {

    // MARK: - Geometry Update API

    /// Set divider position for a split node (0.0-1.0)
    /// - Parameters:
    ///   - position: The new divider position (clamped to 0.1-0.9)
    ///   - splitId: The UUID of the split to update
    ///   - fromExternal: Set to true to suppress outgoing notifications (prevents loops)
    /// - Returns: true if the split was found and updated
    @discardableResult
    func setDividerPosition(_ position: CGFloat, forSplit splitId: UUID, fromExternal: Bool = false) -> Bool {
        guard let split = internalController.findSplit(splitId) else { return false }

        if fromExternal {
            internalController.isExternalUpdateInProgress = true
        }

        // Clamp position to valid range
        let clampedPosition = min(max(position, 0.1), 0.9)
        split.dividerPosition = clampedPosition

        if fromExternal {
            // Use a slight delay to allow the UI to update before re-enabling notifications
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.internalController.isExternalUpdateInProgress = false
            }
        }

        return true
    }

}

extension DevysSplitController {

    // MARK: - Private Helpers

    private func findTabInternal(_ tabId: TabID) -> (PaneState, Int)? {
        for pane in internalController.rootNode.allPanes {
            if let index = pane.tabs.firstIndex(where: { $0.id == tabId.id }) {
                return (pane, index)
            }
        }
        return nil
    }

    private func notifyTabSelection() {
        guard let pane = internalController.focusedPane,
              let tabItem = pane.selectedTab else { return }
        let tab = Tab(from: tabItem)
        delegate?.splitTabBar(self, didSelectTab: tab, inPane: pane.id)
    }
}
