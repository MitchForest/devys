import RemoteCore
import XCTest

final class RemoteCoreTests: XCTestCase {
    func testRemoteRepositoryDrawerDisplayNameUsesHostContext() {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/me/Code/devys"
        )

        XCTAssertEqual(repository.drawerDisplayName, "devys (mac-mini)")
    }

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
