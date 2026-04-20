# Devys Terminal Runtime Reference

Updated: 2026-04-19

## Purpose

This document is the canonical reference for the shipped Devys terminal runtime and host contract.

It describes the supported terminal architecture, rendering rules, and product boundary. It is not an active plan.

## Supported Architecture

Devys ships one terminal product path:

- `libghostty-vt` is the terminal runtime
- `GhosttyTerminalFrameProjection` is the projection contract
- shared Metal rendering is the only supported renderer path
- `GhosttyTerminalView` is the shared host on macOS and iOS

The supported implementation boundary is:

- `GhosttyVTRuntime` and `GhosttyVTCore` own terminal engine lifecycle, render-state updates, resize, scroll, paste encoding, and explicit utility reads
- `GhosttyVTCore.surfaceUpdate()` builds `GhosttyTerminalSurfaceUpdate` from one direct render-state projection path
- `GhosttyTerminalFrameProjection` is the rendering contract consumed upward
- `Packages/Rendering` owns terminal Metal primitives and pure packing helpers
- app hosts remain thin and wire terminal state plus callbacks into the shared host

`screenText()` remains only as an explicit non-rendering utility used for copy or export fallback when no selection exists. It is not part of the render hot path.

## Rendering Rules

- render-state row iteration is the only source of visible terminal rows and cells
- dirty handling is exact:
  - `clean` means no row rebuild
  - `partial` means only Ghostty-marked dirty rows rebuild
  - `full` means a full viewport redraw for explicit engine reasons such as resize or viewport change
- row dirty flags are cleared when projection consumes them
- the global dirty flag is reset explicitly after the frame is projected
- terminal row-cache invalidation policy and pure GPU cell packing live in `Packages/Rendering`
- terminal default foreground, background, cursor color, and light/dark scheme come from Devys theme tokens
- the ANSI 16-color palette is set explicitly to the supported Ghostty-compatible palette contract
- explicit ANSI, 256-color, truecolor, and OSC-driven terminal program colors are rendered by the VT/runtime contract, not recolored in the Metal host
- hosted local sessions advertise `TERM=xterm-ghostty` and ship a bundled `terminfo` entry with the mac app target
- block-drawing terminal glyphs are rasterized explicitly and sampled with nearest filtering to avoid visible seams in ANSI art
- printable ASCII and common block-drawing glyphs are preloaded into the terminal atlas before first interactive use
- runtime glyph misses are prepared in batches and upload only the touched atlas subregion
- partial dirty frames repack and upload only the dirty row ranges
- terminal cell uploads write only the active GPU buffer for the frame
- the shared Metal host renders on demand and does not free-run while idle
- the shared Metal host retries startup draws when the first on-demand render pass cannot acquire a drawable yet
- shared terminal renderer resources are cached explicitly by the inputs that matter, including device, font metrics, and scale

## Unsupported Product Paths

These are not supported steady-state product paths:

- viewport projection fallbacks
- snapshot-driven rendering fallbacks
- parallel terminal host stacks

## Startup And Attach Contract

- macOS shell-scene activation proactively warms the detached terminal host and this warmup is not gated by `restoreTerminalSessions`
- opening a terminal tab inserts the tab immediately and surfaces an explicit startup state while host startup, session creation, and attach finish in the background
- UI-hosted terminal tabs mount the live `GhosttyTerminalView` immediately so viewport measurement happens before first spawn and attach
- a UI-hosted session does not create its PTY or send its first attach request until the terminal view has reported an explicit measured viewport
- the local Ghostty VT runtime is initialized from the first measured viewport instead of a fake `120x40` placeholder grid
- the detached host `createSession` contract carries explicit initial `cols` and `rows`, and PTY creation uses that size instead of a hard-coded default whenever the UI has already measured the viewport
- launcher tabs still wait for the measured viewport before PTY creation, but built-in auto-run executes from the compatibility-shell startup command instead of pasting text into a live prompt
- built-in launcher auto-run uses a valid multiline shell script passed through PTY creation-time `-c`, and that script `exec`s back into an interactive login shell after the launcher command exits
- blank local terminal tabs use the explicit fast shell launch profile
- workflow, launcher, and compatibility-sensitive terminal entry points keep the explicit compatibility shell launch profile unless configured otherwise
- startup does not become `ready` until the first PTY output chunk, the first VT surface update, and the first rendered interactive terminal frame have all happened
- terminal VT runtime and Metal renderer startup failures surface an explicit failed startup state instead of crashing or silently presenting a blank terminal
- hosted-session attach uses an explicit bounded replay budget
- the host retains only a bounded recent PTY transcript and attach does not depend on replaying the full retained output through the client runtime
- once a hosted session has already produced its first surface update, reattach does not replay buffered PTY output again

## Supported Host Contract

### macOS

Supported:

- direct keyboard text input from AppKit key events
- special keys:
  - enter
  - tab and backtab
  - backspace and delete
  - escape
  - arrows
  - home and end
  - page up and page down
- control-modified input
- option-modified input
- selection drag
- double-click word selection
- copy current selection with `Cmd-C`
- paste plain text with `Cmd-V`
- viewport resize
- mouse-wheel scrollback

Intentionally unsupported:

- marked-text IME composition via `NSTextInputClient`
- link hit testing
- hover affordances
- screen-reader cell-by-cell terminal semantics

Accessibility surface:

- the shared host exposes a terminal accessibility element with role, label, help text, and current grid-size value

### iOS

Supported:

- hardware keyboard text input
- hardware keyboard special keys through `UIKeyCommand`
- ASCII software keyboard direct text input through `UIKeyInput`
- control-modified hardware-keyboard input
- option-modified hardware-keyboard input
- touch selection mode with drag selection
- double-tap word selection
- copy selected text
- paste plain text from the system pasteboard
- accessory-row terminal actions
- viewport resize
- scrollback by gesture and accessory actions

Intentionally unsupported:

- non-ASCII marked-text IME composition
- system text-selection handles and native text-edit menus as terminal authorities
- link hit testing
- hover affordances
- screen-reader cell-by-cell terminal semantics

Accessibility surface:

- the shared host exposes a terminal accessibility element with label, hint, and current grid-size value
