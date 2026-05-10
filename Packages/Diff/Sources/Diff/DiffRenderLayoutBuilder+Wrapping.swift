// DiffRenderLayoutBuilder+Wrapping.swift

import Foundation

extension DiffRenderLayoutBuilder {
    struct WrappedSegment {
        let content: String
        let wordChanges: [DiffWordChange]?
        let utf16Range: Range<Int>
    }

    static func wrapContent(
        _ content: String,
        wordChanges: [DiffWordChange]?,
        maxChars: Int
    ) -> [WrappedSegment] {
        guard content.count > maxChars else {
            return [
                WrappedSegment(
                    content: content,
                    wordChanges: wordChanges,
                    utf16Range: 0..<content.utf16.count
                )
            ]
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
            let utf16View = content.utf16
            guard
                let utf16Start = startIndex.samePosition(in: utf16View),
                let utf16End = endIndex.samePosition(in: utf16View)
            else {
                assertionFailure("Failed to project wrapped diff segment into UTF-16 coordinates")
                break
            }
            let utf16Lower = utf16View.distance(from: utf16View.startIndex, to: utf16Start)
            let utf16Upper = utf16View.distance(from: utf16View.startIndex, to: utf16End)

            let segmentChanges = wordChanges?.compactMap { change -> DiffWordChange? in
                guard change.range.overlaps(segmentRange) else { return nil }
                let lower = max(change.range.lowerBound, segmentRange.lowerBound) - start
                let upper = min(change.range.upperBound, segmentRange.upperBound) - start
                guard lower < upper else { return nil }
                return DiffWordChange(range: lower..<upper, type: change.type)
            }

            segments.append(
                WrappedSegment(
                    content: segmentText,
                    wordChanges: segmentChanges,
                    utf16Range: utf16Lower..<utf16Upper
                )
            )
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
