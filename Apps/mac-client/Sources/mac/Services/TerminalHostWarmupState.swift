struct TerminalHostWarmupState {
    private(set) var hasRequestedWarmup = false

    mutating func beginIfNeeded() -> Bool {
        guard hasRequestedWarmup == false else { return false }
        hasRequestedWarmup = true
        return true
    }
}
