# Shiki-Compatible Syntax Highlighting Integration

> Build a native Swift TextMate tokenizer that replicates Shiki's exact syntax highlighting across **all surfaces** in Devys.

---

## Executive Summary

Implement a unified syntax highlighting engine using TextMate grammars and Shiki themes that works across:

1. **File Viewer** (M1) — Read-only file preview with highlighting
2. **Agent Chat** (M2) — Code blocks in Claude/Codex responses
3. **Git Diffs** (M3) — Syntax-highlighted diff lines
4. **Code Editor** (M4) — Full editor integration with incremental tokenization
5. **Terminal** (M5) — Theme sync (ANSI palette from Shiki theme)

**Result**: Exact Shiki color parity for 17 languages, 13 themes, across all code surfaces.

---

## Architecture: Dual-Layer System

VS Code and Cursor use a dual-layer approach. We do the same:

```
┌─────────────────────────────────────────────────────────────────┐
│                          DevysSyntax                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌───────────────────────────┐  ┌─────────────────────────────┐ │
│  │    TextMate Layer         │  │     TreeSitter Layer       │ │
│  │    (OUR IMPLEMENTATION)   │  │     (EXISTING/SEPARATE)    │ │
│  │                           │  │                             │ │
│  │  • Syntax coloring ✨     │  │  • Code folding             │ │
│  │  • Shiki theme support    │  │  • Bracket matching         │ │
│  │  • Font styles            │  │  • Symbol outline           │ │
│  │  • Exact color parity     │  │  • Smart selection          │ │
│  │                           │  │  • Error recovery           │ │
│  └───────────────────────────┘  └─────────────────────────────┘ │
│            │                              │                      │
│            ▼                              ▼                      │
│  ┌───────────────────┐         ┌─────────────────────┐          │
│  │  AttributedString │         │  AST / Structure    │          │
│  │  (visual colors)  │         │  (code intelligence)│          │
│  └───────────────────┘         └─────────────────────┘          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

| System | Optimized For | We Use For |
|--------|---------------|------------|
| **TextMate** | Visual accuracy, theme ecosystem | Syntax coloring |
| **TreeSitter** | Structural accuracy, incremental parsing | Code intelligence |

---

## Package Structure

```
Packages/DevysSyntax/
├── Package.swift
├── Sources/
│   └── DevysSyntax/
│       ├── Oniguruma/
│       │   ├── OnigRegex.swift              # Swift wrapper for Oniguruma C lib
│       │   └── OnigScanner.swift            # Multi-pattern scanner
│       │
│       ├── TextMate/
│       │   ├── TMGrammar.swift              # Grammar data model (Codable)
│       │   ├── TMTokenizer.swift            # Core tokenization engine
│       │   ├── TMRegistry.swift             # Grammar loading & caching
│       │   ├── ScopeStack.swift             # Scope name management
│       │   └── RuleStack.swift              # Pattern state machine
│       │
│       ├── Theme/
│       │   ├── ShikiTheme.swift             # Theme data model (Codable)
│       │   ├── ThemeResolver.swift          # Scope → color resolution
│       │   └── ThemeRegistry.swift          # Theme loading, selection, persistence
│       │
│       ├── Integration/
│       │   ├── HighlightedCodeBlock.swift   # SwiftUI view for code blocks
│       │   ├── ShikiHighlightProvider.swift # CodeEditSourceEditor integration
│       │   ├── DiffHighlighter.swift        # Diff view highlighting
│       │   ├── LanguageDetector.swift       # File extension → language mapping
│       │   └── HighlightCache.swift         # Performance optimization
│       │
│       └── Resources/
│           ├── Grammars/                    # TextMate grammar JSON files
│           │   ├── swift.json
│           │   ├── python.json
│           │   ├── javascript.json
│           │   └── ... (17 languages)
│           │
│           └── Themes/                      # Shiki theme JSON files
│               ├── github-dark.json
│               ├── github-light.json
│               ├── vitesse-dark.json
│               └── ... (13 themes)
│
└── Tests/
    └── DevysSyntaxTests/
        ├── OnigurumTests.swift
        ├── TMTokenizerTests.swift
        ├── ThemeResolverTests.swift
        └── IntegrationTests.swift
```

---

## Surface Adapters

### 1. File Viewer (Milestone 1)

Simple async highlighting for read-only file preview.

```swift
// Integration/FileViewerHighlighter.swift

import SwiftUI

struct FileViewerPanel: View {
    let url: URL
    @State private var content: String = ""
    @State private var highlightedContent: AttributedString?
    @Environment(ThemeRegistry.self) private var themeRegistry
    
    private var language: String {
        LanguageDetector.detect(from: url.path)
    }
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                lineNumbersView
                
                Group {
                    if let highlighted = highlightedContent {
                        Text(highlighted)
                    } else {
                        Text(content)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            }
        }
        .task(id: url) {
            await loadAndHighlight()
        }
    }
    
    private func loadAndHighlight() async {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
            guard let resolver = themeRegistry.resolver() else { return }
            
            highlightedContent = await SyntaxHighlighter.highlight(
                code: content,
                language: language,
                resolver: resolver
            )
        } catch {
            content = "Error: \(error.localizedDescription)"
        }
    }
}
```

---

### 2. Agent Chat Code Blocks (Milestone 2)

Highlight code blocks in agent responses.

```swift
// Integration/HighlightedCodeBlock.swift

import SwiftUI

/// Renders a code block with Shiki-style syntax highlighting
struct HighlightedCodeBlock: View {
    let code: String
    let language: String
    
    @Environment(ThemeRegistry.self) private var themeRegistry
    @State private var highlightedContent: AttributedString?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    CopyButton(text: code)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            // Highlighted code
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if let highlighted = highlightedContent {
                        Text(highlighted)
                    } else {
                        Text(code)
                            .foregroundStyle(.primary)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
            }
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: code + language) {
            await highlight()
        }
    }
    
    private var codeBackground: Color {
        if let theme = themeRegistry.currentTheme,
           let bgHex = theme.colors?.editorBackground {
            return Color(nsColor: NSColor(hex: bgHex) ?? .black)
        }
        return Color(nsColor: .controlBackgroundColor)
    }
    
    private func highlight() async {
        guard let resolver = themeRegistry.resolver() else { return }
        
        highlightedContent = await SyntaxHighlighter.highlight(
            code: code,
            language: language,
            resolver: resolver
        )
    }
}

// Usage in Agent Chat
struct AgentMessageView: View {
    let message: AgentMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.blocks, id: \.id) { block in
                switch block.type {
                case .text:
                    Text(block.content)
                    
                case .code:
                    HighlightedCodeBlock(
                        code: block.content,
                        language: block.language ?? "plaintext"
                    )
                    
                case .thinking:
                    ThinkingBlock(content: block.content)
                }
            }
        }
    }
}
```

---

### 3. Git Diff Highlighting (Milestone 3)

Per-line highlighting for diff views.

```swift
// Integration/DiffHighlighter.swift

import SwiftUI

/// Highlights diff line content using TextMate grammars
@MainActor
class DiffHighlighter {
    private var tokenizers: [String: TMTokenizer] = [:]
    
    func highlight(
        line: String,
        languageId: String,
        resolver: ThemeResolver
    ) -> AttributedString {
        let tokenizer = getTokenizer(for: languageId)
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        
        var attributed = AttributedString(line)
        
        for token in result.tokens {
            let style = resolver.resolve(scopes: token.scopes)
            applyStyle(&attributed, token: token, style: style)
        }
        
        return attributed
    }
    
    private func getTokenizer(for languageId: String) -> TMTokenizer {
        if let cached = tokenizers[languageId] {
            return cached
        }
        
        do {
            let grammar = try TMRegistry.shared.grammar(for: languageId)
            let tokenizer = TMTokenizer(grammar: grammar)
            tokenizers[languageId] = tokenizer
            return tokenizer
        } catch {
            // Fallback to plain text
            return TMTokenizer(grammar: .plainText)
        }
    }
}

// Usage in DiffLineView
struct DiffLineView: View {
    let line: DiffLine
    let languageId: String
    
    @Environment(ThemeRegistry.self) private var themeRegistry
    @State private var highlighter = DiffHighlighter()
    
    var body: some View {
        HStack(spacing: 0) {
            lineNumbers
            indicator
            
            // Syntax-highlighted content
            Text(highlightedContent)
                .font(.system(size: 11, design: .monospaced))
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(diffBackground)
    }
    
    private var highlightedContent: AttributedString {
        guard let resolver = themeRegistry.resolver() else {
            return AttributedString(line.content)
        }
        
        return highlighter.highlight(
            line: line.content,
            languageId: languageId,
            resolver: resolver
        )
    }
}
```

---

### 4. Code Editor (Milestone 4)

Full integration with CodeEditSourceEditor using incremental tokenization.

```swift
// Integration/ShikiHighlightProvider.swift

import CodeEditSourceEditor
import AppKit

/// Provides TextMate-based syntax highlighting for CodeEditSourceEditor
class ShikiHighlightProvider: HighlightProviding {
    private let tokenizer: TMTokenizer
    private let resolver: ThemeResolver
    
    /// Line state cache for incremental tokenization
    private var lineStates: [Int: RuleStack] = [:]
    
    init(languageId: String, themeName: String) throws {
        let grammar = try TMRegistry.shared.grammar(for: languageId)
        self.tokenizer = TMTokenizer(grammar: grammar)
        
        guard let resolver = ThemeRegistry.shared.resolver(for: themeName) else {
            throw HighlightError.themeNotFound(themeName)
        }
        self.resolver = resolver
    }
    
    func queryHighlightsFor(
        textView: TextView,
        range: NSRange
    ) async throws -> [HighlightRange] {
        let string = textView.string
        let lines = string.linesInRange(range)
        
        var highlights: [HighlightRange] = []
        var currentState: RuleStack? = nil
        
        for (lineNumber, lineRange) in lines {
            // Get previous line's end state (for incremental)
            if lineNumber > 0, let cached = lineStates[lineNumber - 1] {
                currentState = cached
            }
            
            let lineText = string.substring(with: lineRange)
            let result = tokenizer.tokenizeLine(
                line: lineText,
                prevState: currentState
            )
            
            // Cache this line's end state
            lineStates[lineNumber] = result.endState
            currentState = result.endState
            
            // Convert tokens to HighlightRanges
            for token in result.tokens {
                let style = resolver.resolve(scopes: token.scopes)
                let absoluteRange = NSRange(
                    location: lineRange.location + token.range.lowerBound,
                    length: token.range.count
                )
                
                highlights.append(HighlightRange(
                    range: absoluteRange,
                    color: style.foreground,
                    bold: style.bold,
                    italic: style.italic
                ))
            }
        }
        
        return highlights
    }
    
    func willApplyEdit(textView: TextView, range: NSRange) {
        // Invalidate line states from edit point onwards
        let editLine = textView.lineNumber(for: range.location)
        lineStates = lineStates.filter { $0.key < editLine }
    }
}
```

---

### 5. Terminal Theme Sync (Milestone 5)

Sync terminal ANSI colors with Shiki theme.

```swift
// Integration/TerminalThemeSync.swift

extension TerminalConfiguration {
    /// Create terminal config from Shiki theme
    init(from shikiTheme: ShikiTheme) {
        // Map editor colors
        self.backgroundColor = NSColor(hex: shikiTheme.colors?.editorBackground ?? "#1e1e1e") ?? .black
        self.foregroundColor = NSColor(hex: shikiTheme.colors?.editorForeground ?? "#d4d4d4") ?? .white
        self.cursorColor = NSColor(hex: shikiTheme.colors?.editorCursor ?? "#aeafad") ?? .gray
        self.selectionColor = NSColor(hex: shikiTheme.colors?.editorSelectionBackground ?? "#264f78") ?? .blue
        
        // Map ANSI palette from theme token colors
        self.ansiPalette = AnsiPalette(from: shikiTheme)
    }
}

extension AnsiPalette {
    /// Extract ANSI colors from Shiki theme token colors
    init(from theme: ShikiTheme) {
        let resolver = ThemeResolver(theme: theme)
        
        // Map semantic scopes to ANSI colors
        self.black = resolver.resolve(scopes: ["comment"]).foreground
        self.red = resolver.resolve(scopes: ["keyword"]).foreground
        self.green = resolver.resolve(scopes: ["string"]).foreground
        self.yellow = resolver.resolve(scopes: ["entity.name.function"]).foreground
        self.blue = resolver.resolve(scopes: ["variable"]).foreground
        self.magenta = resolver.resolve(scopes: ["constant.numeric"]).foreground
        self.cyan = resolver.resolve(scopes: ["entity.name.type"]).foreground
        self.white = resolver.resolve(scopes: ["source"]).foreground
        
        // Bright variants (slightly lighter)
        self.brightBlack = self.black.lighter(by: 0.2)
        self.brightRed = self.red.lighter(by: 0.2)
        // ... etc
    }
}
```

---

## Core Engine Components

### TMGrammar (Data Model)

```swift
// TextMate/TMGrammar.swift

struct TMGrammar: Codable {
    let name: String
    let scopeName: String
    let patterns: [TMPattern]
    let repository: [String: TMPattern]?
    let injections: [String: TMPattern]?
    let fileTypes: [String]?
    let firstLineMatch: String?
    
    static let plainText = TMGrammar(
        name: "Plain Text",
        scopeName: "text.plain",
        patterns: [],
        repository: nil,
        injections: nil,
        fileTypes: nil,
        firstLineMatch: nil
    )
}

struct TMPattern: Codable {
    // Simple match
    let match: String?
    let name: String?
    let captures: [String: TMCapture]?
    
    // Begin/end pair
    let begin: String?
    let end: String?
    let beginCaptures: [String: TMCapture]?
    let endCaptures: [String: TMCapture]?
    let contentName: String?
    
    // Nested patterns
    let patterns: [TMPattern]?
    
    // Repository reference
    let include: String?
}

struct TMCapture: Codable {
    let name: String?
    let patterns: [TMPattern]?
}
```

### TMTokenizer (Core Algorithm)

```swift
// TextMate/TMTokenizer.swift

class TMTokenizer {
    private let grammar: TMGrammar
    
    init(grammar: TMGrammar) {
        self.grammar = grammar
    }
    
    func tokenizeLine(line: String, prevState: RuleStack?) -> TokenizeResult {
        let state = prevState ?? RuleStack.initial(scopeName: grammar.scopeName)
        var tokens: [TMToken] = []
        var position = 0
        var currentState = state
        
        while position < line.count {
            if let result = matchRule(line: line, position: position, state: currentState) {
                tokens.append(contentsOf: result.tokens)
                position = result.newPosition
                currentState = result.newState
            } else {
                position += 1
            }
        }
        
        tokens = fillGaps(tokens: tokens, lineLength: line.count, scopes: currentState.scopes)
        
        return TokenizeResult(tokens: tokens, endState: currentState)
    }
    
    // ... pattern matching implementation ...
}

struct TMToken {
    let range: Range<Int>
    let scopes: [String]  // e.g., ["source.swift", "keyword.control.import"]
}

struct TokenizeResult {
    let tokens: [TMToken]
    let endState: RuleStack
}
```

### ThemeResolver (Scope Matching)

```swift
// Theme/ThemeResolver.swift

class ThemeResolver {
    let theme: ShikiTheme
    private var cache: [String: ResolvedStyle] = [:]
    
    init(theme: ShikiTheme) {
        self.theme = theme
    }
    
    func resolve(scopes: [String]) -> ResolvedStyle {
        let key = scopes.joined(separator: " ")
        if let cached = cache[key] { return cached }
        
        var bestRule: TokenColorRule?
        var bestScore = -1
        
        for rule in theme.tokenColors {
            guard let ruleScopes = rule.scope?.scopes else { continue }
            
            for ruleScope in ruleScopes {
                let score = matchScore(ruleScope: ruleScope, tokenScopes: scopes)
                if score > bestScore {
                    bestScore = score
                    bestRule = rule
                }
            }
        }
        
        let style = ResolvedStyle(
            foreground: parseColor(bestRule?.settings.foreground) ?? defaultForeground,
            background: parseColor(bestRule?.settings.background),
            bold: bestRule?.settings.fontStyle?.contains("bold") ?? false,
            italic: bestRule?.settings.fontStyle?.contains("italic") ?? false,
            underline: bestRule?.settings.fontStyle?.contains("underline") ?? false
        )
        
        cache[key] = style
        return style
    }
    
    /// TextMate scope matching algorithm
    private func matchScore(ruleScope: String, tokenScopes: [String]) -> Int {
        for (index, tokenScope) in tokenScopes.enumerated().reversed() {
            if tokenScope == ruleScope {
                return (index + 1) * 1000  // Exact match
            }
            if tokenScope.hasPrefix(ruleScope + ".") {
                return (index + 1) * 100 + ruleScope.count  // Prefix match
            }
        }
        return -1
    }
}

struct ResolvedStyle {
    let foreground: NSColor
    let background: NSColor?
    let bold: Bool
    let italic: Bool
    let underline: Bool
}
```

---

## Bundled Resources

### Languages (17)

| Language | Grammar File | Priority |
|----------|--------------|----------|
| Swift | `swift.json` | High |
| Python | `python.json` | High |
| JavaScript | `javascript.json` | High |
| TypeScript | `typescript.json` | High |
| TSX | `tsx.json` | High |
| JSX | `jsx.json` | High |
| HTML | `html.json` | High |
| CSS | `css.json` | High |
| JSON | `json.json` | High |
| Markdown | `markdown.json` | High |
| Ruby | `ruby.json` | Medium |
| Rust | `rust.json` | Medium |
| C | `c.json` | Medium |
| C++ | `cpp.json` | Medium |
| Go | `go.json` | Medium |
| PHP | `php.json` | Medium |
| Shell/Bash | `shellscript.json` | Medium |

### Themes (13)

**Dark Themes**:
1. `github-dark` — GitHub's official dark
2. `github-dark-dimmed` — Softer GitHub dark
3. `vitesse-dark` — Anthony Fu's theme
4. `one-dark-pro` — Atom One Dark inspired
5. `tokyo-night` — Popular VS Code theme
6. `dracula` — Classic dark
7. `nord` — Cool arctic tones
8. `monokai` — Classic colorful
9. `catppuccin-mocha` — Warm pastel dark

**Light Themes**:
1. `github-light` — GitHub's official light
2. `vitesse-light` — Light variant
3. `one-light` — Atom One Light inspired
4. `catppuccin-latte` — Warm pastel light

### Resource Acquisition

```bash
# Clone Shiki's grammar/theme repo
git clone https://github.com/shikijs/textmate-grammars-themes.git

# Copy grammars
cd textmate-grammars-themes/packages/tm-grammars/grammars
cp swift.json python.json javascript.json typescript.json \
   html.json css.json json.json markdown.json \
   /path/to/Devys/Packages/DevysSyntax/Sources/DevysSyntax/Resources/Grammars/

# Copy themes
cd ../tm-themes/themes
cp github-dark.json github-light.json vitesse-dark.json \
   one-dark-pro.json tokyo-night.json dracula.json \
   /path/to/Devys/Packages/DevysSyntax/Sources/DevysSyntax/Resources/Themes/
```

---

## Implementation Phases

### Phase 1: Core Engine (shared by all surfaces)

- [ ] Add Oniguruma SPM dependency
- [ ] Create `OnigRegex` Swift wrapper
- [ ] Create `OnigScanner` for multi-pattern matching
- [ ] Implement `TMGrammar` data model
- [ ] Implement `TMRegistry` (grammar loading)
- [ ] Implement `RuleStack` (state management)
- [ ] Implement `TMTokenizer` core algorithm
- [ ] Implement `ShikiTheme` data model
- [ ] Implement `ThemeResolver` (scope matching)
- [ ] Implement `ThemeRegistry` (theme loading, selection)
- [ ] Bundle 17 grammar JSON files
- [ ] Bundle 13 theme JSON files
- [ ] Add unit tests

### Phase 2: File Viewer Integration (M1)

- [ ] Implement `SyntaxHighlighter.highlight()` async helper
- [ ] Implement `LanguageDetector`
- [ ] Update `FileViewerPanel` to use highlighting
- [ ] Test with all 17 languages

### Phase 3: Agent Chat Integration (M2)

- [ ] Implement `HighlightedCodeBlock` SwiftUI view
- [ ] Parse agent response code blocks
- [ ] Test with streaming code blocks

### Phase 4: Diff Integration (M3)

- [ ] Implement `DiffHighlighter`
- [ ] Update `DiffLineView` to use highlighting
- [ ] Pass language from file path to diff view

### Phase 5: Editor Integration (M4)

- [ ] Implement `ShikiHighlightProvider` for CodeEditSourceEditor
- [ ] Add line state caching for incremental tokenization
- [ ] Handle edit invalidation
- [ ] Implement `HighlightCache` for performance
- [ ] Add theme picker UI
- [ ] Test with large files (10k+ lines)

### Phase 6: Terminal Theme Sync (M5)

- [ ] Implement `TerminalConfiguration.init(from: ShikiTheme)`
- [ ] Map ANSI palette from theme token colors
- [ ] Sync terminal when theme changes

---

## Performance Optimizations

### 1. Line State Caching

Cache the `RuleStack` at the end of each line for incremental tokenization:

```swift
private var lineStates: [Int: RuleStack] = [:]

func invalidateFromLine(_ lineNumber: Int) {
    lineStates = lineStates.filter { $0.key < lineNumber }
}
```

### 2. Highlight Cache

```swift
actor HighlightCache {
    private var cache: [CacheKey: CacheEntry] = [:]
    private let maxEntries = 1000
    
    struct CacheKey: Hashable {
        let text: String
        let languageId: String
        let themeName: String
    }
    
    func get(key: CacheKey) -> [TMToken]? { ... }
    func set(key: CacheKey, tokens: [TMToken]) { ... }
}
```

### 3. Background Tokenization

```swift
func tokenizeDocumentAsync(text: String, language: String) async -> [TMToken] {
    await Task.detached(priority: .userInitiated) {
        self.tokenizeDocument(text: text, language: language)
    }.value
}
```

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Visual parity with Shiki | 100% for bundled languages | Side-by-side comparison |
| Tokenization speed | < 50ms for 1000 lines | Instruments |
| Edit responsiveness | < 16ms (60fps) | No visible lag |
| Memory (cached themes) | < 5MB | Activity Monitor |
| Memory (large file 10k lines) | < 100MB | Activity Monitor |

---

## Definition of Done

1. ✅ File Viewer displays syntax-highlighted code (M1)
2. ✅ Agent chat code blocks are highlighted (M2)
3. ✅ Git diffs show syntax-highlighted lines (M3)
4. ✅ Code Editor uses Shiki highlighting (M4)
5. ✅ Terminal ANSI palette syncs with theme (M5)
6. ✅ Visual comparison with Shiki output passes for all 17 languages
7. ✅ 13 themes bundled and selectable
8. ✅ Theme persists across app launches
9. ✅ No visible lag when typing or scrolling
