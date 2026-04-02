# DevysBrowser

Browser integration for Devys - provides an embedded WKWebView browser for web development workflows.

## Overview

DevysBrowser provides a native browser pane that can be opened as a tab in Devys. It's designed for:

- Previewing local development servers (localhost:3000, :5173, etc.)
- Testing web applications during development
- Viewing documentation and web resources

## Architecture

### Components

| File | Purpose |
|------|---------|
| `BrowserSession.swift` | Observable session managing WKWebView state and navigation |
| `BrowserContentView.swift` | SwiftUI view with toolbar and WebView |

### BrowserSession

The core state management class:

```swift
@MainActor @Observable
public final class BrowserSession: Identifiable {
    let id: UUID
    var tabTitle: String
    var tabIcon: String
}
```

### BrowserContentView

The main view component:

- Navigation toolbar (back, forward, reload, URL field)
- Common localhost ports menu
- Loading progress indicator
- Error overlay with retry

## Integration with Devys

Browser tabs are created via:

1. Click the globe icon in the FeatureRail
2. Tab type: `.browser(id: UUID)`
3. Session stored in `browserSessions[id]`

## Future: Agent Automation (Step 2)

The next phase will add:

- `DevysBrowserService` - Full automation API (click, fill, snapshot, etc.)
- `DevysBrowserSocketServer` - Unix socket server for CLI access
- `AccessibilityTreeBuilder.js` - JavaScript for building accessibility tree with refs
- `devys-browser` CLI - Command-line interface for automation

This will enable AI agents (Claude Code, Codex) to:
- Navigate to URLs
- Take accessibility snapshots
- Interact with elements (click, fill, type)
- Wait for conditions
- Take screenshots

## Usage

```swift
import DevysBrowser

// Create a session
let session = BrowserSession(url: URL(string: "http://localhost:3000")!)

// Use in a view
BrowserContentView(session: session)
```

## Building

The package is included in the Devys workspace. Build with:

```bash
cd /path/to/devys
xcodebuild -scheme Devys build
```

Or open the Xcode project and build.
