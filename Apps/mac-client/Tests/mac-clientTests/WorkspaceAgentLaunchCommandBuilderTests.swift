import Testing
@testable import mac_client

@Suite("Workspace agent launch command builder tests")
struct WorkspaceAgentLaunchCommandBuilderTests {
    @Test("Environment wrapper prefixes the command with env assignments")
    func wrapsCommandWithInlineEnvironment() {
        let expected =
            "env DEVYS_WORKSPACE_ID=/tmp/devys/repo DEVYS_TERMINAL_ID=1234-5678 " +
            "DEVYS_EXECUTABLE_PATH='/Applications/Devys.app/Contents/MacOS/mac client' " +
            "claude --model sonnet"
        let command = envWrappedShellCommand(
            "claude --model sonnet",
            environment: [
                ("DEVYS_WORKSPACE_ID", "/tmp/devys/repo"),
                ("DEVYS_TERMINAL_ID", "1234-5678"),
                ("DEVYS_EXECUTABLE_PATH", "/Applications/Devys.app/Contents/MacOS/mac client")
            ]
        )

        #expect(command == expected)
    }

    @Test("Shell quoting escapes empty strings and embedded apostrophes")
    func shellQuotesSpecialValues() {
        #expect(shellQuoted("") == "''")
        #expect(shellQuoted("O'Brien") == "'O'\"'\"'Brien'")
    }
}
