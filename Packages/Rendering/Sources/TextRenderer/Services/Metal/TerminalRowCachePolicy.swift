import Foundation

public struct TerminalGridSignature: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

public enum TerminalRowCachePolicy {
    public static func requiresFullReset(
        previous: TerminalGridSignature?,
        current: TerminalGridSignature,
        isFullDirty: Bool
    ) -> Bool {
        isFullDirty || previous != current
    }
}
