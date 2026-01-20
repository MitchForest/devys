# Sprint 8: Browser Pane - Comprehensive Plan

## Goal
Functional embedded browser panes using WKWebView for previewing localhost dev servers, web documentation, and production sites.

## Demo
⇧⌘B → browser pane appears → navigate to localhost:3000 → back/forward/reload → URL bar updates → dev tools accessible.

---

## Progress Tracker

| Ticket | Title | Status | Commit |
|--------|-------|--------|--------|
| S8-01 | Enhance BrowserPaneState Model | ⬜ Not Started | |
| S8-02 | Create WebViewStore Observable | ⬜ Not Started | |
| S8-03 | Create BrowserWebView (NSViewRepresentable) | ⬜ Not Started | |
| S8-04 | Create Browser Toolbar | ⬜ Not Started | |
| S8-05 | Create BrowserPaneView | ⬜ Not Started | |
| S8-06 | Wire Browser into PaneContainerView | ⬜ Not Started | |
| S8-07 | Verify New Browser Menu Command | ⬜ Not Started | |
| S8-08 | Handle Loading States & Errors | ⬜ Not Started | |
| S8-09 | Implement URL Drag-Drop | ⬜ Not Started | |
| S8-10 | Browser DevTools Integration | ⬜ Not Started | |
| S8-11 | Browser Keyboard Focus | ⬜ Not Started | |
| S8-12 | Browser Context Menu | ⬜ Not Started | |
| S8-13 | Localhost Quick Access | ⬜ Not Started | |
| S8-14 | Write Browser Unit Tests | ⬜ Not Started | |

**Legend**: ⬜ Not Started | 🔄 In Progress | ✅ Complete | ⏸️ Blocked

---

## Prerequisites (Already Done)
- [x] Pane infrastructure (PaneType, PaneContainerView, etc.)
- [x] ⇧⌘B menu command wired up (creates placeholder)
- [x] BrowserPaneState placeholder exists in PaneType.swift
- [x] CanvasState.updatePaneTitle() implemented

---

## Tickets

### S8-01: Enhance BrowserPaneState Model
**Status**: ⬜ Not Started

**Description**: Expand the existing `BrowserPaneState` to track full browser state including navigation history and loading status.

**File**: `Panes/Browser/BrowserState.swift` (new file)

**Tasks**:
- [ ] Create `Panes/Browser/` folder
- [ ] Create `BrowserState.swift` with enhanced model
- [ ] Add navigation state properties:
  - `url: URL` (current URL)
  - `canGoBack: Bool`
  - `canGoForward: Bool`
  - `isLoading: Bool`
  - `title: String` (page title)
  - `loadProgress: Double` (0.0-1.0)
- [ ] Add Codable conformance (only persist URL)
- [ ] Add convenience initializers for common URLs (localhost ports)
- [ ] Update `PaneType.swift` to use new location (or keep inline)

**Code**:
```swift
import Foundation

/// State for a browser pane.
///
/// Contains both configuration (persisted) and runtime state (transient).
/// Only the URL is encoded/decoded for persistence.
public struct BrowserState: Equatable, Codable, Hashable {
    // MARK: - Configuration (Persisted)
    
    /// Current URL
    public var url: URL
    
    // MARK: - Runtime State (Transient)
    
    /// Page title
    public var title: String
    
    /// Whether page is currently loading
    public var isLoading: Bool
    
    /// Load progress (0.0 to 1.0)
    public var loadProgress: Double
    
    /// Whether browser can navigate back
    public var canGoBack: Bool
    
    /// Whether browser can navigate forward
    public var canGoForward: Bool
    
    /// Error message if load failed
    public var errorMessage: String?
    
    // MARK: - Initialization
    
    public init(
        url: URL = URL(string: "http://localhost:3000")!,
        title: String = "Browser"
    ) {
        self.url = url
        self.title = title
        self.isLoading = false
        self.loadProgress = 0
        self.canGoBack = false
        self.canGoForward = false
        self.errorMessage = nil
    }
    
    /// Convenience initializer for localhost with specific port
    public static func localhost(port: Int) -> BrowserState {
        BrowserState(url: URL(string: "http://localhost:\(port)")!)
    }
    
    // MARK: - Codable (Only persist URL)
    
    enum CodingKeys: String, CodingKey {
        case url
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        // Runtime state defaults
        title = "Browser"
        isLoading = false
        loadProgress = 0
        canGoBack = false
        canGoForward = false
        errorMessage = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
    }
}

// MARK: - URL Helpers

extension BrowserState {
    /// Normalize a URL string (add https:// if no scheme)
    public static func normalizeURLString(_ string: String) -> URL? {
        var urlString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no scheme, add https:// (unless localhost)
        if !urlString.contains("://") {
            if urlString.hasPrefix("localhost") || urlString.hasPrefix("127.0.0.1") {
                urlString = "http://" + urlString
            } else {
                urlString = "https://" + urlString
            }
        }
        
        return URL(string: urlString)
    }
    
    /// Common localhost ports for dev servers
    public static let commonPorts: [(name: String, port: Int)] = [
        ("Next.js / React", 3000),
        ("Vite", 5173),
        ("Angular", 4200),
        ("Django / Python", 8000),
        ("Generic", 8080),
        ("Rails", 3001),
    ]
}
```

**Validation**:
- [ ] BrowserState is Equatable and Codable
- [ ] Default URL is `http://localhost:3000`
- [ ] Only URL is persisted to disk
- [ ] URL normalization adds scheme correctly

**Commit**: `feat(browser): enhance BrowserState model`

---

### S8-02: Create WebViewStore Observable
**Status**: ⬜ Not Started

**Description**: Observable store that bridges WKWebView state to SwiftUI, tracking navigation state and providing control methods.

**File**: `Panes/Browser/WebViewStore.swift`

**Tasks**:
- [ ] Create `@Observable` class `WebViewStore`
- [ ] Add published properties for navigation state
- [ ] Add navigation methods (goBack, goForward, reload, etc.)
- [ ] Add weak reference to WKWebView
- [ ] Handle URL normalization

**Code**:
```swift
import Foundation
import WebKit
import Observation

/// Observable store bridging WKWebView state to SwiftUI.
///
/// Tracks navigation state and provides control methods for the webview.
@MainActor
@Observable
public final class WebViewStore {
    // MARK: - State
    
    /// Current URL
    public var currentURL: URL
    
    /// Page title
    public var title: String = ""
    
    /// Whether browser can go back
    public var canGoBack: Bool = false
    
    /// Whether browser can go forward
    public var canGoForward: Bool = false
    
    /// Whether page is loading
    public var isLoading: Bool = false
    
    /// Load progress (0.0 to 1.0)
    public var loadProgress: Double = 0
    
    /// Error message if load failed
    public var errorMessage: String?
    
    // MARK: - WebView Reference
    
    /// Weak reference to the managed WKWebView
    public weak var webView: WKWebView?
    
    // MARK: - Callbacks
    
    /// Called when title changes
    public var onTitleChange: ((String) -> Void)?
    
    // MARK: - Initialization
    
    public init(initialURL: URL = URL(string: "http://localhost:3000")!) {
        self.currentURL = initialURL
    }
    
    // MARK: - Navigation Methods
    
    public func goBack() {
        webView?.goBack()
    }
    
    public func goForward() {
        webView?.goForward()
    }
    
    public func reload() {
        webView?.reload()
    }
    
    public func stopLoading() {
        webView?.stopLoading()
    }
    
    public func load(url: URL) {
        currentURL = url
        webView?.load(URLRequest(url: url))
    }
    
    public func load(urlString: String) {
        guard let url = BrowserState.normalizeURLString(urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        load(url: url)
    }
    
    // MARK: - State Updates (called by Coordinator)
    
    func updateNavigationState(from webView: WKWebView) {
        currentURL = webView.url ?? currentURL
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        loadProgress = webView.estimatedProgress
        
        onTitleChange?(title)
    }
    
    func handleLoadError(_ error: Error) {
        isLoading = false
        
        let nsError = error as NSError
        
        // Provide user-friendly error messages
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            if currentURL.host == "localhost" || currentURL.host == "127.0.0.1" {
                errorMessage = "Cannot connect to localhost:\(currentURL.port ?? 80). Is your dev server running?"
            } else {
                errorMessage = "Cannot connect to server"
            }
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "No internet connection"
        case NSURLErrorTimedOut:
            errorMessage = "Connection timed out"
        case NSURLErrorCancelled:
            errorMessage = nil // User cancelled, not an error
        default:
            errorMessage = error.localizedDescription
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}
```

**Validation**:
- [ ] Store updates when WKWebView navigates
- [ ] Methods control WKWebView correctly
- [ ] No retain cycles (weak webView reference)
- [ ] Error messages are user-friendly

**Commit**: `feat(browser): create WebViewStore observable`

---

### S8-03: Create BrowserWebView (NSViewRepresentable)
**Status**: ⬜ Not Started

**Description**: SwiftUI wrapper for WKWebView with proper delegate setup and state synchronization.

**File**: `Panes/Browser/BrowserWebView.swift`

**Tasks**:
- [ ] Create `BrowserWebView: NSViewRepresentable`
- [ ] Configure WKWebView (dev extras, JavaScript, gestures)
- [ ] Set up `WKNavigationDelegate`
- [ ] Set up KVO observers for state changes
- [ ] Clean up observers in Coordinator deinit

**Code**:
```swift
import SwiftUI
import WebKit

/// SwiftUI wrapper for WKWebView.
public struct BrowserWebView: NSViewRepresentable {
    let store: WebViewStore
    let initialURL: URL
    
    public init(store: WebViewStore, initialURL: URL) {
        self.store = store
        self.initialURL = initialURL
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable developer extras (Inspect Element)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Allow JavaScript
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Store reference
        store.webView = webView
        
        // Set up KVO observers
        context.coordinator.setupObservers(for: webView)
        
        // Load initial URL
        webView.load(URLRequest(url: initialURL))
        
        return webView
    }
    
    public func updateNSView(_ webView: WKWebView, context: Context) {
        // State updates handled via KVO and delegate
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    // MARK: - Coordinator
    
    public class Coordinator: NSObject, WKNavigationDelegate {
        let store: WebViewStore
        private var observations: [NSKeyValueObservation] = []
        
        init(store: WebViewStore) {
            self.store = store
        }
        
        deinit {
            observations.removeAll()
        }
        
        func setupObservers(for webView: WKWebView) {
            observations = [
                webView.observe(\.url) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.title) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoBack) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoForward) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.isLoading) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.loadProgress = webView.estimatedProgress
                    }
                }
            ]
        }
        
        // MARK: - WKNavigationDelegate
        
        public func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            Task { @MainActor in
                store.isLoading = true
                store.clearError()
            }
        }
        
        public func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            Task { @MainActor in
                store.isLoading = false
                store.updateNavigationState(from: webView)
            }
        }
        
        public func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                store.handleLoadError(error)
            }
        }
        
        public func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                store.handleLoadError(error)
            }
        }
    }
}
```

**Validation**:
- [ ] WebView renders in SwiftUI
- [ ] Navigation events update WebViewStore
- [ ] Progress observable
- [ ] Dev tools available via right-click
- [ ] KVO observers clean up properly

**Commit**: `feat(browser): create BrowserWebView wrapper`

---

### S8-04: Create Browser Toolbar
**Status**: ⬜ Not Started

**Description**: Navigation controls bar with back, forward, reload, and URL text field.

**File**: `Panes/Browser/BrowserToolbar.swift`

**Tasks**:
- [ ] Create `BrowserToolbar` view
- [ ] Add navigation buttons (back, forward, reload/stop)
- [ ] Add URL text field with editing
- [ ] Add progress bar
- [ ] Style consistently with app theme

**Code**:
```swift
import SwiftUI

/// Navigation toolbar for browser pane.
public struct BrowserToolbar: View {
    let store: WebViewStore
    @State private var urlText: String = ""
    @State private var isEditingURL: Bool = false
    @FocusState private var isURLFieldFocused: Bool
    
    public init(store: WebViewStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Back button
                Button(action: { store.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoBack)
                .help("Go Back")
                
                // Forward button
                Button(action: { store.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoForward)
                .help("Go Forward")
                
                // Reload/Stop button
                Button(action: {
                    if store.isLoading {
                        store.stopLoading()
                    } else {
                        store.reload()
                    }
                }) {
                    Image(systemName: store.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(store.isLoading ? "Stop Loading" : "Reload")
                
                // URL field
                TextField("Enter URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        store.load(urlString: urlText)
                        isURLFieldFocused = false
                    }
                    .onChange(of: isURLFieldFocused) { _, focused in
                        if focused {
                            // Select all when focused
                            urlText = store.currentURL.absoluteString
                        }
                    }
                    .onChange(of: store.currentURL) { _, newURL in
                        if !isURLFieldFocused {
                            urlText = newURL.absoluteString
                        }
                    }
                    .onAppear {
                        urlText = store.currentURL.absoluteString
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // Progress bar
            if store.isLoading {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * store.loadProgress)
                }
                .frame(height: 2)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

**Validation**:
- [ ] Buttons control navigation
- [ ] URL field shows current URL
- [ ] Enter in URL field navigates
- [ ] Progress bar shows during load
- [ ] Buttons disabled when not applicable
- [ ] URL field selects all on focus

**Commit**: `feat(browser): create browser toolbar`

---

### S8-05: Create BrowserPaneView
**Status**: ⬜ Not Started

**Description**: Complete browser pane combining toolbar and webview with state management.

**File**: `Panes/Browser/BrowserPaneView.swift`

**Tasks**:
- [ ] Create `BrowserPaneView` accepting `paneId` and `BrowserPaneState`
- [ ] Compose toolbar and webview
- [ ] Create and manage `WebViewStore`
- [ ] Wire up title changes to canvas
- [ ] Handle error display

**Code**:
```swift
import SwiftUI

/// Complete browser pane with toolbar and webview.
public struct BrowserPaneView: View {
    let paneId: UUID
    let state: BrowserPaneState
    
    @Environment(\.canvasState) private var _canvas
    private var canvas: CanvasState { _canvas! }
    
    @State private var store: WebViewStore
    
    public init(paneId: UUID, state: BrowserPaneState) {
        self.paneId = paneId
        self.state = state
        self._store = State(wrappedValue: WebViewStore(
            initialURL: state.url ?? URL(string: "http://localhost:3000")!
        ))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(store: store)
            
            ZStack {
                BrowserWebView(
                    store: store,
                    initialURL: state.url ?? URL(string: "http://localhost:3000")!
                )
                
                // Error overlay
                if let error = store.errorMessage {
                    errorOverlay(message: error)
                }
            }
        }
        .onAppear {
            store.onTitleChange = { title in
                Task { @MainActor in
                    canvas.updatePaneTitle(paneId, title: title.isEmpty ? "Browser" : title)
                }
            }
        }
    }
    
    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                store.clearError()
                store.reload()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

**Validation**:
- [ ] Toolbar and webview render correctly
- [ ] Navigation works end-to-end
- [ ] Pane title updates from page title
- [ ] Error overlay shows on load failure
- [ ] Retry button works

**Commit**: `feat(browser): create BrowserPaneView`

---

### S8-06: Wire Browser into PaneContainerView
**Status**: ⬜ Not Started

**Description**: Replace placeholder content with real `BrowserPaneView`.

**File**: `Panes/Core/PaneContainerView.swift`

**Tasks**:
- [ ] Update `paneContent` switch for `.browser` case
- [ ] Remove placeholder content for browser
- [ ] Ensure imports are correct

**Changes**:
```swift
// In paneContent computed property, change:
case .browser(let state):
    PlaceholderContent(...)

// To:
case .browser(let state):
    BrowserPaneView(paneId: pane.id, state: state)
```

**Validation**:
- [ ] Browser pane renders real webview
- [ ] Pane title updates from page title
- [ ] Multiple browsers can coexist

**Commit**: `feat(browser): wire browser pane into container`

---

### S8-07: Verify New Browser Menu Command
**Status**: ⬜ Not Started

**Description**: Verify ⇧⌘B works correctly and creates browser at viewport center.

**File**: `ContentView.swift` (already has handler)

**Tasks**:
- [ ] Test ⇧⌘B creates browser pane
- [ ] Verify default URL is localhost:3000
- [ ] Verify browser appears at viewport center
- [ ] Verify pane is selected after creation

**Validation**:
- [ ] ⇧⌘B creates browser pane
- [ ] Opens localhost:3000 by default
- [ ] Multiple browsers work independently
- [ ] Browser is selected after creation

**Commit**: `test(browser): verify new browser menu command`

---

### S8-08: Handle Loading States & Errors
**Status**: ⬜ Not Started

**Description**: Visual feedback during page load and graceful error handling.

**File**: `Panes/Browser/BrowserWebView.swift`, `BrowserPaneView.swift`

**Tasks**:
- [ ] Progress bar visible during load
- [ ] Reload button becomes stop button when loading
- [ ] Handle common errors:
  - Connection refused (localhost not running)
  - DNS resolution failure
  - SSL certificate errors
  - Timeout
- [ ] Display error state with retry button
- [ ] Special handling for localhost errors

**Validation**:
- [ ] Progress bar visible during load
- [ ] Stop button cancels load
- [ ] Errors show helpful message
- [ ] Retry button reloads
- [ ] Localhost errors suggest starting dev server

**Commit**: `feat(browser): handle loading states and errors`

---

### S8-09: Implement URL Drag-Drop
**Status**: ⬜ Not Started

**Description**: Drag URLs to browser to navigate, drag URL from browser to terminal.

**File**: `Panes/Browser/BrowserPaneView.swift`, `BrowserToolbar.swift`

**Tasks**:
- [ ] Accept URL drops on browser pane
- [ ] Make URL bar draggable
- [ ] Handle dropped URLs in terminal (inserts as text)

**Validation**:
- [ ] Dropping URL navigates browser
- [ ] Can drag URL from address bar
- [ ] Dropped URL in terminal inserts as text

**Commit**: `feat(browser): implement URL drag-drop`

---

### S8-10: Browser DevTools Integration
**Status**: ⬜ Not Started

**Description**: Quick access to Web Inspector for debugging web content.

**File**: `Panes/Browser/BrowserWebView.swift`

**Tasks**:
- [ ] Enable developer extras in WKWebView configuration
- [ ] Verify "Inspect Element" appears in context menu
- [ ] Test that Web Inspector opens correctly

**Validation**:
- [ ] Right-click → Inspect Element works
- [ ] Developer tools window opens
- [ ] Console, Network, Elements tabs available

**Commit**: `feat(browser): add devtools integration`

---

### S8-11: Browser Keyboard Focus
**Status**: ⬜ Not Started

**Description**: Proper keyboard focus handling for browser pane.

**File**: `Panes/Browser/BrowserWebView.swift`, `BrowserPaneView.swift`

**Tasks**:
- [ ] Browser receives focus on click
- [ ] Keyboard input goes to webview
- [ ] Standard web shortcuts work (⌘+/-, ⌘F, Tab)
- [ ] ⌘L focuses URL bar
- [ ] Escape exits URL bar focus

**Validation**:
- [ ] Clicking browser focuses it
- [ ] Can type in web forms
- [ ] ⌘L focuses URL bar
- [ ] Standard browser shortcuts work

**Commit**: `feat(browser): implement browser focus handling`

---

### S8-12: Browser Context Menu
**Status**: ⬜ Not Started

**Description**: Right-click menu for browser operations.

**File**: `Panes/Browser/BrowserWebView.swift`

**Tasks**:
- [ ] Add custom context menu items:
  - Back (if can go back)
  - Forward (if can go forward)
  - Reload
  - Copy URL
  - Open in Default Browser
  - Inspect Element
- [ ] Keep native context menu items for copy/paste

**Validation**:
- [ ] Context menu appears on right-click
- [ ] Navigation items work
- [ ] Copy URL copies current URL
- [ ] Open in Default Browser opens Safari/Chrome

**Commit**: `feat(browser): add browser context menu`

---

### S8-13: Localhost Quick Access
**Status**: ⬜ Not Started

**Description**: Quick buttons or menu for common localhost ports.

**File**: `Panes/Browser/BrowserToolbar.swift`

**Tasks**:
- [ ] Add port presets dropdown/menu in toolbar
- [ ] Include common ports:
  - localhost:3000 (Next.js, React)
  - localhost:5173 (Vite)
  - localhost:8080 (generic)
  - localhost:4200 (Angular)
  - localhost:8000 (Django, Python)
- [ ] One-click navigation to common ports

**Validation**:
- [ ] Dropdown shows common ports
- [ ] Clicking navigates to port
- [ ] Works with http protocol

**Commit**: `feat(browser): add localhost quick access`

---

### S8-14: Write Browser Unit Tests
**Status**: ⬜ Not Started

**Description**: Tests for browser state and utilities.

**File**: `Tests/DevysFeatureTests/BrowserTests.swift`

**Tasks**:
- [ ] Test `BrowserState` initialization
- [ ] Test Codable round-trip (only URL persisted)
- [ ] Test URL normalization helper
- [ ] Test localhost port helpers

**Validation**:
- [ ] All tests pass
- [ ] Edge cases covered

**Commit**: `test(browser): add browser unit tests`

---

## File Structure After Sprint 8

```
DevysPackage/Sources/DevysFeature/
├── Panes/
│   ├── Browser/                    # NEW FOLDER
│   │   ├── BrowserState.swift      # Enhanced state model
│   │   ├── WebViewStore.swift      # Observable for WKWebView
│   │   ├── BrowserWebView.swift    # NSViewRepresentable
│   │   ├── BrowserToolbar.swift    # Navigation controls
│   │   └── BrowserPaneView.swift   # Complete pane view
│   ├── Core/
│   │   ├── Pane.swift
│   │   ├── PaneType.swift
│   │   ├── PaneContainerView.swift # Updated to use real browser
│   │   ├── PaneResizeHandles.swift
│   │   └── DraggablePaneView.swift
│   ├── Snapping/
│   │   ├── SnapEngine.swift
│   │   └── SnapGuideView.swift
│   └── Terminal/
│       ├── ActivityTrackingTerminalView.swift
│       ├── TerminalController.swift
│       ├── TerminalPaneView.swift
│       └── TerminalState.swift
└── Tests/
    └── DevysFeatureTests/
        └── BrowserTests.swift      # NEW FILE
```

---

## Implementation Order

1. **S8-01**: BrowserState model enhancement
2. **S8-02**: WebViewStore observable
3. **S8-03**: BrowserWebView wrapper (core WKWebView integration)
4. **S8-04**: BrowserToolbar
5. **S8-05**: BrowserPaneView (combines components)
6. **S8-06**: Wire into PaneContainerView → **First demo point!**
7. **S8-07**: Verify menu command
8. **S8-08**: Loading states & errors
9. **S8-11**: Keyboard focus (critical for usability)
10. **S8-10**: DevTools integration
11. **S8-12**: Context menu
12. **S8-09**: URL drag-drop
13. **S8-13**: Localhost quick access
14. **S8-14**: Unit tests

---

## Definition of Done

Sprint 8 is complete when:
- [ ] ⇧⌘B creates browser pane with real WKWebView
- [ ] Browser loads localhost:3000 by default
- [ ] Back/Forward/Reload buttons work
- [ ] URL bar shows current URL and allows navigation
- [ ] Progress bar shows during page load
- [ ] Page title updates pane title
- [ ] Can right-click → Inspect Element
- [ ] Multiple browsers work independently
- [ ] Errors display helpful messages
- [ ] All unit tests pass

---

## Notes

### Key Technical Considerations

#### WKWebView Integration
- Use `NSViewRepresentable` (not `UIViewRepresentable`)
- Enable developer extras for Web Inspector
- Use KVO for state observation (URL, title, canGoBack, etc.)
- Handle navigation delegate for load events

#### Keyboard Focus
- WKWebView needs to become first responder
- May need to handle focus coordination with SwiftUI
- URL bar should capture ⌘L shortcut

#### Localhost Handling
- Default to http:// for localhost (not https)
- Provide helpful error messages when server not running
- Quick access to common dev server ports

### Dependencies
- WebKit framework (already available on macOS)
- No new SPM dependencies required

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-20 | Initial sprint plan created |
