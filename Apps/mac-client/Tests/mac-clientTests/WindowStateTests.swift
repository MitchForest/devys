import Foundation
import Testing
@testable import mac_client

@Suite("WindowState Tests")
struct WindowStateTests {
    @Test("A new window starts without a folder")
    @MainActor
    func initialState() {
        let state = WindowState()

        #expect(state.folder == nil)
        #expect(!state.hasFolder)
    }

    @Test("Opening a folder updates the current folder")
    @MainActor
    func openFolder() {
        let state = WindowState()
        let folder = URL(fileURLWithPath: "/tmp/devys-project")

        state.openFolder(folder)

        #expect(state.folder == folder)
        #expect(state.hasFolder)
    }
}
