import Testing
@testable import GhosttyTerminal

@Suite("Ghostty Bootstrap Tests")
struct GhosttyBootstrapTests {
    @Test("Pinned metadata looks valid")
    func pinnedMetadataLooksValid() {
        #expect(GhosttyBootstrap.minimumZigVersion == "0.15.2")
        #expect(GhosttyBootstrap.ghosttyVersion == "1.3.2-dev")
        #expect(GhosttyBootstrap.pinnedCommit.count == 40)
        #expect(GhosttyBootstrap.repositoryURL.contains("ghostty-org/ghostty"))
    }
}
