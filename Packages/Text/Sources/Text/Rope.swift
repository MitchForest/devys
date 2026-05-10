import Foundation

private struct RopeSummary: Sendable {
    let characterCount: Int
    let utf8Length: Int
    let utf16Length: Int
    let newlineCount: Int
    let height: Int

    var lineCount: Int {
        newlineCount + 1
    }
}

private struct RopeLeaf: Sendable {
    let characterCount: Int
    let text: String
    let utf8Length: Int
    let utf16Length: Int
    let newlineUTF8Offsets: [Int]
    let newlineUTF16Offsets: [Int]

    init(text: String) {
        self.characterCount = text.count
        self.text = text
        self.utf8Length = text.utf8.count
        self.utf16Length = text.utf16.count

        var newlineUTF8Offsets: [Int] = []
        var newlineUTF16Offsets: [Int] = []
        newlineUTF8Offsets.reserveCapacity(8)
        newlineUTF16Offsets.reserveCapacity(8)

        var utf8Cursor = 0
        var utf16Cursor = 0
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if text[index] == "\n" {
                newlineUTF8Offsets.append(utf8Cursor)
                newlineUTF16Offsets.append(utf16Cursor)
            }

            let slice = text[index..<nextIndex]
            utf8Cursor += slice.utf8.count
            utf16Cursor += slice.utf16.count
            index = nextIndex
        }

        self.newlineUTF8Offsets = newlineUTF8Offsets
        self.newlineUTF16Offsets = newlineUTF16Offsets
    }

    var summary: RopeSummary {
        RopeSummary(
            characterCount: characterCount,
            utf8Length: utf8Length,
            utf16Length: utf16Length,
            newlineCount: newlineUTF8Offsets.count,
            height: 1
        )
    }
}

private struct RopeBranch: Sendable {
    let left: RopeNode
    let right: RopeNode
    let summary: RopeSummary

    init(left: RopeNode, right: RopeNode) {
        self.left = left
        self.right = right
        self.summary = RopeSummary(
            characterCount: left.summary.characterCount + right.summary.characterCount,
            utf8Length: left.summary.utf8Length + right.summary.utf8Length,
            utf16Length: left.summary.utf16Length + right.summary.utf16Length,
            newlineCount: left.summary.newlineCount + right.summary.newlineCount,
            height: max(left.summary.height, right.summary.height) + 1
        )
    }
}

private indirect enum RopeNode: Sendable {
    case leaf(RopeLeaf)
    case branch(RopeBranch)

    static let chunkUTF8Length = 2048

    var summary: RopeSummary {
        switch self {
        case .leaf(let leaf):
            return leaf.summary
        case .branch(let branch):
            return branch.summary
        }
    }

    static func make(from text: String) -> RopeNode {
        guard !text.isEmpty else {
            return .leaf(RopeLeaf(text: ""))
        }

        var chunks: [RopeNode] = []
        chunks.reserveCapacity(max(1, text.utf8.count / chunkUTF8Length))

        var chunkStart = text.startIndex
        var chunkUTF8Length = 0
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            chunkUTF8Length += text[index..<nextIndex].utf8.count

            if chunkUTF8Length >= Self.chunkUTF8Length {
                chunks.append(.leaf(RopeLeaf(text: String(text[chunkStart..<nextIndex]))))
                chunkStart = nextIndex
                chunkUTF8Length = 0
            }

            index = nextIndex
        }

        if chunkStart < text.endIndex {
            chunks.append(.leaf(RopeLeaf(text: String(text[chunkStart...] ))))
        }

        return buildBalancedTree(from: chunks)
    }

    static func buildBalancedTree(from nodes: [RopeNode]) -> RopeNode {
        guard !nodes.isEmpty else {
            return .leaf(RopeLeaf(text: ""))
        }
        guard nodes.count > 1 else {
            return nodes[0]
        }

        let midpoint = nodes.count / 2
        let left = buildBalancedTree(from: Array(nodes[..<midpoint]))
        let right = buildBalancedTree(from: Array(nodes[midpoint...]))
        return concatenate(left, right)
    }

    static func concatenate(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if left.summary.utf8Length == 0 {
            return right
        }
        if right.summary.utf8Length == 0 {
            return left
        }

        if case .leaf(let leftLeaf) = left,
           case .leaf(let rightLeaf) = right,
           leftLeaf.utf8Length + rightLeaf.utf8Length <= chunkUTF8Length {
            return .leaf(RopeLeaf(text: leftLeaf.text + rightLeaf.text))
        }

        return balance(.branch(RopeBranch(left: left, right: right)))
    }

    static func balance(_ node: RopeNode) -> RopeNode {
        guard case .branch(let branch) = node else {
            return node
        }

        let balanceFactor = branch.left.summary.height - branch.right.summary.height
        if balanceFactor > 1 {
            return rotateRight(branch)
        }
        if balanceFactor < -1 {
            return rotateLeft(branch)
        }

        return node
    }

    static func rotateLeft(_ branch: RopeBranch) -> RopeNode {
        guard case .branch(let rightBranch) = branch.right else {
            return .branch(branch)
        }

        let adjustedRight = if rightBranch.left.summary.height > rightBranch.right.summary.height {
            rotateRight(rightBranch).asBranch
        } else {
            rightBranch
        }

        let newLeft = RopeNode.branch(
            RopeBranch(left: branch.left, right: adjustedRight.left)
        )
        return .branch(
            RopeBranch(left: newLeft, right: adjustedRight.right)
        )
    }

    static func rotateRight(_ branch: RopeBranch) -> RopeNode {
        guard case .branch(let leftBranch) = branch.left else {
            return .branch(branch)
        }

        let adjustedLeft = if leftBranch.right.summary.height > leftBranch.left.summary.height {
            rotateLeft(leftBranch).asBranch
        } else {
            leftBranch
        }

        let newRight = RopeNode.branch(
            RopeBranch(left: adjustedLeft.right, right: branch.right)
        )
        return .branch(
            RopeBranch(left: adjustedLeft.left, right: newRight)
        )
    }

    private var asBranch: RopeBranch {
        guard case .branch(let branch) = self else {
            preconditionFailure("Expected rope branch node")
        }
        return branch
    }

    func split(at utf8Offset: Int) -> (RopeNode, RopeNode) {
        precondition(utf8Offset >= 0, "Split offset must be non-negative")
        precondition(utf8Offset <= summary.utf8Length, "Split offset exceeds rope length")

        switch self {
        case .leaf(let leaf):
            let index = stringIndex(in: leaf.text, utf8Offset: utf8Offset)
            let left = RopeNode.make(from: String(leaf.text[..<index]))
            let right = RopeNode.make(from: String(leaf.text[index...]))
            return (left, right)

        case .branch(let branch):
            let leftLength = branch.left.summary.utf8Length
            if utf8Offset < leftLength {
                let (leftPrefix, leftSuffix) = branch.left.split(at: utf8Offset)
                return (
                    leftPrefix,
                    RopeNode.concatenate(leftSuffix, branch.right)
                )
            }
            if utf8Offset == leftLength {
                return (branch.left, branch.right)
            }

            let (rightPrefix, rightSuffix) = branch.right.split(at: utf8Offset - leftLength)
            return (
                RopeNode.concatenate(branch.left, rightPrefix),
                rightSuffix
            )
        }
    }

    func appendUTF8Slice(
        _ range: Range<Int>,
        to output: inout String
    ) {
        guard range.lowerBound < range.upperBound else {
            return
        }

        switch self {
        case .leaf(let leaf):
            let startIndex = stringIndex(in: leaf.text, utf8Offset: range.lowerBound)
            let endIndex = stringIndex(in: leaf.text, utf8Offset: range.upperBound)
            output.append(contentsOf: leaf.text[startIndex..<endIndex])

        case .branch(let branch):
            let leftLength = branch.left.summary.utf8Length
            if range.lowerBound < leftLength {
                let leftUpperBound = min(range.upperBound, leftLength)
                branch.left.appendUTF8Slice(range.lowerBound..<leftUpperBound, to: &output)
            }
            if range.upperBound > leftLength {
                let rightLowerBound = max(0, range.lowerBound - leftLength)
                let rightUpperBound = range.upperBound - leftLength
                branch.right.appendUTF8Slice(rightLowerBound..<rightUpperBound, to: &output)
            }
        }
    }

    func newlineCount(
        before offset: Int,
        encoding: TextEncoding
    ) -> Int {
        switch self {
        case .leaf(let leaf):
            let offsets = switch encoding {
            case .utf8:
                leaf.newlineUTF8Offsets
            case .utf16:
                leaf.newlineUTF16Offsets
            }
            return insertionIndex(of: offset, in: offsets)

        case .branch(let branch):
            let leftLength = switch encoding {
            case .utf8:
                branch.left.summary.utf8Length
            case .utf16:
                branch.left.summary.utf16Length
            }

            if offset <= leftLength {
                return branch.left.newlineCount(before: offset, encoding: encoding)
            }

            return branch.left.summary.newlineCount
                + branch.right.newlineCount(before: offset - leftLength, encoding: encoding)
        }
    }

    func offset(
        afterNewlineOrdinal ordinal: Int,
        encoding: TextEncoding
    ) -> Int {
        precondition(ordinal >= 0, "Newline ordinal must be non-negative")
        precondition(
            ordinal < summary.newlineCount,
            "Newline ordinal exceeds document newline count"
        )

        switch self {
        case .leaf(let leaf):
            let offsets = switch encoding {
            case .utf8:
                leaf.newlineUTF8Offsets
            case .utf16:
                leaf.newlineUTF16Offsets
            }
            return offsets[ordinal] + 1

        case .branch(let branch):
            let leftNewlineCount = branch.left.summary.newlineCount
            if ordinal < leftNewlineCount {
                return branch.left.offset(afterNewlineOrdinal: ordinal, encoding: encoding)
            }

            let leftLength = switch encoding {
            case .utf8:
                branch.left.summary.utf8Length
            case .utf16:
                branch.left.summary.utf16Length
            }
            return leftLength
                + branch.right.offset(
                    afterNewlineOrdinal: ordinal - leftNewlineCount,
                    encoding: encoding
                )
        }
    }
}

struct Rope: Sendable {
    fileprivate let root: RopeNode

    init(content: String) {
        self.root = RopeNode.make(from: content)
    }

    fileprivate init(root: RopeNode) {
        self.root = root
    }

    var utf8Length: Int {
        root.summary.utf8Length
    }

    var characterCount: Int {
        root.summary.characterCount
    }

    var utf16Length: Int {
        root.summary.utf16Length
    }

    var lineCount: Int {
        root.summary.lineCount
    }

    func replacing(
        _ range: TextByteRange,
        with replacement: String
    ) -> Rope {
        let (prefix, suffixWithRange) = root.split(at: range.lowerBound)
        let (_, suffix) = suffixWithRange.split(at: range.upperBound - range.lowerBound)
        let replacementNode = RopeNode.make(from: replacement)
        return Rope(
            root: RopeNode.concatenate(
                RopeNode.concatenate(prefix, replacementNode),
                suffix
            )
        )
    }

    func slice(_ range: TextByteRange) -> TextSlice {
        validateUTF8Offset(range.lowerBound)
        validateUTF8Offset(range.upperBound)

        var text = ""
        text.reserveCapacity(max(0, range.upperBound - range.lowerBound))
        root.appendUTF8Slice(range.range, to: &text)
        return TextSlice(range: range, text: text)
    }

    func line(_ index: Int) -> LineSlice {
        validateLineIndex(index)
        let range = lineUTF8Range(for: index)
        return LineSlice(lineIndex: index, text: slice(range).text)
    }

    func lines(in range: Range<Int>) -> LineCollection {
        validateLineRange(range)
        return LineCollection(range.map { line($0) })
    }

    func offset(
        of point: TextPoint,
        encoding: TextEncoding
    ) -> Int {
        validateLineIndex(point.line)

        let lineLength = lineLength(at: point.line, encoding: encoding)
        precondition(
            point.column <= lineLength,
            "Column \(point.column) exceeds line length \(lineLength)"
        )

        return lineStartOffset(for: point.line, encoding: encoding) + point.column
    }

    func point(
        at offset: Int,
        encoding: TextEncoding
    ) -> TextPoint {
        switch encoding {
        case .utf8:
            validateUTF8Offset(offset)
        case .utf16:
            validateUTF16Offset(offset)
        }

        let line = root.newlineCount(before: offset, encoding: encoding)
        let lineStart = lineStartOffset(for: line, encoding: encoding)
        return TextPoint(line: line, column: offset - lineStart)
    }

    private func lineLength(
        at lineIndex: Int,
        encoding: TextEncoding
    ) -> Int {
        switch encoding {
        case .utf8:
            let range = lineUTF8Range(for: lineIndex)
            return range.upperBound - range.lowerBound
        case .utf16:
            let start = lineStartOffset(for: lineIndex, encoding: .utf16)
            let end = lineIndex == lineCount - 1
                ? utf16Length
                : lineStartOffset(for: lineIndex + 1, encoding: .utf16) - 1
            return end - start
        }
    }

    private func lineUTF8Range(for lineIndex: Int) -> TextByteRange {
        let start = lineStartOffset(for: lineIndex, encoding: .utf8)
        let end = lineIndex == lineCount - 1
            ? utf8Length
            : lineStartOffset(for: lineIndex + 1, encoding: .utf8) - 1
        return TextByteRange(start, end)
    }

    private func lineStartOffset(
        for lineIndex: Int,
        encoding: TextEncoding
    ) -> Int {
        validateLineIndex(lineIndex)
        guard lineIndex > 0 else {
            return 0
        }

        return root.offset(
            afterNewlineOrdinal: lineIndex - 1,
            encoding: encoding
        )
    }

    private func validateLineIndex(_ index: Int) {
        precondition(index >= 0, "Line index must be non-negative")
        precondition(index < lineCount, "Line index \(index) exceeds line count \(lineCount)")
    }

    private func validateLineRange(_ range: Range<Int>) {
        precondition(range.lowerBound >= 0, "Line range lowerBound must be non-negative")
        precondition(range.upperBound >= range.lowerBound, "Line range upperBound must be >= lowerBound")
        precondition(range.upperBound <= lineCount, "Line range upperBound exceeds line count")
    }

    private func validateUTF8Offset(_ offset: Int) {
        precondition(offset >= 0, "UTF-8 offset must be non-negative")
        precondition(offset <= utf8Length, "UTF-8 offset exceeds document length")
    }

    private func validateUTF16Offset(_ offset: Int) {
        precondition(offset >= 0, "UTF-16 offset must be non-negative")
        precondition(offset <= utf16Length, "UTF-16 offset exceeds document length")
    }
}

private func stringIndex(
    in text: String,
    utf8Offset: Int
) -> String.Index {
    let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: utf8Offset)
    guard let stringIndex = String.Index(utf8Index, within: text) else {
        preconditionFailure("UTF-8 offset \(utf8Offset) is not aligned to a scalar boundary")
    }
    return stringIndex
}

private func insertionIndex(
    of value: Int,
    in sortedValues: [Int]
) -> Int {
    var low = 0
    var high = sortedValues.count

    while low < high {
        let midpoint = (low + high) / 2
        if sortedValues[midpoint] < value {
            low = midpoint + 1
        } else {
            high = midpoint
        }
    }

    return low
}
