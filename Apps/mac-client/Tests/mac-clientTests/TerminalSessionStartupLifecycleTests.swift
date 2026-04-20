import Foundation
import GhosttyTerminal
import Testing
@testable import mac_client

@Suite("Terminal Session Startup Lifecycle Tests")
struct TerminalSessionStartupLifecycleTests {
    @Test("First surface update keeps startup explicit until a rendered frame arrives")
    func firstSurfaceUpdateDoesNotMarkReady() {
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstSurfaceUpdate(from: .startingShell)
                == .startingShell
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstSurfaceUpdate(from: .startingHost)
                == .startingHost
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstSurfaceUpdate(from: .awaitingViewport)
                == .awaitingViewport
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstSurfaceUpdate(from: .ready)
                == .ready
        )
    }

    @Test("Startup becomes ready only after output, a surface update, and an interactive frame")
    func renderedFrameRequiresOutputSurfaceAndInteractiveState() {
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstRenderableFrame(
                from: .startingShell,
                hasSurfaceUpdate: false,
                hasInteractiveFrame: true,
                hasOutputChunk: true
            ) == .startingShell
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstRenderableFrame(
                from: .startingShell,
                hasSurfaceUpdate: true,
                hasInteractiveFrame: false,
                hasOutputChunk: true
            ) == .startingShell
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstRenderableFrame(
                from: .startingShell,
                hasSurfaceUpdate: true,
                hasInteractiveFrame: true,
                hasOutputChunk: false
            ) == .startingShell
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterFirstRenderableFrame(
                from: .startingShell,
                hasSurfaceUpdate: true,
                hasInteractiveFrame: true,
                hasOutputChunk: true
            ) == .ready
        )
    }

    @Test("Host ready stays explicit about whether viewport measurement is complete")
    func hostReadyPhaseDependsOnViewportMeasurement() {
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterHostReady(viewportReady: false)
                == .awaitingViewport
        )
        #expect(
            TerminalSessionStartupLifecycle.phaseAfterHostReady(viewportReady: true)
                == .startingShell
        )
    }

    @Test("Early close stays explicit instead of leaving startup hanging")
    func earlyCloseFailsStartup() {
        #expect(TerminalSessionStartupLifecycle.phaseAfterClose(from: .startingShell) == .failed)
        #expect(
            TerminalSessionStartupLifecycle.closeDescription(
                exitCode: nil,
                signal: nil,
                startupPhase: .startingShell
            ) == "Shell exited before the first frame arrived."
        )
    }

    @Test("Ready terminals preserve normal close semantics")
    func readyTerminalClosePreservesReadyState() {
        #expect(TerminalSessionStartupLifecycle.phaseAfterClose(from: .ready) == .ready)
        #expect(
            TerminalSessionStartupLifecycle.closeDescription(
                exitCode: 0,
                signal: nil,
                startupPhase: .ready
            ) == nil
        )
    }

    @Test("Launcher tabs use the compatibility shell profile")
    func launcherTabsUseCompatibilityShell() {
        #expect(launcherTerminalLaunchProfile(for: .claude) == .compatibilityShell)
        #expect(launcherTerminalLaunchProfile(for: .codex) == .compatibilityShell)
    }

    @Test("Launcher executable shorthand resolves to the canonical executable name")
    func launcherExecutableShorthand() {
        #expect(launcherExecutableName("cc", for: .claude) == "claude")
        #expect(launcherExecutableName("cx", for: .codex) == "codex")
        #expect(launcherExecutableName("/usr/local/bin/claude", for: .claude) == "/usr/local/bin/claude")
    }

    @Test("Launcher command routing always stages delivery until after attach")
    @MainActor
    func launcherCommandRoutingMatchesExecutionBehavior() {
        let runImmediately = launcherCommandRouting(
            command: "claude",
            launcherDisplayName: "Claude",
            launcherExecutable: "claude",
            executionBehavior: .runImmediately
        )
        #expect(runImmediately.stagedCommand == nil)
        #expect(runImmediately.requestedCommand?.contains("command -v claude") == true)
        #expect(runImmediately.requestedCommand?.contains("printf") == true)
        #expect(runImmediately.requestedCommand?.contains("launcher executable") == true)
        #expect(runImmediately.requestedCommand?.contains("was not found on PATH.") == true)
        #expect(runImmediately.requestedCommand?.contains("exec \"${SHELL:-/bin/zsh}\" -i -l") == true)

        let staged = launcherCommandRouting(
            command: "claude",
            launcherDisplayName: "Claude",
            launcherExecutable: "claude",
            executionBehavior: .stageInTerminal
        )
        #expect(staged.requestedCommand == nil)
        #expect(staged.stagedCommand == "claude")
    }

    @Test("Launcher auto-run script surfaces missing executables inline")
    func launcherAutoRunScriptIncludesFailureMessage() {
        let script = launcherAutoRunScript(
            command: "env DEVYS_WORKSPACE_ID=test claude --dangerously-skip-permissions",
            launcherDisplayName: "Claude",
            launcherExecutable: "claude"
        )

        #expect(script.contains("command -v claude") == true)
        #expect(script.contains("\nelse\n") == true)
        #expect(script.contains("printf") == true)
        #expect(script.contains("launcher executable") == true)
        #expect(script.contains("was not found on PATH.") == true)
        #expect(script.contains("exec \"${SHELL:-/bin/zsh}\" -i -l") == true)
        #expect((try? shellSyntaxStatus(for: script)) == 0)
    }
}

private func shellSyntaxStatus(for script: String) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-n", "-c", script]
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
