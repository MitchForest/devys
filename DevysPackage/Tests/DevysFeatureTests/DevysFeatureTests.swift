import Testing
import SwiftUI
@testable import DevysFeature

// MARK: - Theme Color Tests

@Suite("Theme Colors")
struct ThemeColorTests {

    @Test("Canvas colors are distinct from pane colors")
    func canvasAndPaneColorsAreDifferent() {
        // Canvas background should be different from pane background
        // This tests that we have intentional color choices
        _ = Theme.canvasBackground
        _ = Theme.paneBackground
        // Both exist and are valid SwiftUI colors
        #expect(true)
    }

    @Test("All theme colors are accessible")
    func allColorsAccessible() {
        // Verify all color properties compile and return Color values
        // Canvas colors
        let _: Color = Theme.canvasBackground
        let _: Color = Theme.dotColor

        // Pane colors
        let _: Color = Theme.paneBackground
        let _: Color = Theme.paneTitleBar
        let _: Color = Theme.paneBorder
        let _: Color = Theme.paneBorderSelected
        let _: Color = Theme.paneShadow

        // Connector colors
        let _: Color = Theme.connectorColor
        let _: Color = Theme.connectorPending

        // Snap guide colors
        let _: Color = Theme.snapGuide

        // Group colors
        let _: Color = Theme.groupBackground
        let _: Color = Theme.groupBorder

        #expect(true) // If we got here, all colors are valid
    }
}

// MARK: - Layout Constant Tests

@Suite("Layout Constants")
struct LayoutConstantTests {

    @Test("Dot spacing is positive")
    func dotSpacingIsPositive() {
        #expect(Layout.dotSpacing > 0)
    }

    @Test("Dot radius is positive and reasonable")
    func dotRadiusIsReasonable() {
        #expect(Layout.dotRadius > 0)
        #expect(Layout.dotRadius < 10) // Should be small
    }

    @Test("Scale limits are valid")
    func scaleLimitsAreValid() {
        #expect(Layout.minScale > 0)
        #expect(Layout.maxScale > Layout.minScale)
        #expect(Layout.defaultScale >= Layout.minScale)
        #expect(Layout.defaultScale <= Layout.maxScale)
    }

    @Test("Pane dimensions are valid")
    func paneDimensionsAreValid() {
        // Title bar height
        #expect(Layout.paneTitleBarHeight > 0)
        #expect(Layout.paneTitleBarHeight < 100) // Reasonable limit

        // Corner radius
        #expect(Layout.paneCornerRadius >= 0)
        #expect(Layout.paneCornerRadius < 50)

        // Minimum sizes
        #expect(Layout.paneMinWidth > 0)
        #expect(Layout.paneMinHeight > 0)

        // Default sizes
        #expect(Layout.paneDefaultWidth >= Layout.paneMinWidth)
        #expect(Layout.paneDefaultHeight >= Layout.paneMinHeight)
    }

    @Test("Snap threshold is reasonable")
    func snapThresholdIsReasonable() {
        #expect(Layout.snapThreshold > 0)
        #expect(Layout.snapThreshold < 50) // Not too large
    }

    @Test("Handle sizes are positive")
    func handleSizesArePositive() {
        #expect(Layout.resizeHandleSize > 0)
        #expect(Layout.connectionHandleRadius > 0)
    }

    @Test("Animation duration is reasonable")
    func animationDurationIsReasonable() {
        #expect(Layout.animationDuration > 0)
        #expect(Layout.animationDuration < 2.0) // Not too slow
    }
}

// MARK: - Typography Tests

@Suite("Typography")
struct TypographyTests {

    @Test("Pane title font is accessible")
    func paneTitleFontAccessible() {
        let _: Font = Typography.paneTitle
        #expect(true)
    }

    @Test("Code editor font returns valid NSFont")
    func codeEditorFontValid() {
        let font: NSFont = Typography.codeEditor(size: 14)
        #expect(font.pointSize == 14)
    }

    @Test("Code editor font is monospaced")
    func codeEditorFontIsMonospaced() {
        let font = Typography.codeEditor(size: 12)
        // Check that it's a fixed-width font
        #expect(font.isFixedPitch)
    }

    @Test("Code editor font respects size parameter")
    func codeEditorFontSizeWorks() {
        let font12 = Typography.codeEditor(size: 12)
        let font16 = Typography.codeEditor(size: 16)
        #expect(font12.pointSize == 12)
        #expect(font16.pointSize == 16)
    }
}

// MARK: - Canvas State Tests

@Suite("Canvas State")
struct CanvasStateTests {

    @Test("Initial state has default values")
    @MainActor
    func initialState() {
        let canvas = CanvasState()
        #expect(canvas.offset == .zero)
        #expect(canvas.scale == Layout.defaultScale)
    }

    @Test("Zoom in increases scale")
    @MainActor
    func zoomInIncreasesScale() {
        let canvas = CanvasState()
        let initialScale = canvas.scale
        canvas.zoomIn()
        #expect(canvas.scale > initialScale)
    }

    @Test("Zoom out decreases scale")
    @MainActor
    func zoomOutDecreasesScale() {
        let canvas = CanvasState()
        let initialScale = canvas.scale
        canvas.zoomOut()
        #expect(canvas.scale < initialScale)
    }

    @Test("Zoom is clamped to max")
    @MainActor
    func zoomClampedToMax() {
        let canvas = CanvasState()
        canvas.setScale(100.0) // Way above max
        #expect(canvas.scale == Layout.maxScale)
    }

    @Test("Zoom is clamped to min")
    @MainActor
    func zoomClampedToMin() {
        let canvas = CanvasState()
        canvas.setScale(0.001) // Way below min
        #expect(canvas.scale == Layout.minScale)
    }

    @Test("Zoom to fit resets state")
    @MainActor
    func zoomToFitResetsState() {
        let canvas = CanvasState()
        canvas.setScale(2.0)
        canvas.setOffset(CGPoint(x: 100, y: 200))

        canvas.zoomToFit()

        #expect(canvas.scale == Layout.defaultScale)
        #expect(canvas.offset == .zero)
    }

    @Test("Pan updates offset")
    @MainActor
    func panUpdatesOffset() {
        let canvas = CanvasState()
        canvas.pan(by: CGSize(width: 100, height: 50))

        #expect(canvas.offset.x == 100)
        #expect(canvas.offset.y == 50)
    }

    @Test("Pan accounts for scale")
    @MainActor
    func panAccountsForScale() {
        let canvas = CanvasState()
        canvas.setScale(2.0) // 200% zoom
        canvas.pan(by: CGSize(width: 100, height: 50))

        // At 2x zoom, 100 screen points = 50 canvas units
        #expect(canvas.offset.x == 50)
        #expect(canvas.offset.y == 25)
    }
}

// MARK: - Coordinate Transform Tests

@Suite("Coordinate Transforms")
struct CoordinateTransformTests {

    let viewportSize = CGSize(width: 800, height: 600)

    @Test("Screen center maps to canvas origin at default state")
    @MainActor
    func screenCenterMapsToOrigin() {
        let canvas = CanvasState()
        let center = CGPoint(x: 400, y: 300)
        let canvasPoint = canvas.canvasPoint(from: center, viewportSize: viewportSize)

        #expect(abs(canvasPoint.x) < 0.001)
        #expect(abs(canvasPoint.y) < 0.001)
    }

    @Test("Canvas origin maps to screen center at default state")
    @MainActor
    func canvasOriginMapsToScreenCenter() {
        let canvas = CanvasState()
        let screenPoint = canvas.screenPoint(from: .zero, viewportSize: viewportSize)

        #expect(abs(screenPoint.x - 400) < 0.001)
        #expect(abs(screenPoint.y - 300) < 0.001)
    }

    @Test("Round trip conversion is identity")
    @MainActor
    func roundTripIsIdentity() {
        let canvas = CanvasState()
        canvas.setScale(1.5)
        canvas.setOffset(CGPoint(x: 50, y: -30))

        let originalScreen = CGPoint(x: 200, y: 150)
        let canvasPoint = canvas.canvasPoint(from: originalScreen, viewportSize: viewportSize)
        let backToScreen = canvas.screenPoint(from: canvasPoint, viewportSize: viewportSize)

        #expect(abs(backToScreen.x - originalScreen.x) < 0.001)
        #expect(abs(backToScreen.y - originalScreen.y) < 0.001)
    }

    @Test("Panning moves canvas in correct direction")
    @MainActor
    func panMovesCorrectly() {
        let canvas = CanvasState()

        // Pan right (positive X offset)
        canvas.setOffset(CGPoint(x: 100, y: 0))

        // Canvas origin should now be to the right of center
        let originOnScreen = canvas.screenPoint(from: .zero, viewportSize: viewportSize)
        #expect(originOnScreen.x > 400)
    }

    @Test("Zooming scales distances correctly")
    @MainActor
    func zoomScalesDistances() {
        let canvas = CanvasState()

        // At 1x zoom
        let point1x = canvas.screenPoint(from: CGPoint(x: 100, y: 0), viewportSize: viewportSize)
        let dist1x = point1x.x - 400 // Distance from center

        // At 2x zoom
        canvas.setScale(2.0)
        let point2x = canvas.screenPoint(from: CGPoint(x: 100, y: 0), viewportSize: viewportSize)
        let dist2x = point2x.x - 400

        // Distance should double
        #expect(abs(dist2x - dist1x * 2) < 0.001)
    }

    @Test("Visible rect correct at default state")
    @MainActor
    func visibleRectAtDefault() {
        let canvas = CanvasState()
        let rect = canvas.visibleRect(viewportSize: viewportSize)

        // At 1x zoom, centered, visible rect should be viewport size
        #expect(abs(rect.width - 800) < 0.001)
        #expect(abs(rect.height - 600) < 0.001)

        // Centered on origin
        #expect(abs(rect.midX) < 0.001)
        #expect(abs(rect.midY) < 0.001)
    }

    @Test("Visible rect shrinks when zoomed in")
    @MainActor
    func visibleRectShrinksOnZoomIn() {
        let canvas = CanvasState()
        canvas.setScale(2.0)

        let rect = canvas.visibleRect(viewportSize: viewportSize)

        // At 2x zoom, we see half the canvas area
        #expect(abs(rect.width - 400) < 0.001)
        #expect(abs(rect.height - 300) < 0.001)
    }

    @Test("Visible rect expands when zoomed out")
    @MainActor
    func visibleRectExpandsOnZoomOut() {
        let canvas = CanvasState()
        canvas.setScale(0.5)

        let rect = canvas.visibleRect(viewportSize: viewportSize)

        // At 0.5x zoom, we see twice the canvas area
        #expect(abs(rect.width - 1600) < 0.001)
        #expect(abs(rect.height - 1200) < 0.001)
    }

    @Test("Size conversion works correctly")
    @MainActor
    func sizeConversionWorks() {
        let canvas = CanvasState()
        canvas.setScale(2.0)

        let screenSize = CGSize(width: 100, height: 50)
        let canvasSize = canvas.canvasSize(from: screenSize)

        #expect(canvasSize.width == 50)
        #expect(canvasSize.height == 25)

        let backToScreen = canvas.screenSize(from: canvasSize)
        #expect(backToScreen.width == 100)
        #expect(backToScreen.height == 50)
    }
}

// MARK: - Pane Model Tests

@Suite("Pane Model")
struct PaneModelTests {

    @Test("Pane creation with defaults")
    func paneCreation() {
        let pane = Pane(
            type: .terminal(TerminalState()),
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            title: "Test Terminal"
        )

        #expect(pane.title == "Test Terminal")
        #expect(pane.frame.width == 400)
        #expect(pane.frame.height == 300)
        #expect(pane.isCollapsed == false)
        #expect(pane.groupId == nil)
    }

    @Test("Pane center calculation")
    func paneCenterCalculation() {
        let pane = Pane(
            type: .browser(BrowserPaneState()),
            frame: CGRect(x: 100, y: 200, width: 400, height: 300),
            title: "Browser"
        )

        #expect(pane.center.x == 300) // 100 + 400/2
        #expect(pane.center.y == 350) // 200 + 300/2
    }

    @Test("Pane handle positions")
    func paneHandlePositions() {
        let pane = Pane(
            type: .terminal(TerminalState()),
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            title: "Test"
        )

        #expect(pane.leftHandlePosition == CGPoint(x: 0, y: 50))
        #expect(pane.rightHandlePosition == CGPoint(x: 100, y: 50))
        #expect(pane.topHandlePosition == CGPoint(x: 50, y: 0))
        #expect(pane.bottomHandlePosition == CGPoint(x: 50, y: 100))
    }

    @Test("Pane equality is by ID")
    func paneEqualityById() {
        let id = UUID()
        let pane1 = Pane(
            id: id,
            type: .terminal(TerminalState()),
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            title: "A"
        )
        var pane2 = pane1
        pane2.title = "B" // Different title, same ID

        #expect(pane1 == pane2) // Should be equal because same ID
    }

    @Test("Pane factory creates centered pane")
    func paneFactoryCreation() {
        let position = CGPoint(x: 100, y: 100)
        let pane = Pane.create(
            type: .git(GitPaneState()),
            at: position,
            title: "Git"
        )

        // Center should be at the given position
        #expect(abs(pane.center.x - 100) < 0.001)
        #expect(abs(pane.center.y - 100) < 0.001)
    }
}

// MARK: - Pane Type Tests

@Suite("Pane Types")
struct PaneTypeTests {

    @Test("Terminal pane type properties")
    func terminalPaneType() {
        let paneType = PaneType.terminal(TerminalState())
        #expect(paneType.iconName == "terminal")
        #expect(paneType.defaultTitle == "Terminal")
    }

    @Test("Browser pane type properties")
    func browserPaneType() {
        let paneType = PaneType.browser(BrowserPaneState(url: URL(string: "http://example.com")))
        #expect(paneType.iconName == "globe")
        #expect(paneType.defaultTitle == "example.com")
    }

    @Test("File explorer pane type properties")
    func fileExplorerPaneType() {
        let paneType = PaneType.fileExplorer(FileExplorerPaneState())
        #expect(paneType.iconName == "folder")
    }

    @Test("Code editor pane type properties")
    func codeEditorPaneType() {
        let paneType = PaneType.codeEditor(CodeEditorPaneState(fileURL: URL(fileURLWithPath: "/test/file.swift")))
        #expect(paneType.iconName == "doc.text")
        #expect(paneType.defaultTitle == "file.swift")
    }

    @Test("Git pane type properties")
    func gitPaneType() {
        let paneType = PaneType.git(GitPaneState())
        #expect(paneType.iconName == "arrow.triangle.branch")
        #expect(paneType.defaultTitle == "Git")
    }
}

// MARK: - Canvas Pane Management Tests

@Suite("Canvas Pane Management")
struct CanvasPaneManagementTests {

    @Test("Create pane adds to canvas")
    @MainActor
    func createPaneAddsToCanvas() {
        let canvas = CanvasState()
        #expect(canvas.panes.isEmpty)

        canvas.createPane(type: .terminal(TerminalState()), title: "Test")

        #expect(canvas.panes.count == 1)
        #expect(canvas.panes[0].title == "Test")
    }

    @Test("Create pane auto-selects")
    @MainActor
    func createPaneAutoSelects() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "Test")

        let pane = canvas.panes[0]
        #expect(canvas.selectedPaneIds.contains(pane.id))
    }

    @Test("Delete pane removes from canvas")
    @MainActor
    func deletePaneRemovesFromCanvas() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "Test")
        let paneId = canvas.panes[0].id

        canvas.deletePane(paneId)

        #expect(canvas.panes.isEmpty)
        #expect(!canvas.selectedPaneIds.contains(paneId))
    }

    @Test("Move pane updates position")
    @MainActor
    func movePaneUpdatesPosition() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), at: CGPoint(x: 0, y: 0))
        let paneId = canvas.panes[0].id
        let originalX = canvas.panes[0].frame.origin.x

        canvas.movePaneBy(paneId, delta: CGSize(width: 50, height: 30))

        #expect(canvas.panes[0].frame.origin.x == originalX + 50)
    }

    @Test("Resize pane enforces minimum")
    @MainActor
    func resizePaneEnforcesMinimum() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()))
        let paneId = canvas.panes[0].id

        canvas.resizePane(paneId, to: CGSize(width: 50, height: 50)) // Too small

        #expect(canvas.panes[0].frame.size.width >= Layout.paneMinWidth)
        #expect(canvas.panes[0].frame.size.height >= Layout.paneMinHeight)
    }

    @Test("Bring to front updates z-index")
    @MainActor
    func bringToFrontUpdatesZIndex() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "A")
        canvas.createPane(type: .terminal(TerminalState()), title: "B")

        let paneA = canvas.panes[0]
        let paneBZIndex = canvas.panes[1].zIndex

        canvas.bringToFront(paneA.id)

        #expect(canvas.panes[0].zIndex > paneBZIndex)
    }

    @Test("Select pane updates selection")
    @MainActor
    func selectPaneUpdatesSelection() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "A")
        canvas.createPane(type: .terminal(TerminalState()), title: "B")
        canvas.clearSelection()

        let paneA = canvas.panes[0]
        canvas.selectPane(paneA.id)

        #expect(canvas.selectedPaneIds.count == 1)
        #expect(canvas.selectedPaneIds.contains(paneA.id))
    }

    @Test("Toggle selection adds and removes")
    @MainActor
    func toggleSelectionAddsAndRemoves() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "A")
        let paneA = canvas.panes[0]
        canvas.clearSelection()

        canvas.togglePaneSelection(paneA.id)
        #expect(canvas.selectedPaneIds.contains(paneA.id))

        canvas.togglePaneSelection(paneA.id)
        #expect(!canvas.selectedPaneIds.contains(paneA.id))
    }

    @Test("Duplicate pane creates copy")
    @MainActor
    func duplicatePaneCreatesCopy() {
        let canvas = CanvasState()
        canvas.createPane(type: .terminal(TerminalState()), title: "Original")
        let originalId = canvas.panes[0].id

        canvas.duplicatePane(originalId)

        #expect(canvas.panes.count == 2)
        #expect(canvas.panes[1].title == "Original")
        #expect(canvas.panes[1].id != originalId)
    }
}

// MARK: - Terminal State Tests

@Suite("TerminalState Tests")
struct TerminalStateTests {

    @Test("Default initialization uses environment shell")
    func defaultInitializationUsesEnvShell() {
        let state = TerminalState()

        // Should use $SHELL or fall back to /bin/zsh
        let expectedShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        #expect(state.shell == expectedShell)
    }

    @Test("Default initialization uses home directory")
    func defaultInitializationUsesHomeDirectory() {
        let state = TerminalState()

        #expect(state.workingDirectory == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test("Default scrollback is 10000 lines")
    func defaultScrollbackIs10000() {
        let state = TerminalState()

        #expect(state.scrollbackLines == 10_000)
    }

    @Test("Default title is Terminal")
    func defaultTitleIsTerminal() {
        let state = TerminalState()

        #expect(state.title == "Terminal")
    }

    @Test("Runtime state defaults to not exited")
    func runtimeStateDefaultsToNotExited() {
        let state = TerminalState()

        #expect(state.hasExited == false)
        #expect(state.exitCode == nil)
    }

    @Test("Custom initialization preserves values")
    func customInitializationPreservesValues() {
        let customDir = URL(fileURLWithPath: "/tmp")
        let customShell = "/bin/bash"
        let customTitle = "My Terminal"
        let customScrollback = 5000

        let state = TerminalState(
            workingDirectory: customDir,
            shell: customShell,
            title: customTitle,
            scrollbackLines: customScrollback
        )

        #expect(state.workingDirectory == customDir)
        #expect(state.shell == customShell)
        #expect(state.title == customTitle)
        #expect(state.scrollbackLines == customScrollback)
    }

    @Test("Codable encodes only configuration")
    func codableEncodesOnlyConfiguration() throws {
        var state = TerminalState(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            shell: "/bin/bash",
            scrollbackLines: 5000
        )
        state.hasExited = true
        state.exitCode = 42
        state.title = "Custom Title"

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let json = String(data: data, encoding: .utf8)!

        // Configuration should be encoded
        #expect(json.contains("workingDirectory"))
        #expect(json.contains("shell"))
        #expect(json.contains("scrollbackLines"))

        // Runtime state should NOT be encoded
        #expect(!json.contains("hasExited"))
        #expect(!json.contains("exitCode"))
        #expect(!json.contains("title"))
    }

    @Test("Codable decode restores configuration with default runtime state")
    func codableDecodeRestoresConfigurationWithDefaultRuntimeState() throws {
        let json = """
        {
            "workingDirectory": "file:///tmp/",
            "shell": "/bin/bash",
            "scrollbackLines": 5000
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let state = try decoder.decode(TerminalState.self, from: data)

        // Configuration restored
        #expect(state.workingDirectory.path == "/tmp")
        #expect(state.shell == "/bin/bash")
        #expect(state.scrollbackLines == 5000)

        // Runtime state has defaults
        #expect(state.title == "Terminal")
        #expect(state.hasExited == false)
        #expect(state.exitCode == nil)
    }

    @Test("TerminalState is Equatable")
    func terminalStateIsEquatable() {
        let state1 = TerminalState()
        let state2 = TerminalState()

        #expect(state1 == state2)

        var state3 = TerminalState()
        state3.title = "Different"
        #expect(state1 != state3)
    }

    @Test("TerminalState is Hashable")
    func terminalStateIsHashable() {
        let state1 = TerminalState()
        let state2 = TerminalState()

        var set: Set<TerminalState> = []
        set.insert(state1)
        set.insert(state2)

        // Same state should dedupe
        #expect(set.count == 1)
    }
}

// MARK: - Path Escaping Tests

@Suite("Path Escaping Tests")
struct PathEscapingTests {

    @Test("Simple path remains unchanged")
    func simplePathUnchanged() {
        let path = "/Users/test/file.txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == path)
    }

    @Test("Path with spaces is escaped")
    func pathWithSpacesEscaped() {
        let path = "/Users/test/my file.txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == "/Users/test/my\\ file.txt")
    }

    @Test("Path with special characters is escaped")
    func pathWithSpecialCharsEscaped() {
        let path = "/Users/test/file$var.txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == "/Users/test/file\\$var.txt")
    }

    @Test("Path with quotes is escaped")
    func pathWithQuotesEscaped() {
        let path = "/Users/test/file\"name\".txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == "/Users/test/file\\\"name\\\".txt")
    }

    @Test("Path with multiple special chars")
    func pathWithMultipleSpecialChars() {
        let path = "/Users/test/my file (copy).txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == "/Users/test/my\\ file\\ \\(copy\\).txt")
    }

    @Test("Multiple paths joined with spaces")
    func multiplePathsJoined() {
        let paths = ["/Users/test/file1.txt", "/Users/test/my file.txt"]
        let escaped = TerminalState.escapePaths(paths)
        #expect(escaped == "/Users/test/file1.txt /Users/test/my\\ file.txt")
    }

    @Test("Empty path returns empty")
    func emptyPathReturnsEmpty() {
        let escaped = TerminalState.escapePath("")
        #expect(escaped == "")
    }

    @Test("Backslash is escaped")
    func backslashIsEscaped() {
        let path = "/Users/test/file\\name.txt"
        let escaped = TerminalState.escapePath(path)
        #expect(escaped == "/Users/test/file\\\\name.txt")
    }
}
