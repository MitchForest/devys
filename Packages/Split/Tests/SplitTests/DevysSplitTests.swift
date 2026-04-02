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

        controller.updateTab(tabId, title: "Updated", isDirty: true)

        let tab = controller.tab(tabId)
        #expect(tab?.title == "Updated")
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
}
