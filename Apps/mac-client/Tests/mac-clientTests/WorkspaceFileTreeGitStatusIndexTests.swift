import Foundation
import Testing
import Workspace
import Git
@testable import mac_client

struct WorkspaceFileTreeGitStatusIndexTests {
    @Test("File and directory rows derive workspace-local Git summaries")
    @MainActor
    func buildsFileAndDirectorySummaries() {
        let rootURL = URL(fileURLWithPath: "/tmp/devys/repo-a")
        let index = WorkspaceFileTreeGitStatusIndex(
            rootURL: rootURL,
            changes: [
                GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: false),
                GitFileChange(path: "Sources/Feature/New.swift", status: .added, isStaged: true),
                GitFileChange(path: "Derived/output.txt", status: .ignored, isStaged: false)
            ]
        )

        let fileNode = CEWorkspaceFileNode(
            url: rootURL.appendingPathComponent("Sources/App.swift"),
            isDirectory: false
        )
        let featureDirectory = CEWorkspaceFileNode(
            url: rootURL.appendingPathComponent("Sources/Feature"),
            isDirectory: true
        )
        let sourcesDirectory = CEWorkspaceFileNode(
            url: rootURL.appendingPathComponent("Sources"),
            isDirectory: true
        )
        let derivedDirectory = CEWorkspaceFileNode(
            url: rootURL.appendingPathComponent("Derived"),
            isDirectory: true
        )

        #expect(index.summary(for: fileNode)?.label == "M")
        #expect(index.summary(for: featureDirectory)?.label == "A")
        #expect(index.summary(for: sourcesDirectory)?.label == "M A")
        #expect(index.summary(for: derivedDirectory)?.label == "I")
    }

    @Test("Independent workspace indexes do not leak statuses across roots")
    @MainActor
    func isolatesStatusesByWorkspace() {
        let firstRoot = URL(fileURLWithPath: "/tmp/devys/repo-a")
        let secondRoot = URL(fileURLWithPath: "/tmp/devys/repo-b")

        let firstIndex = WorkspaceFileTreeGitStatusIndex(
            rootURL: firstRoot,
            changes: [GitFileChange(path: "README.md", status: .modified, isStaged: false)]
        )
        let secondIndex = WorkspaceFileTreeGitStatusIndex(rootURL: secondRoot, changes: [])

        let firstNode = CEWorkspaceFileNode(
            url: firstRoot.appendingPathComponent("README.md"),
            isDirectory: false
        )
        let secondNode = CEWorkspaceFileNode(
            url: secondRoot.appendingPathComponent("README.md"),
            isDirectory: false
        )

        #expect(firstIndex.summary(for: firstNode)?.label == "M")
        #expect(secondIndex.summary(for: secondNode) == nil)
    }
}
