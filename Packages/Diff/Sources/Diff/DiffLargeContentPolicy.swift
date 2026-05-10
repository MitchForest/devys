// periphery:ignore:all - diff policy helpers are selected indirectly by Git diff workflows
import Syntax

struct DiffLargeContentPolicy: Sendable, Equatable {
    static let maxWordDiffLines = 800
    static let maxWrapLines = 1_500
    static let maxSyntaxLines = 2_000
    static let fullDocumentSyntaxLineThreshold = 600
    static let stagedSyntaxBacklogLineCount = 384
    static let maximumTokenizationLineLength = 1_200

    let totalLines: Int
    let enableWordDiff: Bool
    let enableWrap: Bool
    let enableSyntaxHighlighting: Bool
    let maximumSyntaxLineLength: Int
    let syntaxBacklogPolicy: SyntaxBacklogPolicy

    init(totalLines: Int) {
        self.totalLines = totalLines
        enableWordDiff = totalLines <= Self.maxWordDiffLines
        enableWrap = totalLines <= Self.maxWrapLines
        enableSyntaxHighlighting = totalLines <= Self.maxSyntaxLines
        maximumSyntaxLineLength = enableSyntaxHighlighting ? Self.maximumTokenizationLineLength : 0

        if !enableSyntaxHighlighting {
            syntaxBacklogPolicy = .fullDocument
        } else if totalLines > Self.fullDocumentSyntaxLineThreshold {
            syntaxBacklogPolicy = .visibleWindow(
                maxLineCount: Self.stagedSyntaxBacklogLineCount
            )
        } else {
            syntaxBacklogPolicy = .fullDocument
        }
    }

    init(diff: ParsedDiff) {
        self.init(totalLines: diff.hunks.reduce(0) { $0 + $1.lines.count })
    }

    init(snapshot: DiffSnapshot) {
        self.init(totalLines: snapshot.hunks.reduce(0) { $0 + $1.lines.count })
    }

    var usesStagedSyntaxLoading: Bool {
        if case .visibleWindow = syntaxBacklogPolicy {
            return true
        }
        return false
    }

    var isReduced: Bool {
        !enableWordDiff || !enableWrap || !enableSyntaxHighlighting || usesStagedSyntaxLoading
    }

    var bannerDetailText: String {
        var reducedFeatures: [String] = []
        if usesStagedSyntaxLoading {
            reducedFeatures.append("syntax staged to the visible window")
        }
        if !enableSyntaxHighlighting {
            reducedFeatures.append("syntax highlighting")
        }
        if !enableWordDiff {
            reducedFeatures.append("word diff")
        }
        if !enableWrap {
            reducedFeatures.append("wrapping")
        }
        if reducedFeatures.isEmpty {
            return "All features enabled."
        }
        return "Reduced: " + reducedFeatures.joined(separator: ", ") + "."
    }
}
