import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class WindowGroupFeatureTests: XCTestCase {
    func testOpenNewWindowCreatesTerminalTab() async {
        let projectURL = URL(fileURLWithPath: "/tmp/devys")
        let windowGroupID = testUUID(0)
        let tabID = testUUID(1)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.openNewWindow(projectRootURL: projectURL)) {
            $0.selectedWindowGroupID = windowGroupID
            $0.windowGroups = [
                WindowGroupFeature.State(
                    id: windowGroupID,
                    projectRootURL: projectURL,
                    initialTabID: tabID
                )
            ]
        }
    }

    func testNewTabInheritsProjectRootFromSelectedWindowGroup() async {
        let projectURL = URL(fileURLWithPath: "/tmp/devys")
        let windowGroupID = testUUID(10)
        let initialTabID = testUUID(11)
        let newTabID = testUUID(0)
        let fileURL = projectURL.appendingPathComponent("README.md")
        let store = TestStore(
            initialState: AppFeature.State(
                selectedWindowGroupID: windowGroupID,
                windowGroups: [
                    WindowGroupFeature.State(
                        id: windowGroupID,
                        projectRootURL: projectURL,
                        initialTabID: initialTabID
                    )
                ]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.openNewTab(.file(fileURL))) {
            $0.windowGroups[0].tabs.append(
                WorkspaceTab(
                    id: newTabID,
                    kind: .file(fileURL),
                    projectRootURL: projectURL
                )
            )
            $0.windowGroups[0].selectedTabID = newTabID
        }
    }

    func testNewTabCanUseExplicitProjectRoot() async {
        let groupProjectURL = URL(fileURLWithPath: "/tmp/devys")
        let explicitProjectURL = URL(fileURLWithPath: "/tmp/other")
        let windowGroupID = testUUID(10)
        let initialTabID = testUUID(11)
        let newTabID = testUUID(0)
        let browserURL = URL(string: "http://localhost:3000")!
        let store = TestStore(
            initialState: AppFeature.State(
                selectedWindowGroupID: windowGroupID,
                windowGroups: [
                    WindowGroupFeature.State(
                        id: windowGroupID,
                        projectRootURL: groupProjectURL,
                        initialTabID: initialTabID
                    )
                ]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.openNewTab(.browser(browserURL), projectRootURL: explicitProjectURL)) {
            $0.windowGroups[0].tabs.append(
                WorkspaceTab(
                    id: newTabID,
                    kind: .browser(browserURL),
                    projectRootURL: explicitProjectURL
                )
            )
            $0.windowGroups[0].selectedTabID = newTabID
        }
    }

    func testNewTabUsesExplicitWindowGroupEvenWhenAnotherGroupIsSelected() async {
        let firstProjectURL = URL(fileURLWithPath: "/tmp/first")
        let secondProjectURL = URL(fileURLWithPath: "/tmp/second")
        let firstWindowGroupID = testUUID(20)
        let secondWindowGroupID = testUUID(21)
        let firstInitialTabID = testUUID(22)
        let secondInitialTabID = testUUID(23)
        let newTabID = testUUID(0)
        let fileURL = secondProjectURL.appendingPathComponent("Sources/App.swift")
        let store = TestStore(
            initialState: AppFeature.State(
                selectedWindowGroupID: firstWindowGroupID,
                windowGroups: [
                    WindowGroupFeature.State(
                        id: firstWindowGroupID,
                        projectRootURL: firstProjectURL,
                        initialTabID: firstInitialTabID
                    ),
                    WindowGroupFeature.State(
                        id: secondWindowGroupID,
                        projectRootURL: secondProjectURL,
                        initialTabID: secondInitialTabID
                    )
                ]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.openNewTab(.file(fileURL), projectRootURL: secondProjectURL, windowGroupID: secondWindowGroupID)) {
            $0.selectedWindowGroupID = secondWindowGroupID
            $0.windowGroups[1].tabs.append(
                WorkspaceTab(
                    id: newTabID,
                    kind: .file(fileURL),
                    projectRootURL: secondProjectURL
                )
            )
            $0.windowGroups[1].selectedTabID = newTabID
        }
    }

    func testNativeWindowSelectionChangesSelectedProjectRoot() async {
        let firstProjectURL = URL(fileURLWithPath: "/tmp/first")
        let secondProjectURL = URL(fileURLWithPath: "/tmp/second")
        let firstWindowGroupID = testUUID(30)
        let secondWindowGroupID = testUUID(31)
        let store = TestStore(
            initialState: AppFeature.State(
                selectedWindowGroupID: firstWindowGroupID,
                windowGroups: [
                    WindowGroupFeature.State(
                        id: firstWindowGroupID,
                        projectRootURL: firstProjectURL,
                        initialTabID: testUUID(32)
                    ),
                    WindowGroupFeature.State(
                        id: secondWindowGroupID,
                        projectRootURL: secondProjectURL,
                        initialTabID: testUUID(33)
                    )
                ]
            )
        ) {
            AppFeature()
        }

        await store.send(.nativeWindowSelected(secondWindowGroupID)) {
            $0.selectedWindowGroupID = secondWindowGroupID
        }

        XCTAssertEqual(store.state.selectedProjectRootURL, secondProjectURL.standardizedFileURL)
    }

    func testUnboundTabStaysUnbound() async {
        let windowGroupID = testUUID(10)
        let initialTabID = testUUID(11)
        let newTabID = testUUID(0)
        let store = TestStore(
            initialState: AppFeature.State(
                selectedWindowGroupID: windowGroupID,
                windowGroups: [
                    WindowGroupFeature.State(
                        id: windowGroupID,
                        initialTabID: initialTabID
                    )
                ]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.openNewTab(.terminal)) {
            $0.windowGroups[0].tabs.append(
                WorkspaceTab(id: newTabID, kind: .terminal)
            )
            $0.windowGroups[0].selectedTabID = newTabID
        }
    }
}

private func testUUID(_ value: UInt8) -> UUID {
    UUID(uuid: (
        0, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, value
    ))
}
