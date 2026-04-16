# DevysGit Package Documentation

## Overview

DevysGit is a Swift Package providing a complete Git and GitHub integration layer for the Devys application. It provides:

- **Git CLI wrapper** for core Git operations (status, diff, staging, commits, branches, remotes)
- **GitHub CLI (`gh`) wrapper** for pull request management
- **Unified diff parsing** with word-level change detection
- **SwiftUI views** for displaying changes, diffs, commits, and PRs
- **Metal-accelerated diff rendering** for high-performance display
- **Observable state management** via `GitStore` for reactive UI updates

The package is built with Swift 6 strict concurrency, using actors for thread-safe git operations and `@MainActor` for UI state management.

---

## Package Dependencies

From `Package.swift`:

| Dependency | Purpose |
|------------|---------|
| **DevysCore** | Core utilities and shared types |
| **DevysSyntax** | Syntax highlighting themes (Shiki-based) for diff rendering |
| **DevysTextRenderer** | Text rendering utilities, hex color conversion |
| **DevysUI** | Shared UI components, DevysTheme, DevysColors |

Platform: macOS 14+
Swift: 6.0 with strict concurrency enabled

---

## Architecture

```
DevysGit
├── Models/          # Data models for git entities
├── Services/
│   ├── Client/      # Git CLI and GitHub CLI wrappers
│   ├── Diff/        # Diff parsing, rendering, word-level diff
│   └── Utilities/   # String extensions
└── Views/
    ├── Diff/        # Diff display views (unified, split, Metal)
    │   └── Metal/   # Metal-accelerated diff rendering
    └── PR/          # Pull request views
```

### Core Design Patterns

1. **Actor-based Clients**: `GitClient` and `GitHubClient` are actors ensuring thread-safe CLI operations
2. **Service Protocol**: `GitService` protocol abstracts git operations for testability
3. **Observable State**: `GitStore` uses `@Observable` (Swift Observation) for reactive UI
4. **Observable Store Pattern**: host layers construct `GitStore` instances explicitly for the workspace they are rendering
5. **Diff Parsing Pipeline**: Raw diff text -> `DiffParser` -> `ParsedDiff` -> `DiffRenderLayout` -> Views

---

## Directory Structure

### `/Sources/DevysGit/Models/`

| File | Description |
|------|-------------|
| `GitFileChange.swift` | File change with status, path, staging state |
| `GitBranch.swift` | Branch info (local/remote, current, upstream) |
| `GitCommit.swift` | Commit metadata (hash, author, date, message) |
| `GitRepositoryInfo.swift` | Repo state summary (branch, ahead/behind counts) |
| `PullRequest.swift` | PR model, PR file, merge method, state enums |
| `GitStore.swift` | Main observable state container |
| `GitStore+PullRequests.swift` | PR-related GitStore extensions |

### `/Sources/DevysGit/Services/Client/`

| File | Description |
|------|-------------|
| `GitClient.swift` | Actor wrapping `git` CLI commands |
| `GitHubClient.swift` | Actor wrapping `gh` CLI commands |
| `GitError.swift` | Typed errors for git and PR operations |

### `/Sources/DevysGit/Services/Diff/`

| File | Description |
|------|-------------|
| `DiffModels.swift` | `DiffLine`, `DiffHunk`, `ParsedDiff`, `DiffViewMode` |
| `DiffParser.swift` | Parses unified diff format into structured types |
| `DiffFileParser.swift` | Splits multi-file diffs into per-file `ParsedDiffFile` |
| `WordDiff.swift` | Word-level diff using LCS algorithm |
| `HunkPatch.swift` | Generates git-apply compatible patches from hunks |
| `DiffTheme.swift` | Theme resolution for diff colors (Shiki integration) |
| `DiffRenderConfiguration.swift` | Rendering options (font, line numbers, wrap, etc.) |
| `DiffRenderLayout.swift` | Layout models for unified/split diff display |

### `/Sources/DevysGit/Services/`

| File | Description |
|------|-------------|
| `DevysGit.swift` | Package exports and type aliases |
| `GitService.swift` | Protocol + default implementation |

### `/Sources/DevysGit/Views/`

| File | Description |
|------|-------------|
| `GitPanelView.swift` | Main panel with tabs (Changes, History, PRs) |
| `GitSidebarView.swift` | Staged/unstaged file list with actions |
| `GitDiffView.swift` | Main diff view with toolbar and mode toggle |
| `CommitSheet.swift` | Commit message composition modal |
| `CommitHistoryView.swift` | Commit log display |
| `BranchPicker.swift` | Branch management (checkout, create, delete) |

### `/Sources/DevysGit/Views/Diff/`

| File | Description |
|------|-------------|
| `DiffHunkView.swift` | Single hunk display |
| `DiffLineView.swift` | Single diff line |
| `HighlightedDiffLine.swift` | Line with word-level highlighting |
| `HunkActionBar.swift` | Accept/reject buttons for hunks |
| `SplitDiffView.swift` | Side-by-side diff display |
| `Metal/MetalDiffView.swift` | High-performance Metal-rendered diff |
| `Metal/MetalDiffDocumentView.swift` | Document-level Metal diff |
| `Metal/MetalDiffViewRepresentable.swift` | SwiftUI wrapper for Metal view |

### `/Sources/DevysGit/Views/PR/`

| File | Description |
|------|-------------|
| `PRListView.swift` | List of pull requests |
| `PRDetailView.swift` | Single PR details |
| `CreatePRSheet.swift` | New PR creation modal |

---

## Key Types

### Models

#### `GitFileChange`
```swift
public struct GitFileChange: Identifiable, Equatable, Hashable, Sendable {
    let id: String           // "staged:path" or "unstaged:path"
    let path: String
    let status: GitFileStatus
    let isStaged: Bool
    let oldPath: String?     // For renames
}
```

#### `GitFileStatus`
```swift
public enum GitFileStatus: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case unmerged = "U"
}
```

#### `GitBranch`
```swift
public struct GitBranch: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let isRemote: Bool
    let isCurrent: Bool
    let upstream: String?
}
```

#### `GitCommit`
```swift
public struct GitCommit: Identifiable, Equatable, Hashable, Sendable {
    let hash: String
    let shortHash: String
    let authorName: String
    let authorEmail: String
    let date: Date
    let message: String
}
```

#### `ParsedDiff`
```swift
public struct ParsedDiff: Equatable, Sendable {
    let hunks: [DiffHunk]
    let isBinary: Bool
    let oldPath: String?
    let newPath: String?
}
```

#### `DiffHunk`
```swift
public struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let header: String       // "@@ -1,3 +1,5 @@"
    let lines: [DiffLine]
    let isStaged: Bool
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
}
```

#### `DiffLine`
```swift
public struct DiffLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: LineType       // .context, .added, .removed, .header, .noNewline
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}
```

### Services

#### `GitClient` (Actor)
Thread-safe wrapper for git CLI operations:
- `status()` -> `[GitFileChange]`
- `repositoryInfo()` -> `GitRepositoryInfo`
- `diff(for:staged:contextLines:ignoreWhitespace:)` -> `String`
- `stage(_:)` / `unstage(_:)` / `stageAll()` / `unstageAll()`
- `stageHunk(_:for:)` / `unstageHunk(_:for:)` / `discardHunk(_:for:)`
- `commit(message:)` -> `String` (commit hash)
- `push()` / `pull()` / `fetch()`
- `branches()` -> `[GitBranch]`
- `checkout(branch:)` / `createBranch(name:)` / `deleteBranch(name:)`
- `log(count:)` -> `[GitCommit]`
- `show(commit:)` -> `String`

#### `GitHubClient` (Actor)
Thread-safe wrapper for `gh` CLI:
- `isAvailable()` -> `Bool`
- `listPRs(state:author:limit:)` -> `[PullRequest]`
- `getPR(number:)` -> `PullRequest`
- `getPRFiles(number:)` -> `[PRFile]`
- `getPRDiff(number:)` -> `String`
- `createPR(title:body:base:draft:)` -> `Int`
- `checkoutPR(number:)`
- `approve(number:body:)` / `requestChanges(number:body:)` / `comment(number:body:)`
- `merge(number:method:deleteHead:)`

#### `GitService` (Protocol)
Abstraction over `GitClient` and `GitHubClient` for dependency injection:
```swift
@MainActor
public protocol GitService {
    var hasRepository: Bool { get }
    var hasPRClient: Bool { get }
    // All git operations...
}
```

#### `GitStore` (@Observable)
Main state container for git UI:
```swift
@MainActor
@Observable
public final class GitStore {
    // State
    var repoInfo: GitRepositoryInfo?
    var changes: [GitFileChange]
    var selectedFilePath: String?
    var selectedDiff: ParsedDiff?
    var diffViewMode: DiffViewMode

    // Derived
    var stagedChanges: [GitFileChange]
    var unstagedChanges: [GitFileChange]

    // Actions
    func refresh() async
    func selectFile(_:isStaged:) async
    func stage(_:) async
    func unstage(_:) async
    func acceptHunk(_:) async
    func rejectHunk(_:) async
    // ...
}
```

---

## Git Command Patterns

### Status Parsing
Uses `git status --porcelain=v1` format:
```
XY PATH
```
Where X = index status, Y = worktree status.

### Diff Operations
- Unstaged: `git diff --no-color --unified=N -- PATH`
- Staged: `git diff --cached --no-color --unified=N -- PATH`
- Between refs: `git diff --no-color BASE...HEAD`

### Hunk Staging/Unstaging
Uses `git apply` with temporary patch files:
```swift
// Stage hunk
git apply --cached PATCH_FILE

// Unstage hunk
git apply --cached --reverse PATCH_FILE

// Discard hunk
git apply --reverse PATCH_FILE
```

### Commit Log
Uses custom format for parsing:
```
git log --format=%H|%h|%an|%ae|%at|%s -N
```

### Branch Listing
```
git branch --format=%(refname:short)|%(upstream:short)|%(HEAD) -a
```

---

## Public API Surface

### Entry Points

```swift
// Create a store for the workspace you are rendering
let store = GitStore(projectFolder: folder)
let panel = GitPanelView(store: store)
```

### Key View Components

- `GitPanelView` - Main panel with tabs
- `GitSidebarView` - File change list
- `GitDiffView` - Diff viewer with Metal rendering
- `CommitSheet` - Commit dialog
- `BranchPicker` - Branch management
- `PRListView` / `PRDetailView` - Pull request UI

### Exported Types

```swift
// Type aliases
public typealias GitClientType = GitClient
public typealias GitHubClientType = GitHubClient

// Models
public struct GitFileChange
public struct GitBranch
public struct GitCommit
public struct GitRepositoryInfo
public struct PullRequest
public struct PRFile
public struct ParsedDiff
public struct DiffHunk
public struct DiffLine

// Errors
public enum GitError: Error
public enum PRError: Error

// Services
public actor GitClient
public actor GitHubClient
public protocol GitService
public struct DefaultGitService: GitService
public final class GitStore
```

---

## Diff Rendering Pipeline

```
1. Raw Diff Text (from git diff)
        |
        v
2. DiffParser.parse(_:) -> ParsedDiff
        |
        v
3. WordDiff.diff(old:new:) for paired added/removed lines
        |
        v
4. DiffRenderLayoutBuilder.build(_:) -> DiffRenderLayout
        |
        v
5. MetalDiffView or SwiftUI views
```

### Word Diff Algorithm
Uses Longest Common Subsequence (LCS) to identify changed words:
- Tokenizes into words, symbols, optionally whitespace
- Computes LCS to find unchanged tokens
- Marks non-LCS tokens as added/removed

### Diff View Modes
- **Unified**: Traditional single-column diff with +/- prefixes
- **Split**: Side-by-side old/new columns

---

## Error Handling

### `GitError`
```swift
public enum GitError: Error, LocalizedError {
    case notRepository(URL)
    case commandFailed(arguments:stderr:stdout:status:)
    case timedOut(arguments:timeout:)
    case invalidOutput(String)
}
```

### `PRError`
```swift
public enum PRError: Error, LocalizedError {
    case notFound(Int)
    case ghNotInstalled
    case notAuthenticated
    case rateLimited
    case commandFailed(arguments:stderr:status:)
}
```

---

## Testing

Tests are in `/Tests/DevysGitTests/`:

- `DiffParserTests.swift` - Tests unified diff parsing
- `WordDiffTests.swift` - Tests word-level diff algorithm

Run tests:
```bash
swift test
```

---

## Keyboard Shortcuts

In `GitDiffView`:
- `j` / Down Arrow: Next hunk
- `k` / Up Arrow: Previous hunk
- `n`: Next file
- `p`: Previous file
- `a`: Accept focused hunk
- `r`: Reject focused hunk

---

## Conventions

1. **Concurrency**: All git operations are async. Use `await` for git commands.
2. **MainActor**: UI state (`GitStore`, views) must be accessed on main actor.
3. **Error Messages**: Prefer `localizedDescription` for user-facing errors.
4. **File Paths**: All paths are relative to repository root.
5. **Staged vs Unstaged**: Track via `isStaged` bool, use separate collections in UI.
6. **Hunk Operations**: Generate patches via `DiffHunk.toPatch()` for granular staging.

---

## Usage Examples

### Basic Git Operations
```swift
let client = GitClient(repositoryURL: repoURL)

// Get status
let changes = try await client.status()

// Stage and commit
try await client.stage("file.swift")
let hash = try await client.commit(message: "Add feature")

// Push
try await client.push()
```

### Using GitStore
```swift
@MainActor
func example() async {
    let store = GitStore(projectFolder: repoURL)

    // Refresh status
    await store.refresh()

    // Select file for diff
    await store.selectFile("file.swift", isStaged: false)

    // Stage a hunk
    if let hunk = store.selectedDiff?.hunks.first {
        await store.acceptHunk(hunk)
    }
}
```

### Pull Requests
```swift
let ghClient = GitHubClient(repositoryURL: repoURL)

// List open PRs
let prs = try await ghClient.listPRs(state: .open)

// Create PR
let prNumber = try await ghClient.createPR(
    title: "Feature: New thing",
    body: "Description here",
    draft: false
)

// Merge PR
try await ghClient.merge(number: prNumber, method: .squash)
```
