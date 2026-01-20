# Devys Project Status

## Overview

Devys is a native macOS infinite canvas for orchestrating AI coding agents, terminals, browsers, and development workflows.

**Vision**: Human becomes a conductor directing AI agents rather than writing code directly.

---

## Phase 1 Progress

### Sprint Summary

| Sprint | Focus | Status | Tickets |
|--------|-------|--------|---------|
| Sprint 1 | Project Scaffold & Empty Canvas | ✅ Complete | 7/7 |
| Sprint 2 | Infinite Canvas with Dot Grid | ✅ Complete | 8/8 |
| Sprint 3 | Pane Data Model & Rendering | ✅ Complete | 8/8 |
| Sprint 4 | Pane Dragging & Resizing | ✅ Complete | 8/8 |
| Sprint 5 | Snapping & Grouping | ✅ Complete | 10/10 |
| Sprint 6 | Bezier Connectors | ⏸️ Deferred | 0/10 |
| Sprint 7 | Terminal Pane | ✅ Complete | 12/12 |
| Sprint 8 | Browser Pane | 🔄 In Progress | 9/14 |
| Sprint 9 | File Explorer & Code Editor | 🔴 Not Started | 0/12 |
| Sprint 10 | Git Pane & Persistence | 🔴 Not Started | 0/14 |

**Legend**: ✅ Complete | 🔄 In Progress | 🔴 Not Started | ⏸️ Deferred

---

## Detailed Sprint Status

### Sprint 1: Project Scaffold ✅
- [x] Xcode project with workspace + SPM structure
- [x] SwiftUI app lifecycle
- [x] Folder structure organized
- [x] XCConfig build settings
- [x] App entitlements configured

### Sprint 2: Infinite Canvas ✅
- [x] CanvasState observable
- [x] Coordinate transforms (screen ↔ canvas)
- [x] Dot grid background
- [x] Pan gesture
- [x] Zoom gesture (pinch + scroll wheel)
- [x] Zoom controls in menu
- [x] Zoom indicator overlay

### Sprint 3: Pane System ✅
- [x] Pane data model
- [x] PaneType enum with state types
- [x] Pane container view (chrome)
- [x] Render panes on canvas
- [x] Pane selection (click, ⌘-click)

### Sprint 4: Pane Interaction ✅
- [x] Pane drag gesture
- [x] Resize handles (corners + edges)
- [x] Resize gesture
- [x] Close button
- [x] Collapse toggle
- [x] Keyboard shortcuts (Delete, ⌘D)

### Sprint 5: Snapping & Grouping ✅
- [x] SnapGuide model
- [x] Snap detection engine
- [x] Visual snap guides
- [x] Apply snap on drag end
- [x] PaneGroup model
- [x] Auto-grouping on snap
- [x] Group drag (moves all)
- [x] Group/Ungroup commands (⌘G, ⇧⌘U)

### Sprint 6: Bezier Connectors ⏸️
*Deferred - visual-only connectors not essential for MVP*
- [ ] Connector model
- [ ] Connector rendering
- [ ] Connection handles
- [ ] Connector creation gesture
- [ ] Connector deletion

### Sprint 7: Terminal Pane ✅
- [x] TerminalState model (Codable, Equatable)
- [x] TerminalController (SwiftTerm integration)
- [x] TerminalPaneView (NSViewControllerRepresentable)
- [x] Wire into PaneContainerView
- [x] ⇧⌘T menu command
- [x] Terminal title tracking
- [x] Activity tracking (running state indicator)
- [x] Context menu (copy, paste, clear, etc.)
- [x] Keyboard focus handling
- [x] File drop support
- [x] Path escaping helper

### Sprint 8: Browser Pane 🔄
*Current sprint - see sprint-8-plan.md*
- [x] BrowserState model
- [x] WebViewStore observable
- [x] BrowserWebView (WKWebView wrapper)
- [x] Browser toolbar
- [x] BrowserPaneView
- [x] Wire into PaneContainerView
- [x] Loading states & errors
- [x] DevTools integration
- [x] Localhost quick access
- [ ] URL drag-drop
- [ ] Context menu
- [ ] Keyboard focus
- [ ] Unit tests

### Sprint 9: File Explorer & Code Editor 🔴
- [ ] FileItem model
- [ ] FileSystemWatcher (FSEvents)
- [ ] FileExplorerState
- [ ] FileTreeViewModel
- [ ] FileExplorerPaneView
- [ ] CodeEditorState
- [ ] CodeEditorPaneView (CodeEditSourceEditor)
- [ ] File → Editor navigation
- [ ] File drag from explorer
- [ ] Context menus

### Sprint 10: Git Pane & Persistence 🔴
- [ ] GitClient actor
- [ ] GitState and parse models
- [ ] GitViewModel
- [ ] GitPaneView
- [ ] Stage/unstage actions
- [ ] Commit functionality
- [ ] Persistence models (WorkspaceState)
- [ ] CanvasDocument (FileDocument)
- [ ] Save/load canvas
- [ ] Autosave support

---

## Current Architecture

```
Devys/
├── Devys.xcworkspace/              # Open this in Xcode
├── Devys.xcodeproj/                # Xcode project
├── Devys/                          # App target (all code lives here)
│   ├── DevysApp.swift              # Entry point
│   ├── ContentView.swift           # Root view
│   ├── App/
│   │   └── AppCommands.swift       # Menu commands
│   ├── Canvas/
│   │   ├── CanvasView.swift
│   │   ├── CanvasState.swift
│   │   ├── CanvasGridView.swift
│   │   ├── CanvasCoordinates.swift
│   │   ├── ScrollZoomModifier.swift
│   │   └── ZoomIndicator.swift
│   ├── Panes/
│   │   ├── Core/
│   │   │   ├── Pane.swift
│   │   │   ├── PaneType.swift
│   │   │   ├── PaneContainerView.swift
│   │   │   ├── DraggablePaneView.swift
│   │   │   └── PaneResizeHandles.swift
│   │   ├── Snapping/
│   │   │   ├── SnapEngine.swift
│   │   │   └── SnapGuideView.swift
│   │   ├── Terminal/
│   │   │   ├── TerminalState.swift
│   │   │   ├── TerminalController.swift
│   │   │   ├── TerminalPaneView.swift
│   │   │   └── ActivityTrackingTerminalView.swift
│   │   └── Browser/                # NEW - Sprint 8
│   │       ├── BrowserState.swift
│   │       ├── WebViewStore.swift
│   │       ├── BrowserWebView.swift
│   │       ├── BrowserToolbar.swift
│   │       └── BrowserPaneView.swift
│   ├── Shared/
│   │   ├── Theme.swift
│   │   └── CanvasEnvironment.swift
│   └── Assets.xcassets/
└── Config/
    ├── Shared.xcconfig
    ├── Debug.xcconfig
    └── Release.xcconfig
```

**Note**: Code now lives directly in `Devys/` (no more SPM package).

---

## Dependencies

| Package | Version | Purpose | Sprint |
|---------|---------|---------|--------|
| SwiftTerm | 1.2.0+ | Terminal emulation | 7 |
| CodeEditSourceEditor | 0.7.0+ | Code editing | 9 (planned) |

---

## Keyboard Shortcuts

### Canvas Navigation
| Action | Shortcut |
|--------|----------|
| Pan canvas | Drag on background |
| Zoom in/out | ⌘+ / ⌘- or pinch |
| Zoom to 100% | ⌘1 |
| Zoom to fit | ⌘0 |

### Pane Management
| Action | Shortcut |
|--------|----------|
| Select pane | Click |
| Multi-select | ⇧-click or ⌘-click |
| Delete selected | Delete or ⌫ |
| Duplicate pane | ⌘D |
| Close pane | ⌘W |

### Grouping
| Action | Shortcut |
|--------|----------|
| Group selected | ⌘G |
| Ungroup | ⇧⌘U |

### Create Panes
| Action | Shortcut |
|--------|----------|
| New Terminal | ⇧⌘T |
| New Browser | ⇧⌘B |
| New File Explorer | ⇧⌘E |
| New Code Editor | ⌥⌘N |
| New Git | ⇧⌘G |

---

## What's Working Now

1. **Infinite Canvas**: Pan and zoom with native gestures, dot grid background
2. **Pane System**: Create, move, resize, collapse panes
3. **Snapping**: Panes snap to edges, auto-group when snapped
4. **Grouping**: Move grouped panes together, group/ungroup commands
5. **Terminal Panes**: Full SwiftTerm integration with activity tracking

---

## What's Next

### Immediate (Sprint 8)
Browser panes with WKWebView for previewing localhost dev servers and web content.

### Near-term (Sprint 9-10)
- File explorer for navigating project structure
- Code editor with syntax highlighting
- Git operations (status, stage, commit)
- Canvas persistence (save/load workspaces)

### Future (Phase 2+)
- Agent panes (Claude Code, Codex integration)
- Workflow automation (agent chains)
- Prompt library
- MCP management

---

## Notes

### Design Decisions
- **Workspace + SPM**: Feature code in SPM package for faster iteration
- **@Observable**: Using Swift 5.9 Observation framework (not ObservableObject)
- **AppKit for Terminals/Browsers**: NSViewControllerRepresentable for system views
- **Auto-grouping**: Panes automatically group when snapped edge-to-edge

### Known Issues
- None currently tracked

### Technical Debt
- [ ] Connectors deferred (Sprint 6)
- [ ] Unit test coverage could be improved

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-20 | Initial project status document created |
| 2026-01-20 | Sprint 8 (Browser Pane) planning complete |
