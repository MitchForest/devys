public import TerminalCore

public struct TerminalTextRangeProjection: Equatable, Sendable {
    public let range: TerminalTextRange
    public let visibleStartRow: Int
    public let visibleEndRow: Int
    public let topY: Double
    public let height: Double

    public init(
        range: TerminalTextRange,
        visibleStartRow: Int,
        visibleEndRow: Int,
        topY: Double,
        height: Double
    ) {
        self.range = range
        self.visibleStartRow = max(0, visibleStartRow)
        self.visibleEndRow = max(self.visibleStartRow, visibleEndRow)
        self.topY = max(0, topY)
        self.height = max(0, height)
    }
}

public struct TerminalTextRangeProjectionSnapshot: Equatable, Sendable {
    public let snapshotRevision: UInt64
    public let projections: [TerminalTextRangeProjection]
    public let unavailableReason: TerminalTextRangeUnavailableReason?

    public init(
        snapshotRevision: UInt64 = 0,
        projections: [TerminalTextRangeProjection] = [],
        unavailableReason: TerminalTextRangeUnavailableReason? = nil
    ) {
        self.snapshotRevision = snapshotRevision
        self.projections = projections
        self.unavailableReason = unavailableReason
    }

    public static func unavailable(_ reason: TerminalTextRangeUnavailableReason) -> Self {
        Self(unavailableReason: reason)
    }
}
