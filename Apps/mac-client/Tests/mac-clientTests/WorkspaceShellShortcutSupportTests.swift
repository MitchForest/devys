import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Shell Shortcut Support Tests")
struct WorkspaceShellShortcutSupportTests {
    @Test("Conflicts include duplicate editable bindings and reserved menu bindings")
    func detectsConflicts() {
        let settings = WorkspaceShellShortcutSettings(
            bindingsByAction: [
                .nextWorkspace: ShortcutBinding(
                    key: "o",
                    modifiers: ShortcutModifierSet(command: true)
                ),
                .previousWorkspace: ShortcutBinding(
                    key: "o",
                    modifiers: ShortcutModifierSet(command: true)
                ),
                .launchShell: ShortcutBinding(
                    key: "p",
                    modifiers: ShortcutModifierSet(command: true, shift: true)
                ),
            ]
        )

        let conflicts = detectWorkspaceShellShortcutConflicts(in: settings)

        #expect(conflicts.hasConflicts)
        #expect(conflicts.messages(for: .nextWorkspace).contains { $0.contains("Add Repository") })
        #expect(conflicts.messages(for: .nextWorkspace).contains { $0.contains("Previous Workspace") })
        #expect(conflicts.messages(for: .previousWorkspace).contains { $0.contains("Next Workspace") })
        #expect(conflicts.messages(for: .launchShell).contains { $0.contains("Open Command Palette") })
    }
}
