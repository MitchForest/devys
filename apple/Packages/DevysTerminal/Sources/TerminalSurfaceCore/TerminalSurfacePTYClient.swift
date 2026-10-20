public import Foundation
public import TerminalCore

/// The PTY seam the terminal surface runtime drives. In Devys the PTY lives on the Mac host and
/// this is implemented over a WebSocket, with no renderer changes.
public protocol TerminalSurfacePTYClient: Sendable {
    func create(
        descriptor: TerminalLaunchDescriptor,
        size: TerminalViewportSize
    ) async throws -> TerminalSessionHandle

    func attach(_ handle: TerminalSessionHandle) async throws -> AsyncStream<TerminalPTYEvent>

    func resize(_ handle: TerminalSessionHandle, size: TerminalViewportSize) async throws

    func send(_ data: Data, to handle: TerminalSessionHandle) async throws

    func currentWorkingDirectory(_ handle: TerminalSessionHandle) async -> URL?

    func processSnapshot(_ handle: TerminalSessionHandle) async -> TerminalProcessSnapshot

    func terminate(_ handle: TerminalSessionHandle) async
}
