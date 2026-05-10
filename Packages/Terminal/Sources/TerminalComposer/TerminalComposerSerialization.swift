import Foundation

public enum TerminalComposerSerializationStyle: String, Codable, CaseIterable, Sendable {
    case shell
    case codex
    case claudeCode
}

public enum TerminalComposerSerializer {
    public static func serialize(
        draft: String,
        chips: [TerminalComposerChip],
        style: TerminalComposerSerializationStyle
    ) -> String {
        switch style {
        case .shell:
            shell(draft: draft, chips: chips)
        case .codex:
            agent(draft: draft, chips: chips, pathPrefix: "@", blockPrefix: "codex")
        case .claudeCode:
            agent(draft: draft, chips: chips, pathPrefix: "/attach ", blockPrefix: "claude")
        }
    }

    private static func shell(draft: String, chips: [TerminalComposerChip]) -> String {
        var lines: [String] = []
        var command = draft
        let pathArguments = chips.compactMap(\.path).map(shellQuote)
        if !pathArguments.isEmpty {
            command = ([command] + pathArguments)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        if !command.isEmpty {
            lines.append(command)
        }
        lines.append(contentsOf: chips.compactMap(shellBlock))
        return lines.joined(separator: "\n")
    }

    private static func shellBlock(_ chip: TerminalComposerChip) -> String? {
        guard let text = chip.text else { return nil }
        let compactID = chip.id.uuidString.replacingOccurrences(of: "-", with: "")
        let marker = "DEVYS_\(chip.kind.rawValue.uppercased())_\(compactID)"
        return "cat <<'\(marker)'\n\(text)\n\(marker)"
    }

    private static func agent(
        draft: String,
        chips: [TerminalComposerChip],
        pathPrefix: String,
        blockPrefix: String
    ) -> String {
        var lines = draft.isEmpty ? [] : [draft]
        for chip in chips {
            if let path = chip.path {
                lines.append("\(pathPrefix)\(path)")
            } else if let text = chip.text {
                lines.append("<\(blockPrefix)-\(chip.kind.rawValue) lines=\"\(chip.lineCount ?? 0)\">")
                lines.append(text)
                lines.append("</\(blockPrefix)-\(chip.kind.rawValue)>")
            } else {
                lines.append("<\(blockPrefix)-\(chip.kind.rawValue) />")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
