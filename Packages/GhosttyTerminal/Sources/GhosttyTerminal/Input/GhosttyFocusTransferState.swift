import Foundation

#if canImport(GhosttyKit) && os(macOS)
enum GhosttyFocusTransferOutcome: Equatable {
    case passthrough
    case focusAndConsumeClick
    case focusAndPassthrough
}

struct GhosttyFocusTransferState {
    private(set) var suppressNextLeftMouseUp = false

    mutating func handleLeftMouseDown(
        isFirstResponder: Bool,
        applicationIsActive: Bool,
        windowIsKey: Bool
    ) -> GhosttyFocusTransferOutcome {
        suppressNextLeftMouseUp = false

        guard !isFirstResponder else {
            return .passthrough
        }

        if applicationIsActive, windowIsKey {
            suppressNextLeftMouseUp = true
            return .focusAndConsumeClick
        }

        return .focusAndPassthrough
    }

    mutating func consumeSuppressedLeftMouseUp() -> Bool {
        guard suppressNextLeftMouseUp else { return false }
        suppressNextLeftMouseUp = false
        return true
    }

    mutating func clear() {
        suppressNextLeftMouseUp = false
    }
}
#endif
