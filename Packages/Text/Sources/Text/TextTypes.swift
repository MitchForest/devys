import Foundation

public protocol DocumentHandle: AnyObject {
    func snapshot() -> DocumentSnapshot
    @discardableResult
    func apply(_ transaction: EditTransaction) -> EditResult
    var metadata: DocumentMetadata { get }
}

public struct DocumentVersion: Sendable, Hashable, Comparable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }

    public static func < (lhs: DocumentVersion, rhs: DocumentVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func next() -> DocumentVersion {
        DocumentVersion(rawValue + 1)
    }
}

public struct DocumentMetadata: Sendable, Equatable {
    public let fileURL: URL?
    public let languageIdentifier: String

    public init(
        fileURL: URL? = nil,
        languageIdentifier: String = "plaintext"
    ) {
        self.fileURL = fileURL
        self.languageIdentifier = languageIdentifier
    }
}

public enum TextEncoding: Sendable {
    case utf8
    case utf16
}

public struct TextPoint: Sendable, Hashable, Equatable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        precondition(line >= 0, "TextPoint.line must be non-negative")
        precondition(column >= 0, "TextPoint.column must be non-negative")
        self.line = line
        self.column = column
    }
}

public struct TextByteRange: Sendable, Hashable, Equatable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(_ lowerBound: Int, _ upperBound: Int) {
        precondition(lowerBound >= 0, "TextByteRange.lowerBound must be non-negative")
        precondition(upperBound >= lowerBound, "TextByteRange.upperBound must be >= lowerBound")
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var range: Range<Int> {
        lowerBound..<upperBound
    }
}

public struct SourceLineRange: Sendable, Hashable, Equatable {
    public let lowerBound: Int
    public let upperBound: Int

    public static let empty = SourceLineRange(0, 0)

    public init(_ lowerBound: Int, _ upperBound: Int) {
        precondition(lowerBound >= 0, "SourceLineRange.lowerBound must be non-negative")
        precondition(upperBound >= lowerBound, "SourceLineRange.upperBound must be >= lowerBound")
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var range: Range<Int> {
        lowerBound..<upperBound
    }
}

public enum SelectionIntent: Sendable, Equatable {
    case preserveExisting
    case collapseToInsertionEnd
    case selectReplacement
}

public struct TextEdit: Sendable, Hashable, Equatable {
    public let range: TextByteRange
    public let replacement: String

    public init(range: TextByteRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

public struct EditTransaction: Sendable, Equatable {
    public let edits: [TextEdit]
    public let selectionIntent: SelectionIntent?

    public init(
        edits: [TextEdit],
        selectionIntent: SelectionIntent? = nil
    ) {
        self.edits = edits
        self.selectionIntent = selectionIntent
    }
}

public struct EditResult: Sendable, Equatable {
    public let oldVersion: DocumentVersion
    public let newVersion: DocumentVersion
    public let invalidatedRange: SourceLineRange

    public init(
        oldVersion: DocumentVersion,
        newVersion: DocumentVersion,
        invalidatedRange: SourceLineRange
    ) {
        self.oldVersion = oldVersion
        self.newVersion = newVersion
        self.invalidatedRange = invalidatedRange
    }
}

public struct LineSlice: Sendable, Equatable {
    public let lineIndex: Int
    public let text: String

    public init(lineIndex: Int, text: String) {
        self.lineIndex = lineIndex
        self.text = text
    }
}

public struct LineCollection: RandomAccessCollection, Sendable, Equatable {
    public typealias Element = LineSlice
    public typealias Index = Int

    private let storage: [LineSlice]

    public init(_ storage: [LineSlice]) {
        self.storage = storage
    }

    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public subscript(position: Int) -> LineSlice {
        storage[position]
    }
}

public struct TextSlice: Sendable, Equatable {
    public let range: TextByteRange
    public let text: String

    public init(range: TextByteRange, text: String) {
        self.range = range
        self.text = text
    }
}
