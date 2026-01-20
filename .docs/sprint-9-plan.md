# Sprint 9: Project Tabs + File Explorer + Pane Hotkeys

## Overview

Project tab system with native macOS tabs, functional file explorer pane using NSOutlineView, and keyboard-first pane navigation with ⌘1-9 hotkeys.

**Vision**: Customizable, decomposed IDE where users arrange panes however they want, with project tabs providing automatic context scoping and full keyboard navigation.

---

## Architecture Summary

```
┌─ Devys Window ─────────────────────────────────────────────────────────┐
│ [Tab: my-app ▼] [Tab: api-server ▼] [+]              [Layouts ▼]       │
├────────────────────────────────────────────────────────────────────────┤
│                     Canvas (my-app project context)                     │
│                                                                         │
│   ┌─ [1] File Tree ─┐  ┌─ [2] Editor: App.tsx ─┐ ┌─ [3] Terminal ────┐│
│   │ ~/my-app        │  │ (⌘2 to focus)         │ │ (⌘3 to focus)     ││
│   │ ├─ src/         │  └───────────────────────┘ └───────────────────┘│
│   └─────────────────┘                                                   │
│                                                                         │
│   ┌─ [4] Git ───────────────────┐  ┌─ [5] Browser ───────────────────┐│
│   │ 2 staged (⌘4 to focus)      │  │ :3000 (⌘5 to focus)             ││
│   └─────────────────────────────┘  └─────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Project** | A folder root with git context; provides default paths for panes |
| **WorkspaceTab** | A tab containing a project and its canvas state |
| **Pane Scoping** | Panes have optional `projectId`; project-aware panes inherit active project |
| **Pane Hotkeys** | Each pane gets a number (1-9) in title bar; ⌘1-9 focuses that pane |
| **Decomposed Panes** | File explorer, editor, git, terminal are separate, independent panes |

---

## Goal

Project tab system with native macOS tabs and a functional file explorer pane using NSOutlineView. Full keyboard navigation with ⌘1-9 to focus any pane.

## Demo

Open folder → project tab appears → file tree renders → ⌘1 focuses file tree → arrow keys navigate → Enter opens file → ⌘2 focuses editor → edit code → ⌘3 focuses terminal → type command → all without mouse.

---

## Progress Tracker

| Ticket | Title | Status | Commit |
|--------|-------|--------|--------|
| S9-01 | Project Model | ⬜ Not Started | |
| S9-02 | WorkspaceTab and WorkspaceState | ⬜ Not Started | |
| S9-03 | ProjectTabBar UI | ⬜ Not Started | |
| S9-04 | Tab Lifecycle (Add/Switch/Close) | ⬜ Not Started | |
| S9-05 | Pane Project Scoping | ⬜ Not Started | |
| S9-06 | FileItem Model | ⬜ Not Started | |
| S9-07 | FileSystemWatcher (FSEvents) | ⬜ Not Started | |
| S9-08 | FileExplorerController (NSOutlineView) | ⬜ Not Started | |
| S9-09 | FileExplorerPaneView | ⬜ Not Started | |
| S9-10 | Wire File Explorer into Container | ⬜ Not Started | |
| S9-11 | Open Project Command | ⬜ Not Started | |
| S9-12 | Folder Drag-Drop to Create Project | ⬜ Not Started | |
| S9-13 | Pane Hotkeys (⌘1-9) | ⬜ Not Started | |

**Legend**: ⬜ Not Started | 🔄 In Progress | ✅ Complete | ⏸️ Blocked

---

## Tickets

### S9-01: Project Model

**Status**: ⬜ Not Started

**Description**: Core model representing a project (a rooted folder with optional git context).

**File**: `Devys/Workspace/Project.swift`

**Tasks**:
- [ ] Create `Workspace/` folder
- [ ] Define `Project` struct with Identifiable, Codable, Equatable
- [ ] Add properties: id, name, rootURL, createdAt
- [ ] Add optional git properties: gitBranch, gitRemoteURL
- [ ] Add convenience initializer from URL
- [ ] Add validation (folder exists, is directory)

**Code**:
```swift
import Foundation

/// Represents a project context (a rooted folder).
public struct Project: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var rootURL: URL
    public var createdAt: Date
    
    /// Current git branch name (nil if not a git repo)
    public var gitBranch: String?
    
    /// Git remote URL (nil if no remote)
    public var gitRemoteURL: URL?
    
    /// Whether this is a git repository
    public var isGitRepository: Bool { gitBranch != nil }
    
    public init(id: UUID = UUID(), rootURL: URL, name: String? = nil) {
        self.id = id
        self.rootURL = rootURL
        self.name = name ?? rootURL.lastPathComponent
        self.createdAt = Date()
    }
    
    public static func create(from url: URL) throws -> Project {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectError.notADirectory(url)
        }
        return Project(rootURL: url)
    }
}

public enum ProjectError: LocalizedError {
    case notADirectory(URL)
    case folderNotFound(URL)
    
    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url): return "'\(url.lastPathComponent)' is not a folder"
        case .folderNotFound(let url): return "Folder not found: \(url.path)"
        }
    }
}
```

**Validation**:
- [ ] Project initializes correctly from URL
- [ ] Name defaults to folder name
- [ ] Codable round-trip works

**Commit**: `feat(workspace): add Project model`

---

### S9-02: WorkspaceTab and WorkspaceState

**Status**: ⬜ Not Started

**Description**: Tab model and root observable state for managing multiple project tabs.

**File**: `Devys/Workspace/WorkspaceState.swift`

**Tasks**:
- [ ] Define `WorkspaceTab` struct (project + canvas state)
- [ ] Define `ViewportState` for canvas position
- [ ] Create `WorkspaceState` @Observable class
- [ ] Add tab management methods (add, remove, switch)
- [ ] Add computed property for active project

**Commit**: `feat(workspace): add WorkspaceTab and WorkspaceState`

---

### S9-03: ProjectTabBar UI

**Status**: ⬜ Not Started

**Description**: Native macOS-style tab bar for project switching.

**File**: `Devys/Workspace/ProjectTabBar.swift`

**Tasks**:
- [ ] Create `ProjectTabBar` view
- [ ] Create `ProjectTab` view for individual tabs
- [ ] Show project name and git branch
- [ ] Add tab button, close button
- [ ] Tab selection highlighting
- [ ] Layouts dropdown menu (placeholder for Sprint 11)

**Commit**: `feat(workspace): add ProjectTabBar UI`

---

### S9-04: Tab Lifecycle (Add/Switch/Close)

**Status**: ⬜ Not Started

**Description**: Wire tab bar into main app, handle keyboard shortcuts.

**Files**: `Devys/ContentView.swift`, `Devys/App/AppCommands.swift`

**Tasks**:
- [ ] Add WorkspaceState to DevysApp
- [ ] Integrate ProjectTabBar into ContentView
- [ ] Add shortcuts: ⌘T (new tab), ⌘W (close tab), ⌘⇧]/⌘⇧[ (switch tabs)
- [ ] Handle empty workspace state
- [ ] Pass active tab's canvas state to CanvasView

**Commit**: `feat(workspace): wire tab lifecycle and shortcuts`

---

### S9-05: Pane Project Scoping

**Status**: ⬜ Not Started

**Description**: Add projectId to Pane model; panes auto-scope to active project on creation.

**Files**: `Devys/Panes/Core/Pane.swift`, `Devys/Canvas/CanvasState.swift`

**Tasks**:
- [ ] Add `projectId: UUID?` to Pane
- [ ] Add `isProjectScoped` computed property to PaneType
- [ ] Update `createPane()` to auto-scope to active project
- [ ] Initialize pane state with project root when scoped

**Commit**: `feat(panes): add project scoping to panes`

---

### S9-06: FileItem Model

**Status**: ⬜ Not Started

**Description**: Recursive tree model for file system representation with git status support.

**File**: `Devys/Panes/FileExplorer/FileItem.swift`

**Tasks**:
- [ ] Create `Panes/FileExplorer/` folder
- [ ] Define `FileItem` class (reference type for tree structure)
- [ ] Add parent/children relationships
- [ ] Add git status property
- [ ] Add computed properties (isDirectory, name, icon)
- [ ] Add method to load children from disk
- [ ] Add sorting (folders first, then alphabetical)

**Commit**: `feat(file-explorer): add FileItem model`

---

### S9-07: FileSystemWatcher (FSEvents)

**Status**: ⬜ Not Started

**Description**: Actor that monitors file system changes using macOS FSEvents API.

**File**: `Devys/Panes/FileExplorer/FileSystemWatcher.swift`

**Tasks**:
- [ ] Create `FileSystemWatcher` actor
- [ ] Implement FSEvents stream setup
- [ ] Define callback for file changes
- [ ] Add debouncing (batch rapid changes)
- [ ] Publish changes via AsyncStream
- [ ] Proper cleanup on deinit

**Commit**: `feat(file-explorer): add FileSystemWatcher with FSEvents`

---

### S9-08: FileExplorerController (NSOutlineView)

**Status**: ⬜ Not Started

**Description**: AppKit controller hosting NSOutlineView for performant file tree rendering.

**File**: `Devys/Panes/FileExplorer/FileExplorerController.swift`

**Tasks**:
- [ ] Create `FileExplorerController: NSViewController`
- [ ] Set up `NSOutlineView` with data source and delegate
- [ ] Handle expand/collapse and selection
- [ ] Style cells with icons and git status
- [ ] Create context menu (New File, New Folder, Delete, Rename)
- [ ] Wire up FileSystemWatcher for live updates

**Commit**: `feat(file-explorer): add FileExplorerController with NSOutlineView`

---

### S9-09: FileExplorerPaneView

**Status**: ⬜ Not Started

**Description**: SwiftUI wrapper for FileExplorerController.

**File**: `Devys/Panes/FileExplorer/FileExplorerPaneView.swift`

**Tasks**:
- [ ] Create `FileExplorerPaneView: NSViewControllerRepresentable`
- [ ] Create Coordinator for delegate handling
- [ ] Wire delegate to open files in code editor panes
- [ ] Handle file operations (new, delete, rename)

**Commit**: `feat(file-explorer): add FileExplorerPaneView`

---

### S9-10: Wire File Explorer into Container

**Status**: ⬜ Not Started

**Description**: Replace file explorer placeholder with real implementation.

**File**: `Devys/Panes/Core/PaneContainerView.swift`

**Tasks**:
- [ ] Update `paneContent` switch for `.fileExplorer` case
- [ ] Add project indicator to title bar

**Commit**: `feat(file-explorer): wire into PaneContainerView`

---

### S9-11: Open Project Command

**Status**: ⬜ Not Started

**Description**: Menu command and keyboard shortcut to open a project folder.

**File**: `Devys/App/AppCommands.swift`

**Tasks**:
- [ ] Add "Open Project..." menu item
- [ ] Add ⇧⌘O keyboard shortcut
- [ ] Show folder picker
- [ ] Create new project tab

**Commit**: `feat(workspace): add Open Project command`

---

### S9-12: Folder Drag-Drop to Create Project

**Status**: ⬜ Not Started

**Description**: Drag a folder onto the canvas or tab bar to create a new project.

**Files**: `Devys/Workspace/ProjectTabBar.swift`, `Devys/Canvas/CanvasView.swift`

**Tasks**:
- [ ] Add drop target to ProjectTabBar
- [ ] Add drop target to empty workspace view
- [ ] Validate dropped item is a directory
- [ ] Handle multiple folders (create multiple tabs)

**Commit**: `feat(workspace): add folder drag-drop for project creation`

---

### S9-13: Pane Hotkeys (⌘1-9)

**Status**: ⬜ Not Started

**Description**: Assign each pane a number (1-9) displayed in title bar. ⌘1-9 focuses that pane for full keyboard-only navigation.

**Files**:
- `Devys/Panes/Core/Pane.swift`
- `Devys/Panes/Core/PaneContainerView.swift`
- `Devys/Canvas/CanvasState.swift`
- `Devys/App/AppCommands.swift`

**Tasks**:
- [ ] Add `hotkeyIndex: Int?` to Pane model (1-9, nil if none assigned)
- [ ] Auto-assign hotkey index when pane created (next available 1-9)
- [ ] Recalculate hotkey indices when panes deleted
- [ ] Display hotkey badge in pane title bar (e.g., `[1]`, `[2]`)
- [ ] Add ⌘1-9 keyboard shortcuts in AppCommands
- [ ] `focusPane(hotkeyIndex:)` method in CanvasState
- [ ] Focus pane = select pane + make first responder
- [ ] Style hotkey badge to be visible but not intrusive

**Code**:
```swift
// Pane.swift additions

public struct Pane: Identifiable, Equatable, Codable {
    // ... existing properties ...
    
    /// Hotkey index for keyboard navigation (1-9, nil if not assigned)
    public var hotkeyIndex: Int?
}
```

```swift
// CanvasState.swift additions

/// Assign hotkey indices to panes (1-9)
public func recalculateHotkeyIndices() {
    // Sort panes by creation order or z-index
    let sortedPanes = panesSortedByZIndex
    
    for (index, pane) in sortedPanes.prefix(9).enumerated() {
        if let paneIndex = paneIndex(withId: pane.id) {
            panes[paneIndex].hotkeyIndex = index + 1
        }
    }
    
    // Clear hotkeys for panes beyond 9
    for pane in sortedPanes.dropFirst(9) {
        if let paneIndex = paneIndex(withId: pane.id) {
            panes[paneIndex].hotkeyIndex = nil
        }
    }
}

/// Focus pane by hotkey index
public func focusPaneByHotkey(_ index: Int) {
    guard let pane = panes.first(where: { $0.hotkeyIndex == index }) else { return }
    selectPane(pane.id)
    // Post notification to request focus for this pane
    NotificationCenter.default.post(name: .focusPane, object: pane.id)
}

extension Notification.Name {
    static let focusPane = Notification.Name("focusPane")
}
```

```swift
// PaneContainerView.swift - title bar updates

private var titleBar: some View {
    HStack(spacing: 8) {
        // Hotkey badge
        if let hotkeyIndex = pane.hotkeyIndex {
            Text("⌘\(hotkeyIndex)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Press ⌘\(hotkeyIndex) to focus this pane")
        }
        
        // Project indicator (if scoped)
        if let projectId = pane.projectId,
           let project = workspace?.project(withId: projectId) {
            Text(project.name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
        }
        
        // Pane type icon
        Image(systemName: pane.type.iconName)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        
        // Title
        Text(pane.title)
            .font(Typography.paneTitle)
            .lineLimit(1)
        
        Spacer()
        
        // ... control buttons
    }
}
```

```swift
// AppCommands.swift additions

// Pane focus commands (⌘1-9)
CommandGroup(after: .toolbar) {
    ForEach(1...9, id: \.self) { index in
        Button("Focus Pane \(index)") {
            NotificationCenter.default.post(name: .focusPaneByHotkey, object: index)
        }
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
    }
}

extension Notification.Name {
    static let focusPaneByHotkey = Notification.Name("focusPaneByHotkey")
}
```

```swift
// ContentView.swift - handle focus notifications

.onReceive(NotificationCenter.default.publisher(for: .focusPaneByHotkey)) { notification in
    guard let index = notification.object as? Int else { return }
    canvasState.focusPaneByHotkey(index)
}

.onReceive(NotificationCenter.default.publisher(for: .focusPane)) { notification in
    guard let paneId = notification.object as? UUID else { return }
    // The pane's view will handle becoming first responder
    focusedPaneId = paneId
}
```

**Visual Design**:
```
┌─────────────────────────────────────────────────────────────────────────┐
│  [⌘1] [my-app]  📁  File Explorer                         [−] [□] [×]  │
├─────────────────────────────────────────────────────────────────────────┤
│   └─ src/                                                               │
│      ├─ App.tsx                                                         │
│      └─ index.ts                                                        │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  [⌘2]  📝  App.tsx                                         [−] [□] [×]  │
├─────────────────────────────────────────────────────────────────────────┤
│   1│ import React from 'react';                                         │
│   2│                                                                    │
│   3│ export function App() {                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

**Validation**:
- [ ] Panes display hotkey badge in title bar
- [ ] First 9 panes get hotkeys 1-9
- [ ] ⌘1 focuses first pane
- [ ] ⌘2-9 focus corresponding panes
- [ ] Hotkeys reassigned when panes deleted
- [ ] Focused pane receives keyboard input
- [ ] Hotkey badge styled to match theme

**Commit**: `feat(panes): add hotkey navigation with ⌘1-9`

---

## File Structure After Sprint 9

```
Devys/
├── Workspace/                    # 🆕 NEW FOLDER
│   ├── Project.swift             # S9-01
│   ├── WorkspaceState.swift      # S9-02
│   └── ProjectTabBar.swift       # S9-03
├── Panes/
│   ├── FileExplorer/             # 🆕 NEW FOLDER
│   │   ├── FileItem.swift        # S9-06
│   │   ├── FileSystemWatcher.swift  # S9-07
│   │   ├── FileExplorerController.swift  # S9-08
│   │   ├── FileExplorerPaneView.swift    # S9-09
│   │   └── FileExplorerState.swift
│   └── Core/
│       ├── Pane.swift            # S9-05, S9-13 (updated)
│       └── PaneContainerView.swift  # S9-10, S9-13 (updated)
├── Canvas/
│   └── CanvasState.swift         # S9-05, S9-13 (updated)
├── ContentView.swift             # S9-04 (updated)
└── App/
    └── AppCommands.swift         # S9-04, S9-11, S9-13 (updated)
```

---

## Definition of Done

- [ ] Native project tabs in window header
- [ ] ⌘T creates new project tab (shows folder picker)
- [ ] ⌘W closes current tab
- [ ] ⇧⌘] and ⇧⌘[ switch tabs
- [ ] Dragging folder creates new project tab
- [ ] File explorer pane shows file tree with NSOutlineView
- [ ] Files/folders expand, collapse, show icons
- [ ] Double-clicking file opens code editor pane (placeholder for now)
- [ ] Right-click context menu for New/Delete/Rename
- [ ] File changes detected and tree updates
- [ ] Panes show project indicator in title bar
- [ ] **Panes show hotkey badge [⌘1]-[⌘9] in title bar**
- [ ] **⌘1-9 focuses corresponding pane**
- [ ] **Focused pane receives keyboard input**
- [ ] Terminal panes start in project directory

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-20 | Initial sprint 9 plan created |
| 2026-01-20 | Added S9-13: Pane Hotkeys for keyboard navigation |
