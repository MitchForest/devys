# Swift Native Canvas Exploration

## Overview

Building an infinite canvas with heterogeneous panes (terminals, browsers, files, agents) in native Swift/macOS.

---

## Infinite Canvas Architecture

### Approach: Custom Coordinate System

The canvas is a viewport into a much larger virtual space. We don't render everything—only what's visible.

```
┌─────────────────────────────────────────────────────┐
│                  Virtual Canvas                      │
│                  (infinite space)                    │
│                                                      │
│        ┌──────────────────────┐                      │
│        │      Viewport        │                      │
│        │   (visible area)     │                      │
│        │                      │                      │
│        └──────────────────────┘                      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Core Components

```swift
struct CanvasState {
    var offset: CGPoint      // Pan offset (viewport position in canvas coords)
    var scale: CGFloat       // Zoom level (1.0 = 100%)
    var panes: [Pane]        // All panes on canvas
    var groups: [PaneGroup]  // Grouped panes
    var selection: Set<UUID> // Currently selected pane IDs
}

struct Pane: Identifiable {
    let id: UUID
    var type: PaneType
    var frame: CGRect        // Position/size in canvas coordinates
    var zIndex: Int
    var groupId: UUID?       // nil if ungrouped
}

enum PaneType {
    case terminal(TerminalState)
    case browser(BrowserState)
    case fileTree(FileTreeState)
    case agent(AgentState)
    case diff(DiffState)
}
```

### Coordinate Transforms

Every interaction needs to convert between screen and canvas coordinates:

```swift
extension CanvasState {
    /// Convert screen point to canvas point
    func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x / scale) - offset.x,
            y: (screenPoint.y / scale) - offset.y
        )
    }
    
    /// Convert canvas rect to screen rect
    func screenRect(from canvasRect: CGRect) -> CGRect {
        CGRect(
            x: (canvasRect.origin.x + offset.x) * scale,
            y: (canvasRect.origin.y + offset.y) * scale,
            width: canvasRect.width * scale,
            height: canvasRect.height * scale
        )
    }
    
    /// Check if pane is visible in current viewport
    func isVisible(_ pane: Pane, in viewportSize: CGSize) -> Bool {
        let viewportRect = CGRect(
            origin: CGPoint(x: -offset.x, y: -offset.y),
            size: CGSize(width: viewportSize.width / scale, height: viewportSize.height / scale)
        )
        return pane.frame.intersects(viewportRect)
    }
}
```

### SwiftUI Canvas View

```swift
struct InfiniteCanvasView: View {
    @StateObject var canvas = CanvasState()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid (optional, helps with spatial awareness)
                CanvasGridView(offset: canvas.offset, scale: canvas.scale)
                
                // Render only visible panes
                ForEach(canvas.visiblePanes(in: geometry.size)) { pane in
                    PaneContainerView(pane: pane, canvas: canvas)
                        .frame(width: pane.frame.width * canvas.scale,
                               height: pane.frame.height * canvas.scale)
                        .position(canvas.screenPoint(from: pane.frame.origin))
                }
            }
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onDrop(of: [.pane, .fileURL], delegate: CanvasDropDelegate(canvas: canvas))
        }
    }
    
    var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Two-finger pan moves viewport
                canvas.offset.x += value.translation.width / canvas.scale
                canvas.offset.y += value.translation.height / canvas.scale
            }
    }
    
    var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                canvas.scale = max(0.1, min(3.0, value))
            }
    }
}
```

---

## Terminal Panes

### Library: SwiftTerm

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) is a VT100/xterm terminal emulator in pure Swift.

```swift
import SwiftTerm

struct TerminalState {
    var cwd: URL
    var processId: pid_t?
    var title: String
    var scrollback: Int = 10000
}

class TerminalPaneController: NSViewController {
    var terminalView: LocalProcessTerminalView!
    var state: TerminalState
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        view.addSubview(terminalView)
        
        // Start shell
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: [],
            environment: ProcessInfo.processInfo.environment,
            execName: "zsh"
        )
        
        // Set initial directory
        terminalView.send(txt: "cd \(state.cwd.path)\n")
    }
    
    /// Insert text at cursor (for drag-drop file paths)
    func insertText(_ text: String) {
        terminalView.send(txt: text)
    }
    
    /// Send interrupt (Ctrl+C)
    func interrupt() {
        terminalView.send([0x03]) // ETX
    }
}
```

### SwiftUI Wrapper

```swift
struct TerminalPaneView: NSViewControllerRepresentable {
    @Binding var state: TerminalState
    
    func makeNSViewController(context: Context) -> TerminalPaneController {
        TerminalPaneController(state: state)
    }
    
    func updateNSViewController(_ controller: TerminalPaneController, context: Context) {
        // Handle state updates
    }
}
```

---

## Browser Panes

### Using WKWebView

```swift
import WebKit

struct BrowserState {
    var url: URL
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var title: String = ""
}

struct BrowserPaneView: NSViewRepresentable {
    @Binding var state: BrowserState
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // Enable inspector
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: state.url))
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != state.url {
            webView.load(URLRequest(url: state.url))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var state: BrowserState
        
        init(state: Binding<BrowserState>) {
            _state = state
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward
            state.title = webView.title ?? ""
            state.isLoading = false
        }
    }
}
```

### Browser Toolbar

```swift
struct BrowserToolbar: View {
    @Binding var state: BrowserState
    var webView: WKWebView?
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { webView?.goBack() }) {
                Image(systemName: "chevron.left")
            }.disabled(!state.canGoBack)
            
            Button(action: { webView?.goForward() }) {
                Image(systemName: "chevron.right")
            }.disabled(!state.canGoForward)
            
            Button(action: { webView?.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            
            TextField("URL", text: Binding(
                get: { state.url.absoluteString },
                set: { if let url = URL(string: $0) { state.url = url } }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(4)
    }
}
```

---

## File Tree Panes

### Using OutlineGroup (SwiftUI)

```swift
struct FileNode: Identifiable, Hashable {
    let id: URL
    var name: String
    var isDirectory: Bool
    var children: [FileNode]?
    var isExpanded: Bool = false
}

struct FileTreeState {
    var root: URL
    var nodes: [FileNode] = []
    var selection: Set<URL> = []
}

struct FileTreePaneView: View {
    @Binding var state: FileTreeState
    
    var body: some View {
        List(state.nodes, children: \.children, selection: $state.selection) { node in
            FileRowView(node: node)
                .draggable(node.id) // Enable drag
        }
        .listStyle(.sidebar)
        .onAppear { loadNodes() }
    }
    
    func loadNodes() {
        state.nodes = loadDirectory(at: state.root)
    }
    
    func loadDirectory(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return contents.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileNode(
                id: url,
                name: url.lastPathComponent,
                isDirectory: isDir,
                children: isDir ? [] : nil // Lazy load
            )
        }.sorted { $0.isDirectory && !$1.isDirectory }
    }
}

struct FileRowView: View {
    let node: FileNode
    
    var body: some View {
        HStack {
            Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                .foregroundColor(node.isDirectory ? .blue : .secondary)
            Text(node.name)
        }
    }
    
    func fileIcon(for name: String) -> String {
        switch (name as NSString).pathExtension {
        case "swift": return "swift"
        case "js", "ts": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }
}
```

---

## Drag and Drop System

### Custom Drag Types

```swift
import UniformTypeIdentifiers

extension UTType {
    static let canvasPane = UTType(exportedAs: "com.devys.pane")
    static let canvasPaneGroup = UTType(exportedAs: "com.devys.panegroup")
}
```

### Pane Dragging

```swift
struct PaneContainerView: View {
    let pane: Pane
    @ObservedObject var canvas: CanvasState
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Pane chrome (title bar, resize handles)
            PaneChromeView(pane: pane, canvas: canvas)
            
            // Pane content
            paneContent
        }
        .overlay(resizeHandles)
        .gesture(dragGesture)
        .onDrop(of: [.fileURL], delegate: PaneDropDelegate(pane: pane, canvas: canvas))
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
                
                // Check for snap targets
                canvas.updateSnapGuides(for: pane, translation: value.translation)
            }
            .onEnded { value in
                isDragging = false
                
                // Apply snap if within threshold
                if let snapPosition = canvas.snapPosition(for: pane) {
                    canvas.movePaneTo(pane.id, position: snapPosition)
                } else {
                    canvas.movePaneBy(pane.id, delta: value.translation)
                }
                
                canvas.clearSnapGuides()
            }
    }
    
    @ViewBuilder
    var paneContent: some View {
        switch pane.type {
        case .terminal(let state):
            TerminalPaneView(state: .constant(state))
        case .browser(let state):
            BrowserPaneView(state: .constant(state))
        case .fileTree(let state):
            FileTreePaneView(state: .constant(state))
        case .agent(let state):
            AgentPaneView(state: .constant(state))
        case .diff(let state):
            DiffPaneView(state: .constant(state))
        }
    }
}
```

### Drop Handling

```swift
struct PaneDropDelegate: DropDelegate {
    let pane: Pane
    @ObservedObject var canvas: CanvasState
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle file drops
        if let fileProvider = info.itemProviders(for: [.fileURL]).first {
            fileProvider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url else { return }
                
                DispatchQueue.main.async {
                    handleFileDrop(url: url)
                }
            }
            return true
        }
        
        // Handle pane drops (grouping)
        if let paneProvider = info.itemProviders(for: [.canvasPane]).first {
            paneProvider.loadObject(ofClass: NSString.self) { idString, error in
                guard let idString = idString as? String,
                      let droppedPaneId = UUID(uuidString: idString) else { return }
                
                DispatchQueue.main.async {
                    canvas.groupPanes([pane.id, droppedPaneId])
                }
            }
            return true
        }
        
        return false
    }
    
    func handleFileDrop(url: URL) {
        switch pane.type {
        case .terminal:
            // Insert escaped path into terminal
            let escapedPath = url.path.replacingOccurrences(of: " ", with: "\\ ")
            canvas.sendToTerminal(pane.id, text: escapedPath)
            
        case .agent:
            // Add file to agent context
            canvas.addFileToAgentContext(pane.id, file: url)
            
        default:
            break
        }
    }
}
```

---

## Snapping System

### Snap Detection

```swift
struct SnapGuide {
    enum GuideType { case horizontal, vertical }
    var type: GuideType
    var position: CGFloat
    var sourcePaneId: UUID
}

extension CanvasState {
    static let snapThreshold: CGFloat = 10.0
    
    var snapGuides: [SnapGuide] = []
    
    mutating func updateSnapGuides(for pane: Pane, translation: CGSize) {
        let movingFrame = pane.frame.offsetBy(dx: translation.width, dy: translation.height)
        var guides: [SnapGuide] = []
        
        for other in panes where other.id != pane.id {
            // Left edge snaps
            if abs(movingFrame.minX - other.minX) < Self.snapThreshold {
                guides.append(SnapGuide(type: .vertical, position: other.minX, sourcePaneId: other.id))
            }
            if abs(movingFrame.minX - other.maxX) < Self.snapThreshold {
                guides.append(SnapGuide(type: .vertical, position: other.maxX, sourcePaneId: other.id))
            }
            
            // Right edge snaps
            if abs(movingFrame.maxX - other.minX) < Self.snapThreshold {
                guides.append(SnapGuide(type: .vertical, position: other.minX, sourcePaneId: other.id))
            }
            if abs(movingFrame.maxX - other.maxX) < Self.snapThreshold {
                guides.append(SnapGuide(type: .vertical, position: other.maxX, sourcePaneId: other.id))
            }
            
            // Top/bottom snaps (similar logic)
            // ...
        }
        
        snapGuides = guides
    }
    
    func snapPosition(for pane: Pane) -> CGPoint? {
        guard let guide = snapGuides.first else { return nil }
        // Calculate snapped position based on guide
        // ...
        return nil
    }
}
```

---

## Grouping System

### Group Data Model

```swift
struct PaneGroup: Identifiable {
    let id: UUID
    var paneIds: [UUID]
    var layout: GroupLayout
    var frame: CGRect  // Computed from children
    var isCollapsed: Bool = false
}

enum GroupLayout {
    case freeform          // Panes positioned freely within group bounds
    case horizontal        // Panes arranged left-to-right
    case vertical          // Panes arranged top-to-bottom
    case tabbed            // Only one pane visible, tabs to switch
}
```

### Group Operations

```swift
extension CanvasState {
    mutating func groupPanes(_ paneIds: [UUID]) {
        let group = PaneGroup(
            id: UUID(),
            paneIds: paneIds,
            layout: .freeform,
            frame: computeGroupFrame(for: paneIds)
        )
        
        groups.append(group)
        
        // Assign groupId to panes
        for i in panes.indices where paneIds.contains(panes[i].id) {
            panes[i].groupId = group.id
        }
    }
    
    mutating func ungroupPane(_ paneId: UUID) {
        guard let pane = panes.first(where: { $0.id == paneId }),
              let groupId = pane.groupId,
              let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
        
        // Remove from group
        groups[groupIndex].paneIds.removeAll { $0 == paneId }
        
        // If group is now empty or has 1 pane, dissolve it
        if groups[groupIndex].paneIds.count <= 1 {
            let remainingPaneIds = groups[groupIndex].paneIds
            groups.remove(at: groupIndex)
            for id in remainingPaneIds {
                if let idx = panes.firstIndex(where: { $0.id == id }) {
                    panes[idx].groupId = nil
                }
            }
        }
    }
    
    mutating func duplicatePane(_ paneId: UUID) {
        guard let pane = panes.first(where: { $0.id == paneId }) else { return }
        
        var newPane = pane
        newPane.id = UUID()
        newPane.frame = pane.frame.offsetBy(dx: 20, dy: 20)
        newPane.groupId = nil // Duplicates start ungrouped
        
        panes.append(newPane)
    }
}
```

---

## Keyboard Shortcuts

```swift
struct CanvasCommands: Commands {
    @ObservedObject var canvas: CanvasState
    
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Terminal") {
                canvas.createPane(type: .terminal(TerminalState(cwd: URL(fileURLWithPath: "~"))))
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            
            Button("New Browser") {
                canvas.createPane(type: .browser(BrowserState(url: URL(string: "http://localhost:3000")!)))
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        
        CommandGroup(after: .windowArrangement) {
            Button("Toggle Fullscreen Pane") {
                canvas.toggleSelectedPaneFullscreen()
            }
            .keyboardShortcut(.return, modifiers: .command)
            
            Button("Duplicate Pane") {
                if let selected = canvas.selection.first {
                    canvas.duplicatePane(selected)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            
            Button("Group Selected") {
                canvas.groupPanes(Array(canvas.selection))
            }
            .keyboardShortcut("g", modifiers: .command)
        }
    }
}
```

---

## Performance Considerations

| Challenge | Solution |
|-----------|----------|
| Many terminals | Only attach PTY to visible terminals, pause hidden ones |
| Many browser views | Suspend off-screen WKWebViews, take snapshot images |
| Large file trees | Virtual scrolling, lazy child loading |
| Smooth panning | Use Metal-backed layers, minimize redraws |
| Memory | Limit scrollback, compress terminal history |

---

## Dependencies

| Library | Purpose | Link |
|---------|---------|------|
| SwiftTerm | Terminal emulation | https://github.com/migueldeicaza/SwiftTerm |
| SwiftSoup | HTML parsing (if needed) | https://github.com/scinfu/SwiftSoup |

WebKit (WKWebView) and FileManager are built into macOS.

---

## Open Questions

1. **AppKit vs SwiftUI**: SwiftUI for layout, but terminals/browsers may need AppKit wrappers. Hybrid approach likely.

2. **State persistence**: Core Data? SQLite? File-based JSON? Need fast serialization for canvas state.

3. **Multi-window**: Multiple canvas windows or single-window with workspaces?

4. **Agent process management**: How to manage spawned agent CLIs (Claude Code, Codex)? Need to track PIDs, capture stdout/stderr.
