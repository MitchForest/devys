import Testing
@testable import mac_client

@Suite("Terminal color environment tests")
struct TerminalColorEnvironmentTests {
    @Test("Color-capable environment removes NO_COLOR and keeps other entries")
    func removesNoColor() {
        let environment = colorCapableEnvironment([
            "NO_COLOR": "1",
            "PATH": "/usr/bin:/bin",
            "TERM_PROGRAM": "ghostty"
        ])

        #expect(environment["NO_COLOR"] == nil)
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["TERM_PROGRAM"] == "ghostty")
    }
}
