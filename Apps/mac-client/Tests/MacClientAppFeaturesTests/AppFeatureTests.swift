import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class AppFeatureTests: XCTestCase {
    func testInitialState() {
        let state = AppFeature.State()

        XCTAssertEqual(state.launchCount, 0)
    }

    func testApplicationDidFinishLaunchingIncrementsLaunchCount() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.applicationDidFinishLaunching) {
            $0.launchCount = 1
        }
    }

    func testNativeWindowHostEventsAreRepresentableActions() async {
        let windowGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let store = TestStore(
            initialState: AppFeature.State(
                windowGroups: [
                    WindowGroupFeature.State(
                        id: windowGroupID,
                        initialTabID: tabID
                    )
                ]
            )
        ) {
            AppFeature()
        }

        await store.send(.nativeWindowSelected(windowGroupID)) {
            $0.selectedWindowGroupID = windowGroupID
        }
        await store.send(.nativeWindowClosed)
    }
}
