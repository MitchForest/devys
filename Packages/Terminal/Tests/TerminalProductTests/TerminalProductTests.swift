@testable import TerminalProduct
import TerminalComposer
import TerminalHost
import TerminalVT
import UI
import XCTest

final class TerminalProductTests: XCTestCase {
    @MainActor
    func testPlaceholderViewCanBeCreated() {
        _ = TerminalProductPlaceholderView()
    }

    @MainActor
    func testDefaultWorkingDirectoryIsUserHomeDirectory() {
        XCTAssertEqual(
            TerminalProductModel.defaultWorkingDirectoryURL(),
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        )
        XCTAssertNotEqual(TerminalProductModel.defaultWorkingDirectoryURL().path, "/")
    }

    @MainActor
    func testDefaultTerminalTitleFallsBackToWorkingDirectoryBasename() {
        let model = TerminalProductModel()

        model.updateTerminalTitle(title: "Terminal", workingDirectory: "/Users/mitchwhite/Code/devys")

        XCTAssertEqual(model.windowTitle, "devys")
    }

    @MainActor
    func testConfiguredWorkingDirectorySeedsTitleAndComposerMetadata() {
        let url = URL(fileURLWithPath: "/Users/mitchwhite/Code/devys")
        var observedURLs: [URL] = []
        let model = TerminalProductModel(workingDirectory: url)

        XCTAssertEqual(model.workingDirectory, url.standardizedFileURL)
        XCTAssertEqual(model.windowTitle, "devys")
        XCTAssertEqual(
            model.composer.activeTarget?.metadata.cwdBasename,
            "devys"
        )

        let observedModel = TerminalProductModel(
            workingDirectory: url,
            onWorkingDirectoryChange: { observedURLs.append($0) }
        )
        observedModel.updateTerminalTitle(
            title: "Terminal",
            workingDirectory: "/Users/mitchwhite/Code/side-project"
        )

        XCTAssertEqual(
            observedURLs,
            [
                url.standardizedFileURL,
                URL(fileURLWithPath: "/Users/mitchwhite/Code/side-project").standardizedFileURL,
            ]
        )
    }

    @MainActor
    func testAgentTitleCombinesAgentAndFolder() {
        let model = TerminalProductModel(agentRegistry: .default)
        model.updateTerminalTitle(title: "Terminal", workingDirectory: "/Users/mitchwhite/Code/devys")

        model.applyForegroundProcess(
            TerminalForegroundProcess(pid: 100, executableName: "codex", executablePath: "/opt/homebrew/bin/codex")
        )

        XCTAssertEqual(model.windowTitle, "Codex - devys")
    }

    @MainActor
    func testTerminalProvidedTitleCombinesWithFolder() {
        let model = TerminalProductModel()

        model.updateTerminalTitle(title: "pnpm dev", workingDirectory: "/Users/mitchwhite/Code/web")

        XCTAssertEqual(model.windowTitle, "pnpm dev - web")
    }

    @MainActor
    func testForegroundProcessTitleCombinesWithFolderForNonShells() {
        let model = TerminalProductModel()
        model.updateTerminalTitle(title: "Terminal", workingDirectory: "/Users/mitchwhite/Code/devys")

        model.applyForegroundProcess(
            TerminalForegroundProcess(pid: 100, executableName: "vim", executablePath: "/usr/bin/vim")
        )

        XCTAssertEqual(model.windowTitle, "vim - devys")
    }

    @MainActor
    func testCloseRiskIgnoresShellForegroundProcess() {
        let model = TerminalProductModel()

        model.applyForegroundProcess(
            TerminalForegroundProcess(pid: 100, executableName: "zsh", executablePath: "/bin/zsh")
        )

        XCTAssertNil(model.closeRisk)
    }

    @MainActor
    func testCloseRiskClassifiesKnownAgent() {
        let model = TerminalProductModel(agentRegistry: .default)
        let process = TerminalForegroundProcess(
            pid: 100,
            executableName: "codex",
            executablePath: "/opt/homebrew/bin/codex"
        )

        model.applyForegroundProcess(process)

        XCTAssertEqual(model.closeRisk, .knownAgent(displayName: "Codex", process: process))
    }

    @MainActor
    func testCloseRiskClassifiesGenericForegroundProcess() {
        let model = TerminalProductModel()
        let process = TerminalForegroundProcess(pid: 100, executableName: "vim", executablePath: "/usr/bin/vim")

        model.applyForegroundProcess(process)

        XCTAssertEqual(model.closeRisk, .foregroundProcess(process))
    }

    @MainActor
    func testCloseRiskClearsWhenTerminalExits() {
        let model = TerminalProductModel()
        model.applyForegroundProcess(
            TerminalForegroundProcess(pid: 100, executableName: "vim", executablePath: "/usr/bin/vim")
        )

        model.markTerminalExited()

        XCTAssertNil(model.closeRisk)
    }

    @MainActor
    func testWindowFocusActivatesThisTabsTerminalNotComposer() {
        let model = TerminalProductModel()
        let otherTargetID = TerminalTargetID()

        model.composer.registerTarget(
            id: otherTargetID,
            metadata: TerminalComposerTargetMetadata(cwdBasename: "other"),
            isActive: true
        )

        XCTAssertEqual(model.composer.activeTargetID, otherTargetID)

        model.setWindowFocused(true)

        XCTAssertEqual(model.composer.activeTargetID, model.terminalTargetID)
        XCTAssertEqual(model.composer.visibleTargetIDs, [model.terminalTargetID])
        XCTAssertFalse(model.composer.isFocused, "Default focus is the terminal, not the composer")
        XCTAssertEqual(model.focusRequestID, 1, "Window focus increments terminal focus request")
    }

    @MainActor
    func testTerminalTapExplicitlyMovesFocusToTerminal() {
        let model = TerminalProductModel()

        model.focusComposer()
        model.focusTerminal()

        XCTAssertEqual(model.focusRequestID, 1)
        XCTAssertEqual(model.composer.activeTargetID, model.terminalTargetID)
        XCTAssertFalse(model.composer.isFocused)
    }

    @MainActor
    func testApplyThemeUsesDesignSystemTerminalAppearance() {
        let model = TerminalProductModel()
        let lightTheme = Theme(isDark: false)

        model.applyTheme(lightTheme)

        XCTAssertEqual(model.appearance.colorScheme, .light)
        XCTAssertEqual(model.appearance.background, TerminalProductModel.terminalAppearance(for: lightTheme).background)
        XCTAssertEqual(model.appearance.foreground, TerminalProductModel.terminalAppearance(for: lightTheme).foreground)
        XCTAssertEqual(model.appearance.background, TerminalColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(model.appearance.foreground, TerminalColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(model.appearance.palette, TerminalAppearance.terminalLightPalette)
    }

    @MainActor
    func testInitialAppearanceUsesDesignSystemDarkTerminalAppearance() {
        let model = TerminalProductModel()

        XCTAssertEqual(model.appearance, TerminalProductModel.defaultTerminalAppearance)
        XCTAssertEqual(model.appearance.background, TerminalColor(red: 28, green: 27, blue: 25))
        XCTAssertNotEqual(model.appearance.background, TerminalAppearance.defaultDark.background)
    }

    @MainActor
    func testApplyThemeSwitchesTerminalAppearanceBetweenLightAndDark() {
        let model = TerminalProductModel()

        model.applyTheme(Theme(isDark: false))
        let lightAppearance = model.appearance
        model.applyTheme(Theme(isDark: true))

        XCTAssertEqual(model.appearance.colorScheme, .dark)
        XCTAssertEqual(model.appearance.background, TerminalColor(red: 28, green: 27, blue: 25))
        XCTAssertEqual(model.appearance.foreground, TerminalColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(model.appearance.palette, TerminalAppearance.terminalDarkPalette)
        XCTAssertNotEqual(model.appearance.background, lightAppearance.background)
        XCTAssertNotEqual(model.appearance.foreground, lightAppearance.foreground)
    }

    @MainActor
    func testExitedSingleTargetEntersChooseTargetState() {
        let model = TerminalProductModel()

        model.markTerminalExited()

        XCTAssertNil(model.composer.activeTargetID)
        XCTAssertEqual(model.composer.visibleTargetIDs, [])
        XCTAssertEqual(
            model.composer.presentation,
            .chooseTarget(TerminalComposerChooseTargetState(reason: "Choose a terminal"))
        )
    }

}
