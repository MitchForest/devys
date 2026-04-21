import AppKit
import Testing
@testable import mac_client

@Suite("File Tree Interaction Policy Tests")
struct FileTreeInteractionPolicyTests {
    @Test("Plain folder clicks select and toggle expansion")
    func plainFolderClickTogglesExpansion() {
        #expect(
            fileTreePrimaryClickBehavior(
                isDirectory: true,
                modifiers: []
            ) == .selectAndToggleDirectory
        )
    }

    @Test("Plain file clicks select and preview")
    func plainFileClickPreviewsFile() {
        #expect(
            fileTreePrimaryClickBehavior(
                isDirectory: false,
                modifiers: []
            ) == .selectAndPreviewFile
        )
    }

    @Test("Command-click stays selection-only")
    func commandClickTogglesSelection() {
        #expect(
            fileTreePrimaryClickBehavior(
                isDirectory: true,
                modifiers: [.command]
            ) == .toggleSelection
        )
    }

    @Test("Shift-click stays range-selection-only")
    func shiftClickSelectsRange() {
        #expect(
            fileTreePrimaryClickBehavior(
                isDirectory: true,
                modifiers: [.shift]
            ) == .selectRange
        )
    }

    @Test("Shift-click wins when multiple selection modifiers are present")
    func shiftWinsOverCommand() {
        #expect(
            fileTreePrimaryClickBehavior(
                isDirectory: true,
                modifiers: [.shift, .command]
            ) == .selectRange
        )
    }
}
