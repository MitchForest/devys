# Phase 1: Atomic Tickets

## Overview

- **Sprints**: 10 sprints
- **Ticket format**: `S{sprint}-{number}` (e.g., S1-01)
- **Each sprint**: Results in demoable, runnable software
- **Each ticket**: Atomic, commitable, testable

---

# Sprint 1: Project Scaffold & Empty Canvas

**Goal**: Runnable macOS app with an empty window and basic app structure.

**Demo**: Launch app → see empty window with menu bar → quit app.

---

### S1-01: Initialize Xcode Project

**Description**: Create new macOS App project with SwiftUI lifecycle.

**Tasks**:
1. Create Xcode project named "Devys"
2. Set deployment target to macOS 14.0+
3. Select SwiftUI App lifecycle
4. Set bundle identifier: `com.devys.app`
5. Enable Hardened Runtime
6. Create initial folder structure:
   ```
   Devys/
   ├── App/
   ├── Canvas/
   ├── Panes/
   ├── Shared/
   └── Resources/
   ```

**Validation**:
- [ ] Project builds without errors
- [ ] App launches and displays default "Hello, World!" view
- [ ] App quits cleanly via ⌘Q

**Commit**: `chore: initialize Xcode project with folder structure`

---

### S1-02: Configure Swift Package Dependencies

**Description**: Add external package dependencies to the project.

**Tasks**:
1. Add SwiftTerm package: `https://github.com/migueldeicaza/SwiftTerm.git` (1.2.0+)
2. Add CodeEditSourceEditor: `https://github.com/CodeEditApp/CodeEditSourceEditor.git` (0.7.0+)
3. Verify packages resolve and build

**Validation**:
- [ ] `import SwiftTerm` compiles without error
- [ ] `import CodeEditSourceEditor` compiles without error
- [ ] Project builds successfully

**Commit**: `chore: add SwiftTerm and CodeEditSourceEditor dependencies`

---

### S1-03: Create App Entry Point

**Description**: Set up main app entry point with WindowGroup.

**Tasks**:
1. Create `App/DevysApp.swift`:
   ```swift
   @main
   struct DevysApp: App {
       var body: some Scene {
           WindowGroup {
               ContentView()
           }
           .windowStyle(.automatic)
           .windowResizability(.contentSize)
       }
   }
   ```
2. Create placeholder `ContentView.swift`
3. Set minimum window size to 800x600

**Validation**:
- [ ] App launches with single window
- [ ] Window respects minimum size constraints
- [ ] Window title shows "Devys"

**Commit**: `feat: create app entry point with window configuration`

---

### S1-04: Define Color Theme Constants

**Description**: Create centralized theme definitions for consistent styling.

**Tasks**:
1. Create `Shared/Theme.swift`
2. Define color constants:
   ```swift
   enum Theme {
       static let canvasBackground = Color(nsColor: .windowBackgroundColor)
       static let dotColor = Color.gray.opacity(0.3)
       static let paneBackground = Color(nsColor: .controlBackgroundColor)
       static let paneBorder = Color.gray.opacity(0.3)
       static let paneBorderSelected = Color.accentColor
       static let connectorColor = Color.blue
   }
   ```
3. Define size constants:
   ```swift
   enum Layout {
       static let dotSpacing: CGFloat = 20
       static let dotRadius: CGFloat = 1.5
       static let paneTitleBarHeight: CGFloat = 30
       static let paneCornerRadius: CGFloat = 8
       static let snapThreshold: CGFloat = 8
   }
   ```

**Validation**:
- [ ] Theme constants accessible from any view
- [ ] No hardcoded colors in other files (after this ticket)

**Commit**: `feat: add centralized theme and layout constants`

---

### S1-05: Create Empty Canvas View

**Description**: Create the main canvas view that will host all content.

**Tasks**:
1. Create `Canvas/CanvasView.swift`
2. Implement basic structure:
   ```swift
   struct CanvasView: View {
       var body: some View {
           GeometryReader { geometry in
               ZStack {
                   Theme.canvasBackground
                       .ignoresSafeArea()
               }
           }
       }
   }
   ```
3. Update `ContentView` to use `CanvasView`

**Validation**:
- [ ] Canvas fills entire window
- [ ] Background color matches theme
- [ ] Window resizing works correctly

**Commit**: `feat: create empty canvas view`

---

### S1-06: Add Basic Menu Bar Commands

**Description**: Set up menu bar with placeholder commands.

**Tasks**:
1. Create `App/AppCommands.swift`
2. Add File menu items (New Canvas, Open, Save)
3. Add View menu items (Zoom In, Zoom Out, Zoom to Fit)
4. Add Pane menu items (New Terminal, New Browser, etc.)
5. Wire up to DevysApp:
   ```swift
   .commands {
       AppCommands()
   }
   ```

**Validation**:
- [ ] Menu bar shows all custom menus
- [ ] Menu items display correct keyboard shortcuts
- [ ] Menu items are clickable (no action yet)

**Commit**: `feat: add menu bar command structure`

---

### S1-07: Write Unit Tests for Theme Constants

**Description**: Add unit tests to validate theme configuration.

**Tasks**:
1. Create `DevysTests/ThemeTests.swift`
2. Test that all colors are non-nil
3. Test that layout constants are positive values
4. Test that snap threshold is reasonable (> 0, < 50)

**Validation**:
- [ ] All tests pass
- [ ] Test coverage for Theme.swift

**Commit**: `test: add unit tests for theme constants`

---

**Sprint 1 Deliverable**: Launchable app with empty canvas window and menu structure.

---

# Sprint 2: Infinite Canvas with Dot Grid

**Goal**: Pannable, zoomable canvas with dot grid background.

**Demo**: Launch app → pan canvas by dragging → zoom with pinch/scroll → see dots move accordingly.

---

### S2-01: Create CanvasState Observable

**Description**: Create the central state object for canvas.

**Tasks**:
1. Create `Canvas/CanvasState.swift`
2. Implement:
   ```swift
   @MainActor
   final class CanvasState: ObservableObject {
       @Published var offset: CGPoint = .zero
       @Published var scale: CGFloat = 1.0
       
       static let minScale: CGFloat = 0.1
       static let maxScale: CGFloat = 4.0
   }
   ```
3. Inject into environment from DevysApp

**Validation**:
- [ ] CanvasState is accessible via @EnvironmentObject
- [ ] Published properties trigger view updates

**Commit**: `feat: create CanvasState observable object`

---

### S2-02: Implement Coordinate Transform Functions

**Description**: Add functions to convert between screen and canvas coordinates.

**Tasks**:
1. Create `Canvas/CanvasCoordinates.swift`
2. Add extension to CanvasState:
   ```swift
   extension CanvasState {
       func canvasPoint(from screenPoint: CGPoint, viewportSize: CGSize) -> CGPoint
       func screenPoint(from canvasPoint: CGPoint, viewportSize: CGSize) -> CGPoint
       func visibleRect(viewportSize: CGSize) -> CGRect
   }
   ```
3. Handle centered viewport (0,0 at center of screen)

**Validation**:
- [ ] Round-trip conversion: screen → canvas → screen returns original point
- [ ] visibleRect correctly bounds visible area at different scales
- [ ] Unit tests pass for edge cases (scale=0.1, scale=4.0)

**Commit**: `feat: implement coordinate transform functions`

---

### S2-03: Write Coordinate Transform Unit Tests

**Description**: Comprehensive tests for coordinate math.

**Tasks**:
1. Create `DevysTests/CanvasCoordinatesTests.swift`
2. Test cases:
   - Identity transform (offset=0, scale=1)
   - Panned canvas (offset != 0)
   - Zoomed canvas (scale != 1)
   - Combined pan + zoom
   - Round-trip accuracy
   - Visible rect at various scales

**Validation**:
- [ ] All tests pass
- [ ] Edge cases covered (min/max scale)

**Commit**: `test: add coordinate transform unit tests`

---

### S2-04: Implement Dot Grid Background

**Description**: Render dot grid that responds to pan/zoom.

**Tasks**:
1. Create `Canvas/CanvasGridView.swift`
2. Use SwiftUI Canvas for efficient rendering:
   ```swift
   struct CanvasGridView: View {
       let offset: CGPoint
       let scale: CGFloat
       
       var body: some View {
           Canvas { context, size in
               // Calculate visible grid bounds
               // Render dots at correct positions
           }
           .drawingGroup()
       }
   }
   ```
3. Skip rendering if scale < 0.15 (dots too small)
4. Add to CanvasView

**Validation**:
- [ ] Dots visible at default zoom
- [ ] Dots follow pan movement correctly
- [ ] Dots scale with zoom
- [ ] No dots rendered when zoomed out far
- [ ] Performance: 60fps during pan/zoom

**Commit**: `feat: implement dot grid background`

---

### S2-05: Implement Pan Gesture

**Description**: Add drag gesture to pan the canvas.

**Tasks**:
1. Create `Canvas/CanvasGestures.swift`
2. Implement pan gesture:
   ```swift
   var panGesture: some Gesture {
       DragGesture(minimumDistance: 1)
           .onChanged { value in
               // Update offset based on translation
           }
   }
   ```
3. Apply to CanvasView
4. Ensure gesture doesn't conflict with future pane dragging

**Validation**:
- [ ] Dragging moves canvas in correct direction
- [ ] Pan is smooth (no jitter)
- [ ] Release stops panning (no momentum for now)
- [ ] Works with trackpad and mouse

**Commit**: `feat: implement canvas pan gesture`

---

### S2-06: Implement Zoom Gesture

**Description**: Add pinch/scroll gesture to zoom canvas.

**Tasks**:
1. Add zoom gesture to CanvasGestures:
   ```swift
   var zoomGesture: some Gesture {
       MagnificationGesture()
           .onChanged { value in
               // Update scale, clamped to min/max
           }
   }
   ```
2. Add scroll wheel zoom support via NSEvent monitoring
3. Zoom towards cursor position (not center)

**Validation**:
- [ ] Pinch gesture zooms in/out
- [ ] Scroll wheel zooms (with ⌘ or ⌥ modifier)
- [ ] Zoom is clamped to min/max
- [ ] Zoom centers on cursor position
- [ ] Dots scale correctly during zoom

**Commit**: `feat: implement canvas zoom gesture`

---

### S2-07: Add Zoom Controls to Menu

**Description**: Wire up View menu zoom commands.

**Tasks**:
1. Add actions to AppCommands:
   - Zoom In (⌘+): scale *= 1.25
   - Zoom Out (⌘-): scale /= 1.25
   - Zoom to Fit (⌘0): reset to scale=1, offset=0
   - Zoom to 100% (⌘1): scale=1, keep offset
2. Pass canvasState to AppCommands

**Validation**:
- [ ] ⌘+ zooms in
- [ ] ⌘- zooms out
- [ ] ⌘0 resets view
- [ ] Menu items update canvas correctly

**Commit**: `feat: wire up zoom menu commands`

---

### S2-08: Add Zoom Level Indicator

**Description**: Display current zoom level in UI.

**Tasks**:
1. Create `Canvas/ZoomIndicator.swift`
2. Show percentage in bottom-right corner:
   ```swift
   Text("\(Int(scale * 100))%")
       .font(.caption)
       .padding(4)
       .background(.ultraThinMaterial)
   ```
3. Fade out after 1.5s of no zoom changes

**Validation**:
- [ ] Indicator shows correct percentage
- [ ] Indicator appears during zoom
- [ ] Indicator fades after inactivity
- [ ] Clicking indicator resets to 100%

**Commit**: `feat: add zoom level indicator`

---

**Sprint 2 Deliverable**: Infinite canvas with dot grid, pan, and zoom functionality.

---

# Sprint 3: Pane Data Model & Basic Rendering

**Goal**: Render static panes on canvas that move with pan/zoom.

**Demo**: Launch app → see test panes on canvas → pan/zoom → panes move/scale correctly.

---

### S3-01: Define Pane Data Model

**Description**: Create the core Pane struct.

**Tasks**:
1. Create `Panes/Core/Pane.swift`
2. Implement:
   ```swift
   struct Pane: Identifiable, Equatable {
       let id: UUID
       var type: PaneType
       var frame: CGRect        // Canvas coordinates
       var zIndex: Int
       var groupId: UUID?
       var title: String
       var isCollapsed: Bool
   }
   ```
3. Add computed properties for handle positions

**Validation**:
- [ ] Pane is Identifiable
- [ ] Pane is Equatable
- [ ] Handle positions computed correctly

**Commit**: `feat: define Pane data model`

---

### S3-02: Define PaneType Enum

**Description**: Create enum for different pane types.

**Tasks**:
1. Create `Panes/Core/PaneType.swift`
2. Implement:
   ```swift
   enum PaneType: Equatable {
       case terminal(TerminalState)
       case browser(BrowserState)
       case fileExplorer(FileExplorerState)
       case codeEditor(CodeEditorState)
       case git(GitState)
   }
   ```
3. Create placeholder state structs (empty for now)

**Validation**:
- [ ] All pane types compile
- [ ] PaneType is Equatable

**Commit**: `feat: define PaneType enum with placeholder states`

---

### S3-03: Add Panes Array to CanvasState

**Description**: Store panes in canvas state.

**Tasks**:
1. Add to CanvasState:
   ```swift
   @Published var panes: [Pane] = []
   @Published var selectedPaneIds: Set<UUID> = []
   @Published var hoveredPaneId: UUID?
   ```
2. Add helper methods:
   ```swift
   func pane(withId id: UUID) -> Pane?
   func paneIndex(withId id: UUID) -> Int?
   ```

**Validation**:
- [ ] Panes array is observable
- [ ] Helper methods return correct values
- [ ] Unit tests pass

**Commit**: `feat: add panes storage to CanvasState`

---

### S3-04: Create Pane Container View (Chrome)

**Description**: Create the visual wrapper for all panes.

**Tasks**:
1. Create `Panes/Core/PaneContainerView.swift`
2. Implement title bar with:
   - Pane type icon
   - Title text
   - Collapse button
   - Close button
3. Implement content area (placeholder for now)
4. Add border styling (different when selected)

**Validation**:
- [ ] Title bar renders correctly
- [ ] Buttons are visible and styled
- [ ] Selected state shows accent border
- [ ] Collapsed state hides content

**Commit**: `feat: create pane container view with chrome`

---

### S3-05: Render Panes on Canvas

**Description**: Display panes at correct positions on canvas.

**Tasks**:
1. Update CanvasView to render panes:
   ```swift
   ForEach(canvas.panes) { pane in
       PaneContainerView(pane: pane)
           .frame(width: pane.frame.width * canvas.scale,
                  height: pane.frame.height * canvas.scale)
           .position(canvas.screenPoint(from: pane.frame.center))
   }
   ```
2. Only render visible panes (optimization)
3. Sort by zIndex

**Validation**:
- [ ] Panes appear at correct positions
- [ ] Panes scale with zoom
- [ ] Panes move with pan
- [ ] Higher zIndex panes appear on top

**Commit**: `feat: render panes on canvas`

---

### S3-06: Add Test Panes for Development

**Description**: Create debug helper to spawn test panes.

**Tasks**:
1. Create `Shared/DebugHelpers.swift`
2. Add function to create test panes:
   ```swift
   #if DEBUG
   extension CanvasState {
       func addTestPanes() {
           // Add 3-4 test panes at various positions
       }
   }
   #endif
   ```
3. Call on app launch in debug mode

**Validation**:
- [ ] Test panes appear on launch (debug only)
- [ ] Panes at different positions
- [ ] Different pane types represented

**Commit**: `feat: add debug helper for test panes`

---

### S3-07: Implement Pane Selection

**Description**: Click pane to select it.

**Tasks**:
1. Add tap gesture to PaneContainerView
2. Update selectedPaneIds on tap
3. ⌘+click for multi-select
4. Click canvas background to deselect all

**Validation**:
- [ ] Single click selects pane
- [ ] ⌘+click adds to selection
- [ ] Click elsewhere deselects
- [ ] Selected panes show accent border

**Commit**: `feat: implement pane selection`

---

### S3-08: Write Pane Model Unit Tests

**Description**: Test Pane and PaneType.

**Tasks**:
1. Create `DevysTests/PaneTests.swift`
2. Test Pane creation
3. Test Equatable conformance
4. Test handle position calculations
5. Test PaneType variants

**Validation**:
- [ ] All tests pass
- [ ] Edge cases covered

**Commit**: `test: add pane model unit tests`

---

**Sprint 3 Deliverable**: Canvas with visible static panes that transform correctly.

---

# Sprint 4: Pane Dragging & Resizing

**Goal**: Drag panes to move them, resize via handles.

**Demo**: Drag pane title bar → pane moves → drag corner → pane resizes.

---

### S4-01: Implement Pane Drag Gesture

**Description**: Drag title bar to move pane.

**Tasks**:
1. Add drag gesture to title bar in PaneContainerView
2. Track drag offset during gesture
3. On drag end, update pane.frame.origin in CanvasState
4. Bring pane to front on drag start

**Validation**:
- [ ] Dragging title bar moves pane
- [ ] Pane position persists after drag
- [ ] Dragged pane comes to front
- [ ] Canvas pan doesn't interfere

**Commit**: `feat: implement pane drag gesture`

---

### S4-02: Add movePaneBy Action to CanvasState

**Description**: Create action to move pane by delta.

**Tasks**:
1. Add to CanvasState:
   ```swift
   func movePaneBy(_ id: UUID, delta: CGSize) {
       guard let index = paneIndex(withId: id) else { return }
       panes[index].frame.origin.x += delta.width
       panes[index].frame.origin.y += delta.height
   }
   ```
2. Add `movePaneTo(_ id: UUID, position: CGPoint)`
3. Add `bringToFront(_ id: UUID)`

**Validation**:
- [ ] movePaneBy updates position correctly
- [ ] bringToFront updates zIndex
- [ ] Unit tests pass

**Commit**: `feat: add pane movement actions to CanvasState`

---

### S4-03: Create Resize Handles

**Description**: Add resize handles to pane corners/edges.

**Tasks**:
1. Create `Panes/Core/ResizeHandles.swift`
2. Add handles at:
   - 4 corners (resize both dimensions)
   - 4 edges (resize one dimension)
3. Show handles only when pane is selected or hovered
4. Use appropriate cursors for each handle

**Validation**:
- [ ] Handles visible on hover/selection
- [ ] Correct cursor for each handle type
- [ ] Handles positioned correctly at all zoom levels

**Commit**: `feat: create pane resize handles`

---

### S4-04: Implement Resize Gesture

**Description**: Drag resize handles to resize pane.

**Tasks**:
1. Add drag gesture to each handle type
2. Calculate new frame based on which handle is dragged
3. Enforce minimum size (200x100)
4. Update pane.frame in CanvasState on drag end

**Validation**:
- [ ] Corner drag resizes both dimensions
- [ ] Edge drag resizes one dimension
- [ ] Minimum size enforced
- [ ] Resize works at all zoom levels

**Commit**: `feat: implement pane resize gesture`

---

### S4-05: Add resizePane Action to CanvasState

**Description**: Create action to resize pane.

**Tasks**:
1. Add to CanvasState:
   ```swift
   func resizePane(_ id: UUID, newFrame: CGRect) {
       guard let index = paneIndex(withId: id) else { return }
       var frame = newFrame
       frame.size.width = max(200, frame.size.width)
       frame.size.height = max(100, frame.size.height)
       panes[index].frame = frame
   }
   ```

**Validation**:
- [ ] Resize updates frame correctly
- [ ] Minimum size enforced
- [ ] Unit tests pass

**Commit**: `feat: add pane resize action to CanvasState`

---

### S4-06: Implement Pane Close Button

**Description**: Close button removes pane from canvas.

**Tasks**:
1. Add deletePane action to CanvasState
2. Wire up close button in PaneContainerView
3. Add confirmation for unsaved changes (future)
4. Remove from selection if selected

**Validation**:
- [ ] Close button removes pane
- [ ] Pane disappears from canvas
- [ ] Selection updated correctly

**Commit**: `feat: implement pane close button`

---

### S4-07: Implement Pane Collapse Toggle

**Description**: Collapse button hides pane content.

**Tasks**:
1. Add toggleCollapse action to CanvasState
2. Collapsed state shows only title bar
3. Animate collapse/expand transition

**Validation**:
- [ ] Collapse hides content
- [ ] Expand shows content
- [ ] Transition is smooth
- [ ] Collapsed pane still draggable

**Commit**: `feat: implement pane collapse toggle`

---

### S4-08: Add Keyboard Shortcuts for Pane Actions

**Description**: Keyboard shortcuts for common pane operations.

**Tasks**:
1. Delete/Backspace: Delete selected panes
2. ⌘D: Duplicate selected pane
3. ⌘↵: Toggle fullscreen for selected pane (future)
4. Implement in AppCommands

**Validation**:
- [ ] Backspace deletes selected panes
- [ ] ⌘D duplicates pane (offset by 20,20)
- [ ] Shortcuts work when canvas is focused

**Commit**: `feat: add keyboard shortcuts for pane actions`

---

**Sprint 4 Deliverable**: Fully interactive panes with drag, resize, close, and collapse.

---

# Sprint 5: Snapping & Grouping

**Goal**: Panes snap to each other, can be grouped together.

**Demo**: Drag pane near another → see snap guides → release to snap → select two panes → group them.

---

### S5-01: Define SnapGuide Model

**Description**: Model for visual snap guides.

**Tasks**:
1. Create `DragDrop/SnapGuide.swift`
2. Implement:
   ```swift
   struct SnapGuide: Identifiable {
       let id = UUID()
       var orientation: Orientation // horizontal, vertical
       var position: CGFloat
       var start: CGFloat
       var end: CGFloat
   }
   ```

**Validation**:
- [ ] SnapGuide is Identifiable
- [ ] Can represent horizontal and vertical guides

**Commit**: `feat: define SnapGuide model`

---

### S5-02: Implement Snap Detection

**Description**: Detect when pane edges are near other panes.

**Tasks**:
1. Create `DragDrop/SnapEngine.swift`
2. Add to CanvasState:
   ```swift
   @Published var snapGuides: [SnapGuide] = []
   
   func updateSnapGuides(for pane: Pane, offset: CGSize)
   func clearSnapGuides()
   func snapPosition(for pane: Pane, offset: CGSize) -> CGPoint?
   ```
3. Detect snaps for:
   - Left edge to left/right edges
   - Right edge to left/right edges
   - Top edge to top/bottom edges
   - Bottom edge to top/bottom edges

**Validation**:
- [ ] Snap detected within threshold (8px)
- [ ] Multiple snap guides can exist
- [ ] Unit tests pass for various arrangements

**Commit**: `feat: implement snap detection engine`

---

### S5-03: Render Snap Guides

**Description**: Draw visual snap guides during drag.

**Tasks**:
1. Create `DragDrop/SnapGuidesOverlay.swift`
2. Render guides as thin colored lines
3. Add to CanvasView above panes

**Validation**:
- [ ] Guides appear during drag
- [ ] Guides are correctly positioned
- [ ] Guides disappear on drag end

**Commit**: `feat: render snap guides overlay`

---

### S5-04: Apply Snap on Drag End

**Description**: Snap pane to guide position when released.

**Tasks**:
1. Modify drag end handler in PaneContainerView
2. If snap available, use snapped position instead of raw position
3. Clear snap guides after applying

**Validation**:
- [ ] Pane snaps to nearby edge
- [ ] Snap feels responsive and natural
- [ ] No snap if beyond threshold

**Commit**: `feat: apply snap on pane drag end`

---

### S5-05: Define PaneGroup Model

**Description**: Model for grouped panes.

**Tasks**:
1. Create `Panes/Core/PaneGroup.swift`
2. Implement:
   ```swift
   struct PaneGroup: Identifiable {
       let id: UUID
       var paneIds: [UUID]
       var name: String
       var color: Color
       
       func boundingBox(in panes: [Pane]) -> CGRect
   }
   ```

**Validation**:
- [ ] PaneGroup is Identifiable
- [ ] Bounding box computed correctly

**Commit**: `feat: define PaneGroup model`

---

### S5-06: Add Groups to CanvasState

**Description**: Store groups in canvas state.

**Tasks**:
1. Add to CanvasState:
   ```swift
   @Published var groups: [PaneGroup] = []
   
   func groupSelectedPanes()
   func ungroupPane(_ paneId: UUID)
   func dissolveGroup(_ groupId: UUID)
   ```
2. Update pane.groupId when grouping

**Validation**:
- [ ] Groups stored correctly
- [ ] Panes reference their group
- [ ] Unit tests pass

**Commit**: `feat: add groups storage to CanvasState`

---

### S5-07: Render Group Backgrounds

**Description**: Draw visual container around grouped panes.

**Tasks**:
1. Create `Panes/Core/GroupBackgroundView.swift`
2. Draw rounded rect around group bounding box
3. Show group name label
4. Add to CanvasView behind panes

**Validation**:
- [ ] Group background visible
- [ ] Background updates when panes move
- [ ] Group name visible

**Commit**: `feat: render group backgrounds`

---

### S5-08: Implement Group Dragging

**Description**: Drag one grouped pane to move all.

**Tasks**:
1. Modify drag handler in PaneContainerView
2. If dragged pane is in group, move all group panes
3. Maintain relative positions

**Validation**:
- [ ] Dragging one moves all grouped panes
- [ ] Relative positions preserved
- [ ] Snap detection works for groups

**Commit**: `feat: implement grouped pane dragging`

---

### S5-09: Add Group/Ungroup Menu Commands

**Description**: Menu commands for grouping.

**Tasks**:
1. Add to AppCommands:
   - Group Selected (⌘G)
   - Ungroup (⌘⇧G)
2. Enable only when appropriate selection exists

**Validation**:
- [ ] ⌘G groups selected panes
- [ ] ⌘⇧G ungroups selected pane
- [ ] Menu items disabled when not applicable

**Commit**: `feat: add group/ungroup menu commands`

---

### S5-10: Write Snap Engine Unit Tests

**Description**: Comprehensive tests for snapping.

**Tasks**:
1. Create `DevysTests/SnapEngineTests.swift`
2. Test horizontal snaps
3. Test vertical snaps
4. Test snap threshold boundary
5. Test multiple snap candidates

**Validation**:
- [ ] All tests pass
- [ ] Edge cases covered

**Commit**: `test: add snap engine unit tests`

---

**Sprint 5 Deliverable**: Panes snap to each other and can be grouped/ungrouped.

---

# Sprint 6: Bezier Connectors

**Goal**: Draw bezier curve connectors between panes.

**Demo**: Drag from pane handle → see connector preview → drop on another pane → connector created.

---

### S6-01: Define Connector Model

**Description**: Model for pane-to-pane connections.

**Tasks**:
1. Create `Connectors/Connector.swift`
2. Implement:
   ```swift
   struct Connector: Identifiable {
       let id: UUID
       var sourceId: UUID
       var targetId: UUID
       var sourceHandle: HandlePosition
       var targetHandle: HandlePosition
       var label: String?
       var color: Color
   }
   
   enum HandlePosition: Codable {
       case top, bottom, left, right
   }
   ```

**Validation**:
- [ ] Connector is Identifiable
- [ ] All handle positions represented

**Commit**: `feat: define Connector model`

---

### S6-02: Add Connectors to CanvasState

**Description**: Store connectors in canvas state.

**Tasks**:
1. Add to CanvasState:
   ```swift
   @Published var connectors: [Connector] = []
   
   func addConnector(from: UUID, to: UUID, sourceHandle: HandlePosition, targetHandle: HandlePosition)
   func deleteConnector(_ id: UUID)
   func connectorsFor(pane: UUID) -> [Connector]
   ```

**Validation**:
- [ ] Connectors stored correctly
- [ ] Helper methods work
- [ ] Unit tests pass

**Commit**: `feat: add connectors storage to CanvasState`

---

### S6-03: Render Bezier Connector

**Description**: Draw curved line between panes.

**Tasks**:
1. Create `Connectors/ConnectorView.swift`
2. Implement bezier curve:
   - Start at source handle
   - End at target handle
   - Control points offset horizontally
3. Draw arrow head at target
4. Use connector color

**Validation**:
- [ ] Curve renders between panes
- [ ] Arrow head visible at target
- [ ] Curve updates when panes move

**Commit**: `feat: render bezier connector view`

---

### S6-04: Create Connector Layer

**Description**: Canvas layer for all connectors.

**Tasks**:
1. Create `Connectors/ConnectorLayer.swift`
2. Render all connectors below panes
3. Add to CanvasView

**Validation**:
- [ ] All connectors rendered
- [ ] Connectors appear below panes
- [ ] Performance acceptable with many connectors

**Commit**: `feat: create connector layer`

---

### S6-05: Add Connection Handles to Panes

**Description**: Visual handles for creating connections.

**Tasks**:
1. Create `Connectors/ConnectionHandle.swift`
2. Add small circles at pane edges:
   - Left edge (input)
   - Right edge (output)
3. Show on hover/selection
4. Different color for input vs output

**Validation**:
- [ ] Handles visible on hover
- [ ] Positioned correctly at all zoom levels
- [ ] Visual distinction between input/output

**Commit**: `feat: add connection handles to panes`

---

### S6-06: Implement Connector Creation Gesture

**Description**: Drag from handle to create connector.

**Tasks**:
1. Add drag gesture to connection handles
2. Track pending connector state in CanvasState:
   ```swift
   @Published var isDrawingConnector: Bool = false
   @Published var pendingConnectorSource: (UUID, HandlePosition)?
   @Published var pendingConnectorEndpoint: CGPoint?
   ```
3. On drag start, set source
4. On drag, update endpoint
5. On drop over valid target, create connector

**Validation**:
- [ ] Dragging from handle starts connector
- [ ] Preview line follows cursor
- [ ] Dropping on valid handle creates connector
- [ ] Dropping elsewhere cancels

**Commit**: `feat: implement connector creation gesture`

---

### S6-07: Render Pending Connector Preview

**Description**: Show preview line while creating connector.

**Tasks**:
1. Create `Connectors/PendingConnectorView.swift`
2. Draw dashed bezier from source to cursor
3. Add to CanvasView when isDrawingConnector

**Validation**:
- [ ] Preview visible during drag
- [ ] Follows cursor smoothly
- [ ] Disappears on cancel/complete

**Commit**: `feat: render pending connector preview`

---

### S6-08: Implement Connector Deletion

**Description**: Delete connectors.

**Tasks**:
1. Click connector to select it
2. Backspace/Delete to remove
3. Add right-click context menu with Delete option
4. Auto-delete when connected pane is deleted

**Validation**:
- [ ] Connectors selectable
- [ ] Delete key removes selected connector
- [ ] Context menu works
- [ ] Deleting pane removes its connectors

**Commit**: `feat: implement connector deletion`

---

### S6-09: Add Connector Label Support

**Description**: Optional label on connectors.

**Tasks**:
1. Add label rendering to ConnectorView
2. Position at midpoint of curve
3. Background pill for readability
4. Double-click to edit label

**Validation**:
- [ ] Label renders at curve midpoint
- [ ] Label is readable
- [ ] Double-click enables editing

**Commit**: `feat: add connector label support`

---

### S6-10: Write Connector Unit Tests

**Description**: Tests for connector logic.

**Tasks**:
1. Create `DevysTests/ConnectorTests.swift`
2. Test connector creation
3. Test deletion cascades
4. Test bezier control point calculation

**Validation**:
- [ ] All tests pass

**Commit**: `test: add connector unit tests`

---

**Sprint 6 Deliverable**: Panes connectable with bezier curves, visual connection handles.

---

# Sprint 7: Terminal Pane

**Goal**: Functional terminal pane using SwiftTerm.

**Demo**: Create terminal pane → see shell prompt → type commands → see output.

---

### S7-01: Define TerminalState

**Description**: State model for terminal pane.

**Tasks**:
1. Create `Panes/Terminal/TerminalState.swift`
2. Implement:
   ```swift
   struct TerminalState: Equatable {
       var cwd: URL
       var shell: String = "/bin/zsh"
       var title: String = "Terminal"
       var scrollback: Int = 10000
   }
   ```

**Validation**:
- [ ] TerminalState is Equatable
- [ ] Default values sensible

**Commit**: `feat: define TerminalState model`

---

### S7-02: Create TerminalController (AppKit)

**Description**: NSViewController wrapping SwiftTerm.

**Tasks**:
1. Create `Panes/Terminal/TerminalController.swift`
2. Initialize LocalProcessTerminalView
3. Start shell process with environment
4. Set initial working directory
5. Implement delegate methods

**Validation**:
- [ ] Controller initializes without crash
- [ ] Shell process starts
- [ ] Terminal renders prompt

**Commit**: `feat: create TerminalController with SwiftTerm`

---

### S7-03: Create TerminalPaneView (SwiftUI Wrapper)

**Description**: SwiftUI wrapper for TerminalController.

**Tasks**:
1. Create `Panes/Terminal/TerminalPaneView.swift`
2. Implement NSViewControllerRepresentable
3. Handle state updates
4. Report title changes back to pane

**Validation**:
- [ ] Terminal renders in SwiftUI
- [ ] Terminal is interactive
- [ ] Title updates propagate

**Commit**: `feat: create TerminalPaneView SwiftUI wrapper`

---

### S7-04: Wire Terminal into PaneContainerView

**Description**: Render TerminalPaneView for terminal type.

**Tasks**:
1. Update PaneContainerView switch for .terminal
2. Pass terminal state to TerminalPaneView
3. Handle keyboard focus

**Validation**:
- [ ] Terminal pane renders correctly
- [ ] Can type in terminal
- [ ] Terminal receives keyboard input

**Commit**: `feat: wire terminal pane into container`

---

### S7-05: Add New Terminal Menu Command

**Description**: Create terminal panes from menu.

**Tasks**:
1. Add "New Terminal" to Pane menu (⌘⇧T)
2. Create terminal at viewport center
3. Use current user home as initial cwd

**Validation**:
- [ ] ⌘⇧T creates terminal pane
- [ ] Terminal starts in home directory
- [ ] Multiple terminals can exist

**Commit**: `feat: add new terminal menu command`

---

### S7-06: Implement Terminal Title Tracking

**Description**: Update pane title from terminal.

**Tasks**:
1. Implement setTerminalTitle delegate method
2. Update pane.title in CanvasState
3. Handle working directory updates

**Validation**:
- [ ] Pane title updates when terminal title changes
- [ ] `cd` to directory updates title
- [ ] SSH session updates title

**Commit**: `feat: implement terminal title tracking`

---

### S7-07: Handle Terminal Process Exit

**Description**: Handle when shell process exits.

**Tasks**:
1. Implement processTerminated delegate method
2. Show exit code in terminal
3. Option to restart or close pane
4. Visual indicator for exited terminal

**Validation**:
- [ ] Exit code displayed
- [ ] Can restart shell
- [ ] Visual distinction for exited terminal

**Commit**: `feat: handle terminal process exit`

---

### S7-08: Implement File Drop to Terminal

**Description**: Drop file onto terminal to insert path.

**Tasks**:
1. Add drop handler to TerminalPaneView
2. Accept .fileURL drops
3. Insert escaped path at cursor
4. Handle multiple files

**Validation**:
- [ ] Dropping file inserts path
- [ ] Paths with spaces are escaped
- [ ] Multiple files separated by space

**Commit**: `feat: implement file drop to terminal`

---

### S7-09: Add Terminal Context Menu

**Description**: Right-click menu for terminal.

**Tasks**:
1. Add context menu:
   - Copy
   - Paste
   - Clear
   - Reset
   - Kill Process (Ctrl+C)
2. Implement actions

**Validation**:
- [ ] Context menu appears on right-click
- [ ] All actions work correctly

**Commit**: `feat: add terminal context menu`

---

### S7-10: Terminal Focus and Keyboard Handling

**Description**: Proper keyboard focus for terminal.

**Tasks**:
1. Terminal receives focus on click
2. Tab key works within terminal (not navigation)
3. ⌘+key shortcuts still work (copy, paste, etc.)
4. Escape works correctly

**Validation**:
- [ ] Clicking terminal focuses it
- [ ] Tab key sends to terminal
- [ ] ⌘C copies from terminal
- [ ] ⌘V pastes to terminal

**Commit**: `feat: implement terminal focus and keyboard handling`

---

**Sprint 7 Deliverable**: Fully functional terminal panes with shell interaction.

---

# Sprint 8: Browser Pane

**Goal**: Functional browser pane with WKWebView.

**Demo**: Create browser pane → navigate to localhost:3000 → see web content → use nav controls.

---

### S8-01: Define BrowserState

**Description**: State model for browser pane.

**Tasks**:
1. Create `Panes/Browser/BrowserState.swift`
2. Implement:
   ```swift
   struct BrowserState: Equatable {
       var url: URL
       var canGoBack: Bool = false
       var canGoForward: Bool = false
       var isLoading: Bool = false
       var title: String = ""
   }
   ```

**Validation**:
- [ ] BrowserState is Equatable
- [ ] URL is required

**Commit**: `feat: define BrowserState model`

---

### S8-02: Create WebViewStore

**Description**: Observable store for WKWebView state.

**Tasks**:
1. Create `Panes/Browser/WebViewStore.swift`
2. Implement ObservableObject with navigation state
3. Hold weak reference to WKWebView
4. Implement navigation methods

**Validation**:
- [ ] Store tracks navigation state
- [ ] Methods control webview
- [ ] No retain cycles

**Commit**: `feat: create WebViewStore observable`

---

### S8-03: Create BrowserWebView (NSViewRepresentable)

**Description**: SwiftUI wrapper for WKWebView.

**Tasks**:
1. Create `Panes/Browser/BrowserWebView.swift`
2. Implement NSViewRepresentable
3. Configure WKWebView:
   - Enable dev tools
   - Set up navigation delegate
4. Update store on navigation events

**Validation**:
- [ ] WebView renders in SwiftUI
- [ ] Navigation events update store
- [ ] Dev tools available (right-click → Inspect)

**Commit**: `feat: create BrowserWebView wrapper`

---

### S8-04: Create Browser Toolbar

**Description**: Navigation controls for browser.

**Tasks**:
1. Create `Panes/Browser/BrowserToolbar.swift`
2. Add controls:
   - Back button
   - Forward button
   - Reload button
   - URL text field
3. Wire up to WebViewStore

**Validation**:
- [ ] Buttons control navigation
- [ ] URL field shows current URL
- [ ] Enter in URL field navigates
- [ ] Buttons disabled when not applicable

**Commit**: `feat: create browser toolbar`

---

### S8-05: Create BrowserPaneView

**Description**: Complete browser pane with toolbar and webview.

**Tasks**:
1. Create `Panes/Browser/BrowserPaneView.swift`
2. Combine toolbar and webview
3. Handle state synchronization
4. Show loading indicator

**Validation**:
- [ ] Toolbar and webview render
- [ ] Navigation works end-to-end
- [ ] Loading state visible

**Commit**: `feat: create BrowserPaneView`

---

### S8-06: Wire Browser into PaneContainerView

**Description**: Render BrowserPaneView for browser type.

**Tasks**:
1. Update PaneContainerView switch for .browser
2. Pass browser state
3. Update pane title from page title

**Validation**:
- [ ] Browser pane renders correctly
- [ ] Pane title updates from page

**Commit**: `feat: wire browser pane into container`

---

### S8-07: Add New Browser Menu Command

**Description**: Create browser panes from menu.

**Tasks**:
1. Add "New Browser" to Pane menu (⌘⇧B)
2. Create browser at viewport center
3. Default to localhost:3000

**Validation**:
- [ ] ⌘⇧B creates browser pane
- [ ] Opens localhost:3000 by default
- [ ] Multiple browsers can exist

**Commit**: `feat: add new browser menu command`

---

### S8-08: Implement URL Drag-Drop

**Description**: Drag URLs to browser or from browser.

**Tasks**:
1. Accept URL drops to change location
2. Drag from URL field to other panes
3. Handle link drags within page

**Validation**:
- [ ] Dropping URL navigates browser
- [ ] Can drag URL from address bar
- [ ] Link drag to terminal inserts URL

**Commit**: `feat: implement browser URL drag-drop`

---

### S8-09: Add Browser DevTools Integration

**Description**: Quick access to Web Inspector.

**Tasks**:
1. Add "Inspect Element" to context menu
2. Keyboard shortcut ⌥⌘I opens inspector
3. Handle inspector window lifecycle

**Validation**:
- [ ] Right-click → Inspect works
- [ ] ⌥⌘I opens inspector
- [ ] Inspector closes with pane

**Commit**: `feat: add browser devtools integration`

---

### S8-10: Handle Browser Loading States

**Description**: Visual feedback during page load.

**Tasks**:
1. Show progress bar during load
2. Update reload button to stop button when loading
3. Handle load errors gracefully
4. Show error page for failures

**Validation**:
- [ ] Progress visible during load
- [ ] Stop button cancels load
- [ ] Errors show helpful message

**Commit**: `feat: handle browser loading states`

---

**Sprint 8 Deliverable**: Fully functional browser panes with navigation.

---

# Sprint 9: File Explorer & Code Editor Panes

**Goal**: File tree explorer and syntax-highlighted code editor.

**Demo**: Create file explorer → navigate folders → double-click file → opens in code editor pane.

---

### S9-01: Define FileItem Model

**Description**: Recursive model for file tree.

**Tasks**:
1. Create `Panes/FileExplorer/FileItem.swift`
2. Implement:
   ```swift
   class FileItem: Identifiable, ObservableObject {
       let id: URL
       let url: URL
       var isDirectory: Bool
       @Published var children: [FileItem]?
       @Published var isExpanded: Bool
       @Published var gitStatus: GitFileStatus
       weak var parent: FileItem?
   }
   ```

**Validation**:
- [ ] FileItem is Identifiable
- [ ] Weak parent prevents retain cycles
- [ ] Children lazy-loadable

**Commit**: `feat: define FileItem model`

---

### S9-02: Create FileSystemWatcher

**Description**: FSEvents wrapper for file changes.

**Tasks**:
1. Create `Panes/FileExplorer/FileSystemWatcher.swift`
2. Wrap FSEventStream
3. Debounce rapid changes
4. Callback with changed paths

**Validation**:
- [ ] Detects file creation
- [ ] Detects file deletion
- [ ] Detects file modification
- [ ] Cleans up on deinit

**Commit**: `feat: create FileSystemWatcher`

---

### S9-03: Define FileExplorerState

**Description**: State model for file explorer.

**Tasks**:
1. Create `Panes/FileExplorer/FileExplorerState.swift`
2. Implement:
   ```swift
   struct FileExplorerState: Equatable {
       var root: URL
       var selectedFiles: Set<URL> = []
       var expandedFolders: Set<URL> = []
   }
   ```

**Validation**:
- [ ] FileExplorerState is Equatable
- [ ] Root is required

**Commit**: `feat: define FileExplorerState`

---

### S9-04: Create FileTreeViewModel

**Description**: View model managing file tree.

**Tasks**:
1. Create `Panes/FileExplorer/FileTreeViewModel.swift`
2. Load directory contents
3. Handle file system events
4. Sort directories first, then alphabetically

**Validation**:
- [ ] Tree loads correctly
- [ ] Responds to file system changes
- [ ] Sorting correct

**Commit**: `feat: create FileTreeViewModel`

---

### S9-05: Create FileExplorerPaneView

**Description**: SwiftUI view for file tree.

**Tasks**:
1. Create `Panes/FileExplorer/FileExplorerPaneView.swift`
2. Use List with children parameter
3. Lazy-load child directories
4. Show appropriate file icons
5. Show git status colors

**Validation**:
- [ ] Tree renders correctly
- [ ] Expanding folders loads children
- [ ] Icons appropriate for file types
- [ ] Git status colors visible

**Commit**: `feat: create FileExplorerPaneView`

---

### S9-06: Define CodeEditorState

**Description**: State model for code editor.

**Tasks**:
1. Create `Panes/CodeEditor/CodeEditorState.swift`
2. Implement:
   ```swift
   struct CodeEditorState: Equatable {
       var file: URL?
       var content: String = ""
       var language: String = "plaintext"
       var isModified: Bool = false
   }
   ```

**Validation**:
- [ ] CodeEditorState is Equatable
- [ ] File optional (new file support)

**Commit**: `feat: define CodeEditorState`

---

### S9-07: Create CodeEditorPaneView

**Description**: SwiftUI view with CodeEditSourceEditor.

**Tasks**:
1. Create `Panes/CodeEditor/CodeEditorPaneView.swift`
2. Integrate CodeEditSourceEditor
3. Auto-detect language from file extension
4. Handle file loading
5. Track modifications

**Validation**:
- [ ] Editor renders content
- [ ] Syntax highlighting works
- [ ] Language detected correctly
- [ ] Modified indicator works

**Commit**: `feat: create CodeEditorPaneView`

---

### S9-08: Wire File Explorer and Code Editor into Container

**Description**: Render both pane types.

**Tasks**:
1. Update PaneContainerView for .fileExplorer
2. Update PaneContainerView for .codeEditor
3. Handle state correctly

**Validation**:
- [ ] Both pane types render
- [ ] State passed correctly

**Commit**: `feat: wire file explorer and code editor into container`

---

### S9-09: Implement File → Editor Navigation

**Description**: Double-click file to open in editor.

**Tasks**:
1. Add double-click handler to file rows
2. Create new code editor pane
3. Position near file explorer
4. Create connector from explorer to editor (optional)

**Validation**:
- [ ] Double-click opens file
- [ ] Editor shows correct content
- [ ] Multiple files can be open

**Commit**: `feat: implement file to editor navigation`

---

### S9-10: Add New File Explorer Menu Command

**Description**: Create file explorer from menu.

**Tasks**:
1. Add "New File Explorer" to Pane menu (⌘⇧E)
2. Show folder picker dialog
3. Create explorer at selected folder

**Validation**:
- [ ] ⌘⇧E prompts for folder
- [ ] Creates explorer at selected folder

**Commit**: `feat: add new file explorer menu command`

---

### S9-11: Implement File Drag from Explorer

**Description**: Drag files from explorer to other panes.

**Tasks**:
1. Add draggable modifier to file rows
2. Provide .fileURL drag type
3. Works with terminal (insert path)
4. Works with browser (file:// URL)

**Validation**:
- [ ] Can drag files from explorer
- [ ] Terminal accepts drops
- [ ] Browser accepts drops

**Commit**: `feat: implement file drag from explorer`

---

### S9-12: Add File Explorer Context Menu

**Description**: Right-click menu for files.

**Tasks**:
1. Add context menu:
   - Open
   - Open With...
   - Reveal in Finder
   - Copy Path
   - Delete
2. Implement actions

**Validation**:
- [ ] Context menu appears
- [ ] All actions work

**Commit**: `feat: add file explorer context menu`

---

**Sprint 9 Deliverable**: File explorer with navigation to code editor panes.

---

# Sprint 10: Git Pane & Persistence

**Goal**: Git operations pane and save/load canvas state.

**Demo**: Create git pane → see status → stage files → commit → save canvas → reload → state restored.

---

### S10-01: Create GitClient Actor

**Description**: Actor wrapping git CLI.

**Tasks**:
1. Create `Panes/Git/GitClient.swift`
2. Implement as actor for thread safety
3. Add methods:
   - status()
   - diff(file:, staged:)
   - stage(files:)
   - unstage(files:)
   - commit(message:)
   - currentBranch()
   - log(limit:)

**Validation**:
- [ ] All methods work in git repo
- [ ] Errors handled gracefully
- [ ] Thread-safe

**Commit**: `feat: create GitClient actor`

---

### S10-02: Define GitState and Parse Models

**Description**: State and parsing for git output.

**Tasks**:
1. Create `Panes/Git/GitState.swift`
2. Create `Panes/Git/GitStatusEntry.swift`
3. Create `Panes/Git/GitLogEntry.swift`
4. Implement status parsing (porcelain format)
5. Implement log parsing

**Validation**:
- [ ] Status parsed correctly
- [ ] Log parsed correctly
- [ ] All status codes handled

**Commit**: `feat: define git state and parse models`

---

### S10-03: Create GitViewModel

**Description**: View model for git pane.

**Tasks**:
1. Create `Panes/Git/GitViewModel.swift`
2. Manage GitClient interaction
3. Separate staged/unstaged files
4. Track current branch
5. Handle commit message

**Validation**:
- [ ] Status loads on init
- [ ] Staged/unstaged separated
- [ ] Branch tracked

**Commit**: `feat: create GitViewModel`

---

### S10-04: Create GitPaneView

**Description**: SwiftUI view for git operations.

**Tasks**:
1. Create `Panes/Git/GitPaneView.swift`
2. Show branch header
3. List staged files section
4. List unstaged files section
5. Commit message field
6. Commit button

**Validation**:
- [ ] All sections render
- [ ] Status accurate
- [ ] Commit works

**Commit**: `feat: create GitPaneView`

---

### S10-05: Wire Git Pane into Container

**Description**: Render GitPaneView for git type.

**Tasks**:
1. Update PaneContainerView for .git
2. Pass git state correctly

**Validation**:
- [ ] Git pane renders
- [ ] State passed correctly

**Commit**: `feat: wire git pane into container`

---

### S10-06: Add New Git Pane Menu Command

**Description**: Create git pane from menu.

**Tasks**:
1. Add "New Git" to Pane menu (⌘⇧G)
2. Auto-detect git root from file explorer if exists
3. Otherwise prompt for folder

**Validation**:
- [ ] ⌘⇧G creates git pane
- [ ] Detects git root correctly

**Commit**: `feat: add new git pane menu command`

---

### S10-07: Implement Stage/Unstage Actions

**Description**: Stage and unstage files from UI.

**Tasks**:
1. Add +/- buttons to file rows
2. Implement stage action
3. Implement unstage action
4. Refresh status after action

**Validation**:
- [ ] Clicking + stages file
- [ ] Clicking - unstages file
- [ ] Status updates after action

**Commit**: `feat: implement stage/unstage actions`

---

### S10-08: Define Persistence Models

**Description**: Codable models for save/load.

**Tasks**:
1. Create `Persistence/WorkspaceState.swift`
2. Make all state structs Codable
3. Handle non-serializable state (process IDs, etc.)
4. Define file format version

**Validation**:
- [ ] All models encode/decode
- [ ] Version included for migrations

**Commit**: `feat: define persistence models`

---

### S10-09: Create CanvasDocument

**Description**: Document-based saving.

**Tasks**:
1. Create `Persistence/CanvasDocument.swift`
2. Implement FileDocument protocol
3. Define UTType for .devys files
4. Implement read/write

**Validation**:
- [ ] Document saves to file
- [ ] Document loads from file
- [ ] File extension is .devys

**Commit**: `feat: create CanvasDocument for persistence`

---

### S10-10: Wire Up Document-Based App

**Description**: Enable save/open in app.

**Tasks**:
1. Update DevysApp to use DocumentGroup
2. Handle new document creation
3. Enable save/save as/open from menu
4. Show document name in title bar

**Validation**:
- [ ] ⌘S saves document
- [ ] ⌘O opens document
- [ ] Title shows document name
- [ ] Dirty state indicated

**Commit**: `feat: wire up document-based app`

---

### S10-11: Restore Pane State on Load

**Description**: Restore pane contents on load.

**Tasks**:
1. Terminals: Start new shell in saved cwd
2. Browsers: Navigate to saved URL
3. File Explorers: Reload at saved root
4. Code Editors: Reload file contents
5. Git: Refresh status

**Validation**:
- [ ] Save canvas with multiple panes
- [ ] Quit and reopen
- [ ] All panes restored correctly

**Commit**: `feat: restore pane state on document load`

---

### S10-12: Add Autosave Support

**Description**: Automatic saving of canvas state.

**Tasks**:
1. Enable autosave in DocumentGroup
2. Save on pane changes
3. Throttle saves (max every 5s)
4. Handle background save errors

**Validation**:
- [ ] Changes autosaved
- [ ] No excessive disk writes
- [ ] Errors don't crash app

**Commit**: `feat: add autosave support`

---

### S10-13: Write Git Client Unit Tests

**Description**: Tests for git operations.

**Tasks**:
1. Create `DevysTests/GitClientTests.swift`
2. Set up test git repo
3. Test status parsing
4. Test stage/unstage
5. Test commit

**Validation**:
- [ ] All tests pass
- [ ] Test repo cleaned up after tests

**Commit**: `test: add git client unit tests`

---

### S10-14: Write Persistence Unit Tests

**Description**: Tests for save/load.

**Tasks**:
1. Create `DevysTests/PersistenceTests.swift`
2. Test encode/decode round-trip
3. Test all pane types
4. Test version handling

**Validation**:
- [ ] Round-trip preserves data
- [ ] All pane types tested

**Commit**: `test: add persistence unit tests`

---

**Sprint 10 Deliverable**: Git operations pane and full save/load functionality.

---

# Summary

| Sprint | Tickets | Goal |
|--------|---------|------|
| 1 | 7 | Project scaffold, empty window |
| 2 | 8 | Infinite canvas with dot grid |
| 3 | 8 | Pane rendering on canvas |
| 4 | 8 | Pane drag and resize |
| 5 | 10 | Snapping and grouping |
| 6 | 10 | Bezier connectors |
| 7 | 10 | Terminal pane |
| 8 | 10 | Browser pane |
| 9 | 12 | File explorer & code editor |
| 10 | 14 | Git pane & persistence |

**Total: 97 tickets**

---

# Ticket Template

```markdown
### S{X}-{YY}: {Title}

**Description**: {One sentence description}

**Tasks**:
1. {Specific task}
2. {Specific task}
3. ...

**Validation**:
- [ ] {Testable acceptance criterion}
- [ ] {Testable acceptance criterion}

**Commit**: `{type}: {message}`
```

---

# Definition of Done

A ticket is complete when:
1. All tasks completed
2. All validation criteria checked
3. Code compiles without warnings
4. Unit tests pass (if applicable)
5. UI tests pass (if applicable)
6. Code reviewed (self-review acceptable for solo dev)
7. Committed with proper message format
