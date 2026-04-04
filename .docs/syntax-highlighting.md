# Canonical Syntax Highlighting Status

## Purpose

This is the one canonical document for Devys syntax highlighting.

It replaces the old migration, diff, rendering, and query-source plan docs.

This document answers three things:

- what the syntax system is today
- what has already been completed
- what still remains for professional IDE-grade highlighting in files and diffs

## Current Architecture

Devys now runs a Tree-sitter-only syntax stack.

The current production shape is:

- `Packages/Syntax` owns the parser runtime, language registry, query loading, themes, and span snapshots
- editor files and Git diffs both use the same Tree-sitter runtime and the same themed span model
- the runtime uses `swift-tree-sitter` plus `SwiftTreeSitterLayer`
- highlighting is capture-based, not TextMate-scope-based
- injected child languages are resolved through the canonical language registry
- HTML and Markdown already use layered injections in production

Primary implementation files:

- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxDocumentRuntime.swift`
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshot.swift`
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/TreeSitterLanguageRegistry.swift`
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/TreeSitterLanguageConfigurationProvider.swift`
- `Packages/Syntax/Sources/Syntax/Resources/TreeSitterQueries/`

## Completed Work

The Tree-sitter migration itself is complete.

Completed outcomes:

- TextMate and Oniguruma are removed from the production syntax path
- editor file highlighting is fully on Tree-sitter
- diff highlighting is fully on Tree-sitter
- the runtime uses `LanguageLayer` instead of a single-tree parser model
- bounded invalidation replaced dirty-tail rehighlighting
- capture-native theme mapping replaced TextMate scope theming
- placeholder-driven visible highlighting behavior is gone
- HTML nested JavaScript and CSS highlighting is active
- Markdown fenced-block, frontmatter, metadata-block, HTML, and inline-markdown highlighting is active
- correctness and parity gates exist for the shipped Tree-sitter path

Validation commands currently used for this surface:

- `swift test --package-path Packages/Syntax`
- `swift test --package-path Packages/Editor`
- `swift test --package-path Packages/Git`
- `./scripts/check-tree-sitter-migration.sh`

## Current Language Coverage

Shipped top-level Tree-sitter grammars and query bundles:

- `c`
- `cpp`
- `csharp`
- `css`
- `go`
- `html`
- `java`
- `javascript`
- `json`
- `jsx`
- `kotlin`
- `lua`
- `make`
- `markdown`
- `markdown_inline`
- `php`
- `python`
- `ruby`
- `rust`
- `shellscript`
- `sql`
- `swift`
- `toml`
- `tsx`
- `typescript`
- `yaml`

Query-source status:

- Zed-derived and curated: `c`, `cpp`, `css`, `go`, `html`, `javascript`, `json`, `jsx`, `markdown`, `markdown_inline`, `python`, `rust`, `shellscript`, `tsx`, `typescript`, `yaml`
- audited against upstream and now aligned or intentionally filtered: `swift`, `java`, `lua`, `php`, `ruby`
- bundled and intentionally left as-is for now: `csharp`, `kotlin`, `make`, `toml`
- shipped from its own upstream source: `sql`

## Current Status

The requested near-term follow-up scope is complete.

Completed follow-up work:

- SQL is now a first-class shipped Tree-sitter language in editor files and diffs
- SQL parser artifacts are vendored from `tree-sitter-sql`
- SQL query assets are bundled under `TreeSitterQueries/sql`
- SQL is now part of the bundled language registry, configuration provider, fixtures, parity tests, and migration gate
- SQL injection aliases are now resolved by the canonical language registry
- SQL-specific injection rules were restored in the curated JavaScript, JSX, TypeScript, TSX, Python, Go, and Rust query sets where Devys can now resolve the `sql` child language
- Lua now uses the upstream `tree-sitter-lua` query set and matching parser artifacts
- Swift `highlights.scm` and `locals.scm` are aligned with `alex-pinkus/tree-sitter-swift`
- Swift upstream injections were intentionally filtered because `regex` and `comment` remain out of scope
- PHP, Ruby, and Java were audited against their upstream query sources and were already effectively aligned for the shipped Devys scope

### Leave-As-Is For Now

The following are not priority migration items right now:

- `regex`
- `jsdoc`

Other languages that already have shipped grammars and functioning query bundles can stay as-is for now, even if they are not yet as rich as the Zed-derived set.

That means no immediate follow-up is required for:

- `csharp`
- `kotlin`
- `make`
- `toml`

## Validation

Validated from the live worktree with:

- `swift test --package-path Packages/Syntax`
- `swift test --package-path Packages/Editor`
- `swift test --package-path Packages/Git`
- `./scripts/check-tree-sitter-migration.sh`

## Notes

- Do not reintroduce TextMate, Oniguruma, Shiki compatibility layers, or mixed-engine fallbacks.
- Do not open a new migration track for the other shipped languages unless product quality issues justify it.
- Treat this document as the canonical status and remaining-work list for syntax highlighting going forward.
