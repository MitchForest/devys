import Foundation

public struct SemanticOverlayStyle: Sendable, Hashable, Equatable {
    public let foregroundColor: String?
    public let backgroundColor: String?
    public let fontStyle: FontStyle?

    public init(
        foregroundColor: String? = nil,
        backgroundColor: String? = nil,
        fontStyle: FontStyle? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.fontStyle = fontStyle
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(foregroundColor)
        hasher.combine(backgroundColor)
        hasher.combine(fontStyle?.rawValue)
    }
}

public struct SemanticOverlayToken: Sendable, Hashable, Equatable {
    public let range: Range<Int>
    public let style: SemanticOverlayStyle

    public init(
        range: Range<Int>,
        style: SemanticOverlayStyle
    ) {
        self.range = range
        self.style = style
    }
}

public struct SemanticOverlayLine: Sendable, Hashable, Equatable {
    public let lineIndex: Int
    public let tokens: [SemanticOverlayToken]

    public init(
        lineIndex: Int,
        tokens: [SemanticOverlayToken]
    ) {
        self.lineIndex = lineIndex
        self.tokens = tokens
    }
}

public struct SemanticOverlaySnapshot: Sendable, Equatable {
    public let revision: Int
    private let linesByIndex: [Int: SemanticOverlayLine]

    public static let empty = SemanticOverlaySnapshot(lines: [])

    public init(lines: [SemanticOverlayLine]) {
        self.linesByIndex = Dictionary(uniqueKeysWithValues: lines.map { ($0.lineIndex, $0) })
        self.revision = Self.makeRevision(linesByIndex: linesByIndex)
    }

    public func line(_ index: Int) -> SemanticOverlayLine? {
        linesByIndex[index]
    }

    public var fingerprint: Int {
        revision
    }

    private static func makeRevision(linesByIndex: [Int: SemanticOverlayLine]) -> Int {
        var hasher = Hasher()
        for key in linesByIndex.keys.sorted() {
            guard let line = linesByIndex[key] else { continue }
            hasher.combine(line.lineIndex)
            for token in line.tokens {
                hasher.combine(token.range.lowerBound)
                hasher.combine(token.range.upperBound)
                hasher.combine(token.style.foregroundColor)
                hasher.combine(token.style.backgroundColor)
                hasher.combine(token.style.fontStyle?.rawValue)
            }
        }
        return hasher.finalize()
    }
}
