import Testing
@testable import Split

@Suite("DevysSplit Tests")
struct DevysSplitTests {

    @MainActor
    @Test("Controller creation initializes focused pane")
    func controllerCreation() {
        let controller = DevysSplitController()
        #expect(controller.focusedPaneId != nil)
    }

    @MainActor
    @Test("Tab creation returns an identifier")
    func tabCreation() {
        let controller = DevysSplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")
        #expect(tabId != nil)
    }

    @MainActor
    @Test("Tab retrieval returns created metadata")
    func tabRetrieval() throws {
        let controller = DevysSplitController()
        let tabId = try #require(controller.createTab(title: "Test Tab", icon: "doc"))
        let tab = controller.tab(tabId)
        #expect(tab?.title == "Test Tab")
        #expect(tab?.icon == "doc")
    }

    @MainActor
    @Test("Tab updates are reflected in lookup")
    func tabUpdate() throws {
        let controller = DevysSplitController()
        let tabId = try #require(controller.createTab(title: "Original", icon: "doc"))

        controller.updateTab(tabId, title: "Updated", isPreview: true, isDirty: true)

        let tab = controller.tab(tabId)
        #expect(tab?.title == "Updated")
        #expect(tab?.isPreview == true)
        #expect(tab?.isDirty == true)
    }

    @MainActor
    @Test("Closing a tab removes it from the controller")
    func tabClose() throws {
        let controller = DevysSplitController()
        let tabId = try #require(controller.createTab(title: "Test Tab", icon: "doc"))

        let closed = controller.closeTab(tabId)

        #expect(closed)
        #expect(controller.tab(tabId) == nil)
    }

    @MainActor
    @Test("Configuration is preserved on initialization")
    func configuration() {
        let config = DevysSplitConfiguration(
            allowSplits: false,
            allowCloseTabs: true
        )
        let controller = DevysSplitController(configuration: config)

        #expect(!controller.configuration.allowSplits)
        #expect(controller.configuration.allowCloseTabs)
    }

    @MainActor
    @Test("Handled gesture intents do not mutate controller topology")
    func handledGestureIntentDoesNotMutateController() throws {
        let controller = DevysSplitController()
        let paneID = try #require(controller.focusedPaneId)
        let delegate = GestureIntentDelegate(shouldHandle: true)
        controller.delegate = delegate

        let handled = controller.dispatchGestureIntent(
            .splitPane(
                paneID: paneID,
                orientation: .horizontal,
                insertion: .before
            )
        )

        #expect(handled)
        #expect(delegate.intents == [.splitPane(
            paneID: paneID,
            orientation: .horizontal,
            insertion: .before
        )])
        #expect(controller.allPaneIds == [paneID])
        #expect(controller.focusedPaneId == paneID)
    }

    @MainActor
    @Test("Unhandled gesture intents fall back to controller mutations")
    func unhandledGestureIntentFallsBackToController() throws {
        let controller = DevysSplitController()
        let paneID = try #require(controller.focusedPaneId)

        let handled = controller.dispatchGestureIntent(
            .splitPane(
                paneID: paneID,
                orientation: .vertical,
                insertion: .after
            )
        )

        #expect(!handled)
        #expect(controller.allPaneIds.count == 2)
        #expect(controller.focusedPaneId != paneID)
    }

    @MainActor
    @Test("Restoring a reducer-owned snapshot preserves active tab drag state")
    func restoreTreeSnapshotPreservesActiveDragState() throws {
        let controller = DevysSplitController()
        let paneID = try #require(controller.focusedPaneId)
        let tabID = try #require(controller.createTab(title: "Dragged Tab", icon: "doc"))
        let pane = try #require(controller.internalController.rootNode.findPane(paneID))
        let draggedTab = try #require(pane.tabs.first(where: { $0.id == tabID.id }))

        controller.internalController.draggingTab = draggedTab
        controller.internalController.dragSourcePaneId = paneID

        controller.restoreTreeSnapshot(
            controller.treeSnapshot(),
            focusedPaneId: paneID
        )

        #expect(controller.internalController.draggingTab?.id == draggedTab.id)
        #expect(controller.internalController.dragSourcePaneId == paneID)
    }
}

private final class GestureIntentDelegate: DevysSplitDelegate {
    let shouldHandle: Bool
    var intents: [SplitGestureIntent] = []

    init(shouldHandle: Bool) {
        self.shouldHandle = shouldHandle
    }

    func splitView(
        _ controller: DevysSplitController,
        didRequest intent: SplitGestureIntent
    ) -> Bool {
        intents.append(intent)
        return shouldHandle
    }
}
