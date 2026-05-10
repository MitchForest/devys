import Foundation
import TerminalComposer

/// A pattern that classifies a foreground PTY process (or terminal title) as a known
/// agent CLI, alongside the composer serialization style that should be used when
/// the agent is in the foreground.
struct TerminalAgentMatch: Equatable, Hashable, Sendable {
    var displayName: String
    var executableNames: Set<String>
    var titleSubstrings: [String]
    var serializationStyle: TerminalComposerSerializationStyle

    init(
        displayName: String,
        executableNames: Set<String>,
        titleSubstrings: [String] = [],
        serializationStyle: TerminalComposerSerializationStyle
    ) {
        self.displayName = displayName
        self.executableNames = executableNames
        self.titleSubstrings = titleSubstrings
        self.serializationStyle = serializationStyle
    }
}

/// A registry of known agent CLIs. The probe and product layer use this to decide
/// whether to surface the composer and which serialization style to apply.
///
/// The registry is intentionally explicit and small: detection is best-effort, and
/// false positives (e.g., surfacing the composer for `vim`) are worse than false
/// negatives (composer stays hidden, user falls back to ⌘L).
struct TerminalAgentRegistry: Equatable, Sendable {
    var entries: [TerminalAgentMatch]

    init(entries: [TerminalAgentMatch]) {
        self.entries = entries
    }

    /// Default registry covering the agent CLIs Devys recognizes today.
    static let `default` = TerminalAgentRegistry(entries: [
        TerminalAgentMatch(
            displayName: "Claude Code",
            executableNames: ["claude", "claude-code"],
            titleSubstrings: ["claude"],
            serializationStyle: .claudeCode
        ),
        TerminalAgentMatch(
            displayName: "Codex",
            executableNames: ["codex"],
            titleSubstrings: ["codex"],
            serializationStyle: .codex
        ),
        TerminalAgentMatch(
            displayName: "Aider",
            executableNames: ["aider"],
            titleSubstrings: ["aider"],
            // Aider does not have a dedicated serializer yet; treat as Codex-style
            // pasting until we add one.
            serializationStyle: .codex
        ),
        TerminalAgentMatch(
            displayName: "OpenCode",
            executableNames: ["opencode"],
            titleSubstrings: ["opencode"],
            serializationStyle: .codex
        ),
        TerminalAgentMatch(
            displayName: "Cursor Agent",
            executableNames: ["cursor-agent"],
            titleSubstrings: ["cursor-agent"],
            serializationStyle: .claudeCode
        ),
    ])

    /// Resolves an agent match for the given foreground signals.
    ///
    /// Executable name takes precedence over title because the title can be set by any
    /// process and is easier to spoof or have stale. Title is the SSH/remote fallback.
    func match(executableName: String?, title: String?) -> TerminalAgentMatch? {
        if let executableName, !executableName.isEmpty {
            let normalized = executableName.lowercased()
            if let entry = entries.first(where: { $0.executableNames.contains(normalized) }) {
                return entry
            }
        }
        if let title, !title.isEmpty {
            let normalizedTitle = title.lowercased()
            if let entry = entries.first(where: { entry in
                entry.titleSubstrings.contains { normalizedTitle.contains($0.lowercased()) }
            }) {
                return entry
            }
        }
        return nil
    }
}
