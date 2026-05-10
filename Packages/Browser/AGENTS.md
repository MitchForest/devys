# Browser Package Guide

This package provides the embedded browser surface used by Devys for local app preview and web-based workflows.

## Package Role

`Packages/Browser` owns:

- `BrowserSession`, the `@Observable` session object that lazily creates and retains a `WKWebView`
- `BrowserContentView`, the SwiftUI view that renders browser controls and the hosted web view
- browser-specific navigation, load-state, and error presentation inside the browser surface

`Packages/Browser` does not own:

- app shell state
- pane/tab topology
- browser tab lifecycle policy
- persistence or relaunch policy
- workspace-level session registries

Those concerns belong to reducer-owned `AppFeatures` state and the narrow host/runtime adapters in `Apps/mac-client`.

## Integration Rules

- The reducer owns browser tab identity and presentation policy through `WorkspaceTabContent`.
- The host owns live `BrowserSession` objects in a focused cache. Do not move `WKWebView` or other engine handles into reducer state.
- Browser metadata that affects visible app behavior should publish back into reducer-owned hosted content summaries rather than becoming host-owned truth.
- Keep this package UI-focused. If future browser automation is added, the automation boundary must stay explicit and must not bypass reducer-owned app behavior.

## Current Shape

- `BrowserSession.swift`
  Observable session with navigation state, current URL, title, loading progress, and lazy `WKWebView` creation.
- `BrowserContentView.swift`
  Browser chrome plus `WKWebView` hosting for a single session.

## Usage

```swift
import Browser

let session = BrowserSession(url: URL(string: "http://localhost:3000")!)
BrowserContentView(session: session)
```
