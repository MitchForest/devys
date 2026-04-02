# DevysSplit Package Documentation

## Overview

DevysSplit is a Swift package that provides a flexible, macOS-native split view system with tabbed panes. It enables IDE-like split layouts where users can create horizontal and vertical splits, manage tabs within each pane, drag tabs between panes, and navigate using keyboard shortcuts. The package is built on SwiftUI with AppKit integration for native `NSSplitView` behavior and smooth 120fps animations.

**Platform:** macOS 14.0+
**Swift Tools Version:** 5.9
**Concurrency:** StrictConcurrency enabled

## Architecture

### Tree-Based Layout Model

DevysSplit uses a recursive tree structure to represent the split layout:

```
SplitNode (indirect enum)
  |
  +-- .pane(PaneState)     // Leaf node: contains tabs
  |
  +-- .split(SplitState)   // Branch node: contains two children
        |
        +-- first: SplitNode
        +-- second: SplitNode
        +-- orientation: .horizontal | .vertical
        +-- dividerPosition: 0.0-1.0
```

This design allows unlimited nesting of splits. Each leaf (`PaneState`) manages its own collection of tabs, selected tab, and unique identifier.

### Controller Architecture

The package follows a two-layer controller pattern:

1. **`DevysSplitController`** (Public) - The main API for consumers
   - Manages configuration and delegate callbacks
   - Provides tab/pane CRUD operations
   - Exposes geometry query APIs
   - Wraps internal controller

2. **`SplitViewController`** (Internal) - Core state management
   - Owns the root `SplitNode` tree
   - Handles focus management
   - Performs recursive tree operations
   - Manages drag state

### View Hierarchy

```
DevysSplitView (Public entry point)
  |
  +-- SplitViewContainer
        |
        +-- SplitNodeView (recursive)
              |
              +-- PaneContainerView (for .pane nodes)
              |     |
              |     +-- TabBarView
              |     +-- Content area (user-provided)
              |
              +-- SplitContainerView (for .split nodes, wraps NSSplitView)
                    |
                    +-- SplitChildView (first)
                    +-- SplitChildView (second)
```

## File Organization

```
Sources/DevysSplit/
  |
  +-- Public/
  |     |
  |     +-- DevysSplitController.swift   # Main public controller API
  |     +-- DevysSplitView.swift         # SwiftUI entry point view
  |     +-- DevysSplitConfiguration.swift # Configuration & appearance
  |     +-- DevysSplitDelegate.swift     # Delegate protocol for callbacks
  |     |
  |     +-- Types/
  |           +-- Tab.swift              # Public tab representation
  |           +-- TabID.swift            # Opaque tab identifier
  |           +-- PaneID.swift           # Opaque pane identifier
  |           +-- SplitOrientation.swift # .horizontal | .vertical
  |           +-- NavigationDirection.swift # .left/.right/.up/.down
  |           +-- DropContent.swift      # External drag-drop content
  |           +-- WelcomeTabBehavior.swift # Empty pane behavior
  |           +-- LayoutSnapshot.swift   # Geometry query types
  |
  +-- Internal/
        |
        +-- Controllers/
        |     +-- SplitViewController.swift  # Core state controller
        |
        +-- Models/
        |     +-- SplitNode.swift        # Tree node enum
        |     +-- SplitState.swift       # Split branch state
        |     +-- PaneState.swift        # Pane leaf state
        |     +-- TabItem.swift          # Internal tab representation
        |
        +-- Views/
        |     +-- SplitViewContainer.swift   # Root container
        |     +-- SplitNodeView.swift        # Recursive node renderer
        |     +-- SplitContainerView.swift   # NSSplitView wrapper
        |     +-- PaneContainerView.swift    # Tab bar + content
        |     +-- TabBarView.swift           # Scrollable tab bar
        |     +-- TabItemView.swift          # Individual tab UI
        |     +-- TabDragPreview.swift       # Drag preview
        |
        +-- Styling/
        |     +-- SplitColors.swift      # Observable theme colors
        |     +-- TabBarColors.swift     # Legacy static colors
        |     +-- TabBarMetrics.swift    # Sizing constants
        |
        +-- Utilities/
              +-- SplitAnimator.swift    # Display-synced animations
```

## Key Types

### Public Types

#### `DevysSplitController`
The main controller for managing split view state. Observable class that provides:
- Tab operations: `createTab()`, `closeTab()`, `updateTab()`, `selectTab()`
- Split operations: `splitPane()`, `closePane()`
- Focus management: `focusPane()`, `navigateFocus(direction:)`
- Queries: `allTabIds`, `allPaneIds`, `tabs(inPane:)`, `layoutSnapshot()`
- Dynamic theming: `updateColors()`

#### `DevysSplitView`
SwiftUI view that renders the split layout:
```swift
DevysSplitView(controller: controller) { tab, paneId in
    // Content for each tab
    MyContentView(for: tab)
} emptyPane: { paneId in
    // View for empty panes
    Text("No tabs")
}
```

#### `DevysSplitConfiguration`
Comprehensive configuration struct with nested types:
- **Behavior:** `allowSplits`, `allowCloseTabs`, `autoCloseEmptyPanes`, `contentViewLifecycle`, `welcomeTabBehavior`
- **Appearance:** `tabBarHeight`, `tabMinWidth`, `minimumPaneWidth`, `showSplitButtons`
- **Colors:** `accent`, `tabBarBackground`, `activeTabBackground`, `separator`
- **Presets:** `.default`, `.singlePane`, `.readOnly`, `.compact`, `.spacious`

#### `DevysSplitDelegate`
Protocol for receiving callbacks (all methods optional via default implementations):
- Veto operations: `shouldCreateTab`, `shouldCloseTab`, `shouldSplitPane`, `shouldClosePane`
- Notifications: `didCreateTab`, `didCloseTab`, `didSelectTab`, `didSplitPane`, `didFocusPane`
- Geometry: `didChangeGeometry(snapshot:)`
- Drag-drop: `didReceiveDrop`, `shouldAcceptDrop`
- Welcome tabs: `welcomeTabForPane`, `isWelcomeTab`

#### `Tab` / `TabID` / `PaneID`
Public immutable types for identifying and querying tabs/panes. Internal UUIDs are wrapped in opaque structs for type safety.

#### `SplitOrientation`
```swift
enum SplitOrientation {
    case horizontal  // Side-by-side (left | right)
    case vertical    // Stacked (top / bottom)
}
```

#### `LayoutSnapshot` / `PaneGeometry` / `PixelRect`
Types for querying the current layout with pixel coordinates, useful for external synchronization.

### Internal Types

#### `SplitNode`
Indirect enum representing tree nodes:
```swift
indirect enum SplitNode: Identifiable, Equatable {
    case pane(PaneState)
    case split(SplitState)

    func findPane(_ paneId: PaneID) -> PaneState?
    func computePaneBounds(in: CGRect) -> [PaneBounds]
    var allPanes: [PaneState]
    var allPaneIds: [PaneID]
}
```

#### `SplitState`
Observable class for split branch nodes:
```swift
@Observable class SplitState {
    var orientation: SplitOrientation
    var first: SplitNode
    var second: SplitNode
    var dividerPosition: CGFloat  // 0.0-1.0
    var animationOrigin: SplitAnimationOrigin?
}
```

#### `PaneState`
Observable class for leaf nodes containing tabs:
```swift
@Observable class PaneState {
    let id: PaneID
    var tabs: [TabItem]
    var selectedTabId: UUID?

    func selectTab(_ tabId: UUID)
    func addTab(_ tab: TabItem, select: Bool)
    func removeTab(_ tabId: UUID) -> TabItem?
    func moveTab(from: Int, to: Int)
}
```

#### `TabItem`
Internal tab representation with `Transferable` conformance for drag-drop:
```swift
struct TabItem: Identifiable, Hashable, Codable, Transferable {
    let id: UUID
    var title: String
    var icon: String?
    var isDirty: Bool
}
```

## Dependencies

**None.** DevysSplit has no external dependencies beyond the Apple SDK frameworks:
- SwiftUI
- AppKit
- Foundation
- CoreVideo / QuartzCore (for display-synced animations)
- UniformTypeIdentifiers (for drag-drop)

## Public API Surface

### DevysSplitController

```swift
// Initialization
init(configuration: DevysSplitConfiguration = .default)

// Delegate
var delegate: DevysSplitDelegate?
var configuration: DevysSplitConfiguration

// Tab Operations
func createTab(title:, icon:, isDirty:, inPane:) -> TabID?
func updateTab(_: TabID, title:, icon:, isDirty:)
func closeTab(_: TabID) -> Bool
func closeTab(_: TabID, inPane: PaneID) -> Bool
func selectTab(_: TabID)
func selectPreviousTab()
func selectNextTab()

// Split Operations
func splitPane(_: PaneID?, orientation:, withTab:) -> PaneID?
func closePane(_: PaneID) -> Bool

// Focus
var focusedPaneId: PaneID?
func focusPane(_: PaneID)
func navigateFocus(direction: NavigationDirection)

// Queries
var allTabIds: [TabID]
var allPaneIds: [PaneID]
func tab(_: TabID) -> Tab?
func tabs(inPane: PaneID) -> [Tab]
func selectedTab(inPane: PaneID) -> Tab?
func isWelcomeTab(_: TabID) -> Bool

// Geometry
func layoutSnapshot() -> LayoutSnapshot
func treeSnapshot() -> ExternalTreeNode
func setDividerPosition(_: CGFloat, forSplit: UUID, fromExternal: Bool) -> Bool

// Theming
func updateColors(_: DevysSplitConfiguration.Colors)
```

### DevysSplitView

```swift
// Full initializer
init(controller: DevysSplitController,
     content: @escaping (Tab, PaneID) -> Content,
     emptyPane: @escaping (PaneID) -> EmptyContent)

// Convenience (with default empty view)
init(controller: DevysSplitController,
     content: @escaping (Tab, PaneID) -> Content)
```

## Split View Patterns

### Creating Splits
```swift
// Split the focused pane horizontally (side-by-side)
let newPaneId = controller.splitPane(orientation: .horizontal)

// Split a specific pane vertically with a new tab
let tab = Tab(title: "New File", icon: "doc")
controller.splitPane(somePaneId, orientation: .vertical, withTab: tab)
```

### Keyboard Navigation
```swift
// Navigate between panes spatially
controller.navigateFocus(direction: .left)
controller.navigateFocus(direction: .right)
controller.navigateFocus(direction: .up)
controller.navigateFocus(direction: .down)

// Cycle tabs in focused pane
controller.selectNextTab()
controller.selectPreviousTab()
```

### Tab Lifecycle
```swift
// Create tab in focused pane
let tabId = controller.createTab(title: "Untitled", icon: "doc.text")

// Update tab state
controller.updateTab(tabId!, title: "main.swift", isDirty: true)

// Close tab
controller.closeTab(tabId!)
```

### Geometry Synchronization
For external systems that need layout information:
```swift
// Get current layout with pixel coordinates
let snapshot = controller.layoutSnapshot()
for pane in snapshot.panes {
    print("Pane \(pane.paneId) at \(pane.frame)")
}

// Update divider from external source
controller.setDividerPosition(0.3, forSplit: splitUUID, fromExternal: true)
```

## Pane Management

### Content View Lifecycle
Two modes controlled by `configuration.contentViewLifecycle`:

1. **`.recreateOnSwitch`** (default): Only selected tab's content is in the view hierarchy. Memory efficient but loses view state on tab switch.

2. **`.keepAllAlive`**: All tab contents remain in hierarchy, hidden when not selected. Preserves scroll position, @State, focus, etc.

### Empty Pane Handling
Controlled by `configuration.welcomeTabBehavior`:
- `.none`: No automatic welcome tabs
- `.autoCreateOnly`: Create welcome tab via delegate
- `.autoCreateAndClosePane`: Create welcome tab; closing it closes the pane

### Auto-Close Empty Panes
When `configuration.autoCloseEmptyPanes` is true (default), panes with no tabs are automatically closed (except the last pane).

## Animation System

DevysSplit uses a custom `SplitAnimator` class for smooth 120fps animations via `CVDisplayLink`:

- **Display-synced**: Updates happen on every frame refresh
- **Pixel-perfect**: Positions are rounded to avoid sub-pixel rendering artifacts
- **Easing**: Uses exponential ease-out curve (`1 - 2^(-10t)`)
- **Duration**: 0.16 seconds for split animations

Animations are triggered automatically when:
- Creating a new split (new pane slides in from edge)
- The divider position is changed programmatically

## Drag and Drop

### Internal Tab Moves
Tabs can be dragged between panes within the same window. The system uses:
- `TabTransferData` with JSON encoding
- Custom `UTType.tabItem` and `UTType.tabTransfer`
- Visual drop indicators in tab bar and pane content areas

### External Drops
Configure accepted drop types via `configuration.acceptedDropTypes`. The delegate receives:
```swift
func splitView(_ controller: DevysSplitController,
               didReceiveDrop content: DropContent,
               inPane pane: PaneID,
               zone: DropZone) -> TabID?
```

Drop zones:
- `.center`: Add as tab to existing pane
- `.edge(.horizontal)`: Create horizontal split
- `.edge(.vertical)`: Create vertical split
- `.tabBar(index:)`: Insert at specific tab position

## Theming

Colors are managed through `SplitColors`, an observable class injected via environment:

```swift
// Update theme dynamically
controller.updateColors(DevysSplitConfiguration.Colors(
    accent: .blue,
    tabBarBackground: .black.opacity(0.9),
    activeTabBackground: .gray.opacity(0.3)
))
```

Views access colors via `@Environment(\.splitColors)`.

## Testing

The package includes a test target at `Tests/DevysSplitTests/` with basic tests for:
- Controller creation
- Tab creation and retrieval
- Tab updates
- Tab closing
- Configuration handling

## Integration Example

```swift
import SwiftUI
import DevysSplit

struct ContentView: View {
    @State private var controller = DevysSplitController(
        configuration: DevysSplitConfiguration(
            allowSplits: true,
            allowCloseTabs: true,
            contentViewLifecycle: .keepAllAlive,
            appearance: .default,
            colors: .default
        )
    )

    var body: some View {
        DevysSplitView(controller: controller) { tab, paneId in
            VStack {
                Text(tab.title)
                    .font(.headline)
                // Your content here
            }
            .onTapGesture {
                controller.focusPane(paneId)
            }
        } emptyPane: { paneId in
            VStack {
                Text("Empty Pane")
                Button("Add Tab") {
                    controller.createTab(title: "New Tab", inPane: paneId)
                }
            }
        }
        .onAppear {
            controller.delegate = self
        }
    }
}

extension ContentView: DevysSplitDelegate {
    func splitTabBar(_ controller: DevysSplitController,
                     didSelectTab tab: Tab,
                     inPane pane: PaneID) {
        print("Selected: \(tab.title)")
    }
}
```
