import ACPClientKit
import Foundation
import Testing

@Suite("ACP Adapter Launcher Tests")
struct ACPAdapterLauncherTests {
    @Test("Configured executable path is resolved without UI dependencies")
    func resolvesConfiguredExecutable() throws {
        let launcher = ACPAdapterLauncher()
        let resolved = try launcher.resolve(
            descriptor: sharedTestDescriptor,
            options: makeTestLaunchOptions()
        )

        #expect(resolved.source == ACPResolvedAdapter.Source.configured)
        #expect(resolved.executableURL == testAdapterExecutableURL())
    }

    @Test("Missing adapters fail with binary-not-found diagnostics")
    func missingBinaryProducesTypedError() {
        let launcher = ACPAdapterLauncher()
        let options = ACPAdapterLaunchOptions(
            fallbackSearchDirectories: [],
            environment: ["PATH": "/tmp/devys-missing-acp-path-\(UUID().uuidString)"]
        )
        let descriptor = ACPAgentDescriptor(
            kind: .claude,
            displayName: "Missing Adapter",
            executableName: "devys-missing-acp-\(UUID().uuidString)"
        )

        do {
            _ = try launcher.resolve(
                descriptor: descriptor,
                options: options
            )
            Issue.record("Expected resolve to fail.")
        } catch let error as ACPAdapterLaunchError {
            guard case .binaryNotFound(let kind, let candidates) = error else {
                Issue.record("Unexpected launch error: \(error)")
                return
            }
            #expect(kind == .claude)
            #expect(candidates == [descriptor.executableName])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Fallback search directories are used when PATH does not include the adapter")
    func resolvesFromFallbackSearchDirectories() throws {
        let launcher = ACPAdapterLauncher()
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "devys-acp-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executableURL = rootURL.appending(path: "codex-acp", directoryHint: .notDirectory)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        defer { try? FileManager.default.removeItem(at: rootURL) }
        let descriptor = ACPAgentDescriptor(
            kind: .codex,
            displayName: "Fallback Adapter",
            executableName: "devys-test-fallback-\(UUID().uuidString)"
        )
        let renamedExecutableURL = rootURL.appending(path: descriptor.executableName, directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: executableURL, to: renamedExecutableURL)

        let resolved = try launcher.resolve(
            descriptor: descriptor,
            options: ACPAdapterLaunchOptions(
                fallbackSearchDirectories: [rootURL],
                environment: ["PATH": "/tmp/devys-missing-acp-path-\(UUID().uuidString)"]
            )
        )

        #expect(resolved.source == ACPResolvedAdapter.Source.path)
        #expect(resolved.executableURL == renamedExecutableURL)
    }

    @Test("Fallback directories never shadow a non-fallback PATH entry")
    func pathEntriesBeatFallbackDirectoriesEvenWhenFallbacksAreInjectedIntoPATH() throws {
        let launcher = ACPAdapterLauncher()
        let fallbackRootURL = FileManager.default.temporaryDirectory
            .appending(path: "devys-acp-fallback-\(UUID().uuidString)", directoryHint: .isDirectory)
        let pathRootURL = FileManager.default.temporaryDirectory
            .appending(path: "devys-acp-path-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executableName = "devys-path-order-\(UUID().uuidString)"
        let fallbackExecutableURL = fallbackRootURL.appending(path: executableName, directoryHint: .notDirectory)
        let pathExecutableURL = pathRootURL.appending(path: executableName, directoryHint: .notDirectory)

        try FileManager.default.createDirectory(at: fallbackRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathRootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: fallbackRootURL)
            try? FileManager.default.removeItem(at: pathRootURL)
        }

        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: fallbackExecutableURL, atomically: true, encoding: .utf8)
        try script.write(to: pathExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fallbackExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pathExecutableURL.path)

        let resolved = try launcher.resolve(
            descriptor: ACPAgentDescriptor(
                kind: .codex,
                displayName: "Path Ordering",
                executableName: executableName
            ),
            options: ACPAdapterLaunchOptions(
                fallbackSearchDirectories: [fallbackRootURL],
                environment: [
                    "PATH": [
                        fallbackRootURL.path(percentEncoded: false),
                        pathRootURL.path(percentEncoded: false)
                    ].joined(separator: ":")
                ]
            )
        )

        #expect(resolved.executableURL == pathExecutableURL)
    }

    @Test("Launch errors expose explicit localized diagnostics")
    func missingBinaryLocalizedDescriptionIsActionable() {
        let error = ACPAdapterLaunchError.binaryNotFound(
            kind: .codex,
            candidates: ["codex-acp"]
        )

        #expect(
            error.localizedDescription ==
                "No Codex ACP adapter was found. Expected `codex-acp` in a configured path, the app bundle helpers, or PATH."
        )
    }

    @Test("Initialize failures stay distinct from spawn failures")
    func initializeFailureIsTyped() async {
        let launcher = ACPAdapterLauncher()

        do {
            _ = try await launcher.launch(
                descriptor: sharedTestDescriptor,
                options: makeTestLaunchOptions(mode: "crash_on_initialize")
            )
            Issue.record("Expected initialize to fail.")
        } catch let error as ACPAdapterLaunchError {
            guard case .initializeFailed(let failure) = error else {
                Issue.record("Unexpected launch error: \(error)")
                return
            }

            guard case .transport(let transportError) = failure,
                  case .processTerminated = transportError else {
                Issue.record("Unexpected initialize failure: \(failure)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Unsupported protocol versions are rejected")
    func unsupportedProtocolVersionIsRejected() async {
        let launcher = ACPAdapterLauncher()

        do {
            _ = try await launcher.launch(
                descriptor: sharedTestDescriptor,
                options: makeTestLaunchOptions(mode: "unsupported_protocol")
            )
            Issue.record("Expected unsupported protocol version failure.")
        } catch let error as ACPAdapterLaunchError {
            guard case .unsupportedProtocolVersion(let expected, let actual) = error else {
                Issue.record("Unexpected launch error: \(error)")
                return
            }
            #expect(expected == ACPProtocolVersion.current)
            #expect(actual == ACPProtocolVersion(rawValue: 999))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Unsupported capabilities are rejected after initialize")
    func unsupportedCapabilitiesAreRejected() async {
        let launcher = ACPAdapterLauncher()

        do {
            _ = try await launcher.launch(
                descriptor: sharedTestDescriptor,
                options: makeTestLaunchOptions(
                    mode: "missing_terminal_capability",
                    requiredCapabilities: ["terminals"]
                )
            )
            Issue.record("Expected unsupported capability failure.")
        } catch let error as ACPAdapterLaunchError {
            guard case .unsupportedCapability(let capability) = error else {
                Issue.record("Unexpected launch error: \(error)")
                return
            }
            #expect(capability == "terminals")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
