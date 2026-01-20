# Devys - Visual Canvas for Software Development 2.0

A native macOS infinite canvas for orchestrating AI coding agents, terminals, browsers, and development workflows. Built for developers who direct AI agents rather than write code directly.

## Keyboard Shortcuts

### Canvas Navigation
| Action | Shortcut |
|--------|----------|
| Pan canvas | Drag on background |
| Zoom in/out | ⌘+ / ⌘- or pinch gesture |
| Zoom with trackpad | Two-finger scroll (hold ⌘ during momentum) |
| Zoom to 100% | ⌘1 |
| Zoom to fit | ⌘0 |

### Pane Management
| Action | Shortcut |
|--------|----------|
| Select pane | Click |
| Multi-select | ⇧-click or ⌘-click |
| Move pane | Drag pane |
| Delete selected | Delete or ⌫ |
| Duplicate pane | ⌘D |
| Close pane | ⌘W |
| Toggle fullscreen | ⌘Return |

### Grouping
| Action | Shortcut |
|--------|----------|
| Group selected | ⌘G |
| Ungroup | ⇧⌘G |
| Auto-group | Snap panes edge-to-edge |

### Create Panes
| Action | Shortcut |
|--------|----------|
| New Terminal | ⇧⌘T |
| New Browser | ⇧⌘B |
| New File Explorer | ⇧⌘E |
| New Code Editor | ⌥⌘N |
| New Git | ⇧⌘G |
| New Canvas | ⇧⌘N |

## Features

- **Infinite Canvas**: Pan and zoom with native macOS gestures
- **Draggable Panes**: Terminal, browser, file explorer, code editor, git panes
- **Snap & Group**: Panes snap together and auto-group for unified movement
- **Resize Handles**: Corner and edge handles for precise sizing
- **Visual Guides**: Alignment guides appear when snapping

## Project Architecture

```
Devys/
├── Devys.xcworkspace/              # Open this file in Xcode
├── Devys.xcodeproj/                # App shell project
├── Devys/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── DevysApp.swift              # App entry point
│   ├── Devys.entitlements          # App sandbox settings
│   └── Devys.xctestplan            # Test configuration
├── DevysPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/DevysFeature/       # Your feature code
│   └── Tests/DevysFeatureTests/    # Unit tests
└── DevysUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `Devys/` contains minimal app lifecycle code
- **Feature Code**: `DevysPackage/Sources/DevysFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `Devys.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `DevysPackage/Sources/DevysFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `DevysPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "DevysFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `DevysPackage/Tests/DevysFeatureTests/` (Swift Testing framework)
- **UI Tests**: `DevysUITests/` (XCUITest framework)
- **Test Plan**: `Devys.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `Devys/Devys.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct DevysApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `Devys/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "DevysFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.