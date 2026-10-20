@testable import DevysWorkspace
import Foundation
import TerminalCore
import Testing

/// The native terminal's PTY seam against a live Devys in local mode. Runs only when
/// DEVYS_LIVE_TERMINAL is "<server>|<token>|<business>|<terminal>".
@Test(.enabled(if: ProcessInfo.processInfo.environment["DEVYS_LIVE_TERMINAL"] != nil))
func remoteTerminalTypesAndReadsALiveSession() async throws {
    let parts = (ProcessInfo.processInfo.environment["DEVYS_LIVE_TERMINAL"] ?? "").split(separator: "|").map(String.init)
    let (server, token, business, terminal) = (parts[0], parts[1], parts[2], parts[3])
    let pty = RemoteTerminalPTY(
        businessID: business,
        terminalID: terminal,
        socketRequest: { offset in
            var request = URLRequest(url: URL(string: "\(server)/api/businesses/\(business)/terminals/\(terminal)/socket?offset=\(offset)")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            return request
        },
        report: { _ in }
    )
    let handle = try await pty.create(descriptor: TerminalLaunchDescriptor(executablePath: "", arguments: []), size: TerminalViewportSize(cols: 80, rows: 24))
    let stream = try await pty.attach(handle)
    try await Task.sleep(for: .seconds(1))
    await pty.takeControl()
    try await Task.sleep(for: .milliseconds(300))
    try await pty.send(Data("echo native-$((6*7))\n".utf8), to: handle)
    var output = ""
    for await event in stream {
        if case .output(let data) = event { output += String(bytes: data, encoding: .utf8) ?? "" }
        if output.contains("native-42\r\n") { break }
    }
    await pty.terminate(handle)
    #expect(output.contains("native-42"))
}
