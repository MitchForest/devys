// periphery:ignore:all - policy metadata is read indirectly through editor runtime state
import Syntax
import Text

struct EditorLargeFilePolicy: Sendable, Equatable {
    static let fullDocumentSyntaxLineThreshold = 5_000
    static let fullDocumentSyntaxByteThreshold = 2_000_000
    static let windowedSyntaxBacklogLineCount = 512
    static let maximumTokenizationLineLength = 1_200

    let lineCount: Int
    let utf8Length: Int
    let syntaxBacklogPolicy: SyntaxBacklogPolicy
    let maximumSyntaxLineLength: Int

    init(documentSnapshot: DocumentSnapshot) {
        let lineCount = documentSnapshot.lineCount
        let utf8Length = documentSnapshot.utf8Length
        self.lineCount = lineCount
        self.utf8Length = utf8Length
        self.maximumSyntaxLineLength = Self.maximumTokenizationLineLength

        if lineCount > Self.fullDocumentSyntaxLineThreshold
            || utf8Length > Self.fullDocumentSyntaxByteThreshold {
            syntaxBacklogPolicy = .visibleWindow(
                maxLineCount: Self.windowedSyntaxBacklogLineCount
            )
        } else {
            syntaxBacklogPolicy = .fullDocument
        }
    }

    static let `default` = EditorLargeFilePolicy(
        lineCount: 0,
        utf8Length: 0,
        syntaxBacklogPolicy: .fullDocument,
        maximumSyntaxLineLength: maximumTokenizationLineLength
    )

    var usesWindowedSyntax: Bool {
        if case .visibleWindow = syntaxBacklogPolicy {
            return true
        }
        return false
    }

    private init(
        lineCount: Int,
        utf8Length: Int,
        syntaxBacklogPolicy: SyntaxBacklogPolicy,
        maximumSyntaxLineLength: Int
    ) {
        self.lineCount = lineCount
        self.utf8Length = utf8Length
        self.syntaxBacklogPolicy = syntaxBacklogPolicy
        self.maximumSyntaxLineLength = maximumSyntaxLineLength
    }
}
