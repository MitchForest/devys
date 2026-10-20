// TerminalRowCachePolicy.swift
// Devys - Decides when the per-row GPU cell cache must be rebuilt.

public struct TerminalGridSignature: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
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
