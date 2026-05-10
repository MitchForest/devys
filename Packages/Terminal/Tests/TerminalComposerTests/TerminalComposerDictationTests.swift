import TerminalComposer
import XCTest

@MainActor
final class TerminalComposerDictationTests: XCTestCase {
    func testDictatingStateCommitsTranscriptIntoTargetDraft() {
        let model = TerminalComposerModel()
        model.registerTarget(
            id: TerminalTargetID(),
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )

        model.startDictation()
        XCTAssertEqual(
            model.mode,
            .dictating(
                TerminalComposerDictatingState(
                    transcript: "",
                    baseDraft: "",
                    selectedRange: .insertion(at: 0)
                )
            )
        )

        model.updateDictationTranscript("run tests")
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "run tests")
        XCTAssertEqual(model.mode, .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false)))
    }

    func testDictationAppendsAtCursorAndPreservesExistingDraft() {
        let model = registeredModel()
        model.updateActiveDraft("run  now")

        model.startDictation(selection: .insertion(at: 4))
        model.updateDictationTranscript("tests")
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "run tests now")
    }

    func testDictationReplacesSelectionOnly() {
        let model = registeredModel()
        model.updateActiveDraft("run placeholder now")

        model.startDictation(selection: TerminalComposerTextRange(location: 4, length: 11))
        model.updateDictationTranscript("tests")
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "run tests now")
    }

    func testDictationKeepsFinalTextAndReplacesOnlyVolatileText() {
        let model = registeredModel()
        model.updateActiveDraft("run ")

        model.startDictation(selection: .insertion(at: model.activeDraft.count))
        model.updateDictationTranscript("tests", isFinal: false)
        XCTAssertEqual(model.activeDraft, "run tests")

        model.updateDictationTranscript("tests", isFinal: true)
        XCTAssertEqual(model.activeDraft, "run tests")

        model.updateDictationTranscript("and lint", isFinal: false)
        XCTAssertEqual(model.activeDraft, "run tests and lint")

        model.updateDictationTranscript("and lint", isFinal: true)
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "run tests and lint")
    }

    func testDictationDoesNotDuplicateRepeatedFinalTranscript() {
        let model = registeredModel()
        model.startDictation(selection: .insertion(at: model.activeDraft.count))

        model.updateDictationTranscript("Audit this PR for senior quality completion.", isFinal: false)
        model.updateDictationTranscript("Audit this PR for senior quality completion.", isFinal: true)
        model.updateDictationTranscript("audit this PR for senior quality completion.", isFinal: true)
        model.updateDictationTranscript("Audit this PR for senior quality completion", isFinal: true)
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "Audit this PR for senior quality completion.")
    }

    func testDictationDoesNotDuplicateRepeatedPartialAfterFinalTranscript() {
        let model = registeredModel()
        model.startDictation(selection: .insertion(at: model.activeDraft.count))

        model.updateDictationTranscript("Audit this PR for senior quality completion.", isFinal: true)
        model.updateDictationTranscript("audit this PR for senior quality completion.", isFinal: false)
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "Audit this PR for senior quality completion.")
    }

    func testDictationAcceptsCumulativeTranscriptWithoutRepeatingCommittedPrefix() {
        let model = registeredModel()
        model.startDictation(selection: .insertion(at: model.activeDraft.count))

        model.updateDictationTranscript("run tests", isFinal: true)
        model.updateDictationTranscript("run tests and lint", isFinal: false)
        XCTAssertEqual(model.activeDraft, "run tests and lint")

        model.updateDictationTranscript("run tests and lint", isFinal: true)
        model.finishDictation()

        XCTAssertEqual(model.activeDraft, "run tests and lint")
    }

    func testDictationCancelRestoresBaseDraft() {
        let model = registeredModel()
        model.updateActiveDraft("keep this")

        model.startDictation(selection: .insertion(at: 5))
        model.updateDictationTranscript("do not ")
        model.cancelDictation()

        XCTAssertEqual(model.activeDraft, "keep this")
        XCTAssertEqual(model.mode, .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false)))
    }

    func testEscapeDuringDictationCancelsWithoutRoutingToTerminal() {
        let model = registeredModel()
        model.updateActiveDraft("keep this")
        model.startDictation(selection: .insertion(at: model.activeDraft.count))
        model.updateDictationTranscript(" discarded")

        let destination = model.escape()

        XCTAssertEqual(destination, .composer)
        XCTAssertEqual(model.activeDraft, "keep this")
        XCTAssertEqual(model.mode, .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false)))
    }

    private func registeredModel() -> TerminalComposerModel {
        let model = TerminalComposerModel()
        model.registerTarget(
            id: TerminalTargetID(),
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )
        return model
    }
}
