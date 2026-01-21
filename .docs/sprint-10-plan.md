# Sprint 10: Code Editor + Git Pane

## Overview

Fully functional code editor using CodeEditSourceEditor with syntax highlighting, tabs, and save functionality. Git pane showing status with stage/unstage/commit capabilities.

---

## Goal

Code editor with syntax highlighting powered by Tree-sitter, multi-file tabs, and dirty state tracking. Git pane with full status, stage, unstage, and commit workflow.

## Demo

Open project → file tree shows git status colors → click file → code editor opens with syntax highlighting → edit file → ⌘S saves → git pane shows modified file → stage → commit.

---

## Progress Tracker

| Ticket | Title | Status | Commit |
|--------|-------|--------|--------|
| S10-01 | Add CodeEditSourceEditor Dependency | ✅ Complete | pending |
| S10-02 | Enhanced CodeEditorState | ✅ Complete | pending |
| S10-03 | CodeEditorPaneView | ✅ Complete | pending |
| S10-04 | Editor Tab Bar (Multi-file) | ✅ Complete | pending |
| S10-05 | File Save and Dirty State | ✅ Complete | pending |
| S10-06 | Wire Code Editor into Container | ✅ Complete | pending |
| S10-07 | GitClient Actor | ✅ Complete | pending |
| S10-08 | Enhanced GitState | ✅ Complete | pending |
| S10-09 | GitPaneView (Status List) | ✅ Complete | pending |
| S10-10 | Git Status in File Explorer | ✅ Complete | pending |
| S10-11 | Stage/Unstage Actions | ✅ Complete | pending |
| S10-12 | Commit Functionality | ✅ Complete | pending |
| S10-13 | Wire Git Pane into Container | ✅ Complete | pending |
| S10-14 | Terminal Auto-CWD | ✅ Complete | pending |

**Sprint Status**: ✅ COMPLETE (14/14 tickets)

**Legend**: ⬜ Not Started | 🔄 In Progress | ✅ Complete | ⏸️ Blocked

---

## Tickets

### S10-01: Add CodeEditSourceEditor Dependency

**Status**: ⬜ Not Started

**Description**: Add CodeEditSourceEditor package for syntax-highlighted code editing.

**File**: `Devys.xcodeproj/project.pbxproj` (via Xcode)

**Tasks**:
- [ ] Add package dependency via Xcode: File → Add Packages
- [ ] URL: `https://github.com/CodeEditApp/CodeEditSourceEditor`
- [ ] Version: 0.7.0+
- [ ] Add to Devys target
- [ ] Verify import works

**Validation**:
- [ ] `import CodeEditSourceEditor` compiles
- [ ] Package resolved in Package.resolved

**Commit**: `chore(deps): add CodeEditSourceEditor package`

---

### S10-02: Enhanced CodeEditorState

**Status**: ⬜ Not Started

**Description**: Expand code editor state to track open files, active file, cursor positions, and dirty state.

**File**: `Devys/Panes/CodeEditor/CodeEditorState.swift`

**Tasks**:
- [ ] Create `Panes/CodeEditor/` folder
- [ ] Define `OpenFile` model for each open file
- [ ] Define `CodeEditorState` with open files, active file
- [ ] Track dirty state per file
- [ ] Track cursor position per file
- [ ] Add language detection from file extension
- [ ] Add Codable support

**Code**:
```swift
import Foundation
import CodeEditSourceEditor

public struct OpenFile: Identifiable, Equatable, Codable {
    public let id: UUID
    public let url: URL
    public var content: String
    public var isDirty: Bool
    public var cursorLine: Int
    public var cursorColumn: Int
    public var language: CodeLanguage
    
    public init(url: URL, content: String = "") {
        self.id = UUID()
        self.url = url
        self.content = content
        self.isDirty = false
        self.cursorLine = 1
        self.cursorColumn = 1
        self.language = CodeLanguage.detectFromURL(url)
    }
    
    public var name: String { url.lastPathComponent }
    public var displayName: String { isDirty ? "• \(name)" : name }
}

public struct CodeEditorState: Equatable, Codable {
    public var openFiles: [OpenFile]
    public var activeFileId: UUID?
    
    public var activeFile: OpenFile? {
        guard let id = activeFileId else { return nil }
        return openFiles.first { $0.id == id }
    }
    
    public var hasUnsavedChanges: Bool {
        openFiles.contains { $0.isDirty }
    }
    
    public init() {
        self.openFiles = []
        self.activeFileId = nil
    }
    
    public init(fileURL: URL, content: String = "") {
        let file = OpenFile(url: fileURL, content: content)
        self.openFiles = [file]
        self.activeFileId = file.id
    }
    
    public mutating func openFile(_ url: URL, content: String) { /* ... */ }
    public mutating func closeFile(_ id: UUID) { /* ... */ }
    public mutating func updateContent(_ id: UUID, content: String) { /* ... */ }
    public mutating func markSaved(_ id: UUID) { /* ... */ }
}
```

**Commit**: `feat(code-editor): add enhanced CodeEditorState`

---

### S10-03: CodeEditorPaneView

**Status**: ⬜ Not Started

**Description**: SwiftUI view wrapping CodeEditSourceEditor for syntax-highlighted editing.

**File**: `Devys/Panes/CodeEditor/CodeEditorPaneView.swift`

**Tasks**:
- [ ] Create `CodeEditorPaneView` using SourceEditor
- [ ] Configure editor appearance (theme, font, line numbers)
- [ ] Handle content changes
- [ ] Update cursor position
- [ ] Create editor theme matching Devys colors

**Commit**: `feat(code-editor): add CodeEditorPaneView with syntax highlighting`

---

### S10-04: Editor Tab Bar (Multi-file)

**Status**: ⬜ Not Started

**Description**: Tab bar for switching between multiple open files in an editor pane.

**File**: `Devys/Panes/CodeEditor/EditorTabBar.swift`

**Tasks**:
- [ ] Create `EditorTabBar` view
- [ ] Show tab per open file
- [ ] Highlight active tab
- [ ] Show dirty indicator (dot)
- [ ] Close button per tab
- [ ] Tab click switches active file

**Commit**: `feat(code-editor): add EditorTabBar for multi-file editing`

---

### S10-05: File Save and Dirty State

**Status**: ⬜ Not Started

**Description**: ⌘S saves active file, dirty indicators, unsaved changes warning.

**Files**: `Devys/App/AppCommands.swift`, `Devys/Panes/CodeEditor/CodeEditorPaneView.swift`

**Tasks**:
- [ ] Add ⌘S shortcut to save active file
- [ ] Add ⌘⇧S for Save All
- [ ] Dirty indicator in tab and title
- [ ] Confirm before closing dirty file
- [ ] Confirm before closing dirty editor pane

**Commit**: `feat(code-editor): add file save and dirty state handling`

---

### S10-06: Wire Code Editor into Container

**Status**: ⬜ Not Started

**Description**: Replace code editor placeholder with real implementation.

**File**: `Devys/Panes/Core/PaneContainerView.swift`

**Tasks**:
- [ ] Update `paneContent` switch for `.codeEditor` case
- [ ] Pass mutable binding to state
- [ ] Show dirty indicator in pane title

**Commit**: `feat(code-editor): wire into PaneContainerView`

---

### S10-07: GitClient Actor

**Status**: ⬜ Not Started

**Description**: Actor for thread-safe git operations via shell commands.

**File**: `Devys/Panes/Git/GitClient.swift`

**Tasks**:
- [ ] Create `Panes/Git/` folder
- [ ] Create `GitClient` actor
- [ ] Implement status parsing (porcelain v1 format)
- [ ] Implement stage/unstage
- [ ] Implement commit
- [ ] Implement branch info
- [ ] Add async shell helper

**Commit**: `feat(git): add GitClient actor`

---

### S10-08: Enhanced GitState

**Status**: ⬜ Not Started

**Description**: State model for git pane with status entries and commit staging.

**File**: `Devys/Panes/Git/GitState.swift`

**Tasks**:
- [ ] Define `GitState` with repository URL
- [ ] Track staged and unstaged entries
- [ ] Track current branch
- [ ] Track commit message draft
- [ ] Add loading/error states

**Commit**: `feat(git): add enhanced GitState`

---

### S10-09: GitPaneView (Status List)

**Status**: ⬜ Not Started

**Description**: SwiftUI view showing git status with staged/unstaged sections.

**File**: `Devys/Panes/Git/GitPaneView.swift`

**Tasks**:
- [ ] Create `GitPaneView`
- [ ] Header with branch name and refresh button
- [ ] Staged changes section
- [ ] Unstaged changes section
- [ ] File rows with status icons
- [ ] Commit message field
- [ ] Commit button
- [ ] Loading and error states
- [ ] Auto-refresh on file system changes

**Commit**: `feat(git): add GitPaneView with status and commit`

---

### S10-10: Git Status in File Explorer

**Status**: ⬜ Not Started

**Description**: Show git status indicators in file explorer tree.

**Files**: `Devys/Panes/FileExplorer/FileExplorerController.swift`

**Tasks**:
- [ ] Create GitStatusProvider that watches repository
- [ ] Pass status map to FileExplorerController
- [ ] Color file names based on status (orange=modified, green=new, red=deleted)
- [ ] Refresh on git changes

**Commit**: `feat(git): add git status indicators in file explorer`

---

### S10-11: Stage/Unstage Actions

**Status**: ⬜ Not Started

**Description**: Context menu actions for staging files.

**Tasks**:
- [ ] Add "Stage" context menu item in file explorer
- [ ] Add "Unstage" context menu item
- [ ] Stage by clicking checkbox in git pane
- [ ] Stage All / Unstage All buttons
- [ ] Keyboard shortcuts (space to toggle stage in git pane)

**Commit**: `feat(git): add stage/unstage actions`

---

### S10-12: Commit Functionality

**Status**: ⬜ Not Started

**Description**: Full commit workflow with message.

**File**: `Devys/Panes/Git/GitPaneView.swift`

**Tasks**:
- [ ] Multi-line commit message field
- [ ] Commit button (disabled when nothing staged or no message)
- [ ] Clear message after successful commit
- [ ] Show commit success feedback

**Commit**: `feat(git): add commit functionality`

---

### S10-13: Wire Git Pane into Container

**Status**: ⬜ Not Started

**Description**: Replace git placeholder with real implementation.

**File**: `Devys/Panes/Core/PaneContainerView.swift`

**Tasks**:
- [ ] Update `paneContent` switch for `.git` case
- [ ] Pass mutable binding to state
- [ ] Initialize GitClient when pane appears

**Commit**: `feat(git): wire into PaneContainerView`

---

### S10-14: Terminal Auto-CWD

**Status**: ⬜ Not Started

**Description**: Terminals created for a project start in the project's root directory.

**Files**: `Devys/Panes/Terminal/TerminalState.swift`, `Devys/Canvas/CanvasState.swift`

**Tasks**:
- [ ] TerminalState stores workingDirectory
- [ ] createPane sets workingDirectory from project root
- [ ] Terminal starts shell with cd to directory
- [ ] Title shows current directory

**Commit**: `feat(terminal): auto-cwd to project root`

---

## File Structure After Sprint 10

```
Devys/Panes/
├── CodeEditor/                   # 🆕 NEW FOLDER
│   ├── CodeEditorState.swift     # S10-02
│   ├── CodeEditorPaneView.swift  # S10-03
│   └── EditorTabBar.swift        # S10-04
├── Git/                          # 🆕 NEW FOLDER
│   ├── GitClient.swift           # S10-07
│   ├── GitState.swift            # S10-08
│   ├── GitPaneView.swift         # S10-09
│   └── GitStatusProvider.swift   # S10-10
├── FileExplorer/
│   └── ... (updated with git status)
└── Core/
    └── PaneContainerView.swift   # Updated
```

---

## Definition of Done

- [ ] CodeEditSourceEditor integrated
- [ ] Code editor pane with syntax highlighting
- [ ] Multi-file tabs in editor
- [ ] ⌘S saves file
- [ ] Dirty indicator shows unsaved changes
- [ ] Git pane shows repository status
- [ ] Staged/unstaged sections work
- [ ] Stage/unstage from git pane and file explorer
- [ ] Commit with message works
- [ ] File explorer shows git status colors
- [ ] Terminals start in project directory

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-20 | Sprint 10 split from combined plan |
