# Phase 1: Implementation Plan

## Goal

Build a native macOS infinite canvas app with:
- Dot-grid background (React Flow aesthetic)
- Draggable, groupable, connectable panes
- Pane types: Terminal, Browser, File Explorer, Code Editor, Git
- Bezier curve connectors between panes (visual for now, automation later)

---

## Project Structure

```
Devys/
├── Devys.xcodeproj
├── Devys/
│   ├── App/
│   │   ├── DevysApp.swift              # @main entry point
│   │   ├── AppCommands.swift           # Menu bar commands
│   │   └── AppDelegate.swift           # NSApplicationDelegate
│   │
│   ├── Canvas/
│   │   ├── CanvasView.swift            # Main infinite canvas
│   │   ├── CanvasState.swift           # Observable state object
│   │   ├── CanvasGridView.swift        # Dot grid background
│   │   ├── CanvasCoordinates.swift     # Coordinate transforms
│   │   └── CanvasGestures.swift        # Pan, zoom, selection
│   │
│   ├── Panes/
│   │   ├── Core/
│   │   │   ├── Pane.swift              # Pane data model
│   │   │   ├── PaneType.swift          # Enum of pane types
│   │   │   ├── PaneContainerView.swift # Chrome (title bar, resize)
│   │   │   ├── PaneGroup.swift         # Group data model
│   │   │   └── PaneRegistry.swift      # Factory for creating panes
│   │   │
│   │   ├── Terminal/
│   │   │   ├── TerminalPaneView.swift  # SwiftTerm wrapper
│   │   │   ├── TerminalState.swift     # Terminal state
│   │   │   └── TerminalController.swift # PTY management
│   │   │
│   │   ├── Browser/
│   │   │   ├── BrowserPaneView.swift   # WKWebView wrapper
│   │   │   ├── BrowserState.swift      # URL, nav state
│   │   │   └── BrowserToolbar.swift    # Nav controls
│   │   │
│   │   ├── FileExplorer/
│   │   │   ├── FileExplorerPaneView.swift  # NSOutlineView wrapper
│   │   │   ├── FileItem.swift              # Recursive file model
│   │   │   ├── FileSystemWatcher.swift     # FSEvents wrapper
│   │   │   └── FileExplorerController.swift # NSOutlineView delegate
│   │   │
│   │   ├── CodeEditor/
│   │   │   ├── CodeEditorPaneView.swift    # Editor wrapper
│   │   │   ├── CodeEditorState.swift       # File, cursor, selection
│   │   │   └── SyntaxTheme.swift           # Color schemes
│   │   │
│   │   └── Git/
│   │       ├── GitPaneView.swift           # Git operations UI
│   │       ├── GitClient.swift             # Shell wrapper for git
│   │       ├── GitStatus.swift             # Status parsing
│   │       └── DiffView.swift              # Diff rendering
│   │
│   ├── Connectors/
│   │   ├── Connector.swift             # Connector data model
│   │   ├── ConnectorView.swift         # Bezier curve rendering
│   │   ├── ConnectorHandle.swift       # Drag handles on panes
│   │   └── ConnectorLayer.swift        # Canvas layer for all connectors
│   │
│   ├── DragDrop/
│   │   ├── DragTypes.swift             # UTType definitions
│   │   ├── PaneDragDelegate.swift      # Pane drag handling
│   │   ├── CanvasDropDelegate.swift    # Canvas drop handling
│   │   └── SnapEngine.swift            # Edge snapping logic
│   │
│   ├── Persistence/
│   │   ├── CanvasDocument.swift        # Document-based saving
│   │   ├── WorkspaceState.swift        # Serializable state
│   │   └── Codable+Extensions.swift    # Custom encoding
│   │
│   └── Shared/
│       ├── Theme.swift                 # Colors, fonts
│       ├── Hotkeys.swift               # Keyboard shortcuts
│       └── Extensions/                 # Swift extensions
│
├── Packages/
│   └── DevysKit/                       # Shared utilities (SPM)
│
└── Dependencies/                       # External packages
```

---

## Milestones

### Milestone 1: Canvas Foundation
**Deliverable**: Pannable, zoomable infinite canvas with dot grid

### Milestone 2: Pane System
**Deliverable**: Draggable, resizable panes with chrome

### Milestone 3: Grouping & Snapping
**Deliverable**: Snap panes together, group/ungroup

### Milestone 4: Connectors
**Deliverable**: Bezier curves between panes

### Milestone 5: Terminal Pane
**Deliverable**: SwiftTerm-powered terminal pane

### Milestone 6: Browser Pane
**Deliverable**: WKWebView browser pane

### Milestone 7: File Explorer Pane
**Deliverable**: NSOutlineView file tree

### Milestone 8: Code Editor Pane
**Deliverable**: Syntax-highlighted editor

### Milestone 9: Git Pane
**Deliverable**: Status, staging, diff, commit

### Milestone 10: Persistence
**Deliverable**: Save/load canvas state

---

## Milestone 1: Canvas Foundation

### 1.1 Project Setup

```swift
// DevysApp.swift
import SwiftUI

@main
struct DevysApp: App {
    @StateObject private var canvasState = CanvasState()
    
    var body: some Scene {
        WindowGroup {
            CanvasView()
                .environmentObject(canvasState)
        }
        .commands {
            AppCommands(canvas: canvasState)
        }
    }
}
```

### 1.2 Canvas State

```swift
// CanvasState.swift
import SwiftUI

@MainActor
class CanvasState: ObservableObject {
    // Viewport
    @Published var offset: CGPoint = .zero    // Pan position
    @Published var scale: CGFloat = 1.0       // Zoom (0.25 - 4.0)
    
    // Panes
    @Published var panes: [Pane] = []
    @Published var groups: [PaneGroup] = []
    @Published var connectors: [Connector] = []
    
    // Selection
    @Published var selectedPaneIds: Set<UUID> = []
    @Published var hoveredPaneId: UUID?
    
    // Snapping
    @Published var snapGuides: [SnapGuide] = []
    
    // Zoom constraints
    static let minScale: CGFloat = 0.25
    static let maxScale: CGFloat = 4.0
}
```

### 1.3 Coordinate System

```swift
// CanvasCoordinates.swift
extension CanvasState {
    /// Screen point → Canvas point
    func canvasPoint(from screen: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (screen.x - center.x) / scale - offset.x,
            y: (screen.y - center.y) / scale - offset.y
        )
    }
    
    /// Canvas point → Screen point
    func screenPoint(from canvas: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (canvas.x + offset.x) * scale + center.x,
            y: (canvas.y + offset.y) * scale + center.y
        )
    }
    
    /// Visible rect in canvas coordinates
    func visibleRect(viewportSize: CGSize) -> CGRect {
        let topLeft = canvasPoint(from: .zero, viewportSize: viewportSize)
        let size = CGSize(
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
        return CGRect(origin: topLeft, size: size)
    }
}
```

### 1.4 Dot Grid Background

```swift
// CanvasGridView.swift
import SwiftUI

struct CanvasGridView: View {
    let offset: CGPoint
    let scale: CGFloat
    let dotSpacing: CGFloat = 20  // Base spacing in canvas coords
    let dotRadius: CGFloat = 1.5
    let dotColor = Color.gray.opacity(0.3)
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let spacing = dotSpacing * scale
                
                // Don't render if too zoomed out (performance)
                guard spacing > 4 else { return }
                
                // Calculate visible grid bounds
                let startX = offset.x.truncatingRemainder(dividingBy: dotSpacing) * scale
                let startY = offset.y.truncatingRemainder(dividingBy: dotSpacing) * scale
                
                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2
                
                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = startX + CGFloat(col) * spacing
                        let y = startY + CGFloat(row) * spacing
                        
                        let circle = Path(ellipseIn: CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        ))
                        context.fill(circle, with: .color(dotColor))
                    }
                }
            }
        }
        .drawingGroup() // Flatten for performance
    }
}
```

### 1.5 Canvas View with Gestures

```swift
// CanvasView.swift
import SwiftUI

struct CanvasView: View {
    @EnvironmentObject var canvas: CanvasState
    @State private var isPanning = false
    @GestureState private var gestureScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .windowBackgroundColor)
                
                // Dot grid
                CanvasGridView(offset: canvas.offset, scale: canvas.scale)
                
                // Connector layer (behind panes)
                ConnectorLayer()
                
                // Panes
                ForEach(canvas.panes.filter { pane in
                    canvas.visibleRect(viewportSize: geometry.size).intersects(pane.frame)
                }) { pane in
                    PaneContainerView(pane: pane)
                        .position(canvas.screenPoint(
                            from: CGPoint(
                                x: pane.frame.midX,
                                y: pane.frame.midY
                            ),
                            viewportSize: geometry.size
                        ))
                }
                
                // Snap guides overlay
                SnapGuidesOverlay()
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onTapGesture {
                canvas.selectedPaneIds.removeAll()
            }
        }
    }
    
    var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                // Only pan if not dragging a pane
                if canvas.selectedPaneIds.isEmpty {
                    canvas.offset.x += value.translation.width / canvas.scale
                    canvas.offset.y += value.translation.height / canvas.scale
                }
            }
    }
    
    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = canvas.scale * value
                canvas.scale = min(max(newScale, CanvasState.minScale), CanvasState.maxScale)
            }
    }
}
```

---

## Milestone 2: Pane System

### 2.1 Pane Data Model

```swift
// Pane.swift
import Foundation
import CoreGraphics

struct Pane: Identifiable, Equatable {
    let id: UUID
    var type: PaneType
    var frame: CGRect        // Position & size in canvas coordinates
    var zIndex: Int
    var groupId: UUID?
    var title: String
    var isCollapsed: Bool = false
    
    // Connection handles
    var inputHandlePosition: CGPoint { CGPoint(x: frame.minX, y: frame.midY) }
    var outputHandlePosition: CGPoint { CGPoint(x: frame.maxX, y: frame.midY) }
    
    static func == (lhs: Pane, rhs: Pane) -> Bool {
        lhs.id == rhs.id
    }
}
```

### 2.2 Pane Types

```swift
// PaneType.swift
enum PaneType: Codable, Equatable {
    case terminal(TerminalState)
    case browser(BrowserState)
    case fileExplorer(FileExplorerState)
    case codeEditor(CodeEditorState)
    case git(GitState)
}
```

### 2.3 Pane Container (Chrome)

```swift
// PaneContainerView.swift
import SwiftUI

struct PaneContainerView: View {
    let pane: Pane
    @EnvironmentObject var canvas: CanvasState
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var isResizing = false
    
    var isSelected: Bool {
        canvas.selectedPaneIds.contains(pane.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar
            
            // Content
            if !pane.isCollapsed {
                paneContent
                    .frame(
                        width: pane.frame.width * canvas.scale,
                        height: (pane.frame.height - 30) * canvas.scale
                    )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .overlay(resizeHandles, alignment: .bottomTrailing)
        .overlay(connectionHandles)
        .offset(dragOffset)
        .gesture(dragGesture)
        .onTapGesture {
            canvas.selectedPaneIds = [pane.id]
        }
    }
    
    var titleBar: some View {
        HStack {
            // Pane type icon
            Image(systemName: paneIcon)
                .foregroundColor(.secondary)
            
            // Title
            Text(pane.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            
            Spacer()
            
            // Collapse button
            Button(action: { toggleCollapse() }) {
                Image(systemName: pane.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            
            // Close button
            Button(action: { closePane() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 30 * canvas.scale)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    var paneIcon: String {
        switch pane.type {
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .fileExplorer: return "folder"
        case .codeEditor: return "doc.text"
        case .git: return "arrow.triangle.branch"
        }
    }
    
    @ViewBuilder
    var paneContent: some View {
        switch pane.type {
        case .terminal(let state):
            TerminalPaneView(state: state, paneId: pane.id)
        case .browser(let state):
            BrowserPaneView(state: state, paneId: pane.id)
        case .fileExplorer(let state):
            FileExplorerPaneView(state: state, paneId: pane.id)
        case .codeEditor(let state):
            CodeEditorPaneView(state: state, paneId: pane.id)
        case .git(let state):
            GitPaneView(state: state, paneId: pane.id)
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
                canvas.updateSnapGuides(for: pane, offset: dragOffset)
            }
            .onEnded { value in
                isDragging = false
                canvas.movePaneBy(pane.id, delta: CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                ))
                dragOffset = .zero
                canvas.clearSnapGuides()
            }
    }
    
    // ... resize handles, connection handles implementations
}
```

### 2.4 Canvas State Extensions

```swift
// CanvasState+Panes.swift
extension CanvasState {
    func createPane(type: PaneType, at position: CGPoint? = nil) {
        let defaultSize = CGSize(width: 400, height: 300)
        let pos = position ?? CGPoint(x: -offset.x, y: -offset.y)
        
        let pane = Pane(
            id: UUID(),
            type: type,
            frame: CGRect(origin: pos, size: defaultSize),
            zIndex: panes.count,
            groupId: nil,
            title: defaultTitle(for: type)
        )
        panes.append(pane)
        selectedPaneIds = [pane.id]
    }
    
    func deletePane(_ id: UUID) {
        panes.removeAll { $0.id == id }
        connectors.removeAll { $0.sourceId == id || $0.targetId == id }
        selectedPaneIds.remove(id)
    }
    
    func movePaneBy(_ id: UUID, delta: CGSize) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        panes[index].frame.origin.x += delta.width
        panes[index].frame.origin.y += delta.height
    }
    
    func resizePane(_ id: UUID, to size: CGSize) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        panes[index].frame.size = size
    }
    
    func bringToFront(_ id: UUID) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        let maxZ = panes.map(\.zIndex).max() ?? 0
        panes[index].zIndex = maxZ + 1
    }
    
    private func defaultTitle(for type: PaneType) -> String {
        switch type {
        case .terminal: return "Terminal"
        case .browser(let state): return state.url.host ?? "Browser"
        case .fileExplorer(let state): return state.root.lastPathComponent
        case .codeEditor(let state): return state.file?.lastPathComponent ?? "Untitled"
        case .git: return "Git"
        }
    }
}
```

---

## Milestone 3: Grouping & Snapping

### 3.1 Snap Engine

```swift
// SnapEngine.swift
import CoreGraphics

struct SnapGuide: Identifiable {
    let id = UUID()
    enum Orientation { case horizontal, vertical }
    var orientation: Orientation
    var position: CGFloat       // x for vertical, y for horizontal
    var start: CGFloat          // Start of guide line
    var end: CGFloat            // End of guide line
}

extension CanvasState {
    static let snapThreshold: CGFloat = 8.0
    
    func updateSnapGuides(for pane: Pane, offset: CGSize) {
        var guides: [SnapGuide] = []
        let movingFrame = pane.frame.offsetBy(dx: offset.width, dy: offset.height)
        
        for other in panes where other.id != pane.id {
            // Left edge → Left edge
            if abs(movingFrame.minX - other.frame.minX) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .vertical,
                    position: other.frame.minX,
                    start: min(movingFrame.minY, other.frame.minY),
                    end: max(movingFrame.maxY, other.frame.maxY)
                ))
            }
            
            // Right edge → Right edge
            if abs(movingFrame.maxX - other.frame.maxX) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .vertical,
                    position: other.frame.maxX,
                    start: min(movingFrame.minY, other.frame.minY),
                    end: max(movingFrame.maxY, other.frame.maxY)
                ))
            }
            
            // Right edge → Left edge (adjacent)
            if abs(movingFrame.maxX - other.frame.minX) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .vertical,
                    position: other.frame.minX,
                    start: min(movingFrame.minY, other.frame.minY),
                    end: max(movingFrame.maxY, other.frame.maxY)
                ))
            }
            
            // Left edge → Right edge (adjacent)
            if abs(movingFrame.minX - other.frame.maxX) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .vertical,
                    position: other.frame.maxX,
                    start: min(movingFrame.minY, other.frame.minY),
                    end: max(movingFrame.maxY, other.frame.maxY)
                ))
            }
            
            // Similar for horizontal snapping (top/bottom edges)
            // Top edge → Top edge
            if abs(movingFrame.minY - other.frame.minY) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .horizontal,
                    position: other.frame.minY,
                    start: min(movingFrame.minX, other.frame.minX),
                    end: max(movingFrame.maxX, other.frame.maxX)
                ))
            }
            
            // Bottom edge → Bottom edge
            if abs(movingFrame.maxY - other.frame.maxY) < Self.snapThreshold {
                guides.append(SnapGuide(
                    orientation: .horizontal,
                    position: other.frame.maxY,
                    start: min(movingFrame.minX, other.frame.minX),
                    end: max(movingFrame.maxX, other.frame.maxX)
                ))
            }
        }
        
        snapGuides = guides
    }
    
    func clearSnapGuides() {
        snapGuides = []
    }
}
```

### 3.2 Group Model

```swift
// PaneGroup.swift
struct PaneGroup: Identifiable {
    let id: UUID
    var paneIds: [UUID]
    var name: String
    var color: Color = .accentColor
    
    // Computed bounding box
    func boundingBox(in panes: [Pane]) -> CGRect {
        let groupPanes = panes.filter { paneIds.contains($0.id) }
        guard !groupPanes.isEmpty else { return .zero }
        
        let minX = groupPanes.map { $0.frame.minX }.min()!
        let minY = groupPanes.map { $0.frame.minY }.min()!
        let maxX = groupPanes.map { $0.frame.maxX }.max()!
        let maxY = groupPanes.map { $0.frame.maxY }.max()!
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension CanvasState {
    func groupSelectedPanes() {
        guard selectedPaneIds.count > 1 else { return }
        
        let group = PaneGroup(
            id: UUID(),
            paneIds: Array(selectedPaneIds),
            name: "Group \(groups.count + 1)"
        )
        groups.append(group)
        
        for id in selectedPaneIds {
            if let idx = panes.firstIndex(where: { $0.id == id }) {
                panes[idx].groupId = group.id
            }
        }
    }
    
    func ungroupPane(_ paneId: UUID) {
        guard let pane = panes.first(where: { $0.id == paneId }),
              let groupId = pane.groupId else { return }
        
        if let paneIdx = panes.firstIndex(where: { $0.id == paneId }) {
            panes[paneIdx].groupId = nil
        }
        
        if let groupIdx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[groupIdx].paneIds.removeAll { $0 == paneId }
            
            // Dissolve if 1 or fewer panes remain
            if groups[groupIdx].paneIds.count <= 1 {
                for remainingId in groups[groupIdx].paneIds {
                    if let idx = panes.firstIndex(where: { $0.id == remainingId }) {
                        panes[idx].groupId = nil
                    }
                }
                groups.remove(at: groupIdx)
            }
        }
    }
}
```

---

## Milestone 4: Connectors

### 4.1 Connector Model

```swift
// Connector.swift
struct Connector: Identifiable {
    let id: UUID
    var sourceId: UUID          // Source pane
    var targetId: UUID          // Target pane
    var sourceHandle: HandlePosition
    var targetHandle: HandlePosition
    var label: String?
    var color: Color = .blue
    
    enum HandlePosition: Codable {
        case top, bottom, left, right
    }
}
```

### 4.2 Bezier Connector View

```swift
// ConnectorView.swift
import SwiftUI

struct ConnectorView: View {
    let connector: Connector
    @EnvironmentObject var canvas: CanvasState
    
    var body: some View {
        GeometryReader { geometry in
            if let sourcePt = sourcePoint(in: geometry.size),
               let targetPt = targetPoint(in: geometry.size) {
                
                Path { path in
                    path.move(to: sourcePt)
                    
                    // Bezier control points
                    let dx = targetPt.x - sourcePt.x
                    let controlOffset = max(abs(dx) * 0.5, 50)
                    
                    let cp1 = CGPoint(x: sourcePt.x + controlOffset, y: sourcePt.y)
                    let cp2 = CGPoint(x: targetPt.x - controlOffset, y: targetPt.y)
                    
                    path.addCurve(to: targetPt, control1: cp1, control2: cp2)
                }
                .stroke(connector.color, style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                ))
                
                // Arrow head at target
                arrowHead(at: targetPt, from: CGPoint(
                    x: targetPt.x - 20,
                    y: targetPt.y
                ))
                .fill(connector.color)
            }
        }
    }
    
    func sourcePoint(in viewportSize: CGSize) -> CGPoint? {
        guard let pane = canvas.panes.first(where: { $0.id == connector.sourceId }) else { return nil }
        let canvasPt = handlePosition(for: connector.sourceHandle, in: pane.frame)
        return canvas.screenPoint(from: canvasPt, viewportSize: viewportSize)
    }
    
    func targetPoint(in viewportSize: CGSize) -> CGPoint? {
        guard let pane = canvas.panes.first(where: { $0.id == connector.targetId }) else { return nil }
        let canvasPt = handlePosition(for: connector.targetHandle, in: pane.frame)
        return canvas.screenPoint(from: canvasPt, viewportSize: viewportSize)
    }
    
    func handlePosition(for handle: Connector.HandlePosition, in frame: CGRect) -> CGPoint {
        switch handle {
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        }
    }
    
    func arrowHead(at point: CGPoint, from: CGPoint) -> Path {
        let angle = atan2(point.y - from.y, point.x - from.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        
        return Path { path in
            path.move(to: point)
            path.addLine(to: CGPoint(
                x: point.x - arrowLength * cos(angle - arrowAngle),
                y: point.y - arrowLength * sin(angle - arrowAngle)
            ))
            path.addLine(to: CGPoint(
                x: point.x - arrowLength * cos(angle + arrowAngle),
                y: point.y - arrowLength * sin(angle + arrowAngle)
            ))
            path.closeSubpath()
        }
    }
}

struct ConnectorLayer: View {
    @EnvironmentObject var canvas: CanvasState
    
    var body: some View {
        ForEach(canvas.connectors) { connector in
            ConnectorView(connector: connector)
        }
    }
}
```

### 4.3 Connector Creation

```swift
// CanvasState+Connectors.swift
extension CanvasState {
    @Published var isDrawingConnector: Bool = false
    @Published var pendingConnectorSource: (paneId: UUID, handle: Connector.HandlePosition)?
    @Published var pendingConnectorEndpoint: CGPoint?
    
    func startConnector(from paneId: UUID, handle: Connector.HandlePosition) {
        isDrawingConnector = true
        pendingConnectorSource = (paneId, handle)
    }
    
    func updatePendingConnector(to point: CGPoint) {
        pendingConnectorEndpoint = point
    }
    
    func finishConnector(to paneId: UUID, handle: Connector.HandlePosition) {
        guard let source = pendingConnectorSource,
              source.paneId != paneId else {
            cancelConnector()
            return
        }
        
        // Check if connection already exists
        let exists = connectors.contains {
            ($0.sourceId == source.paneId && $0.targetId == paneId) ||
            ($0.sourceId == paneId && $0.targetId == source.paneId)
        }
        
        if !exists {
            let connector = Connector(
                id: UUID(),
                sourceId: source.paneId,
                targetId: paneId,
                sourceHandle: source.handle,
                targetHandle: handle
            )
            connectors.append(connector)
        }
        
        cancelConnector()
    }
    
    func cancelConnector() {
        isDrawingConnector = false
        pendingConnectorSource = nil
        pendingConnectorEndpoint = nil
    }
    
    func deleteConnector(_ id: UUID) {
        connectors.removeAll { $0.id == id }
    }
}
```

---

## Milestone 5: Terminal Pane

### 5.1 Dependencies

Add to Package.swift or Xcode:
```swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
```

### 5.2 Terminal State

```swift
// TerminalState.swift
struct TerminalState: Codable, Equatable {
    var cwd: URL
    var shell: String = "/bin/zsh"
    var title: String = "Terminal"
    var scrollback: Int = 10000
    
    // Not persisted
    var processId: pid_t? = nil
    
    enum CodingKeys: String, CodingKey {
        case cwd, shell, title, scrollback
    }
}
```

### 5.3 Terminal Controller

```swift
// TerminalController.swift
import SwiftTerm
import AppKit

class TerminalController: NSViewController {
    var terminalView: LocalProcessTerminalView!
    var state: TerminalState
    var onTitleChange: ((String) -> Void)?
    
    init(state: TerminalState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func loadView() {
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.terminalDelegate = self
        view.addSubview(terminalView)
        
        // Start shell process
        let env = ProcessInfo.processInfo.environment
        terminalView.startProcess(
            executable: state.shell,
            args: [],
            environment: env.merging(["TERM": "xterm-256color"]) { $1 },
            execName: (state.shell as NSString).lastPathComponent
        )
        
        // Set working directory
        if FileManager.default.fileExists(atPath: state.cwd.path) {
            terminalView.send(txt: "cd \"\(state.cwd.path)\"\n")
        }
    }
    
    func sendText(_ text: String) {
        terminalView.send(txt: text)
    }
    
    func sendInterrupt() {
        terminalView.send([0x03]) // Ctrl+C
    }
}

extension TerminalController: LocalProcessTerminalViewDelegate {
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        // Update CWD tracking
    }
    
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        // Handle resize
    }
    
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        state.title = title
        onTitleChange?(title)
    }
    
    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        // Handle process exit
    }
}
```

### 5.4 SwiftUI Wrapper

```swift
// TerminalPaneView.swift
import SwiftUI

struct TerminalPaneView: NSViewControllerRepresentable {
    let state: TerminalState
    let paneId: UUID
    @EnvironmentObject var canvas: CanvasState
    
    func makeNSViewController(context: Context) -> TerminalController {
        let controller = TerminalController(state: state)
        controller.onTitleChange = { title in
            canvas.updatePaneTitle(paneId, title: title)
        }
        return controller
    }
    
    func updateNSViewController(_ controller: TerminalController, context: Context) {
        // Handle state updates if needed
    }
}

extension CanvasState {
    func updatePaneTitle(_ id: UUID, title: String) {
        if let idx = panes.firstIndex(where: { $0.id == id }) {
            panes[idx].title = title
        }
    }
}
```

---

## Milestone 6: Browser Pane

### 6.1 Browser State

```swift
// BrowserState.swift
import Foundation

struct BrowserState: Codable, Equatable {
    var url: URL
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var title: String = ""
    
    enum CodingKeys: String, CodingKey {
        case url  // Only persist URL
    }
}
```

### 6.2 Browser Pane View

```swift
// BrowserPaneView.swift
import SwiftUI
import WebKit

struct BrowserPaneView: View {
    let state: BrowserState
    let paneId: UUID
    @EnvironmentObject var canvas: CanvasState
    @State private var webViewStore = WebViewStore()
    
    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(store: webViewStore, paneId: paneId)
            WebViewWrapper(store: webViewStore, initialURL: state.url)
        }
    }
}

class WebViewStore: ObservableObject {
    @Published var url: URL = URL(string: "about:blank")!
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var title = ""
    
    weak var webView: WKWebView?
    
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func load(_ url: URL) { webView?.load(URLRequest(url: url)) }
}

struct WebViewWrapper: NSViewRepresentable {
    @ObservedObject var store: WebViewStore
    let initialURL: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        store.webView = webView
        webView.load(URLRequest(url: initialURL))
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let store: WebViewStore
        
        init(store: WebViewStore) {
            self.store = store
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            store.url = webView.url ?? URL(string: "about:blank")!
            store.canGoBack = webView.canGoBack
            store.canGoForward = webView.canGoForward
            store.title = webView.title ?? ""
            store.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            store.isLoading = true
        }
    }
}

struct BrowserToolbar: View {
    @ObservedObject var store: WebViewStore
    let paneId: UUID
    @State private var urlText: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: store.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!store.canGoBack)
            
            Button(action: store.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.canGoForward)
            
            Button(action: store.reload) {
                Image(systemName: store.isLoading ? "xmark" : "arrow.clockwise")
            }
            
            TextField("URL", text: $urlText, onCommit: {
                if let url = URL(string: urlText) {
                    store.load(url.scheme == nil ? URL(string: "https://\(urlText)")! : url)
                }
            })
            .textFieldStyle(.roundedBorder)
            .onAppear { urlText = store.url.absoluteString }
            .onChange(of: store.url) { urlText = $0.absoluteString }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

---

## Milestone 7: File Explorer Pane

### 7.1 File Item Model

```swift
// FileItem.swift
import Foundation

class FileItem: Identifiable, ObservableObject, Hashable {
    let id: URL
    let url: URL
    var name: String { url.lastPathComponent }
    var isDirectory: Bool
    @Published var children: [FileItem]?
    @Published var isExpanded: Bool = false
    @Published var gitStatus: GitFileStatus = .unchanged
    
    weak var parent: FileItem?
    
    init(url: URL, isDirectory: Bool) {
        self.id = url
        self.url = url
        self.isDirectory = isDirectory
        self.children = isDirectory ? [] : nil
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

enum GitFileStatus {
    case unchanged
    case modified
    case added
    case deleted
    case untracked
    case ignored
}
```

### 7.2 File System Watcher

```swift
// FileSystemWatcher.swift
import Foundation
import CoreServices

class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let callback: (Set<String>) -> Void
    private let path: String
    
    init(path: String, callback: @escaping (Set<String>) -> Void) {
        self.path = path
        self.callback = callback
    }
    
    func start() {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        
        stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
                
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                watcher.callback(Set(paths))
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // Latency
            flags
        )
        
        guard let stream = stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }
    
    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
    
    deinit {
        stop()
    }
}
```

### 7.3 File Explorer State & View

```swift
// FileExplorerState.swift
struct FileExplorerState: Codable, Equatable {
    var root: URL
    var selectedFiles: Set<URL> = []
    var expandedFolders: Set<URL> = []
    
    static func == (lhs: FileExplorerState, rhs: FileExplorerState) -> Bool {
        lhs.root == rhs.root
    }
    
    enum CodingKeys: String, CodingKey {
        case root
    }
}

// FileExplorerPaneView.swift
struct FileExplorerPaneView: View {
    let state: FileExplorerState
    let paneId: UUID
    @StateObject private var fileTree = FileTreeViewModel()
    @EnvironmentObject var canvas: CanvasState
    
    var body: some View {
        List(fileTree.rootItems, children: \.loadedChildren) { item in
            FileRowView(item: item)
                .onTapGesture(count: 2) {
                    if !item.isDirectory {
                        openFileInEditor(item.url)
                    }
                }
                .draggable(item.url)
        }
        .listStyle(.sidebar)
        .onAppear {
            fileTree.load(root: state.root)
        }
    }
    
    func openFileInEditor(_ url: URL) {
        canvas.createPane(
            type: .codeEditor(CodeEditorState(file: url)),
            at: nil
        )
    }
}

class FileTreeViewModel: ObservableObject {
    @Published var rootItems: [FileItem] = []
    private var watcher: FileSystemWatcher?
    
    func load(root: URL) {
        rootItems = loadDirectory(at: root)
        
        watcher = FileSystemWatcher(path: root.path) { [weak self] changedPaths in
            DispatchQueue.main.async {
                self?.handleChanges(changedPaths)
            }
        }
        watcher?.start()
    }
    
    private func loadDirectory(at url: URL) -> [FileItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return contents.compactMap { url -> FileItem? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileItem(url: url, isDirectory: isDir)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func handleChanges(_ paths: Set<String>) {
        // Refresh affected parts of tree
        // (Implementation depends on specifics)
    }
}

struct FileRowView: View {
    @ObservedObject var item: FileItem
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon)
                .foregroundColor(item.isDirectory ? .blue : .secondary)
                .frame(width: 16)
            
            Text(item.name)
                .foregroundColor(gitStatusColor)
            
            Spacer()
        }
    }
    
    var fileIcon: String {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "doc.text"
        case "ts", "tsx": return "doc.text"
        case "json": return "curlybraces"
        case "md", "markdown": return "doc.richtext"
        case "html": return "globe"
        case "css", "scss": return "paintbrush"
        default: return "doc"
        }
    }
    
    var gitStatusColor: Color {
        switch item.gitStatus {
        case .unchanged: return .primary
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .gray
        case .ignored: return .gray.opacity(0.5)
        }
    }
}

// Helper to lazily load children
extension FileItem {
    var loadedChildren: [FileItem]? {
        guard isDirectory else { return nil }
        if children?.isEmpty == true {
            loadChildren()
        }
        return children
    }
    
    func loadChildren() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        children = contents.map { childURL in
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let child = FileItem(url: childURL, isDirectory: isDir)
            child.parent = self
            return child
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
```

---

## Milestone 8: Code Editor Pane

### 8.1 Option A: Use CodeEditSourceEditor

Add dependency:
```swift
.package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor.git", from: "0.7.0")
```

### 8.2 Code Editor State

```swift
// CodeEditorState.swift
struct CodeEditorState: Codable, Equatable {
    var file: URL?
    var content: String = ""
    var language: String = "plaintext"
    var cursorPosition: Int = 0
    var isModified: Bool = false
    
    static func == (lhs: CodeEditorState, rhs: CodeEditorState) -> Bool {
        lhs.file == rhs.file
    }
}
```

### 8.3 Code Editor View

```swift
// CodeEditorPaneView.swift
import SwiftUI
import CodeEditSourceEditor

struct CodeEditorPaneView: View {
    let state: CodeEditorState
    let paneId: UUID
    @State private var content: String = ""
    @State private var language: CodeLanguage = .default
    @State private var cursorPositions: [CursorPosition] = []
    @EnvironmentObject var canvas: CanvasState
    
    var body: some View {
        CodeEditSourceEditor(
            $content,
            language: language,
            theme: EditorTheme.default,
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            tabWidth: 4,
            lineHeight: 1.4,
            wrapLines: true,
            cursorPositions: $cursorPositions
        )
        .onAppear {
            loadFile()
        }
    }
    
    func loadFile() {
        guard let file = state.file,
              let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else {
            content = state.content
            return
        }
        content = text
        language = CodeLanguage.detectLanguage(for: file)
    }
}

extension CodeLanguage {
    static func detectLanguage(for url: URL) -> CodeLanguage {
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "js": return .javascript
        case "ts": return .typescript
        case "py": return .python
        case "rs": return .rust
        case "go": return .go
        case "json": return .json
        case "html": return .html
        case "css": return .css
        case "md", "markdown": return .markdown
        default: return .default
        }
    }
}
```

---

## Milestone 9: Git Pane

### 9.1 Git Client

```swift
// GitClient.swift
import Foundation

actor GitClient {
    let workingDirectory: URL
    
    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }
    
    func status() async throws -> [GitStatusEntry] {
        let output = try await run("status", "--porcelain=v1")
        return parseStatus(output)
    }
    
    func diff(file: URL? = nil, staged: Bool = false) async throws -> String {
        var args = ["diff"]
        if staged { args.append("--cached") }
        if let file = file { args.append(file.path) }
        return try await run(args)
    }
    
    func stage(files: [URL]) async throws {
        let paths = files.map { $0.path }
        try await run(["add"] + paths)
    }
    
    func unstage(files: [URL]) async throws {
        let paths = files.map { $0.path }
        try await run(["reset", "HEAD"] + paths)
    }
    
    func commit(message: String) async throws {
        try await run("commit", "-m", message)
    }
    
    func log(limit: Int = 50) async throws -> [GitLogEntry] {
        let output = try await run(
            "log",
            "--oneline",
            "--format=%H|%h|%s|%an|%ar",
            "-n", String(limit)
        )
        return parseLog(output)
    }
    
    func currentBranch() async throws -> String {
        try await run("branch", "--show-current").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private
    
    private func run(_ args: String...) async throws -> String {
        try await run(args)
    }
    
    private func run(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func parseStatus(_ output: String) -> [GitStatusEntry] {
        output.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            let status = String(line.prefix(2))
            let path = String(line.dropFirst(3))
            return GitStatusEntry(status: status, path: path)
        }
    }
    
    private func parseLog(_ output: String) -> [GitLogEntry] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 4)
            guard parts.count >= 5 else { return nil }
            return GitLogEntry(
                hash: String(parts[0]),
                shortHash: String(parts[1]),
                message: String(parts[2]),
                author: String(parts[3]),
                relativeDate: String(parts[4])
            )
        }
    }
}

struct GitStatusEntry {
    let status: String
    let path: String
    
    var statusType: GitFileStatus {
        switch status.trimmingCharacters(in: .whitespaces) {
        case "M", "MM": return .modified
        case "A": return .added
        case "D": return .deleted
        case "??": return .untracked
        default: return .unchanged
        }
    }
}

struct GitLogEntry: Identifiable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let message: String
    let author: String
    let relativeDate: String
}
```

### 9.2 Git Pane View

```swift
// GitState.swift
struct GitState: Codable, Equatable {
    var workingDirectory: URL
    
    static func == (lhs: GitState, rhs: GitState) -> Bool {
        lhs.workingDirectory == rhs.workingDirectory
    }
}

// GitPaneView.swift
struct GitPaneView: View {
    let state: GitState
    let paneId: UUID
    @StateObject private var viewModel: GitViewModel
    @EnvironmentObject var canvas: CanvasState
    
    init(state: GitState, paneId: UUID) {
        self.state = state
        self.paneId = paneId
        _viewModel = StateObject(wrappedValue: GitViewModel(workingDirectory: state.workingDirectory))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Branch header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                Text(viewModel.currentBranch)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Changes list
            List {
                if !viewModel.stagedFiles.isEmpty {
                    Section("Staged") {
                        ForEach(viewModel.stagedFiles, id: \.path) { entry in
                            GitFileRow(entry: entry, isStaged: true, viewModel: viewModel)
                        }
                    }
                }
                
                if !viewModel.unstagedFiles.isEmpty {
                    Section("Changes") {
                        ForEach(viewModel.unstagedFiles, id: \.path) { entry in
                            GitFileRow(entry: entry, isStaged: false, viewModel: viewModel)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Commit area
            VStack(spacing: 8) {
                TextField("Commit message", text: $viewModel.commitMessage)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: { viewModel.commit() }) {
                    Text("Commit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.stagedFiles.isEmpty || viewModel.commitMessage.isEmpty)
            }
            .padding(8)
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

struct GitFileRow: View {
    let entry: GitStatusEntry
    let isStaged: Bool
    @ObservedObject var viewModel: GitViewModel
    
    var body: some View {
        HStack {
            statusIcon
            Text(entry.path)
                .lineLimit(1)
            Spacer()
            Button(action: { toggleStaged() }) {
                Image(systemName: isStaged ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }
    
    var statusIcon: some View {
        Text(entry.status)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(statusColor)
            .frame(width: 20)
    }
    
    var statusColor: Color {
        switch entry.statusType {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .gray
        default: return .primary
        }
    }
    
    func toggleStaged() {
        let url = viewModel.workingDirectory.appendingPathComponent(entry.path)
        if isStaged {
            viewModel.unstage(files: [url])
        } else {
            viewModel.stage(files: [url])
        }
    }
}

@MainActor
class GitViewModel: ObservableObject {
    let workingDirectory: URL
    private let client: GitClient
    
    @Published var currentBranch = "main"
    @Published var stagedFiles: [GitStatusEntry] = []
    @Published var unstagedFiles: [GitStatusEntry] = []
    @Published var commitMessage = ""
    
    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
        self.client = GitClient(workingDirectory: workingDirectory)
    }
    
    func refresh() {
        Task {
            do {
                currentBranch = try await client.currentBranch()
                let status = try await client.status()
                
                // Split into staged/unstaged (simplified)
                stagedFiles = status.filter { $0.status.first != " " && $0.status.first != "?" }
                unstagedFiles = status.filter { $0.status.last != " " || $0.status.first == "?" }
            } catch {
                print("Git error: \(error)")
            }
        }
    }
    
    func stage(files: [URL]) {
        Task {
            try? await client.stage(files: files)
            refresh()
        }
    }
    
    func unstage(files: [URL]) {
        Task {
            try? await client.unstage(files: files)
            refresh()
        }
    }
    
    func commit() {
        Task {
            try? await client.commit(message: commitMessage)
            commitMessage = ""
            refresh()
        }
    }
}
```

---

## Milestone 10: Persistence

### 10.1 Document-Based App

```swift
// CanvasDocument.swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let devysCanvas = UTType(exportedAs: "com.devys.canvas")
}

struct CanvasDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.devysCanvas] }
    
    var state: WorkspaceState
    
    init() {
        state = WorkspaceState()
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        state = try JSONDecoder().decode(WorkspaceState.self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(state)
        return .init(regularFileWithContents: data)
    }
}

struct WorkspaceState: Codable {
    var canvasOffset: CGPoint = .zero
    var canvasScale: CGFloat = 1.0
    var panes: [PersistablePaneData] = []
    var groups: [PaneGroup] = []
    var connectors: [Connector] = []
}

struct PersistablePaneData: Codable, Identifiable {
    let id: UUID
    var type: PaneType
    var frame: CGRect
    var zIndex: Int
    var groupId: UUID?
    var title: String
    var isCollapsed: Bool
}
```

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Terminal | ⌘⇧T |
| New Browser | ⌘⇧B |
| New File Explorer | ⌘⇧E |
| New Code Editor | ⌘⇧N |
| New Git Pane | ⌘⇧G |
| Toggle Fullscreen Pane | ⌘↵ |
| Duplicate Pane | ⌘D |
| Group Selected | ⌘G |
| Ungroup | ⌘⇧G |
| Delete Pane | ⌫ (when selected) |
| Zoom In | ⌘+ |
| Zoom Out | ⌘- |
| Zoom to Fit | ⌘0 |
| Save Canvas | ⌘S |

---

## Dependencies Summary

| Package | Purpose | URL |
|---------|---------|-----|
| SwiftTerm | Terminal emulation | https://github.com/migueldeicaza/SwiftTerm |
| CodeEditSourceEditor | Code editing | https://github.com/CodeEditApp/CodeEditSourceEditor |
| CodeEditLanguages | Syntax highlighting | https://github.com/CodeEditApp/CodeEditLanguages |

Built-in frameworks used:
- WebKit (WKWebView)
- CoreServices (FSEvents)
- AppKit (NSOutlineView, NSView wrappers)

---

## Next Steps

After Phase 1:
1. **Agent Panes** - Spawn Claude Code / Codex processes, stream output
2. **Workflow Automation** - Connectors trigger actions (agent chains)
3. **Prompt Library** - Store and inject prompts
4. **MCP Management** - Visual config for MCP servers
