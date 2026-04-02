import Foundation
import Testing
@testable import mac_client

@Suite("TabContent Tests")
struct TabContentTests {
    @Test("Editor tabs derive fallback title and stable id from URL")
    func editorTabMetadata() {
        let url = URL(fileURLWithPath: "/tmp/Notes.swift")
        let tab = TabContent.editor(url: url)

        #expect(tab.fallbackTitle == "Notes.swift")
        #expect(tab.fallbackIcon == "swift")
        #expect(tab.stableId == "editor:\(url.absoluteString)")
    }

    @Test("Git diff tabs use the last path component in their title")
    func gitDiffMetadata() {
        let tab = TabContent.gitDiff(path: "Sources/Feature/Thing.swift", isStaged: true)

        #expect(tab.fallbackTitle == "Thing.swift")
        #expect(tab.fallbackIcon == "plus.forwardslash.minus")
        #expect(tab.stableId == "gitDiff:Sources/Feature/Thing.swift:true")
    }

    @Test("Welcome and settings tabs use stable built-in identifiers")
    func builtInMetadata() {
        #expect(TabContent.welcome.stableId == "welcome")
        #expect(TabContent.welcome.fallbackTitle == "Welcome")
        #expect(TabContent.settings.stableId == "settings")
        #expect(TabContent.settings.fallbackIcon == "gearshape")
    }
}
