# Devys Terminal Performance Plan

Status: active plan

Updated: 2026-04-20

## Current State

This plan remains active only because the benchmark and acceptance sweep is still outstanding.

The previously reopened render-path correctness regressions are now fixed and validated:

- rotated Metal buffers are now primed correctly before partial uploads are allowed
- block cursor invalidation now rebuilds the affected rows instead of leaving stale visual state behind
- startup readiness and startup redraw scheduling no longer clear the overlay on a non-stable visible frame

Current execution status:

- `TPERF-01` complete
- `TPERF-02` complete
- `TPERF-03` complete
- `TPERF-04` complete
- `TPERF-05` complete
- `TPERF-06` complete
- `TPERF-07` complete
- `TPERF-08` complete
- `TPERF-09` in progress
- `TPERF-10` complete
- `TPERF-11` complete
- `TPERF-12` complete
- `TPERF-13` complete
- `TPERF-14` complete
- `TPERF-15` complete
- `TPERF-16` complete
- `TPERF-17` complete
- `TPERF-18` in progress
- `TPERF-19` complete
- `TPERF-20` complete
- `TPERF-21` complete
- `TPERF-22` complete

What is still open:

- collect measured results for the required benchmark profiles
- compare those results against the strict p95 acceptance thresholds
- record any misses and either fix them or explicitly reopen the relevant ticket
- record the benchmark output in this plan
- only then close and delete this plan

## Purpose

This plan makes the shipped Ghostty VT + Metal terminal feel materially faster than the old SwiftUI terminal in the ways users actually notice:

- time to visible terminal tab
- time to first painted terminal frame
- time to first interactive shell
- reattach speed for existing sessions
- typing and scroll responsiveness
- idle efficiency

This is an active implementation plan, not a future brief and not a reference document.

## Problem Statement

The current terminal is architecturally correct but does not yet feel performance-shaped unless the user-perceived path is optimized and measured end to end.

The core issues this plan addresses are:

- terminal tab creation waiting on host and session startup instead of painting immediately
- first terminal open being cold by default because host warmup was gated on restore settings
- local shells launching through login plus interactive startup before the user sees useful output
- attach and reopen paths replaying buffered PTY output through the VT runtime before the surface feels ready
- the terminal glyph atlas lazily rasterizing and replacing too much texture state on glyph misses
- exact dirty rows being computed while the renderer still flattened and uploaded the whole visible cell set
- the terminal continuously redrawing while idle
- weak terminal-first performance instrumentation compared with the Metal editor
- hosted terminals being created and attached at a fake `120x40` size before the real view has measured its viewport
- Claude and Codex first frames being emitted at the wrong PTY width and only reflowing after a later resize or user input

## Scope

This plan covers the shipped terminal product path only:

- `libghostty-vt`
- `GhosttyTerminalFrameProjection`
- `GhosttyTerminalView`
- shared Metal rendering on macOS and iOS
- local hosted terminal startup and attach behavior on macOS

## Non-Goals

This plan does not:

- add a parallel SwiftUI terminal path
- add a snapshot-driven rendering fallback
- change the canonical terminal architecture into a host-owned renderer
- broaden terminal feature scope into IME, links, or accessibility depth
- replace Ghostty VT with another runtime
- turn `Apps/mac-client` into a new app-domain owner

## Invariants

These rules remain true while implementing this plan:

- `GhosttyVTRuntime` and `GhosttyVTCore` remain the terminal runtime authority
- `GhosttyVTCore.surfaceUpdate()` remains the only supported projection path into `GhosttyTerminalFrameProjection`
- `Packages/Rendering` owns low-level terminal Metal primitives, buffer packing, and atlas support
- `GhosttyTerminalView` remains the shared host on macOS and iOS
- app hosts stay thin and do not become terminal state authorities
- `screenText()` remains a non-rendering utility only
- no viewport fallback path is reintroduced
- no snapshot-driven renderer path is introduced

## Measurement Contract

No ticket in this plan is complete without direct measurement.

The terminal must emit a reducer-independent performance trace with these checkpoints:

- `open_request`
- `tab_visible`
- `controller_created`
- `host_ensure_start`
- `host_ready`
- `session_create_start`
- `session_created`
- `attach_start`
- `attach_ack`
- `first_output_chunk`
- `first_surface_update`
- `first_atlas_mutation`
- `first_frame_commit`
- `first_interactive_frame`
- `viewport_measured`
- `viewport_applied`

The trace must distinguish:

- cold host
- warm host
- fresh session
- existing session attach
- fast local shell launch profile
- compatibility shell launch profile
- startup with an immediate measured viewport
- startup delayed waiting for viewport measurement

## Benchmark Profiles

The implementation is accepted against these benchmark profiles on Apple Silicon macOS using the supported `mac-client` Debug scheme:

1. `cold-empty-shell`
   A blank local terminal with no existing daemon and the fast launch profile.
2. `warm-empty-shell`
   A blank local terminal with an already running daemon and the fast launch profile.
3. `warm-real-shell`
   A blank local terminal with the compatibility shell profile.
4. `existing-session-attach`
   Reopen a running hosted session after at least 512 KiB of historical PTY output has been produced.
5. `typing-burst`
   Send repeated ASCII input and paste bursts to a warm terminal.
6. `scroll-burst`
   Scroll through a warm terminal with populated scrollback.

Release metrics may also be recorded, but Debug metrics are the merge gate because that is the supported developer testing path.

## Strict Acceptance Criteria

All of the following must be true before this plan is closed.

### User-Visible Startup

- `open_request -> tab_visible` is at or below 100 ms p95 for all benchmark profiles.
- opening a terminal tab never waits for session creation before the tab is inserted into the shell
- the terminal surface shows a purposeful startup state immediately if the runtime is not yet attached

### Host Startup

- macOS terminal host warmup is not gated on `restoreTerminalSessions`
- app launch or first shell-scene activation warms the detached terminal host proactively
- `host_ensure_start -> host_ready` is at or below 150 ms p95 on warm relaunch and at or below 300 ms p95 on cold launch

### First Paint And First Interactive Frame

- `open_request -> first_frame_commit` is at or below 300 ms p95 for `cold-empty-shell`
- `open_request -> first_frame_commit` is at or below 150 ms p95 for `warm-empty-shell`
- `open_request -> first_interactive_frame` is at or below 400 ms p95 for `cold-empty-shell`
- `open_request -> first_interactive_frame` is at or below 200 ms p95 for `warm-empty-shell`
- `attach_start -> first_frame_commit` is at or below 250 ms p95 for `existing-session-attach`

### Viewport-First Startup Contract

- no hosted terminal session is created at a hard-coded fallback size when the tab is opened from a live UI surface
- no first attach request is sent without an explicit measured viewport for UI-hosted sessions
- the first PTY size and the first client VT size match the measured terminal viewport for launcher and plain shell tabs
- the startup overlay may appear before the first frame, but the live terminal host view is mounted early enough to measure the real viewport before spawn and attach
- first-frame wrapping for Claude and Codex matches the steady-state wrapping without requiring a later keypress, focus event, or resize
- typing must not be the event that corrects the initial layout

### Shell Launch Behavior

- blank local terminal tabs use an explicit fast launch profile instead of the compatibility shell path
- workflow and launcher-driven terminal sessions keep an explicit compatibility path unless deliberately configured otherwise
- the fast launch profile is documented, measurable, and covered by tests

### Attach And Replay Behavior

- existing-session attach time must not scale linearly with arbitrarily long PTY history
- the host-side attach replay budget is explicit and bounded
- reattach does not depend on replaying the full trimmed PTY buffer through the client runtime
- the chosen attach optimization does not introduce a snapshot-driven rendering fallback

### Glyph Atlas Behavior

- printable ASCII is preloaded before the first interactive shell frame
- runtime ASCII shell startup causes zero dynamic glyph atlas misses after preload
- glyph misses are batched per frame or per preparation pass, not uploaded one-by-one
- no full-atlas texture replacement occurs after renderer initialization
- dynamic glyph insertion uploads only the touched atlas subregion

### Dirty-Row And GPU Upload Behavior

- partial dirty frames do not flatten and upload the entire visible grid
- a one-row dirty update repacks and uploads only the dirty row ranges
- terminal cell uploads touch only the active GPU buffer for the frame
- inactive buffers are not rewritten on each update
- buffer rotation is either used correctly or removed

### Idle And Steady-State Behavior

- with cursor blink disabled and no output, the terminal commits zero frames over 5 seconds
- with cursor blink enabled and no output, frame commits are bounded to the blink cadence
- `first_output_chunk -> first_frame_commit` is at or below 16 ms p95 for warm ASCII-only updates with no atlas misses
- typing and paste bursts in `typing-burst` do not exceed 33 ms p95 frame latency
- `scroll-burst` does not exceed 33 ms p95 frame latency for warm terminals

### Resource Reuse

- terminal pipeline creation is shared or cached so opening a second terminal view does not repeat avoidable shader and pipeline setup work
- shared terminal renderer resources are keyed explicitly by the inputs that matter, such as font and scale

### Validation

- `swift test` passes in `Packages/GhosttyTerminal`
- `swift test` passes in `Packages/Rendering`
- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build` passes
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passes
- targeted mac-client terminal validation passes via `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/TerminalSessionStartupLifecycleTests -only-testing:mac-clientTests/WorkspaceTerminalRegistryTests -only-testing:mac-clientTests/TerminalHostWarmupStateTests -only-testing:mac-clientTests/TerminalRendererWarmupStateTests`
- targeted mac-client tests cover viewport-gated startup, initial PTY sizing, launcher command staging, and readiness transitions
- the terminal runtime reference is updated in the same change stream if any supported startup or host contract changes

## Execution Order

The intended order is:

1. instrumentation and benchmark harness
2. immediate tab presentation
3. unconditional host warmup
4. fast local shell launch profile
5. bounded attach replay contract
6. glyph atlas startup and upload fixes
7. dirty-row GPU upload path
8. event-driven render scheduling and shared renderer resources
9. viewport-first startup contract
10. initial-size host session creation and restore behavior
11. launcher command staging and startup readiness proof
12. launcher shell contract correction
13. launcher executable preflight
14. non-blocking startup chrome
15. renderer warmup and production-safe failure handling
16. launcher auto-run script and prompt-safe delivery hardening
17. rendered-frame readiness and first-draw retry hardening
18. validation, benchmark pass, and docs closeout

## Tickets

### TPERF-01 Terminal Open And Render Instrumentation

Status: complete

Delivered:

- terminal open trace state and tracker
- checkpoint coverage for open, attach, surface, atlas, frame, and interactive milestones
- terminal trace logging through `WorkspacePerformanceRecorder`
- tracker tests

Remaining closeout requirement:

- use the emitted traces to produce the benchmark table for the required profiles

### TPERF-02 Immediate Tab Presentation And Async Startup

Status: complete

Delivered:

- terminal tabs are inserted immediately
- startup phases are explicit and user-visible
- hosted session creation and attach happen after visible presentation

### TPERF-03 Unconditional Host Warmup

Status: complete

Delivered:

- host warmup is no longer gated by `restoreTerminalSessions`
- shell-scene activation proactively warms the detached host
- host warmup state is explicit and tested

### TPERF-04 Fast Local Shell Launch Profile

Status: complete

Delivered:

- explicit `fast_shell` and `compatibility_shell` launch profiles
- blank local shell tabs use the fast profile
- workflow, launcher, agent, and compatibility-sensitive paths stay on the compatibility profile
- daemon transport and tests carry the launch profile explicitly

### TPERF-05 Bounded Attach Replay Contract

Status: complete

Delivered:

- explicit attach replay budget in transport and daemon contracts
- bounded retained PTY output
- reattach can skip replay once the session has already produced a first surface update
- replay budget tests

### TPERF-06 Glyph Atlas Startup And Upload Fixes

Status: complete

Delivered:

- ASCII and common block glyph preload
- batched runtime miss preparation
- partial atlas subregion uploads only
- glyph atlas tests for preload and batched misses

### TPERF-07 Event-Driven Render Scheduling And Shared Renderer Resources

Status: complete

Delivered:

- `GhosttyTerminalView` now uses on-demand `MTKView` configuration
- redraws are requested explicitly instead of free-running continuously
- redundant draw requests are suppressed when render inputs have not changed
- terminal pipeline reuse is shared per device
- shared renderer resources are cached explicitly by device, font metrics, and scale
- renderer resource tests added
- startup viewport notification no longer forces an eager extra draw before the measured viewport callback applies
- the shared host now maintains a stable on-demand first frame instead of amplifying buffer-rotation flicker with redundant startup draws

### TPERF-08 Exact Dirty-Row GPU Upload Path

Status: complete

Delivered:

- row-range aware packing
- partial dirty row replacement in the flattened cache
- active-buffer-only terminal cell uploads
- correct buffer rotation after commit
- dirty-row upload tests in `Packages/Rendering`
- per-buffer revision tracking now forces a full rebase upload when rotation advances to an unprimed Metal buffer
- clean redraws and partial redraws after rotation now preserve the cached terminal frame instead of presenting stale or blank content
- block-cursor-only dirty frames rebuild the old and new cursor rows without requiring broader VT dirtiness

### TPERF-09 Validation, Benchmark Pass, And Docs Closeout

Status: in progress

Delivered:

- `swift test` passes in `Packages/Rendering`
- `swift test` passes in `Packages/GhosttyTerminal`
- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build` passes
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passes
- targeted mac-client terminal validation passes for startup lifecycle, workspace registry, and warmup coverage
- durable runtime contract updated in `.docs/reference/terminal-runtime.md`

Still required before plan closure:

- run the six benchmark profiles using the terminal-open traces
- capture p50 and p95 numbers for each relevant checkpoint pair
- compare the measured values against every strict acceptance threshold in this file
- if any threshold misses, reopen the responsible ticket instead of closing the plan
- if all thresholds pass, delete this plan and leave only the durable runtime reference

### TPERF-10 Viewport-First Hosted Startup

Status: complete

Delivered:

- hosted terminal tabs mount the live `GhosttyTerminalView` immediately and keep startup UI as an overlay
- hosted startup tracks explicit measured viewport state instead of inferring first geometry from placeholder surface dimensions
- first attach is blocked until a measured viewport exists for UI-hosted sessions
- the local Ghostty VT runtime initializes lazily from the measured viewport instead of a fake `120x40`
- readiness now requires host readiness, measured viewport application, and the first real surface update

Scope:

- mount the live `GhosttyTerminalView` immediately for hosted terminal tabs and keep startup UI as an overlay instead of a replacement
- introduce explicit hosted-terminal viewport startup state instead of deriving startup geometry from placeholder `surfaceState`
- block first attach for UI-hosted sessions until the first measured viewport exists
- stop creating the local Ghostty VT runtime at a fake `120x40` size for tabs that have not yet measured
- ensure the first runtime resize and the first attach use the same measured viewport payload

Primary files:

- `Apps/mac-client/Sources/mac/Views/Window/TabContentView.swift`
- `Apps/mac-client/Sources/mac/Services/HostedLocalTerminalController.swift`
- `Apps/mac-client/Sources/mac/Services/TerminalSessionStartupLifecycle.swift`
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyTerminalView.swift`
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyTerminalSession.swift`

Exit criteria:

- hosted terminal tabs measure viewport before first attach
- no launcher or plain-shell startup path attaches using placeholder controller dimensions
- the startup overlay does not prevent early viewport measurement
- readiness requires measured viewport plus first surface update after that viewport is applied

### TPERF-11 Initial-Size Host Session Creation And Restore

Status: complete

Delivered:

- detached-host `createSession` now carries explicit initial terminal dimensions
- `forkpty` uses those initial dimensions instead of a hard-coded `120x40`
- hosted session persistence and restore paths can reuse last known viewport size
- targeted daemon, registry, and startup tests cover the initial-size contract end to end

Scope:

- extend the detached host `createSession` transport to carry initial `cols` and `rows`
- use those explicit dimensions for `forkpty` instead of hard-coded `120x40`
- persist or reuse the last known viewport for restore and reattach paths that start without a visible tab
- keep attach replay bounded without reintroducing any snapshot rendering fallback

Primary files:

- `Apps/mac-client/Sources/mac/Services/TerminalHostTransport.swift`
- `Apps/mac-client/Sources/mac/Services/PersistentTerminalHostController.swift`
- `Apps/mac-client/Sources/mac/Services/PersistentTerminalHostDaemon.swift`
- `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
- `Apps/mac-client/Sources/mac/Services/TerminalHostModels.swift`

Exit criteria:

- PTY creation uses explicit initial dimensions when available
- no UI-hosted session falls back to `120x40` on first spawn
- restored sessions without a visible host can reuse last known dimensions instead of fake defaults
- daemon and transport tests prove the initial-size contract end to end

### TPERF-12 Launcher Command Staging And Startup Readiness Proof

Status: complete

Delivered:

- Claude and Codex launcher commands are staged until after viewport measurement and first attach
- terminal open traces now record `viewport_measured` and `viewport_applied`
- targeted startup tests cover viewport-gated readiness and launcher ordering
- the durable startup contract is updated in `.docs/reference/terminal-runtime.md`

Scope:

- ensure Claude and Codex launcher commands are staged until after the measured viewport handshake and first attach
- keep fast-shell and compatibility-shell policy explicit while separating command staging from PTY creation
- add startup trace checkpoints and tests that prove viewport measurement, viewport application, first output, and readiness happen in the intended order
- update the terminal runtime reference if the supported startup contract changes

Primary files:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView+LaunchActions.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+TerminalPersistence.swift`
- `Apps/mac-client/Sources/mac/Services/HostedLocalTerminalController.swift`
- `Apps/mac-client/Sources/mac/Services/TerminalOpenPerformanceTracker.swift`
- `.docs/reference/terminal-runtime.md`

Exit criteria:

- Claude and Codex do not emit first wrapped output at the wrong width
- launcher command execution begins only after the measured viewport has been applied to the session
- trace output can prove `viewport_measured -> viewport_applied -> first_output_chunk -> first_surface_update`
- targeted tests cover launcher staging and startup ordering

### TPERF-13 Launcher Compatibility Shell Contract Correction

Status: complete

Delivered:

- built-in Claude and Codex launcher tabs now use `compatibility_shell`
- built-in launcher commands no longer route through detached-host `-c` execution
- launcher auto-run still begins only after the measured viewport, session creation, and attach path completes
- targeted startup tests now assert the compatibility-shell launcher contract

Scope:

- keep built-in Claude and Codex launcher tabs on the explicit compatibility shell path
- stop routing built-in launcher commands through PTY creation-time `-c` execution
- ensure launcher command execution still starts only after viewport measurement, session creation, and attach
- align tests and the runtime reference with the shipped launcher contract

Exit criteria:

- launcher tabs use `compatibility_shell`
- built-in launcher tabs do not execute the launcher command until after attach
- targeted tests prove the launcher contract instead of codifying `fast_shell`

### TPERF-14 Launcher Executable Preflight And Inline Failure

Status: complete

Delivered:

- built-in launcher auto-run now preflights `claude` and `codex` inside the attached shell
- missing launcher executables now print an explicit inline terminal failure instead of opening a broken tab
- staged launcher templates still preserve non-auto-run behavior

Scope:

- preflight built-in launcher executables inside the attached shell before auto-executing the command
- surface missing `claude` or `codex` executables as explicit terminal-visible failures
- preserve staged-in-terminal behavior for launcher templates that are configured not to auto-run

Exit criteria:

- launcher buttons fail visibly and deterministically when the executable is missing
- auto-run launcher sessions execute the command from staged terminal input, not from detached-host `-c`
- staged launcher sessions still open with the command present but not yet executed

### TPERF-15 Non-Blocking Terminal Startup Chrome

Status: complete

Delivered:

- the full-pane startup replacement is removed
- terminal startup state now renders as lightweight overlay chrome
- the live terminal host stays visible and mounted throughout startup and failure presentation

Scope:

- replace the full-pane startup mask with lightweight overlay chrome
- keep the live `GhosttyTerminalView` visible and mounted throughout startup
- preserve explicit startup and failure messaging without hiding the terminal surface

Exit criteria:

- opening a shell does not show an opaque loading replacement over the full pane
- startup state remains visible without blocking the first live frame
- failure UI remains readable and actionable

### TPERF-16 Proactive Metal Renderer Warmup

Status: complete

Delivered:

- shared Metal terminal renderer resources now have an explicit warmup API in `GhosttyTerminal`
- macOS app startup now proactively warms renderer resources alongside detached-host warmup
- targeted warmup tests cover the once-per-lifecycle app warmup state and shared renderer preparation

Scope:

- prewarm shared terminal renderer resources during app launch or first shell-scene activation
- avoid first-terminal cold costs for Metal pipeline and glyph atlas setup when the host is otherwise already warm
- keep renderer ownership inside `GhosttyTerminal` and host warmup ownership inside `Apps/mac-client`

Exit criteria:

- app startup proactively requests shared terminal renderer resources once per process
- the first terminal open does not pay avoidable shared renderer initialization cost
- renderer warmup is explicit and covered by targeted tests where feasible

### TPERF-17 Production-Safe Terminal Startup And Render Failures

Status: complete

Delivered:

- VT runtime initialization failure now transitions the session into an explicit failed startup state instead of crashing
- Metal renderer initialization failure now reports through the shared terminal view callback path instead of silently failing
- the runtime reference now documents explicit startup failure surfacing

Scope:

- replace terminal VT runtime `fatalError` paths with explicit startup failure state
- replace silent `try?` renderer initialization failure with explicit failure reporting
- keep failure diagnostics visible to the user and observable in tests

Exit criteria:

- VT runtime initialization failure does not crash the app
- renderer initialization failure transitions the session into a visible failed startup state
- startup failure tests cover both host/runtime and renderer error surfacing

### TPERF-18 Benchmark Report And Acceptance Gate

Status: in progress

Delivered:

- added `scripts/terminal-benchmark-report.mjs` to summarize terminal-open trace samples into profile tables
- the benchmark report path now has a concrete repo-local command instead of an implied manual log sweep
- the benchmark report script validates cleanly with `node --check`

Scope:

- add a repeatable report path for the six benchmark profiles using the emitted terminal-open traces
- summarize the required checkpoint pairs as p50 and p95 values
- make the closeout path explicit enough that acceptance misses reopen the responsible ticket instead of silently closing the plan

Exit criteria:

- the repo has a documented command or script that turns terminal-open traces into the benchmark table
- benchmark output includes the strict checkpoint pairs needed by this plan
- plan closeout has an explicit gate instead of a manual best-effort sweep

### TPERF-19 Launcher Auto-Run Script Validity

Status: complete

Delivered:

- built-in launcher auto-run now emits a valid multiline shell script instead of an invalid one-line `if/then/else/fi` sequence
- launcher auto-run uses an explicit command terminator that behaves like pressing Return in the attached shell
- targeted tests now syntax-check the generated launcher script with `zsh -n`

Scope:

- replace the broken one-line launcher preflight script with a syntactically valid multiline shell script
- ensure built-in launcher auto-run terminates the staged command as interactive shell input instead of relying on a fragile trailing newline
- add targeted coverage that proves the generated shell script is valid

Exit criteria:

- pressing the Claude or Codex launcher button no longer drops the shell into `then>` continuation state
- launcher preflight still prints the inline missing-executable message when `claude` or `codex` is absent
- targeted tests prove the generated shell script parses successfully

### TPERF-20 Prompt-Safe Launcher Input Delivery

Status: complete

Delivered:

- built-in launcher auto-run no longer relies on staged terminal input after attach
- launcher auto-run now uses the compatibility-shell startup command path and returns to an interactive login shell after the launcher exits
- stage-in-terminal remains available only for templates that intentionally open text at the prompt instead of executing immediately

Scope:

- stop treating `runImmediately` as a staged prompt-input feature
- execute built-in launcher auto-run from the compatibility-shell startup command path so the shell runs the launcher before exposing an interactive prompt
- keep `stageInTerminal` available for templates that intentionally want visible prompt text instead of immediate execution

Exit criteria:

- launcher auto-run no longer appears as pasted or typed shell text at the prompt
- launcher buttons start from the measured viewport and interactive shell compatibility path without depending on prompt-input delivery
- launcher tabs remain usable after the launched tool exits

### TPERF-21 Rendered-Frame Startup Readiness Gate

Status: complete

Delivered:

- terminal startup no longer becomes `ready` on the first VT surface update alone
- readiness now requires both the first surface update and the first rendered interactive terminal frame
- targeted startup tests now prove that surface updates alone do not clear startup state
- readiness now also requires the first PTY output chunk, so a blank projected grid is not treated as a stable visible shell presentation
- runtime docs and targeted startup tests now cover the stronger readiness contract explicitly

Scope:

- keep first-surface-update instrumentation for performance traces without treating it as user-visible readiness
- gate terminal startup readiness on rendered terminal presentation instead of VT state mutation alone
- align targeted tests and runtime docs with the rendered-frame startup contract

Exit criteria:

- the startup overlay does not disappear before the terminal has rendered interactive content
- readiness reflects actual terminal presentation, not only VT projection updates
- targeted tests prove the new readiness contract

### TPERF-22 First-Draw Retry For On-Demand Metal Startup

Status: complete

Delivered:

- the shared terminal Metal renderer now reports startup drawable-unavailable conditions back to the host
- macOS and iOS terminal host views now retry the first on-demand draw instead of dropping it permanently
- on-demand draw requests now force an immediate draw when the host is already attached to a live window

Scope:

- detect startup draw attempts that fail because the `MTKView` cannot yet provide a drawable or render pass
- schedule a bounded retry from the shared host instead of waiting for unrelated UI invalidation
- keep the on-demand rendering model while hardening first-frame startup reliability

Exit criteria:

- the first real terminal frame is not lost permanently just because the initial on-demand draw happened too early
- opening another tab or forcing unrelated layout is no longer required for a launched terminal to appear
- the shared on-demand Metal host stays event-driven while becoming reliable on cold startup
