public struct TerminalTextPosition: Codable, Equatable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = max(0, row)
        self.column = max(0, column)
    }
}

public struct TerminalTextRange: Codable, Equatable, Sendable {
    public let start: TerminalTextPosition
    public let end: TerminalTextPosition
    public let snapshotRevision: UInt64

    public init(
        start: TerminalTextPosition,
        end: TerminalTextPosition,
        snapshotRevision: UInt64
    ) {
        self.start = start
        self.end = end
        self.snapshotRevision = snapshotRevision
    }
}

public struct TerminalTextQuery: Equatable, Sendable {
    public let text: String
    public let searchLimitRows: Int

    public init(text: String, searchLimitRows: Int = 2_000) {
        self.text = text
        self.searchLimitRows = max(1, searchLimitRows)
    }
}

public enum TerminalTextRangeUnavailableReason: String, Equatable, Sendable {
    case runtimeNotReady
    case alternateScreen
    case emptyQuery
}

public enum TerminalTextRangeLookupResult: Equatable, Sendable {
    case found(TerminalTextRange)
    case notFound
    case unavailable(TerminalTextRangeUnavailableReason)
}
