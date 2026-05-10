import TerminalComposer
@testable import TerminalProduct
import XCTest

final class TerminalAgentRegistryTests: XCTestCase {
    func testExecutableNameMatchTakesPrecedenceOverTitle() {
        let registry = TerminalAgentRegistry.default

        let match = registry.match(executableName: "claude", title: "codex")

        XCTAssertEqual(match?.displayName, "Claude Code")
        XCTAssertEqual(match?.serializationStyle, .claudeCode)
    }

    func testExecutableMatchIsCaseInsensitive() {
        let registry = TerminalAgentRegistry.default

        XCTAssertEqual(
            registry.match(executableName: "Claude", title: nil)?.displayName,
            "Claude Code"
        )
        XCTAssertEqual(
            registry.match(executableName: "CODEX", title: nil)?.displayName,
            "Codex"
        )
    }

    func testTitleSubstringFallbackResolvesAgentBehindSSH() {
        let registry = TerminalAgentRegistry.default

        let match = registry.match(executableName: "ssh", title: "remote: claude session")

        XCTAssertEqual(match?.displayName, "Claude Code")
    }

    func testNoMatchForShellsAndUnrelatedTUIs() {
        let registry = TerminalAgentRegistry.default

        XCTAssertNil(registry.match(executableName: "zsh", title: nil))
        XCTAssertNil(registry.match(executableName: "vim", title: "vim - file.swift"))
        XCTAssertNil(registry.match(executableName: "htop", title: "htop"))
        XCTAssertNil(registry.match(executableName: nil, title: nil))
    }

    func testEmptyStringsAreTreatedAsNoSignal() {
        let registry = TerminalAgentRegistry.default

        XCTAssertNil(registry.match(executableName: "", title: ""))
    }

    func testCustomRegistryCanReplaceDefaults() {
        let custom = TerminalAgentRegistry(entries: [
            TerminalAgentMatch(
                displayName: "Test Agent",
                executableNames: ["test-agent"],
                serializationStyle: .codex
            ),
        ])

        XCTAssertEqual(
            custom.match(executableName: "test-agent", title: nil)?.displayName,
            "Test Agent"
        )
        XCTAssertNil(custom.match(executableName: "claude", title: nil))
    }
}
