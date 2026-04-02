// CommandCleaner.swift
// Cleans shell commands for display in the UI.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Cleans shell commands for display by removing wrapper scripts and prefixes.
public struct CommandCleaner {

    /// Cleans a command string for UI display.
    ///
    /// Removes:
    /// - Shell wrappers like `/bin/zsh -lc "actual command"`
    /// - `cd /path &&` prefixes
    /// - Redundant quotes
    public static func clean(_ command: String) -> String {
        var result = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove shell wrapper: `/bin/zsh -lc "actual command"` or `/bin/bash -c "..."`
        // Pattern: /bin/(ba)?sh -[flags] "..."
        let shellWrapperPattern = #"^/bin/(?:ba)?sh\s+(?:-\w+\s+)*[\"'](.+?)[\"']$"#
        if let range = result.range(of: shellWrapperPattern, options: .regularExpression) {
            // Extract the inner command
            let matched = String(result[range])
            if let quoteStart = matched.firstIndex(of: "\"") ?? matched.firstIndex(of: "'"),
               let quoteEnd = matched.lastIndex(of: "\"") ?? matched.lastIndex(of: "'"),
               quoteStart < quoteEnd {
                let innerStart = matched.index(after: quoteStart)
                result = String(matched[innerStart..<quoteEnd])
            }
        }
        
        // Also handle: /bin/zsh -lc 'command' (with single quotes)
        if result.hasPrefix("/bin/") {
            // Try to extract command from common patterns
            let patterns = [
                #"^/bin/zsh\s+-lc\s+[\"'](.+)[\"']$"#,
                #"^/bin/bash\s+-c\s+[\"'](.+)[\"']$"#,
                #"^/bin/sh\s+-c\s+[\"'](.+)[\"']$"#
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                   match.numberOfRanges > 1,
                   let captureRange = Range(match.range(at: 1), in: result) {
                    result = String(result[captureRange])
                    break
                }
            }
        }
        
        // Remove cd prefix: `cd /some/path && actual command`
        if result.hasPrefix("cd ") {
            if let andIndex = result.range(of: " && ") {
                result = String(result[andIndex.upperBound...])
            }
        }
        
        // Trim again
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove redundant outer quotes
        if result.count > 2 {
            if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
               (result.hasPrefix("'") && result.hasSuffix("'")) {
                result = String(result.dropFirst().dropLast())
            }
        }
        
        return result.isEmpty ? command : result
    }
}
