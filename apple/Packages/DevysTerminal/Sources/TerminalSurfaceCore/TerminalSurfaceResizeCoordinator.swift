import TerminalCore

struct TerminalSurfaceResizeApplication: Equatable, Sendable {
    var transaction: TerminalSurfaceResizeTransaction
    var shouldResizeVT: Bool
    var shouldResizePTY: Bool
}

struct TerminalSurfaceResizeCoordinator: Sendable {
    private(set) var latestViewportSize = TerminalViewportSize()
    private(set) var hasMeasuredViewport = false
    private var lastObservedTransaction: TerminalSurfaceResizeTransaction?
    private var pendingTransaction: TerminalSurfaceResizeTransaction?
    private var lastAppliedVTTransaction: TerminalSurfaceResizeTransaction?
    private var lastAppliedPTYSize: TerminalViewportSize?

    var hasPendingTransaction: Bool {
        pendingTransaction != nil
    }

    mutating func observe(_ transaction: TerminalSurfaceResizeTransaction) -> Bool {
        hasMeasuredViewport = true
        latestViewportSize = transaction.size

        guard transaction != lastObservedTransaction else {
            return false
        }

        lastObservedTransaction = transaction
        pendingTransaction = transaction
        return true
    }

    mutating func takePendingTransaction() -> TerminalSurfaceResizeTransaction? {
        let transaction = pendingTransaction
        pendingTransaction = nil
        return transaction
    }

    mutating func markInitialPTYSizeApplied(_ size: TerminalViewportSize) {
        lastAppliedPTYSize = size
    }

    func application(for transaction: TerminalSurfaceResizeTransaction) -> TerminalSurfaceResizeApplication {
        TerminalSurfaceResizeApplication(
            transaction: transaction,
            shouldResizeVT: transaction != lastAppliedVTTransaction,
            shouldResizePTY: transaction.size != lastAppliedPTYSize
        )
    }

    mutating func markApplied(_ application: TerminalSurfaceResizeApplication, ptyResizeSucceeded: Bool) {
        if application.shouldResizeVT {
            lastAppliedVTTransaction = application.transaction
        }
        if application.shouldResizePTY, ptyResizeSucceeded {
            lastAppliedPTYSize = application.transaction.size
        }
    }
}
