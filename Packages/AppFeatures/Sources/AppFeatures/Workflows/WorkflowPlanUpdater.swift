import Foundation

public enum WorkflowPlanUpdater {
    public static func appendFollowUp(
        content: String,
        request: WorkflowPlanAppendRequest
    ) throws -> String {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw WorkflowPlanUpdaterError.emptyTicketText
        }

        var lines = content.components(separatedBy: .newlines)
        let phaseRanges = phaseRanges(in: lines)
        guard phaseRanges.indices.contains(request.phaseIndex) else {
            throw WorkflowPlanUpdaterError.invalidPhaseIndex(request.phaseIndex)
        }

        let phaseRange = phaseRanges[request.phaseIndex]
        let originalHasTrailingNewline = content.hasSuffix("\n")
        let ticketLine = "- [ ] \(text)"

        if let sectionRange = existingSectionRange(
            in: lines,
            phaseRange: phaseRange,
            sectionTitle: request.sectionTitle
        ) {
            var insertionIndex = sectionRange.upperBound
            while insertionIndex > sectionRange.lowerBound,
                  lines[insertionIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertionIndex -= 1
            }
            lines.insert(ticketLine, at: insertionIndex)
        } else {
            var insertionIndex = phaseRange.upperBound
            while insertionIndex > phaseRange.lowerBound,
                  lines[insertionIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertionIndex -= 1
            }

            var block: [String] = []
            if insertionIndex > phaseRange.lowerBound,
               !lines[insertionIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                block.append("")
            }
            block.append("### \(request.sectionTitle)")
            block.append(ticketLine)
            lines.insert(contentsOf: block, at: insertionIndex)
        }

        let updated = lines.joined(separator: "\n")
        guard originalHasTrailingNewline else { return updated }
        return updated.hasSuffix("\n") ? updated : "\(updated)\n"
    }
}

public enum WorkflowPlanUpdaterError: LocalizedError, Equatable {
    case emptyTicketText
    case invalidPhaseIndex(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyTicketText:
            "Workflow follow-up text is empty."
        case .invalidPhaseIndex(let phaseIndex):
            "Workflow phase \(phaseIndex + 1) does not exist in the current plan file."
        }
    }
}

private extension WorkflowPlanUpdater {
    static func phaseRanges(
        in lines: [String]
    ) -> [Range<Int>] {
        let phaseHeadings = lines.enumerated().compactMap { index, rawLine -> Int? in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("## ") ? index : nil
        }

        guard !phaseHeadings.isEmpty else {
            return [0 ..< lines.count]
        }

        return phaseHeadings.enumerated().map { offset, startIndex in
            let endIndex = phaseHeadings[safe: offset + 1] ?? lines.count
            return startIndex ..< endIndex
        }
    }

    static func existingSectionRange(
        in lines: [String],
        phaseRange: Range<Int>,
        sectionTitle: String
    ) -> Range<Int>? {
        var activeSectionStart: Int?
        let bodyStart = phaseRange.lowerBound + 1
        let normalizedSectionTitle = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        for index in bodyStart ..< phaseRange.upperBound {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("### ") else { continue }

            let heading = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let activeSectionStart {
                return activeSectionStart ..< index
            }

            if heading.compare(
                normalizedSectionTitle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame {
                activeSectionStart = index + 1
            }
        }

        guard let activeSectionStart else { return nil }
        return activeSectionStart ..< phaseRange.upperBound
    }
}
