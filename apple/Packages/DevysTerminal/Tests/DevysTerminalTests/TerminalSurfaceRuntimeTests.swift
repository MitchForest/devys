// Ported from the reference repo's TerminalSurfaceTests (P0-014):
// runtime lifecycle and interaction suites, nested under the serialized
// TerminalSurfaceCoreTests parent because they mutate the shared
// MetalSurfaceDiagnostics counters.

import CoreGraphics
import Foundation
import TerminalCore
@testable import TerminalSurfaceCore
import TerminalVT
import Testing

extension TerminalSurfaceCoreTests {
    @Suite
    struct RuntimeLifecycle {
        @Test
        @MainActor
        func runtimeStartupSurvivesRepeatedViewRequests() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("lifetime"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )
            let size = terminalTestPixelSize()

            runtime.startIfNeeded()
            runtime.setSurfaceSize(size)
            runtime.startIfNeeded()
            runtime.setSurfaceSize(size)
            runtime.startIfNeeded()

            try await terminalTestWait { runtime.handle != nil }

            #expect(await pty.createCount() == 1)
            #expect(runtime.handle != nil)
        }

        @Test
        @MainActor
        func runtimeOnlySendsPTYResizeForGridChanges() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("resize"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )

            runtime.setSurfaceSize(terminalTestPixelSize())
            try await terminalTestSettle()
            #expect(await pty.resizeSizes().isEmpty)

            runtime.setSurfaceSize(TerminalSurfacePixelSize(
                pixelWidth: 2000,
                pixelHeight: 1000,
                scale: 2,
                cellWidthPoints: 10,
                cellHeightPoints: 25
            ))
            try await terminalTestSettle()
            #expect(await pty.resizeSizes().isEmpty)

            runtime.setSurfaceSize(TerminalSurfacePixelSize(
                pixelWidth: 2400,
                pixelHeight: 1000,
                scale: 2,
                cellWidthPoints: 10,
                cellHeightPoints: 25
            ))
            try await terminalTestWait { await pty.resizeSizes().isEmpty == false }

            #expect(await pty.resizeSizes() == [TerminalViewportSize(cols: 120, rows: 20)])
        }

        @Test
        @MainActor
        func runtimeCoalescesResizeToLatestTransaction() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("coalesce-resize"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )

            runtime.setSurfaceSize(terminalTestPixelSize())
            try await terminalTestSettle()

            runtime.setSurfaceSize(TerminalSurfacePixelSize(
                pixelWidth: 1760,
                pixelHeight: 800,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            ))
            runtime.setSurfaceSize(TerminalSurfacePixelSize(
                pixelWidth: 1920,
                pixelHeight: 800,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            ))
            runtime.setSurfaceSize(TerminalSurfacePixelSize(
                pixelWidth: 2080,
                pixelHeight: 800,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            ))

            // Coalescing means exactly one PTY resize arrives, carrying the
            // latest grid.
            try await terminalTestWait { await pty.resizeSizes().isEmpty == false }

            #expect(await pty.resizeSizes() == [TerminalViewportSize(cols: 130, rows: 20)])
        }

        @Test
        @MainActor
        func runtimeTerminateIsExplicitPTYLifetimeBoundary() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("terminate"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )

            runtime.setSurfaceSize(terminalTestPixelSize())
            try await terminalTestWait { runtime.handle != nil }
            runtime.terminate()
            try await terminalTestWait { await pty.terminateCount() == 1 }

            #expect(await pty.terminateCount() == 1)
        }

        @Test
        @MainActor
        func runtimePublishesBellAndExitCallbacksFromPTYEvents() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let recorder = TerminalSurfaceCallbackRecorder()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("events"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: recorder.callbacks(),
                pty: pty
            )
            runtime.setSurfaceSize(terminalTestPixelSize())
            runtime.startIfNeeded()
            try await terminalTestWait { runtime.handle != nil }

            await pty.yield(.output(Data([0x07])))
            try await terminalTestWait { recorder.bellCount == 1 }
            await pty.yield(.exited(TerminalExit(exitCode: 7, signal: nil)))
            try await terminalTestWait { recorder.exits.isEmpty == false }

            #expect(recorder.bellCount == 1)
            #expect(recorder.statuses.contains(.starting))
            #expect(recorder.statuses.contains(.running))
            #expect(recorder.statuses.last == .exited)
            #expect(recorder.exits == [TerminalExit(exitCode: 7, signal: nil)])
            #expect(recorder.snapshots.last?.exit == TerminalExit(exitCode: 7, signal: nil))
        }

        @Test
        @MainActor
        func runtimeExitSnapshotReusesLatestProcessFactsWhenProbeIsEmpty() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let recorder = TerminalSurfaceCallbackRecorder()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("exit-snapshot"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: recorder.callbacks(),
                pty: pty
            )
            let latest = TerminalSnapshot(
                terminalID: TerminalID("exit-snapshot"),
                shellProcessID: 10,
                foregroundProcess: TerminalProcessIdentity(processID: 20, executableName: "vim"),
                processTree: [TerminalProcessIdentity(processID: 10, executableName: "zsh")],
                listeningPorts: [TerminalListeningPort(port: 3000, processID: 20)]
            )
            runtime.updateLatestSnapshot(latest)
            runtime.setSurfaceSize(terminalTestPixelSize())
            runtime.startIfNeeded()
            try await terminalTestWait { runtime.handle != nil }

            await pty.yield(.exited(TerminalExit(exitCode: 0, signal: nil)))
            try await terminalTestWait { recorder.snapshots.isEmpty == false }

            let snapshot = try #require(recorder.snapshots.last)
            #expect(snapshot.shellProcessID == 10)
            #expect(snapshot.foregroundProcess?.executableName == "vim")
            #expect(snapshot.processTree.map(\.processID) == [10])
            #expect(snapshot.listeningPorts.map(\.port) == [3000])
        }

        @Test
        @MainActor
        func runtimeCreateFailurePublishesFailedStatus() async throws {
            let pty = TerminalSurfaceTestPTYClient(failCreate: true)
            let recorder = TerminalSurfaceCallbackRecorder()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("create-failure"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: recorder.callbacks(),
                pty: pty
            )

            runtime.setSurfaceSize(terminalTestPixelSize())
            runtime.startIfNeeded()
            try await terminalTestWait { recorder.statuses.count == 2 }

            #expect(recorder.statuses == [.starting, .failed])
            #expect(runtime.handle == nil)
        }

        @Test
        @MainActor
        func runtimeFailedPTYResizeCanRetryAfterInterveningSurfaceChange() async throws {
            let pty = TerminalSurfaceTestPTYClient(failResizeCount: 1)
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("resize-retry"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )
            runtime.setSurfaceSize(terminalTestPixelSize())
            runtime.startIfNeeded()
            try await terminalTestWait { runtime.handle != nil }

            let changedGrid = TerminalSurfacePixelSize(
                pixelWidth: 2400,
                pixelHeight: 800,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            )
            runtime.setSurfaceSize(changedGrid)
            try await terminalTestWait { await pty.resizeSizes().count == 1 }
            runtime.setSurfaceSize(terminalTestPixelSize())
            try await terminalTestSettle()
            runtime.setSurfaceSize(changedGrid)
            try await terminalTestWait { await pty.resizeSizes().count == 2 }

            #expect(await pty.resizeSizes() == [
                TerminalViewportSize(cols: 150, rows: 20),
                TerminalViewportSize(cols: 150, rows: 20)
            ])
        }
    }
}

extension TerminalSurfaceCoreTests {
    @Suite
    struct RuntimeInteraction {
        @Test
        @MainActor
        func runtimeSelectionCallbacksReportTextAndClearToNil() {
            let recorder = TerminalSurfaceCallbackRecorder()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("selection-callbacks"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: recorder.callbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            runtime.renderSession.apply(update: TerminalSurfaceUpdate(
                surfaceState: .init(cols: 5, rows: 1),
                frameProjection: makeTerminalProjection(strings: ["hello"])
            ))

            runtime.selectionBegin(row: 0, col: 1)
            runtime.selectionMove(row: 0, col: 3)
            runtime.selectionEnd()
            runtime.clearSelection()

            #expect(recorder.selectionChanges.contains("ell"))
            #expect(recorder.selectionChanges.last == .some(nil))
        }

        @Test
        @MainActor
        func runtimeSearchHighlightsMatchesAndCyclesActiveResult() {
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("search"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            runtime.renderSession.apply(update: TerminalSurfaceUpdate(
                surfaceState: .init(cols: 10, rows: 2),
                frameProjection: makeTerminalProjection(strings: ["hello", "yellow"])
            ))

            runtime.updateSearchQuery("ell")

            #expect(runtime.searchState.isPresented)
            #expect(runtime.searchState.matchCount == 2)
            #expect(runtime.searchState.activeMatchIndex == 0)
            #expect(runtime.renderSession.searchRanges.count == 2)

            runtime.selectNextSearchMatch()
            #expect(runtime.searchState.activeMatchIndex == 1)

            runtime.closeSearch()
            #expect(runtime.searchState == TerminalSearchState())
            #expect(runtime.renderSession.searchRanges.isEmpty)
        }

        @Test
        @MainActor
        func runtimeSearchScrollsActiveScrollbackMatchIntoView() async throws {
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("search-scrollback"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            let vt = try TerminalVTRuntime(cols: 24, rows: 4)
            _ = await vt.write(Data((0..<20).map { "line-\($0)\n" }.joined().utf8))
            let initial = await vt.scrollViewport(by: 0)
            runtime.vt = vt
            runtime.surfaceUpdate = initial
            runtime.renderSession.apply(update: initial)

            runtime.updateSearchQuery("line-0")
            try await terminalTestWait {
                runtime.searchState.matchCount == 1
                    && runtime.surfaceUpdate.surfaceState.viewportOffset > 0
            }

            #expect(runtime.searchState.matchCount == 1)
            #expect(runtime.searchState.activeMatchIndex == 0)
            #expect(runtime.surfaceUpdate.surfaceState.viewportOffset > 0)
            #expect(runtime.renderSession.activeSearchRange != nil)
        }

        @Test
        @MainActor
        func runtimeTextRangeLookupReportsUnavailableStates() async throws {
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("text-range-unavailable"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )

            #expect(
                await runtime.latestTextRange(matching: TerminalTextQuery(text: "   "))
                    == .unavailable(.emptyQuery)
            )
            #expect(
                await runtime.latestTextRange(matching: TerminalTextQuery(text: "target"))
                    == .unavailable(.runtimeNotReady)
            )

            runtime.surfaceUpdate = TerminalSurfaceUpdate(
                surfaceState: .init(cols: 10, rows: 2, altScreenMode: true),
                frameProjection: makeTerminalProjection(strings: ["target"])
            )

            #expect(
                await runtime.latestTextRange(matching: TerminalTextQuery(text: "target"))
                    == .unavailable(.alternateScreen)
            )
        }

        @Test
        @MainActor
        func runtimeTextRangeLookupUsesVTRowsAndRenderRevision() async throws {
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("text-range-runtime"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            let vt = try TerminalVTRuntime(cols: 24, rows: 4)
            _ = await vt.write(Data("alpha\r\nbeta target\r\n".utf8))
            let update = await vt.scrollViewport(by: 0)
            runtime.vt = vt
            runtime.surfaceUpdate = update
            runtime.renderSession.apply(update: update)

            let result = await runtime.latestTextRange(matching: TerminalTextQuery(text: "target"))

            #expect(result == .found(TerminalTextRange(
                start: TerminalTextPosition(row: 1, column: 5),
                end: TerminalTextPosition(row: 1, column: 10),
                snapshotRevision: runtime.renderSession.renderRevision
            )))
        }

        @Test
        @MainActor
        func runtimeProjectsTextRangesThroughContentPadding() {
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("text-range-projection"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            runtime.surfaceUpdate = TerminalSurfaceUpdate(
                surfaceState: .init(cols: 80, rows: 4),
                frameProjection: .empty(cols: 80, rows: 4)
            )
            runtime.latestSurfacePixelSize = TerminalSurfacePixelSize(
                pixelWidth: 800,
                pixelHeight: 200,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 10
            )
            let range = TerminalTextRange(
                start: TerminalTextPosition(row: 1, column: 0),
                end: TerminalTextPosition(row: 1, column: 4),
                snapshotRevision: 0
            )

            let snapshot = runtime.projectTextRanges([range])

            #expect(snapshot.unavailableReason == nil)
            #expect(snapshot.projections.first?.topY == Double(TerminalSurfaceDefaults.contentPadding) + 10)
        }

        @Test
        @MainActor
        func runtimeCoalescesScrollDeltas() async throws {
            MetalSurfaceDiagnostics.reset()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("scroll"),
                launchDescriptor: .userShell(workingDirectoryPath: "/tmp"),
                callbacks: TerminalSurfaceCallbacks(),
                pty: TerminalSurfaceTestPTYClient()
            )
            let vt = try TerminalVTRuntime(cols: 80, rows: 10)
            _ = await vt.write(Data((0..<100).map { "line-\($0)\n" }.joined().utf8))
            runtime.vt = vt

            runtime.scroll(TerminalSurfaceScrollEvent(lines: -1))
            runtime.scroll(TerminalSurfaceScrollEvent(lines: -1))
            runtime.scroll(TerminalSurfaceScrollEvent(lines: -1))

            try await terminalTestWait { runtime.surfaceUpdate.surfaceState.viewportOffset == 3 }

            #expect(runtime.surfaceUpdate.surfaceState.viewportOffset == 3)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollTasksStarted == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollApplications == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollDeltasApplied == 3)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollRoutedToViewport == 1)
        }

        @Test
        @MainActor
        func runtimeSendsKeyAndPasteCommandsToPTY() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("input"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )
            runtime.vt = try TerminalVTRuntime(cols: 20, rows: 4)
            runtime.handle = await pty.testHandle()

            runtime.sendInput(.key(GhosttyTerminalKeyEvent(
                key: .a,
                text: "a",
                unshiftedCodepoint: 97
            )))
            try await terminalTestWait { await pty.sentData().count == 1 }
            #expect(await pty.sentData() == [Data("a".utf8)])

            runtime.sendInput(.paste(""))
            try await terminalTestSettle(for: .milliseconds(20))
            #expect(await pty.sentData() == [Data("a".utf8)])

            _ = await runtime.vt?.write(Data("\u{1B}[?2004h".utf8))
            runtime.sendInput(.paste("one\ntwo"))
            try await terminalTestWait { await pty.sentData().count == 2 }

            let sent = await pty.sentData()
            #expect(sent.count == 2)
            #expect(String(data: sent[1], encoding: .utf8) == "\u{1B}[200~one\ntwo\u{1B}[201~")
        }

        @Test
        @MainActor
        func runtimeSubmitsTextByPastingThenSendingEnter() async throws {
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("submit-text"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )
            runtime.vt = try TerminalVTRuntime(cols: 20, rows: 4)
            runtime.handle = await pty.testHandle()

            runtime.sendInput(.submitText(""))
            try await terminalTestSettle(for: .milliseconds(20))
            #expect(await pty.sentData().isEmpty)

            _ = await runtime.vt?.write(Data("\u{1B}[?2004h".utf8))
            runtime.sendInput(.submitText("echo hello"))
            try await terminalTestWait { await pty.sentData().count == 1 }

            let sent = await pty.sentData()
            #expect(sent.count == 1)
            #expect(String(data: sent[0], encoding: .utf8) == "\u{1B}[200~echo hello\u{1B}[201~\r")
        }

        @Test
        @MainActor
        func runtimeRoutesMouseTrackingScrollToPTY() async throws {
            MetalSurfaceDiagnostics.reset()
            let pty = TerminalSurfaceTestPTYClient()
            let runtime = TerminalSurfaceRuntime(
                terminalID: TerminalID("mouse-scroll"),
                launchDescriptor: .explicitCommand(executablePath: "/bin/sh", arguments: ["sh"]),
                callbacks: TerminalSurfaceCallbacks(),
                pty: pty
            )
            let vt = try TerminalVTRuntime(cols: 20, rows: 4)
            let update = await vt.write(Data("\u{1B}[?1000h\u{1B}[?1006h".utf8))
            runtime.vt = vt
            runtime.handle = await pty.testHandle()
            runtime.surfaceUpdate = update.surfaceUpdate

            runtime.scroll(TerminalSurfaceScrollEvent(
                lines: -1,
                positionX: 8,
                positionY: 8,
                screenWidthPx: 160,
                screenHeightPx: 64,
                cellWidthPx: 8,
                cellHeightPx: 16
            ))

            try await terminalTestWait { await pty.sentData().isEmpty == false }

            let sent = await pty.sentData()
            #expect(sent.count == 1)
            #expect(String(data: sent[0], encoding: .utf8)?.hasPrefix("\u{1B}[<64;") == true)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollRoutedToPTY == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.scrollRoutedToViewport == 0)
        }
    }
}
