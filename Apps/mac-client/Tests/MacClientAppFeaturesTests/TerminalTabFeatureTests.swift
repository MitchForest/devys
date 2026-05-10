import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class TerminalTabFeatureTests: XCTestCase {
    func testInitialProjectRootSeedsWorkingDirectory() {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let state = TerminalTabFeature.State(projectRootURL: rootURL)

        XCTAssertEqual(state.projectRootURL, rootURL.standardizedFileURL)
        XCTAssertEqual(state.workingDirectoryURL, rootURL.standardizedFileURL)
        XCTAssertEqual(state.composerPresentation, .transientBottomDrawer)
    }

    func testWorkingDirectorySignalIsReducerOwned() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let cwdURL = rootURL.appendingPathComponent("Packages/UI")
        let store = TestStore(initialState: TerminalTabFeature.State(projectRootURL: rootURL)) {
            TerminalTabFeature()
        }

        await store.send(.workingDirectoryChanged(cwdURL)) {
            $0.workingDirectoryURL = cwdURL.standardizedFileURL
        }
    }

    func testProjectRootCandidateCanBeDismissed() async {
        let candidate = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: TerminalTabFeature.State()) {
            TerminalTabFeature()
        }

        await store.send(.pendingProjectRootCandidateChanged(candidate)) {
            $0.pendingProjectRootCandidateURL = candidate.standardizedFileURL
        }
        await store.send(.dismissProjectRootCandidate(candidate)) {
            $0.dismissedProjectRootCandidatePaths = [candidate.standardizedFileURL.path]
            $0.pendingProjectRootCandidateURL = nil
        }
        await store.send(.pendingProjectRootCandidateChanged(candidate))
    }

    func testCloseRiskIsReducerVisible() async {
        let risk = TerminalTabCloseRisk(displayName: "vim", detail: "vim is active")
        let store = TestStore(initialState: TerminalTabFeature.State()) {
            TerminalTabFeature()
        }

        await store.send(.closeRiskChanged(risk)) {
            $0.closeRisk = risk
        }
        await store.send(.closeRiskChanged(nil)) {
            $0.closeRisk = nil
        }
    }

    func testComposerIntentsAreReducerOwned() async {
        let store = TestStore(initialState: TerminalTabFeature.State()) {
            TerminalTabFeature()
        }

        await store.send(.focusComposerRequested) {
            $0.isComposerPresented = true
            $0.composerIntent = .focus
        }
        await store.send(.composerIntentHandled) {
            $0.composerIntent = nil
        }
        await store.send(.pasteIntoComposerRequested) {
            $0.isComposerPresented = true
            $0.composerIntent = .paste
        }
        await store.send(.captureSelectionIntoComposerRequested) {
            $0.isComposerPresented = true
            $0.composerIntent = .captureSelection
        }
    }

    func testComposerPresentationVisibilityIsReducerOwned() async {
        let store = TestStore(initialState: TerminalTabFeature.State()) {
            TerminalTabFeature()
        }

        await store.send(.composerPresentationChanged(true)) {
            $0.isComposerPresented = true
        }
        await store.send(.composerPresentationChanged(false)) {
            $0.isComposerPresented = false
        }
    }
}
