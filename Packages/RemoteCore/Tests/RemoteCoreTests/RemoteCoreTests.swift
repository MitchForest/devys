import RemoteCore
import XCTest

final class RemoteCoreTests: XCTestCase {
    func testSessionNameIsStableForEquivalentPaths() {
        let first = RemoteSessionNaming.shellSessionName(
            target: "mac-mini",
            remotePath: "/Users/me/Code/devys/../devys-feature"
        )
        let second = RemoteSessionNaming.shellSessionName(
            target: "mac-mini",
            remotePath: "/Users/me/Code/devys-feature"
        )

        XCTAssertEqual(first, second)
    }
}
