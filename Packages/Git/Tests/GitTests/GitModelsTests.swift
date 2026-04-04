// GitModelsTests.swift
// Tests for Git models.

import Foundation
import Testing
@testable import Git

struct GitModelsTests {
    
    // MARK: - GitFileChange
    
    @Test func fileChangeFilename() {
        let change = GitFileChange(
            path: "src/components/Button.swift",
            status: .modified,
            isStaged: false
        )
        
        #expect(change.filename == "Button.swift")
        #expect(change.directory == "src/components")
    }
    
    @Test func fileChangeRootFile() {
        let change = GitFileChange(
            path: "README.md",
            status: .added,
            isStaged: true
        )
        
        #expect(change.filename == "README.md")
        #expect(change.directory == ".")
    }
    
    @Test func fileChangeId() {
        let staged = GitFileChange(path: "file.txt", status: .modified, isStaged: true)
        let unstaged = GitFileChange(path: "file.txt", status: .modified, isStaged: false)
        
        #expect(staged.id != unstaged.id)
        #expect(staged.id.hasPrefix("staged:"))
        #expect(unstaged.id.hasPrefix("unstaged:"))
    }
    
    // MARK: - GitBranch
    
    @Test func branchDisplayName() {
        let local = GitBranch(name: "feature/new-ui", isRemote: false)
        let remote = GitBranch(name: "origin/main", isRemote: true)
        
        #expect(local.displayName == "feature/new-ui")
        #expect(remote.displayName == "main")
    }
    
    // MARK: - GitCommit
    
    @Test func commitSubject() {
        let commit = GitCommit(
            hash: "abc123def456",
            shortHash: "abc123d",
            authorName: "John Doe",
            date: Date(),
            message: "Fix bug in login\n\nThis fixes the issue where users could not log in."
        )
        
        #expect(commit.subject == "Fix bug in login")
    }
    
    // MARK: - GitRepositoryInfo
    
    @Test func syncStatus() {
        let ahead = GitRepositoryInfo(currentBranch: "main", aheadCount: 3, behindCount: 0)
        let behind = GitRepositoryInfo(currentBranch: "main", aheadCount: 0, behindCount: 2)
        let both = GitRepositoryInfo(currentBranch: "main", aheadCount: 1, behindCount: 1)
        let synced = GitRepositoryInfo(currentBranch: "main", aheadCount: 0, behindCount: 0)
        
        #expect(ahead.syncStatus == "↑3")
        #expect(behind.syncStatus == "↓2")
        #expect(both.syncStatus == "↑1 ↓1")
        #expect(synced.syncStatus == "")
    }
    
    @Test func aheadBehindCounts() {
        let ahead = GitRepositoryInfo(currentBranch: "main", aheadCount: 3, behindCount: 0)
        let behind = GitRepositoryInfo(currentBranch: "main", aheadCount: 0, behindCount: 2)
        
        #expect(ahead.aheadCount == 3)
        #expect(ahead.behindCount == 0)

        #expect(behind.aheadCount == 0)
        #expect(behind.behindCount == 2)
    }
    
    // MARK: - DiffHunk
    
    @Test func hunkToPatch() {
        let hunk = DiffHunk(
            id: "hunk-1",
            header: "@@ -1,3 +1,4 @@",
            lines: [
                DiffLine(id: "line-1", type: .header, content: "@@ -1,3 +1,4 @@"),
                DiffLine(id: "line-2", type: .context, content: "line 1", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(id: "line-3", type: .removed, content: "line 2", oldLineNumber: 2, newLineNumber: nil),
                DiffLine(id: "line-4", type: .added, content: "line 2 modified", oldLineNumber: nil, newLineNumber: 2),
                DiffLine(id: "line-5", type: .added, content: "new line", oldLineNumber: nil, newLineNumber: 3),
                DiffLine(id: "line-6", type: .context, content: "line 3", oldLineNumber: 3, newLineNumber: 4)
            ],
            oldStart: 1,
            oldCount: 3,
            newStart: 1,
            newCount: 4
        )
        
        let patch = hunk.toPatch(oldPath: "file.txt", newPath: "file.txt")
        
        #expect(patch.contains("--- a/file.txt"))
        #expect(patch.contains("+++ b/file.txt"))
        #expect(patch.contains("@@ -1,3 +1,4 @@"))
        #expect(patch.contains(" line 1"))
        #expect(patch.contains("-line 2"))
        #expect(patch.contains("+line 2 modified"))
        #expect(patch.contains("+new line"))
    }
    
    // MARK: - ParsedDiff
    
    @Test func parsedDiffStats() {
        let diff = ParsedDiff(
            hunks: [
                DiffHunk(
                    id: "hunk-a",
                    header: "@@ -1,3 +1,5 @@",
                    lines: [
                        DiffLine(id: "line-a", type: .added, content: "a"),
                        DiffLine(id: "line-b", type: .added, content: "b"),
                        DiffLine(id: "line-c", type: .removed, content: "c")
                    ]
                ),
                DiffHunk(
                    id: "hunk-b",
                    header: "@@ -10,2 +12,3 @@",
                    lines: [
                        DiffLine(id: "line-d", type: .added, content: "d")
                    ]
                )
            ]
        )
        
        #expect(diff.totalAdded == 3)
        #expect(diff.totalRemoved == 1)
        #expect(diff.hasChanges)
    }

    @Test func reparsingSameDiffRetainsDeterministicIdentifiers() {
        let diffText = """
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let value = 1
        +let value = 2
         print(value)
        """

        let firstParse = DiffParser.parse(diffText)
        let secondParse = DiffParser.parse(diffText)

        #expect(firstParse.hunks.map(\.id) == secondParse.hunks.map(\.id))
        #expect(
            firstParse.hunks.flatMap(\.lines).map(\.id) ==
            secondParse.hunks.flatMap(\.lines).map(\.id)
        )

        let firstSnapshot = DiffSnapshot(
            from: firstParse,
            baseContent: "let value = 1\nprint(value)\n",
            modifiedContent: "let value = 2\nprint(value)\n"
        )
        let secondSnapshot = DiffSnapshot(
            from: secondParse,
            baseContent: "let value = 1\nprint(value)\n",
            modifiedContent: "let value = 2\nprint(value)\n"
        )

        #expect(firstSnapshot.sourceDocuments == secondSnapshot.sourceDocuments)
        #expect(firstSnapshot.version == secondSnapshot.version)
    }

    @Test func diffSourceRequestUsesParsedRenamePaths() {
        let parsedDiff = ParsedDiff(
            hunks: [],
            oldPath: "Sources/Legacy.swift",
            newPath: "Sources/Renamed.swift"
        )

        let stagedRequest = GitClient.makeDiffSourceContentRequest(
            parsedDiff: parsedDiff,
            staged: true
        )
        #expect(stagedRequest.baseGitSpecifier == "HEAD:Sources/Legacy.swift")
        #expect(stagedRequest.modifiedGitSpecifier == ":Sources/Renamed.swift")
        #expect(stagedRequest.modifiedWorktreePath == nil)

        let unstagedRequest = GitClient.makeDiffSourceContentRequest(
            parsedDiff: parsedDiff,
            staged: false
        )
        #expect(unstagedRequest.baseGitSpecifier == ":Sources/Legacy.swift")
        #expect(unstagedRequest.modifiedGitSpecifier == nil)
        #expect(unstagedRequest.modifiedWorktreePath == "Sources/Renamed.swift")
    }

    @Test func missingRequiredSourceDocumentDisablesSyntaxExplicitly() {
        let parsedDiff = DiffParser.parse("""
        --- a/Sources/Legacy.swift
        +++ b/Sources/Renamed.swift
        @@ -1 +1 @@
        -let value = 1
        +let value = 2
        """)

        let snapshot = DiffSnapshot(
            from: parsedDiff,
            baseContent: nil,
            modifiedContent: "let value = 2\n"
        )

        #expect(snapshot.sourceDocuments.availability == .unavailable)
        #expect(!snapshot.sourceDocuments.supportsSyntaxHighlighting)
    }

    @Test func diffVersionChangesWhenOnlySourcePathsChange() {
        let firstParse = DiffParser.parse("""
        --- a/Sources/First.swift
        +++ b/Sources/First.swift
        @@ -1 +1 @@
        -let value = 1
        +let value = 2
        """)
        let secondParse = DiffParser.parse("""
        --- a/Sources/Second.swift
        +++ b/Sources/Second.swift
        @@ -1 +1 @@
        -let value = 1
        +let value = 2
        """)

        let firstSnapshot = DiffSnapshot(
            from: firstParse,
            baseContent: "let value = 1\n",
            modifiedContent: "let value = 2\n"
        )
        let secondSnapshot = DiffSnapshot(
            from: secondParse,
            baseContent: "let value = 1\n",
            modifiedContent: "let value = 2\n"
        )

        #expect(firstSnapshot.version != secondSnapshot.version)
    }
}
