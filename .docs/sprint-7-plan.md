# Sprint 7: Terminal Pane - Comprehensive Plan

## Goal
Functional terminal panes using SwiftTerm that can run shell commands, AI coding agents (Claude Code, Codex), and other CLI tools.

## Demo
Launch app → ⇧⌘T creates terminal pane → see shell prompt → type commands → see output → run `claude` or `codex` → interact with AI agent.

---

## Prerequisites (Already Done)
- [x] SwiftTerm dependency added to Package.swift
- [x] Pane infrastructure (PaneType, PaneContainerView, etc.)
- [x] ⇧⌘T menu command wired up

---

## Tickets

### S7-01: Define TerminalState Model
**Description**: Create the state model for terminal panes with all configuration options.

**File**: `Panes/Terminal/TerminalState.swift`

```swift
import Foundation

/// State for a terminal pane
public struct TerminalState: Equatable, Codable {
    /// Current working directory
    public var workingDirectory: URL
    
    /// Shell executable path
    public var shell: String
    
    /// Terminal title (from shell escape sequence)
    public var title: String
    
    /// Scrollback buffer size
    public var scrollbackLines: Int
    
    /// Whether the shell process has exited
    public var hasExited: Bool
    
    /// Exit code (if exited)
    public var exitCode: Int32?
    
    public init(
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        title: String = "Terminal",
        scrollbackLines: Int = 10000
    ) {
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.title = title
        self.scrollbackLines = scrollbackLines
        self.hasExited = false
        self.exitCode = nil
    }
    
    // Only persist configuration, not runtime state
    enum CodingKeys: String, CodingKey {
        case workingDirectory, shell, scrollbackLines
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try container.decode(URL.self, forKey: .workingDirectory)
        shell = try container.decode(String.self, forKey: .shell)
        scrollbackLines = try container.decode(Int.self, forKey: .scrollbackLines)
        title = "Terminal"
        hasExited = false
        exitCode = nil
    }
}
```

**Validation**:
- [ ] TerminalState is Equatable
- [ ] TerminalState is Codable (without runtime state)
- [ ] Default shell uses $SHELL environment variable
- [ ] Default CWD is user home directory

**Commit**: `feat(terminal): define TerminalState model`

---

### S7-02: Update PaneType with Real TerminalState
**Description**: Replace placeholder TerminalState in PaneType with the real implementation.

**File**: `Panes/Core/PaneType.swift`

**Tasks**:
1. Import TerminalState
2. Update `.terminal(TerminalState)` case to use real type
3. Remove placeholder struct
4. Update Equatable conformance

**Validation**:
- [ ] PaneType.terminal uses real TerminalState
- [ ] Existing tests still pass
- [ ] Project compiles

**Commit**: `refactor(terminal): use real TerminalState in PaneType`

---

### S7-03: Create TerminalController (AppKit)
**Description**: NSViewController that wraps SwiftTerm's LocalProcessTerminalView.

**File**: `Panes/Terminal/TerminalController.swift`

```swift
import AppKit
import SwiftTerm

/// Protocol for terminal events
protocol TerminalControllerDelegate: AnyObject {
    func terminalTitleDidChange(_ title: String)
    func terminalDirectoryDidChange(_ directory: URL?)
    func terminalProcessDidExit(exitCode: Int32?)
}

/// AppKit controller managing a SwiftTerm terminal
class TerminalController: NSViewController {
    private var terminalView: LocalProcessTerminalView!
    private var state: TerminalState
    
    weak var delegate: TerminalControllerDelegate?
    
    init(state: TerminalState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTerminalView()
        startShellProcess()
    }
    
    private func setupTerminalView() {
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.terminalDelegate = self
        
        // Configure appearance
        terminalView.configureNativeColors()
        
        view.addSubview(terminalView)
    }
    
    private func startShellProcess() {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        
        let shellName = (state.shell as NSString).lastPathComponent
        
        terminalView.startProcess(
            executable: state.shell,
            args: ["-l"], // Login shell
            environment: env,
            execName: shellName
        )
        
        // Change to initial working directory
        if FileManager.default.fileExists(atPath: state.workingDirectory.path) {
            let escapedPath = state.workingDirectory.path
                .replacingOccurrences(of: "\"", with: "\\\"")
            terminalView.send(txt: "cd \"\(escapedPath)\" && clear\n")
        }
    }
    
    // MARK: - Public API
    
    func sendText(_ text: String) {
        terminalView.send(txt: text)
    }
    
    func sendInterrupt() {
        terminalView.send([0x03]) // Ctrl+C
    }
    
    func sendEOF() {
        terminalView.send([0x04]) // Ctrl+D
    }
    
    func clear() {
        terminalView.send(txt: "clear\n")
    }
    
    func restartShell() {
        // Kill existing and restart
        terminalView.send([0x03]) // Ctrl+C first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startShellProcess()
        }
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        terminalView.frame = view.bounds
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalController: LocalProcessTerminalViewDelegate {
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            let url = URL(fileURLWithPath: dir)
            state.workingDirectory = url
            delegate?.terminalDirectoryDidChange(url)
        }
    }
    
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Terminal handles this internally
    }
    
    func setTerminalTitle(source: TerminalView, title: String) {
        state.title = title
        delegate?.terminalTitleDidChange(title)
    }
    
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        state.hasExited = true
        state.exitCode = exitCode
        delegate?.terminalProcessDidExit(exitCode: exitCode)
    }
}
```

**Validation**:
- [ ] Controller initializes without crash
- [ ] Shell process starts
- [ ] Terminal renders prompt
- [ ] Delegate methods fire correctly

**Commit**: `feat(terminal): create TerminalController with SwiftTerm`

---

### S7-04: Create TerminalPaneView (SwiftUI Wrapper)
**Description**: SwiftUI wrapper using NSViewControllerRepresentable.

**File**: `Panes/Terminal/TerminalPaneView.swift`

```swift
import SwiftUI

/// SwiftUI wrapper for TerminalController
public struct TerminalPaneView: NSViewControllerRepresentable {
    let paneId: UUID
    let state: TerminalState
    
    @Environment(\.canvasState) private var _canvas
    private var canvas: CanvasState { _canvas! }
    
    public init(paneId: UUID, state: TerminalState) {
        self.paneId = paneId
        self.state = state
    }
    
    public func makeNSViewController(context: Context) -> TerminalController {
        let controller = TerminalController(state: state)
        controller.delegate = context.coordinator
        return controller
    }
    
    public func updateNSViewController(_ controller: TerminalController, context: Context) {
        // State updates handled via delegate
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(paneId: paneId, canvas: canvas)
    }
    
    public class Coordinator: TerminalControllerDelegate {
        let paneId: UUID
        let canvas: CanvasState
        
        init(paneId: UUID, canvas: CanvasState) {
            self.paneId = paneId
            self.canvas = canvas
        }
        
        func terminalTitleDidChange(_ title: String) {
            canvas.updatePaneTitle(paneId, title: title)
        }
        
        func terminalDirectoryDidChange(_ directory: URL?) {
            // Could update pane subtitle or state
        }
        
        func terminalProcessDidExit(exitCode: Int32?) {
            // Could show visual indicator
        }
    }
}
```

**Validation**:
- [ ] Terminal renders in SwiftUI
- [ ] Terminal is interactive (keyboard input works)
- [ ] Title updates propagate to pane

**Commit**: `feat(terminal): create TerminalPaneView SwiftUI wrapper`

---

### S7-05: Wire Terminal into PaneContainerView
**Description**: Render TerminalPaneView for terminal pane type.

**File**: `Panes/Core/PaneContainerView.swift`

**Tasks**:
1. Import TerminalPaneView
2. Add case in paneContent switch:
```swift
case .terminal(let terminalState):
    TerminalPaneView(paneId: pane.id, state: terminalState)
```
3. Ensure terminal receives keyboard focus

**Validation**:
- [ ] Terminal pane renders correctly
- [ ] Can type in terminal
- [ ] Terminal receives keyboard input when clicked

**Commit**: `feat(terminal): wire terminal pane into container`

---

### S7-06: Implement New Terminal Command
**Description**: ⇧⌘T creates a new terminal pane at viewport center.

**File**: `ContentView.swift` (update existing handler)

**Tasks**:
1. Update `.onReceive(.newTerminal)` handler
2. Create terminal pane at viewport center
3. Use user's default shell and home directory
4. Select the new pane

```swift
.onReceive(NotificationCenter.default.publisher(for: .newTerminal)) { _ in
    let center = canvasState.viewportCenter(viewportSize: /* geometry.size */)
    let terminalState = TerminalState()
    canvasState.createPane(
        type: .terminal(terminalState),
        at: center,
        size: CGSize(width: 600, height: 400)
    )
}
```

**Validation**:
- [ ] ⇧⌘T creates terminal pane
- [ ] Terminal starts in home directory
- [ ] Multiple terminals can exist
- [ ] New terminal is selected

**Commit**: `feat(terminal): implement new terminal menu command`

---

### S7-07: Terminal Title and Directory Tracking
**Description**: Update pane title from terminal escape sequences.

**File**: `Canvas/CanvasState.swift` (add helper if not exists)

**Tasks**:
1. Ensure `updatePaneTitle(_:title:)` exists in CanvasState
2. Terminal title updates pane title bar
3. Show current directory in title or subtitle

**Validation**:
- [ ] Pane title updates when terminal title changes
- [ ] `cd` to directory updates title (if shell is configured)
- [ ] SSH session updates title

**Commit**: `feat(terminal): implement terminal title tracking`

---

### S7-08: Handle Terminal Process Exit
**Description**: Show exit status when shell process terminates.

**File**: `Panes/Terminal/TerminalPaneView.swift` (or new overlay)

**Tasks**:
1. Show exit code in terminal or as overlay
2. Visual indicator for exited terminal (dimmed, badge)
3. Option to restart shell (button or keyboard shortcut)
4. Handle ⌘W on exited terminal (close pane)

**Validation**:
- [ ] Exit code displayed when shell exits
- [ ] Can restart shell with button or shortcut
- [ ] Visual distinction for exited terminal
- [ ] `exit` command shows exit status

**Commit**: `feat(terminal): handle terminal process exit`

---

### S7-09: Implement File Drop to Terminal
**Description**: Drop files onto terminal to insert escaped path.

**File**: `Panes/Terminal/TerminalPaneView.swift`

**Tasks**:
1. Add `.onDrop` modifier to TerminalPaneView
2. Accept `.fileURL` drops
3. Insert escaped path at cursor position
4. Handle multiple files (space-separated)

```swift
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    for provider in providers {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            if let data = data as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                let escaped = url.path.replacingOccurrences(of: " ", with: "\\ ")
                DispatchQueue.main.async {
                    // Send to terminal
                }
            }
        }
    }
    return true
}
```

**Validation**:
- [ ] Dropping file inserts path
- [ ] Paths with spaces are escaped
- [ ] Multiple files separated by space
- [ ] Works with folders too

**Commit**: `feat(terminal): implement file drop to terminal`

---

### S7-10: Terminal Keyboard Focus
**Description**: Proper keyboard focus handling for terminal pane.

**File**: Multiple files

**Tasks**:
1. Terminal receives focus on click
2. Tab key works within terminal (not SwiftUI navigation)
3. ⌘+key shortcuts still work (copy, paste)
4. Escape key sends to terminal
5. Focus indicator visible

**Validation**:
- [ ] Clicking terminal focuses it
- [ ] Tab key sends to terminal, not navigation
- [ ] ⌘C copies from terminal selection
- [ ] ⌘V pastes to terminal
- [ ] Keyboard input goes to focused terminal

**Commit**: `feat(terminal): implement terminal focus handling`

---

### S7-11: Terminal Context Menu
**Description**: Right-click menu for terminal operations.

**File**: `Panes/Terminal/TerminalPaneView.swift`

**Tasks**:
1. Add context menu with:
   - Copy (⌘C)
   - Paste (⌘V)
   - Select All
   - Clear (⌘K)
   - Send Interrupt (Ctrl+C)
   - Send EOF (Ctrl+D)
   - Restart Shell
2. Wire up actions to TerminalController

**Validation**:
- [ ] Context menu appears on right-click
- [ ] Copy/Paste work correctly
- [ ] Clear clears terminal
- [ ] Interrupt sends Ctrl+C

**Commit**: `feat(terminal): add terminal context menu`

---

### S7-12: Write Terminal Unit Tests
**Description**: Tests for TerminalState and related logic.

**File**: `Tests/DevysFeatureTests/TerminalTests.swift`

**Tasks**:
1. Test TerminalState initialization
2. Test TerminalState Codable (encode/decode)
3. Test default values
4. Test path escaping helper

**Validation**:
- [ ] All tests pass
- [ ] Edge cases covered

**Commit**: `test(terminal): add terminal unit tests`

---

## File Structure After Sprint 7

```
DevysPackage/Sources/DevysFeature/
├── Panes/
│   ├── Core/
│   │   ├── Pane.swift
│   │   ├── PaneType.swift          # Updated with real TerminalState
│   │   ├── PaneContainerView.swift # Updated to render terminal
│   │   ├── PaneResizeHandles.swift
│   │   └── DraggablePaneView.swift
│   ├── Terminal/                    # NEW FOLDER
│   │   ├── TerminalState.swift
│   │   ├── TerminalController.swift
│   │   └── TerminalPaneView.swift
│   └── Snapping/
│       ├── SnapEngine.swift
│       └── SnapGuideView.swift
```

---

## Implementation Order

1. **S7-01**: TerminalState model
2. **S7-02**: Update PaneType
3. **S7-03**: TerminalController (core AppKit work)
4. **S7-04**: TerminalPaneView (SwiftUI wrapper)
5. **S7-05**: Wire into PaneContainerView
6. **S7-06**: New Terminal command → **First demo point!**
7. **S7-07**: Title tracking
8. **S7-08**: Process exit handling
9. **S7-10**: Keyboard focus (critical for usability)
10. **S7-09**: File drop
11. **S7-11**: Context menu
12. **S7-12**: Unit tests

---

## Key Technical Considerations

### SwiftTerm Integration
- `LocalProcessTerminalView` is the main class for local shell
- Must run on main thread
- Delegate pattern for events

### Keyboard Focus
- SwiftUI focus management can conflict with AppKit
- May need to use `NSViewControllerRepresentable` focus hooks
- Terminal should "capture" keyboard when clicked

### Performance
- SwiftTerm is well-optimized
- Avoid unnecessary state updates
- Terminal content not in SwiftUI state (managed by SwiftTerm)

### Sandbox Considerations
- App needs appropriate entitlements for process spawning
- May need to add `com.apple.security.cs.allow-unsigned-executable-memory`

---

## Definition of Done

Sprint 7 is complete when:
- [ ] Can create terminal panes via ⇧⌘T
- [ ] Terminal shows shell prompt and accepts input
- [ ] Can run commands and see output
- [ ] Can run `claude` or `codex` CLI tools
- [ ] Terminal title updates from shell
- [ ] Can close/delete terminal panes
- [ ] Multiple terminals work independently
- [ ] Basic copy/paste works
- [ ] All unit tests pass
