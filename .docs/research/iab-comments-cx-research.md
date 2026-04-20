# Browser Comments CX Research

Comprehensive reverse-engineering notes on the Codex macOS browser comment / annotation feature shipped inside the Codex app bundle. This focuses on the feature where a browser tab stays open and Codex lets you hover UI, click elements, drag regions, and attach comments directly to page content.

This is based on local bundle inspection of the installed app, extracted `app.asar` assets, and targeted string/code analysis of the browser runtime. It is not based on public marketing copy alone.

## Scope

This document covers:

- where the browser comment feature lives in the Codex bundle
- how it is separated from browser automation itself
- the page overlay runtime
- the Electron host/controller runtime
- the comment model and anchor model
- the screenshot capture flow
- per-site capability gating
- why the system is robust across dynamic DOM changes
- how we could recreate a comparable feature in Devys

## Executive Summary

The browser comment feature is a distinct annotation system layered on top of Codex's browser control stack.

The strongest evidence supports this split:

1. Browser automation is provided by the bundled browser client runtime in:
   - `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/browser-use/scripts/browser-client.mjs`
   - `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/browser-client.mjs`
2. The browser comment UI is implemented by an injected page overlay preload in:
   - `/tmp/codex_browser_probe/browser-sidebar-comment-preload.js`
3. The comment editor, session orchestration, site gating, and screenshot capture are handled by Electron host code in:
   - `/tmp/codex_browser_host/main-CUDSf52Z.js`
4. Shared thread/comment state is backed by comment/collaboration bundles in:
   - `/tmp/codex_browser_probe2/comments-BL219IPZ.js`
   - `/tmp/codex_browser_host/comments-collab-store-CaMLpxiK.js`

The runtime model appears to be:

- a browser automation substrate that can inspect and act on tabs
- a page-injected overlay that handles hover, click, drag, markers, and previews
- a separate popup editor window managed by Electron
- a browser comment snapshot model that stores anchors plus optional screenshots
- a message bridge between the page and host
- policy gating so comment mode or related agent/browser behavior can be blocked per site

This is not just "draw a rectangle in the DOM." The implementation is frame-aware, shadow-DOM-aware, geometry-aware, and synchronized with screenshot capture so saved comments can include the exact highlight state the user saw when the comment was created.

## Investigation Method

The findings here came from:

- listing bundled plugins under `Codex.app`
- comparing browser plugin artifacts
- extracting `app.asar` assets with `npx asar`
- grepping minified preload and Electron main bundles for message names, controller classes, CSS class names, and comment model fields
- inspecting the browser automation client for socket names, runtime setup, and DOM/CDP integration

## Artifact Inventory

### Browser automation substrate

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/browser-use/scripts/browser-client.mjs`
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/browser-client.mjs`

These two files are byte-identical and represent the shared browser control client.

### Extracted Electron/browser assets

The relevant files were located in `app.asar` and extracted for inspection:

- `/.vite/build/browser-sidebar-comment-preload.js`
- `/webview/assets/comments-BL219IPZ.js`
- `/webview/assets/comments-collab-store-CaMLpxiK.js`
- `/.vite/build/main-CUDSf52Z.js`

Extracted working copies used during inspection:

- `/tmp/codex_browser_probe/browser-sidebar-comment-preload.js`
- `/tmp/codex_browser_probe2/comments-BL219IPZ.js`
- `/tmp/codex_browser_host/comments-collab-store-CaMLpxiK.js`
- `/tmp/codex_browser_host/main-CUDSf52Z.js`

These `/tmp` paths are analysis artifacts, not canonical bundle locations.

## Architecture Overview

The browser comment feature appears to have three major layers.

### 1. Browser control runtime

The browser control runtime exposes browser automation and DOM inspection APIs over local sockets. It supports:

- an in-app browser backend
- a Chrome extension/native-host backend
- Playwright-style selectors
- CDP-backed DOM inspection
- DOM-based browser CUA actions
- coordinate-based browser CUA actions

The relevant socket paths embedded in `browser-client.mjs` are:

- `/tmp/codex-browser-use-iab.sock` for the in-app browser backend
- `/tmp/codex-browser-use.sock` for the Chrome/native-host backend

The browser client labels these backends as:

- `Codex In-app Browser`
- `Chrome`

Important runtime names present in the client bundle:

- `PlaywrightLocator`
- `PlaywrightAPI`
- `DomCUAAPI`
- `CUAAPI`
- `setupAtlasRuntime`
- `window.__codexPlaywrightInjected`
- `data-codex-playwright-match`

This tells us the browser runtime is not just visual automation. It has a structured DOM/CDP path for tab automation and element resolution.

### 2. Page overlay runtime

The annotation UI itself is injected into the page by `browser-sidebar-comment-preload.js`. This runtime:

- mounts a shadow DOM overlay into the active page
- listens to pointer, mouse, keyboard, and scroll/resize events
- resolves target elements from page coordinates
- supports clicks for element comments
- supports drags for region comments
- renders markers, hover boxes, selection regions, and previews
- maintains enough metadata to refind anchors later
- communicates with the Electron host over explicit IPC channels

### 3. Electron host/controller

The Electron main bundle manages:

- comment-mode orchestration
- popup editor windows
- anchor synchronization
- screenshot capture
- comment create/edit/delete flows
- host-to-page runtime sync
- site-level policy checks

This means the visible feature is split deliberately:

- page overlay for picking and rendering
- host popup for editing and persistence

That split is important because it avoids site CSS/JS conflicts and gives Codex full control over focus, geometry, and screenshot capture.

## Browser Automation Substrate

The annotation feature is adjacent to, but separate from, the browser-use automation stack.

`browser-client.mjs` shows that Codex uses a local JSON-RPC transport over a length-prefixed local socket. It expects turn metadata from:

- `globalThis.nodeRepl?.requestMeta?.["x-codex-turn-metadata"]`

It requires:

- `session_id`
- `turn_id`

for session requests.

The browser runtime exposes capabilities such as:

- DOM snapshots
- visible DOM retrieval
- element info
- element screenshots
- Playwright-style locator actions
- coordinate browser CUA actions such as click and scroll
- DOM-node-based browser CUA actions such as `dom_cua.click`

That strongly suggests the browser comment feature can rely on a much richer browser substrate than raw screen pixels.

## Page Overlay Runtime

The core browser comment implementation lives in:

- `/tmp/codex_browser_probe/browser-sidebar-comment-preload.js`

### Overlay mounting

The preload creates a fixed overlay host element, attaches a shadow root, and mounts a React tree into it. The entry path includes functions named:

- `qs`
- `Js`
- `sc`

The overlay uses a high-z-index fixed-position layer and renders its own styles inside the shadow root. This isolates the comment UI from the page's CSS.

### Host/page bridge

The bridge is explicit and easy to identify.

Host to page channel:

- `codex_desktop:message-for-view`

Page to host channel:

- `codex_desktop:browser-sidebar-runtime-message`

The preload handles host messages:

- `browser-sidebar-runtime-sync`
- `browser-sidebar-runtime-prepare-comment-screenshot`
- `browser-sidebar-runtime-clear-comment-screenshot`
- `browser-sidebar-runtime-select-comment`
- `browser-sidebar-runtime-close-editor`

The preload sends host messages:

- `browser-sidebar-runtime-open-editor`
- `browser-sidebar-runtime-update-anchor`
- `browser-sidebar-runtime-focus-editor`
- `browser-sidebar-runtime-stop-agent-control`
- `browser-sidebar-runtime-exit-comment-mode`
- `browser-sidebar-runtime-comment-screenshot-ready`
- `browser-sidebar-runtime-mouse-navigation`

This is the fundamental control contract for the feature.

### Runtime state

The preload holds browser comment runtime state that includes:

- `comments`
- `interactionMode`
- `isAgentControllingBrowser`
- `intlConfig`

The default state visible in the bundle is:

- `interactionMode: "browse"`
- `isAgentControllingBrowser: false`

When `interactionMode === "comment"`, the overlay becomes interactive for annotation instead of passive.

### Visual affordances

The page overlay includes explicit CSS/class names for the browser comment UI:

- `.agent-control-blocker`
- `.agent-control-shimmer`
- `.hover-box`
- `.region-box`
- `.posted-region-highlight`
- `.markers-layer`
- `.marker`
- `.saved-marker`
- `.draft-marker`
- `.element-metadata-tooltip`
- `.comment-preview`
- `.comment-preview-body`
- `.comment-preview-mention`

These map directly to the visible product behavior:

- hover outlines
- drag-to-select regions
- numbered or saved markers
- a temporary draft marker while editing
- metadata and preview tooltips
- a blocker overlay when the browser is under agent control

### Interaction flow in the page

The preload listens in the capture phase for:

- `pointerdown`
- `pointermove`
- `pointerup`
- `pointercancel`
- `mousemove`
- `mouseout`
- `keydown`
- `click`

It also listens for:

- scroll
- resize
- blur

Behavior inferred from the code path:

1. In comment mode, moving the pointer updates the current hovered target and renders a hover box.
2. A simple click resolves a target element and sends `browser-sidebar-runtime-open-editor` for an element comment.
3. A drag above a movement threshold turns into a region selection and opens the editor with a region anchor.
4. Escape cancels drag or exits comment mode.
5. Clicking an existing marker opens the editor in edit mode for that saved comment.
6. While the editor is open, the preload keeps updating the anchor if the page scrolls or layout changes.

### Element resolution and frame handling

This runtime is not limited to the top document.

The code is clearly:

- iframe-aware
- shadow-DOM-aware
- point-to-element aware across nested browsing contexts

Functions involved in that logic include helpers like:

- `xc`
- `Sc`
- `Cc`
- `wc`
- `cc`

The preload traverses iframes recursively, translates coordinates across frame boundaries, and walks composed paths. This is one of the reasons the feature feels much more robust than a simple DOM extension.

### Hover metadata

When hovering UI in comment mode, the overlay computes style and geometry metadata about the current element. That metadata includes values such as:

- `tagName`
- `size`
- `color`
- `font`
- `borderRadius`

That explains the "inspect and comment on UI items" feel. The runtime is not just selecting an element; it is also collecting presentation metadata for the current target.

## Anchor Model

The feature uses a richer anchor model than a plain selector.

### Element anchors

The element anchor construction path includes data like:

- `pageUrl`
- `frameUrl`
- `title`
- `elementPath`
- `point`
- `rect`
- `isFixed`
- `role`
- `name`
- `selector`
- `framePath`
- `nearbyText`

This gives the system multiple ways to relocate the same target later.

### Region anchors

Region anchors include comparable page/frame identity plus region geometry and scroll-context information. That allows the feature to:

- attach comments to layout regions instead of only discrete DOM elements
- maintain highlight placement even if the DOM structure shifts

### Re-finding targets

The preload contains a reconstruction path that tries to refind a target from stored anchor data. The logic appears to use:

- selector matching
- frame path matching
- page URL matching
- geometry/viewport normalization
- fallback to nearby clickable or matching elements

This is why the system can survive moderate page churn instead of breaking immediately when the DOM changes.

## Comment Model And Collaboration Layer

The extracted comments bundles suggest that browser comments reuse a more general comment/thread infrastructure.

Relevant bundles:

- `/tmp/codex_browser_probe2/comments-BL219IPZ.js`
- `/tmp/codex_browser_host/comments-collab-store-CaMLpxiK.js`

Observed capabilities include:

- thread and comment IDs
- replies
- reactions
- citations
- resolve/reopen flows
- shared snapshot or collaboration-store abstractions

This suggests the browser annotation feature is not a one-off UI widget. It plugs into a broader internal comments system, with browser anchors as one specific comment target type.

## Host Controller Runtime

The host orchestration lives in:

- `/tmp/codex_browser_host/main-CUDSf52Z.js`

### Core IPC constants

The Electron main bundle contains:

- `W = "codex_desktop:message-for-view"`
- `dn = "codex_desktop:browser-sidebar-runtime-message"`

That matches the preload bridge exactly.

### Site gating and policy

One of the most important findings is that comment-related browser capability appears to be site-gated.

The main bundle includes logic around:

- `/aura/site_status?site_url=...`
- hostname normalization
- cached site policy state

Relevant functions/names present in the bundle:

- `ku`
- `Au`
- `ju`
- `Mu`

The cache TTL embedded in the bundle is:

- `1440 * 60 * 1e3`

which is 24 hours.

The site-status response is checked for:

- `feature_status.agent === true`

The naming strongly suggests some sites can be blocked or restricted for agent/browser capabilities, including this annotation experience.

### Overlay window manager

The host bundle contains a controller class named:

- `Iu`

This class manages the floating editor window associated with a browser comment session.

Responsibilities visible in the code include:

- prewarming overlay windows
- opening overlays
- updating anchor placement
- focusing and dismissing overlays
- closing overlays
- transferring overlays across conversation IDs
- claiming renderer-opened windows
- syncing overlay state to the renderer
- updating visibility when the owner window moves, focuses, or minimizes

The overlay uses anchored geometry when possible and falls back to a safer placement otherwise.

Important placement data in the bundle:

- editor width target around `294`
- editor height base around `112`
- placement strategy names like `anchored` and `fallback`

This tells us the editor is not inline in the page. It is a separate Electron popup window positioned relative to the selected anchor.

### Browser comment controller

The host bundle also contains a controller class named:

- `ed`

This appears to be the browser-sidebar comment controller.

Responsibilities visible in code:

- prepare overlay state
- handle runtime open-editor requests
- update anchors
- focus the editor
- wait for screenshot-ready events
- submit comment create/edit operations
- delete comments
- close editors
- capture screenshots
- sync runtime state back to the page

Important method names visible in the minified bundle:

- `prepare`
- `dismiss`
- `close`
- `transferConversation`
- `handleOverlayMounted`
- `handleRuntimeOpenEditor`
- `handleRuntimeUpdateAnchor`
- `handleRuntimeFocusEditor`
- `handleRuntimeCommentScreenshotReady`
- `handleOverlaySubmit`
- `handleOverlayDelete`
- `handleOverlayClose`
- `captureBrowserScreenshot`
- `captureSavedCommentScreenshot`
- `captureDirectCommentScreenshot`
- `syncRuntimeStateToPage`
- `closeRuntimeEditor`
- `waitForRuntimeCommentScreenshotReady`

This is the strongest evidence for the end-to-end comment flow.

## Screenshot Capture Flow

The screenshot path is one of the clearest and most important implementation details.

The host does not capture a screenshot blindly. Instead it coordinates with the page runtime so the annotation overlay is in the right visual state at capture time.

The flow appears to be:

1. The host tells the page runtime to prepare the selected comment screenshot using:
   - `browser-sidebar-runtime-prepare-comment-screenshot`
2. The preload renders the right selected marker/highlight state.
3. Once the page is visually ready, the preload sends:
   - `browser-sidebar-runtime-comment-screenshot-ready`
4. The host calls `capturePage()` on the browser contents.
5. The host stores the screenshot in the comment snapshot.
6. The host tells the page to clean up temporary capture state using:
   - `browser-sidebar-runtime-clear-comment-screenshot`

The host waits up to a bundled timeout before capture:

- `1000` ms

That is important because it means the saved screenshot is intentionally synchronized with the page-side marker/highlight rendering. This is a much better design than trying to reconstruct the annotation later at render time.

## Comment Snapshot Shape

The host bundle contains a helper that creates browser comment snapshots with fields including:

- `id`
- `body`
- `createdAt`
- `anchor`
- `color: "blue"`
- `markerViewportPoint`
- optional `attachedImages`
- optional `screenshot`
- optional `viewportSize`

This indicates a saved browser comment is not just text plus selector. It is a richer serialized object designed to support:

- stable marker placement
- image previews
- thread replay or auditing
- more reliable restoration when reopened later

## Direct Comment Vs Saved Comment Paths

The host bundle appears to support more than one submit path.

There is evidence of a direct-submit mode:

- `submitDirectly === true`

That path appears to:

- create the comment payload directly
- wait for the page screenshot-ready signal
- capture a screenshot immediately
- send a `browser-sidebar-direct-comment` event back to the owning context

There is also a saved comment screenshot flow for persistent comments. This implies the system may support both:

- immediate direct annotation handoff
- persistent threaded comments stored in the collaboration system

## Agent-Control Blocker

The preload explicitly handles the case where the browser is actively being controlled by an agent.

Runtime state includes:

- `isAgentControllingBrowser`

When that is true, and the environment check passes, the overlay shows a blocker UI and intercepts certain interactions. The CSS class names make this clear:

- `.agent-control-blocker`
- `.agent-control-shimmer`

The preload also sends:

- `browser-sidebar-runtime-stop-agent-control`

That suggests the browser comment mode is integrated with the broader browser agent runtime so the user can interrupt active agent control before manually annotating the page.

## Mouse Navigation Handling

An interesting smaller feature in the preload is explicit handling for mouse back/forward buttons.

The preload intercepts:

- button `3` as `back`
- button `4` as `forward`

and sends:

- `browser-sidebar-runtime-mouse-navigation`

This is small, but it shows the overlay runtime is trying to preserve a real browsing experience even while it is sitting between the page and the user.

## Why The System Works Well

The strongest reasons this feature is robust are:

### 1. It isolates page UI from editor UI

The page only renders overlays, markers, and previews. The editor itself is a separate host-managed popup. That avoids:

- site CSS collisions
- z-index fights
- focus traps inside the page
- layout breakage from inline editing widgets

### 2. It stores rich anchors instead of plain selectors

Anchors include page, frame, selector, geometry, accessible labeling, and nearby text. That gives the system multiple relocation strategies.

### 3. It is frame-aware and shadow-DOM-aware

Many browser annotation systems break on embedded apps or component-heavy sites. This runtime clearly tries to cross those boundaries.

### 4. It synchronizes screenshot capture with rendered overlay state

That yields accurate visual snapshots and avoids race conditions between page rendering and capture.

### 5. It has site policy gating

If a site is known to be unsafe or unsupported for agent/browser interaction, the host can block or restrict the feature without changing the page runtime.

### 6. It integrates with the broader browser agent stack

The comment system is not isolated from browser automation. It knows when the browser is under agent control and can coordinate with that state.

## How To Recreate This In Devys

The cleanest recreation is to keep the same architectural split, but implement it in a way that matches Devys ownership rules.

### High-level architecture

Use four layers:

1. `BrowserCommentFeature` reducer domain in TCA
2. `BrowserCommentClient` dependency for host/window/screenshot orchestration
3. page overlay runtime injected into the webview or browser surface
4. shared browser comment model and persistence layer

This maps well to the repo's architecture rules:

- reducer owns state, intent, lifecycle, and workflow
- dependency client owns low-level Electron/AppKit/WebKit/browser execution
- overlay runtime owns only local rendering mechanics inside the page

### Recommended ownership

Reducer-owned state:

- comment mode enabled/disabled
- selected thread/comment
- draft/open editor state
- per-tab comment collections
- site policy state
- screenshot capture lifecycle
- conversation/session linkage

Dependency-owned execution:

- inject/remove preload overlay
- message bridge to page runtime
- popup/panel editor window creation
- browser screenshot capture
- browser viewport geometry
- site policy fetch/caching

Page runtime responsibilities:

- hover detection
- element/region anchor generation
- marker rendering
- region highlight rendering
- element metadata tooltip rendering
- comment preview rendering
- anchor updates during scroll/layout change

### Minimal viable recreation

The fastest convincing clone is:

1. Inject a shadow-DOM overlay into the browser page.
2. Support hover highlight for one target element at a time.
3. On click, build an element anchor with:
   - page URL
   - frame path
   - selector
   - bounding rect
   - nearby text
   - role/name if available
4. Open a separate floating editor window near that anchor.
5. Save a browser comment snapshot.
6. Render persistent numbered markers for saved comments.
7. Add screenshot-ready handshake before capture.

This gets most of the visible product value without immediately needing region comments or deep collaboration support.

### Full-fidelity recreation plan

#### Phase 1. Page overlay foundation

Build:

- shadow-root mount
- capture-phase event listeners
- hover box
- click-to-anchor
- element metadata tooltip
- host bridge

Do not start with inline editors.

#### Phase 2. Host popup editor

Build:

- popup editor window
- anchored geometry near selection
- fallback placement when anchored placement fails
- focus/dismiss/open flows
- create/edit/delete handlers

Keep editor ownership in the host, not the page.

#### Phase 3. Persistent markers and previews

Build:

- saved comment markers
- selected-comment highlight
- hover preview tooltip
- marker click to reopen editor

#### Phase 4. Region comments

Add:

- drag threshold
- region box rendering
- region anchors
- posted-region highlight rendering

#### Phase 5. Screenshot synchronization

Add:

- host `prepare-comment-screenshot` request
- page `comment-screenshot-ready` event
- host `capturePage()` or equivalent
- `clear-comment-screenshot` cleanup step

#### Phase 6. Robust relocation

Add:

- frame path support
- shadow DOM traversal
- nearby-text fallback
- geometry fallback
- best-nearby clickable fallback

#### Phase 7. Policy and agent coordination

Add:

- site allow/block list
- remote site policy later if needed
- agent-control blocker state
- interrupt-active-agent action before annotation

## Concrete Devys Implementation Sketch

One reasonable module split would be:

- `Packages/Browser`
  - low-level browser page bridge, injection, screenshot capture, viewport APIs
- `Packages/AppFeatures`
  - `BrowserCommentsFeature`
  - `BrowserCommentsClient`
  - comment/session reducers
- `Packages/UI`
  - popup editor chrome and comment thread UI primitives

Suggested internal types:

- `BrowserCommentAnchor`
- `BrowserElementAnchor`
- `BrowserRegionAnchor`
- `BrowserCommentSnapshot`
- `BrowserCommentSessionState`
- `BrowserCommentOverlayMessage`
- `BrowserCommentOverlayEvent`

Suggested host/page bridge events:

- `sync`
- `openEditor`
- `updateAnchor`
- `closeEditor`
- `prepareScreenshot`
- `screenshotReady`
- `clearScreenshot`
- `selectComment`
- `exitCommentMode`
- `stopAgentControl`

### Storage model

A useful snapshot shape for Devys would be:

```ts
type BrowserElementAnchor = {
  kind: "element"
  pageUrl: string
  frameUrl?: string | null
  framePath: string[]
  selector?: string | null
  role?: string | null
  name?: string | null
  nearbyText?: string | null
  rect: { x: number; y: number; width: number; height: number }
  point: { xPercent: number; y: number }
  isFixed: boolean
}

type BrowserRegionAnchor = {
  kind: "region"
  pageUrl: string
  frameUrl?: string | null
  framePath: string[]
  rect: { x: number; y: number; width: number; height: number }
  isFixed: boolean
}

type BrowserCommentSnapshot = {
  id: string
  body: string
  createdAt: string
  anchor: BrowserElementAnchor | BrowserRegionAnchor
  markerViewportPoint?: { x: number; y: number } | null
  screenshot?: { dataUrl: string; width: number; height: number } | null
}
```

This mirrors the shape Codex appears to use closely enough to recreate the product behavior.

## What Not To Copy

There are a few things we should preserve conceptually but not necessarily reproduce literally.

### Do not put the editor in the page DOM

That is the easiest implementation, but it is the wrong one. Codex's split is better.

### Do not rely on only CSS selectors

Selectors alone will be too brittle for dynamic apps. We should store at least:

- selector when available
- nearby text
- role/name
- geometry
- frame path

### Do not make screenshot capture best-effort only

The screenshot-ready handshake is one of the most valuable design decisions in the system.

### Do not let the browser package own product workflow

In Devys, reducer state should own session and behavior policy. The browser package should stay an execution boundary.

## Open Questions

There are still a few things this pass did not prove completely.

- Whether browser comments are always tied to the in-app browser, or can also be attached to externally controlled Chrome tabs through the same UI.
- How much of the generic comments/collab stack is shared with non-browser comment surfaces elsewhere in Codex.
- Whether site gating blocks only agent actions, or also the full comment experience on certain sites.
- What persistence boundary stores browser comment snapshots long-term in the desktop app.

These are implementation questions, not architectural blockers. The core browser comment runtime is already clear enough to reproduce.

## Bottom Line

The Codex browser comment feature is a carefully layered annotation system built on top of a richer browser automation substrate.

Its key design choices are:

- page overlay in a shadow DOM
- separate host-managed popup editor
- rich element and region anchors
- frame-aware and shadow-DOM-aware target resolution
- synchronized screenshot capture
- site policy gating
- explicit coordination with active browser agent control

If we recreate those same decisions in Devys, we can build something that feels materially similar instead of a weaker "DOM note widget" approximation.
