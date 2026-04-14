import Testing
@testable import GhosttyTerminal

@Suite("Ghostty Focus Transfer State Tests")
struct GhosttyFocusTransferStateTests {
    @Test("Focused terminal clicks pass through unchanged")
    func focusedTerminalClicksPassThrough() {
        var state = GhosttyFocusTransferState()

        let outcome = state.handleLeftMouseDown(
            isFirstResponder: true,
            applicationIsActive: true,
            windowIsKey: true
        )

        #expect(outcome == .passthrough)
        #expect(state.consumeSuppressedLeftMouseUp() == false)
    }

    @Test("Focus transfer click is consumed in active key window")
    func focusTransferClickIsConsumed() {
        var state = GhosttyFocusTransferState()

        let outcome = state.handleLeftMouseDown(
            isFirstResponder: false,
            applicationIsActive: true,
            windowIsKey: true
        )

        #expect(outcome == .focusAndConsumeClick)
        let firstMouseUpSuppression = state.consumeSuppressedLeftMouseUp()
        let secondMouseUpSuppression = state.consumeSuppressedLeftMouseUp()
        #expect(firstMouseUpSuppression)
        #expect(secondMouseUpSuppression == false)
    }

    @Test("Inactive app focus transfer preserves the click")
    func inactiveAppFocusTransferPreservesClick() {
        var state = GhosttyFocusTransferState()

        let outcome = state.handleLeftMouseDown(
            isFirstResponder: false,
            applicationIsActive: false,
            windowIsKey: false
        )

        #expect(outcome == .focusAndPassthrough)
        #expect(state.consumeSuppressedLeftMouseUp() == false)
    }
}
