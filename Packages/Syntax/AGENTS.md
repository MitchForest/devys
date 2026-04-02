# DevysSyntax

A Shiki-compatible syntax highlighting library for Swift, providing TextMate grammar tokenization and theme resolution for the Devys application.

## Purpose and Overview

DevysSyntax is a native Swift implementation of a TextMate-compatible tokenizer that replicates Shiki's exact syntax highlighting behavior. It is designed to provide consistent syntax highlighting across all surfaces in Devys:

1. **File Viewer (M1)** - Read-only file preview with highlighting
2. **Agent Chat (M2)** - Code blocks in Claude/Codex responses
3. **Git Diffs (M3)** - Syntax-highlighted diff lines
4. **Code Editor (M4)** - Full editor integration with incremental tokenization
5. **Terminal (M5)** - Theme sync (ANSI palette from Shiki theme)

The package uses Oniguruma (the same regex engine used by VS Code and TextMate) to ensure full compatibility with TextMate grammar patterns.

## Architecture and Systems Design

### Dual-Layer Architecture

The package follows VS Code's dual-layer approach:
- **TextMate Layer** - Provides visual accuracy and theme ecosystem compatibility
- **TreeSitter Layer** - (Separate package) Provides code intelligence (folding, brackets)

### Core Components

```
DevysSyntax
├── OnigurumaKit          # Swift wrapper for Oniguruma C library
├── COniguruma            # C module with Oniguruma headers
├── libonig.xcframework   # Pre-built Oniguruma binary
└── DevysSyntax           # Main syntax highlighting library
    ├── Models/           # Data structures
    ├── Services/         # Business logic
    └── Resources/        # Bundled grammars and themes
```

### Data Flow

1. **Input**: Source code string + language identifier
2. **Grammar Loading**: `TMRegistry` loads TextMate grammar JSON
3. **Tokenization**: `TMTokenizer` processes text line-by-line
4. **Scope Resolution**: Tokens are assigned TextMate scope stacks
5. **Theme Resolution**: `ThemeResolver` maps scopes to colors
6. **Output**: `AttributedString` or `[StyledToken]`

## Key Protocols and Conventions

### Concurrency

- All types are `Sendable`
- `HighlightProvider` is an `actor` for thread-safe tokenization
- `TMRegistry` and `ThemeRegistry` are actors/main-actor isolated
- `OnigRegex` and `OnigScanner` are `@unchecked Sendable` (thread-safe for read operations)

### Protocol Abstractions

```swift
// Grammar loading service
protocol GrammarService: Sendable {
    func grammar(for languageId: String) async throws -> TMGrammar
    func grammarForScope(_ scopeName: String) async throws -> TMGrammar?
    func clearCache() async
    func grammarsByScope() async throws -> [String: TMGrammar]
}

// Theme management service
@MainActor
protocol ThemeService: AnyObject, Sendable {
    var currentTheme: ShikiTheme? { get }
    var currentResolver: ThemeResolver? { get }
    var currentThemeName: String { get set }
    func loadTheme(name: String)
    func resolver(for themeName: String?) -> ThemeResolver?
    func clearCache()
}

// Regex engine abstraction
protocol RegexEngine: Sendable {
    func createScanner(patterns: [String]) throws -> any PatternScanner
}

protocol PatternScanner: Sendable {
    func findNextMatch(in string: String, from position: Int) -> PatternMatch?
}
```

## File/Folder Organization

```
Sources/
├── COniguruma/
│   └── include/
│       └── oniguruma.h              # Oniguruma C header
│
├── OnigurumaKit/
│   ├── OnigurumaKit.swift           # Core Oniguruma Swift wrapper
│   │   - OnigRegex                  # Compiled regex pattern
│   │   - OnigMatch                  # Match result
│   │   - OnigCapture                # Capture group
│   │   - OnigScanner                # Multi-pattern scanner
│   │   - OnigScannerMatch           # Scanner match result
│   │   - OnigError                  # Error types
│   │
│   └── OnigEngine.swift             # High-level engine wrapper
│       - OnigEngine                 # Factory for scanners
│       - OnigPatternScanner         # UTF-16 compatible scanner
│       - OnigPatternMatch           # Match with UTF-16 positions
│       - OnigPatternCapture         # Capture with UTF-16 positions
│
└── DevysSyntax/
    ├── Models/
    │   ├── TextMate/
    │   │   ├── TMGrammar.swift      # Grammar data structures
    │   │   ├── TMToken.swift        # Token types
    │   │   ├── RuleStack.swift      # Tokenizer state management
    │   │   └── TextMateScope.swift  # Scope utilities
    │   │
    │   └── Theme/
    │       ├── ShikiTheme.swift     # Theme data structures
    │       └── ThemeResolver.swift  # Scope-to-color resolution
    │
    ├── Services/
    │   ├── DevysSyntax.swift        # Package constants and metadata
    │   │
    │   ├── TextMate/
    │   │   ├── TMTokenizer.swift    # Core tokenization engine
    │   │   ├── TMTokenizer+Matching.swift   # Pattern matching logic
    │   │   ├── TMTokenizer+Includes.swift   # Include resolution
    │   │   ├── TMTokenizer+GapFilling.swift # Token gap filling
    │   │   ├── TMTokenizer+While.swift      # While pattern handling
    │   │   └── TMRegistry.swift     # Grammar loading/caching
    │   │
    │   ├── Regex/
    │   │   ├── RegexEngine.swift    # Engine protocol definitions
    │   │   ├── RegexCache.swift     # Compiled regex caching
    │   │   └── OnigurumaEngine.swift # Oniguruma implementation
    │   │
    │   ├── Theme/
    │   │   └── ThemeRegistry.swift  # Theme loading/management
    │   │
    │   ├── Integration/
    │   │   ├── HighlightProvider.swift  # Main public API
    │   │   └── LanguageDetector.swift   # File extension mapping
    │   │
    │   └── Utilities/
    │       ├── StringExtensions.swift   # UTF-16 string helpers
    │       └── BundleExtension.swift    # Resource bundle access
    │
    └── Resources/
        ├── Grammars/                # TextMate grammar JSON files
        │   ├── swift.json
        │   ├── python.json
        │   ├── javascript.json
        │   └── ... (24 languages)
        │
        └── Themes/                  # VS Code theme JSON files
            ├── github-dark.json
            ├── github-light.json
            ├── dracula.json
            └── ... (12 themes)

Tests/
├── DevysSyntaxTests/
│   ├── IntegrationTests.swift       # End-to-end tests
│   ├── TMTokenizerTests.swift       # Tokenizer unit tests
│   ├── ThemeResolverTests.swift     # Theme resolution tests
│   ├── SwiftGrammarTests.swift      # Swift-specific tests
│   ├── HTMLGrammarTests.swift       # HTML-specific tests
│   ├── CSSGrammarTests.swift        # CSS-specific tests
│   ├── EngineTests.swift            # Regex engine tests
│   ├── ShikiParityReportTests.swift # Shiki compatibility tests
│   ├── SyntaxCoverageReportTests.swift # Coverage tests
│   └── Fixtures/                    # Sample code files
│
└── OnigurumaKitTests/
    └── OnigurumaKitTests.swift      # Oniguruma wrapper tests

Scripts/
└── build-oniguruma.sh               # Rebuild Oniguruma static library

xcframeworks/
└── libonig.xcframework/             # Pre-built Oniguruma binary
```

## Important Types for Syntax Highlighting

### TMGrammar

Represents a TextMate grammar loaded from JSON:

```swift
public struct TMGrammar: Codable, Sendable {
    let name: String                              // Display name
    let scopeName: String                         // Root scope (e.g., "source.swift")
    let patterns: [TMPattern]                     // Top-level patterns
    let repository: [String: TMRepositoryPattern]? // Named pattern repository
    let injections: [String: TMPattern]?          // Injection rules
    let fileTypes: [String]?                      // File extensions
    let firstLineMatch: String?                   // First line detection regex
}
```

### TMPattern

A single TextMate pattern rule:

```swift
public struct TMPattern: Codable, Sendable {
    // Simple match
    let match: String?              // Single-line regex
    let name: String?               // Scope name for match
    let captures: [String: TMCapture]?

    // Begin/End pair
    let begin: String?              // Opening regex
    let end: String?                // Closing regex
    let beginCaptures: [String: TMCapture]?
    let endCaptures: [String: TMCapture]?
    let contentName: String?        // Scope for content between

    // While pattern (heredocs, etc.)
    let `while`: String?
    let whileCaptures: [String: TMCapture]?

    // Nested patterns
    let patterns: [TMPattern]?
    let applyEndPatternLast: Int?

    // Repository reference
    let include: String?            // "#name", "$self", "$base"
}
```

### TMToken

Output token from tokenization:

```swift
public struct TMToken: Sendable, Equatable {
    let startIndex: Int             // UTF-16 start offset
    let endIndex: Int               // UTF-16 end offset
    let scopes: [String]            // Scope stack (e.g., ["source.swift", "keyword.control"])
}
```

### RuleStack

Manages nested rule state during tokenization:

```swift
public struct RuleStack: Sendable, Equatable, Hashable {
    var scopes: [String]            // Current accumulated scopes
    var endPattern: String?         // End pattern to watch for
    var whilePattern: String?       // While pattern to validate
    var contentName: String?        // Content scope name
    var nestedPatterns: [TMPattern]? // Patterns to apply within
    var anchorPosition: Int         // Anchor for \G matches

    // Operations
    func push(...) -> RuleStack
    func pop() -> RuleStack
}
```

### ShikiTheme

VS Code/Shiki theme representation:

```swift
public struct ShikiTheme: Codable, Sendable {
    let name: String
    let type: ThemeType?            // dark, light, hc
    let colors: [String: String]?   // Editor colors
    let tokenColors: [TokenColorRule]?  // Token coloring rules

    var editorBackground: String?
    var editorForeground: String?
    var isDark: Bool
}

public struct TokenColorRule: Codable, Sendable {
    let name: String?
    let scope: ScopeSelector?       // String or [String]
    let settings: TokenSettings     // foreground, background, fontStyle
}
```

### ThemeResolver

Resolves TextMate scopes to colors:

```swift
public final class ThemeResolver: Sendable {
    let theme: ShikiTheme
    let defaultForeground: String
    let defaultBackground: String

    func resolve(scopes: [String]) -> ResolvedStyle
}

public struct ResolvedStyle: Sendable, Equatable {
    let foreground: String          // Hex color
    let background: String?         // Hex color (optional)
    let fontStyle: FontStyle        // bold, italic, underline
}
```

### HighlightProvider

Main public API for syntax highlighting:

```swift
public actor HighlightProvider {
    // Get AttributedString directly
    func attributedLine(_ line: String, language: String, fontSize: CGFloat, fontName: String) async -> AttributedString
    func attributedText(_ text: String, language: String, fontSize: CGFloat, fontName: String) async -> AttributedString
}
```

## Dependencies

### Package.swift Structure

```swift
let package = Package(
    name: "DevysSyntax",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevysSyntax", targets: ["DevysSyntax"]),
        .library(name: "OnigurumaKit", targets: ["OnigurumaKit"]),
    ],
    dependencies: [],  // No external dependencies
    targets: [
        .target(name: "COniguruma", dependencies: ["libonig"]),
        .binaryTarget(name: "libonig", path: "xcframeworks/libonig.xcframework"),
        .target(name: "OnigurumaKit", dependencies: ["COniguruma"]),
        .target(name: "DevysSyntax", dependencies: ["OnigurumaKit"], resources: [...]),
    ]
)
```

### Internal Dependencies

- **COniguruma**: C module that provides headers for the Oniguruma library
- **libonig.xcframework**: Pre-built static library of Oniguruma 6.9.9
- **OnigurumaKit**: Swift wrapper around Oniguruma C API
- **DevysSyntax**: Main library that uses OnigurumaKit for regex matching

### Why Oniguruma?

TextMate grammars rely on Oniguruma regex features not available in Swift's native regex or NSRegularExpression:
- Named capturing groups: `(?<name>...)`
- Named backreferences: `\k<name>`
- Variable-length lookbehind
- Unicode property escapes
- Possessive quantifiers
- Ruby-style syntax (TextMate grammars' foundation)

## Public API Surface

### Primary Entry Point

```swift
import DevysSyntax

// Quick start - get highlighted AttributedString
let provider = await HighlightProvider()
let highlighted = await provider.attributedText(
    code,
    language: "swift",
    fontSize: 13,
    fontName: "Menlo"
)

// Use in SwiftUI
Text(highlighted)
```

### Grammar Access

```swift
// Load grammar by language ID
let registry = TMRegistry()
let grammar = try await registry.grammar(for: "swift")

// Create tokenizer
let tokenizer = TMTokenizer(grammar: grammar)
let result = tokenizer.tokenizeLine(line: "let x = 42", prevState: nil)
```

### Theme Access

```swift
// Load and use themes
@MainActor
let themeRegistry = ThemeRegistry()
themeRegistry.currentThemeName = "github-dark"

let resolver = themeRegistry.currentResolver
let style = resolver?.resolve(scopes: ["source.swift", "keyword.control"])
```

### Language Detection

```swift
// Detect language from file path
let lang = LanguageDetector.detect(from: "main.swift")  // "swift"
let lang = LanguageDetector.detect(from: "Dockerfile")  // "dockerfile"
```

### Available Resources

Theme and language resources are bundled with the package and loaded through
`TMRegistry` and `ThemeRegistry` at runtime.

## Language Support

### Bundled Grammars (24 languages)

| Language | Scope Name | File Extensions |
|----------|------------|-----------------|
| Swift | source.swift | .swift |
| Python | source.python | .py |
| JavaScript | source.js | .js, .mjs, .cjs |
| TypeScript | source.ts | .ts, .mts, .cts |
| TSX | source.tsx | .tsx |
| JSX | source.jsx | .jsx |
| HTML | text.html.basic | .html, .htm |
| CSS | source.css | .css |
| JSON | source.json | .json, .jsonc |
| YAML | source.yaml | .yaml, .yml |
| Markdown | text.html.markdown | .md, .markdown |
| Ruby | source.ruby | .rb |
| Rust | source.rust | .rs |
| C | source.c | .c, .h |
| C++ | source.cpp | .cpp, .cc, .cxx, .hpp |
| Go | source.go | .go |
| PHP | source.php | .php |
| Java | source.java | .java |
| C# | source.cs | .cs |
| Lua | source.lua | .lua |
| Kotlin | source.kotlin | .kt, .kts |
| Make | source.makefile | Makefile, .mk |
| Shell | source.shell | .sh, .bash, .zsh |
| Plain Text | text.plain | (fallback) |

### Bundled Themes (12 themes)

**Dark Themes:**
- github-dark
- github-dark-dimmed
- vitesse-dark
- one-dark-pro
- tokyo-night
- dracula
- nord
- monokai
- catppuccin-mocha

**Light Themes:**
- github-light
- vitesse-light
- catppuccin-latte

## Token Types and Scopes

### Common TextMate Scope Categories

| Category | Example Scopes |
|----------|----------------|
| Keywords | `keyword.control`, `keyword.operator`, `keyword.other` |
| Storage | `storage.type`, `storage.modifier` |
| Constants | `constant.numeric`, `constant.language`, `constant.character` |
| Strings | `string.quoted.double`, `string.quoted.single`, `string.template` |
| Comments | `comment.line`, `comment.block`, `comment.documentation` |
| Variables | `variable.parameter`, `variable.other`, `variable.language` |
| Functions | `entity.name.function`, `support.function` |
| Types | `entity.name.type`, `entity.name.class`, `support.type` |
| Punctuation | `punctuation.definition`, `punctuation.separator` |
| Meta | `meta.function`, `meta.class`, `meta.embedded` |

### Scope Resolution Algorithm

The theme resolver uses TextMate's scope matching algorithm:
1. Scopes are matched from most specific (deepest) to least specific
2. Exact matches score higher than prefix matches
3. Deeper matches score higher than shallow matches
4. Comma-separated selectors are OR'd together
5. Space-separated selectors require ancestor matching

## Highlighting Patterns

### Begin/End Patterns

Used for multi-line constructs like strings and comments:

```json
{
  "begin": "\"",
  "end": "\"",
  "name": "string.quoted.double",
  "patterns": [
    { "match": "\\\\.", "name": "constant.character.escape" }
  ]
}
```

### Match Patterns

Used for single-line constructs:

```json
{
  "match": "\\b(let|var|func)\\b",
  "name": "keyword.declaration"
}
```

### Include Patterns

Reference other patterns in the repository:

```json
{
  "include": "#comments"     // Local repository reference
  "include": "$self"         // Include all patterns from this grammar
  "include": "source.swift"  // Include external grammar
}
```

### Capture Groups

Assign scopes to regex capture groups:

```json
{
  "match": "(func)\\s+(\\w+)",
  "captures": {
    "1": { "name": "keyword.declaration.function" },
    "2": { "name": "entity.name.function" }
  }
}
```

## Environment Variables for Debugging

| Variable | Description |
|----------|-------------|
| `DEVYS_DEBUG_RAW=1` | Dump raw tokens per line |
| `DEVYS_TOKENIZER_GUARD=1` | Log when tokenizer guard trips |
| `DEVYS_SHIKI_LANG=swift,ts` | Filter parity tests to specific languages |
| `DEVYS_SHIKI_DEBUG_LANG=jsx` | Debug specific language in parity tests |
| `DEVYS_SHIKI_DEBUG_LINES=11,12` | Debug specific line numbers |

## Testing

### Running Tests

```bash
# All tests
swift test --package-path Packages/DevysSyntax

# Specific test suite
swift test --package-path Packages/DevysSyntax --filter IntegrationTests

# Shiki parity tests
swift test --package-path Packages/DevysSyntax \
  --filter DevysSyntaxTests.ShikiParityReportTests/testShikiParityReport
```

### Test Categories

1. **Unit Tests**: Test individual components in isolation
2. **Integration Tests**: End-to-end tokenization and theme resolution
3. **Grammar Tests**: Language-specific tokenization validation
4. **Parity Tests**: Compare output against Shiki reference implementation

## Adding a New Language

1. Add TextMate grammar JSON to `Sources/DevysSyntax/Resources/Grammars/`
2. Add sample fixture to `Tests/DevysSyntaxTests/Fixtures/`
3. Update `TMRegistry.availableLanguages`
4. Update `LanguageDetector.extensionMap`
5. Regenerate Shiki fixtures: `node scripts/generate-shiki-fixtures.mjs`
6. Run parity tests to verify

## Adding a New Theme

1. Add VS Code theme JSON to `Sources/DevysSyntax/Resources/Themes/`
2. Update `ThemeRegistry.availableThemes`
3. Regenerate Shiki fixtures with new theme
4. Run parity tests to verify color resolution

## Rebuilding Oniguruma

If you need to update the Oniguruma library:

```bash
./Packages/DevysSyntax/Scripts/build-oniguruma.sh
```

This builds a universal static library for macOS (arm64 + x86_64) and copies headers to `Sources/COniguruma/include`.

## Performance Considerations

- **Regex Caching**: `RegexCache` caches compiled scanners (LRU, max 1024 entries)
- **Theme Caching**: `ThemeResolver` caches resolved styles (LRU, max 1000 entries)
- **Grammar Caching**: `TMRegistry` caches loaded grammars by language ID
- **Incremental Tokenization**: `RuleStack` enables line-by-line incremental updates
- **UTF-16 Indexing**: All positions use UTF-16 offsets for Swift String compatibility
