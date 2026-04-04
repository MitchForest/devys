import Testing
import Text
@testable import Syntax

@Suite("Tree-sitter Document Runtime Tests")
struct TreeSitterDocumentRuntimeTests {
    @Test("Initial parse creates persistent parser state")
    func initialParseCreatesPersistentState() async throws {
        let document = TextDocument(content: sampleSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let state = await runtime.currentState()

        #expect(state.documentVersion == document.snapshot().version)
        #expect(state.syntaxRevision == 0)
        #expect(state.lineCount == document.snapshot().lineCount)
        #expect(state.tree.rootNode?.nodeType == "source_file")
        #expect(state.tree.rootNode?.hasError == false)
    }

    @Test("Single-line edits reparse incrementally and expose changed ranges")
    func singleLineEditsReparseIncrementally() async throws {
        let originalContent = sampleSource
        let document = TextDocument(content: originalContent)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let oldSnapshot = document.snapshot()
        let transaction = EditTransaction(
            edits: [
                TextEdit(
                    range: utf8Range(of: "\"world\"", in: originalContent),
                    replacement: "\"team\""
                )
            ]
        )

        _ = document.apply(transaction)
        let newSnapshot = document.snapshot()

        let parseResult = try await runtime.reparse(
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            transaction: transaction
        )
        let state = await runtime.currentState()

        #expect(parseResult.strategy == .incremental)
        #expect(parseResult.documentVersion == newSnapshot.version)
        #expect(parseResult.syntaxRevision == 1)
        #expect(parseResult.changedRanges.isEmpty == false)
        #expect(parseResult.changedRanges.contains { $0.lineRange.range.contains(2) })
        #expect(parseResult.invalidation.lineRanges.count == 1)
        #expect(parseResult.invalidation.contains(lineIndex: 2))
        #expect(parseResult.invalidation.lineRanges[0].upperBound - parseResult.invalidation.lineRanges[0].lowerBound < newSnapshot.lineCount)
        #expect(state.documentVersion == newSnapshot.version)
        #expect(state.syntaxRevision == 1)
        #expect(state.tree.rootNode?.nodeType == "source_file")
        #expect(state.tree.rootNode?.hasError == false)
    }

    @Test("Multiline edits invalidate bounded changed ranges instead of the remainder of the file")
    func multilineEditsInvalidateBoundedRanges() async throws {
        let originalContent = multilineSource
        let document = TextDocument(content: originalContent)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let oldSnapshot = document.snapshot()
        let transaction = EditTransaction(
            edits: [
                TextEdit(
                    range: utf8Range(of: "beta", in: originalContent),
                    replacement: "beta\n        delta"
                )
            ]
        )

        _ = document.apply(transaction)
        let newSnapshot = document.snapshot()

        let parseResult = try await runtime.reparse(
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            transaction: transaction
        )

        #expect(parseResult.strategy == .incremental)
        #expect(parseResult.changedRanges.isEmpty == false)
        #expect(parseResult.invalidation.lineRanges.count == 1)
        #expect(parseResult.invalidation.contains(lineIndex: 4))
        #expect(parseResult.invalidation.contains(lineIndex: 5))
        #expect(parseResult.invalidation.lineRanges[0].upperBound - parseResult.invalidation.lineRanges[0].lowerBound < newSnapshot.lineCount)
    }

    @Test("Edits inside injected regions invalidate only the affected layered range")
    func injectedRegionEditsInvalidateBoundedRanges() async throws {
        let originalContent = htmlLayeredSource
        let document = TextDocument(content: originalContent)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html()
        )

        _ = await runtime.currentState(resolving: 0..<document.snapshot().lineCount)

        let oldSnapshot = document.snapshot()
        let transaction = EditTransaction(
            edits: [
                TextEdit(
                    range: utf8Range(of: "42", in: originalContent),
                    replacement: "420"
                )
            ]
        )

        _ = document.apply(transaction)
        let newSnapshot = document.snapshot()

        let parseResult = try await runtime.reparse(
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            transaction: transaction
        )

        #expect(parseResult.strategy == .incremental)
        #expect(parseResult.changedRanges.isEmpty == false)
        #expect(parseResult.invalidation.contains(lineIndex: 1))
        #expect(parseResult.invalidation.contains(lineIndex: 4) == false)
        #expect(parseResult.invalidation.lineRanges[0].upperBound - parseResult.invalidation.lineRanges[0].lowerBound < newSnapshot.lineCount)
    }
}

private let sampleSource = """
struct Greeter {
    func greet() {
        let subject = "world"
    }
}
"""

private let multilineSource = """
struct Example {
    func build() {
        let banner = \"\"\"
        alpha
        beta
        gamma
        \"\"\"
        print(banner)
        let suffix = 42
    }
}
"""

private let htmlLayeredSource = """
<script>
const value = 42;
</script>
<style>
body { color: red; }
</style>
"""

private func utf8Range(of needle: String, in haystack: String) -> TextByteRange {
    guard let range = haystack.range(of: needle) else {
        Issue.record("Missing needle '\(needle)' in test fixture.")
        return TextByteRange(0, 0)
    }

    let lowerBound = haystack.utf8.distance(from: haystack.startIndex, to: range.lowerBound)
    let upperBound = haystack.utf8.distance(from: haystack.startIndex, to: range.upperBound)

    return TextByteRange(lowerBound, upperBound)
}
