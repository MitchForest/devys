# Sky (Codex Computer Use) — Deep Research & Recreation Playbook

Comprehensive reverse-engineering notes on OpenAI's macOS Computer Use stack shipped inside the Codex Mac app (April 2026). Based on inspection of binaries, entitlements, Info.plists, Swift type names, embedded strings, MCP protocol artifacts, and bundled prompt packs on disk.

**Source app version analyzed**
- `Codex.app` — `CFBundleShortVersionString = 26.415.32059`, build `1789`, bundle ID `com.openai.codex`, Electron shell.
- `Codex Computer Use.app` (embedded plugin) — `CFBundleVersion = 750`, bundle ID `com.openai.sky.CUAService`, macOS 15.0+ min, built with `macosx26.1` SDK.
- Embedded client: `SkyComputerUseClient.app` — bundle ID `com.openai.sky.CUAService.cli`, copyright `© 2026 Software Applications Incorporated`.

**Binary paths on disk**
- Service: `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService` (12 MB arm64 Swift).
- CLI (MCP server): `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient` (10 MB).
- MCP wire: `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json`.

---

## 0. Executive summary

The new "computer use" capability in Codex is not part of the Electron app itself. It ships as a sibling macOS app bundle — internally codenamed **Sky** — that Codex launches as a **local MCP (Model Context Protocol) server** over stdio. Inside that bundle are two Swift executables:

- **SkyComputerUseService** — a privileged menu-bar agent that holds the TCC grants (Accessibility, Screen Recording, Apple Events) and actually drives the Mac via ScreenCaptureKit, `AXUIElement`, and CoreGraphics `CGEvent`.
- **SkyComputerUseClient** — a stateless stdio MCP server that Codex spawns per project; it proxies model tool calls to the Service over a codesign-verified Unix socket.

The model sees exactly **nine tools** (`list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, `set_value`). Every action returns a fresh **Skyshot** — a bundle of `{PNG screenshot, structured Accessibility tree with stable integer element indices, key-window metadata}`. The system prompt forces the loop structure: call `get_app_state` first each turn, then act, then the next action's return Skyshot is the grounding for the next decision.

Parallel "background" use works through `SyntheticAppFocusEnforcer` — the Service briefly promotes the target app to frontmost for the duration of one synthesized event, then restores the user's app. `ComputerUseAppInstanceManager` pools one `SerialExecutor` actor per target bundle ID; `CodexComputerUseSessionTracker` maps each Codex conversation to its set of open app instances. Multiple agents (different conversations) can safely act on different apps in parallel.

On-screen presence is rendered by the `Fog` module: a translucent GPU-composited backdrop that desaturates the controlled app, plus a virtual cursor (`ComputerUseCursor`) and a monocle/lens animation (`SkyLensView` — 45 PNG frames `Lens_frame_00.png`..`Lens_frame_44.png`).

Per-app approval ("Allow Codex to use {App}?") is delivered through MCP's **elicitation** feature — the Client returns a tool-call-level user prompt to Codex, which surfaces it in the UI, and the user's choice flows back into the tool response. Approvals persist per bundle ID in `AppApprovalStore`.

Provenance: the copyright on `SkyComputerUseClient` attributes the code to **Software Applications Incorporated** — Mike Matas's company, acquired by OpenAI. That team built the Mac CUA stack and it was rebranded into Codex as the "computer use" plugin.

---

## 1. Process topology

```
┌──────────────────────────────┐   MCP (JSON-RPC 2.0 over stdio)
│   Codex (Electron main)      │────────────────────────────────┐
│   CodexAppServerJSONRPC      │                                │
│   listens on a Unix socket   │                                ▼
└──────────────────────────────┘                  ┌─────────────────────────────┐
               ▲                                  │ SkyComputerUseClient        │
               │ JSON-RPC / LineBuffer            │   ComputerUseMCPServer      │
               │ (CodexAppServer IPC)             │   AppApprovalStore          │
               │                                  │   AppInstructionDelivery…   │
               │                                  │   CodexAppServerAuthCache   │
               │                                  └──────────┬──────────────────┘
               │                                             │ ComputerUseIPCClient
               │                                             │  (Unix socket + NSFileHandle,
               │                                             │   newline-delimited JSON;
               │                                             │   SecCode sender auth)
               ▼                                             ▼
     ┌─────────────────────────────────────────────────────────────────┐
     │ SkyComputerUseService  (menu-bar agent, LSUIElement)            │
     │                                                                 │
     │  Codex_Computer_Use:                                            │
     │    CUAServiceApplicationDelegate                                │
     │    CUAServiceStatusItemController                               │
     │    CUAServicePermissionState / …Window / …RowRegistry           │
     │    CodexAppServerThreadEventObserver   (→ Codex IPC)            │
     │    CodexComputerUseSessionTracker      (convID → {bundleIDs})   │
     │                                                                 │
     │  ComputerUse:                                                   │
     │    ComputerUseIPCServer                (inbound from Client)    │
     │    ComputerUseAppInstanceManager  →  ComputerUseAppInstance     │
     │                                                SerialExecutor   │
     │    ComputerUseAppController         (high-level app driver)     │
     │    RefetchableSkyshotAXTree + RefetchableUIElement              │
     │    ComputerUseCursor (+ Fog/SoftwareCursorStyle) + Window       │
     │    ComputerUseUserInteractionMonitor                            │
     │    ComputerUseURLBlocklistCache + AuraSiteStatusURLPolicyChecker│
     │    SkyshotClassifier                                            │
     │                                                                 │
     │  AccessibilitySupport:                                          │
     │    AXNotificationObserver, AXEnablementAssertion                │
     │    UIElementTreeInvalidationMonitor / …Transaction              │
     │    EventTap (CGEvent), SyntheticAppFocusEnforcer                │
     │    SystemFocusStealPreventer, KeyWindowTracker                  │
     │    SystemFrontmostApplicationTracker, WindowOrderingObserver    │
     │    SystemFocusedUIElementObserver, VirtualCursor, UIRecorder    │
     │                                                                 │
     │  Fog: WallpaperCaptureProvider, DesktopImageLayer/Source,       │
     │       FogBackgroundEffectViewController, ShareableContentContainer
     │  GraphicsSupport: FogBackdropLayer/View, NonanimatedLayer,      │
     │       WindowBoundsObserver                                      │
     │  SlimCore: SystemSettingsAccessCoordinator +                    │
     │       SystemSettingsAccessoryWindow (guides user through TCC)   │
     │  SQLite (their own wrapper, not better-sqlite3)                 │
     │  MCP (in-proc, for re-exporting state to the Client)            │
     │                                                                 │
     │  macOS APIs: ScreenCaptureKit, ApplicationServices (AX),        │
     │              CoreGraphics (CGEvent), Carbon TIS/UCKeyTranslate, │
     │              ScriptingBridge (Apple Events), AppKit, SwiftUI    │
     └─────────────────────────────────────────────────────────────────┘
```

Three processes. The Service is the only one that actually touches the OS; it holds the TCC grants. The Client is a stateless stdio MCP server that Codex spawns per project. They talk over a Unix socket created by the Service (evidence strings: `Failed to create Codex appserver IPC socket`, `_pipe`, `NSFileHandle.AsyncBytes`), framed as **newline-delimited JSON** via an internal `JSONRPCLineBuffer`. Every inbound IPC message is authenticated with `_SecCodeCopyGuestWithAttributes` + `_kSecCodeInfoTeamIdentifier` against the Codex team ID (`ComputerUseIPCSenderAuthorization`, `SecurityError.Requirement`) — so a random process can't inject actions.

### 1.1 Wire configuration that Codex ships

```json
// computer-use/.mcp.json (verbatim)
{
  "mcpServers": {
    "computer-use": {
      "command": "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
```

### 1.2 Plugin manifest that Codex loads

```json
// computer-use/.codex-plugin/plugin.json (verbatim excerpt)
{
  "name": "computer-use",
  "version": "1.0.750",
  "description": "Control desktop apps on macOS from Codex through Computer Use.",
  "mcpServers": "./.mcp.json",
  "interface": {
    "displayName": "Computer Use",
    "shortDescription": "Control Mac apps from Codex",
    "longDescription": "Mac Computer Use lets Codex use any app on your computer, including your web browsers and files you allow it to access. It may take screenshots or page content while working. You stay in control: you choose which apps to allow Codex to access, you can stop actions at any time, and control whether we use screenshots for training.",
    "defaultPrompt": [
      "Play a playlist to help me lock in",
      "Build & run my open Xcode project and test it for bugs",
      "Play a game in Chess.app"
    ]
  }
}
```

### 1.3 Entitlements (service)

Only one privileged entitlement is declared; everything else is TCC-gated at runtime.

```
com.apple.application-identifier         2DC432GLL2.com.openai.sky.CUAService
com.apple.developer.team-identifier      2DC432GLL2
com.apple.security.application-groups    [2DC432GLL2.com.openai.sky.CUAService]
com.apple.security.automation.apple-events  true
```

The CLI has the same entitlement shape but with `...CUAService.cli` identifier. Both share the same app group (for the Unix socket location).

### 1.4 Internal codenames

| Name | Meaning |
|---|---|
| **Sky** | The CUA runtime. Bundle ID prefix `com.openai.sky.*`; Swift module `Codex_Computer_Use`; supporting modules `ComputerUse`, `ComputerUseClient`, `AccessibilitySupport`, `Fog`, `SlimCore`, `GraphicsSupport`, `MCP`. |
| **Sidekick** | Auto-update feed (`https://oaisidekickupdates.blob.core.windows.net/mac/cua/alpha/appcast.xml`) — channel is `alpha`, delivery via Sparkle. |
| **Skyshot** | Bundle of {screenshot + AX tree + window metadata} returned from every action. Types: `RefetchableSkyshotAXTree`, `SkyshotClassifier`, `ComputerUseSkyshotAttachment`, `SkyshotCapture`. |
| **Fog / SkyLensView** | The on-screen "Sky is looking" overlay. Fog is the translucent desaturation backdrop; SkyLensView is the animated monocle/lens (45 frames). |
| **Aura** | Trust/safety URL policy service (`AuraSiteStatusURLPolicyChecker`). |
| **SAI** | Software Applications Incorporated — namespaces their private virtual-keyboard wrapper (`SAIVirtualKeyPress`). |
| **CUA** | Public-facing "Computer Use Assistant". |

---

## 2. The MCP tool surface (what the model sees)

Implemented by `ComputerUseClient.ComputerUseMCPServer` in the CLI binary. Nine tools, names and descriptions verbatim from the binary strings.

| Tool | Description (verbatim) | Args |
|---|---|---|
| `list_apps` | "List the apps on this computer. Returns the set of apps that are currently running, as well as any that have been used in the last 14 days, including details on usage frequency." | `{}` |
| `get_app_state` | "Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app." | `{ app: "App name or bundle identifier" }` |
| `click` | "Click an element by index or pixel coordinates from screenshot" | `{ index?, x?, y?, clicks=1, button="left" }` |
| `perform_secondary_action` | "Invoke a secondary accessibility action exposed by an element" | `{ index, action }` |
| `scroll` | "Scroll an element in a direction by a number of pages" | `{ index, direction: "up"\|"down"\|"left"\|"right", pages=1 }` |
| `drag` | "Drag from one point to another using pixel coordinates" | `{ startX, startY, endX, endY }` |
| `type_text` | "Type literal text using keyboard input" | `{ text }` |
| `press_key` | "Press a key or key-combination on the keyboard, including modifier and navigation keys. Supports xdotool's `key` syntax. Examples: `a`, `Return`, `Tab`, `super+c`, `Up`, `KP_0` (for the numpad 0 key)." | `{ key }` |
| `set_value` | "Set the value of a settable accessibility element" | `{ index, value }` |

Parameter descriptions pulled verbatim:
- `"Element index to click"`
- `"X coordinate in screenshot pixel coordinates"`
- `"Y coordinate in screenshot pixel coordinates"`
- `"Number of clicks. Defaults to 1"`
- `"Mouse button to click. Defaults to left."`
- `"Element identifier"`
- `"Secondary accessibility action name"`
- `"Scroll direction: up, down, left, or right"`
- `"Number of page scroll actions. Defaults to 1"`
- `"Start X coordinate"`, `"Start Y coordinate"`, `"End X coordinate"`, `"End Y coordinate"`
- `"Key or key combination to press"`
- `"Literal text to type"`
- `"App name or bundle identifier"`

Every action tool returns a **`SkyshotCapture`** — a bundled `{screenshot PNG (base64), refreshed AX tree, key-window metadata}`. That's why the system prompt tells the model "after each action, use the action result or fetch the latest state."

### 2.1 Verbatim system prompt

```
Computer Use tools let you interact with macOS apps by performing UI actions.

Some apps might have a separate dedicated plugin or skill. You may want to
use that plugin or skill instead of Computer Use when it seems like a good fit
for the task. While the separate plugin or skill may not expose every feature
in the app, if the plugin can perform the task with its available features,
prefer it. If the needed capability is not exposed there, use Computer Use
may be appropriate for the missing interaction.

Begin by calling `get_app_state` every turn you want to use Computer Use to
get the latest state before acting. Codex will automatically stop the session
after each assistant turn, so this step is required before interacting with
apps in a new assistant turn.

The available tools are list_apps, get_app_state, click, perform_secondary_action,
scroll, drag, type_text, press_key, and set_value. If any of these are not
available in your environment, use tool_search to surface one before calling
any Computer Use action tools.

Computer Use tools allow you to use the user's apps in the background, so while
you're using an app, the user can continue to use other apps on their computer.
Avoid doing anything that would disrupt the user's active session, such as
overwriting the contents of their clipboard, unless they asked you to!

After each action, use the action result or fetch the latest state to verify
the UI changed as expected.

Prefer element-targeted interactions over coordinate clicks when an index for
the targeted element is available. Note that element indices are the sequential
integers from the app state's accessibility tree.

Avoid falling back to AppleScript during a computer use session. Prefer Computer
Use tools as much as possible to complete tasks.

Ask the user before taking destructive or externally visible actions such as
sending, deleting, or purchasing. If helpful, you can ask follow-up questions
before taking action to make sure you're understanding the user's request
correctly.
```

### 2.2 Per-app skill packs (prompt sandwich)

Found at: `Codex Computer Use.app/Contents/Resources/Package_ComputerUseClient.bundle/Contents/Resources/AppInstructions/`

Five markdown files ship by default: `Notion.md`, `Spotify.md`, `AppleMusic.md`, `Numbers.md`, `Clock.md`. They're wrapped in `<app_specific_instructions>…</app_specific_instructions>` tags and injected **once per bundle ID per session** — tracked by `AppInstructionDeliveryState.bundleIdentifiersWithDeliveredInstructions: Set<String>`.

Examples of the per-app guidance style:

**Numbers.md** (spreadsheet cell editing):
```
To select a cell for editing, use a click. If the cell is empty or you'd
like to append to it, use one click; to replace the existing contents of
the cell, use three clicks.

When changing the value of the cell in a spreadsheet, return (in parallel):
(1) a click tool call (with either one or three clicks) to select the cell
and (2) a keyboard tool call to enter the new value(s).

Entering an entire row at a time (with \t delimiters) is great for batch
entry, but do not try to enter multiple rows at a time, or multiple formulas
a time, in one `type_text` call; it will fail.

- Focused spreadsheet cells may include a 'text entry area' which includes
  additional formatting, such as Markdown bolding, in table headers; you
  can ignore this.
- Cell values are saved right away; there's no need to press Return to
  confirm edits, unless you're finished with the entire spreadsheet.
- To enter a value for a checkbox cell, you may type 0 or 1.
```

**Spotify.md** (state convergence):
```
The Spotify app doesn't immediately update after requesting playback, so the
result from a click might indicate paused media or outdated media. Instead of
acting again, first: run `get-state` to confirm it didn't take. You may be
pleasantly surprised. Do not sleep any time, it should be updated by the
time you notice and request another `get-state`.
```

**Notion.md** (block model):
```
Notion document consists of "blocks". Blocks can be selected. To edit contents
of a selected block, press <Return>.

Insert one line of text at a time and press <Return> using parallel tool calls.

Format text by using markdown syntax. Unlike markdown, ">" inserts a toggle
checklist. Use "|" for block quotes.
```

**Clock.md** has the richest example — a full procedure for timers including input bounds (rejects >23:59:59).

These packs are the result of the team driving the agent against each app and patching the failure modes with written guidance rather than model training.

---

## 3. MCP protocol features Sky depends on

Sky ships its own in-process `MCP` module (Swift) that implements the full MCP spec plus three features that matter for CUA.

Evidence — modules linked and referenced:
- `MCP/Client.swift`, `MCP/Server.swift`, `MCP/Messages.swift`
- `MCP/StdioTransport.swift` (used between Client and Codex)
- `MCP/HTTPClientTransport.swift`, `MCP/StatefulHTTPServerTransport.swift`, `MCP/StatelessHTTPServerTransport.swift`
- `MCP/SSEClientTransport.swift`, `MCP/InMemoryTransport.swift`, `MCP/NetworkTransport.swift`
- `MCP.OAuthAuthorizer`, `MCP.OAuthNoRedirectSessionDelegate`, `MCP.InMemoryTokenStorage`, `MCP.SessionIDGenerator`

### 3.1 Elicitation

Fields in wire messages: `elicitationId`, `requestedSchema`, `action`, `url`, `message`.

Methods used:
- `elicitation/create` — server → client request: "ask the user X, return their answer"
- `notifications/elicitation/complete` — client → server: resolution

Sky uses elicitation for **two** things:

**(a) Per-app approval** — the first time a Codex conversation asks Sky to touch a given app, Sky returns an elicitation prompt:

```
Allow Codex to use {AppName}
Allowing Codex to use this app introduces new risks, including those related
to prompt injection attacks, such as data theft or loss. Carefully monitor
Codex while it uses this app.
```

Result actions include `allow / deny / allow_always / deny_always` — persistence handled by `AppApprovalStore`.

If the user denies, the tool call returns: `"Computer Use approval denied via MCP elicitation for app '{App}'"`.

**(b) Pending TCC permissions** — if Accessibility/Screen Recording aren't granted yet, tool calls return:

```
Computer Use permissions are still pending. The user has not finished granting
Accessibility and Screen Recording permissions in the Codex Computer Use
window. Call this tool again, as the user is almost done finishing granting
permissions. Do not end your turn yet, just call this tool again.
```

This is how the agent stays in the loop instead of erroring — it keeps re-calling, the user finishes the TCC flow, and the next call succeeds.

### 3.2 URL elicitation

For OAuth-style flows. `URL elicitation required: {url}` / `to complete the required authentication or input` / `Complete the required URL-based elicitation`.

### 3.3 Sampling

`sampling/createMessage` — server-to-client request that lets Sky ask the host (Codex) for an LLM completion. Likely used by `SkyshotClassifier` to ask *"does this screenshot contain image content?"* without bundling a local model. No CoreML/ONNX models are present on disk.

### 3.4 Turn-scoped session lifecycle

Custom notification: `agent-turn-complete`. Handled by `ComputerUseIPCCodexTurnEndedRequest.handle` on the Service side. Codex forwards `x-codex-turn-metadata` (containing `codex_session_id` and `codex_turn_id`) on every tool call so Sky can scope telemetry and so `SessionTracker` can scope approvals by conversation.

When `agent-turn-complete` fires, Sky tears down all open app-use sessions for that conversation. That's the implementation of the system-prompt line: *"Codex will automatically stop the session after each assistant turn."*

### 3.5 Roots

`notifications/roots/list_changed` — implemented but unclear from strings whether Sky uses it beyond spec compliance.

---

## 4. The inner IPC catalog (Client ↔ Service)

Every IPC message class name found in `SkyComputerUseService`'s strings (prefix `ComputerUse.ComputerUseIPC*`). Protocol is a Swift `ExecutableComputerUseIPCRequest.handle(…) async throws -> Response` actor.

| Request | Response | Meaning |
|---|---|---|
| `ComputerUseIPCListAppsRequest` | `[ComputerUseIPCDiscoveredApp]` with `{bundleIdentifier, displayName, lastUsedDate, useCount, isRunning}` | Ranked catalog for `list_apps`. |
| `ComputerUseIPCAppStartRequest` | `ComputerUseIPCAppState` | Launches/activates target; begins app-use session. |
| `ComputerUseIPCAppModifyRequest` + `Modification` enum | state | Focus changes, session teardown. |
| `ComputerUseIPCAppPerformActionRequest` (carries `ComputerUseIPCAction` + `ComputerUseIPCLocationSpecifier`) | `ComputerUseIPCSkyshotResult` | Bulk of the work: click/type/scroll/drag/set-value/secondary. |
| `ComputerUseIPCAppGetSkyshotRequest` | `ComputerUseIPCSkyshot` (`{image, tree, keyWindow, ancestors, elements, appName, bundleIdentifier}`) | `get_app_state`. |
| `ComputerUseIPCAppUsageRequest` | usage stats | Feeds `list_apps` recency ranking. |
| `ComputerUseIPCCodexTurnEndedRequest` | `ComputerUseIPCEmptyResponse` | Ends all of this conversation's app-use sessions. |
| `ComputerUseIPCPermissionResult` | (async) | Sent when TCC state changes. |

`ComputerUseIPCRequestRequiringSystemPermissions` is a marker protocol. Any request that needs AX/Screen Recording gates through the permission check and generates the "still pending" elicitation if grants are missing.

### 4.1 IPC wire format and auth

- **Transport:** Unix socket in the app-group container (`Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/…`), accessed via `NSFileHandle.AsyncBytes` and `FileHandle.write(contentsOf:)`.
- **Framing:** newline-delimited JSON. Class is `ComputerUse.JSONRPCLineBuffer`.
- **Envelope:** JSON-RPC 2.0 `{ id, method, params }`.
- **Sender auth:** every connection verified by `SecCodeCopyGuestWithAttributes(pid: peer)` → `SecCodeCopySigningInformation(..., kSecCSRequirementInformation, ...)` → compare `kSecCodeInfoTeamIdentifier` against `2DC432GLL2`. Mismatch → `SecurityError.Requirement` rejected.

Same socket is also used for the **Codex main ↔ Service** channel (`CodexAppServerThreadEventObserver.connection`) carrying `"thread-stream-state-changed"` with sub-events `"initializing-client"` / `agent-turn-complete`. Socket path contains `./.codex/plugins/computer-use` (per-project dotdir).

---

## 5. Skyshot — "seeing" the screen

The snapshot composition is orchestrated by `ComputerUse.RefetchableSkyshotAXTree` + `ComputerUse.RefetchableUIElement` + `AccessibilitySupport.UIElementTreeTransaction`.

### 5.1 Capture algorithm

1. **Pick target window.** `AccessibilitySupport.SystemFrontmostApplicationTracker` + `AccessibilitySupport.KeyWindowTracker` resolve the target app's `AXFocusedWindow`/`AXMainWindow`. `AccessibilitySupport.WindowOrderingObserver` maintains current z-order.
2. **Hold an AX assertion.** `AccessibilitySupport.AXEnablementAssertion` (with `AssertionTracker` + `operation` + `kinds`) elevates the target process's AX responsiveness for the duration of the snapshot.
3. **Walk the AX tree.** Breadth-first from the window root using `AXUIElementCopyAttributeValue` for these attributes (all observed as literal strings in the binary):

   `AXRole`, `AXSubrole`, `AXRoleDescription`, `AXTitle`, `AXTitleUIElement`, `AXDescription`, `AXValue`, `AXValueIncrement`, `AXIdentifier`, `AXPosition`, `AXSize`, `AXEnabled`, `AXFocused`, `AXSelected`, `AXChildren`, `AXActions`, `AXSelectedChildren`, `AXVisibleChildren`, `AXSelectedColumns`, `AXVisibleColumns`, `AXVisibleCharacterRange`, `AXSelectedTextMarkerRange`, `AXFocusedApplication`, `AXTextAttachment`, `AXTextualContext` (with sub-kind `AXTextualContextSourceCode` — special handling for source code editors).

   Guarded by a depth limit (`Max depth exceeded` message).

4. **Assign sequential integer `index`.** Each element gets a stable index for the life of the Skyshot. That integer is what the model passes as `index` to `click`/`scroll`/`set_value`/etc.
5. **Extract `actions`.** Per-element list from `AXUIElementCopyActionNames`, including `AXPress`, `AXPick`, `AXIncrement`, `AXShowMenu`. These populate the `action` argument of `perform_secondary_action`.
6. **Subscribe to diff notifications.** `AccessibilitySupport.UIElementTreeInvalidationMonitor` registers `AXObserver` callbacks for: `AXFocusedUIElementChanged`, `AXFocusedWindowChanged`, `AXSelectedTextChanged`, `AXSelectedRowsChanged`, `AXSelectedColumnsChanged`, `AXSelectedChildrenChanged`, `AXSelectedChildrenMoved`, `AXSelectedCellsChanged`. Used to build incremental `UIElementTreeTransaction`s instead of fully rewalking.
7. **Capture pixels.** Concurrent with step 3–6:
   - `SCShareableContent.current(excludingDesktopWindows:onScreenWindowsOnly:)` → iterate `SCWindow` for the target `ownerPID`, match against the target `AXFocusedWindow` via CGWindowID.
   - `SCContentFilter(desktopIndependentWindow:)` with the matched SCWindow.
   - `SCScreenshotManager.captureImage(contentFilter:configuration:completionHandler:)`.
   - Service method: `captureScreenshot(imageSize:) async -> CGImageRef`.
8. **Optional classify.** `SkyshotClassifier` (behind `feature/skyshotClassifier` — *"Enables classifier to determine if Skyshot contains image or not"*). Decides whether to attach the PNG or just send the AX tree. No local model; presumed implementation is either Apple Vision (`VNClassifyImageRequest`) or MCP sampling.
9. **Serialize.** PNG (base64) + tree JSON. Observed JSON keys: `{ appName, bundleIdentifier, keyWindow { title, frame }, ancestors[], elements[{index, role, subrole, roleDescription, title, description, value, enabled, focused, selected, actions[], children[]}], tree, image }`. Wrapped in `ComputerUseSkyshotAttachment` and returned as MCP `content: [image, text]`.

### 5.2 Why re-indexing each turn

The system prompt says *"element indices are the sequential integers from the app state's accessibility tree."* Each `get_app_state` re-numbers DFS. This is a deliberate design choice: persistent IDs would encourage the model to reuse stale indices after UI changes. Re-indexing forces the model to re-read state when the structure changes. Combined with the system prompt rule *"Begin by calling `get_app_state` every turn"* and the auto-session-stop on `agent-turn-complete`, the loop structure converges deterministically.

---

## 6. Synthetic input — CGEvent + keyboard-layout resolution

### 6.1 Mouse + scroll

Mouse and scroll go through `AccessibilitySupport.EventTap` and CoreGraphics.

Observed method signatures (demangled from Swift mangled names in the binary):

```swift
static func click(
    at: CGPoint,
    andDragTo: CGPoint?,
    mouseButton: CGMouseButton,
    count: Int,
    flags: CGEventFlags,
    inWindow: UInt32?,           // CGWindowID
    windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) async throws -> SkyshotCapture

static func mouseDown(
    eventNumber: Int64,
    type: MouseDownType,
    clickCount: Int,
    at: CGPoint,
    mouseButton: CGMouseButton,
    flags: CGEventFlags,
    inWindow: UInt32?,
    windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) async throws

static func scroll(
    at: CGPoint,
    deltaX: Int, deltaY: Int,
    inWindow: UInt32?,
    windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) throws

func scroll(deltaX: Int, deltaY: Int) async throws
func leftMouseDownUp(isG: Bool) async throws -> SkyshotCapture  // "G" likely "Guarded"
```

Built atop `CGEventCreateMouseEvent` and `CGEventCreateScrollWheelEvent`, posted via `CGEventPost(.cghidEventTap, event)`.

Internal string in service: *"Prefer simulating physical clicks over Accessibility actions."* The default path is CGEvent, not `AXUIElementPerformAction`, because many apps ignore AX actions for complex widgets. AX-level actions are used only for `perform_secondary_action`.

### 6.2 Keyboard — the tricky part

Keyboard events are wrapped in `SAIVirtualKeyPress` (format: `<SAIVirtualKeyPress: %d, %04x, %@>` = `{virtualKey, modifierFlags, char}`).

**Character → keycode resolution** (this is the subtle engineering that makes `type_text` work across layouts):

- Get current layout via `TISCopyCurrentKeyboardLayoutInputSource()` → `TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)`.
- For each target character, iterate virtual keycodes 0..127 × modifier masks, call `UCKeyTranslate` on each, find the `(keyCode, modifiers)` combination that produces the target Unicode character.
- Cache the resolution.
- On failure: `"Could not find key code for character: %C"`.

**Method signatures:**

```swift
static func createKeyboardEvent(
    source: CGEventSource?,
    virtualKey: UInt16,
    keyDown: Bool
) -> CGEvent?

static func pressKeysForHolding(
    _ keyDown: [SAIVirtualKeyPress],
    _ keyUp: [SAIVirtualKeyPress]
) async throws

static func pressKeys(_ keys: [SAIVirtualKeyPress]) async throws

func performKeyboardAction(
    _ action: KeyboardAction,
    text: String?,
    duration: Int?,
    waitForUIToSettle: Bool
) async throws -> SkyshotCapture
```

**xdotool syntax support** — `press_key` parses strings like `"super+c"`, `"shift+Return"`, `"KP_0"`. The parser walks a keysym table mapping xdotool names to virtualKeys, and modifier names (`super`, `cmd`, `ctrl`, `shift`, `alt`, `opt`, `meta`) to `CGEventFlags`.

**Modifier coalescing** — `cmd+shift+a` posts a single event pair with the combined `CGEventFlags`, not five down/up pairs. That's why fast agents don't leak stray shift-downs.

### 6.3 Action-level serialization

All input goes through `ComputerUseAppInstance.SerialExecutor` — a Swift custom actor executor. Parallel `click` + `type_text` from the same app session are serialized in-order so you never get interleaved modifier states, but actions on **different** app instances run truly concurrently.

---

## 7. Parallel background-app control (the "multiple agents" claim)

This is the novel architectural piece. Instead of hijacking your mouse, Sky drives apps "in the background" via a carefully orchestrated focus dance.

### 7.1 Focus enforcement

- **`AccessibilitySupport.SyntheticAppFocusEnforcer`** briefly promotes the *target* app to frontmost for the duration of a single action (so AX actions and keyboard input get routed there), then immediately restores the user's previous frontmost.
- Uses `NSWorkspace.shared.frontmostApplication` to snapshot, then `NSRunningApplication.activate(options:)` to promote, act, and restore. The promotion window is typically tens of milliseconds.

### 7.2 Focus-steal prevention

- **`AccessibilitySupport.SystemFocusStealPreventer`** with a `disallowedThiefProcesses` set blocks *other* apps from stealing focus during the promote-act-restore window. Without this, random notification popups or unrelated apps could claim the frontmost spot during the synthesized action.
- Uses `AXObserver` on `kAXApplicationActivatedNotification` / `NSWorkspaceDidActivateApplicationNotification` to detect thieves.

### 7.3 User-interaction monitoring

- **`ComputerUse.ComputerUseUserInteractionMonitor`** installs a `CGEventTap` in *listen-only* mode watching for real user input (mouse move, mouse click, keyboard). If the user starts using the computer, `UserInterruptedIntervention` fires and the event tap pauses Sky's synthetic input.
- This also enforces the "don't disrupt the user's active session" rule from the system prompt.

### 7.4 Multi-app concurrency

- **`ComputerUse.ComputerUseAppInstanceManager`** owns a pool of `ComputerUseAppInstance`s keyed by bundle ID.
- Each `ComputerUseAppInstance` owns a `SerialExecutor` actor — all actions on that app are serialized through it.
- **`Codex_Computer_Use.CodexComputerUseSessionTracker.bundleIDsByConversationID`** maps each Codex conversation to its set of active app instances.
- Different conversations can act on different apps truly in parallel; the same conversation's serial actions on one app are ordered.

### 7.5 Idle timeout

- Telemetry event: `cua_service_idle_timeout_reached`. After quiet period, the Service self-terminates to avoid holding AX attention forever (LSUIElement agents can be relaunched on-demand).

---

## 8. On-screen cue — Fog overlay + virtual cursor

Sky doesn't hijack your cursor. Instead it paints an unmistakable but non-disruptive overlay so the user always knows when the agent is active.

### 8.1 Virtual cursor

- **`ComputerUse.ComputerUseCursor`** — an `NSWindow` at the overlay window level (`Computer Use Cursor`), `ignoresMouseEvents = true`, hosting a `CALayer` tree rendering Sky's distinctive virtual cursor.
- Styles: `ComputerUse.SoftwareCursorStyle` and `ComputerUse.FogCursorStyle` (with `FogCursorViewModel`). Style selection is feature-flagged.
- Animated along `CursorMotionPath`s. Supporting types: `cursorMotionProgressAnimation`, `cursorMotionNextInteractionTimingHandler`, `cursorMotionCompletionHandler`, `cursorMotionDidSatisfyNextInteractionTiming`.
- Also: `ComputerUseCursor.AppMonitor` watches the target app and pauses/resumes the cursor animation when windows come/go.
- Feature flags: `feature/computerUseCursor` (*"Enable the virtual cursor in Computer Use"*), `feature/detachComputerUseCursor` (*"Detach the computer use cursor from the command palette"*).

### 8.2 Sky lens (the monocle)

- **`ComputerUse.SkyLensView`** — the monocle/magnifying-glass shape rendered via an animated sprite. 45 PNG frames at `Package_ComputerUse.bundle/Contents/Resources/LensSequence/Lens_frame_00.png`..`Lens_frame_44.png`. Signals "Sky is looking."

### 8.3 Fog backdrop

- **`Fog.WallpaperCaptureProvider`** — samples the user's desktop wallpaper once via `SCShareableContent`, emits `Fog.WallpaperCaptureProvider.WallpaperEvents`.
- **`Fog.DesktopImageLayer`** / **`Fog.DesktopImageSource`** — a `CALayer` + `CGImage` source backed by the captured wallpaper.
- **`Fog.FogBackgroundEffectViewController`** + `Fog.FogBackgroundEffectWindow` — hosts the composite.
- **`GraphicsSupport.FogBackdropLayer`** + **`GraphicsSupport.FogBackdropView`** with `LayerFilter` — the actual `CALayer` + `CIFilter` blur/desaturation composite.
- **`GraphicsSupport.NonanimatedLayer`** + **`GraphicsSupport.WindowBoundsObserver`** — ensure the fog tracks window bounds without stutter.
- Dev override: `feature/overrideFogSamplingTexture` lets engineers drop a file at `~/Pictures/SkyWallpaper.jpg` to pin a test texture. Preference: `wallpaperCaptureOpacity`, `dynamicShadowWallpaperCaptureOpacity`.

### 8.4 SystemSettings accessory (onboarding)

- **`SlimCore.SystemSettingsAccessoryWindow`** + **`SlimCore.SystemSettingsAccessoryTransitionOverlayWindow`** + **`DraggableApplicationView`** — the animated pointer window that appears over System Settings and shows the user where to drag the app icon into **Accessibility** or **Screen Recording** during first-run.
- Coordinator: `SlimCore.SystemSettingsAccessCoordinator`.
- Drives the TCC grant UX — they don't just show a "please grant permission" dialog, they animate a clone of the app icon from the permissions window into the correct row of System Settings.

---

## 9. Approval / permission state machine

Two independent things gate each action: OS-level TCC and Sky's per-app approval.

### 9.1 OS-level TCC

Handled by:
- **`Codex_Computer_Use.CUAServicePermissionState`** — observable object with `_isAccessibilityGranted`, `_isScreenRecordingGranted`, `_activePermissionRequest`. Uses Swift's `@Observable` observation registrar.
- **`Codex_Computer_Use.CUAServicePermissionRowRegistry`** — registry of `Entry` (`sourceView`, `snapshotProvider`) that drives the row UI.
- **`Codex_Computer_Use.CUAServicePermissionsWindow`** — SwiftUI window that walks the user through granting.
- **`CUAServicePermissionRowTransitionSourceProbe.ProbeView`** — the view whose bounds become the starting rectangle for the drag-to-Settings animation.

States observed in strings: `granted`, `denied`, `pending`, `requested`, `authorized`.

When a tool call hits a missing TCC, the MCP response uses **elicitation** (see §3.1b) to tell the model to loop rather than fail.

### 9.2 Per-app approval (Sky's own layer)

- Store: **`ComputerUseClient.AppApprovalStore`** — persists per-bundle-ID decisions. Backed by a SQLite table (wrapper in `SQLite/` module — **their own lightweight SQLite wrapper, not better-sqlite3** which is a separate thing used by the Electron main for Codex's memory feature).
- UI copy: `"Allow Codex to use {AppName}"` + `"Allowing Codex to use this app introduces new risks, including those related to prompt injection attacks, such as data theft or loss. Carefully monitor Codex while it uses this app."`
- Telemetry: `computer_use_mcp_app_approval_requested` / `_resolved` / `_result` / `_persistence`.
- Result actions: `allow` / `deny` / `allow_always` / `deny_always` (persistence flag determines whether decision is remembered).
- Error strings: `"Computer Use could not persist the approval permanently."`, `"Computer Use permission request canceled for app '{App}'"`, `"Computer Use approval denied via MCP elicitation for app '{App}'"`.

---

## 10. URL blocklist (content safety)

Classes: `ComputerUse.ComputerUseURLBlocklistCache`, `ComputerUse.ComputerUseURLPolicyChecking`, `ComputerUse.AuraSiteStatusURLPolicyChecker`, `ComputerUse.ComputerUseURLBlocklist`.

- "Aura" appears to be an OpenAI trust/safety service.
- Cached verdicts keyed by URL.
- `ChatGPT-Account-ID` is sent in the request header (pulled from `CodexAppServerAuthCache`).
- The check runs before any CUA action that might trigger navigation (e.g., before `get_app_state` on a browser window, or before `press_key` that could submit a form).

---

## 11. Telemetry taxonomy

All telemetry events and context keys observed:

**Context (on every event):**
- `codex_computer_use` (context namespace)
- `codex_session_id`
- `codex_turn_id`

**Service lifecycle:**
- `cua_service_launched`
- `cua_service_idle_timeout_reached`
- `cua_service_permission_window_shown`
- `cua_service_permission_requested`
- `cua_service_permission_grant_finished`
- `cua_service_permission_grant_duration`
- `cua_service_permission` (rollup)
- `cua_service_result`

**Session:**
- `computer_use_started`
- `computer_use_ended`

**IPC:**
- `computer_use_ipc_request_failed`
- `computer_use_ipc_request_type`
- `computer_use_ipc_error_code`

**MCP:**
- `computer_use_mcp_server_launched`
- `computer_use_mcp_tool_called`
- `computer_use_mcp_tool_name`
- `computer_use_mcp_app_approval_requested`
- `computer_use_mcp_app_approval_resolved`
- `computer_use_mcp_approval_result`
- `computer_use_mcp_approval_persistence`

Telemetry context class: `Logging.CodexComputerUseTelemetryContext`.

---

## 12. Feature flags (developer/debug menu)

From `meta/featureFlagMenu`:

| Flag | Behavior |
|---|---|
| `feature/screenshot` | Gates the screenshot attachment in Skyshots. |
| `feature/skyshotClassifier` | Enables classifier deciding whether Skyshot contains image or not. |
| `feature/computerUseCursor` | Enable the virtual cursor in Computer Use. |
| `feature/detachComputerUseCursor` | Detach the computer use cursor from the command palette. |
| `feature/overrideFogSamplingTexture` | If `~/Pictures/SkyWallpaper.jpg` exists, use it instead of the real wallpaper for Fog. |
| `workaround/overrideFunctionsAgentSystemPrompt` | Read `AllFunctionsAgent` system prompt from `~/systemprompt.txt` for debugging. |
| *(unnamed)* | *"Prefer simulating physical clicks over Accessibility actions."* |
| *(unnamed)* | *"Allows 'Do All' to submit sensitive tool calls in the background. This is disabled to prevent data leakage by default."* |
| *(unnamed)* | *"Enables the Send Email tool for Gmail"* |
| *(unnamed)* | *"Enables evaluation tools in the debug menu."* |
| *(unnamed)* | *"Enables showing argument fields in previews for custom tools."* |
| *(unnamed)* | *"When Anthropic or OpenAI is set as the default chat service, use their web search tools instead of Exa."* |

Settings suite storage: error string `"Failed to initialize Feature Flags store for suiteName = %s"` implies `UserDefaults(suiteName:)`.

---

## 13. Full Swift class inventory

Extracted by demangling `_TtC*` symbols in the binary strings. Grouped by module.

### Codex_Computer_Use (the Service's top-level app code)
- `CUAServiceApplicationDelegate`
- `CUAServiceStatusItemController`
- `CUAServicePermissionState`
- `CUAServicePermissionsWindow`
- `CUAServicePermissionRowRegistry` + `.Entry`
- `CUAServicePermissionRowTransitionSourceProbe.ProbeView`
- `CodexAppServerThreadEventObserver`
- `CodexComputerUseSessionTracker`
- `(ResourceBundleClass)`

### ComputerUse (the core CUA runtime)
- `ComputerUseAppController`
- `ComputerUseAppInstance` + `.SerialExecutor`
- `ComputerUseAppInstanceManager`
- `ComputerUseIPCServer`
- `ComputerUseIPCClient`
- `ComputerUseCursor` + `.Style` + `.Window` + `.AppMonitor` + `.Delegate`
- `SoftwareCursorStyle`, `FogCursorStyle`, `FogCursorViewModel`
- `SkyLensView`
- `SkyshotClassifier`
- `SkyshotCapture` (value type)
- `ComputerUseSkyshotAttachment`
- `RefetchableSkyshotAXTree`
- `RefetchableUIElement`
- `ComputerUseURLBlocklistCache`
- `ComputerUseURLBlocklist`
- `AuraSiteStatusURLPolicyChecker`
- `ComputerUseUserInteractionMonitor`
- `UserInterruptedIntervention`
- `JSONRPCLineBuffer`
- `CodexAppServerJSONRPCConnection`
- `CodexAppServerAuthCache` (+ `CachedCodexAuth`, `CodexAppServerAuthProvider`, `CodexAppServerAuthError`)
- `CodexAuthProviding` (protocol)
- `CodexMCPServerConfig`
- `LaunchConfiguration`
- `PIPControllerProxy` (picture-in-picture?)
- `PIPControllerIntegrations`
- `SystemSelectionClient`
- IPC message types:
  - `ComputerUseIPCRequest` (protocol)
  - `ExecutableComputerUseIPCRequest` (protocol)
  - `ComputerUseIPCRequestTypes` (enum)
  - `ComputerUseIPCRequestRequiringSystemPermissions` (protocol)
  - `ComputerUseIPCSenderAuthorization` + `SecurityError` + `Requirement`
  - `ComputerUseIPCAppUsageRequest`
  - `ComputerUseIPCListAppsRequest`
  - `ComputerUseIPCDiscoveredApp`
  - `ComputerUseIPCAppStartRequest`
  - `ComputerUseIPCAppModifyRequest` + `.Modification`
  - `ComputerUseIPCAppPerformActionRequest`
  - `ComputerUseIPCAction`
  - `ComputerUseIPCLocationSpecifier`
  - `ComputerUseIPCAppGetSkyshotRequest`
  - `ComputerUseIPCSkyshot`
  - `ComputerUseIPCSkyshotResult`
  - `ComputerUseIPCAppState`
  - `ComputerUseIPCApp`
  - `ComputerUseIPCPermissionResult`
  - `ComputerUseIPCEmptyResponse`
  - `ComputerUseIPCCodexTurnEndedRequest`
- Enums: `ClickType`, `KeyboardAction`, `ScrollDirection`

### ComputerUseClient (the MCP server CLI)
- `ComputerUseMCPServer`
- `AppApprovalStore`
- `AppInstructionDeliveryState`
- `ComputerUseClient.ComputerUseIPCRequest` (client-side mirror)

### AccessibilitySupport (cross-cutting AX + input primitives)
- `AXNotificationObserver`
- `AXEnablementAssertion` + `AXEnablementOperation.AssertionTracker`
- `EventTap`
- `SyntheticAppFocusEnforcer`
- `SystemFocusStealPreventer`
- `SystemEventObserver`
- `SystemFocusedUIElementObserver` + `.Worker`
- `SystemFrontmostApplicationTracker` + `.UpdateHandlerObserver`
- `ApplicationWindow`
- `KeyWindowTracker`
- `UIElementTreeInvalidationMonitor`
- `WindowOrderingObserver`
- `UIRecorder`
- `VirtualCursor`
- `RunLoopTask` + `.RunLoopThread`

### Fog
- `WallpaperCaptureProvider` + `.WallpaperEvents`
- `DesktopImageLayer`
- `DesktopImageSource`
- `FogBackgroundEffectViewController`
- `FogBackgroundEffectWindow`
- `ShareableContentContainer`

### GraphicsSupport
- `FogBackdropLayer`, `FogBackdropView`
- `NonanimatedLayer`
- `WindowBoundsObserver`
- `FlippedView`

### SlimCore
- `ArrowWindow`
- `SystemSettingsAccessCoordinator`
- `SystemSettingsAccessoryWindow` + `.ViewController`
- `SystemSettingsAccessoryTransitionController`
- `SystemSettingsAccessoryTransitionOverlayWindow`
- `SystemSettingsAccessoryTransitionOverlayReplicantWindow`
- `SystemSettingsAccessoryTransitionContentModel`
- `SystemSettingsAccessoryWindowView.DraggableApplicationView`
- `SystemSettingsApp`
- `AppSearchEngine`
- `CoreLocationManager`
- `LazyContactStore`, `LazyEventStore`
- `DataFile`, `TemporaryFile`
- `Constants`

### MCP (their own Swift MCP SDK)
- `Client` + `.Batch`
- `Server`
- `StdioTransport`, `HTTPClientTransport`, `NetworkTransport`, `SSEClientTransport`, `InMemoryTransport`
- `StatefulHTTPServerTransport`, `StatelessHTTPServerTransport`
- `OAuthAuthorizer`, `OAuthNoRedirectSessionDelegate`, `InMemoryTokenStorage`
- `SessionIDGenerator`
- `RequestHandlerBox`, `NotificationHandlerBox`
- `MainFlag`
- `HTTPRequestValidator` (protocol with `requiredScopes` + `errorDescription`)

### SQLite (their own lightweight wrapper)
- `Connection`, `UnsafeConnection` + `.PreparedStatement`
- `Module` + `.Cursor` + `.Table`
- `Value`
- `FSEventStream.AsyncIterator`

### Animation + Logging + EventSource
- `Animation.AnimationCoordinator` + `.AnimationDriverHandler`
- `Animation.AnimationDriver`
- `Animation.DisplayLinkAnimationDriver`
- `Logging.EventLogger`
- `EventSource.EventSource` + `.Parser`

---

## 14. Method signatures reconstructed from mangled symbols

Partial decode of Swift symbol fragments found in binary strings. These are the action primitives on the Service side.

```swift
// ComputerUseAppController / ComputerUseAppInstance
func performClick(
    elementID: Int,
    type: ClickType?,
    numberOfClicks: Int?
) async throws -> SkyshotCapture

func performSecondaryAction(
    elementID: Int,
    action: String
) async throws -> SkyshotCapture

func performKeyboardAction(
    _ action: KeyboardAction,
    text: String?,
    duration: Int?,
    waitForUIToSettle: Bool
) async throws -> SkyshotCapture

func setValue(elementID: Int, value: String) async throws -> SkyshotCapture

func scroll(deltaX: Int, deltaY: Int) async throws
func leftMouseDownUp(isG: Bool) async throws -> SkyshotCapture
func mouseMoved(...)

func captureScreenshot(imageSize: CGSize?) async throws -> CGImageRef

// Drag composition
func clickAt(
    _ point: CGPoint,
    withCount count: [Int]?,
    andDragTo: CGPoint?,
    mouseButton: CGMouseButton,
    ...
) async throws -> SkyshotCapture
```

```swift
// AccessibilitySupport.EventTap (static helpers)
static func click(
    at: CGPoint, andDragTo: CGPoint?,
    mouseButton: CGMouseButton, count: Int,
    flags: CGEventFlags,
    inWindow: CGWindowID?, windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) throws

static func mouseDown(
    eventNumber: Int64, type: MouseDownType, clickCount: Int,
    at: CGPoint, mouseButton: CGMouseButton,
    flags: CGEventFlags,
    inWindow: CGWindowID?, windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) throws

static func scroll(
    at: CGPoint, deltaX: Int, deltaY: Int,
    inWindow: CGWindowID?, windowBounds: CGRect?,
    usesFlippedCoordinates: Bool
) throws

static func createKeyboardEvent(
    source: CGEventSource?, virtualKey: UInt16, keyDown: Bool
) -> CGEvent?

static func pressKeys(
    _ keys: [SAIVirtualKeyPress]
) async throws

static func pressKeysForHolding(
    _ keyDown: [SAIVirtualKeyPress],
    _ keyUp: [SAIVirtualKeyPress]
) async throws
```

---

## 15. Swift source file inventory (referenced in binary)

Files referenced in assertion messages / type metadata — sketch of their source-tree layout:

```
Codex_Computer_Use/
  CUAServicePermissionRowRegistry.swift
  CUAServicePermissionState.swift
  CUAServiceStatusItemController.swift
  CodexAppServerThreadEventObserver.swift
  CodexComputerUseSessionTracker.swift
  GeneratedAssetSymbols.swift
  resource_bundle_accessor.swift

ComputerUse/
  ComputerUseCursor.swift
  RefetchableSkyshotAXTree.swift
  resource_bundle_accessor.swift

ComputerUseClient/
  resource_bundle_accessor.swift

AccessibilitySupport/
  UIElementTreeTransaction.swift

Fog/
  DesktopImageLayer.swift
  FogBackgroundEffectViewController.swift

GraphicsSupport/
  BackdropLayer.swift
  BackdropView.swift
  LayerFilter.swift

SlimCore/
  SystemSettingsAccessCoordinator.swift
  SystemSettingsAccessoryTransitionOverlayWindow.swift
  SystemSettingsAccessoryWindow.swift
  SystemSettingsAccessoryWindowView.swift
  resource_bundle_accessor.swift

MCP/
  Client.swift
  Server.swift
  Messages.swift
  StdioTransport.swift
  HTTPClientTransport.swift
  NetworkTransport.swift
  SSEClientTransport.swift
  StatefulHTTPServerTransport.swift
  StatelessHTTPServerTransport.swift
  InMemoryTransport.swift

Logging/
  CodexComputerUseTelemetryContext.swift

SQLite/
  Authorization.swift  ClientDataKey.swift  Context.swift
  Index.swift  Predicate.swift  PreparedStatement.swift
  StatementIdentifier.swift  Table.swift  Token.swift
  Updates.swift  Value.swift

SQLiteSchema/
  TableColumn.swift

Animation/
  AnimationCoordinator.swift
  DynamicPropertyAnimator.swift

EventSource/
  EventSource.swift

ArgumentParser/...    (swift-argument-parser)
AsyncAlgorithms/...   (swift-async-algorithms)
Algorithms/...        (swift-algorithms)
Atomics/...           (swift-atomics)
SystemPackage/...     (swift-system)
```

Package bundles shipped (resources):
- `Package_ComputerUse.bundle` → `Assets.car` + `LensSequence/Lens_frame_00..44.png`
- `Package_SlimCore.bundle` → `Assets.car`
- `Package_ComputerUseClient.bundle` → `AppInstructions/*.md`

---

## 16. Other notable internals

- **Codex ↔ Service socket path:** `./.codex/plugins/computer-use` (per-project dotdir inside the user's project directory).
- **Codex auth:** `CodexAppServerAuthCache.CachedCodexAuth` pulls `Payload` from Codex (ChatGPT auth). Service uses it to authenticate outbound calls to Aura/telemetry with `ChatGPT-Account-ID`.
- **AX scope:** `AXObserver` elevation (`AXEnablementAssertion`) is scoped to the target process, not a global grant.
- **`com.openai.atlas`:** referenced inside `AccessibilitySupport`. Atlas is OpenAI's browser — suggests shared AX/IPC code, or Atlas is whitelisted in `SystemFocusStealPreventer.disallowedThiefProcesses`.
- **Cursor-lock SQLite virtual table:** strings `CursorLock`, `CursorUnlock`, `CursorHint` — SQLite's VirtualTableCursor interface, unrelated to the UI cursor.
- **No bundled ML models.** No `.mlmodelc`, `.onnx`, `.espresso*`, or similar files — `SkyshotClassifier` does not ship a local model.
- **SDK target:** built with `macosx26.1` SDK (Xcode 26), minimum macOS 15.0 (Sequoia). The Electron app itself targets macOS 12.0+, but CUA requires 15.0+.
- **Sparkle auto-update:** alpha channel only (`.../mac/cua/alpha/appcast.xml`).
- **Default prompts** Codex shows for the plugin (user-visible suggestions):
  - "Play a playlist to help me lock in"
  - "Build & run my open Xcode project and test it for bugs"
  - "Play a game in Chess.app"

---

## 17. Why this design is good (architectural notes)

Three things stand out as genuinely worth copying:

**1. Separating the MCP server (Client) from the privileged worker (Service).**
The MCP server is stateless and spawnable per project — the host can fire up many and kill them freely. The Service holds the expensive state: long-lived app instances, cached AX trees, TCC grants, approval decisions. This keeps the MCP boundary clean (just a thin proxy) and means you never prompt for TCC per project.

**2. Actions return the next Skyshot, not a status code.**
This is what makes the loop converge. The model always has ground truth on what happened. No separate "did it work?" verification step is needed; the next observation is baked into the action response. Combined with re-indexing on every `get_app_state`, stale-state bugs mostly can't happen.

**3. Focus enforcement at the action level, not the session level.**
`SyntheticAppFocusEnforcer` brackets *individual* CGEvent posts with promote-and-restore, not whole sessions. That's why a Codex agent can drive Spotify while you keep typing in Xcode. Most prior CUA attempts hold focus for entire sessions and end up hijacking the user's flow.

Three things that are probably over-engineered for a clone:

- The full Sky lens + Fog backdrop + animated cursor system. Informative but not functionally required.
- The SlimCore animated "drag the app to Accessibility" onboarding. A plain "Open System Settings" button works fine.
- Their own SQLite wrapper — Apple's `SQLite3` import or GRDB is fine.

---

## 18. Recreation playbook

You can build a decent open-source clone in roughly **4 engineering weeks** by reusing the Sky architecture. Core decision: keep the **three-process split** (host, MCP server, privileged service) and the **Skyshot-as-return-value** invariant.

### 18.1 Repo layout

```
SkyLike/
├── Packages/                            # SwiftPM packages
│   ├── AccessibilitySupport/            # AX + CGEvent + focus (no UI)
│   ├── ComputerUse/                     # Skyshot, AppInstance, Manager, Controller
│   ├── ComputerUseClient/               # MCP stdio server + AppApprovalStore
│   ├── Fog/                             # Overlay backdrop + virtual cursor
│   ├── GraphicsSupport/                 # CALayer primitives
│   └── MCP/                             # use swift-mcp upstream; add elicitation if missing
├── Apps/
│   ├── SkyService.app/                  # LSUIElement=true; owns TCC; hosts IPC server
│   └── SkyClient/                       # CLI in Apps/SkyService.app/Contents/SharedSupport/
└── SkillPacks/                          # AppInstructions/{bundle-id}.md
```

Swift Package dependencies:
- [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) — CLI parsing.
- [`swift-async-algorithms`](https://github.com/apple/swift-async-algorithms) — sequences.
- [`swift-atomics`](https://github.com/apple/swift-atomics) — lock-free counters.
- [`swift-system`](https://github.com/apple/swift-system) — `FilePath`, `Errno`, `pipe()`.
- [`swift-mcp`](https://github.com/modelcontextprotocol/swift-sdk) — MCP impl.

### 18.2 Concrete build steps

**Week 1 — Skeleton + AX + capture**

1. **Service app skeleton.** `NSApplication` with `LSUIElement=true`. Menu bar status item. Entitlements: `com.apple.security.automation.apple-events`. Team ID + app group (`$TEAM_ID.com.yourco.sky`).
2. **TCC prompts.**
   - Accessibility: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
   - Screen Recording: `CGRequestScreenCaptureAccess()`; observe status via `CGPreflightScreenCaptureAccess()`.
   - Apple Events: per-bundle-ID prompts arrive automatically from the first `AppleScript`/`NSAppleScript` use.
3. **Permission window** (SwiftUI). Two rows, each with state `pending | granted | denied`. Deep-link to System Settings: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (and `..._ScreenCapture`).
4. **AccessibilitySupport package.**
   - `AXObserverWrapper` — `AXObserverCreate`, `AXObserverAddNotification`, run-loop source install. Notifications: the nine from §5.1.
   - `AXTreeWalker` — BFS with depth cap, `AXUIElementCopyAttributeValue` for the attributes from §5.1.
   - `UIElementTree` and `UIElementTreeTransaction` — snapshot + diff-from-previous.
   - `EventTap.click/scroll/mouseDown/mouseUp` — static helpers atop `CGEventCreateMouseEvent` / `CGEventCreateScrollWheelEvent`, `CGEventPost(.cghidEventTap, event)`.
   - `KeyboardLayoutResolver` — see §6.2. Carbon `TIS*` + `UCKeyTranslate` + cache.
   - `XDoToolParser` — keysym table for `press_key` argument.
5. **Capture via ScreenCaptureKit.**
   ```swift
   let content = try await SCShareableContent.current
   guard let sc = content.windows.first(where: { $0.owningApplication?.processID == pid
                                                  && $0.windowID == axWindowID }) else { ... }
   let filter = SCContentFilter(desktopIndependentWindow: sc)
   let cfg = SCStreamConfiguration()
   cfg.width = Int(sc.frame.width * 2); cfg.height = Int(sc.frame.height * 2)  // Retina
   let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
   ```

**Week 2 — Skyshot + input + focus**

6. **Skyshot composition.** Use the JSON keys from §5.1. Assign sequential integer `index` in DFS order. Emit `elements[]` and nested `tree`.
7. **Mouse helpers** from §6.1.
8. **Keyboard helpers** from §6.2. This is the longest task; budget 2–3 days.
9. **`SyntheticAppFocusEnforcer`** (§7.1). Wrap each action: snapshot prior frontmost → `activate(options: [.activateIgnoringOtherApps])` on target → perform → restore.
10. **`SystemFocusStealPreventer`** (§7.2). Observe `AXApplicationActivated` + `NSWorkspaceDidActivateApplicationNotification` during the action window. If unexpected activation, re-activate target. Whitelist your own service's bundle ID.
11. **`UserInteractionMonitor`** (§7.3). `CGEventTapCreate` in listen-only mode on mouse and keyboard events. If any recent (last 300 ms) real event, pause synthetic output.

**Week 3 — IPC + MCP server + approval**

12. **IPC transport.** Unix socket in app-group container (`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`). Validate peer via `SecCodeCopyGuestWithAttributes` + `kSecCodeInfoTeamIdentifier`. Framing: newline-delimited JSON. Build a `JSONRPCLineBuffer` that reads `NSFileHandle.AsyncBytes` into complete JSON objects.
13. **IPC request dispatch.** Define the types from §4. One async handler per request type. `ComputerUseAppInstanceManager` is just a `[String: ComputerUseAppInstance]` protected by an actor.
14. **MCP server CLI.** Swift `@main` that instantiates `MCPServer(transport: StdioTransport())`. Register the nine tools from §2. Each tool handler calls the matching IPC request on the Service. Return `content: [ImageContent, TextContent]` from Skyshot.
15. **Elicitation.** When the Service returns "permissions pending" or "approval required", the tool handler emits an `elicitation/create` request through MCP, awaits `elicitation/complete`, then decides how to answer the tool call.
16. **Approval store.** SQLite in app group. Table: `(bundle_id TEXT PRIMARY KEY, decision TEXT CHECK(decision IN ('allow','deny','allow_always','deny_always')), timestamp INTEGER)`.
17. **Plug into your host.** If using Claude Code / Codex-style host, drop in `.mcp.json` pointing to the CLI. Otherwise use any MCP-compatible host.

**Week 4 — Polish, on-screen cue, skills, telemetry**

18. **Virtual cursor + Fog** (§8). Overlay `NSWindow` at `.popUpMenu` level, `ignoresMouseEvents = true`. Root `CALayer` with a blurred wallpaper `CIFilter` backdrop and an animated cursor sprite on top. 45-frame lens sprite optional but fun.
19. **Skill packs.** Ship `AppInstructions/{bundleID}.md`. Load lazily; inject into MCP system prompt once per bundle ID per session. Sandwich: `<app_specific_instructions>\n{md}\n</app_specific_instructions>`.
20. **`list_apps` catalog.** Combine `NSWorkspace.shared.runningApplications` with `kMDItemLastUsedDate` queried via `NSMetadataQuery`, or parse `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments.sfl3`. Rank by combined recency + frequency. Fuzzy-match the caller's `app` argument (`firstMatchIndex`, `alternativeNames`, `lastUsedDateRanking`, `useCount`).
21. **Telemetry** (if you want it) — match the taxonomy in §11 for parity.
22. **Idle timeout.** After N minutes with no IPC requests, service self-quits (`NSApp.terminate(nil)`).

### 18.3 What to skip on v1

- **`SkyshotClassifier`** — just always attach the PNG.
- **URL blocklist** — ship a no-op `URLPolicyChecking` that returns "allow" for everything. Revisit when you have a trust service.
- **Sparkle** — ship manual updates.
- **SlimCore's animated permission window** — a plain SwiftUI row with "Open System Settings" is fine.
- **OAuth in MCP** — only needed for hosted-HTTP MCP transports.
- **CoreLocation / Contacts / EventKit integrations** — Sky links these frameworks but doesn't expose them as tools in v1.

### 18.4 What's easy to miss

- **Actions return the next Skyshot, not a status code.** This is the single most important invariant. Never return `"ok"` — always return `SkyshotCapture` (or an error).
- **Element indices are sequential and renumbered on each `get_app_state`.** Persistent IDs encourage the model to reuse stale indices after UI changes. Re-index every snapshot.
- **Focus enforcement must bracket individual actions,** not whole sessions. Otherwise your agent steals the user's typing.
- **The clipboard warning is not a substitute for actually not reading/writing the pasteboard.** Don't have your tools touch `NSPasteboard` at all unless the model asks.
- **Keyboard layout resolution via UCKeyTranslate is not optional** if you want to support non-US users. Plan for the full char→keycode cache.
- **Modifier coalescing:** build the full `CGEventFlags` mask once and post a single key-down/key-up pair per modifier group, not one pair per modifier.
- **Session scoping:** tie your per-app-approval state to the host's session/turn ID, not to wall-clock time. Otherwise an approval granted in one conversation leaks to another.
- **AX observer lifetime:** `AXObserver` must be installed on the run loop of whatever thread `AXUIElementCopyAttributeValue` will be called from — which must be a thread with a live CF run loop. Easiest: a dedicated `RunLoopTask` thread per target app (Sky has exactly this — `AccessibilitySupport.RunLoopTask.RunLoopThread`).

### 18.5 Estimated scope

Aggressive but achievable for one senior Swift engineer:

| Area | Days |
|---|---|
| Service skeleton + TCC UI | 2 |
| `AccessibilitySupport` package | 5 |
| Skyshot assembly + SCK capture | 2 |
| Mouse + keyboard synthesis | 4 |
| Focus enforcement + steal prevention + user monitor | 3 |
| IPC socket + codesign auth + request dispatch | 2 |
| MCP server CLI + elicitation + approval store | 3 |
| Skill packs + list_apps catalog | 2 |
| Virtual cursor + fog overlay | 3 |
| Polish, testing, quirks per app | 4 |
| **Total** | **~30 working days** |

---

## 19. Appendix — verbatim artifacts for reference

### 19.1 Full list of AX notifications observed

```
AXFocusedUIElementChanged
AXFocusedWindowChanged
AXSelectedTextChanged
AXSelectedColumnsChanged
AXSelectedRowsChanged
AXSelectedChildrenChanged
AXSelectedChildrenMoved
AXSelectedCellsChanged
```

### 19.2 Full list of AX attributes observed

```
AXRole, AXSubrole, AXRoleDescription
AXTitle, AXTitleUIElement, AXDescription
AXValue, AXValueIncrement
AXIdentifier, AXPosition, AXSize
AXEnabled, AXFocused, AXSelected
AXChildren, AXActions
AXSelectedChildren, AXVisibleChildren
AXSelectedColumns, AXVisibleColumns
AXVisibleCharacterRange
AXSelectedTextMarkerRange
AXFocusedApplication
AXTextAttachment
AXTextualContext (sub-kind: AXTextualContextSourceCode)
```

### 19.3 Secondary-action names observed

```
AXPress, AXPick, AXIncrement, AXShowMenu
AXIncrementArrow, AXIncrementButton
```

### 19.4 IPC error tags

```
missingArgument, invalidArgument, unknownTool
Invalid mouse button: {s}
Invalid scroll direction: {s}
pages must be >= 1
No scroll action was performed
Accessibility error: {AXError}
Max depth exceeded
Invalid number of keys found, expected one.
```

### 19.5 `AXError` cases Sky maps explicitly

```
AXError.attributeUnsupported
AXError.cannotComplete
AXError.illegalArgument
AXError.invalidUIElement
AXError.invalidUIElementObserver
AXError.notEnoughPrecision
AXError.notImplemented
AXError.notificationAlreadyRegistered
AXError.notificationNotRegistered
AXError.notificationUnsupported
AXError.parameterizedAttributeUnsupported
(undocumented AXError)
```

### 19.6 Auto-update channel

```
SUFeedURL = https://oaisidekickupdates.blob.core.windows.net/mac/cua/alpha/appcast.xml
SUPublicEDKey = 5Yw9jMXMH6O3mJZmpFuQT6ECfC3ZKBfVjWUVMNrElRo=
SUEnableAutomaticChecks = true
SUAutomaticallyUpdate = true
SUAllowsAutomaticUpdates = true
SUVerifyUpdateBeforeExtraction = true
```

### 19.7 Contents of the `Package_ComputerUse.bundle`

```
Package_ComputerUse.bundle/
  Contents/
    Info.plist
    Resources/
      Assets.car
      LensSequence/
        Lens_frame_00.png ... Lens_frame_44.png  (45 frames)
```

### 19.8 Contents of the `Package_ComputerUseClient.bundle`

```
Package_ComputerUseClient.bundle/
  Contents/
    Info.plist
    Resources/
      AppInstructions/
        AppleMusic.md
        Clock.md
        Notion.md
        Numbers.md
        Spotify.md
```

### 19.9 Full MCP method set Sky implements (client-side)

```
initialize
tools/list
tools/call
elicitation/create                (server → client)
notifications/elicitation/complete (client → server)
sampling/createMessage             (server → client)
notifications/roots/list_changed
notifications/agent-turn-complete  (OpenAI extension)
```

### 19.10 x-codex-turn-metadata header fields

```
codex_session_id
codex_turn_id
```

---

**End of research.**
