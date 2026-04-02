import Foundation
import UniformTypeIdentifiers

/// Protocol for receiving callbacks about tab bar events
public protocol DevysSplitDelegate: AnyObject {
    // MARK: - Tab Lifecycle (Veto Operations)

    /// Called when a new tab is about to be created.
    /// Return `false` to prevent creation.
    func splitTabBar(
        _ controller: DevysSplitController,
        shouldCreateTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool

    /// Called when a tab is about to be closed.
    /// Return `false` to prevent closing (e.g., prompt to save unsaved changes).
    func splitTabBar(
        _ controller: DevysSplitController,
        shouldCloseTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool

    // MARK: - Tab Lifecycle (Notifications)

    /// Called after a tab has been created.
    func splitTabBar(
        _ controller: DevysSplitController,
        didCreateTab tab: Tab,
        inPane pane: PaneID
    )

    /// Called after a tab has been closed.
    func splitTabBar(
        _ controller: DevysSplitController,
        didCloseTab tabId: TabID,
        fromPane pane: PaneID
    )

    /// Called when a tab is selected.
    func splitTabBar(
        _ controller: DevysSplitController,
        didSelectTab tab: Tab,
        inPane pane: PaneID
    )

    /// Called when a tab is moved between panes.
    func splitTabBar(
        _ controller: DevysSplitController,
        didMoveTab tab: Tab,
        fromPane source: PaneID,
        toPane destination: PaneID
    )

    // MARK: - Split Lifecycle (Veto Operations)

    /// Called when a split is about to be created.
    /// Return `false` to prevent the split.
    func splitTabBar(
        _ controller: DevysSplitController,
        shouldSplitPane pane: PaneID,
        orientation: SplitOrientation
    ) -> Bool

    /// Called when a pane is about to be closed.
    /// Return `false` to prevent closing.
    func splitTabBar(
        _ controller: DevysSplitController,
        shouldClosePane pane: PaneID
    ) -> Bool

    // MARK: - Split Lifecycle (Notifications)

    /// Called after a split has been created.
    func splitTabBar(
        _ controller: DevysSplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    )

    /// Called after a pane has been closed.
    func splitTabBar(
        _ controller: DevysSplitController,
        didClosePane paneId: PaneID
    )

    // MARK: - Focus

    /// Called when focus changes to a different pane.
    func splitTabBar(
        _ controller: DevysSplitController,
        didFocusPane pane: PaneID
    )

    // MARK: - External Drops

    /// Called when external content is dropped onto a pane.
    /// Return the TabID of the created tab, or nil if the drop was not handled.
    func splitView(
        _ controller: DevysSplitController,
        didReceiveDrop content: DropContent,
        inPane pane: PaneID,
        zone: DropZone
    ) -> TabID?

    /// Called to check if a drop should be accepted based on the types.
    func splitView(
        _ controller: DevysSplitController,
        shouldAcceptDrop types: [UTType],
        inPane pane: PaneID
    ) -> Bool

    // MARK: - Welcome Tabs

    /// Called to get the welcome tab for an empty pane.
    /// Return nil to not create a welcome tab.
    func splitView(
        _ controller: DevysSplitController,
        welcomeTabForPane pane: PaneID
    ) -> Tab?

    /// Called to check if a tab is a welcome tab (for auto-close behavior).
    func splitView(
        _ controller: DevysSplitController,
        isWelcomeTab tabId: TabID,
        inPane pane: PaneID
    ) -> Bool
}

// MARK: - Default Implementations (all methods optional)

public extension DevysSplitDelegate {
    func splitTabBar(
        _ _: DevysSplitController,
        shouldCreateTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool { true }

    func splitTabBar(
        _ _: DevysSplitController,
        shouldCloseTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool { true }

    func splitTabBar(
        _ _: DevysSplitController,
        didCreateTab tab: Tab,
        inPane pane: PaneID
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        didCloseTab tabId: TabID,
        fromPane pane: PaneID
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        didSelectTab tab: Tab,
        inPane pane: PaneID
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        didMoveTab tab: Tab,
        fromPane source: PaneID,
        toPane destination: PaneID
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        shouldSplitPane pane: PaneID,
        orientation: SplitOrientation
    ) -> Bool { true }

    func splitTabBar(
        _ _: DevysSplitController,
        shouldClosePane pane: PaneID
    ) -> Bool { true }

    func splitTabBar(
        _ _: DevysSplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        didClosePane paneId: PaneID
    ) {}

    func splitTabBar(
        _ _: DevysSplitController,
        didFocusPane pane: PaneID
    ) {}

    func splitView(
        _ _: DevysSplitController,
        didReceiveDrop content: DropContent,
        inPane pane: PaneID,
        zone: DropZone
    ) -> TabID? { nil }

    func splitView(
        _ _: DevysSplitController,
        shouldAcceptDrop types: [UTType],
        inPane pane: PaneID
    ) -> Bool { true }

    func splitView(
        _ _: DevysSplitController,
        welcomeTabForPane pane: PaneID
    ) -> Tab? { nil }

    func splitView(
        _ _: DevysSplitController,
        isWelcomeTab tabId: TabID,
        inPane pane: PaneID
    ) -> Bool { false }
}
