# Sprint 11: Layouts, Persistence & Polish

## Overview

Layout templates for common IDE arrangements, workspace persistence (save/load), and polish across all pane types.

---

## Goal

Layout templates for common IDE arrangements. Full workspace persistence - save on quit, restore on launch. Recent projects menu. Keyboard navigation polish.

## Demo

Create layout → save → switch projects → apply saved layout → close app → reopen → workspace restored exactly.

---

## Progress Tracker

| Ticket | Title | Status | Commit |
|--------|-------|--------|--------|
| S11-01 | LayoutTemplate Model | ⬜ Not Started | |
| S11-02 | Built-in Layout Presets | ⬜ Not Started | |
| S11-03 | Save Current Layout | ⬜ Not Started | |
| S11-04 | Apply Layout Template | ⬜ Not Started | |
| S11-05 | Layouts UI in Tab Bar | ⬜ Not Started | |
| S11-06 | Workspace Persistence Model | ⬜ Not Started | |
| S11-07 | Auto-Save Workspace | ⬜ Not Started | |
| S11-08 | Restore Workspace on Launch | ⬜ Not Started | |
| S11-09 | Recent Projects Menu | ⬜ Not Started | |
| S11-10 | Pane Focus Management | ⬜ Not Started | |
| S11-11 | Pane Type Focus Shortcuts | ⬜ Not Started | |
| S11-12 | Unit Tests | ⬜ Not Started | |

**Legend**: ⬜ Not Started | 🔄 In Progress | ✅ Complete | ⏸️ Blocked

---

## Tickets

### S11-01: LayoutTemplate Model

**Status**: ⬜ Not Started

**Description**: Model for saveable pane layout templates.

**File**: `Devys/Workspace/LayoutTemplate.swift`

**Tasks**:
- [ ] Define `LayoutTemplate` struct
- [ ] Define `PaneTemplate` for relative pane positions
- [ ] Use normalized 0-1 coordinates for positions
- [ ] Store pane types (not actual content)
- [ ] Add Codable for persistence

**Code**:
```swift
import Foundation
import CoreGraphics

public struct LayoutTemplate: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var panes: [PaneTemplate]
    public var isBuiltIn: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        panes: [PaneTemplate],
        isBuiltIn: Bool = false
    ) { /* ... */ }
}

public struct PaneTemplate: Codable, Equatable {
    public var type: PaneTypeTemplate
    public var relativeFrame: CGRect  // 0-1 normalized coordinates
    public var zIndex: Int
}

public enum PaneTypeTemplate: String, Codable, CaseIterable {
    case fileExplorer, codeEditor, terminal, git, browser
    public var displayName: String { /* ... */ }
    public var iconName: String { /* ... */ }
}
```

**Commit**: `feat(layouts): add LayoutTemplate model`

---

### S11-02: Built-in Layout Presets

**Status**: ⬜ Not Started

**Description**: Pre-defined layout templates for common IDE arrangements.

**File**: `Devys/Workspace/LayoutPresets.swift`

**Tasks**:
- [ ] Create "Classic IDE" preset (file tree left, editor center, terminal bottom)
- [ ] Create "Side by Side" preset (two editors)
- [ ] Create "Focus Mode" preset (editor + terminal only)
- [ ] Create "Full Stack" preset (all panes)

**Commit**: `feat(layouts): add built-in layout presets`

---

### S11-03: Save Current Layout

**Status**: ⬜ Not Started

**Description**: Save current pane arrangement as a named layout template.

**File**: `Devys/Workspace/LayoutManager.swift`

**Tasks**:
- [ ] Create `LayoutManager` for saving/loading layouts
- [ ] Convert current panes to PaneTemplates
- [ ] Normalize positions to 0-1 range
- [ ] Persist to disk (Application Support)
- [ ] Handle naming and overwrite

**Commit**: `feat(layouts): add LayoutManager for save/load`

---

### S11-04: Apply Layout Template

**Status**: ⬜ Not Started

**Description**: Apply a saved layout template to the current project tab.

**File**: `Devys/Workspace/LayoutManager.swift` (extend)

**Tasks**:
- [ ] Clear current panes (with unsaved confirmation)
- [ ] Create panes from template
- [ ] Initialize panes with project context
- [ ] Recalculate hotkey indices for new panes

**Commit**: `feat(layouts): apply layout template to tab`

---

### S11-05: Layouts UI in Tab Bar

**Status**: ⬜ Not Started

**Description**: Layouts dropdown menu in the tab bar header.

**File**: `Devys/Workspace/ProjectTabBar.swift`

**Tasks**:
- [ ] Replace placeholder layouts menu
- [ ] List built-in presets with icons
- [ ] List user layouts
- [ ] "Save Current Layout..." option with name dialog
- [ ] Delete user layouts (swipe or context menu)

**Commit**: `feat(layouts): add layouts UI in tab bar`

---

### S11-06: Workspace Persistence Model

**Status**: ⬜ Not Started

**Description**: Model for persisting entire workspace state to disk.

**File**: `Devys/Persistence/WorkspaceDocument.swift`

**Tasks**:
- [ ] Create `Persistence/` folder
- [ ] Define `WorkspaceDocument` Codable struct
- [ ] Include all tabs and their panes
- [ ] Include viewport states
- [ ] Exclude transient state (terminal PTYs, web views)
- [ ] Include pane hotkey indices

**Commit**: `feat(persistence): add WorkspaceDocument model`

---

### S11-07: Auto-Save Workspace

**Status**: ⬜ Not Started

**Description**: Automatically save workspace state periodically and on quit.

**File**: `Devys/Persistence/WorkspacePersistence.swift`

**Tasks**:
- [ ] Create persistence manager
- [ ] Auto-save every 30 seconds
- [ ] Save on app terminate
- [ ] Save on significant changes (tab add/remove, pane add/remove)
- [ ] Store in Application Support

**Commit**: `feat(persistence): add auto-save`

---

### S11-08: Restore Workspace on Launch

**Status**: ⬜ Not Started

**Description**: Restore previous workspace state when app launches.

**File**: `Devys/DevysApp.swift`

**Tasks**:
- [ ] Check for saved workspace on launch
- [ ] Restore tabs and panes
- [ ] Reload file contents for editors
- [ ] Start terminals in correct directories
- [ ] Handle missing projects gracefully
- [ ] Recalculate hotkey indices

**Commit**: `feat(persistence): restore workspace on launch`

---

### S11-09: Recent Projects Menu

**Status**: ⬜ Not Started

**Description**: File menu showing recently opened projects.

**Files**: `Devys/App/AppCommands.swift`, `Devys/Persistence/RecentProjects.swift`

**Tasks**:
- [ ] Track recently opened project URLs
- [ ] Store in UserDefaults
- [ ] Add "Open Recent" submenu
- [ ] Clear recents option
- [ ] Limit to 10 recent projects
- [ ] Filter out non-existent paths

**Commit**: `feat(persistence): add recent projects menu`

---

### S11-10: Pane Focus Management

**Status**: ⬜ Not Started

**Description**: Proper keyboard focus handling across panes.

**Tasks**:
- [ ] Click pane to focus it
- [ ] Focus ring on focused pane (subtle border highlight)
- [ ] Terminal receives keyboard when focused
- [ ] Editor receives keyboard when focused
- [ ] File explorer receives keyboard for arrow navigation

**Note**: ⌘1-9 pane focusing is implemented in S9-13.

**Commit**: `feat(panes): add focus management`

---

### S11-11: Pane Type Focus Shortcuts

**Status**: ⬜ Not Started

**Description**: Additional keyboard shortcuts to focus specific pane types.

**File**: `Devys/App/AppCommands.swift`

**Tasks**:
- [ ] ⌘⇧E to focus first file explorer pane
- [ ] ⌘⇧X to focus first terminal pane
- [ ] ⌘⇧G to focus first git pane
- [ ] ⌘⇧B to focus first browser pane
- [ ] If multiple of same type, cycle through them

**Code**:
```swift
CommandGroup(after: .windowList) {
    Button("Focus File Explorer") {
        NotificationCenter.default.post(name: .focusPaneType, object: PaneTypeTemplate.fileExplorer)
    }
    .keyboardShortcut("e", modifiers: [.command, .shift])
    
    Button("Focus Terminal") {
        NotificationCenter.default.post(name: .focusPaneType, object: PaneTypeTemplate.terminal)
    }
    .keyboardShortcut("x", modifiers: [.command, .shift])
    
    Button("Focus Git") {
        NotificationCenter.default.post(name: .focusPaneType, object: PaneTypeTemplate.git)
    }
    .keyboardShortcut("g", modifiers: [.command, .shift])
    
    Button("Focus Browser") {
        NotificationCenter.default.post(name: .focusPaneType, object: PaneTypeTemplate.browser)
    }
    .keyboardShortcut("b", modifiers: [.command, .shift])
}
```

**Commit**: `feat(navigation): add pane type focus shortcuts`

---

### S11-12: Unit Tests

**Status**: ⬜ Not Started

**Description**: Unit tests for new functionality.

**Tasks**:
- [ ] Project model tests
- [ ] WorkspaceState tests
- [ ] LayoutTemplate tests
- [ ] FileItem tests
- [ ] GitClient mock tests
- [ ] CodeEditorState tests
- [ ] Persistence tests
- [ ] Hotkey index calculation tests

**Commit**: `test: add unit tests for sprints 9-11`

---

## File Structure After Sprint 11

```
Devys/
├── Workspace/
│   ├── LayoutTemplate.swift      # S11-01
│   ├── LayoutPresets.swift       # S11-02
│   ├── LayoutManager.swift       # S11-03, S11-04
│   └── ProjectTabBar.swift       # S11-05 (updated)
├── Persistence/                  # 🆕 NEW FOLDER
│   ├── WorkspaceDocument.swift   # S11-06
│   ├── WorkspacePersistence.swift # S11-07, S11-08
│   └── RecentProjects.swift      # S11-09
└── Tests/
    └── DevysTests/
        ├── ProjectTests.swift
        ├── LayoutTests.swift
        └── PersistenceTests.swift
```

---

## Definition of Done

- [ ] Built-in layout presets available
- [ ] Can save current layout with name
- [ ] Can apply layout from menu
- [ ] Workspace auto-saves periodically
- [ ] Workspace restored on launch
- [ ] Recent projects menu works
- [ ] Keyboard focus management works
- [ ] ⌘⇧E/X/G/B shortcuts work
- [ ] Unit tests pass

---

## Full Feature Completion Summary

After Sprints 9-11, Devys will have:

| Feature | Status |
|---------|--------|
| Infinite canvas with pan/zoom | ✅ Complete |
| Pane system with drag/resize/snap | ✅ Complete |
| Terminal panes (SwiftTerm) | ✅ Complete |
| Browser panes (WKWebView) | ✅ Complete |
| **Project tabs (native macOS)** | 🆕 Sprint 9 |
| **File explorer (NSOutlineView)** | 🆕 Sprint 9 |
| **Pane hotkeys (⌘1-9)** | 🆕 Sprint 9 |
| **Code editor (CodeEditSourceEditor)** | 🆕 Sprint 10 |
| **Git pane (status, stage, commit)** | 🆕 Sprint 10 |
| **Layout templates** | 🆕 Sprint 11 |
| **Workspace persistence** | 🆕 Sprint 11 |
| **Recent projects** | 🆕 Sprint 11 |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| SwiftTerm | 1.2.0+ | Terminal emulation |
| CodeEditSourceEditor | 0.7.0+ | Code editor with syntax highlighting |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-20 | Sprint 11 split from combined plan |
