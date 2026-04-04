import Foundation

public final class TextDocument: DocumentHandle, @unchecked Sendable {
    private let lock = NSLock()

    private var rope: Rope
    private let metadataStorage: DocumentMetadata
    private var version: DocumentVersion

    public init(
        content: String,
        metadata: DocumentMetadata = DocumentMetadata()
    ) {
        self.rope = Rope(content: content)
        self.metadataStorage = metadata
        self.version = DocumentVersion()
    }

    public var metadata: DocumentMetadata {
        lock.withLock { metadataStorage }
    }

    public func snapshot() -> DocumentSnapshot {
        lock.withLock {
            DocumentSnapshot(version: version, rope: rope)
        }
    }

    @discardableResult
    public func apply(_ transaction: EditTransaction) -> EditResult {
        lock.withLock {
            applyLocked(transaction)
        }
    }

    private func applyLocked(_ transaction: EditTransaction) -> EditResult {
        let oldVersion = version
        let oldSnapshot = DocumentSnapshot(version: oldVersion, rope: rope)

        guard !transaction.edits.isEmpty else {
            return EditResult(
                oldVersion: oldVersion,
                newVersion: oldVersion,
                invalidatedRange: .empty
            )
        }

        let sortedEdits = transaction.edits.sorted { lhs, rhs in
            lhs.range.lowerBound > rhs.range.lowerBound
        }
        validateEdits(sortedEdits, against: oldSnapshot)

        var updatedRope = rope
        var earliestInvalidatedLine = Int.max

        for edit in sortedEdits {
            let startPoint = oldSnapshot.point(at: edit.range.lowerBound, encoding: .utf8)
            earliestInvalidatedLine = min(earliestInvalidatedLine, startPoint.line)
            updatedRope = updatedRope.replacing(edit.range, with: edit.replacement)
        }

        let newVersion = oldVersion.next()
        let newSnapshot = DocumentSnapshot(version: newVersion, rope: updatedRope)

        rope = updatedRope
        version = newVersion

        let invalidatedRange = SourceLineRange(
            earliestInvalidatedLine,
            newSnapshot.lineCount
        )

        return EditResult(
            oldVersion: oldVersion,
            newVersion: newVersion,
            invalidatedRange: invalidatedRange
        )
    }

    private func validateEdits(
        _ edits: [TextEdit],
        against snapshot: DocumentSnapshot
    ) {
        var previousLowerBound = snapshot.utf8Length

        for edit in edits {
            precondition(
                edit.range.upperBound <= snapshot.utf8Length,
                "Edit range exceeds document UTF-8 length"
            )
            precondition(
                edit.range.upperBound <= previousLowerBound,
                "Edit ranges must not overlap"
            )
            previousLowerBound = edit.range.lowerBound
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
