import AppFeatures
import Foundation
import Workspace

actor ReviewPersistenceStore {
    private enum RetentionPolicy {
        static let maxInactiveRuns = 25
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadWorkspace(
        workspaceID _: Workspace.ID,
        rootURL: URL
    ) throws -> ReviewWorkspaceSnapshot {
        let runsURL = ReviewStorageLocations.runsDirectory(for: rootURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: runsURL.path) else {
            return ReviewWorkspaceSnapshot()
        }

        let snapshots = try loadRunSnapshots(in: runsURL)
        let retained = retainedSnapshots(from: snapshots)
        try pruneSnapshots(snapshots, retaining: retained)

        return ReviewWorkspaceSnapshot(
            runs: retained.map(\.run),
            issues: retained.flatMap(\.issues)
        )
    }

    func saveRun(
        _ run: ReviewRun,
        issues: [ReviewIssue],
        rootURL: URL
    ) throws {
        let runURL = ReviewStorageLocations.runDirectory(
            for: rootURL,
            runID: run.id,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: runURL, withIntermediateDirectories: true)

        try encoded(run).write(
            to: runURL.appendingPathComponent("run.json", isDirectory: false),
            options: .atomic
        )
        try encoded(issues).write(
            to: runURL.appendingPathComponent("issues.json", isDirectory: false),
            options: .atomic
        )
        try pruneRuns(rootURL: rootURL)
    }

    func deleteRun(
        _ runID: UUID,
        rootURL: URL
    ) throws {
        let runURL = ReviewStorageLocations.runDirectory(
            for: rootURL,
            runID: runID,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: runURL.path) else { return }
        try fileManager.removeItem(at: runURL)
    }
}

private extension ReviewPersistenceStore {
    struct ReviewRunSnapshot {
        let directoryURL: URL
        let run: ReviewRun
        let issues: [ReviewIssue]

        var isActive: Bool {
            run.status.isActive
        }

        var retentionDate: Date {
            run.completedAt ?? run.createdAt
        }
    }

    func loadRunSnapshot(
        at directoryURL: URL
    ) throws -> ReviewRunSnapshot {
        let run = try decoder.decode(
            ReviewRun.self,
            from: Data(contentsOf: directoryURL.appendingPathComponent("run.json", isDirectory: false))
        )

        let issuesURL = directoryURL.appendingPathComponent("issues.json", isDirectory: false)
        let issues: [ReviewIssue]
        if fileManager.fileExists(atPath: issuesURL.path) {
            issues = try decoder.decode([ReviewIssue].self, from: Data(contentsOf: issuesURL))
        } else {
            issues = []
        }

        return ReviewRunSnapshot(
            directoryURL: directoryURL,
            run: run,
            issues: issues
        )
    }

    func loadRunSnapshots(
        in runsURL: URL
    ) throws -> [ReviewRunSnapshot] {
        let runDirectories = try fileManager.contentsOfDirectory(
            at: runsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try runDirectories.compactMap { directory -> ReviewRunSnapshot? in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return try loadRunSnapshot(at: directory)
        }
    }

    func pruneRuns(
        rootURL: URL
    ) throws {
        let runsURL = ReviewStorageLocations.runsDirectory(for: rootURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: runsURL.path) else {
            return
        }

        let snapshots = try loadRunSnapshots(in: runsURL)
        let retained = retainedSnapshots(from: snapshots)
        try pruneSnapshots(snapshots, retaining: retained)
    }

    func retainedSnapshots(
        from snapshots: [ReviewRunSnapshot]
    ) -> [ReviewRunSnapshot] {
        let active = snapshots
            .filter(\.isActive)
            .sorted { ReviewRun.sort($0.run, $1.run) }
        let inactive = snapshots
            .filter { !$0.isActive }
            .sorted(by: reviewRetentionSort)
            .prefix(RetentionPolicy.maxInactiveRuns)

        return (active + inactive).sorted { ReviewRun.sort($0.run, $1.run) }
    }

    func pruneSnapshots(
        _ snapshots: [ReviewRunSnapshot],
        retaining retained: [ReviewRunSnapshot]
    ) throws {
        let retainedRunIDs = Set(retained.map(\.run.id))
        for snapshot in snapshots where retainedRunIDs.contains(snapshot.run.id) == false {
            guard fileManager.fileExists(atPath: snapshot.directoryURL.path) else {
                continue
            }
            try fileManager.removeItem(at: snapshot.directoryURL)
        }
    }

    func encoded<T: Encodable>(_ value: T) throws -> Data {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}

private func reviewRetentionSort(
    _ lhs: ReviewPersistenceStore.ReviewRunSnapshot,
    _ rhs: ReviewPersistenceStore.ReviewRunSnapshot
) -> Bool {
    if lhs.retentionDate != rhs.retentionDate {
        return lhs.retentionDate > rhs.retentionDate
    }

    return ReviewRun.sort(lhs.run, rhs.run)
}
