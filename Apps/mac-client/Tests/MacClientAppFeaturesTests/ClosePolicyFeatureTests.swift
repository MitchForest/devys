import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class ClosePolicyFeatureTests: XCTestCase {
    func testCleanCloseAllowsImmediately() async {
        let id = UUID(0)
        let store = TestStore(initialState: ClosePolicyFeature.State()) {
            ClosePolicyFeature()
        }

        await store.send(.register(CloseSubject(id: id, kind: .plain))) {
            $0.subjects[id] = CloseSubject(id: id, kind: .plain)
        }
        await store.send(.requestClose(id)) {
            $0.decisions[id] = .allow
        }
    }

    func testDirtyCancelDeniesClose() async {
        await assertDirtyDocumentClose(response: .cancel, decision: .deny)
    }

    func testDirtySaveRequestsSaveThenClose() async {
        await assertDirtyDocumentClose(response: .confirm, decision: .saveThenClose)
    }

    func testDirtyDiscardRequestsDiscardThenClose() async {
        await assertDirtyDocumentClose(response: .secondary, decision: .discardThenClose)
    }

    func testTerminalForegroundProcessCloseRiskRequiresConfirmation() async {
        let id = UUID(0)
        let subject = CloseSubject(
            id: id,
            kind: .terminalCloseRisk(
                displayName: "vim",
                detail: "vim is active in this terminal as process 42."
            )
        )
        let store = TestStore(initialState: ClosePolicyFeature.State()) {
            ClosePolicyFeature()
        } withDependencies: {
            $0.alertClient = AlertClient { request in
                XCTAssertEqual(request.title, "Close terminal running vim?")
                return true
            }
        }

        await store.send(.register(subject)) {
            $0.subjects[id] = subject
        }
        await store.send(.requestClose(id))
        await store.receive(.closeAlertResponse(id, .confirm)) {
            $0.decisions[id] = .allow
        }
    }

    private func assertDirtyDocumentClose(
        response: AlertResponse,
        decision: CloseDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let id = UUID(0)
        let subject = CloseSubject(id: id, kind: .dirtyDocument(displayName: "README.md"))
        let store = TestStore(initialState: ClosePolicyFeature.State()) {
            ClosePolicyFeature()
        } withDependencies: {
            $0.alertClient = AlertClient(
                confirm: { _ in XCTFail("Dirty document close should use a multi-choice alert", file: file, line: line); return false },
                choose: { request in
                    XCTAssertEqual(request.title, "Save changes to README.md?", file: file, line: line)
                    XCTAssertEqual(request.confirmTitle, "Save", file: file, line: line)
                    XCTAssertEqual(request.secondaryTitle, "Don't Save", file: file, line: line)
                    return response
                }
            )
        }

        await store.send(.register(subject)) {
            $0.subjects[id] = subject
        }
        await store.send(.requestClose(id))
        await store.receive(.closeAlertResponse(id, response)) {
            $0.decisions[id] = decision
        }
    }
}
