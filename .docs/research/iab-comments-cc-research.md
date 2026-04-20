# Codex In-App Browser (IAB) + Click-to-Comment Deep Dive

Reverse-engineering notes on Codex's in-app browser and its "click an element, leave a comment for the agent" feature. Built from inspecting the Electron asar, both bundled plugins, and the preload scripts on disk.

**Source files analyzed**
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/browser-use/` — "browser-use" plugin (backend: `"iab"`)
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/chrome/` — "chrome" plugin (backend: `"chrome"`)
- `.vite/build/bootstrap.js` — Electron entry point
- `.vite/build/main-CUDSf52Z.js` (678 KB) — main-process app code
- `.vite/build/product-name-C630vpQ6.js` (5.2 MB) — shared/renderer code
- `.vite/build/preload.js` — generic view preload (exposes `electronBridge`, `codexWindowType`)
- `.vite/build/browser-sidebar-comment-preload.js` (25 MB) — **the preload for the comment feature** (React app, runs inside the IAB's page context)
- `webview/index.html` + `webview/assets/` — the Codex app's own renderer UI

---

## 0. Executive summary

Codex ships an in-app Chromium BrowserView (Electron `WebContentsView`) called the **browser sidebar** that you can open next to the chat. On top of it sits a **Comment Mode**: when toggled, a React overlay injected via preload highlights the element under your cursor, lets you click one to drop a pin, and opens a composer for a comment — the anchor (URL + CSS selector + bounding box + ARIA name + page-percent position + framePath for iframes) plus the comment text plus a cropped screenshot are attached to the next message you send the agent.

The agent gets two ways to see the page:

1. **As a user** — your comments are included in your next turn, each a structured anchor pointing at the exact element you clicked with the text you wrote.
2. **As an automaton** — the `agent.browser.*` API (`tab.playwright.*`, `tab.cua.*`) drives the same BrowserView over CDP. The plugin's `browser-client.mjs` connects to a Unix socket the main process exposes; the main process forwards requests through `webContents.debugger.sendCommand()` to the attached page.

The two-layer architecture — a shadow-DOM overlay injected into the page for hit-testing/pins, plus a separate native Electron window (`overlayManager`) floating above for the text composer — is a clean trick: the hit-test has to live inside the page's coordinate space, but the textarea should not, because the page's CSS/JS can't be trusted not to break IME, focus, and key events.

The same plumbing works for both `"iab"` (Codex BrowserView) and `"chrome"` (user's real Chrome via a first-party extension with a native-messaging host — that's what gets you "comment on pages" in your real Chrome too).

---

## 1. Process topology

```
┌─────────────────────────────────────────────────────────────┐
│  Codex Electron main process                                 │
│                                                              │
│  ┌───────────────────────────────────┐                       │
│  │ BrowserSidebarManager             │                       │
│  │   windows: Map<owner, WindowState>│                       │
│  │   per-conversation thread state   │                       │
│  │   commentOverlayManager           │                       │
│  │   commentModeBlocklistLookup      │                       │
│  └─────────┬─────────────────────────┘                       │
│            │                                                 │
│            │  creates                                        │
│            ▼                                                 │
│  ┌────────────────────────────────────┐                      │
│  │ WebContentsView (browser sidebar)  │                      │
│  │   preload: browser-sidebar-        │                      │
│  │            comment-preload.js      │                      │
│  │   webContents.debugger.attach(1.3) │◄── CDP bridge        │
│  └───────────┬────────────────────────┘                      │
│              │ (page DOM)                                    │
│              ▼                                               │
│  ┌────────────────────────────────────┐                      │
│  │ React shadow-DOM overlay (in-page) │                      │
│  │   id="codex-browser-sidebar-       │                      │
│  │        comments-root"              │                      │
│  │   • pin markers                    │                      │
│  │   • hit-test highlighter           │                      │
│  │   • comment thread badges          │                      │
│  └────────────────────────────────────┘                      │
│                                                              │
│  ┌────────────────────────────────────┐                      │
│  │ CommentOverlayManager              │                      │
│  │   creates a separate NSWindow       │                      │
│  │   floating above the BrowserView    │                      │
│  │   renders the comment composer      │                      │
│  │   (textarea, submit, attach image)  │                      │
│  └────────────────────────────────────┘                      │
│                                                              │
│  ┌────────────────────────────────────┐                      │
│  │ CDP IPC server (Unix socket)        │                      │
│  │   server = net.createServer()       │                      │
│  │   pipePath = tmpdir/uuid.sock       │                      │
│  │   4-byte LE length-prefix framing   │                      │
│  │   max frame = 8 MiB                 │                      │
│  └────────────┬───────────────────────┘                      │
│               │                                              │
└───────────────┼──────────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────┐
│  MCP-hosted Node REPL (external, e.g. Codex agent shell) │
│                                                          │
│  browser-client.mjs (plugin file, bundled Playwright)    │
│    setupAtlasRuntime({globals, backend: "iab"})          │
│    creates globals: `agent`, `display`                   │
│    agent.browser.tabs.new() → Tab with:                  │
│      .playwright.*   (Playwright-style)                  │
│      .cua.*          (coord-based actions)               │
│      .content.*      (export, exportGsuite)              │
│      .clipboard.*    (read, write, readText, writeText)  │
│      .dev.logs()     (console)                           │
│                                                          │
│  Transport: net.createConnection(socketPath)             │
│  Wire: 4-byte LE length + JSON                           │
│  Envelope: {method, params, session_id, turn_id, id}     │
└──────────────────────────────────────────────────────────┘
```

The `"chrome"` backend mirrors this with:
- Native-messaging host binary bundled in `chrome/extension-host/{platform}/{arch}/extension-host`
- Installed via `scripts/installManifest.mjs` writing `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/*.json`
- Chrome extension ID `lfkehkpjohcoelkpembgemeipeppanef` auto-installed via `External Extensions/` manifest pointing at `clients2.google.com/service/update2/crx`
- Socket: `process.env.CODEX_CHROME_SOCKET ?? ~/.codex-chrome/codex-chrome.sock`
- Envelope shape differs slightly: `{request_id, client_id, session_id, command, timeout_ms}` — but the CDP verbs and Playwright layer are identical.

---

## 2. Evidence for the transport (CDP over length-prefix Unix socket)

### 2.1 Server side (main process)

From `main-CUDSf52Z.js`:

```js
// length-prefix framing constants
Ge = 4                // 4-byte LE length prefix
Ke = 8 * 1024 * 1024  // 8 MB max frame
qe = 200              // (limit; likely max pending requests)

Je = class {
  pipePath
  sockets = new Set
  pendingDataBySocket = new Map
  server = l.default.createServer(e => { this.handleSocketConnection(e) })
  messageCallback = null
  started = false
  constructor(e) { this.pipePath = e }
  async start() {
    await this.prepareSocketPath()
    await new Promise((e, t) => {
      this.server.once(`error`, t)
      this.server.listen(this.pipePath, () => { /* ... */ })
    })
  }
  // ... handleSocketConnection parses length-prefix frames, dispatches
}

// socket path factory
Xe = async () => {
  let e = (0, n.platform)() === `win32`
  let t = e ? `` : `.sock`
  if (!e) await (0, f.mkdir)(We, { recursive: true })
  return r.default.resolve(We, crypto.randomUUID() + t)
}
```

The CDP forwarder:

```js
// inside handler — dispatches CDP on behalf of the plugin-side browser-client
e.webContents.debugger.attach(`1.3`)
// ...
e.webContents.debugger.sendCommand(t.method, t.params)
e.webContents.debugger.on(/* events */)
```

Electron's [`webContents.debugger` API](https://www.electronjs.org/docs/latest/api/debugger) is the built-in CDP client for `WebContents`. Attaching at protocol `1.3` gives full Page/Input/Runtime/DOM access. The main process essentially implements a stateless CDP multiplexer: incoming frames on the Unix socket are forwarded to `debugger.sendCommand`; incoming debugger events from the page are wrapped and written back.

### 2.2 Client side (browser-client.mjs)

```js
import { createConnection } from "node:net"
import { endianness } from "node:os"

const fr = 4  // 4-byte prefix (matches server)

// session-scoped request:
sendRequest(method, params) {
  let id = this.nextId++
  return new Promise((resolve, reject) => {
    this.pendingRequests.set(id, { resolve, reject })
    this.transport.sendMessage({
      jsonrpc: "2.0",
      method,
      params: { ...params, session_id, turn_id },
      id
    })
  })
}
```

The plugin speaks **raw CDP verbs**, not a custom wrapper. Observed calls (literal strings in `browser-client.mjs`):

```
Page.navigate                       Page.enable
Page.getFrameTree                   Runtime.enable
Page.getLayoutMetrics               Runtime.evaluate
Page.captureScreenshot              Runtime.consoleAPICalled
Page.getNavigationHistory           Runtime.exceptionThrown
Page.navigateToHistoryEntry         Input.dispatchMouseEvent
Page.reload                         Input.dispatchKeyEvent
Page.close                          Input.insertText
Page.navigatedWithinDocument        DOM.getDocument
Page.frameNavigated                 DOM.querySelector
Page.frameStartedLoading            DOM.describeNode
Page.domContentEventFired           DOM.setFileInputFiles
Page.loadEventFired                 Page.setInterceptFileChooserDialog
Page.addScriptToEvaluateOnNewDocument
Page.removeScriptToEvaluateOnNewDocument
Page.fileChooserOpened
```

### 2.3 Playwright on top of CDP

The plugin ships **Playwright's own InjectedScript** engine (one of the `XX` import chunks in the bundle contains `PlaywrightInjected.InjectedScript`). When you call `tab.playwright.getByRole("button", { name: "Save" })`, the client:

1. Dispatches `Runtime.evaluate` with an expression that calls `InjectedScript.querySelector(selector)` where `selector` is an internal Playwright selector string (e.g., `internal:role=button[name="Save"s]`).
2. Returns a `PlaywrightLocator` handle that stores the selector, not a `RemoteObjectId` — so each subsequent call re-queries. This is how locators stay robust across DOM changes.

Internal verbs the model **does not** see but the runtime uses:

```
playwright.evaluateOnPlaywrightPage          cua.clickPoint
playwright.evaluateOnPlaywrightSelector      cua.dispatchMouseMove
playwright.evaluateOnPlaywrightSelectorAll   cua.dispatchKeyPress
playwright.clickLocator                      playwright.query
playwright.focusLocator                      playwright.inspect
playwright.readElementState                  playwright.selector
playwright.readCheckedState                  playwright.filter/first/last/nth/and/or
playwright.elementInfo                       playwright.elementScreenshot
```

`playwright.elementInfo(x, y)` is the one that matters for recreating the comment feature — it takes a screenshot pixel coordinate and returns `ElementInfo[]` with ranked `selector.candidates`, `ariaName`, `role`, `boundingBox`, `tagName`, `testId`, `visibleText`. The preload's selector ranking (below) uses the same heuristic.

---

## 3. The comment preload — what's actually injected into the page

### 3.1 Mount point

- Preload path is computed in main as:
  ```js
  Lf = (0, r.join)(__dirname, `browser-sidebar-comment-preload.js`)
  ```
- On every navigation that isn't comment-mode-blocked, the preload injects a single host element into the page:
  ```
  id="codex-browser-sidebar-comments-root"
  ```
- The preload calls `attachShadow({ mode: ... })` on that host so the overlay CSS + React tree is **isolated from the page** (confirmed: strings `attachShadow`, `shadowRoot`, and the root id all present in the preload).
- React 18 root mounts the `Js` coordinator component into the shadow root via `createRoot(root).render(<Coordinator/>)`. All pin markers, the hover highlighter, selection box, and comment pin thread badges are subtrees of this root.

### 3.2 Hit-test and highlighter

On `mousemove` (throttled), the preload runs:

```js
// approximate
let hit = document.elementFromPoint(x, y)
let actionable = nearestActionable(hit)   // walks up DOM, prefers
                                          //   button, a, [role], input, 
                                          //   label, [data-testid], elements
                                          //   with >48×24 bounds
let rect = actionable.getBoundingClientRect()
let computed = getComputedStyle(actionable)
drawHighlighter({
  rect,
  tagName: actionable.tagName.toLowerCase(),
  dims: `${rect.width}×${rect.height}`,
  color: computed.backgroundColor,
  borderRadius: computed.borderRadius
})
```

Highlighter is positioned via the `al()` utility which clamps to viewport bounds; it's rendered as a bordered CSS box plus a small metadata tooltip showing `tagName / size / color / borderRadius`. i18n keys confirm this:

```
browserSidebarCommentRuntime.elementMetadata.color
browserSidebarCommentRuntime.elementMetadata.size
browserSidebarCommentRuntime.elementMetadata.tagName
```

### 3.3 Element selector + anchor

On click, the preload builds a **structured anchor** for the picked element. The anchor schema (all field names confirmed as literal strings in the preload and main):

```ts
type Anchor =
  | { kind: "element"; ...ElementAnchor }
  | { kind: "region";  ...RegionAnchor }  // freehand / drag-to-select area

interface ElementAnchor {
  pageUrl:   string          // window.location.href
  frameUrl?: string          // iframe.src if the element is inside an iframe
  framePath?: string[]       // ["iframe.nav", "iframe#nested"] — selectors to reach the frame
  title?:    string          // aria-label || textContent fallback
  elementPath: string        // "div > button > span" breadcrumb
  selector:  string          // stable CSS selector (heuristic below)
  point:     { xPercent: number; y: number }   // viewport-%-x, page-px-y
  rect:      { x: number; y: number; width: number; height: number }
  isFixed:   boolean         // computed position: fixed / sticky
  role?:     string          // computed or attribute role
  name?:     string          // accessible name
  nearbyText?: string        // short context from nearest semantic ancestor
  scrollContainers?: Array<{ // scroll offsets for scroll-dependent elements
    selector: string
    scrollLeft: number
    scrollTop: number
  }>
}
```

Selector heuristic (ranked, walking up ~4 ancestors):

1. `#id` — if stable-looking ID present, return immediately
2. `tag.class1.class2` — up to 2 whitelisted classes (alnum/_/-)
3. `:nth-of-type(n)` appended if multiple siblings share tagName
4. Joined with ` > ` from the nearest stable ancestor down

Ambiguous cases are left to the `elementPath` breadcrumb and `role`/`name` fields — the agent can use those to disambiguate.

### 3.4 Composer — separate native window

Clicking sends `browser-sidebar-runtime-open-editor` to main:

```js
{
  type: "browser-sidebar-runtime-open-editor",
  target: { mode: "create" } | { mode: "edit", commentId: string },
  anchor: Anchor,
  body: ""   // empty for create, current text for edit
}
```

Main handles it via `CommentOverlayManager.open(...)`:

```js
await this.overlayManager.open({
  owner:           n.owner,                        // the parent browser window
  hostId:          this.windowManager.getHostIdForWebContents(n.owner) ?? this.hostId,
  conversationId:  n.page.conversationId,
  browserBounds:   r.bounds,
  target:          t.target,
  anchorState:     t.anchorState,
  body:            t.body,
  cwd:             r.cwd,
  attachedImages:  (editing-an-existing-comment? grab its images : undefined),
  screenshot:      undefined
})
```

The `overlayManager` is **not** the in-page shadow-DOM root. It's a **separate Electron window** (evidenced by strings `browser-sidebar-comment-overlay-session`, `browser-sidebar-comment-overlay-prepare`, and `failed to prepare browser comment overlay`). It's positioned above the BrowserView at the anchor rect's location and hosts the composer UI. Why separate?

- IME, spellcheck, autocorrect work natively.
- Page CSS can't break the composer's layout.
- Focus and key-event handling is free from the page's JS.
- Paste/drag-to-attach for images (`attachedImages`) works with Electron file handling.

As the user scrolls, the preload sends `browser-sidebar-runtime-update-anchor` with new rect/xPercent; main calls `overlayManager.updateAnchor(...)` to reposition the composer window.

### 3.5 Comment screenshot

When a comment is being created or opened, main asks the preload to prepare a local-to-anchor screenshot:

1. Main → preload: `browser-sidebar-runtime-prepare-comment-screenshot`
2. Preload computes a high-DPR crop (scrolling the element into view if needed), captures via... actually, the simpler path: **main uses Electron's `webContents.capturePage()`** (visible in the main code as `let t = await e.capturePage(); let {width, height} = t.getSize(); return { dataUrl: t.toDataURL(), width, height }`) and crops to the anchor rect. The "prepare" and "ready" round-trip gives the preload a chance to scroll/stabilize first.
3. Preload → main: `browser-sidebar-runtime-comment-screenshot-ready`
4. Main waits with a timeout (error string: *"Timed out waiting for browser comment screenshot"*); resolves a `runtimeCommentScreenshotWaiters` entry.
5. The resulting data URL is attached to the comment record under `screenshot`.

### 3.6 Other overlay states

- `browser-sidebar-runtime-exit-comment-mode` — preload → main: user cancelled via Esc / toggle.
- `browser-sidebar-runtime-close-editor` / `browser-sidebar-runtime-focus-editor` — open/close/focus the composer overlay.
- `browser-sidebar-runtime-select-comment` — clicking an existing pin focuses that thread.
- `browser-sidebar-runtime-stop-agent-control` — user wants to interrupt an active agent run on this tab (the "agent-control shimmer" gets dismissed).
- `browser-sidebar-runtime-mouse-navigation` — mouse back/forward buttons forwarded to `tab.back()`/`tab.forward()`.

---

## 4. Full IPC catalog (preload ↔ main)

All via the single Electron channel `codex_desktop:browser-sidebar-runtime-message` (and the generic preload-to-view `codex_desktop:message-for-view` / `codex_desktop:message-from-view`).

| Message type | Direction | Purpose |
|---|---|---|
| `browser-sidebar-runtime-sync` | main → preload | Snapshot broadcast: `{comments[], interactionMode, isAgentControllingBrowser, intlConfig, commentModeDisabledReason}` |
| `browser-sidebar-runtime-open-editor` | preload → main | User clicked an element or pin; open composer with `{target, anchor, body}` |
| `browser-sidebar-runtime-close-editor` | bi | Close composer |
| `browser-sidebar-runtime-focus-editor` | main → preload | Give focus to composer |
| `browser-sidebar-runtime-update-anchor` | preload → main | Anchor moved (scroll/resize); reposition composer |
| `browser-sidebar-runtime-select-comment` | bi | Select/highlight a specific `commentId` |
| `browser-sidebar-runtime-prepare-comment-screenshot` | main → preload | Request preload to scroll/stabilize for screenshot |
| `browser-sidebar-runtime-comment-screenshot-ready` | preload → main | "go ahead and capture now" |
| `browser-sidebar-runtime-exit-comment-mode` | preload → main | User cancelled comment mode |
| `browser-sidebar-runtime-stop-agent-control` | preload → main | User wants to interrupt agent |
| `browser-sidebar-runtime-mouse-navigation` | preload → main | Mouse-button back/forward |

---

## 5. Comment state model

Per-thread state, on the main process. No persistent store — lives for the duration of the conversation. Rebuilt in-memory and synced with `browser-sidebar-runtime-sync`.

```ts
interface CommentRecord {
  id:                string                     // UUID
  anchor:            Anchor
  anchorState:       AnchorState                // computed snapshot including scroll state
  body:              string                     // user's text
  createdAt:         number                     // Date.now()
  attachedImages?:   Array<AttachedImage>       // drag-pasted images in composer
  screenshot?:       { dataUrl: string; width: number; height: number }
}

interface ThreadSnapshot {
  title:    string
  url:      string
  isLoading: boolean
  canGoBack: boolean
  canGoForward: boolean
  commentModeDisabledReason: string | null
  interactionMode: "browse" | "comment"
  comments: CommentRecord[]
}

interface WindowState {
  snapshot: ThreadSnapshot
  page?:    { view, webContents, conversationId }
  pendingCommentModeActivation?: { url: string }
  isAgentControllingBrowser: boolean
  // ...
}
```

The main process keeps a `Map<owner, WindowState>` (`windows = new Map()` in `Rf` class) and per-conversation thread state. Every change calls `syncCommentSnapshot(owner, conversationId)` which re-broadcasts the `browser-sidebar-runtime-sync` to the preload and also pushes to the Codex sidebar list UI (via `sendMessageToWebContents(owner, { type, ... })`).

### 5.1 Submit flows

Two submit modes:

```js
// mode "create" — add new
if (s.mode === "create") {
  let e = randomUUID()
  i.snapshot = {
    ...i.snapshot,
    comments: [...i.snapshot.comments, td({
      anchorState: r.session.anchorState,
      body: a,
      commentId: e,
      attachedImages: n.attachedImages,
      screenshot: r.session.screenshot
    })]
  }
  await this.captureSavedCommentScreenshot({ commentId: e, ... })
}

// mode "edit" — update existing
else {
  i.snapshot = {
    ...i.snapshot,
    comments: i.snapshot.comments.map(e => 
      e.id === s.commentId 
        ? { ...e, body: a, attachedImages: n.attachedImages } 
        : e
    )
  }
}
```

And a special path — `submitDirectly`:

```js
if (n.submitDirectly === true) {
  // Build comment but *don't* persist — send it immediately as a one-off turn
  let t = td({ anchorState, body: a, commentId: randomUUID(), attachedImages, screenshot })
  let c = threadState.page.view.webContents
  await this.captureDirectCommentScreenshot({ comment: t, conversationId, page: c, threadState })
  // close composer and emit as a submit event to the window
  this.windowManager.sendMessageToWebContents(r.owner, {
    type: /* submit shape */,
    conversationId, sessionId,
    body: a,
    comment: e.ii(l == null ? t : { ...t, screenshot: l }, s)
  })
}
```

So there are **two ways comments reach the agent**:
- **Deferred**: added to `snapshot.comments`, appears in the chat sidebar list, attached to the next chat message you explicitly send.
- **Immediate** (`submitDirectly`): the comment IS the message — like hitting Send with the comment composer's text and the anchor as attachment.

### 5.2 How the comment gets into the message

Searching `commentAttachments` in `product-name-C630vpQ6.js` confirms the attachment field on the outgoing user-message envelope. The shape (reconstructed):

```ts
interface UserMessage {
  text: string
  commentAttachments?: CommentRecord[]   // this is the key
  // ... other attachments (files, images)
}
```

Downstream, the agent's system prompt (or a structured tool context) sees:

```
<browser_comments>
  [Comment 1] on https://example.com/page
    anchor: button.signup (rect x/y/w/h, xPercent, y; role=button, name="Sign up")
    body: "this should be bigger"
    screenshot: <image attached>
  ...
</browser_comments>
```

Exact prompt format is not directly visible in the bundle (it's likely assembled by the agent-server backend, not the Electron app), but the plugin skills already reference the pattern: the browser-use SKILL says *"the user is asking questions about what they see on the screen. Base your interactions on what is visible to the user (based on DOM and screenshots) rather than programmatically determining what they are talking about."* That's the comment feature as context.

---

## 6. Comment mode blocklist (safety gating)

From `main-CUDSf52Z.js`:

- Endpoint name: **`browser-sidebar-comment-mode-site-status`** (called via the Codex AppServer with user's auth).
- Cache TTL: **24 hours** (`Eu = 1440 * 60 * 1e3` milliseconds).
- Cache key: normalized domain (origin + path components).
- Error strings: *"browser sidebar comment mode site status request failed"*, *"failed to load browser sidebar comment mode site status"*.
- The result pattern: `{ feature_status: { "agent": true | false } }`. If `agent` is `true`, comment mode is **blocked** on that URL.
- Default: allow (graceful failure — if the request fails, comment mode stays available).
- Per-window:
  ```js
  pendingCommentModeActivation = { url }    // user flipped to comment but blocklist check pending
  commentModeDisabledReason = null | string // if blocked, string is shown
  ```

Before a user can enter comment mode on a given URL, main schedules `refreshCommentModeBlockStatus(...)` which:

1. Checks the 24h cache.
2. If miss or stale, fetches `/browser-sidebar-comment-mode-site-status?url=<normalized>`.
3. If blocked, sets `commentModeDisabledReason` and emits sync.
4. If allowed, proceeds to flip `interactionMode` to `"comment"` and emits sync.

This is why the SKILL docs have so much safety text and why URL policy is a layer separate from the Sky URL blocklist (`AuraSiteStatusURLPolicyChecker`) — the comment blocklist is for **user-initiated** annotation on a site, whereas Sky's URL policy is for **agent-initiated** navigation.

---

## 7. The `agent.browser.*` API surface (model-facing)

All of this is available to the model from inside `node_repl` after running `setupAtlasRuntime({ globals: globalThis, backend: "iab" })`. Full API shape (extracted from `browser-use/skills/browser/SKILL.md`).

### 7.1 Top level

```ts
agent.browser.nameSession(name: string): Promise<void>
agent.browser.tabs: Tabs
agent.browser.user: BrowserUser   // readonly info about the user's own tabs
```

### 7.2 Tabs

```ts
agent.browser.tabs.new():     Promise<Tab>
agent.browser.tabs.get(id):   Promise<Tab>
agent.browser.tabs.list():    Promise<TabInfo[]>
agent.browser.tabs.selected(): Promise<Tab | undefined>
agent.browser.tabs.content({ urls, contentType: "html"|"text"|"domSnapshot", timeoutMs? }):
                              Promise<TabsContentResult[]>   // opens temp bg tabs, extracts, closes
```

### 7.3 BrowserUser (readonly user context)

```ts
agent.browser.user.history({ from?, to?, query?, limit? }): Promise<BrowserHistoryEntry[]>
agent.browser.user.openTabs(): Promise<BrowserUserTabInfo[]>  // user's own open tabs (all windows)
```

### 7.4 Tab

```ts
tab.id: string
tab.goto(url): Promise<void>
tab.reload(): Promise<void>
tab.back(): Promise<void>
tab.forward(): Promise<void>
tab.close(): Promise<void>
tab.title(): Promise<string | undefined>
tab.url():   Promise<string | undefined>

tab.playwright: PlaywrightAPI
tab.cua:        CUAAPI
tab.content:    ContentAPI
tab.clipboard:  TabClipboardAPI
tab.dev:        TabDevAPI
```

### 7.5 Playwright API (subset)

```ts
domSnapshot():    Promise<string>
screenshot({ clip?, fullPage? }): Promise<Image>
elementInfo({ x, y, includeNonInteractable? }): Promise<ElementInfo[]>
elementScreenshot({ x, y, includeNonInteractable? }): Promise<Image>  // annotated
getByRole(role, { exact?, name? })
getByTestId(id)
getByText(text, { exact? })
getByLabel(text, { exact? })
getByPlaceholder(text, { exact? })
locator(selector): PlaywrightLocator
frameLocator(selector): PlaywrightFrameLocator
expectNavigation(action, { url?, waitUntil?, timeoutMs? })
waitForLoadState({ state?, timeoutMs? })
waitForURL(url, { waitUntil?, timeoutMs? })
waitForEvent("download" | "filechooser", { timeoutMs? })
waitForTimeout(ms)   // discouraged
```

Locator methods: `click`, `dblclick`, `fill`, `type`, `press`, `check`, `uncheck`, `setChecked`, `selectOption`, `getAttribute`, `textContent`, `innerText`, `isVisible`, `isEnabled`, `count`, `all`, `nth`, `first`, `last`, `filter`, `and`, `or`, `locator`, `waitFor`, `getBy*`, `downloadMedia`.

### 7.6 CUA API (coord-based, per tab)

```ts
tab.cua.click({ x, y, button?, keypress? })
tab.cua.double_click({ x, y, keypress? })
tab.cua.move({ x, y, keys? })
tab.cua.drag({ path: [{x,y}, ...], keys? })
tab.cua.scroll({ x, y, scrollX, scrollY, keypress? })
tab.cua.type({ text })
tab.cua.keypress({ keys: [...] })
tab.cua.get_visible_screenshot(): Promise<Image>
tab.cua.downloadMedia({ x, y, timeoutMs? })
```

### 7.7 ContentAPI

```ts
tab.content.export(): Promise<string>           // absolute path to exported file
tab.content.exportGsuite("pdf"|"md"|"xlsx"|"csv"|"docx"|"pptx"): Promise<string>
```

`export()` handles PDFs/images (downloads the underlying asset) and by default exports a textual or visual representation of the page. `exportGsuite` hits Google's export URL for Docs/Sheets/Slides.

### 7.8 ClipboardAPI (per tab)

```ts
tab.clipboard.read():       Promise<TabClipboardItem[]>
tab.clipboard.readText():   Promise<string>
tab.clipboard.write(items)
tab.clipboard.writeText(text)
```

### 7.9 DevAPI

```ts
tab.dev.logs({ levels?, filter?, limit? }): Promise<TabDevLogEntry[]>
```

Reads the console log stream captured by CDP `Runtime.consoleAPICalled`.

---

## 8. Internal RPC vocabulary (what actually crosses the socket)

Methods you won't see in the skill docs but that the runtime emits:

```
cua.clickPoint
cua.dispatchMouseMove
cua.dispatchKeyPress
playwright.evaluateOnPlaywrightPage
playwright.evaluateOnPlaywrightSelector
playwright.evaluateOnPlaywrightSelectorAll
playwright.clickLocator
playwright.focusLocator
playwright.readElementState
playwright.readCheckedState
playwright.query
playwright.inspect
playwright.selector
playwright.filter / .first / .last / .nth / .and / .or
playwright.elementInfo
playwright.elementScreenshot
TabBack / TabForward / TabReload / TabUrl
TabContentExport / TabContentExportGSuite
TabClipboardRead / TabClipboardReadText / TabClipboardWrite / TabClipboardWriteText
TabDevLogs
```

Every frame on the wire carries `session_id` and `turn_id` (set by the host: the Codex main process includes them when setting up the socket env for the plugin process). Cleanup handlers:

```
TabCleanupHandler / TabCleanupHandlers
TabAttachHandler / TabAttachHandlers
```

These run when a tab is closed or when a navigation happens; they reset any injected state (e.g., `Page.removeScriptToEvaluateOnNewDocument`).

---

## 9. The `"chrome"` backend (for completeness)

Codex treats the user's own Chrome as a second backend. Relevant artifacts:

### 9.1 Scripts shipped in `plugins/chrome/scripts/`

- `chrome-extension-installer.js` — `DEFAULT_REMOTE_CHROME_EXTENSION_ID = "lfkehkpjohcoelkpembgemeipeppanef"`; the main helper.
- `install-remote-extension.js` — writes `~/Library/Application Support/Google/Chrome/External Extensions/lfkehkpjohcoelkpembgemeipeppanef.json` pointing at `https://clients2.google.com/service/update2/crx`, then launches Chrome (so Chrome picks up the external manifest and auto-installs).
- `check-extension-installed.js` — checks `Profile X/Extensions/{ID}/` for installed version directories; exit 0 if present.
- `installed-browsers.js` — enumerates browsers via `mdfind` / LSSharedFileList / app bundle inspection.
- `installManifest.mjs` — writes the native-messaging host manifest to `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/{host}.json` with `{name, description, path, type: "stdio", allowed_origins: ["chrome-extension://..."]}`.
- `browser-client.mjs` — **same bundle as browser-use/**; both plugins ship identical `browser-client.mjs`. Only difference: the backend flag passed in.

### 9.2 Native-messaging host

Bundled at `chrome/extension-host/{darwin-arm64,darwin-x64,linux-*,win-*}/extension-host`. This is a small native binary invoked by Chrome over stdio. It relays CDP commands from the socket out to Chrome's extension APIs — the extension in turn drives tabs via `chrome.debugger.attach` / `chrome.tabs.*` / `chrome.scripting.executeScript` for the overlay injection. So the "comment on pages" feature works the same way inside the user's real Chrome as it does inside the Codex BrowserView.

### 9.3 Socket path

`browser-client.mjs` when backend is `"chrome"`:

```js
let socketPath = process.env.CODEX_CHROME_SOCKET
              ?? path.join(os.homedir(), ".codex-chrome", "codex-chrome.sock")
let envelope = {
  request_id: randomUUID(),
  client_id:  t,            // plugin-session id
  session_id: i,
  command:    e,
  timeout_ms: a ?? 30000
}
```

The native-messaging host listens on this socket on one side and talks to Chrome over stdio on the other. From the plugin's perspective the API is identical to the IAB backend.

---

## 10. Recreation playbook

You can build the IAB + comment feature on top of any Electron app in about **3 engineering weeks**, plus 1 extra week if you also want the Chrome backend.

### 10.1 Target architecture

Copy Codex's split literally:

1. A `WebContentsView` hosted in your main window, with a preload script (the overlay).
2. A separate `CommentOverlayManager` that manages a floating frameless Electron window per open composer.
3. A CDP forwarder server (`net.createServer` on a Unix socket) that attaches `webContents.debugger` and pipes commands to/from clients.
4. A client library — either a thin wrapper around CDP, or port Codex's approach of shipping Playwright's InjectedScript for `getByRole`/`locator` support.

### 10.2 Week 1 — BrowserView + preload + shadow-DOM overlay

Minimal plan:

1. Create a `WebContentsView`, load the user's URL.
2. Ship a preload script. On `DOMContentLoaded`, create a host element, `attachShadow({mode:"closed"})`, mount a React (or Preact — fewer bytes) app into it.
3. Implement two interaction modes: `browse` (default, overlay is just pin markers) and `comment` (overlay captures pointer, draws highlighter).
4. For highlight, on `mousemove`:
   - `document.elementFromPoint(x, y)`
   - Walk up until actionable element found (tag in `{button, a, label, input, select, textarea}` or has `role` or `data-testid` or bounds > 48×24)
   - Draw a bordered CSS box at its `getBoundingClientRect()`
   - Show a small tooltip: `tagName dims color borderRadius`

### 10.3 Week 2 — Comment anchor + composer + main-process state

1. Define the `Anchor` schema from §3.3. Implement the selector generator. Recommended shortcut: reuse Playwright's InjectedScript (`require("playwright-core/lib/server/injected/injectedScript")`) — its `generateSelector()` output is essentially what you want.
2. On click in comment mode, the preload emits `runtime-open-editor` over `ipcRenderer.invoke(channel, message)`.
3. Main process creates a new frameless Electron window positioned at `{x: rect.x + browserView.x, y: rect.y + rect.height}` with `resizable: false`, `alwaysOnTop: true`, `transparent: true`. Load a local HTML file with the composer UI.
4. On preload-side scroll/resize events (throttled), emit `runtime-update-anchor` so main can reposition the composer.
5. On submit, main builds a `CommentRecord` (UUID id, anchor, body, screenshot placeholder), adds to `threadState.snapshot.comments`, broadcasts `runtime-sync` to preload (so pins update) AND to your sidebar renderer.

Comment screenshot flow:
- Main → preload: `runtime-prepare-comment-screenshot` (preload scrolls element into view if needed, waits a frame)
- Preload → main: `runtime-comment-screenshot-ready`
- Main: `const img = await webContents.capturePage(); const crop = cropToRect(img, rect); record.screenshot = { dataUrl: crop.toDataURL(), w, h }`

### 10.4 Week 3 — CDP socket + agent API

1. Start a Unix socket server on `path.join(os.tmpdir(), <uuid>.sock)`. Length-prefix framing: 4 bytes LE length + JSON body. Max frame 8 MB.
2. Pass the socket path to your agent's runtime via env var (`YOUR_APP_CDP_SOCKET`).
3. In the forwarder, on connection:
   - `await webContents.debugger.attach("1.3")`
   - On incoming frame `{id, method, params}` → `webContents.debugger.sendCommand(method, params).then(result => write({id, result}))`
   - Subscribe to debugger events and forward: `webContents.debugger.on("message", (event, method, params) => write({method, params}))`
4. In your plugin / agent process, write `agent.browser.*` as a thin wrapper over these CDP primitives. The cheapest way is: implement `tab.goto`, `tab.url`, `tab.title`, `tab.back/forward/reload`, `tab.playwright.screenshot`, `tab.playwright.domSnapshot`, `tab.cua.click/type/scroll`. Then if you want Playwright locators, bring in the real Playwright InjectedScript.

### 10.5 Sending comments to the agent

The key trick: when the user submits a chat message, **splice `snapshot.comments` into the outgoing message envelope** as a structured attachment. Example:

```ts
const outgoing = {
  text: userTypedText,
  attachments: [
    ...fileAttachments,
    ...snapshot.comments.map(c => ({
      type: "browser_comment",
      id: c.id,
      anchor: c.anchor,
      body: c.body,
      screenshot: c.screenshot
    }))
  ]
}
snapshot.comments = []  // clear after send
```

On the backend, surface them in the agent's system or user message:

```xml
<browser_comments>
  <comment id="...">
    <url>https://example.com/page</url>
    <selector>button.signup</selector>
    <role>button</role>
    <name>Sign up</name>
    <rect x="..." y="..." width="..." height="..."/>
    <screenshot ref="attachment-0"/>
    <body>this should be bigger</body>
  </comment>
</browser_comments>
```

### 10.6 Blocklist (safety gating)

Optional for v1 but easy: keep a `Map<domain, { blockedAt: number, blocked: boolean }>` in-memory, refresh per 24h. Before flipping `interactionMode` to `"comment"`, check the cache; if stale/missing, hit your site-status endpoint; if blocked, show a banner instead of enabling comment mode. Graceful fallback: allow if request fails.

### 10.7 What to skip on v1

- The separate composer window (use an in-page shadow DOM textarea first; move to native window only when you hit IME/focus bugs).
- The full Playwright InjectedScript (start with raw CDP + a hand-rolled selector generator).
- Chrome backend entirely (IAB is enough for most use cases; Chrome backend is months of extension work).
- The region/freehand anchor kind (`kind: "region"`). Element anchors cover 95% of use.
- Screenshot crop precision (start with full-page screenshot attached per comment; crop later).

### 10.8 What's easy to miss

- **The selector must be computed from the page's real DOM at click time**, not reconstructed on the backend. Selector generation needs the live node tree; by the time the agent runs, the page state has changed.
- **Anchor point is (xPercent, yPercent) in page coordinates, not viewport** — otherwise the pin drifts on scroll or on resize.
- **The `framePath` matters**: if the user clicks inside a nested iframe, the selector is only meaningful if the agent first enters the frame chain. Include `framePath: ["iframe.main", "iframe#cards"]` with the anchor.
- **IME breaks in-page textareas**. Plan for the separate composer window from day one if you want Chinese/Japanese/Korean users.
- **Scroll containers**: if the commented element is inside a scroll container, record `{selector, scrollLeft, scrollTop}` so the agent can restore scroll before acting.
- **Dedup pins on hover**: multiple pins near each other must not all highlight; use pointer-events routing and z-index.
- **Shadow DOM matters**: if your overlay is not in a closed shadow root, the page's CSS can style it, the page's JS can introspect/break it, and your click handlers may get blocked by `pointerdown` listeners. Use `attachShadow({mode: "closed"})`.

### 10.9 Effort breakdown

| Area | Days |
|---|---|
| WebContentsView + preload injection | 1 |
| Shadow-DOM React overlay + highlighter | 3 |
| Anchor schema + selector generator | 2 |
| Comment composer (native window) + IPC | 3 |
| Comment state model + sidebar list UI | 2 |
| Screenshot crop on comment save | 1 |
| CDP socket forwarder + length-prefix framing | 2 |
| Minimal `agent.browser.*` over CDP | 3 |
| Blocklist endpoint + 24h cache | 1 |
| Polish, multi-window, scroll edge cases | 3 |
| **Total** | **~21 working days** |

Add ~15 days for the full Playwright locator API, and ~30 days for Chrome backend (extension + native host + distribution).

---

## 11. Appendix — verbatim evidence

### 11.1 Socket + server setup (main-CUDSf52Z.js)

```js
Ge = 4                // 4-byte length prefix
Ke = 8 * 1024 * 1024  // 8 MiB max frame
qe = 200

Je = class {
  pipePath
  sockets = new Set
  pendingDataBySocket = new Map
  server = l.default.createServer(e => { this.handleSocketConnection(e) })
  messageCallback = null
  started = false
  constructor(e) { this.pipePath = e }
  async start() {
    await this.prepareSocketPath()
    await new Promise((e, t) => {
      this.server.once(`error`, t)
      this.server.listen(this.pipePath, () => { /* ... */ })
    })
  }
}

Xe = async () => {
  let e = (0, n.platform)() === `win32`
  let t = e ? `` : `.sock`
  if (!e) await (0, f.mkdir)(We, { recursive: true })
  return r.default.resolve(We, crypto.randomUUID() + t)
}
```

### 11.2 Debugger attach (main-CUDSf52Z.js / product-name-C630vpQ6.js)

```js
e.webContents.debugger.attach(`1.3`)
// ...
.debugger.sendCommand(t.method, /* params */)
.debugger.on(/* event */)
.detach()
```

### 11.3 Chrome backend socket path (main-CUDSf52Z.js)

```js
let s = process.env.CODEX_CHROME_SOCKET
      ?? r.default.join((0, n.homedir)(), `.codex-chrome`, `codex-chrome.sock`)
let c = {
  request_id: (0, o.randomUUID)(),
  client_id:  t,
  session_id: i,
  command:    e,
  timeout_ms: a ?? yi
}
```

### 11.4 Default IPC sockets (product-name-C630vpQ6.js)

```js
let e = path.join(os.tmpdir(), `codex-ipc`)
if (!v.existsSync(e)) v.mkdirSync(e, { recursive: true })
let t = process.getuid?.()
return h.join(e, t ? `ipc-${t}.sock` : `ipc.sock`)
```

### 11.5 Preload path construction (main-CUDSf52Z.js)

```js
Lf = (0, r.join)(__dirname, `browser-sidebar-comment-preload.js`)
Rf = class {
  windows = new Map
  configuredPartitions = new Set
  browserUseOpenRequests
  // ...
}
```

### 11.6 Comment submit & direct-submit handler (main-CUDSf52Z.js, excerpt)

```js
async handleOverlaySubmit(t, n) {
  let r = this.overlayManager.getOverlayStateForOwner(t, n.conversationId)
  if (r == null || r.session.sessionId !== n.sessionId) return
  let i = this.delegate.getThreadState(r.owner, r.conversationId)
  if (i == null) return
  let a = n.body.trim()
  if (a.length === 0) {
    this.dismiss(r.owner, r.conversationId, i)
    return
  }
  let s = r.session.target

  if (n.submitDirectly === true) {
    let t = td({ anchorState: r.session.anchorState, body: a, commentId: randomUUID(),
                 attachedImages: n.attachedImages, screenshot: r.session.screenshot })
    let c = i.page?.view.webContents ?? null
    let l = await this.captureDirectCommentScreenshot({ comment: t, conversationId: r.conversationId, page: c, threadState: i })
    this.closeRuntimeEditor(c)
    this.syncRuntimeStateToPage(c, i)
    this.windowManager.sendMessageToWebContents(r.owner, {
      type: /* submit type */, conversationId: r.conversationId, sessionId: n.sessionId,
      body: a, comment: e.ii(l == null ? t : { ...t, screenshot: l }, s)
    })
    return
  }

  if (s.mode === `create`) {
    let e = randomUUID()
    i.snapshot = { ...i.snapshot, comments: [...i.snapshot.comments,
      td({ anchorState: r.session.anchorState, body: a, commentId: e,
           attachedImages: n.attachedImages, screenshot: r.session.screenshot }) ] }
    this.delegate.syncCommentSnapshot(r.owner, r.conversationId)
    await this.captureSavedCommentScreenshot({ commentId: e, conversationId: r.conversationId,
      owner: r.owner, page: i.page?.view.webContents ?? null, threadState: i })
  } else {
    // edit mode
    i.snapshot = { ...i.snapshot, comments: i.snapshot.comments.map(e =>
      e.id === s.commentId ? { ...e, body: a, attachedImages: n.attachedImages } : e) }
    this.delegate.syncCommentSnapshot(r.owner, r.conversationId)
  }
}
```

### 11.7 Full list of runtime message types

```
codex_desktop:browser-sidebar-runtime-message   (single channel carrying all of these)
  - browser-sidebar-runtime-sync
  - browser-sidebar-runtime-open-editor
  - browser-sidebar-runtime-close-editor
  - browser-sidebar-runtime-focus-editor
  - browser-sidebar-runtime-update-anchor
  - browser-sidebar-runtime-select-comment
  - browser-sidebar-runtime-prepare-comment-screenshot
  - browser-sidebar-runtime-comment-screenshot-ready
  - browser-sidebar-runtime-clear-comment-screenshot
  - browser-sidebar-runtime-exit-comment-mode
  - browser-sidebar-runtime-stop-agent-control
  - browser-sidebar-runtime-mouse-navigation
```

Main-process only:

```
browser-sidebar-comment-overlay-session
browser-sidebar-comment-overlay-prepare
browser-sidebar-comment-controller
browser-sidebar-comment-screenshot
browser-sidebar-comment-mode-site-status
```

### 11.8 Generic view IPC (preload.js)

```js
ipcRenderer.sendSync(`codex_desktop:get-sentry-init-options`)
ipcRenderer.sendSync(`codex_desktop:get-build-flavor`)
ipcRenderer.sendSync(`codex_desktop:get-shared-object-snapshot`)
ipcRenderer.sendSync(`codex_desktop:get-system-theme-variant`)
ipcRenderer.on(`codex_desktop:system-theme-variant-updated`, ...)
ipcRenderer.invoke(`codex_desktop:message-from-view`, ...)
ipcRenderer.on(`codex_desktop:message-for-view`, ...)
ipcRenderer.invoke(`codex_desktop:show-context-menu`, ...)
ipcRenderer.invoke(`codex_desktop:show-application-menu`, ...)
ipcRenderer.invoke(`codex_desktop:trigger-sentry-test`)

contextBridge.exposeInMainWorld(`codexWindowType`, `electron`)
contextBridge.exposeInMainWorld(`electronBridge`, {
  windowType, sendMessageFromView, getPathForFile,
  sendWorkerMessageFromView, subscribeToWorkerMessages,
  showContextMenu, showApplicationMenu,
  getFastModeRolloutMetrics, getSharedObjectSnapshotValue,
  getSystemThemeVariant, subscribeToSystemThemeVariant,
  triggerSentryTestError, getSentryInitOptions,
  getAppSessionId, getBuildFlavor
})
```

### 11.9 Interaction-mode sync payload (main-CUDSf52Z.js)

```js
// typical sync broadcast
{
  type:                     `browser-sidebar-runtime-sync`,
  interactionMode:           t.snapshot.interactionMode,  // "browse" | "comment"
  isAgentControllingBrowser: t.isAgentControllingBrowser,
  intlConfig:                t.runtimeIntlConfig,
  comments:                  n,
  commentModeDisabledReason: ...
}
```

### 11.10 Chrome extension installer constants

```js
DEFAULT_REMOTE_CHROME_EXTENSION_ID = "lfkehkpjohcoelkpembgemeipeppanef"
CHROME_EXTENSION_UPDATE_URL        = "https://clients2.google.com/service/update2/crx"
CHROME_WEB_STORE_EXTENSION_BASE_URL = "https://chromewebstore.google.com/detail"
EXTERNAL_EXTENSIONS_DIR_ENV        = "CODEX_CHROME_EXTERNAL_EXTENSIONS_DIR"
CHROME_PREFERENCES_PATH_ENV        = "CODEX_CHROME_PREFERENCES_PATH"
CHROME_USER_DATA_DIR_ENV           = "CODEX_CHROME_USER_DATA_DIR"
REMOTE_INSTALL_PERMISSION_PROMPT   = "Do you want to install the Codex Chrome Extension?"
```

Default external-manifest path on macOS:
```
~/Library/Application Support/Google/Chrome/External Extensions/lfkehkpjohcoelkpembgemeipeppanef.json
```

Content:
```json
{
  "external_update_url": "https://clients2.google.com/service/update2/crx",
  "is_from_webstore": true
}
```

### 11.11 CDP methods the runtime is known to use

```
Page: navigate, enable, reload, close, getFrameTree, getLayoutMetrics,
      captureScreenshot, getNavigationHistory, navigateToHistoryEntry,
      addScriptToEvaluateOnNewDocument, removeScriptToEvaluateOnNewDocument,
      setInterceptFileChooserDialog, fileChooserOpened (event),
      navigatedWithinDocument (event), frameNavigated (event),
      frameStartedLoading (event), domContentEventFired (event),
      loadEventFired (event)
Input: dispatchMouseEvent, dispatchKeyEvent, insertText
Runtime: enable, evaluate, consoleAPICalled (event), exceptionThrown (event)
DOM: getDocument, querySelector, describeNode, setFileInputFiles
```

### 11.12 Anchor field names (literal strings found in preload + main)

```
kind        pageUrl     frameUrl    title        elementPath
framePath   selector    role        name         nearbyText
point       xPercent    y           rect         isFixed
scrollContainers         attachedImages            screenshot
commentId   body        createdAt   anchor       anchorState
```

### 11.13 Surfaces in the renderer sidebar (Codex's own UI)

The same `commentAttachments` field appears in the outgoing message envelope (reference in `product-name-C630vpQ6.js`). The sidebar list of comments is driven by the same `snapshot.comments` array via `syncCommentSnapshot(owner, conversationId)` fan-out to the main Codex webview.

---

**End of research.**
