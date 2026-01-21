# Sprint 9.5: File Explorer Linking, Git Enhancements, Diff View

## Overview

Polish sprint connecting file explorer to editor panes, adding per-file git discard, and implementing a proper diff view with hunk support.

---

## Goal

- File tree opens files in a linked editor pane (not creating new panes)
- Git pane supports per-file discard (revert to HEAD)
- Unified diff view with hunks, syntax coloring, and hunk-level actions

## Demo

Open project → file tree linked to editor → click file → opens as tab in linked editor → git pane shows changes → click change → diff pane shows hunks → discard individual file or hunk.

---

## Progress Tracker

| Ticket | Title | Status | Commit |
|--------|-------|--------|--------|
| FE-01 | Linked Editor State | ✅ Complete | |
| FE-02 | File Click Opens in Linked Editor | ✅ Complete | |
| FE-03 | Visual Link Indicator | ⏸️ Deferred | |
| FE-04 | Context Menu Open in New Editor | ⏸️ Deferred | |
| GIT-01 | GitClient Discard Method | ✅ Complete | |
| GIT-02 | Discard Button in Git Row | ✅ Complete | |
| GIT-03 | Discard Confirmation Dialog | ✅ Complete | |
| DIFF-01 | DiffPaneState and DiffPaneView | ✅ Complete | |
| DIFF-02 | Parse Diff into Hunks | ✅ Complete | |
| DIFF-03 | Render Hunks with Colors | ✅ Complete | |
| DIFF-04 | Wire Git File Click to Diff Pane | ✅ Complete | |
| DIFF-05 | Hunk-level Stage/Discard | ✅ Complete | |

**Legend**: ⬜ Not Started | 🔄 In Progress | ✅ Complete | ⏸️ Blocked/Deferred

---

## Tickets

### Phase 1: File Explorer → Editor Linking

---

### FE-01: Linked Editor State

**Status**: ✅ Complete

**Description**: Add ability for file explorer to link to a specific code editor pane.

**File**: `Devys/Panes/Core/PaneType.swift`

**Tasks**:
- [ ] Add `linkedEditorPaneId: UUID?` to `FileExplorerPaneState`
- [ ] Add method to find/create linked editor in `CanvasState`
- [ ] Store link when file explorer creates an editor

**Validation**:
- [ ] FileExplorerPaneState has linkedEditorPaneId property
- [ ] Link persists across file explorer updates

**Commit**: `feat(file-explorer): add linked editor pane tracking`

---

### FE-02: File Click Opens in Linked Editor

**Status**: ✅ Complete

**Description**: When clicking a file in file explorer, open it as a tab in the linked editor instead of creating a new pane.

**File**: `Devys/Panes/FileExplorer/FileExplorerPaneView.swift`

**Tasks**:
- [ ] On file click, check if linked editor exists
- [ ] If exists: open file as new tab in that editor
- [ ] If not exists: create new editor, link it, open file
- [ ] Update FileExplorerController callback to support this

**Validation**:
- [ ] First file click creates editor and links
- [ ] Subsequent file clicks open in same editor as tabs
- [ ] Multiple files open as tabs, not new panes

**Commit**: `feat(file-explorer): open files in linked editor pane`

---

### FE-03: Visual Link Indicator

**Status**: ⏸️ Deferred (polish item)

**Description**: Show visual indicator in file explorer when linked to an editor.

**File**: `Devys/Panes/FileExplorer/FileExplorerPaneView.swift`

**Tasks**:
- [ ] Add small icon/badge showing linked status
- [ ] Tooltip showing which editor is linked
- [ ] Different color if linked editor is closed

**Validation**:
- [ ] Visual indicator visible when linked
- [ ] Indicator updates when link changes

**Commit**: `feat(file-explorer): add linked editor indicator`

---

### FE-04: Context Menu Open in New Editor

**Status**: ⏸️ Deferred (polish item)

**Description**: Add context menu option to force open file in a new editor pane.

**File**: `Devys/Panes/FileExplorer/FileExplorerController.swift`

**Tasks**:
- [ ] Add "Open in New Editor" context menu item
- [ ] Create new editor pane on selection
- [ ] Option to "Set as Linked Editor"

**Validation**:
- [ ] Context menu shows option
- [ ] New editor created with file open
- [ ] Can change linked editor via context menu

**Commit**: `feat(file-explorer): context menu for new editor`

---

### Phase 2: Git Per-File Discard

---

### GIT-01: GitClient Discard Method

**Status**: ✅ Complete

**Description**: Add method to discard changes for a single file.

**File**: `Devys/Panes/Git/GitClient.swift`

**Tasks**:
- [ ] Add `discard(_ path: String)` method
- [ ] Use `git checkout -- <path>` for tracked files
- [ ] Use `git clean -f <path>` for untracked files
- [ ] Add `discardAll()` method

**Code**:
```swift
/// Discard changes to a file (revert to HEAD)
public func discard(_ path: String) async throws {
    _ = try await runGit("checkout", "--", path)
}

/// Discard an untracked file
public func discardUntracked(_ path: String) async throws {
    _ = try await runGit("clean", "-f", "--", path)
}
```

**Validation**:
- [ ] Modified files reverted to HEAD
- [ ] Untracked files deleted
- [ ] Staged changes preserved (only worktree discarded)

**Commit**: `feat(git): add per-file discard methods`

---

### GIT-02: Discard Button in Git Row

**Status**: ✅ Complete

**Description**: Add discard button to each file row in git pane.

**File**: `Devys/Panes/Git/GitPaneView.swift`

**Tasks**:
- [ ] Add discard icon (arrow.uturn.backward) to GitChangeRow
- [ ] Show on hover alongside stage/unstage button
- [ ] Different handling for staged vs unstaged
- [ ] Red color to indicate destructive

**UI Layout**:
```
[status] filename.swift  [↩︎] [+/-]
                         ^     ^
                     discard  stage
```

**Validation**:
- [ ] Button appears on hover
- [ ] Clicking triggers discard flow
- [ ] Visual feedback during discard

**Commit**: `feat(git): add per-file discard button`

---

### GIT-03: Discard Confirmation Dialog

**Status**: ✅ Complete

**Description**: Show confirmation before discarding changes (destructive action).

**File**: `Devys/Panes/Git/GitPaneView.swift`

**Tasks**:
- [ ] Add confirmation alert state
- [ ] Show alert with file name and warning
- [ ] "Discard" and "Cancel" buttons
- [ ] Skip confirmation for untracked files (optional)

**Validation**:
- [ ] Alert shown before discard
- [ ] Cancel aborts discard
- [ ] Confirm executes discard

**Commit**: `feat(git): confirmation dialog for discard`

---

### Phase 3: Diff View

---

### DIFF-01: DiffPaneState and DiffPaneView

**Status**: ✅ Complete

**Description**: Create new pane type for viewing file diffs.

**Files**: 
- `Devys/Panes/Diff/DiffPaneState.swift`
- `Devys/Panes/Diff/DiffPaneView.swift`
- `Devys/Panes/Core/PaneType.swift`

**Tasks**:
- [ ] Create `Panes/Diff/` folder
- [ ] Define `DiffPaneState` with file path, hunks
- [ ] Add `.diff(DiffPaneState)` to PaneType
- [ ] Create basic `DiffPaneView` shell
- [ ] Wire into PaneContainerView

**Validation**:
- [ ] Can create diff pane via code
- [ ] Pane appears on canvas
- [ ] Shows placeholder content

**Commit**: `feat(diff): add diff pane type and view shell`

---

### DIFF-02: Parse Diff into Hunks

**Status**: ✅ Complete

**Description**: Parse unified diff output into structured hunk models.

**File**: `Devys/Panes/Diff/DiffParser.swift`

**Tasks**:
- [ ] Define `DiffHunk` model (header, lines)
- [ ] Define `DiffLine` model (type: add/remove/context, content)
- [ ] Parse unified diff format
- [ ] Handle multiple hunks per file

**Models**:
```swift
struct DiffHunk: Identifiable {
    let id: UUID
    let header: String  // @@ -1,5 +1,6 @@
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable {
    let id: UUID
    let type: LineType  // .added, .removed, .context
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}
```

**Validation**:
- [ ] Parse simple diff with one hunk
- [ ] Parse diff with multiple hunks
- [ ] Handle edge cases (binary files, renames)

**Commit**: `feat(diff): add unified diff parser`

---

### DIFF-03: Render Hunks with Colors

**Status**: ✅ Complete

**Description**: Display parsed hunks with proper syntax coloring.

**File**: `Devys/Panes/Diff/DiffPaneView.swift`

**Tasks**:
- [ ] Render each hunk in a section
- [ ] Green background for added lines (+)
- [ ] Red background for removed lines (-)
- [ ] Gray for context lines
- [ ] Line numbers (old/new)
- [ ] Monospace font
- [ ] Collapsible hunks

**Validation**:
- [ ] Added lines show green
- [ ] Removed lines show red
- [ ] Context lines show neutral
- [ ] Line numbers accurate

**Commit**: `feat(diff): render hunks with syntax colors`

---

### DIFF-04: Wire Git File Click to Diff Pane

**Status**: ✅ Complete

**Description**: Clicking a file in git pane opens/updates diff pane.

**File**: `Devys/Panes/Git/GitPaneView.swift`

**Tasks**:
- [ ] On file click, find or create diff pane
- [ ] Load diff content and parse to hunks
- [ ] Update diff pane with new content
- [ ] Highlight selected file in git pane

**Validation**:
- [ ] First click creates diff pane
- [ ] Subsequent clicks update same pane
- [ ] Diff shows correct file content

**Commit**: `feat(git): open diff pane on file click`

---

### DIFF-05: Hunk-level Stage/Discard

**Status**: ✅ Complete

**Description**: Allow staging or discarding individual hunks.

**Files**:
- `Devys/Panes/Git/GitClient.swift`
- `Devys/Panes/Diff/DiffPaneView.swift`

**Tasks**:
- [ ] Add hunk header to DiffHunk for patch format
- [ ] Generate patch from single hunk
- [ ] `git apply --cached` for staging hunk
- [ ] `git apply --reverse` for discarding hunk
- [ ] Add stage/discard buttons per hunk

**Validation**:
- [ ] Can stage single hunk
- [ ] Can discard single hunk
- [ ] Other hunks unaffected

**Commit**: `feat(diff): hunk-level stage and discard`

---

## Dependencies

```
Phase 1: File Explorer Linking
├── FE-01 (state)
├── FE-02 (core logic) ← depends on FE-01
├── FE-03 (visual) ← depends on FE-01
└── FE-04 (context menu) ← depends on FE-01

Phase 2: Git Discard (independent)
├── GIT-01 (client methods)
├── GIT-02 (UI button) ← depends on GIT-01
└── GIT-03 (confirmation) ← depends on GIT-02

Phase 3: Diff View
├── DIFF-01 (pane shell)
├── DIFF-02 (parser)
├── DIFF-03 (renderer) ← depends on DIFF-01, DIFF-02
├── DIFF-04 (git integration) ← depends on DIFF-01
└── DIFF-05 (hunk actions) ← depends on DIFF-02, GIT-01
```

---

## Execution Order

1. **FE-01, FE-02** - File explorer linking (highest UX impact)
2. **GIT-01, GIT-02, GIT-03** - Git discard (independent, quick wins)
3. **DIFF-01, DIFF-02, DIFF-03** - Diff view (new feature)
4. **DIFF-04** - Wire git to diff
5. **FE-03, FE-04** - Polish file explorer
6. **DIFF-05** - Hunk-level actions (advanced)

---

## Technical Notes

### Git Library

Currently using shell-out to `/usr/bin/git`. For hunk-level staging, we need to generate patches.

**Options**:
- Continue with shell commands (`git apply --cached`)
- Consider SwiftGit2 (libgit2 wrapper) for more control
- ObjectiveGit (Objective-C, older)

**Recommendation**: Continue with shell commands for simplicity. Patch generation is string manipulation.

### Diff Parsing

Unified diff format:
```diff
--- a/file.swift
+++ b/file.swift
@@ -10,6 +10,7 @@ func example() {
     let a = 1
+    let b = 2
     let c = 3
 }
```

Parse with regex:
- Hunk header: `^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@`
- Added line: `^\+(.*)$`
- Removed line: `^-(.*)$`
- Context line: `^ (.*)$`

---

## Definition of Done

- [x] File explorer opens files in linked editor (not new panes)
- [x] Git pane has per-file discard with confirmation
- [x] Diff pane shows hunks with green/red coloring
- [x] Clicking git file opens diff pane
- [x] Build succeeds with no errors
- [ ] All features manually tested
