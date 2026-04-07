# Syntax Highlighting Improvement Plan

## Goal

Bring the Tree-sitter syntax highlighting stack up to professional IDE quality:

- fast on large files
- visibly bounded to the requested range
- explicit about parser and query selection
- correct across injected languages and edits
- observable when the system degrades instead of silently falling back

This plan is intentionally biased toward simple, explicit changes in the existing architecture rather than introducing more abstraction.

## Current Baseline

- `swift test --package-path Packages/Syntax` passes locally on April 5, 2026.
- Current tests cover bundled language loading, visible-range snapshot building, bounded invalidation, and basic layered injections.
- Current tests do not cover parser identity, injection removal or retagging, degraded-state reporting, or performance budgets.

## Audit Findings

### 1. Parser selection is not explicit or correct for JavaScript

Evidence:

- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/TreeSitterLanguageConfigurationProvider.swift:190-194` maps `.javascript` to `tree_sitter_tsx()`.
- `Packages/Syntax/Package.swift` ships a dedicated `TreeSitterJavaScript` target.

Why it matters:

- This makes plain JavaScript behavior depend on the TSX grammar.
- It blurs the parser/query contract and makes future regressions hard to reason about.
- It weakens confidence that `javascript`, `jsx`, `typescript`, and `tsx` are intentionally paired.

Required outcome:

- Each shipped language ID must map to an intentional parser/query pairing.
- The mapping must be testable and obvious from one table.

### 2. Injection lifecycle is incomplete and can retain stale sublayers

Evidence:

- `Packages/Syntax/Sources/SwiftTreeSitterLayer/LanguageLayer.swift:330-353` only replaces included ranges that share the same lower bound.
- `Packages/Syntax/Sources/SwiftTreeSitterLayer/LanguageLayer.swift:359-387` only adds or updates grouped injections; it never removes sublayers or ranges that disappeared.

Why it matters:

- If an injected block is deleted, moved, or retagged to a different language, the old sublayer can survive.
- That creates stale highlighting and stale parse work in exactly the scenarios editors hit constantly.
- This is a correctness issue, not just a performance issue.

Required outcome:

- Injection resolution must reconcile desired sublayers against existing sublayers on every resolve pass.
- Removed injections must remove ranges.
- Retagged injections must remove the old language layer and create the new one.

### 3. Visible-range work is still not truly bounded

Evidence:

- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshotCandidateCollector.swift:11-21` precomputes line starts and line lengths for every line.
- The visible-range narrowing only happens later at `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshotCandidateCollector.swift:47-52`.
- `Packages/Syntax/Sources/SwiftTreeSitterLayer/LanguageLayer.swift:249-260` accepts `snapshot(in:)` but always snapshots every sublayer.
- `Packages/Syntax/Sources/SwiftTreeSitterLayer/Snapshots.swift:68-85` enumerates every snapshot even when a narrowed set is provided.

Why it matters:

- The public API suggests bounded visible-range work, but the implementation still scales with whole-document and whole-layer-tree state in important steps.
- That mismatch makes scroll and edit performance less predictable on large files with many injections.

Required outcome:

- Layout, snapshotting, and query target selection must all scale with the requested range, not with the full document or full layer tree.

### 4. Failure handling is still silent in multiple critical paths

Evidence:

- `Packages/Syntax/Sources/SwiftTreeSitterLayer/LanguageLayer.swift:182-189` catches sublayer parse failures and prints.
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxDocumentRuntime.swift:283-289` swallows `resolveSublayers` failures with `try?` and then assumes snapshot success.
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshotCandidateCollector.swift:49-52` swallows highlight query failures and returns an empty result.
- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/TreeSitterLanguageRegistry.swift:18-20` swallows configuration loading errors.
- `Packages/Syntax/Sources/Syntax/Services/Integration/SyntaxController.swift:97-127,177-252` uses `try?` in runtime creation, reparsing, replacement, and theme loading.

Why it matters:

- The system can degrade to blank or plain highlighting without any structured signal.
- Existing `SyntaxRuntimeDiagnostics` and `OSLog` infrastructure already exist, so this silent behavior is unnecessary and hard to defend.
- A professional editor needs explicit degraded states, not best-effort silence.

Required outcome:

- Failures must be recorded through structured diagnostics.
- The controller must know when it is showing degraded output.
- Silent `try?` fallbacks should be limited to deliberate, documented boundaries.

### 5. Span normalization is more expensive than it needs to be

Evidence:

- `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxSpanSnapshotCandidateCollector.swift:77-117` computes segment winners by filtering the full candidate list for every boundary segment.

Why it matters:

- This is effectively quadratic per line in the number of highlight candidates.
- It may not dominate today, but it is exactly the kind of hot-path inefficiency that appears under dense captures, large visible windows, or heavily injected documents.

Required outcome:

- Replace with a sweep-line or similarly linearithmic normalization pass after the bigger bounded-work fixes land.
- Measure before and after so this is justified by data, not instinct.

## Work Plan

## Phase 1: Correctness And Explicitness

### 1. Fix parser-to-language mappings

Changes:

- Replace the `.javascript` descriptor with the dedicated JavaScript parser.
- Audit `javascript`, `jsx`, `typescript`, and `tsx` together and document the intended pairing for each language ID.
- Keep the mapping in one static table; do not spread parser choice across helpers.

Acceptance criteria:

- `javascript` no longer resolves through the TSX parser.
- The descriptor table has a one-line comment or test expectation explaining any intentionally shared parser.
- New tests fail if a shipped language points to the wrong parser family.

Tests to add:

- `TreeSitterLanguageConfigurationTests`: assert parser family for `javascript`, `jsx`, `typescript`, and `tsx`.
- Fixture-based regression tests for `sample.js`, `sample.jsx`, `sample.ts`, and `sample.tsx` that check representative captures instead of only “configuration loads.”

### 2. Reconcile injections instead of only appending them

Changes:

- Replace the current add-or-update logic in `LanguageLayer.resolveSublayers` with a full reconciliation step:
  - compute desired injection ranges by language
  - remove languages no longer present
  - remove obsolete ranges within surviving languages
  - update changed ranges
  - add new languages
- Rename `encorporateRanges` to `incorporateRanges` while touching this code.
- Make the invalidation set include removed injection regions, not just added or updated ones.

Acceptance criteria:

- Deleting a `<script>` or fenced code block removes the corresponding sublayer.
- Changing an injection language retags the region correctly on the next resolve.
- No stale highlighting remains after removal or retagging.

Tests to add:

- HTML test: remove a `<script>` block after initial resolve and assert JavaScript captures disappear.
- Markdown test: change a fenced block from `javascript` to `swift` and assert the old language no longer contributes spans.
- Multi-injection test: remove one of two same-language blocks and assert only the surviving block remains in the sublayer range set.

### 3. Make degradation explicit

Changes:

- Define a small degraded-state model for syntax work, for example:
  - configuration load failure
  - theme load failure
  - root parse failure
  - injection resolve failure
  - highlight query failure
- Route those events through `SyntaxRuntimeDiagnostics` and `OSLog`.
- Replace opportunistic `try?` use with one of:
  - explicit propagation where the caller can recover
  - a logged, typed degraded state where the UI intentionally falls back
- Remove `print` from `LanguageLayer`.

Acceptance criteria:

- No Tree-sitter failure path silently degrades without a structured signal.
- The controller can distinguish “plain highlighting because language unsupported” from “plain highlighting because Tree-sitter degraded.”
- Diagnostics snapshot exposes counters for degraded parse/query events.

Tests to add:

- Fault-injection tests with a stubbed language provider or broken query/config path.
- Diagnostics test that verifies a degraded event is recorded when injection resolution fails.
- Controller test that verifies fallback output is accompanied by degraded-state metadata.

## Phase 2: Make Visible-Range Work Actually Bounded

### 4. Stop computing whole-document line layout for visible batches

Changes:

- Replace `SyntaxSpanSnapshotLineLayout` full-array precomputation with a range-aware layout helper.
- Compute line starts and line lengths only for:
  - the requested visible range, or
  - the actual touched lines of multiline captures intersecting that range
- Cache per-line offsets only when there is a measured benefit.

Acceptance criteria:

- Building a visible snapshot for `N` lines does not iterate `0..<snapshot.lineCount` up front.
- The collector code makes the bounded-work path obvious from top to bottom.

Tests to add:

- Targeted unit tests for range normalization and visible-range offset calculation.
- A regression perf test using a large file where the visible range is small.

### 5. Make layered snapshotting and query execution region-aware

Changes:

- Change `snapshot(in:)` and `LanguageLayerTreeSnapshot.enumerateSnapshots(in:)` so they do not walk unrelated sublayers.
- Use included range intersection as the first filter.
- If parent-query expansion truly requires additional traversal, do it explicitly in two stages:
  - stage 1: query root or directly intersecting layers
  - stage 2: expand into newly intersecting child layers only when needed
- Do not keep the current “accept a set, ignore it internally” contract.

Acceptance criteria:

- Query target count for a small visible range is proportional to intersecting layers, not total layers.
- The code path documents why any extra expansion happens.

Tests to add:

- A synthetic layered document with many injections where only one region is visible.
- An assertion-based test that counts queried layers or query targets for a bounded request.

## Phase 3: Hot-Path Tightening

### 6. Optimize candidate normalization after correctness and boundedness are fixed

Changes:

- Replace the per-segment `filter` approach with a sweep-line algorithm or equivalent.
- Avoid repeated theme resolution or repeated array allocation where not needed.
- Benchmark the before and after on dense-capture fixtures.

Acceptance criteria:

- Candidate normalization complexity is no worse than `O(n log n)` per line.
- Benchmarks show a measurable win on dense lines.

Tests to add:

- Benchmark fixture with many overlapping captures on a single line.
- Correctness test that preserves existing precedence behavior.

### 7. Measure the edit pipeline before changing it

Observation:

- `SyntaxDocumentRuntime.reparse` currently rebuilds a `TextDocument` from the full old snapshot and re-snapshots while replaying edits at `Packages/Syntax/Sources/Syntax/Services/TreeSitter/SyntaxDocumentRuntime.swift:353-368`.

Plan:

- Instrument this path before refactoring it.
- Only optimize if it shows up meaningfully after Phases 1 and 2 land.

Reason:

- It may be a real cost, but the current larger wins are clearer and less risky.
- This keeps the plan explicit and avoids speculative refactors.

## Verification Plan

### Functional

- Run `swift test --package-path Packages/Syntax` after each phase.
- Add new tests for:
  - parser identity
  - injection removal
  - injection retagging
  - degraded-state signaling
  - bounded layer query execution

### Performance

- Add a microbenchmark target or benchmark-style tests for:
  - visible snapshot build on a large file
  - layered query execution with many injections
  - dense per-line normalization
- Define target budgets before optimizing:
  - visible-range highlight request should scale with visible lines and intersecting layers
  - no whole-document prepass for a small visible window

### Diagnostics

- Extend `SyntaxRuntimeDiagnosticSnapshot` with degraded-state counters.
- Verify logs and counters for:
  - parser/config load failures
  - injection resolution failures
  - highlight query failures

## Recommended Delivery Order

1. Parser mapping cleanup plus tests.
2. Injection reconciliation plus tests.
3. Degraded-state plumbing plus diagnostics tests.
4. Range-aware line layout.
5. Region-aware layer snapshot and query execution.
6. Candidate normalization optimization.
7. Re-evaluate incremental reparse cost with measurements.

This order keeps correctness first, then makes the visible-range promise true, then tightens the remaining hot path with data.

## Guardrails

- Do not introduce a new generic highlighting framework.
- Do not add another cache until a measured miss shows the need.
- Prefer direct, typed result paths over `try?` and sentinel empty arrays.
- Keep parser/query pairing centralized and inspectable.
- Treat hidden fallback behavior as a defect unless it is logged and intentionally surfaced as degraded output.
