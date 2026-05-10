import Foundation

public struct DocumentSnapshot: Sendable {
    public let version: DocumentVersion
    public let characterCount: Int
    public let lineCount: Int
    public let utf8Length: Int
    public let utf16Length: Int

    private let rope: Rope

    init(
        version: DocumentVersion,
        rope: Rope
    ) {
        self.version = version
        self.characterCount = rope.characterCount
        self.lineCount = rope.lineCount
        self.utf8Length = rope.utf8Length
        self.utf16Length = rope.utf16Length
        self.rope = rope
    }

    public func line(_ index: Int) -> LineSlice {
        rope.line(index)
    }

    public func lines(in range: Range<Int>) -> LineCollection {
        rope.lines(in: range)
    }

    public func slice(_ range: TextByteRange) -> TextSlice {
        rope.slice(range)
    }

    public func offset(of point: TextPoint, encoding: TextEncoding) -> Int {
        rope.offset(of: point, encoding: encoding)
    }

    public func point(at offset: Int, encoding: TextEncoding) -> TextPoint {
        rope.point(at: offset, encoding: encoding)
    }
}
