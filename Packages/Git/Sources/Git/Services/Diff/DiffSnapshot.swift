// periphery:ignore:all - diff source snapshots are consumed by render layout builders and tests
import Foundation
import Text

enum DiffSourceAvailability: Sendable, Equatable {
    case actual
    case unavailable
}

struct DiffVersion: Sendable, Hashable, Equatable {
    let rawValue: Int
}

struct DiffSourceLineMapping: Sendable, Equatable {
    let base: Int?
    let modified: Int?
}

struct DiffSourceDocuments: Sendable, Equatable {
    struct Identity: Sendable, Equatable {
        let textHash: Int
        let sourceLineCount: Int
        let utf8Length: Int
    }

    let version: DiffVersion
    let baseSnapshot: DocumentSnapshot
    let modifiedSnapshot: DocumentSnapshot
    let baseIdentity: Identity
    let modifiedIdentity: Identity
    let lineMappings: [DiffIdentity: DiffSourceLineMapping]
    let availability: DiffSourceAvailability

    static let empty = DiffSourceDocuments(
        version: DiffVersion(rawValue: 0),
        baseSnapshot: TextDocument(content: "").snapshot(),
        modifiedSnapshot: TextDocument(content: "").snapshot(),
        baseIdentity: Identity(textHash: 0, sourceLineCount: 0, utf8Length: 0),
        modifiedIdentity: Identity(textHash: 0, sourceLineCount: 0, utf8Length: 0),
        lineMappings: [:],
        availability: .unavailable
    )

    var baseSourceLineCount: Int {
        baseIdentity.sourceLineCount
    }

    var modifiedSourceLineCount: Int {
        modifiedIdentity.sourceLineCount
    }

    var supportsSyntaxHighlighting: Bool {
        availability == .actual
    }

    func hasSourceLines(for side: DiffSourceSide) -> Bool {
        guard supportsSyntaxHighlighting else { return false }
        return switch side {
        case .base:
            baseSourceLineCount > 0
        case .modified:
            modifiedSourceLineCount > 0
        }
    }

    func snapshot(for side: DiffSourceSide) -> DocumentSnapshot {
        switch side {
        case .base:
            baseSnapshot
        case .modified:
            modifiedSnapshot
        }
    }

    func sourceLines(for side: DiffSourceSide) -> [String] {
        switch side {
        case .base:
            lines(from: baseSnapshot, lineCount: baseSourceLineCount)
        case .modified:
            lines(from: modifiedSnapshot, lineCount: modifiedSourceLineCount)
        }
    }

    private func lines(from snapshot: DocumentSnapshot, lineCount: Int) -> [String] {
        guard lineCount > 0 else { return [] }
        return snapshot.lines(in: 0..<lineCount).map(\.text)
    }

    static func == (lhs: DiffSourceDocuments, rhs: DiffSourceDocuments) -> Bool {
        lhs.version == rhs.version &&
        lhs.availability == rhs.availability &&
        lhs.baseIdentity == rhs.baseIdentity &&
        lhs.modifiedIdentity == rhs.modifiedIdentity &&
        lhs.lineMappings == rhs.lineMappings
    }
}

struct DiffSnapshot: Sendable, Equatable {
    let version: DiffVersion
    let hunks: [DiffHunk]
    let isBinary: Bool
    let oldPath: String?
    let newPath: String?
    let sourceDocuments: DiffSourceDocuments

    static let empty = DiffSnapshot(
        version: DiffVersion(rawValue: 0),
        hunks: [],
        isBinary: false,
        oldPath: nil,
        newPath: nil,
        sourceDocuments: .empty
    )

    init(
        version: DiffVersion,
        hunks: [DiffHunk],
        isBinary: Bool,
        oldPath: String?,
        newPath: String?,
        sourceDocuments: DiffSourceDocuments
    ) {
        self.version = version
        self.hunks = hunks
        self.isBinary = isBinary
        self.oldPath = oldPath
        self.newPath = newPath
        self.sourceDocuments = sourceDocuments
    }

    init(from parsedDiff: ParsedDiff) {
        self.init(
            from: parsedDiff,
            sourceDocuments: DiffSnapshot.makeUnavailableSourceDocuments(from: parsedDiff)
        )
    }

    init(
        from parsedDiff: ParsedDiff,
        baseContent: String?,
        modifiedContent: String?
    ) {
        self.init(
            from: parsedDiff,
            sourceDocuments: DiffSnapshot.makeActualSourceDocuments(
                from: parsedDiff,
                baseContent: baseContent,
                modifiedContent: modifiedContent
            )
        )
    }

    private init(
        from parsedDiff: ParsedDiff,
        sourceDocuments: DiffSourceDocuments
    ) {
        let version = sourceDocuments.version

        self.init(
            version: version,
            hunks: parsedDiff.hunks,
            isBinary: parsedDiff.isBinary,
            oldPath: parsedDiff.oldPath,
            newPath: parsedDiff.newPath,
            sourceDocuments: sourceDocuments
        )
    }

    var hasChanges: Bool {
        !hunks.isEmpty || isBinary || oldPath != newPath
    }

    var totalAdded: Int {
        hunks.reduce(0) { $0 + $1.addedCount }
    }

    var totalRemoved: Int {
        hunks.reduce(0) { $0 + $1.removedCount }
    }
}

private extension DiffSnapshot {
    struct StableHasher {
        private var state: UInt64 = 14_695_981_039_346_656_037

        mutating func combine(_ value: String) {
            combine(bytes: value.utf8)
        }

        mutating func combine(_ value: Int) {
            combine(UInt64(bitPattern: Int64(value)))
        }

        mutating func combine(_ value: UInt64) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                combine(bytes: bytes)
            }
        }

        mutating func combine(_ value: Bool) {
            combine(value ? 1 : 0)
        }

        mutating func combine(_ value: String?) {
            guard let value else {
                combine(false)
                return
            }
            combine(true)
            combine(value)
        }

        mutating func combine<S: Sequence>(bytes: S) where S.Element == UInt8 {
            for byte in bytes {
                state ^= UInt64(byte)
                state &*= 1_099_511_628_211
            }
        }

        func finalize() -> Int {
            Int(truncatingIfNeeded: state)
        }
    }

    struct SourceMappingData {
        let lineMappings: [DiffIdentity: DiffSourceLineMapping]
        let maxBaseLineNumber: Int
        let maxModifiedLineNumber: Int
    }

    static func makeActualSourceDocuments(
        from parsedDiff: ParsedDiff,
        baseContent: String?,
        modifiedContent: String?
    ) -> DiffSourceDocuments {
        let requiresBaseContent = parsedDiff.oldPath != nil
        let requiresModifiedContent = parsedDiff.newPath != nil
        if (requiresBaseContent && baseContent == nil)
            || (requiresModifiedContent && modifiedContent == nil) {
            return makeUnavailableSourceDocuments(from: parsedDiff)
        }

        let mappingData = makeSourceMappingData(from: parsedDiff)
        let baseSnapshot = makeSnapshot(from: baseContent)
        let modifiedSnapshot = makeSnapshot(from: modifiedContent)
        let baseIdentity = makeIdentity(content: baseContent, snapshot: baseSnapshot)
        let modifiedIdentity = makeIdentity(content: modifiedContent, snapshot: modifiedSnapshot)
        let version = makeVersion(
            parsedDiff: parsedDiff,
            availability: .actual,
            baseIdentity: baseIdentity,
            modifiedIdentity: modifiedIdentity,
            lineMappings: mappingData.lineMappings
        )

        return DiffSourceDocuments(
            version: version,
            baseSnapshot: baseSnapshot,
            modifiedSnapshot: modifiedSnapshot,
            baseIdentity: baseIdentity,
            modifiedIdentity: modifiedIdentity,
            lineMappings: mappingData.lineMappings,
            availability: .actual
        )
    }

    static func makeUnavailableSourceDocuments(from parsedDiff: ParsedDiff) -> DiffSourceDocuments {
        let mappingData = makeSourceMappingData(from: parsedDiff)
        let version = makeVersion(
            parsedDiff: parsedDiff,
            availability: .unavailable,
            baseIdentity: DiffSourceDocuments.Identity(
                textHash: 0,
                sourceLineCount: mappingData.maxBaseLineNumber,
                utf8Length: 0
            ),
            modifiedIdentity: DiffSourceDocuments.Identity(
                textHash: 0,
                sourceLineCount: mappingData.maxModifiedLineNumber,
                utf8Length: 0
            ),
            lineMappings: mappingData.lineMappings
        )

        return DiffSourceDocuments(
            version: version,
            baseSnapshot: TextDocument(content: "").snapshot(),
            modifiedSnapshot: TextDocument(content: "").snapshot(),
            baseIdentity: DiffSourceDocuments.Identity(
                textHash: 0,
                sourceLineCount: mappingData.maxBaseLineNumber,
                utf8Length: 0
            ),
            modifiedIdentity: DiffSourceDocuments.Identity(
                textHash: 0,
                sourceLineCount: mappingData.maxModifiedLineNumber,
                utf8Length: 0
            ),
            lineMappings: mappingData.lineMappings,
            availability: .unavailable
        )
    }

    static func makeSourceMappingData(from parsedDiff: ParsedDiff) -> SourceMappingData {
        var lineMappings: [DiffIdentity: DiffSourceLineMapping] = [:]
        var maxBaseLineNumber = 0
        var maxModifiedLineNumber = 0

        for hunk in parsedDiff.hunks {
            for line in hunk.lines where line.type != .header {
                let baseLineIndex = line.oldLineNumber.map { max(0, $0 - 1) }
                let modifiedLineIndex = line.newLineNumber.map { max(0, $0 - 1) }

                if let baseLineIndex {
                    maxBaseLineNumber = max(maxBaseLineNumber, baseLineIndex + 1)
                }
                if let modifiedLineIndex {
                    maxModifiedLineNumber = max(maxModifiedLineNumber, modifiedLineIndex + 1)
                }

                lineMappings[line.id] = DiffSourceLineMapping(
                    base: baseLineIndex,
                    modified: modifiedLineIndex
                )
            }
        }

        return SourceMappingData(
            lineMappings: lineMappings,
            maxBaseLineNumber: maxBaseLineNumber,
            maxModifiedLineNumber: maxModifiedLineNumber
        )
    }

    static func makeSnapshot(from content: String?) -> DocumentSnapshot {
        TextDocument(content: content ?? "").snapshot()
    }

    static func makeIdentity(
        content: String?,
        snapshot: DocumentSnapshot
    ) -> DiffSourceDocuments.Identity {
        let normalizedContent = content ?? ""
        return DiffSourceDocuments.Identity(
            textHash: stableHash(for: normalizedContent),
            sourceLineCount: normalizedContent.isEmpty ? 0 : snapshot.lineCount,
            utf8Length: normalizedContent.utf8.count
        )
    }

    static func stableHash(for text: String) -> Int {
        var hasher = StableHasher()
        hasher.combine(bytes: text.utf8)
        return hasher.finalize()
    }

    static func makeVersion(
        parsedDiff: ParsedDiff,
        availability: DiffSourceAvailability,
        baseIdentity: DiffSourceDocuments.Identity,
        modifiedIdentity: DiffSourceDocuments.Identity,
        lineMappings: [DiffIdentity: DiffSourceLineMapping]
    ) -> DiffVersion {
        var hasher = StableHasher()
        hasher.combine(parsedDiff.oldPath)
        hasher.combine(parsedDiff.newPath)
        hasher.combine(parsedDiff.hunks.count)
        hasher.combine(parsedDiff.isBinary)
        hasher.combine(availability == .actual)
        hasher.combine(baseIdentity.textHash)
        hasher.combine(baseIdentity.sourceLineCount)
        hasher.combine(baseIdentity.utf8Length)
        hasher.combine(modifiedIdentity.textHash)
        hasher.combine(modifiedIdentity.sourceLineCount)
        hasher.combine(modifiedIdentity.utf8Length)
        hasher.combine(lineMappings.count)
        for key in lineMappings.keys.sorted() {
            hasher.combine(key)
            if let mapping = lineMappings[key] {
                hasher.combine(mapping.base ?? -1)
                hasher.combine(mapping.modified ?? -1)
            }
        }

        return DiffVersion(
            rawValue: hasher.finalize()
        )
    }
}
