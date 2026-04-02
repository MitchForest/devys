# DevysEditor

A GPU-accelerated code editor package built with Metal rendering for macOS. Part of the Devys application ecosystem.

## Overview

DevysEditor provides a high-performance code editor that renders text using Metal for smooth 120fps scrolling and efficient GPU utilization. The package virtualizes line rendering (only visible content is rendered), integrates with DevysSyntax for Shiki-compatible syntax highlighting, and supports full editing capabilities including undo/redo.

### Key Features
- Metal-based GPU text rendering
- Line virtualization for large files
- Syntax highlighting via TextMate grammars (Shiki-compatible)
- Full editing support (insert, delete, selection, copy/paste)
- Cursor and selection rendering with blinking animation
- Smooth scroll wheel support
- SwiftUI integration via `NSViewRepresentable`
- Dark/light theme support with DevysColors design system

## Architecture

```
DevysEditor/
├── Models/
│   ├── Document/
│   │   └── EditorDocument.swift      # Text storage, cursor, editing operations
│   └── Layout/
│       └── LineBuffer.swift          # Viewport management, visible line range
├── Services/
│   ├── DevysEditor.swift             # Package metadata and version
│   ├── DocumentIOService.swift       # File load/save abstraction
│   └── Highlighting/
│       ├── HighlightEngine.swift     # Async tokenization engine
│       └── HighlightingService.swift # Grammar/theme loading service
├── Views/
│   ├── Metal/
│   │   ├── MetalEditorView.swift           # MTKView-based editor
│   │   └── MetalEditorView+Buffers.swift   # Cell/overlay buffer building
│   └── SwiftUI/
│       ├── EditorConfiguration.swift # Configuration options
│       └── EditorView.swift          # SwiftUI wrapper
└── Resources/
    └── (empty - shaders come from DevysTextRenderer)
```

## Dependencies

### Package.swift Dependencies

```swift
dependencies: [
    .package(path: "../DevysSyntax"),
    .package(path: "../DevysTextRenderer"),
]
```

### DevysSyntax
Provides Shiki-compatible syntax highlighting:
- `TMTokenizer` - TextMate grammar tokenization
- `ThemeResolver` - Theme color resolution for scopes
- `TMRegistry` / `GrammarService` - Grammar loading
- `ThemeRegistry` / `ThemeService` - Theme loading
- `ShikiTheme` - Theme model
- `RuleStack` - Tokenizer state for line continuation
- `FontStyle` - Bold/italic/underline flags
- `LanguageDetector` - File extension to language mapping

### DevysTextRenderer
Provides Metal rendering infrastructure:
- `EditorRenderPipeline` - Metal pipeline states
- `EditorGlyphAtlas` - Pre-rendered glyph texture atlas
- `EditorCellBuffer` - Triple-buffered GPU cell data
- `EditorOverlayBuffer` - Cursor/selection vertex buffer
- `EditorMetrics` - Cell/line dimension calculations
- `EditorUniforms` - Per-frame GPU uniforms
- `EditorCellGPU` - Per-character GPU data structure
- `EditorCellFlags` - Bold/italic/underline bit flags
- `ScrollWheelNormalizer` - macOS scroll wheel handling
- `hexToLinearColor()` - Hex color to linear sRGB conversion

## Key Types

### EditorDocument

The source of truth for document content. MainActor-isolated, Observable class.

```swift
@MainActor
@Observable
public final class EditorDocument {
    // Text storage
    private var lines: [String]
    public var lineCount: Int
    public var characterCount: Int

    // Cursor state
    public var cursor: EditorCursor
    public var selection: TextRange?

    // Metadata
    public var fileURL: URL?
    public var language: String
    public var isDirty: Bool
}
```

**Key Methods:**
- `line(at:)` / `lines(in:)` / `allLines` - Line access
- `insert(_:)` / `insert(_:at:)` - Text insertion
- `deleteBackward()` / `deleteForward()` - Character deletion
- `delete(_:)` - Range deletion
- `replace(_:with:)` - Range replacement
- `text(in:)` - Extract text from range
- `moveCursorLeft/Right/Up/Down()` - Cursor movement
- `moveCursorToLineStart/End()` - Line navigation
- `load(from:)` - Async file loading

### TextPosition / TextRange / EditorCursor

Position and range types for document navigation:

```swift
public struct TextPosition: Equatable, Hashable, Sendable {
    public var line: Int
    public var column: Int
}

public struct TextRange: Equatable, Sendable {
    public var start: TextPosition
    public var end: TextPosition
    public var normalized: TextRange  // Ensures start < end
}

public struct EditorCursor: Equatable, Sendable {
    public var position: TextPosition
    public var preferredColumn: Int?  // For vertical movement
}
```

### LineBuffer

Manages visible line range and viewport calculations:

```swift
@MainActor
public final class LineBuffer {
    public var scrollOffset: CGFloat
    public var viewportHeight: CGFloat
    public var viewportWidth: CGFloat
    public var bufferLines: Int = 50  // Pre-render buffer

    public var visibleRange: Range<Int>
    public var tokenizationRange: Range<Int>  // visible + buffer

    public func scrollToLine(_:position:)
    public func scroll(by:)
}
```

### HighlightEngine

Actor that manages async syntax highlighting:

```swift
public actor HighlightEngine {
    // Caches
    private var lineStates: [Int: RuleStack]
    private var highlightedLines: [Int: HighlightedLine]
    private var dirtyLines: Set<Int>

    public func highlightLines(_:startingAt:) -> [HighlightedLine]
    public func invalidate(from:)
    public func clearCache()
}
```

### HighlightedToken / HighlightedLine

Styled token data for rendering:

```swift
public struct HighlightedToken: Sendable {
    public let range: Range<Int>        // UTF-16 character range
    public let foregroundColor: String  // Hex color
    public let backgroundColor: String?
    public let fontStyle: FontStyle
}

public struct HighlightedLine: Sendable {
    public let lineIndex: Int
    public let text: String
    public let tokens: [HighlightedToken]
    public let endState: RuleStack
}
```

### EditorConfiguration

Configuration options for editor appearance:

```swift
public struct EditorConfiguration: Sendable {
    public var fontName: String          // Default: "Menlo"
    public var fontSize: CGFloat         // Default: 13
    public var colorScheme: EditorColorScheme  // .light, .dark, .system
    public var showLineNumbers: Bool     // Default: true
    public var tabWidth: Int             // Default: 4
    public var insertSpacesForTab: Bool  // Default: true
    public var showWhitespace: Bool      // Default: false
    public var wordWrap: Bool            // Default: false
    public var useDevysColors: Bool      // Default: true
}
```

### MetalEditorView

The core MTKView-based editor implementation:

```swift
@MainActor
public final class MetalEditorView: NSView, MTKViewDelegate {
    // Metal components
    var mtkView: MTKView!
    var pipeline: EditorRenderPipeline!
    var glyphAtlas: EditorGlyphAtlas!
    var cellBuffer: EditorCellBuffer!
    var overlayBuffer: EditorOverlayBuffer!

    // Document state
    public var document: EditorDocument?
    var lineBuffer: LineBuffer?
    var highlightEngine: HighlightEngine?

    // Configuration
    public var configuration: EditorConfiguration
}
```

### EditorView (SwiftUI)

SwiftUI wrapper for MetalEditorView:

```swift
public struct EditorView: NSViewRepresentable {
    // Initializers
    public init(url: URL)
    public init(content: String, language: String)
    public init(document: EditorDocument, onDocumentURLChange: ((URL) -> Void)?)
}
```

## Rendering Pipeline

### Frame Rendering Flow

1. **Update Animation Time** - Track time for cursor blink
2. **Update Visible Range** - Recalculate which lines are visible
3. **Check Highlighting** - Queue async highlight if needed
4. **Build Cell Buffer** - Generate per-character GPU data
5. **Build Overlay Buffer** - Generate cursor/selection geometry
6. **Sync to GPU** - Copy data to Metal buffers
7. **Draw Cells** - Instanced rendering of text cells
8. **Draw Overlays** - Render cursor and selection

### Cell Buffer Building

Each visible character becomes an `EditorCellGPU` instance:

```swift
EditorCellGPU(
    position: SIMD2<Float>      // Pixel position
    foregroundColor: SIMD4<Float>  // Linear sRGB
    backgroundColor: SIMD4<Float>
    uvOrigin: SIMD2<Float>      // Glyph atlas UV
    uvSize: SIMD2<Float>
    flags: UInt32               // Bold/italic/underline/cursor
)
```

Line numbers are rendered with `EditorCellFlags.lineNumber` flag and dimmed color.

### Highlighting Strategy

The editor uses incremental highlighting with batched background processing:

1. **First Paint** - Highlight visible lines immediately
2. **Background Fill** - Async task tokenizes buffer lines in 64-line batches
3. **Scroll Update** - On scroll, missing visible lines trigger immediate highlight
4. **Edit Invalidation** - Edited lines and all subsequent lines are invalidated

## Input Handling

### Mouse Events
- `mouseDown` - Click to position cursor, shift-click extends selection
- `mouseDragged` - Drag selection
- `mouseUp` - Finalize selection

### Keyboard Events
- Arrow keys - Cursor movement (with shift for selection)
- Home/End - Line start/end
- Backspace/Delete - Character deletion
- Return/Enter - Newline insertion
- Tab - Insert tab or spaces
- Cmd+C/V/X/A - Copy/paste/cut/select all
- Cmd+S - Save document

### Scroll Events
Uses `ScrollWheelNormalizer` to handle both trackpad and mouse wheel:
- Precise scrolling deltas for trackpads
- Line-based scrolling for mouse wheels

## File Operations

### Loading Documents

```swift
// Via URL
EditorView(url: fileURL)

// Via content string
EditorView(content: "let x = 1", language: "swift")

// Via pre-loaded document
let doc = try await EditorDocument.load(from: url)
EditorView(document: doc)
```

### Saving Documents

MetalEditorView exposes save actions:
- `saveDocument(_:)` - Save to existing URL or prompt for new
- `saveDocumentAs(_:)` - Always prompt for location

Uses `DocumentIOService` protocol for testable I/O:

```swift
public protocol DocumentIOService {
    func load(url: URL) async throws -> (content: String, language: String)
    func save(content: String, to url: URL) async throws
}
```

## Theme System

### Color Sources

1. **DevysColors** (default) - Built-in design system colors
   - Dark: True black background (#000000)
   - Light: White background (#FFFFFF)

2. **Shiki Themes** - Loaded via DevysSyntax
   - Theme colors from JSON theme files
   - Editor background/foreground
   - Cursor and selection colors

### Color Conversion

All colors are converted to linear sRGB for correct Metal rendering:

```swift
// Hex to linear sRGB
let color = hexToLinearColor("#FF5733", alpha: 1.0)
```

## Environment Configuration

```swift
// Set configuration via SwiftUI environment
EditorView(url: fileURL)
    .environment(\.editorConfiguration, EditorConfiguration(
        fontSize: 14,
        colorScheme: .dark,
        tabWidth: 2
    ))
```

## Platform Requirements

- macOS 14+ (Sonoma)
- Swift 6.0+
- Metal-capable GPU

## Swift 6 Concurrency

The package uses strict concurrency:
- `@MainActor` isolation for UI components
- `actor` isolation for `HighlightEngine`
- `Sendable` conformance for data types
- `Task` for async operations

## File Organization Conventions

- **Models/** - Data structures and document model
- **Services/** - Business logic and external integrations
- **Views/** - UI components (Metal and SwiftUI)
- **Resources/** - Bundle resources (currently empty, shaders in DevysTextRenderer)

## Public API Surface

### Types
- `EditorDocument` - Document model
- `TextPosition`, `TextRange`, `EditorCursor` - Position types
- `EditorConfiguration`, `EditorColorScheme` - Configuration
- `EditorView` - SwiftUI view
- `MetalEditorView` - AppKit view (advanced use)
- `LineBuffer`, `ScrollPosition` - Layout utilities
- `HighlightEngine`, `HighlightedLine`, `HighlightedToken` - Highlighting
- `HighlightingService`, `DefaultHighlightingService` - Services
- `DocumentIOService`, `DefaultDocumentIOService` - I/O abstraction

### Environment Keys
- `\.editorConfiguration` - Editor configuration

## Example Usage

```swift
import SwiftUI
import DevysEditor

struct ContentView: View {
    var body: some View {
        EditorView(url: URL(fileURLWithPath: "/path/to/file.swift"))
            .environment(\.editorConfiguration, .dark)
    }
}
```

## Version

Current version: 1.0.0
