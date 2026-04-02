// HighlightedDiffLine.swift
// Syntax-highlighted diff line using Syntax.
//
// Combines Shiki-style syntax colors with word-diff backgrounds.
// Inspired by Pierre Diffs' beautiful syntax highlighting in diffs.

import SwiftUI
import Syntax

/// A diff line with syntax highlighting via Syntax.
/// Layers word-diff backgrounds on top of syntax token colors.
@MainActor
struct HighlightedDiffLine: View {
    let content: String
    let lineType: DiffLine.LineType
    let filePath: String
    let wordChanges: [WordDiff.Change]?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString?

    private var language: String {
        LanguageDetector.detect(from: filePath)
    }

    private var taskID: String {
        "\(content)|\(language)"
    }
    
    init(
        content: String,
        lineType: DiffLine.LineType,
        filePath: String,
        wordChanges: [WordDiff.Change]? = nil
    ) {
        self.content = content
        self.lineType = lineType
        self.filePath = filePath
        self.wordChanges = wordChanges
    }
    
    var body: some View {
        Group {
            if let highlighted = highlighted {
                Text(highlighted)
            } else {
                // Plain text fallback while highlighting loads
                Text(content)
                    .foregroundStyle(contentColor)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .task(id: taskID) {
            await loadHighlighting()
        }
    }
    
    // MARK: - Highlighting
    
    private func loadHighlighting() async {
        // Skip highlighting for empty content or headers
        guard !content.isEmpty, lineType != .header, lineType != .noNewline else {
            highlighted = AttributedString(content)
            return
        }
        
        // Get syntax-highlighted line from DevysSyntax
        let provider = HighlightProvider()
        var attrString = await provider.attributedLine(
            content,
            language: language,
            fontSize: 12,
            fontName: "Menlo"
        )
        
        // Apply word-diff backgrounds on top of syntax highlighting
        if let wordChanges = wordChanges {
            applyWordDiffHighlights(to: &attrString, changes: wordChanges)
        }
        
        highlighted = attrString
    }
    
    private func applyWordDiffHighlights(to attrString: inout AttributedString, changes: [WordDiff.Change]) {
        for change in changes where change.type != .unchanged {
            // Convert String.Index range to AttributedString range
            guard let attrStart = AttributedString.Index(change.range.lowerBound, within: attrString),
                  let attrEnd = AttributedString.Index(change.range.upperBound, within: attrString) else {
                continue
            }
            let attrRange = attrStart..<attrEnd
            
            // Apply change background
            attrString[attrRange].backgroundColor = changeBackground(for: change.type)
        }
    }
    
    // MARK: - Styling
    
    private func changeBackground(for type: WordDiff.ChangeType) -> Color {
        if let themed = themedChangeBackground(for: type) {
            return themed
        }

        switch type {
        case .added:
            return colorScheme == .dark
                ? Color.green.opacity(0.4)
                : Color.green.opacity(0.3)
        case .removed:
            return colorScheme == .dark
                ? Color.red.opacity(0.4)
                : Color.red.opacity(0.3)
        case .unchanged:
            return .clear
        }
    }

    private func themedChangeBackground(for type: WordDiff.ChangeType) -> Color? {
        let registry = ThemeRegistry()
        let themeName = colorScheme == .dark ? "github-dark" : "github-light"
        let theme = registry.resolver(for: themeName)?.theme ?? registry.currentTheme
        guard let colors = theme?.colors else { return nil }

        let keys: [String]
        switch type {
        case .added:
            keys = [
                "diffEditor.insertedTextBackground",
                "diffEditor.insertedLineBackground"
            ]
        case .removed:
            keys = [
                "diffEditor.removedTextBackground",
                "diffEditor.deletedTextBackground",
                "diffEditor.removedLineBackground",
                "diffEditor.deletedLineBackground"
            ]
        case .unchanged:
            return .clear
        }

        for key in keys {
            if let hex = colors[key], let color = Color(hex: hex) {
                return color
            }
        }
        return nil
    }

    private var contentColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 4) {
        HighlightedDiffLine(
            content: "let greeting = \"Hello, World!\"",
            lineType: .added,
            filePath: "example.swift"
        )
        
        HighlightedDiffLine(
            content: "const x = { foo: 'bar', count: 42 };",
            lineType: .context,
            filePath: "example.js"
        )
        
        HighlightedDiffLine(
            content: "def calculate(a, b):",
            lineType: .removed,
            filePath: "example.py"
        )
    }
    .padding()
    .background(Color.black)
}
#endif
