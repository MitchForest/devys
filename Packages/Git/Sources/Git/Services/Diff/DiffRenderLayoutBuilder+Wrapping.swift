// DiffRenderLayoutBuilder+Wrapping.swift

import Foundation

extension DiffRenderLayoutBuilder {
    struct WrappedSegment {
        let content: String
        let wordChanges: [DiffWordChange]?
    }

    static func wrapContent(
        _ content: String,
        wordChanges: [DiffWordChange]?,
        maxChars: Int
    ) -> [WrappedSegment] {
        guard content.count > maxChars else {
            return [WrappedSegment(content: content, wordChanges: wordChanges)]
        }

        var segments: [WrappedSegment] = []
        var start = 0
        let total = content.count

        while start < total {
            let length = min(maxChars, total - start)
            let startIndex = content.index(content.startIndex, offsetBy: start)
            let endIndex = content.index(startIndex, offsetBy: length)
            let segmentText = String(content[startIndex..<endIndex])
            let segmentRange = start..<start + length

            let segmentChanges = wordChanges?.compactMap { change -> DiffWordChange? in
                guard change.range.overlaps(segmentRange) else { return nil }
                let lower = max(change.range.lowerBound, segmentRange.lowerBound) - start
                let upper = min(change.range.upperBound, segmentRange.upperBound) - start
                guard lower < upper else { return nil }
                return DiffWordChange(range: lower..<upper, type: change.type)
            }

            segments.append(WrappedSegment(content: segmentText, wordChanges: segmentChanges))
            start += length
        }

        return segments
    }

    static func toWordChanges(_ changes: [WordDiff.Change], in content: String) -> [DiffWordChange] {
        changes.compactMap { change in
            let lower = content.distance(from: content.startIndex, to: change.range.lowerBound)
            let upper = content.distance(from: content.startIndex, to: change.range.upperBound)
            guard lower < upper else { return nil }
            return DiffWordChange(range: lower..<upper, type: change.type)
        }
    }
}
