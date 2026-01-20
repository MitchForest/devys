# Devys

Agent-native terminal for macOS and iOS.

## Vision

A GPU-accelerated terminal designed for AI agent workflows:
- **Terminal pane**: Metal-rendered terminal with PTY support (macOS)
- **Orchestration UI**: SwiftUI surfaces for agent review, diffs, and approvals
- **Relay**: WebSocket bridge for iOS access to macOS terminal sessions

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           macOS App (SwiftUI)                           │
│                                                                         │
│  ┌────────────────┐  ┌─────────────────────┐  ┌──────────────────────┐ │
│  │   Sidebar      │  │   Timeline/Review   │  │   Inspector          │ │
│  │   (SwiftUI)    │  │   (SwiftUI)         │  │   (SwiftUI)          │ │
│  └────────────────┘  └─────────────────────┘  └──────────────────────┘ │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                Terminal Pane (MTKView + Metal)                    │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│                                    ↕ PTY                                │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  Terminal Core (Swift)                                            │  │
│  │  - Screen buffer (cells, scrollback)                              │  │
│  │  - VT parser (ANSI escape codes)                                  │  │
│  │  - PTY wrapper (forkpty, read/write)                              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│                           ↕ WebSocket (relay)                           │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                           iOS App (SwiftUI)                             │
│  Same Metal renderer, receives screen state over WebSocket              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
devys/
├── Devys/                    # macOS app (Xcode project)
│   ├── App/                  # App entry, scenes, menus
│   ├── Terminal/             # Terminal core
│   │   ├── Screen/           # Grid, cells, scrollback
│   │   ├── Parser/           # VT/ANSI state machine
│   │   └── PTY/              # forkpty wrapper
│   ├── Renderer/             # Metal rendering
│   │   ├── Shaders/          # .metal files
│   │   └── GlyphAtlas/       # Core Text → MTLTexture
│   └── UI/                   # SwiftUI views
├── DevysRemote/              # iOS app (shares Terminal + Renderer)
├── Shared/                   # Shared Swift packages
│   ├── TerminalCore/         # Screen, Parser (no PTY)
│   └── TerminalRenderer/     # Metal rendering
├── fixtures/                 # Agent stream fixtures
├── _archive/                 # Previous Rust/GPUI implementation
└── .docs/                    # Specs, plans, notes
```

## Reference

The `_archive/rust-gpui/` folder contains the previous Rust/GPUI implementation:
- `screen/`: VT parser and grid model (port to Swift)
- `agent/`: Event schema and adapters (reference for Swift implementation)
- `fixtures/`: Reusable agent stream fixtures

## Commands

```bash
# Build macOS app
xcodebuild -project Devys/Devys.xcodeproj -scheme Devys -configuration Debug build

# Run tests
xcodebuild test -project Devys/Devys.xcodeproj -scheme Devys -destination 'platform=macOS'
```
