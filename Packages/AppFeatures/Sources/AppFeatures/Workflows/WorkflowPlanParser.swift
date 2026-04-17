import Foundation

public enum WorkflowPlanParser {
    public static func parse(
        content: String,
        planFilePath: String
    ) -> WorkflowPlanSnapshot {
        let lines = content.components(separatedBy: .newlines)
        var phases: [WorkflowPlanPhase] = []
        var currentPhaseTitle: String?
        var currentPhaseHeadingLine = 0
        var currentPhaseTickets: [WorkflowPlanTicket] = []
        var currentSection: WorkflowPlanSection = .phaseBody

        func flushPhase() {
            guard let currentPhaseTitle else { return }
            let phaseIndex = phases.count + 1
            let normalizedTitle = currentPhaseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = normalizedTitle.isEmpty ? "Phase \(phaseIndex)" : normalizedTitle
            phases.append(
                WorkflowPlanPhase(
                    id: "phase-\(phaseIndex)",
                    title: title,
                    headingLine: currentPhaseHeadingLine,
                    tickets: currentPhaseTickets
                )
            )
        }

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("### ") {
                if currentPhaseTitle == nil {
                    currentPhaseTitle = "Phase 1"
                    currentPhaseHeadingLine = 1
                }
                currentSection = section(forHeading: String(line.dropFirst(4)))
                continue
            }

            if line.hasPrefix("## ") {
                flushPhase()
                currentPhaseTitle = String(line.dropFirst(3))
                currentPhaseHeadingLine = index + 1
                currentPhaseTickets = []
                currentSection = .phaseBody
                continue
            }

            guard let ticket = ticket(from: line, lineNumber: index + 1, section: currentSection) else {
                continue
            }

            if currentPhaseTitle == nil {
                currentPhaseTitle = "Phase 1"
                currentPhaseHeadingLine = index + 1
            }
            currentPhaseTickets.append(ticket)
        }

        flushPhase()
        return WorkflowPlanSnapshot(planFilePath: planFilePath, phases: phases)
    }
}

extension WorkflowPlanParser {
    static func section(forHeading heading: String) -> WorkflowPlanSection {
        let normalized = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.compare("follow-ups", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return .followUps
        }
        return .named(normalized)
    }

    static func ticket(
        from line: String,
        lineNumber: Int,
        section: WorkflowPlanSection
    ) -> WorkflowPlanTicket? {
        if let ticket = checkboxTicket(from: line, lineNumber: lineNumber, section: section) {
            return ticket
        }
        if let ticket = bulletTicket(from: line, lineNumber: lineNumber, section: section) {
            return ticket
        }
        return nil
    }

    static func checkboxTicket(
        from line: String,
        lineNumber: Int,
        section: WorkflowPlanSection
    ) -> WorkflowPlanTicket? {
        let lowercased = line.lowercased()
        guard lowercased.hasPrefix("- [") || lowercased.hasPrefix("* [") else {
            return nil
        }
        guard line.count >= 6 else { return nil }

        let markerIndex = line.index(line.startIndex, offsetBy: 3)
        let marker = line[markerIndex].lowercased()
        let isCompleted = marker == "x"
        let textStart = line.index(line.startIndex, offsetBy: 6)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return WorkflowPlanTicket(
            id: "line-\(lineNumber)",
            text: text,
            isCompleted: isCompleted,
            line: lineNumber,
            section: section
        )
    }

    static func bulletTicket(
        from line: String,
        lineNumber: Int,
        section: WorkflowPlanSection
    ) -> WorkflowPlanTicket? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return WorkflowPlanTicket(
            id: "line-\(lineNumber)",
            text: text,
            isCompleted: false,
            line: lineNumber,
            section: section
        )
    }
}
