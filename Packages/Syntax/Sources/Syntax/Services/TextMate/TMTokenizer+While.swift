// TMTokenizer+While.swift
// DevysSyntax

import Foundation

extension TMTokenizer {
    // MARK: - While Handling

    /// Ensure begin/while rules are valid for the current line.
    /// If a while pattern fails at line start, pop the state and re-check.
    func resolveWhileStateAtLineStart(line: String, state: RuleStack) -> RuleStack {
        var currentState = state
        var guardCount = 0

        while true {
            guardCount += 1
            if guardCount > 100 { break }

            let whileFrames = currentState.whileFrames()
            if whileFrames.isEmpty { break }

            var didPop = false
            for whileInfo in whileFrames {
                let match = tryMatch(
                    pattern: whileInfo.pattern,
                    in: line,
                    at: 0,
                    anchorPosition: whileInfo.anchor
                )
                if let match, match.startOffset == 0 {
                    continue
                }

                currentState = currentState.popTo(depth: whileInfo.index - 1)
                didPop = true
                break
            }

            if !didPop { break }
        }

        return currentState
    }

    /// If an end pattern can match at the end of the line (zero-length),
    /// pop the state so the next line starts cleanly.
    func resolveEndStateAtLineEnd(line: String, state: RuleStack) -> RuleStack {
        var currentState = state
        var guardCount = 0
        while let endPattern = currentState.endPattern {
            guardCount += 1
            if guardCount > 100 { break }

            if let match = tryMatch(
                pattern: endPattern,
                in: line,
                at: line.utf16Count,
                anchorPosition: currentState.anchorPosition
            ) {
                if match.startOffset == line.utf16Count {
                    currentState = currentState.pop()
                    continue
                }
                break
            }

            if patternHasEndAnchor(endPattern)
                || endPattern.contains("\\z")
                || endPattern.contains("\\Z") {
                if let match = tryMatch(
                    pattern: endPattern,
                    in: line,
                    at: 0,
                    anchorPosition: currentState.anchorPosition
                ), match.endOffset == line.utf16Count {
                    currentState = currentState.pop()
                    continue
                }
            }

            if endPattern.contains("\\n") {
                let lineWithNewline = line + "\n"
                if let match = tryMatch(
                    pattern: endPattern,
                    in: lineWithNewline,
                    at: line.utf16Count,
                    anchorPosition: currentState.anchorPosition
                ), match.startOffset == line.utf16Count {
                    currentState = currentState.pop()
                    continue
                }
            }

            break
        }

        return currentState
    }

    private func patternHasEndAnchor(_ pattern: String) -> Bool {
        var escaped = false
        var inCharacterClass = false

        for char in pattern {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                continue
            }
            if char == "[" {
                inCharacterClass = true
                continue
            }
            if char == "]", inCharacterClass {
                inCharacterClass = false
                continue
            }
            if char == "$", !inCharacterClass {
                return true
            }
        }

        return false
    }
}
