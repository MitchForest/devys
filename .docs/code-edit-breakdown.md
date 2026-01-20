# CodeEdit Architecture Breakdown

[CodeEdit](https://github.com/CodeEditApp/CodeEdit) is a native macOS code editor built with **Swift** and **SwiftUI** (22.6k ⭐, MIT license). It's designed as an open-source, lightweight alternative to Xcode and VS Code — prioritizing native macOS feel and performance.

---

## Overview

| Aspect | Details |
|--------|---------|
| **Language** | Swift |
| **UI Framework** | SwiftUI + AppKit bridges |
| **License** | MIT |
| **Stars** | 22.6k |
| **Architecture** | Highly modular (Swift Package Manager) |

### Key Repositories

| Module | Purpose |
|--------|---------|
| [CodeEdit](https://github.com/CodeEditApp/CodeEdit) | Main app |
| [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView) | Custom high-performance text engine |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | Full editor with syntax highlighting |
| [CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages) | Tree-sitter integration for parsing |
| [CodeEditKit](https://github.com/CodeEditApp/CodeEditKit) | Extension/plugin SDK |

---

## 1. File Tree (Project Navigator)

### Data Model

```swift
// FileItem is a recursive model representing the file system
class FileItem: Identifiable, Hashable {
    var id: UUID
    var url: URL
    var children: [FileItem]?   // nil = file, [] or [items] = folder
    var parent: FileItem?
    var gitStatus: GitStatus?   // tracked for gutter indicators
    // ...
}
```

### Why NSOutlineView (not SwiftUI List)?

CodeEdit uses **AppKit's `NSOutlineView`** wrapped via `NSViewRepresentable` instead of SwiftUI's native `OutlineGroup` or `List`:

| SwiftUI List | NSOutlineView |
|--------------|---------------|
| Struggles with 10k+ files | Handles massive trees natively |
| Limited drag-and-drop | Full native DnD support |
| Basic context menus | Rich right-click menus |
| Simple selection | Multi-selection, keyboard nav |

### File System Monitoring

Uses macOS's **FSEvents** API (kernel-level) for real-time file system updates:

```swift
import CoreServices

let stream = FSEventStreamCreate(
    kCFAllocatorDefault,
    callback,
    &context,
    pathsToWatch as CFArray,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
    1.0,  // latency in seconds
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
)
```

When a file is added/deleted externally (e.g., via Terminal), the `WorkspaceClient` receives the event and updates the `FileItem` tree.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     WorkspaceDocument                        │
│                  (Source of truth for window)                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │  WorkspaceClient │───▶│  FileItem (recursive tree)   │   │
│  │  (FSEvents watcher)   │  ├─ url: URL                  │   │
│  └──────────────────┘    │  ├─ children: [FileItem]?     │   │
│                          │  └─ gitStatus: GitStatus?     │   │
│                          └──────────────────────────────────┘   │
│                                         │                    │
│                                         ▼                    │
│                          ┌──────────────────────────────┐   │
│                          │  ProjectNavigatorView        │   │
│                          │  (NSOutlineView wrapper)     │   │
│                          └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. File Explorer (Quick Open & Search)

### Quick Open (⌘⇧O)

CodeEdit maintains a **flattened file index** for fuzzy search:

```swift
// Background indexing on workspace open
Task {
    let files = FileManager.default.enumerator(at: rootURL, ...)
    for case let url as URL in files {
        index.append(url.lastPathComponent)  // fast in-memory lookup
    }
}
```

The search uses fuzzy matching against this index, returning results asynchronously to avoid blocking the UI.

### Breadcrumbs

The editor header shows path components as clickable buttons:

```swift
// Parse path hierarchy from current FileItem
let components = fileItem.url.pathComponents
    .dropFirst()  // remove "/"
    .map { BreadcrumbItem(name: $0) }
```

---

## 3. Code Editor (CodeEditTextView)

### Custom Text Engine

CodeEdit does **not** use `NSTextView` directly. Instead, it uses a custom-built text engine called **CodeEditTextView** for performance and control.

| Feature | Implementation |
|---------|----------------|
| **Text Layout** | Custom layout manager using Core Text |
| **Line Numbers** | Gutter rendered separately, synced with scroll |
| **Syntax Highlighting** | Tree-sitter via CodeEditLanguages |
| **Layers/Adornments** | Custom drawing behind/in-front of text |
| **Selection** | Native-feeling multi-cursor support |

### Why Custom?

- `NSTextView` is optimized for rich text editing (word processors), not code
- Need precise control over gutter, line highlighting, diff markers
- Performance with large files (100k+ lines)
- Layer-based rendering for decorations

### CodeEditSourceEditor

The full editor component that combines:
- CodeEditTextView (text rendering)
- CodeEditLanguages (syntax highlighting via tree-sitter)
- Gutter (line numbers, diff markers, breakpoints)
- Minimap (optional)

---

## 4. Terminal

CodeEdit uses **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** — an open-source Swift terminal emulator by Miguel de Icaza.

### SwiftTerm

| Aspect | Details |
|--------|---------|
| **Author** | Miguel de Icaza (creator of Mono, Xamarin, GNOME) |
| **Language** | Swift |
| **Stars** | ~1.5k |
| **License** | MIT |
| **Platforms** | macOS (AppKit), iOS (UIKit), SwiftUI wrapper |

SwiftTerm handles:
- **VT100/ANSI escape sequences** — colors, cursor movement, scrolling
- **PTY communication** — spawning shells, sending/receiving I/O
- **Text rendering** — using Core Text for high-performance glyph layout
- **Mouse support** — terminal mouse reporting modes
- **Selection & copy** — native text selection

### Integration

```
┌─────────────────────────────────────────────────────────┐
│                    CodeEdit Workspace                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Editor Area (CodeEditSourceEditor)              │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Terminal Drawer (toggleable)                    │    │
│  │  ┌─────────────────────────────────────────────┐│    │
│  │  │  SwiftTerm (NSViewRepresentable)            ││    │
│  │  │  ├─ PTY → $SHELL (zsh/bash/fish)           ││    │
│  │  │  ├─ VT parser → ANSI rendering             ││    │
│  │  │  └─ Theme colors synced with editor        ││    │
│  │  └─────────────────────────────────────────────┘│    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Key Points

1. **`NSViewRepresentable` wrapper** — SwiftTerm is AppKit-based, wrapped for SwiftUI
2. **Uses `Foundation.Process`** — spawns shell via PTY
3. **Inherits `$SHELL`** — respects user's default shell
4. **Theme sync** — maps editor theme colors to ANSI palette

---

## 5. Git Integration

### Architecture

CodeEdit wraps the `git` CLI (or uses SwiftGit2) for Git operations:

```swift
// Shell execution example
func gitStatus() async throws -> [FileStatus] {
    let output = try await shell("git status --porcelain")
    return parseStatusOutput(output)
}

func gitDiff(file: URL) async throws -> String {
    return try await shell("git diff HEAD -- \(file.path)")
}
```

### Git Status Tracking

Each `FileItem` has a `gitStatus` property:

```swift
enum GitStatus {
    case untracked
    case modified
    case staged
    case conflict
    case unchanged
}
```

This status is displayed:
- In the file tree (colored file names, icons)
- In the gutter (diff markers)
- In the Source Control sidebar

---

## 6. Diff Rendering

### Diff Parsing

The unified diff format is parsed into **hunks**:

```swift
struct DiffHunk {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

enum DiffLine {
    case unchanged(String)
    case addition(String)
    case deletion(String)
}
```

### Parsing Unified Diff

```
@@ -10,4 +10,6 @@
 unchanged line
-deleted line
+added line
+another added line
```

### Visual Rendering

**1. Gutter Markers (in main editor):**

```
┌─────┬────────────────────────────────┐
│  1  │ let x = 1                      │
│  2  │ let y = 2                      │  
│  3 ▌│ let z = 3  // modified         │  ← blue bar
│  4 +│ let w = 4  // added            │  ← green bar
└─────┴────────────────────────────────┘
```

**2. Diff View (dedicated panel):**

```swift
// Custom text view layers
func drawDiffBackground(for line: DiffLine, in rect: NSRect) {
    switch line {
    case .addition:
        NSColor.systemGreen.withAlphaComponent(0.2).setFill()
    case .deletion:
        NSColor.systemRed.withAlphaComponent(0.2).setFill()
    case .unchanged:
        return
    }
    rect.fill()
}
```

### Diff Algorithm

Uses **Myers diff algorithm** (same as Git) for computing line-level changes:

```swift
// Pseudo-code
let diff = myers(oldLines, newLines)
for change in diff {
    switch change {
    case .equal(let line): // unchanged
    case .insert(let line): // addition
    case .delete(let line): // deletion
    }
}
```

---

## 7. Key Architectural Patterns

### 1. AppKit Bridges for Performance

SwiftUI is used for layout and simpler views, but performance-critical components use AppKit:

| Component | Implementation |
|-----------|----------------|
| File Tree | `NSOutlineView` via `NSViewRepresentable` |
| Text Editor | Custom `NSView` subclass |
| Terminal | SwiftTerm (`NSView`) via `NSViewRepresentable` |

### 2. Modular Swift Packages

Everything is split into focused packages:

```
CodeEdit/
├── CodeEditModules/
│   ├── CodeEditUI/           # Shared UI components
│   ├── ProjectNavigator/     # File tree
│   ├── SourceControl/        # Git operations
│   ├── Terminal/             # SwiftTerm wrapper
│   └── ...
├── Dependencies:
│   ├── CodeEditTextView      # Text engine
│   ├── CodeEditSourceEditor  # Full editor
│   ├── CodeEditLanguages     # Tree-sitter
│   └── SwiftTerm             # Terminal emulator
```

### 3. WorkspaceDocument as Central State

```swift
class WorkspaceDocument: NSDocument {
    var fileTree: FileItem          // Root of file hierarchy
    var openFiles: [FileItem]       // Currently open tabs
    var selectedFile: FileItem?     // Active editor
    var gitClient: GitClient        // Git operations
    var terminalState: TerminalState
    // ...
}
```

---

## 8. Lessons for Devys

| Feature | CodeEdit Approach | Consideration for Devys |
|---------|-------------------|------------------------|
| **File Tree** | `NSOutlineView` wrapped in SwiftUI | Use AppKit for performance |
| **File Watching** | `FSEvents` API | Kernel-level, very efficient |
| **Text Editor** | Custom engine (CodeEditTextView) | Could use or fork this |
| **Terminal** | SwiftTerm | Mature, well-tested option |
| **Git** | Shell out to `git` CLI | Simple, reliable |
| **Diffs** | Parse unified format, layer-based rendering | Draw behind text |
| **Architecture** | Modular SPM packages | Good for maintainability |

---

## References

- [CodeEdit GitHub](https://github.com/CodeEditApp/CodeEdit)
- [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView)
- [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor)
- [CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- [Apple FSEvents Documentation](https://developer.apple.com/documentation/coreservices/file_system_events)
- [Apple NSOutlineView Documentation](https://developer.apple.com/documentation/appkit/nsoutlineview)
