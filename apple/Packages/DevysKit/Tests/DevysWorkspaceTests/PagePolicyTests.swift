import Foundation
import Testing
@testable import DevysWorkspace

@Suite("Page policy")
struct PagePolicyTests {
    @Test("Pages render under the same policy as the web's pagePolicy (src/apps/documents/contract.ts)")
    func matchesServer() throws {
        let contract = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../../src/apps/documents/contract.ts").standardized
        let source = try String(contentsOf: contract, encoding: .utf8)
        let match = try #require(source.firstMatch(of: /const pagePolicy =\s*"([^"]+)"/))
        #expect(pagePolicy == String(match.1))
    }
}
