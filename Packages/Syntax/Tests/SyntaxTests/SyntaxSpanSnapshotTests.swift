import Testing
import Text
@testable import Syntax

@Suite("SyntaxSpanSnapshot Tests")
struct SyntaxSpanSnapshotTests {
    @Test("Builds a line-addressable span snapshot from Tree-sitter captures")
    func buildsLineAddressableSnapshot() async throws {
        let document = TextDocument(content: source)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let state = await runtime.currentState()
        let theme = try SyntaxTheme.load(name: "devys-dark")
        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: state,
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift(),
            theme: theme
        )

        let declarationLine = snapshot.line(2)

        #expect(snapshot.revision == state.syntaxRevision)
        #expect(snapshot.documentVersion == state.documentVersion)
        #expect(snapshot.themeName == theme.name)
        #expect(snapshot.lineCount == document.snapshot().lineCount)
        #expect(declarationLine.spans.isEmpty == false)
        #expect(declarationLine.spans.contains { $0.captureName.hasPrefix("keyword") })
        #expect(declarationLine.spans.contains { $0.captureName == "string" })
        #expect(snapshot.lines(in: 1..<4).count == 3)
    }

    @Test("Multiline captures are split into per-line spans")
    func multilineCapturesSplitPerLine() async throws {
        let document = TextDocument(content: multilineSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )

        #expect(snapshot.line(3).spans.contains { $0.captureName == "string" })
        #expect(snapshot.line(4).spans.contains { $0.captureName == "string" })
        #expect(snapshot.line(5).spans.contains { $0.captureName == "string" })
    }

    @Test("Builder can target only a visible line range")
    func builderCanTargetVisibleLineRange() async throws {
        let document = TextDocument(content: multilineSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.swift(),
            theme: try SyntaxTheme.load(name: "devys-dark"),
            lineRange: 3..<5
        )

        #expect(snapshot.line(2).spans.isEmpty)
        #expect(snapshot.line(3).spans.isEmpty == false)
        #expect(snapshot.line(4).spans.isEmpty == false)
        #expect(snapshot.line(6).spans.isEmpty)
    }

    @Test("HTML resolves script and style injections into layered spans")
    func htmlResolvesScriptAndStyleInjections() async throws {
        let document = TextDocument(content: htmlSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(
                resolving: 0..<document.snapshot().lineCount
            ),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )

        #expect(snapshot.line(1).spans.contains { $0.captureName.hasPrefix("keyword") })
        #expect(snapshot.line(1).spans.contains { $0.captureName == "number" })
        #expect(snapshot.line(4).spans.contains { $0.captureName == "property" })
    }

    @Test("Markdown resolves frontmatter, inline markdown, and fenced code injections")
    func markdownResolvesLayeredInjections() async throws {
        let document = TextDocument(content: markdownLayeredSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(
                resolving: 0..<document.snapshot().lineCount
            ),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )
        #expect(snapshot.line(1).spans.contains { $0.captureName == "property" })
        #expect(snapshot.line(1).spans.contains { $0.captureName == "string" })
        #expect(snapshot.line(4).spans.contains { $0.captureName.contains("uri") })
        #expect(snapshot.line(7).spans.contains { $0.captureName.hasPrefix("keyword") })
        #expect(snapshot.line(7).spans.contains { $0.captureName == "number" })
    }

    @Test("Markdown captures heading markers and list markers distinctly")
    func markdownCapturesHeadingAndListMarkers() async throws {
        let document = TextDocument(content: markdownPresentationSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(
                resolving: 0..<document.snapshot().lineCount
            ),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )

        #expect(snapshot.line(0).spans.contains { $0.captureName == "punctuation.special" })
        #expect(snapshot.line(0).spans.contains { $0.captureName == "text.title" })
        #expect(snapshot.line(2).spans.contains { $0.captureName == "punctuation.special" })
    }

    @Test("Markdown list paths keep markers and inline code consistent per line")
    func markdownListPathsKeepMarkersAndInlineCodeConsistentPerLine() async throws {
        let document = TextDocument(content: markdownPathListSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown()
        )

        let snapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(
                resolving: 0..<document.snapshot().lineCount
            ),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.markdown(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )
        let firstLine = snapshot.line(0).spans
        let secondLine = snapshot.line(1).spans

        #expect(firstLine.map(\.captureName) == secondLine.map(\.captureName))
        #expect(firstLine.map(\.style) == secondLine.map(\.style))
        #expect(firstLine.contains { $0.captureName == "punctuation.special" })
        #expect(firstLine.contains { $0.captureName == "text.literal" })
        #expect(firstLine.contains { $0.captureName == "punctuation.delimiter" })
    }

    @Test("Layer resolution stays bounded to the requested visible range")
    func layerResolutionStaysBoundedToVisibleRange() async throws {
        let document = TextDocument(content: htmlSource)
        let runtime = try SyntaxDocumentRuntime(
            documentSnapshot: document.snapshot(),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html()
        )

        let scriptOnlySnapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(resolving: 0..<3),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )

        #expect(scriptOnlySnapshot.line(1).spans.contains { $0.captureName.hasPrefix("keyword") })
        #expect(scriptOnlySnapshot.line(4).spans.contains { $0.captureName == "property" } == false)

        let styleSnapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: document.snapshot(),
            documentState: await runtime.currentState(resolving: 3..<6),
            languageConfiguration: try TreeSitterLanguageConfigurationProvider.html(),
            theme: try SyntaxTheme.load(name: "devys-dark")
        )

        #expect(styleSnapshot.line(4).spans.contains { $0.captureName == "property" })
    }
}

private let source = """
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
    }
}
"""

private let htmlSource = """
<script>
const value = 42;
</script>
<style>
body { color: red; }
</style>
"""

private let markdownLayeredSource = """
+++
title = "Example"
+++

[link](https://example.com)

```javascript
const value = 42;
```
"""

private let markdownPresentationSource = """
# Heading

- Item one
"""

private let markdownPathListSource = """
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxDocumentRuntime.swift`
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshot.swift`

"""
