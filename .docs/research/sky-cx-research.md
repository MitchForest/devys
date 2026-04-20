# Sky CX Research

## Purpose

This document captures a deep reverse-engineering pass on the Codex macOS "Computer Use" runtime shipped inside the Codex app bundle. It covers:

- what is actually installed on disk
- how the runtime appears to be structured
- what evidence exists in manifests, plists, entitlements, frameworks, strings, and Objective-C metadata
- what was observed from limited live process inspection
- what is still inference instead of proof
- how we could recreate a comparable runtime in Devys

This is based on static bundle inspection plus a small amount of live process probing on the local machine.

## Executive Summary

The Codex macOS Computer Use feature is not just an Electron feature toggle. It is a separate native helper stack embedded inside the Codex app bundle.

The strongest evidence supports this architecture:

1. The main Codex app loads a first-party `computer-use` plugin.
2. That plugin launches a nested native client app, `SkyComputerUseClient`, in `mcp` mode.
3. The nested client appears to expose the MCP-facing tool surface to Codex.
4. The client appears to talk to a long-lived native background service, `SkyComputerUseService`, over an internal IPC layer.
5. The service appears to own permissions, app approvals, turn lifecycle tracking, and OS-level automation.

The runtime appears to combine:

- `ScreenCaptureKit` for screenshots/window capture
- macOS Accessibility APIs for semantic UI state
- synthesized mouse and keyboard input for physical interaction
- Apple Events / `ScriptingBridge` where app automation is allowed
- a background-session UI layer including a status item, virtual cursor, and Picture-in-Picture style affordances

The interaction model is explicitly per-turn. The shipped client strings say the agent must call `get_app_state` every assistant turn and that Codex automatically stops the app session after each assistant turn.

The runtime also appears to include:

- per-app approval state
- persistent approval storage
- browser URL safety gating
- app-specific instruction overlays for certain apps like Apple Music and Notion

One notable product split is that the main Codex app supports older macOS than the Computer Use helper does. The main app bundle was observed earlier with a minimum macOS of `12.0`, while the Computer Use helper and nested client both declare `15.0`. That strongly suggests Computer Use is an optional capability layer with stricter OS requirements than the base app shell.

## Scope And Method

The investigation used:

- plugin manifests
- app bundle plists
- codesigning entitlements
- notarization checks
- linked framework inspection with `otool -L`
- binary string inspection with `strings`
- Objective-C / Swift metadata inspection with `otool -ov`
- limited live process inspection with `ps`, `pgrep`, and `lsof`

This was enough to derive a high-confidence runtime model, but not enough to prove every wire-level detail. In particular, I did not successfully complete a standalone MCP session by launching the helper binaries outside the full Codex app context.

## Artifact Inventory

### Main app

- `/Applications/Codex.app`
- bundle id: `com.openai.codex`
- main app version observed earlier in bundle inspection: `26.415.32059` (build `1789`)
- main app minimum macOS observed earlier in bundle inspection: `12.0`
- bundled helper binaries include:
  - `/Applications/Codex.app/Contents/Resources/codex`
  - `/Applications/Codex.app/Contents/Resources/node`
  - `/Applications/Codex.app/Contents/Resources/rg`

### Computer Use plugin

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json`
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json`

### Computer Use helper stack

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app`
- service executable:
  - `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`
- nested client app:
  - `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app`
- nested client executable:
  - `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`

### Resource bundles

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle`
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Resources/Package_ComputerUseClient.bundle`
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Resources/Package_SlimCore.bundle`

## Manifest Evidence

The plugin manifest in `.codex-plugin/plugin.json` says:

- name: `computer-use`
- version: `1.0.750`
- description: `Control desktop apps on macOS from Codex through Computer Use.`
- interface text says Codex may take screenshots or page content, the user chooses which apps to allow, the user can stop actions at any time, and the user controls whether screenshots are used for training

This is important because it states the feature contract openly: screenshots, page content, app-scoped approvals, and user interruption are all first-class product concepts.

The MCP manifest in `.mcp.json` is even more important:

- it launches `./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`
- it passes `["mcp"]`

That is the cleanest evidence that the MCP-facing entrypoint is the nested client binary, not the Electron shell.

## Relationship To Browser Integrations

The broader Codex bundle strongly suggests that browser work is intentionally split across multiple paths, with Computer Use as only one option.

### In-app browser path

The separate bundled `browser-use` skill says the preferred path is the in-app browser backend, not raw desktop control. In earlier inspection of:

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/browser-use/skills/browser/SKILL.md`

the skill text explicitly steers the agent toward the in-app browser backend first and away from falling back to Computer Use just because desktop tools are visible.

Interpretation:

- browser automation is not supposed to default to screenshots and clicks
- Codex appears to treat browser automation as a first-class dedicated capability

### Chrome integration path

There is also a dedicated Chrome path in the broader Codex bundle. Earlier inspection of:

- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/chrome/skills/chrome/SKILL.md`
- `/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/chrome-extension-installer.js`

showed evidence that Codex can:

- detect or install a specific Chrome extension
- choose a concrete Chrome profile from local Chrome state
- write a Chrome external extensions manifest

Interpretation:

- Computer Use is not the only browser control mechanism
- the product likely prefers DOM- or extension-level browser control when available
- Computer Use becomes the fallback or gap-filler for browser workflows that are not covered by the in-app browser or Chrome extension path

This browser context matters because the Computer Use helper also contains browser URL safety gating. That makes more sense in a product where browser tasks can route through multiple control channels and only some of them require full desktop automation.

## Bundle And Signing Evidence

### Codex Computer Use.app

The helper app plist shows:

- bundle id: `com.openai.sky.CUAService`
- bundle name: `Codex Computer Use`
- version: `1.0`
- build: `750`
- minimum macOS: `15.0`
- `LSUIElement = true`
- Sparkle update feed:
  - `https://oaisidekickupdates.blob.core.windows.net/mac/cua/alpha/appcast.xml`

Interpretation:

- this is a background-style helper app, not a normal dock app
- it is built and versioned independently
- it is updateable on its own path

### Nested client app

The nested client plist shows:

- bundle id: `com.openai.sky.CUAService.cli`
- executable name: `SkyComputerUseClient`
- minimum macOS: `15.0`
- build: `750`

### Entitlements

Codesign entitlements on the helper app and client app show:

- `com.apple.security.automation.apple-events = true`
- app group: `2DC432GLL2.com.openai.sky.CUAService`

This is strong evidence that the runtime uses standard Apple automation channels rather than hidden system hooks.

### Notarization

`spctl` reports the helper app as:

- accepted
- source: `Notarized Developer ID`
- origin: `Developer ID Application: OpenAI OpCo, LLC (2DC432GLL2)`

## Linked Framework Evidence

Both `SkyComputerUseService` and `SkyComputerUseClient` link these key frameworks:

- `ScreenCaptureKit`
- `ApplicationServices`
- `ScriptingBridge`
- `WebKit`
- also `AppKit`, `CoreGraphics`, `IOKit`, `Network`, `SwiftUI`, and others

Interpretation:

- `ScreenCaptureKit` strongly suggests screenshot or window capture support
- `ApplicationServices` strongly suggests Accessibility and event synthesis work
- `ScriptingBridge` strongly suggests Apple Events / app scripting access
- `WebKit` suggests some browser or embedded web handling capability inside the helper stack

## Strongest Architectural Reading

The best-supported architecture is:

### Layer 1: Codex main app

Responsibilities likely include:

- agent orchestration
- threads and turns
- approvals UI integration
- plugin management
- appserver lifecycle

### Layer 2: MCP-facing client

The nested `SkyComputerUseClient` is very likely the MCP bridge. Evidence:

- `.mcp.json` launches it directly in `mcp` mode
- the client binary embeds tool descriptions and user-facing tool instructions
- the client binary includes `ComputerUseIPCClient` and multiple request/response model types

Likely responsibilities:

- expose Computer Use tools to Codex over MCP
- map tool invocations into internal IPC requests
- handle tool schemas, validation, and turn-level instructions
- deliver app-specific instruction snippets

### Layer 3: Long-lived service

The main helper executable `SkyComputerUseService` is very likely the resident OS-facing runtime. Evidence:

- it contains `ComputerUseIPCServer`
- it contains permission state classes
- it contains Codex appserver thread observer classes
- it contains session approval and persistent approval state
- it contains status-item and PiP-related classes

Likely responsibilities:

- permission acquisition and state tracking
- session activation / deactivation
- access to screenshots and accessibility trees
- real mouse and keyboard synthesis
- app approval persistence
- lifecycle handling when Codex turns end
- background UI affordances like status item and virtual cursor

## Client-Side Tool Contract Evidence

The client binary contains several very explicit strings.

### Per-turn session model

The client says:

- `Begin by calling get_app_state every turn`
- `Codex will automatically stop the session after each assistant turn`

This is one of the most important findings. It means Computer Use is not an open-ended infinite app-control session. It is designed as a turn-bounded interaction model.

### Tool list

The client embeds:

- `list_apps`
- `get_app_state`
- `click`
- `perform_secondary_action`
- `scroll`
- `drag`
- `type_text`
- `press_key`
- `set_value`

### Semantics

The client also embeds descriptions that strongly imply the operating model:

- `list_apps` returns running apps plus apps used in the last 14 days, with usage frequency
- `get_app_state` returns a screenshot and accessibility tree
- `click` can target an element index or pixel coordinates
- `perform_secondary_action` invokes a secondary accessibility action
- `set_value` sets the value of a settable accessibility element
- `press_key` supports `xdotool` key syntax

### Behavioral guidance

The client explicitly says:

- prefer element-targeted interactions over coordinate clicks when an element index is available
- avoid falling back to AppleScript during a Computer Use session
- verify UI changes after each action
- ask before destructive or externally visible actions such as sending, deleting, or purchasing

Interpretation:

- the system is trying to operate semantically first, not just visually
- raw pixel clicking is present, but it is a fallback
- AppleScript exists as a possible control path in the broader product, but the Computer Use runtime prefers its own action system

## IPC And Session Model Evidence

### Client-side IPC model types

The client binary contains:

- `ComputerUseIPCClient`
- `ComputerUseIPCRequest`
- `ComputerUseIPCAppState`
- `ComputerUseIPCApp`
- `ComputerUseIPCDiscoveredApp`
- `ComputerUseIPCListAppsRequest`
- `ComputerUseIPCAppStartRequest`
- `ComputerUseIPCAppModifyRequest`
- `ComputerUseIPCAction`
- `ComputerUseIPCLocationSpecifier`
- `ComputerUseIPCAppPerformActionRequest`
- `ComputerUseIPCSkyshot`
- `ComputerUseIPCSkyshotResult`
- `ComputerUseIPCEmptyResponse`
- `ComputerUseIPCAppGetSkyshotRequest`
- `ComputerUseIPCCodexTurnEndedRequest`

This is strong evidence that the client is not directly doing all work itself. It is encoding structured requests and responses for another process.

### Service-side IPC ownership

The service binary contains Objective-C / Swift metadata for:

- `ComputerUseIPCServer`
- ivars:
  - `ensureApplicationHasPermissions`
  - `onAppUsed`
  - `onCodexTurnEnded`
  - `clientExitSources`
  - `senderAuthorization`

This is the strongest evidence that the service owns the receiving side of the internal IPC boundary and enforces authorization and permission policy.

### Appserver connection

The service binary contains strings like:

- `Failed to connect to Codex appserver IPC socket`
- `Failed to create Codex appserver IPC socket`
- `Connected to Codex appserver IPC socket at %s`
- `Starting Codex appserver thread event observer`
- `turn-ended`

Interpretation:

- the service appears to watch Codex thread lifecycle from a local appserver socket
- this is likely how ended turns cause app sessions to be stopped or cleaned up

## Permission And Approval Model

### OS permissions

The binaries contain:

- `AccessibilityPermission`
- `ScreenRecordingPermission`
- `AppleEventsPermission`
- `requestingSystemSettingsPermission`

The service metadata contains:

- `CUAServicePermissionState`
- ivars:
  - `_isAccessibilityGranted`
  - `_isScreenRecordingGranted`
  - `_activePermissionRequest`
  - `_inProgressPermission`

Interpretation:

- the helper manages OS permission flow directly
- it tracks whether accessibility and screen recording were granted
- it likely opens System Settings when needed

### App-specific approvals

The client contains:

- `approvalStore`
- `computer_use_mcp_app_approval_requested`
- `computer_use_mcp_app_approval_resolved`
- a warning about prompt injection and data theft or loss

The service contains:

- `sessionApprovedBundleIdentifiers`
- `persistentApprovals`
- `persistentApprovalsModificationDate`

Interpretation:

- there is a second approval layer above macOS permissions
- OS permission is necessary but not sufficient
- each target app can require explicit approval
- approvals may persist across sessions

### Browser URL safety gating

Both binaries contain a stop message indicating that a session can end because Computer Use is not allowed on the current browser URL.

Interpretation:

- browser use is subject to URL policy, not just app bundle policy
- there is likely a domain or URL allow/deny layer when the app target is a browser

## Accessibility, Focus, And Input Synthesis

The binaries expose a lot of direct evidence for how the runtime manipulates the OS.

### Accessibility observers and focus control

The client contains strings and metadata for:

- `AXNotificationObserver`
- `SystemFocusedUIElementObserver`
- `WindowOrderingObserver`
- `SyntheticAppFocusEnforcer`
- `SystemFocusStealPreventer`

Metadata also shows:

- `SystemFocusedUIElementObserver`
  - `onFocusedUIElementChanged`
  - `appObserver`
  - `worker`
- a nested worker with `focusedUIElementObserver`
- `SyntheticAppFocusEnforcer`
  - `pid`
  - `frontmostApplicationTracker`
  - `frontmostApplicationObserver`
  - `clickEventTap`
  - `_state`

Interpretation:

- the runtime watches system focus and window ordering in detail
- it likely attempts to keep automation aligned with the intended app
- it likely tries to avoid or mitigate focus stealing side effects

### Input synthesis

The client contains:

- `clickEventTap`
- `dragContinuation`
- drag session handlers
- `mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:`

Interpretation:

- the runtime can synthesize real mouse motion, clicks, and drags
- it is not limited to high-level accessibility actions

### Semantic-first interaction

The client guidance plus tool surface points to a layered control strategy:

1. inspect the app using screenshot plus accessibility tree
2. target elements by index when possible
3. use semantic mutations like `set_value` or accessibility secondary actions
4. fall back to raw click, drag, or key synthesis when necessary

This likely explains how the product can claim background interaction without always competing with the user for the visible pointer.

## Skyshot Model

The word `Skyshot` appears repeatedly:

- `ComputerUseIPCSkyshot`
- `ComputerUseIPCSkyshotResult`
- `RefetchableSkyshotAXTree`
- service metadata includes `systemSelection` on `RefetchableSkyshotAXTree`

My interpretation is:

- "Skyshot" is the internal state snapshot object
- it likely combines screenshot pixels with accessibility tree data
- the `RefetchableSkyshotAXTree` type suggests the AX tree can be refreshed or rebound without losing surrounding session state

## MCP Transport Evidence

The service binary contains strings for:

- `initialize`
- `protocolVersion`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- `Session initialized`
- `Bad Request: Session not initialized`

It also contains HTTP/SSE transport strings:

- `text/event-stream`
- `application/json`
- `MCP-Session-Id`
- `http://localhost:`
- `mcp.transport.http.server.stateful`
- `Stateful HTTP server transport started`

Interpretation:

- some part of the helper stack includes a stateful MCP HTTP transport implementation
- the product may support more than stdio-only MCP internally
- the service may share MCP code even if the plugin entrypoint is the client binary

Important caveat:

- `.mcp.json` definitively launches the client, not the service
- I do not have proof that the service is directly exposed to Codex as an MCP endpoint in normal operation
- the strongest evidence still supports client-as-MCP-bridge and service-as-runtime

## Background UX Evidence

The service contains multiple signs that Computer Use is designed to operate without simply hijacking the user's active workspace.

### Background mode language

The shipped strings say:

- Computer Use tools allow use of the user's apps in the background
- the user can continue using other apps
- Codex should avoid disruptive actions like overwriting the clipboard unless requested

This is explicit product intent, not guesswork.

### Status item

The service contains:

- `CUAServiceStatusItemController`
- log strings about failing to initialize the status item button

The local preferences file currently contains:

- `NSStatusItem Visible Item-0`

Interpretation:

- the helper owns a menu-bar style status item for session visibility and control

### Picture-in-Picture

The service contains:

- `PIPControllerIntegrations`
- `feature/computerUsePIP`
- description: show backgrounded apps that Computer Use is working on in Picture-in-Picture mode
- `feature/computerUsePIPOverrideMinimizeButton`

Interpretation:

- there is likely a detached floating preview mode for background automation windows

### Virtual cursor

The service contains:

- `feature/computerUseCursor`
- `feature/detachComputerUseCursor`
- classes like `ComputerUseCursor`, `SoftwareCursorStyle`, `FogCursorStyle`, `AgentCursor`
- strings like `cursorWindow`, `cursorMotionProgressAnimation`, and `virtualCursor`

The bundled resources also contain a `LensSequence` folder full of animation frames.

Interpretation:

- the helper likely renders its own cursor or lens overlay
- this is probably used to visualize agent activity without requiring full takeover of the real system cursor

## App-Specific Instruction Layer

The helper ships app instruction documents in:

- `.../Package_ComputerUseClient.bundle/Contents/Resources/AppInstructions/`

Included files:

- `AppleMusic.md`
- `Clock.md`
- `Notion.md`
- `Numbers.md`
- `Spotify.md`

The Apple Music instructions show concrete, app-specific guidance such as:

- use `set-value` on the search text field
- use `Scroll Up` / `Scroll Down` actions for scrolling
- double-click a track to play it
- use the More button or right-click for queue actions

The client binary also contains:

- `appInstructionDeliveryState`
- `bundleIdentifiersWithDeliveredInstructions`
- an `<app_specific_instructions>` marker

Interpretation:

- this is not a purely generic computer-use stack
- the runtime can selectively inject playbooks for known apps
- the playbooks likely improve reliability without needing a dedicated plugin for every app

## Live Process Observations

I did a small amount of live runtime probing.

### What was observed

Launching the service directly created state under:

- `/Users/mitchwhite/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService`
- `/Users/mitchwhite/Library/Preferences/com.openai.sky.CUAService.plist`
- cache and HTTP storage paths under the helper bundle id

`lsof` showed the service reading and writing:

- cache db files
- HTTP storage sqlite files
- analytics db in the app group container

This is consistent with a standalone native helper maintaining its own persistent state.

### What was not proven

I was not able to successfully drive a full standalone MCP exchange with the binaries outside the normal Codex app context.

That means:

- I did not live-list tools through the real running helper
- I did not capture the exact internal IPC message format
- I did not prove the full socket topology between Codex, client, and service

The architecture described here is therefore:

- high confidence on process roles
- high confidence on tool surface and OS integration
- moderate confidence on exact IPC plumbing details

## Most Important Findings

If we compress the entire investigation down to the most consequential conclusions, they are:

1. Computer Use is a native helper architecture, not just an Electron wrapper feature.
2. The MCP-facing process is the nested `SkyComputerUseClient`, launched from the plugin manifest.
3. The long-lived service likely owns the hard parts: permissions, approvals, appserver turn tracking, and OS automation.
4. The interaction loop is screenshot plus accessibility tree plus action tools.
5. The runtime strongly prefers semantic element-level actions before coordinate clicks.
6. Sessions are bounded per assistant turn and must refresh state each turn.
7. The system includes an app approval layer in addition to macOS permissions.
8. The runtime is designed for backgrounded operation, with status-item, virtual cursor, and PiP-related UX.
9. There is explicit browser URL gating and prompt-injection risk language.
10. The stack ships app-specific instruction playbooks for reliability on known apps.

## How We Could Recreate This In Devys

The key point is not to clone the exact implementation. The key point is to recreate the product shape and reliability strategy.

The minimal credible Devys version should use the same high-level split:

### 1. Devys host app

Responsibilities:

- agent turns and approvals UX
- session orchestration
- visible task history and audit trail
- user intent confirmation for destructive actions
- plugin or capability routing

### 2. MCP-facing Computer Use client

Responsibilities:

- expose a clean tool surface to the model
- translate tool calls into structured internal requests
- inject app-specific instruction overlays
- enforce per-turn `get_app_state` discipline

Devys should not let the model speak directly to raw macOS APIs.

### 3. Native automation service

Responsibilities:

- own screen capture, accessibility, and input synthesis
- own permission state machine
- own approval store
- own browser URL policy checks
- own app session lifecycle
- emit snapshots and action results back to the client

This should be a native Swift service or helper app, not a JavaScript subsystem.

## Suggested Devys Architecture

### Process topology

Recommended topology:

1. Devys main app
2. `DevysComputerUseClient` helper launched in MCP mode
3. `DevysComputerUseService` resident helper

Communication model:

- app <-> client: stdio MCP or local plugin runtime
- client <-> service: authenticated local IPC
- service <-> app: turn lifecycle events and approval callbacks

### Core data model

We would need stable model types roughly like:

- `ComputerUseApp`
- `DiscoveredApp`
- `ComputerUseSession`
- `ComputerUseSnapshot`
- `AccessibilityNode`
- `LocationSpecifier`
- `ComputerUseAction`
- `PermissionState`
- `ApprovalState`
- `BrowserPolicyDecision`
- `TurnMetadata`

### Tool surface

A practical first version should mirror the Codex tool shape:

- `list_apps`
- `get_app_state`
- `click`
- `perform_secondary_action`
- `scroll`
- `drag`
- `type_text`
- `press_key`
- `set_value`

This is the right shape because:

- it is small
- it mixes semantic and physical actions
- it lets the model recover when one channel fails

### Snapshot design

The `get_app_state` result should include:

- screenshot bytes or image handle
- app bundle id
- window metadata
- accessibility tree with stable indices
- focused element info
- selected text or selection metadata when safely available
- scrollability hints
- action affordances for nodes

This is the most important product object. If the snapshot is weak, the whole system is weak.

## Recommended Implementation Plan

### Phase 1: Local single-app prototype

Goal:

- prove we can capture one app, inspect AX state, and perform safe actions

Build:

- Swift helper app with:
  - Accessibility permission checks
  - Screen Recording permission checks
  - `get_app_state` for a single frontmost app
  - `click`, `press_key`, `type_text`, `set_value`

Do not start with:

- multi-app concurrent sessions
- background PiP
- browser policies
- app-specific playbooks

Success criteria:

- can reliably inspect Finder, Notes, and TextEdit
- can target AX elements by stable indices
- can round-trip action then refresh state

### Phase 2: Add proper session model

Goal:

- make automation safe and turn-bounded

Build:

- app session activation
- per-turn `get_app_state` requirement
- explicit turn end deactivation
- approval prompts per bundle id
- persistent approval store

Success criteria:

- model cannot perform stale actions without refreshing state
- user can revoke or stop a session quickly

### Phase 3: Split client and service

Goal:

- separate MCP concerns from OS automation concerns

Build:

- MCP-facing client binary
- internal IPC layer
- authenticated sender checks
- structured request/response protocol

Success criteria:

- Devys app can relaunch or upgrade the client without collapsing the service model
- service remains the only owner of sensitive OS privileges

### Phase 4: Browser policy and known-app instructions

Goal:

- improve safety and reliability

Build:

- browser URL allow/deny layer
- app instruction registry keyed by bundle id
- bundle-specific action hints for popular targets

Success criteria:

- browser tasks can be blocked based on policy
- known apps become measurably more reliable than generic control alone

### Phase 5: Background UX

Goal:

- make automation understandable and non-disruptive

Build:

- menu-bar status item
- visible session indicator
- optional virtual cursor overlay
- optional detached preview / PiP

Success criteria:

- the user can always tell what the agent is doing
- the user can stop it immediately
- background work is observable without being annoying

## Concrete Technical Building Blocks For Devys

### macOS frameworks

Likely stack:

- `ScreenCaptureKit` for screenshots and window capture
- Accessibility APIs through `ApplicationServices`
- `CGEvent` or equivalent for event synthesis
- `ScriptingBridge` only when absolutely necessary
- `AppKit` for helper UI, overlays, and status item

### IPC options

Good candidates:

- XPC if we want tight native service boundaries
- Unix domain sockets if we want a simpler cross-process protocol
- a stateful local HTTP/SSE transport only if we truly need multi-client or inspection tooling

My recommendation:

- use XPC or Unix domain sockets first
- do not start with HTTP unless there is a clear product reason

### Storage

Need explicit storage for:

- persistent approvals
- recent app usage metadata if we want `list_apps` richness
- browser policy settings
- analytics and audit events

### Safety controls

Need first-class support for:

- destructive action confirmations
- stop session immediately
- clipboard protection
- app-scoped approvals
- browser URL gating
- permission state introspection

## What Not To Copy Blindly

We should not blindly reproduce every observed detail.

Things to avoid unless product need is proven:

- too many fallback paths between semantic actions, Apple Events, and raw clicks
- overcomplicated transport stacks
- aggressive background UX before core reliability exists
- broad app-specific playbooks too early

The right order is:

1. trustworthy snapshot
2. reliable semantic actions
3. explicit permissions and approvals
4. strong lifecycle model
5. UX polish and app-specific tuning

## Open Questions

The following remain unresolved:

- exact on-the-wire IPC message format between client and service
- whether the service exposes MCP internally or just shares MCP transport code
- exact browser URL policy source and enforcement point
- how recent-app usage history is gathered for the 14-day app list
- whether the background mode always avoids the real pointer or only sometimes
- when the runtime chooses accessibility action vs physical click vs Apple Events

These would require:

- live instrumentation during an actual Codex Computer Use task
- socket tracing
- process tree observation while the user triggers approvals
- possibly DYLD or logging interception if we wanted to go deeper

## Practical Recommendation For Devys

If we want this capability in Devys, the recommended path is:

1. Build a native Swift automation service first.
2. Model the tool contract around `get_app_state` plus a small action set.
3. Make the snapshot object excellent before chasing fancy UI.
4. Add per-app approvals and per-turn lifecycle before broad rollout.
5. Split MCP client from service once the single-process prototype proves reliability.
6. Only then add app-specific playbooks, browser policy, and background visualization.

The main product lesson from Codex is not just "use screenshots and clicks." The lesson is that a reliable macOS computer-use stack needs:

- a native helper boundary
- structured semantic state
- explicit safety and approval layers
- a turn-bounded lifecycle
- background UX that keeps the user in control

## Reproduction Commands

The following commands were useful during investigation:

```bash
nl -ba /Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json
nl -ba /Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json
plutil -convert xml1 -o - '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Info.plist'
plutil -convert xml1 -o - '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/Info.plist'
codesign -d --entitlements :- '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app'
codesign -d --entitlements :- '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app'
spctl -a -vv '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app'
otool -L '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService'
otool -L '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient'
strings -a '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService'
strings -a '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient'
otool -ov '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService'
otool -ov '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient'
find '/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Resources/Package_ComputerUseClient.bundle/Contents/Resources/AppInstructions' -type f
```

## Final Assessment

Codex Computer Use on macOS appears to be a fairly serious native automation runtime with a careful separation between:

- agent-facing tools
- privileged OS interaction
- approvals and permissions
- background user experience

It is not just "vision plus clicks." It is a layered system with:

- structured accessibility state
- screenshot-backed context
- action semantics
- app and URL gating
- session lifecycle management
- productized control affordances

That is the bar we should assume if we want to build a comparable experience in Devys.
