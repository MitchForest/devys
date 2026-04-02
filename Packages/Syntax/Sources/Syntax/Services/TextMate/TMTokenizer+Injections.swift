import Foundation

extension TMTokenizer {
    func injectionPatterns(
        for state: RuleStack,
        grammar: TMGrammar
    ) -> ([TMPattern], [TMPattern]) {
        guard let injections = grammar.injections, !injections.isEmpty else {
            return ([], [])
        }

        var left: [TMPattern] = []
        var right: [TMPattern] = []

        for (selector, pattern) in injections {
            let (priority, cleanedSelector) = parseInjectionSelector(selector)
            if selectorMatches(cleanedSelector, scopes: state.scopes) {
                switch priority {
                case .left: left.append(pattern)
                case .right: right.append(pattern)
                }
            }
        }

        return (left, right)
    }
}

private extension TMTokenizer {
    enum InjectionPriority {
        case left
        case right
    }

    func parseInjectionSelector(_ selector: String) -> (InjectionPriority, String) {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("L:") {
            let cleaned = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.left, cleaned)
        }
        if trimmed.hasPrefix("R:") {
            let cleaned = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.right, cleaned)
        }
        return (.right, trimmed)
    }

    func selectorMatches(_ selector: String, scopes: [String]) -> Bool {
        let selectors = selector.split(separator: ",")
        for raw in selectors {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if matchesIncludeExclude(trimmed, scopes: scopes) {
                return true
            }
        }
        return false
    }

    func matchesIncludeExclude(_ selector: String, scopes: [String]) -> Bool {
        let parts = selector
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let include = parts.first else { return false }
        guard matchesSelector(include, scopes: scopes) else { return false }

        if parts.count > 1 {
            for exclude in parts.dropFirst() where matchesSelector(exclude, scopes: scopes) {
                return false
            }
        }

        return true
    }

    func matchesSelector(_ selector: String, scopes: [String]) -> Bool {
        let parts = selector.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }

        var scopeIndex = 0
        for part in parts {
            var found = false
            while scopeIndex < scopes.count {
                if scopes[scopeIndex].hasPrefix(part) {
                    found = true
                    scopeIndex += 1
                    break
                }
                scopeIndex += 1
            }
            if !found { return false }
        }

        return true
    }
}
