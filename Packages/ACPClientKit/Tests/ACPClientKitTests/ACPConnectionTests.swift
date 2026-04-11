import ACPClientKit
import Foundation
import Testing

@Suite("ACP Connection Tests")
struct ACPConnectionTests {
    @Test("Initialize handles notifications and stderr")
    func initializeRoundTrip() async throws {
        let launcher = ACPAdapterLauncher()
        let launched = try await launcher.launch(
            descriptor: sharedTestDescriptor,
            options: makeTestLaunchOptions()
        )

        #expect(launched.initializeResult.protocolVersion == ACPProtocolVersion.current)
        #expect(launched.initializeResult.capabilities.supports("terminals"))

        let events = try await collectEvents(from: launched.connection, count: 2)

        #expect(
            events.contains {
                guard case .notification(let notification) = $0 else { return false }
                return notification.method == "acp/test_notification"
                    && notification.params?["phase"]?.stringValue == "initialized"
            }
        )
        #expect(
            events.contains {
                guard case .stderr(let text) = $0 else { return false }
                return text.contains("initialize complete")
            }
        )

        await launched.connection.shutdown()
    }

    @Test("Concurrent request responses stay correlated")
    func correlatesConcurrentResponses() async throws {
        let launcher = ACPAdapterLauncher()
        let launched = try await launcher.launch(
            descriptor: sharedTestDescriptor,
            options: makeTestLaunchOptions()
        )

        async let slow = launched.connection.sendRequest(
            method: "delayed_echo",
            params: ACPValue.object([
                "value": .string("slow"),
                "delay_ms": .integer(60)
            ])
        )
        async let fast = launched.connection.sendRequest(
            method: "delayed_echo",
            params: ACPValue.object([
                "value": .string("fast"),
                "delay_ms": .integer(1)
            ])
        )

        let (slowResult, fastResult) = try await (slow, fast)
        #expect(slowResult?.stringValue == "slow")
        #expect(fastResult?.stringValue == "fast")

        await launched.connection.shutdown()
    }

    @Test("Process termination is surfaced as a typed transport error")
    func processTerminationSurfacesTypedError() async throws {
        let launcher = ACPAdapterLauncher()
        let launched = try await launcher.launch(
            descriptor: sharedTestDescriptor,
            options: makeTestLaunchOptions()
        )

        do {
            _ = try await launched.connection.sendRequest(
                method: "crash_after_request",
                params: ACPValue.object([:])
            )
            Issue.record("Expected crash_after_request to fail.")
        } catch let error as ACPTransportError {
            guard case .processTerminated = error else {
                Issue.record("Unexpected transport error: \(error)")
                return
            }
        }

        await launched.connection.shutdown(terminateProcess: false)
    }

    @Test("Inbound agent requests can be answered by the client")
    func inboundRequestsRoundTrip() async throws {
        let launcher = ACPAdapterLauncher()
        let launched = try await launcher.launch(
            descriptor: sharedTestDescriptor,
            options: makeTestLaunchOptions()
        )

        try await launched.connection.sendRequest(
            method: "emit_permission_request",
            params: ACPValue.object([
                "sessionId": .string("sess-probe")
            ]),
            as: ACPValue.self
        )

        var iterator = launched.connection.events.makeAsyncIterator()
        while let event = await iterator.next() {
            guard case .request(let request) = event else { continue }
            #expect(request.method == "session/request_permission")
            try await launched.connection.respond(
                to: request.id,
                result: ACPValue.object([
                    "outcome": .object([
                        "outcome": .string("selected"),
                        "optionId": .string("allow_once")
                    ])
                ])
            )
            break
        }

        await launched.connection.shutdown()
    }
}

private enum ACPTestError: Error {
    case timedOut
}

private func collectEvents(
    from connection: ACPConnection,
    count: Int,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws -> [ACPConnectionEvent] {
    try await withThrowingTaskGroup(of: [ACPConnectionEvent].self) { group in
        group.addTask {
            var iterator = connection.events.makeAsyncIterator()
            var result: [ACPConnectionEvent] = []
            while result.count < count,
                  let event = await iterator.next() {
                result.append(event)
            }
            return result
        }

        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw ACPTestError.timedOut
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}
