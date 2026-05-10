import Git
@testable import MacClientAppFeatures
import Testing

@Suite("Git Change Status Presentation Tests")
struct GitChangeStatusPresentationTests {
    @Test("Git status icon mapping lives in the app layer")
    func appIconNameMapsEveryGitStatus() {
        #expect(GitChangeStatus.modified.appIconName == "pencil.circle.fill")
        #expect(GitChangeStatus.added.appIconName == "plus.circle.fill")
        #expect(GitChangeStatus.deleted.appIconName == "minus.circle.fill")
        #expect(GitChangeStatus.renamed.appIconName == "arrow.right.circle.fill")
        #expect(GitChangeStatus.copied.appIconName == "doc.on.doc.fill")
        #expect(GitChangeStatus.untracked.appIconName == "questionmark.circle.fill")
        #expect(GitChangeStatus.ignored.appIconName == "eye.slash.circle.fill")
        #expect(GitChangeStatus.unmerged.appIconName == "exclamationmark.triangle.fill")
    }
}
