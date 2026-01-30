# Milestone 5: Terminal Port from devys-old

> **Goal**: Port DevysTerminal from `devys-old` with careful refactoring and heavy testing.

---

## Source Analysis

### Location
```
devys-old/Packages/DevysTerminal/
```

### Quality Assessment

| Component | Lines | Status | Quality |
|-----------|-------|--------|---------|
| VTParser.swift | 825 | ✅ Complete | Production-quality, full state machine |
| PtySession.swift | 567 | ✅ Complete | Darwin APIs, shell hooks, thread-safe |
| ScreenBuffer.swift | ~500 | ✅ Complete | Grid, cursor, scrollback, alt screen |
| TerminalShaders.metal | 287 | ✅ Complete | GPU rendering, instanced, all flags |
| Tests | 10 files | ✅ Present | Parser, screen, PTY, renderer |

### Known Issues (from README backlog)
- [ ] Dynamic color palette switching
- [ ] Theme synchronization
- [ ] Shell integration hooks (OSC 133) - partial
- [ ] Performance profiling needed
- [ ] Line-based selection mode

---

## What to Strip

### 1. DevysPaneKit Protocol

**File**: `DevysTerminal/DevysTerminalPackage.swift`

The old Devys used a package protocol for pane integration. We now use Bonsplit.

```swift
// REMOVE THIS
public struct DevysTerminalPackage: DevysPackage {
    public static var metadata: PackageMetadata { ... }
    public static func makeContentView(...) -> some View { ... }
}
```

**Replace with**: Simple SwiftUI view that Bonsplit can host as tab content.

### 2. Package.swift Dependencies

**Current**:
```swift
dependencies: [
    .package(path: "../DevysPaneKit"),  // ❌ Remove
    .package(url: "swift-log", from: "1.0.0")
]
```

**Updated**:
```swift
dependencies: [
    .package(url: "swift-log", from: "1.0.0")  // Keep for logging
]
```

### 3. Canvas/Pane Mental Model

The old Devys had concepts like:
- `TerminalPaneView` — pane-specific wrapper
- `TabbedTerminalWindow` — native tabs (we use Bonsplit instead)
- `TerminalSessionStore` — may need rethinking

**Action**: Review `SwiftUI/` folder and simplify to just:
- `TerminalView` — main SwiftUI entry point
- `TerminalSession` — @Observable session state
- `TerminalConfiguration` — config options

---

## What to Keep (Core Engine)

### 1. VTParser (keep as-is)

The parser is solid. 13-state machine handling:
- CSI sequences (cursor, erase, scroll, SGR)
- OSC sequences (title, colors, hyperlinks, clipboard, cwd)
- DCS sequences
- UTF-8 handling
- C1 controls

### 2. PtySession (keep as-is)

Excellent PTY implementation:
- `forkpty()` with proper child setup
- Non-blocking I/O with `O_NONBLOCK`
- Shell hooks for zsh/bash (OSC 7 directory tracking)
- Thread-safe with `NSLock`
- Proper shutdown with SIGTERM → SIGKILL

### 3. ScreenBuffer (keep as-is)

Complete terminal state:
- Grid of cells with attributes
- Cursor position, style, visibility
- Scrollback buffer
- Alt screen support
- Scroll regions
- Mouse reporting mode

### 4. Metal Rendering (keep as-is)

GPU pipeline:
- `CellBuffer` — packs grid into GPU buffer
- `GlyphAtlas` — on-demand glyph rasterization
- `RenderPipeline` — Metal compute setup
- `TerminalShaders.metal` — vertex/fragment shaders

### 5. Input Handling (keep as-is)

- `KeyboardInput` — key events → escape codes
- `MouseInput` — mouse events → SGR codes
- `ClipboardSupport` — copy/paste

---

## Refactoring Tasks

### Phase 1: Package Cleanup

- [ ] Remove `DevysPaneKit` dependency from Package.swift
- [ ] Delete `DevysTerminalPackage.swift`
- [ ] Delete `TabbedTerminalWindow.swift` (we use Bonsplit)
- [ ] Review/simplify `TerminalSessionStore.swift`

### Phase 2: SwiftUI Integration

- [ ] Create `TerminalPanelView` for Bonsplit tab content
- [ ] Ensure `TerminalView` works standalone
- [ ] Add configuration for Devys design system colors

### Phase 3: Testing

- [ ] Run all existing unit tests
- [ ] Fix any test failures
- [ ] Manual testing matrix (see below)
- [ ] Performance benchmarks

### Phase 4: Bug Fixes

- [ ] Document any bugs found during testing
- [ ] Prioritize and fix critical bugs
- [ ] Defer non-critical bugs to backlog

---

## Testing Matrix

### Unit Tests (existing)

| Test File | Coverage |
|-----------|----------|
| VTParserTests.swift | Escape sequences, state machine |
| ScreenBufferTests.swift | Grid operations, cursor, scroll |
| CellTests.swift | Cell attributes, colors |
| CursorTests.swift | Cursor movement, visibility |
| GridTests.swift | Grid resize, content |
| InputTests.swift | Key/mouse event encoding |
| PtyTests.swift | PTY lifecycle, I/O |
| RendererTests.swift | Metrics, glyph cache |
| MetalTests.swift | Buffer packing, shader uniforms |
| TypesTests.swift | Color, attribute types |

### Manual Testing

| Application | Test Cases |
|-------------|------------|
| **Basic shell** | Commands, output, scrollback |
| **vim/neovim** | Alt screen, cursor keys, colors, mouse |
| **htop** | Colors, refresh, resize |
| **tmux** | Splits, mouse, alt screen |
| **less/more** | Paging, search, alt screen |
| **git log** | Pager, colors |
| **claude CLI** | True color, streaming output |
| **npm/yarn** | Progress bars, spinners |
| **ssh** | Remote shell, latency |

### Performance Benchmarks

| Metric | Target | Measurement |
|--------|--------|-------------|
| Scrolling FPS | ≥ 120fps | Instruments |
| Large output (1MB) | < 500ms | Manual timing |
| Resize latency | < 16ms | No visible lag |
| Glyph cache hit rate | > 95% | Logging |
| Memory (idle session) | < 20MB | Activity Monitor |
| Memory (10k scrollback) | < 50MB | Activity Monitor |

---

## Integration with Bonsplit

### Tab Content Pattern

```swift
// In WorkspaceCanvasView
BonsplitView(controller: controller) { tab in
    switch tab.contentType {
    case .terminal(let sessionId):
        TerminalPanelView(sessionId: sessionId)
    case .file(let url):
        FileViewerPanel(url: url)
    // ...
    }
}
```

### Terminal Panel View

```swift
// DevysTerminal/SwiftUI/TerminalPanelView.swift
struct TerminalPanelView: View {
    let sessionId: UUID
    @StateObject private var session = TerminalSession()
    
    var body: some View {
        TerminalView(session: session)
            .task {
                await session.start(shell: "/bin/zsh")
            }
    }
}
```

---

## Color Scheme Integration

### Current (devys-old)

Uses its own `AnsiColors.swift` palette.

### Target (new Devys)

Sync with `DevysColors`:

```swift
extension TerminalConfiguration {
    static var devysDefault: TerminalConfiguration {
        TerminalConfiguration(
            backgroundColor: DevysColors.base,
            foregroundColor: DevysColors.textPrimary,
            cursorColor: DevysColors.primary,
            selectionColor: DevysColors.primary.opacity(0.3),
            // ANSI palette mapped to Devys design system
            palette: AnsiPalette.devys
        )
    }
}
```

---

## Timeline Estimate

| Phase | Effort | Notes |
|-------|--------|-------|
| Package cleanup | 2-3 hours | Remove deps, delete files |
| SwiftUI integration | 4-6 hours | New panel view, config |
| Run tests + fix | 4-8 hours | Depends on failures |
| Manual testing | 4-6 hours | Full matrix |
| Bug fixes | Variable | Depends on findings |
| **Total** | **2-3 days** | Before M5 starts |

---

## Success Criteria

Before declaring terminal ready for M5:

1. ✅ All unit tests pass
2. ✅ Manual testing matrix complete with no critical bugs
3. ✅ 120fps scrolling confirmed
4. ✅ vim, tmux, htop work correctly
5. ✅ True color output works (claude CLI)
6. ✅ Resize works without glitches
7. ✅ Copy/paste works
8. ✅ OSC 7 directory tracking works

---

## Appendix: Files to Review

```
DevysTerminal/
├── DevysTerminal.swift           # Keep - entry point
├── DevysTerminalPackage.swift    # DELETE - old pane protocol
├── Input/
│   ├── ClipboardSupport.swift    # Keep
│   ├── InputModifiers.swift      # Keep
│   ├── KeyboardInput.swift       # Keep
│   ├── MouseInput.swift          # Keep
│   └── TerminalInput.swift       # Keep
├── Metal/
│   ├── CellBuffer.swift          # Keep
│   ├── GlyphAtlas.swift          # Keep
│   ├── MetalTerminalView.swift   # Keep
│   ├── RenderPipeline.swift      # Keep
│   ├── ShaderTypes.swift         # Keep
│   └── TerminalShaders.metal     # Keep
├── PTY/
│   ├── PtySession.swift          # Keep
│   └── PtySize.swift             # Keep
├── Renderer/
│   ├── AnsiColors.swift          # Keep - may update palette
│   ├── BoxDrawing.swift          # Keep
│   ├── GlyphCache.swift          # Keep
│   ├── TerminalMetrics.swift     # Keep
│   └── TerminalRenderer.swift    # Keep
├── Screen/
│   ├── Cell.swift                # Keep
│   ├── Cursor.swift              # Keep
│   ├── Grid.swift                # Keep
│   ├── ScreenBuffer.swift        # Keep
│   ├── Selection.swift           # Keep
│   ├── Types.swift               # Keep
│   └── VTParser.swift            # Keep
└── SwiftUI/
    ├── TabbedTerminalWindow.swift    # DELETE - use Bonsplit
    ├── TerminalConfiguration.swift   # Keep - update for Devys colors
    ├── TerminalNSView.swift          # Keep
    ├── TerminalSession.swift         # Keep
    ├── TerminalSessionStore.swift    # REVIEW - may simplify
    └── TerminalView.swift            # Keep
```
