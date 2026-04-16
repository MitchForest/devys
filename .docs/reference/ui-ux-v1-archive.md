# Devys UI/UX Reference — Complete Interaction Specification

Updated: 2026-04-15

## Purpose

This document specifies every surface, interaction state, animation, and component needed for the redesigned Devys IDE. It is the canonical UI and interaction reference for what to build, how it behaves, and which reusable components compose each surface.

It supersedes the earlier design-system planning notes and pairs with:

- `architecture.md` for architecture and ownership rules
- `../plan/implementation-plan.md` for migration status and execution order

The goal is to produce a UI where:

- Every interaction has been thought through to the pixel level
- Every component is reusable and token-driven
- The main workflow (multiple repos, worktrees, agents in parallel) feels effortless
- Power users get keyboard-first efficiency; newcomers get visual clarity
- Joy comes from orientation, warmth, and responsiveness — not decoration

---

## Part 1: App Shell Architecture

### 1.1 Window Anatomy

```
┌─────────────────────────────────────────────────────────────────┐
│  Titlebar (unified compact toolbar)                             │
│  [◀▶ sidebar] ─── [breadcrumb / context] ─── [(+) FAB] [⌘K]   │
├────────┬──────────────┬─────────────────────────────────────────┤
│ Repo   │  Content     │                                         │
│ Rail   │  Sidebar     │       Tab Strip                         │
│        │              ├─────────────────────────────────────────┤
│ 44pt   │  260pt       │                                         │
│        │  (resizable) │       Split Pane Area                   │
│        │              │       (editor / terminal / agent /      │
│        │  Tab 1:      │        diff / empty pane CTA state)     │
│        │  Files &     │                                         │
│        │  Diffs       │                                         │
│        │              │                                         │
│        │  Tab 2:      │                                         │
│        │  Agents &    │                                         │
│        │  Workflows   │                                         │
│        │              │                                         │
├────────┴──────────────┴─────────────────────────────────────────┤
│  [Floating Status Capsule]                          (centered)  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Zone Model

The shell has four zones, each with a clear role:

| Zone | Width | Role | Background |
|------|-------|------|------------|
| **Repo Rail** | 44pt fixed | Project/worktree switching | `bg-2` |
| **Content Sidebar** | 260pt default, 180–400pt resizable | Browse files, diffs, agents | `bg-2` + `.sidebar` material |
| **Main Content** | Flexible | Tabs + split panes where work happens | `bg-1` (focused) / `bg-0` (unfocused) |
| **Status Capsule** | Auto-width, floating | Branch, sync status, errors | `bg-3`, `radius-full` |

### 1.3 Titlebar

The titlebar uses `NSToolbar` with `.unifiedCompact` style. Three regions:

**Leading (left of traffic lights):**
- Sidebar toggle button (chevron icon, toggles repo rail + content sidebar)

**Center:**
- Breadcrumb context: `RepoName / branch-name` — clickable, opens quick-switch popover
- When an agent tab is focused: `RepoName / branch-name / Agent: name` with agent identity color dot

**Trailing:**
- **(+) FAB button** — the single entry point for creating new tabs (replaces the 4 separate Shell/Agents/Codex/Claude buttons)
- **Command palette trigger** — `⌘K` icon button (supplementary to keyboard shortcut)

---

## Part 2: The (+) FAB — Unified Creation Point

### 2.1 Why

The current titlebar has four separate buttons (Shell, Agents, Codex, Claude) that:
- Take up permanent chrome space for infrequent actions
- Don't scale as we add more agent types
- Don't communicate what they create (tabs? sessions? splits?)
- Are disabled when no worktree is selected, creating dead UI

A single (+) button solves all of these. It's the universal "create something new" action.

### 2.2 Button Design

```
┌───────┐
│  (+)  │   28pt × 28pt, radius-full (circle)
└───────┘   accent.solid background, white icon
            Hover: accent.hover background, scale 1.05
            Press: accent.solid darkened 10%, scale 0.95
```

The (+) uses a `plus` SF Symbol at 14pt weight medium.

### 2.3 Menu Design (Popover)

Clicking (+) opens a popover anchored below the button. The popover uses `shadow-md`, `radius-lg`, `bg-3` background.

```
┌─────────────────────────────┐
│  New Tab                    │
│                             │
│  ◎ Terminal         ⌘T      │
│  ◎ Agent Session    ⌘⇧A     │
│  ◎ Claude Code      ⌘⇧C     │
│  ◎ Codex            ⌘⇧X     │
│                             │
│  ── Split ──────────────    │
│  ◎ Split Right      ⌘\     │
│  ◎ Split Down       ⌘⇧\    │
│                             │
│  ── Other ──────────────    │
│  ◎ Open File        ⌘O      │
│  ◎ Settings         ⌘,      │
└─────────────────────────────┘
```

**Row design**: Each row is a `DevysListRow` with:
- 18pt icon in `text-secondary`
- 13pt label in `text-primary` (proportional font)
- Trailing keyboard shortcut badge in `DevysKeyboardShortcut`
- Hover: `bg-4` background, 100ms ease-out
- Active: `accent.subtle` background

**Agent rows** show a small agent identity color dot preview to the left of the icon, hinting at the color the new session will receive.

**Behavior:**
- Menu appears with the signature spring (scale 95%→100% + fade, 180ms)
- Keyboard navigation: arrow keys move selection, Enter confirms, Escape closes
- Selecting an item closes the menu and creates the tab in the focused pane
- If no worktree is selected, Terminal/Agent/Claude/Codex rows are disabled with `text-disabled` and a tooltip: "Select a workspace first"

### 2.4 Keyboard Shortcuts (Direct, Bypassing Menu)

Power users never need to open the menu:

| Shortcut | Action |
|----------|--------|
| `⌘T` | New terminal in focused pane |
| `⌘⇧A` | New agent session (shows agent picker if multiple harnesses) |
| `⌘⇧C` | New Claude Code session |
| `⌘⇧X` | New Codex session |
| `⌘\` | Split right |
| `⌘⇧\` | Split down |
| `⌘K` | Command palette |

---

## Part 3: Tab Strip — Complete Interaction Specification

The tab strip is where people spend the most time. Every pixel matters.

### 3.1 Tab Pill Anatomy

```
┌──┬────────────────────────────────┬──┐
│▐ │  [icon]  Title           [●]  │×│
│▐ │                                │  │
└──┴────────────────────────────────┴──┘
 ↑                              ↑    ↑
 Identity stripe (2pt)     Dirty dot  Close button
 (agents only)             (4pt)      (hidden until hover)
```

**Dimensions:**
- Height: 34pt (comfortable) / 28pt (compact)
- Min width: 120pt
- Max width: 200pt
- Pill shape: `radius-sm` (6pt)
- Horizontal padding: 10pt
- Icon-to-title spacing: 6pt
- Title-to-close spacing: 4pt

### 3.2 Tab States

#### Default (Inactive, No Hover)

```
Background:     transparent
Title:          text-secondary, 12pt medium (proportional)
Icon:           text-secondary, 14pt
Close button:   hidden
Identity stripe: visible (agents only), identity color at 60% opacity
```

#### Hover (Inactive)

```
Background:     bg-3, fades in 100ms ease-out
Title:          text-secondary (no change)
Icon:           text-secondary (no change)
Close button:   fades in 100ms, text-tertiary, 10pt
Identity stripe: identity color at 80% opacity
```

On hover, the tab also shows a **tooltip** after 600ms delay:
- For agents: last 2 lines of output + status chip
- For terminals: current working directory + shell
- For editors: full file path relative to repo root
- For diffs: file path + change stats (+N -N)

#### Active (Selected)

```
Background:     bg-1 (matches content area — tab "merges" with content)
Title:          text-primary, 12pt semibold
Icon:           text-primary, 14pt
Close button:   visible, text-tertiary
Bottom border:  accent.solid, 2pt (the "you are here" indicator)
Identity stripe: identity color at 100% opacity (agents only)
Shadow:         shadow-sm on the pill edges for subtle lift
```

#### Active + Hover

```
Same as Active, except:
Close button:   text-secondary (brighter on hover)
Close hover:    bg-4 circle behind close icon
```

#### Preview Tab

```
Same as Inactive, except:
Title:          italic style
Opacity:        85% on the entire pill
```

A preview tab is a placeholder. Single-clicking a file opens it in the preview tab. Double-clicking (or editing) promotes it to a permanent tab. Only one preview tab per pane.

#### Dirty Tab (Unsaved Changes)

```
Same as respective state (active/inactive), plus:
Dirty dot:      4pt circle, warning color (#D4A54A), positioned left of close button
                The dot pulses gently once on transition to dirty (scale 1.0→1.3→1.0, 300ms)
Close button:   when hovered, the dirty dot disappears and close button appears
```

#### Agent Tab (Running)

```
Same as respective state, plus:
Identity stripe: 2pt left edge in agent color (coral, teal, violet, etc.)
Icon:           sparkles SF Symbol, tinted in agent identity color
Activity pulse: the identity stripe gently pulses (opacity 60%→100%, 2s cycle)
```

#### Agent Tab (Complete)

```
Identity stripe: static (no pulse)
A brief glow radiates from the stripe (300ms, then fades)
```

#### Agent Tab (Error)

```
Identity stripe: shifts to error color
A single gentle shake (2pt horizontal, 300ms)
Then static — errors need attention, not anxiety
```

#### Agent Tab (Waiting for Approval)

```
Identity stripe: shifts to warning color
A slow, gentle pulse (3s cycle) — slower than running, signaling patience needed
```

### 3.3 Tab Naming

Tab titles are determined by content type and must be concise but distinguishable:

| Content Type | Title Format | Example |
|-------------|-------------|---------|
| Editor | Filename (no extension by default) | `ContentView` |
| Editor (ambiguous) | Filename + parent dir | `ContentView — Views` |
| Terminal | `Terminal` + optional custom name | `Terminal`, `Terminal: build` |
| Agent | User-defined name, or auto: `Agent: harness` | `API Refactor`, `Agent: Claude` |
| Git Diff | Filename + status | `auth.swift (modified)` |
| Settings | `Settings` | `Settings` |

**Auto-disambiguation**: When two tabs have the same filename, append the parent directory in `text-tertiary` after an em dash. E.g., `ContentView — Views` vs `ContentView — Tests`.

**Agent naming**: Users can rename agent sessions. Double-clicking the agent tab title enters inline edit mode (text field replaces title, 200ms transition). Press Enter to confirm, Escape to cancel. The name persists for the session lifetime.

### 3.4 Tab Bar Behavior

**Scrolling:**
- When tabs overflow the pane width, the tab bar scrolls horizontally
- A subtle fade gradient (24pt wide) appears at the overflow edge(s)
- Scroll via trackpad gesture or Shift+scroll wheel
- An overflow indicator pill `•••` appears at the right edge; clicking it opens a dropdown of all tabs in the pane

**Tab overflow dropdown:**
- Same `shadow-md`, `radius-lg`, `bg-3` popover style
- Each tab shown as a row: icon + title + dirty dot + agent identity dot
- Active tab has `accent.subtle` background
- Click to select, keyboard navigable

**New tab button in tab bar:**
- A small `+` button (20pt × 20pt) sits at the right end of the tab bar, after the last tab
- `text-tertiary`, ghost style
- Hover: `bg-3` circle, `text-secondary`
- Click: opens the same (+) FAB menu, but anchored to this pane specifically (so the new tab opens in this pane, not the focused one)

### 3.5 Tab Drag & Drop — Complete State Machine

Tab drag-and-drop is the primary way users rearrange their workspace. Every state must feel polished.

#### Drag Initiation

```
Trigger:        Mouse down + 4pt movement threshold
Delay:          None (instant after threshold)
Cursor:         Changes to grab cursor on mouse down
Visual:         The tab pill lifts from the bar:
                - Scale to 1.05
                - shadow-lg appears
                - Opacity drops to 90%
                - 80ms spring transition for the lift
Source gap:     The space where the tab was collapses with a 150ms spring
                Other tabs slide together to fill the gap
```

#### Drag Preview

```
The lifted tab pill follows the cursor with a slight offset (+8pt x, +8pt y)
The preview shows: icon + title + identity stripe (if agent)
Size: matches original tab dimensions
Background: bg-4 with shadow-lg
Radius: radius-sm (matches tab pill)
```

#### Drag Over Tab Bar (Reorder)

```
As the drag preview moves over other tabs in the same bar:
- An insertion indicator appears: a 2pt vertical line in accent.solid
- The indicator slides between tabs with 100ms spring
- Adjacent tabs slide apart (4pt each side) to make room
- The insertion position updates based on cursor X relative to tab centers
```

#### Drag Over Different Pane's Tab Bar

```
Same as reorder, except:
- The target pane's tab bar gets a subtle accent.subtle background tint (150ms fade in)
- The insertion indicator appears in the target bar
- Releasing here moves the tab from source pane to target pane at the indicated position
```

#### Drag Over Pane Content Area (Split Creation)

```
When the drag preview moves over a pane's content area (not the tab bar):
The pane is divided into 5 drop zones:

         ┌──────────────────────────┐
         │         TOP (20%)        │
         ├──────┬──────────┬────────┤
         │      │          │        │
         │ LEFT │  CENTER  │ RIGHT  │
         │(20%) │  (60%)   │ (20%)  │
         │      │          │        │
         ├──────┴──────────┴────────┤
         │       BOTTOM (20%)       │
         └──────────────────────────┘

Zone visual feedback:
- CENTER:  Entire pane gets accent.subtle overlay (8% opacity)
           → Tab will be added to this pane's tab bar
- LEFT:    Left half gets accent.subtle overlay + a vertical accent.muted line at center
           → Will create a horizontal split, tab goes to new left pane
- RIGHT:   Right half gets accent.subtle overlay + vertical line
           → Horizontal split, tab to new right pane
- TOP:     Top half gets overlay + horizontal line
           → Vertical split, tab to new top pane
- BOTTOM:  Bottom half gets overlay + horizontal line
           → Vertical split, tab to new bottom pane

The overlay transitions in with 100ms fade
A 2pt dashed outline in accent.muted appears around the highlighted zone
```

#### Drop

```
On mouse up:
- If over tab bar: tab inserts at indicated position
  - The tab pill springs into place (signature spring, 180ms)
  - The shadow dissolves (100ms)
  - If moved to a different pane, the source pane's tabs re-flow

- If over content zone CENTER: tab is added to that pane's tab bar
  - Tab springs into the tab bar at the end
  - Content area overlay fades out (100ms)

- If over content zone LEFT/RIGHT/TOP/BOTTOM: pane splits
  - New pane slides in from the split edge (signature spring, 180ms)
  - The tab appears in the new pane's tab bar
  - Existing content compresses smoothly

- If over invalid area (outside window, or same position):
  - Tab springs back to original position (signature spring)
  - Shadow dissolves
  - The gap that was held open closes
```

#### Drop Cancel (Escape or Invalid)

```
Tab returns to original position with signature spring
All visual indicators (gaps, overlays, insertion lines) fade out 100ms
```

### 3.6 Tab Close Interaction

```
Close button click:
1. If tab is clean: tab closes immediately
   - Tab shrinks horizontally to 0 width (150ms spring)
   - Adjacent tabs slide to fill the gap (150ms spring, slightly delayed 30ms)
   - If it was the active tab, the next tab to the right becomes active
     (or the one to the left if it was the rightmost tab)

2. If tab is dirty: show save prompt
   - A small popover appears below the tab (not a modal sheet)
   - "Save changes to [filename]?" with three buttons: Save, Don't Save, Cancel
   - Save: saves then closes with animation above
   - Don't Save: closes with animation
   - Cancel: popover dismisses, tab stays open

3. If tab is the last tab in a pane:
   - Tab closes, pane shows empty state
   - If autoCloseEmptyPanes is on, pane collapses (reverse of split creation animation)

Middle-click on tab: close without prompt (force close)
⌘W: close active tab (with dirty prompt if needed)
⌘⇧W: close all tabs in focused pane
```

### 3.7 Tab Context Menu (Right-Click)

```
┌─────────────────────────────┐
│  Close                 ⌘W   │
│  Close Others               │
│  Close to the Right         │
│  Close All             ⌘⇧W  │
│  ── ──────────────────────  │
│  Split Right                │
│  Split Down                 │
│  ── ──────────────────────  │
│  Copy Path                  │
│  Reveal in Finder           │
│  ── ──────────────────────  │
│  Pin Tab                    │  (for agents: keeps tab from being replaced)
│  Rename Tab                 │  (for agents/terminals)
└─────────────────────────────┘
```

---

## Part 4: Split Panes — Zone Interaction Design

### 4.1 Divider States

Split dividers are invisible by default. The tone shift between panes is the separator.

#### Default State

```
Visual:         No visible line. The background color difference between
                focused (bg-1) and unfocused (bg-0) panes creates separation.
Cursor:         Default arrow cursor
Hit target:     8pt wide invisible hit area centered on the pane boundary
```

#### Hover State

```
Trigger:        Cursor enters the 8pt hit area
Visual:         A 2pt line in border-default fades in (150ms ease-out)
Cursor:         Changes to resize cursor (horizontal or vertical depending on split)
Adjacent panes: No change
```

#### Drag State (Resizing)

```
Trigger:        Mouse down on hovered divider
Visual:         Line thickens to 3pt, color shifts to accent.solid (100ms)
Cursor:         Resize cursor maintained
Adjacent panes: Subtle brightness shift — expanding pane brightens slightly,
                compressing pane dims slightly (very subtle, 5% opacity overlay)
Feedback:       Divider position updates in real time (display-synced, 120fps)
Constraints:    Each pane has a minimum width of 200pt (or height for vertical splits)
                Divider snaps to 50% when within 8pt of center (with haptic-style
                visual indicator — the line briefly glows accent.muted)
```

#### Drag Release

```
Visual:         Line returns to 2pt, color returns to border-default (100ms)
                After 1.5s of no interaction, line fades out entirely (200ms)
Cursor:         Returns to default if cursor exits hit area
```

### 4.2 Pane Focus

```
Focused pane:
  - Background: bg-1 (the content background — slightly lighter)
  - Tab bar: accent.subtle tint on background (barely visible)
  - No border. The background shift is the indicator.

Unfocused pane:
  - Background: bg-0 (the deepest background — slightly darker)
  - Tab bar: bg-2 (standard tab bar background, no tint)
  - Text and icons slightly dimmed (text-secondary instead of text-primary for some elements)

Focus change:
  - Background transitions with 200ms ease-in-out
  - The tab bar tint transitions with 150ms

Focus via click:
  - Clicking anywhere in a pane (tab bar, content, empty space) focuses it
  - No additional visual flourish needed — the background shift is enough

Focus via keyboard:
  - ⌘⌥← / ⌘⌥→ to navigate focus between panes (left/right)
  - ⌘⌥↑ / ⌘⌥↓ for vertical splits
```

### 4.3 Split Creation Animation

```
Trigger:    User chooses "Split Right" / "Split Down" from (+) menu or ⌘\ / ⌘⇧\

Horizontal split (right):
  1. A new pane slides in from the right edge of the current pane
  2. The existing content compresses leftward
  3. The divider position animates from 1.0 to 0.5
  4. Uses signature spring (response: 0.32, damping: 0.82)
  5. Duration: ~280ms to settle
  6. New pane receives focus and shows empty state or the specified tab

Vertical split (down):
  Same as horizontal but sliding from bottom, compressing upward

The animation is the same spring used everywhere — sidebar, modals, command palette.
```

### 4.4 Split Destruction Animation

```
Trigger:    Last tab closed in a pane (with autoCloseEmptyPanes), or explicit close

1. The closing pane compresses toward its origin edge (reverse of creation)
2. The adjacent pane expands to fill the space
3. Same signature spring, reversed
4. Focus moves to the adjacent pane
5. Duration: ~250ms to settle (slightly faster than creation — closing should feel snappy)
```

### 4.5 Empty Pane State

When a pane has no tabs:

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│         [sparkles icon, 32pt]       │
│                                     │
│      Open a file, start a           │
│      terminal, or launch            │
│      an agent                       │
│                                     │
│   [Terminal]  [Agent]  [Open File]  │
│                                     │
│                                     │
└─────────────────────────────────────┘

Background: bg-0
Icon: text-tertiary, 32pt
Text: text-tertiary, 14pt body, centered
Buttons: ghost style, text-secondary, 12pt
         Hover: bg-3 fill, text-primary
Spacing: space-4 between icon and text, space-3 between text and buttons
```

---

## Part 5: Repository Rail (Left Edge)

### 5.1 Purpose

The repo rail is the leftmost strip. It shows which repositories and worktrees are loaded and lets you switch between them. This is the highest-level navigation — "which project am I working in?"

### 5.2 Layout

```
┌────┐
│ ≡  │   ← Sidebar toggle (top)
├────┤
│    │
│ R1 │   ← Repository 1 (icon/avatar)
│    │
│ W1 │   ← Worktree 1.1
│ W2 │   ← Worktree 1.2
│    │
├╌╌╌╌┤   ← Subtle divider
│    │
│ R2 │   ← Repository 2
│    │
│ W3 │   ← Worktree 2.1
│    │
├────┤
│    │
│ (+)│   ← Add repo button (bottom)
│    │
└────┘
```

Width: 44pt
Background: `bg-2`
Border: `border-subtle` 1pt on the right edge

### 5.3 Repo Item

```
┌────────┐
│        │
│  [Rn]  │   Two-letter abbreviation of repo name in a rounded square
│        │   e.g., "DV" for "devys", "AP" for "api-server"
└────────┘

Default:    bg-3 square (radius-sm), text-secondary letters, 11pt semibold
Hover:      bg-4 square, text-primary letters, 100ms
Active:     accent.muted square, accent.solid letters
            Left edge: 3pt accent.solid indicator bar

Size: 32pt × 32pt square
Spacing: 8pt between items
```

### 5.4 Worktree Item (Nested Under Repo)

```
┌────────┐
│   ○    │   Small dot (6pt) or branch icon
│  main  │   Branch name, 9pt caption, truncated
└────────┘

Default:    text-tertiary dot and label
Hover:      text-secondary, bg-3 pill behind label
Active:     accent.solid dot, text-primary label
            + accent.subtle background tint on the 44pt strip

Size: 32pt wide, 28pt tall
Indentation: 4pt from repo item (visually nested)
```

### 5.5 Worktree Status Indicators

Small colored dots on worktree items communicate git state:

| Status | Indicator | Color |
|--------|-----------|-------|
| Clean | No dot | — |
| Has uncommitted changes | Filled dot (4pt) | `warning` (amber) |
| Has staged changes ready to commit | Half-filled dot | `success` (sage) |
| Ahead of remote | Up arrow (tiny, 6pt) | `info` (blue) |
| Behind remote | Down arrow (tiny, 6pt) | `warning` (amber) |
| Merge conflict | Exclamation dot | `error` (rose) |

### 5.6 Add Repository (+) Button

At the bottom of the rail:

```
Default:    text-tertiary (+) icon, 16pt, centered in 32×32 area
Hover:      bg-3 circle, text-secondary
Click:      Opens "Add Repository" sheet
```

### 5.7 Add Repository / Worktree — Simplified Flow

**Current problem**: The workspace creation sheet has too many options and a complex multi-step flow.

**New principle**: Power users use the terminal. The UI should handle the 80% case beautifully.

#### Add Repository

```
┌─────────────────────────────────────┐
│  Add Repository                  ×  │
│                                     │
│  [  Drop a folder here or browse  ] │
│                                     │
│  Recent:                            │
│    ~/Code/api-server                │
│    ~/Code/frontend                  │
│    ~/Code/shared-lib                │
│                                     │
│              [Browse...]  [Cancel]  │
└─────────────────────────────────────┘
```

That's it. Drop a folder, browse, or pick a recent one. No git init options, no template selection, no branch configuration. One action: point at a git repo.

#### Add Worktree

```
┌─────────────────────────────────────┐
│  New Worktree                    ×  │
│                                     │
│  Branch:                            │
│  [  branch-name  ▾ ]               │
│                                     │
│  ○ Existing branch                  │
│  ○ New branch (from current)        │
│                                     │
│              [Create]   [Cancel]    │
└─────────────────────────────────────┘
```

Two options. Pick an existing branch or type a new one. That's it. The worktree path is auto-generated based on repo conventions. Advanced users who want custom paths use `git worktree add` in a terminal.

### 5.8 Repo Rail Reordering

Repos and worktrees can be reordered via drag-and-drop within the rail:

```
Drag initiation:  Long-press (200ms) on repo/worktree item
Drag preview:     The item lifts with shadow-md, scale 1.1
Drop zones:       Between other items (shown with accent.solid 2pt horizontal line)
Animation:        Items shift apart with 100ms spring to make room
Drop:             Item settles into new position with signature spring
```

Repos can also be removed via right-click context menu: "Remove from Devys" (doesn't delete the repo, just removes it from the rail).

---

## Part 6: Content Sidebar — Two-Tab Design

### 6.1 Structure

The content sidebar sits between the repo rail and the main content area. It has two tabs at the top:

```
┌──────────────────────────┐
│  [Files & Diffs] [Agents]│   ← Segmented control
├──────────────────────────┤
│                          │
│  (tab content)           │
│                          │
└──────────────────────────┘
```

**Segmented control**: A `DevysSegmentedControl` with two options. Active segment has `accent.muted` background + `text-primary`. Inactive has transparent background + `text-secondary`. Transition: 150ms spring, the active indicator slides.

### 6.2 Tab 1: Files & Diffs

This tab has two collapsible sections:

#### Files Section

**Section header**: "Files" with file count badge, collapse chevron

**File tree design** (replacing tree characters):

```
▶ Sources                          │
  ▼ Views                          │
    ▼ Components                   │
    │  Button.swift          ●     │  ← amber dot = modified
    │  Toggle.swift                │  ← no dot = clean
    │  TextField.swift       ●     │
    ▶ Layouts                      │
  ▼ Models                         │
    │  User.swift            ◕     │  ← half-filled = staged
    │  Settings.swift        +     │  ← green + = new file
```

**File tree principles:**
- Indentation: 16pt per level
- Connector lines: subtle vertical `Path` lines in `border-subtle`, connecting parent to children
- No tree characters (no `|`, `+---`, etc.)
- Disclosure triangles: `chevron.right` / `chevron.down`, 9pt, `text-tertiary`
- Folder names: 13pt medium weight, proportional font
- File names: 13pt regular weight, proportional font
- File extensions: hidden by default, shown in `text-tertiary` suffix on hover
- Folder open/close: 150ms height animation with signature spring

**Git status indicators on files** (replacing U, M, A, D, etc.):

| Git Status | Indicator | Visual |
|-----------|-----------|--------|
| Untracked (new) | `+` | `success` color, 10pt bold |
| Modified | `●` (filled dot, 6pt) | `warning` color (amber) |
| Staged | `◕` (half-filled dot) | `success` color (sage) |
| Deleted | `−` | `error` color (rose) |
| Renamed | `→` | `info` color (blue) |
| Conflict | `!` | `error` color (rose), with error.subtle background tint on the row |
| Ignored | dimmed | `text-disabled`, 50% opacity on entire row |

These are small, color-coded symbols that communicate status instantly without requiring git literacy. The hover tooltip spells it out: "Modified — unstaged changes".

**File row interactions:**
- Click: opens file in preview tab (single-click = preview, double-click = permanent)
- Hover: `bg-4` background, action menu `•••` appears at right edge (100ms fade)
- Right-click: context menu (Open, Open to Side, Copy Path, Reveal in Finder, Stage, Unstage, Discard Changes)
- Drag: files can be dragged to the tab bar or content area to open in specific panes

#### Diffs Section

**Section header**: "Changes" with count badge (number of changed files), collapse chevron

```
▼ Staged (3)
    auth.swift               +12 −3
    config.swift             +1  −0
    README.md                +25 −10

▼ Unstaged (2)
    ContentView.swift        +45 −22
    Theme.swift              +3  −1
```

**Diff row design:**
- File name: 13pt regular, `text-primary`
- Change stats: `+N` in `success`, `-N` in `error`, 10pt medium, right-aligned
- Status dot: same git status indicators as file tree
- Click: opens diff view in a tab
- Hover: `bg-4` background + action buttons fade in (Stage/Unstage, Discard)

**Inline actions on hover:**
- Staged file hover: [Unstage] ghost button at right edge
- Unstaged file hover: [Stage] [Discard] ghost buttons at right edge
- These are small (20pt height) ghost buttons with `text-secondary`

**Commit area** (at the bottom of the Diffs section when staged files exist):

```
┌──────────────────────────────┐
│  [Commit message...        ] │   ← text field, auto-grows to 3 lines
│                              │
│  [Commit ⌘⏎]                │   ← primary button, accent.solid
└──────────────────────────────┘
```

The commit area slides in with 150ms spring when staged files count > 0, slides out when count = 0.

### 6.3 Tab 2: Agents & Workflows

This tab has two sections:

#### Agents Section

**Section header**: "Agents" with running agent count badge

```
▼ Running (3)
    ● API Refactor              Working     │  ← coral dot + status chip
    ● Frontend Tests            Waiting     │  ← teal dot + warning chip
    ● Docs Update               Thinking    │  ← violet dot + animated ellipsis

▼ Recent
    ○ Auth Migration            Complete    │  ← dimmed, no pulse
    ○ Bug Fix #234              Complete    │
    ○ CSS Cleanup               Error       │  ← error chip
```

**Agent row design** (`DevysAgentRow`):
- Identity color dot: 8pt, left edge, with pulse animation for running agents
- Agent name: 13pt medium, `text-primary` (running) or `text-secondary` (recent)
- Status chip: `DevysChip` with semantic color background
  - Running/Thinking: `success.subtle` bg, `success` text, animated ellipsis
  - Working: `success.subtle` bg, `success` text, with file name context
  - Waiting: `warning.subtle` bg, `warning` text
  - Complete: `bg-3` bg, `text-tertiary` text, checkmark
  - Error: `error.subtle` bg, `error` text

**Agent row interactions:**
- Click: jumps to the agent's tab. If no tab exists, one is created.
- Right-click: context menu (Jump to Tab, Rename, Restart, Stop, Copy Last Output)
- Hover: `bg-4` background + Rename and Stop actions fade in at right edge

#### Workflows Section (Stubbed)

```
┌──────────────────────────────┐
│                              │
│     [sparkles icon, 24pt]    │
│                              │
│   Workflows coming soon      │
│                              │
│   Multi-step automated       │
│   agent pipelines            │
│                              │
└──────────────────────────────┘
```

A `DevysEmptyState` component with a subtle illustration. This section is a placeholder for the AgentFlows engine. It communicates the future without being empty or broken.

### 6.4 Sidebar Collapse

The entire sidebar (rail + content) can collapse:

**⌘\\** toggles sidebar visibility

```
Collapse animation:
  - Content sidebar width animates to 0 (signature spring)
  - Repo rail remains visible at 44pt
  - Main content expands to fill

Full collapse (double-click rail toggle or ⌘⇧\\):
  - Both rail and sidebar animate to 0
  - Main content gets the full window width

Expand:
  - Reverse animation
  - Content sidebar returns to its last width
  - Items fade in as width exceeds ~80pt (prevents text clipping during animation)
```

---

## Part 7: Git UX — User-Friendly Operations

### 7.1 Principles

Git is powerful but intimidating. Our principle: **the UI handles the common path beautifully; the terminal handles everything else.** We don't need to expose every git option — we need to make stage/commit/push/pull feel effortless.

### 7.2 Status Indicators (Replacing U, M, A, D Letters)

Throughout the app — in file trees, diff lists, tab titles, and status displays — we use visual indicators instead of git terminology:

| Traditional | Our Indicator | Visual | Tooltip |
|------------|--------------|--------|---------|
| `U` (untracked) | Green `+` | Small green plus | "New file — not yet tracked by git" |
| `M` (modified) | Amber `●` | Filled amber dot | "Modified — has unsaved changes" |
| `A` (added/staged) | Sage `◕` | Half-filled sage dot | "Staged — ready to commit" |
| `D` (deleted) | Rose `−` | Small rose minus | "Deleted" |
| `R` (renamed) | Blue `→` | Small blue arrow | "Renamed" |
| `C` (conflict) | Rose `!` | Exclamation with rose tint | "Conflict — needs manual resolution" |
| `??` (ignored) | Dimmed row | Reduced opacity | "Ignored by .gitignore" |

These indicators appear in:
1. File tree rows (right-aligned)
2. Diff list rows (left of file name)
3. Tab titles (after file name for dirty editors)
4. Repo rail worktree items (aggregate status)
5. Status capsule (summary counts)

### 7.3 Stage / Unstage / Discard

All three operations are accessible without opening a modal or navigating away:

**From the file tree:**
- Right-click any modified file → Stage / Unstage / Discard Changes
- Hover → action buttons appear at right edge

**From the diffs sidebar section:**
- Hover on file row → Stage / Unstage / Discard ghost buttons
- Click the section header action: "Stage All" / "Unstage All"

**From the diff view tab:**
- Hunk-level stage/unstage buttons appear on hover over each diff hunk
- "Stage File" / "Unstage File" button in the diff toolbar

**Discard changes confirmation:**
Discarding is destructive. A small popover appears:
```
"Discard changes to [filename]? This can't be undone."
[Discard] (danger style)  [Cancel] (ghost style)
```

### 7.4 Commit Flow

**Inline commit** (sidebar):
- The commit message field is always visible at the bottom of the "Changes" section when staged files exist
- Type a message, press `⌘⏎` to commit
- The message field clears, staged files disappear from the list with a 200ms slide-out animation
- A brief success toast: "Committed: [first line of message]" with a checkmark

**Full commit sheet** (for longer messages, co-authors, etc.):
- Accessible via `⌘⇧C` or clicking "Expand" on the inline commit field
- A sheet slides up with:
  - Subject line input (50-char soft limit, amber warning at 72)
  - Body textarea (optional, with markdown preview)
  - Staged files list (read-only summary)
  - [Commit] primary button + [Cancel]

### 7.5 Push / Pull / Fetch

These are in the status capsule menu and command palette, not permanent chrome:

**Status capsule hover** expands to show:
```
┌─────────────────────────────────────────────┐
│  main  ↑3 ↓1  [Pull] [Push] [Fetch]        │
└─────────────────────────────────────────────┘
```

- `↑3` = 3 commits ahead (info color)
- `↓1` = 1 commit behind (warning color)
- Buttons are ghost style, appear on hover

**Push/pull progress**: A thin accent-colored progress bar at the bottom edge of the status capsule, left-to-right animation.

### 7.6 Branch Switching

Branch switching lives in the command palette and the titlebar breadcrumb:

- Click the branch name in the titlebar breadcrumb → opens branch picker popover
- `⌘K` then type `>branch` or `>checkout` → command palette shows branch list
- The branch picker is a searchable list with:
  - Current branch highlighted with accent dot
  - Recent branches at top
  - Remote branches in a separate section
  - "Create new branch..." option at bottom

---

## Part 8: Status Capsule

### 8.1 Design

The status capsule replaces the full-width status bar. It's a floating pill at the bottom-center of the window.

```
Default:    ┌───────────────────────┐
            │  ⎇ main   ↑2  ✓      │
            └───────────────────────┘

Expanded:   ┌────────────────────────────────────────┐
(on hover)  │  ⎇ main   ↑2 ↓0   Last: "Fix auth"   │
            │  [Fetch] [Pull] [Push]  ·  2 agents    │
            └────────────────────────────────────────┘
```

**Default state:**
- Auto-width, min 140pt
- `bg-3` background, `radius-full`
- 80% opacity (semi-transparent)
- Branch icon + name + ahead/behind counts + overall status icon (✓, ⚠, ✗)
- 8pt vertical padding, 14pt horizontal padding
- `shadow-sm`

**Hover state:**
- 100% opacity
- Expands width to show additional info (signature spring)
- Additional row with action buttons and agent count
- `shadow-md`

**Auto-hide:**
- Fades out after 3s of no interaction (300ms fade)
- Reappears on: hover over bottom 40pt of window, git status change, agent completion/error
- Reappear animation: fade in + slide up 4pt (200ms)

### 8.2 Agent Status in Capsule

When agents are running, the capsule shows a summary:

```
┌──────────────────────────────────────┐
│  ⎇ main  ↑2  ·  ●●● 3 agents       │
└──────────────────────────────────────┘
                   ↑ dots in agent identity colors
```

When an agent completes or errors:
- The capsule briefly pulses in the agent's identity color (300ms)
- The capsule auto-shows if it was hidden
- A brief text appears: "Agent complete: [name]" or "Agent error: [name]"
- Returns to normal after 3s

---

## Part 9: Command Palette

### 9.1 Design (Refined from Phase 2 Plan)

The command palette is the power user's home base. `⌘K` to open.

**Appearance:**
- Centered in window, 520pt wide, max 480pt tall
- `radius-xl` corners, `bg-3` background, `.hudWindow` material
- `shadow-lg` elevation
- Entry: scale 95%→100% + fade in (signature spring, 180ms)
- Exit: scale→97% + fade out (120ms ease-out)

**Home state (no query):**

```
┌──────────────────────────────────────────────┐
│  [🔍] Search files, commands, agents...      │
├──────────────────────────────────────────────┤
│                                              │
│  Running Agents                              │
│    ● API Refactor          Working           │
│    ● Frontend              Waiting           │
│                                              │
│  Recent Files                                │
│    ContentView.swift       Views/Window      │
│    Theme.swift             Models            │
│    Package.swift           root              │
│                                              │
│  Quick Actions                               │
│    ◎ New Terminal                    ⌘T       │
│    ◎ New Agent                      ⌘⇧A      │
│    ◎ Toggle Sidebar                 ⌘\       │
│    ◎ Open Settings                  ⌘,       │
│                                              │
└──────────────────────────────────────────────┘
```

**Query state:**
- Results grouped by category: Files, Commands, Agents, Git
- Each result: icon + title + subtitle + keyboard shortcut
- Active result: `accent.muted` background + 2pt `accent.solid` left border
- Navigate with ↑↓, confirm with Enter, close with Escape

### 9.2 Command Prefix System

| Prefix | Category | Example |
|--------|----------|---------|
| (none) | Files + recent | `ContentView` |
| `>` | Commands | `>theme dark` |
| `@` | Agents | `@api refactor` |
| `#` | Git branches | `#feature/auth` |
| `:` | Go to line | `:42` |

---

## Part 10: Complete Component Inventory

Every component in `Packages/UI` that the app needs. Components are organized by dependency wave — later waves depend on earlier ones.

### Wave 0: Design Tokens (Not Components, But Foundation)

| Token Set | File | Covers |
|-----------|------|--------|
| `DevysColors` | `DevysColors.swift` | Warm neutral palette, text, border, semantic, accent variants |
| `DevysTypography` | `DevysTypography.swift` | `.ui` (proportional) + `.code` (monospace) scales |
| `DevysSpacing` | `DevysSpacing.swift` | 4px scale, semantic aliases, radii (xs–full), icon sizes |
| `DevysAnimation` | `DevysAnimation.swift` | Signature spring, hover/press/focus/status timings |
| `DevysShadow` | `DevysShadow.swift` | sm/md/lg/xl shadow presets |
| `DevysDensity` | `DevysDensity.swift` | `.comfortable` / `.compact` with all size multipliers |
| `AgentColor` | `AgentColor.swift` | 8-color agent palette with solid/muted/subtle/text variants |
| `ChatTokens` | `ChatTokens.swift` | Agent chat-specific tokens (bubble, timestamp, code block) |
| `DevysTheme` | (in `DevysColors.swift`) | Unified theme struct resolving all tokens by mode + accent |

### Wave 1: Atomic Components (No Internal Dependencies)

| Component | File | Purpose | States |
|-----------|------|---------|--------|
| `DevysButton` | `DevysButton.swift` | Universal button | primary, secondary, ghost, danger × default, hover, press, disabled, loading |
| `DevysIcon` | `DevysIcon.swift` | SF Symbol wrapper | Density-aware sizing, color variants |
| `DevysTextField` | `DevysTextField.swift` | Text input | default, focused, error, disabled. Focus ring in accent |
| `DevysSearchField` | `DevysSearchField.swift` | Search input | Leading magnifier, trailing clear, same states as TextField |
| `DevysToggle` | `DevysToggle.swift` | On/off switch | macOS-style, accent track when on, spring animation |
| `DevysChip` | `DevysChip.swift` | Status/metadata chip | Variants: status, count, tag, shortcut. Semantic colors |
| `DevysDivider` | `DevysDivider.swift` | Line separator | horizontal, vertical. Uses border-subtle |
| `DevysKeyboardShortcut` | `DevysKeyboardShortcut.swift` | Shortcut badge | `[⌘K]` style, monospace, bg-3, radius-xs |
| `DevysStatusDot` | `StatusIndicator.swift` | Colored status dot | Static, pulse (running), glow-then-fade (complete), shake (error) |
| `DevysGitStatusIndicator` | **NEW** | Git file status symbol | `+`, `●`, `◕`, `−`, `→`, `!` in semantic colors |
| `DevysAgentIdentityStripe` | **NEW** | 2pt colored stripe | For tab pills and other surfaces needing agent color edge |

### Wave 2: Container Components (Depend on Wave 1)

| Component | File | Purpose | Notes |
|-----------|------|---------|-------|
| `DevysListRow` | `DevysListRow.swift` | Standard list row | Leading icon + title + subtitle + trailing accessory. Hover state |
| `DevysSectionHeader` | `DevysSectionHeader.swift` | Section title | Title + count badge + disclosure chevron + optional trailing action |
| `DevysEmptyState` | `DevysEmptyState.swift` | Centered empty state | Icon + title + description + optional CTA buttons |
| `DevysPanel` | `DevysPanel.swift` | Panel scaffold | Background + optional header toolbar + content + optional footer |
| `DevysToolbar` | **NEW** | Horizontal toolbar | Leading/center/trailing slots, standard height |
| `DevysPopover` | **NEW** | Floating popover | Shadow-md, radius-lg, arrow, auto-positioning |
| `DevysSheet` | **NEW** | Modal sheet | Title bar + content + action buttons. Shadow-lg. Standard sizing |
| `DevysSegmentedControl` | **NEW** | 2-4 option selector | Sliding active indicator with spring animation |
| `DevysTooltip` | **NEW** | Hover tooltip | Shadow-sm, radius-sm, delay 600ms, max 240pt wide |
| `DevysContextMenu` | **NEW** | Right-click menu | Consistent styling for all context menus |

### Wave 3: Feature-Adjacent Components (Depend on Wave 1 + 2)

| Component | File | Purpose | Notes |
|-----------|------|---------|-------|
| `DevysTabPill` | **NEW** (replaces `TabItemView`) | Tab in tab bar | Full redesign: pill shape, identity stripe, dirty dot, hover close, preview italic, all states from §3.2 |
| `DevysTabBar` | **NEW** (replaces `TabBarView`) | Tab bar container | Scroll, fade gradients, overflow dropdown, (+) button, drop zones |
| `DevysFileRow` | **NEW** (replaces `FileTreeRow`) | File tree row | Indentation + connector lines + name + git status dot + hover actions |
| `DevysFolderRow` | **NEW** | Folder in file tree | Disclosure triangle + name + medium weight + animate open/close |
| `DevysAgentRow` | **NEW** | Agent sidebar entry | Identity dot + name + status chip + hover actions |
| `DevysDiffRow` | **NEW** | Diff file entry | File name + git status + change stats + hover stage/unstage |
| `DevysRepoItem` | **NEW** | Repo in rail | Two-letter avatar, active indicator bar |
| `DevysWorktreeItem` | **NEW** | Worktree in rail | Branch dot + name + status indicator |
| `DevysNotificationToast` | **NEW** | Ephemeral toast | Auto-dismiss, accent or agent-color border, slide-up entry |
| `DevysBreadcrumb` | **NEW** | Titlebar breadcrumb | Repo / branch path, clickable segments |
| `DevysFABMenu` | **NEW** | (+) creation menu | Popover with categorized actions, keyboard navigable |
| `DevysDropZoneOverlay` | **NEW** | Drag-drop zone indicator | Semi-transparent overlay with dashed border for split creation |
| `DevysInsertionIndicator` | **NEW** | Tab drag insertion line | 2pt accent.solid vertical line between tabs |
| `DevysDragPreview` | **NEW** (replaces `TabDragPreview`) | Drag preview pill | Lifted tab with shadow-lg, follows cursor |
| `DevysConnectorLine` | **NEW** | File tree connector | Subtle vertical/horizontal lines connecting parent to children |
| `DevysInlineCommit` | **NEW** | Commit message area | Auto-growing text field + commit button, slides in/out |
| `DevysBranchPicker` | **NEW** | Branch selection | Searchable list, current branch highlight, create new option |
| `DevysSavePromptPopover` | **NEW** | Dirty file prompt | "Save changes?" with Save/Don't Save/Cancel |

### Wave 4: Composed Surfaces (Depend on Wave 1 + 2 + 3)

| Component | File | Purpose | Notes |
|-----------|------|---------|-------|
| `DevysCommandPalette` | **NEW** | The command palette | Search + grouped results + home state + keyboard nav + signature animation |
| `DevysStatusCapsule` | **NEW** | Floating status pill | Branch + sync + agents. Expand on hover, auto-hide, agent pulse |
| `DevysSidebarSection` | **NEW** | Collapsible sidebar group | Animated disclosure, count badge, consistent styling |
| `DevysCommandPaletteRow` | **NEW** | Result row in palette | Icon + title + subtitle + shortcut. Active state with accent left border |

### Summary: Component Count

| Wave | Existing (Update) | New | Total |
|------|-------------------|-----|-------|
| 0 (Tokens) | 9 | 0 | 9 |
| 1 (Atomic) | 8 | 3 | 11 |
| 2 (Container) | 4 | 6 | 10 |
| 3 (Feature) | 0 | 18 | 18 |
| 4 (Composed) | 0 | 4 | 4 |
| **Total** | **21** | **31** | **52** |

---

## Part 11: Micro-Animation Specification

Every animation in the app uses one of these presets. No ad-hoc timings.

### 11.1 The Signature Spring

```swift
static let devysSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
```

**Used for:** command palette open/close, split creation/destruction, sidebar expand/collapse, modal presentation, tab reordering, popover appearance, FAB menu, segmented control indicator.

### 11.2 Micro-Interaction Timings

```swift
static let hover     = Animation.easeOut(duration: 0.10)    // 100ms — hover background appear
static let press     = Animation.easeOut(duration: 0.06)    // 60ms  — button press scale
static let focus     = Animation.easeInOut(duration: 0.15)  // 150ms — focus ring, divider appear
static let status    = Animation.easeInOut(duration: 0.30)  // 300ms — status color change, glow
static let collapse  = Animation.easeInOut(duration: 0.15)  // 150ms — section collapse/expand
static let tab       = Animation.spring(response: 0.25, dampingFraction: 0.85) // tab slide/close
```

### 11.3 Status Animations

| Animation | Trigger | Spec |
|-----------|---------|------|
| **Agent running pulse** | Agent starts working | Identity dot opacity 60%→100%, 2s cycle, ease-in-out, continuous |
| **Agent complete glow** | Agent finishes | Dot glow radiates outward (scale 1→1.5, opacity 1→0), 300ms, one-shot |
| **Agent error shake** | Agent errors | Dot shifts 2pt left, 2pt right, center. 300ms total, one-shot |
| **Agent waiting pulse** | Agent needs approval | Identity dot opacity 70%→100%, 3s cycle (slower than running) |
| **Dirty dot appear** | File becomes dirty | Dot scales from 0→1.3→1.0, 300ms spring |
| **File save sweep** | File saves | Subtle accent.subtle sweep left→right across tab title, 200ms, one-shot |
| **Task progress bar** | Build/task running | 1pt accent line at pane bottom edge, indeterminate left→right |
| **Toast enter** | Notification appears | Slide up 16pt + fade in, signature spring |
| **Toast exit** | Auto-dismiss | Fade out + slide down 8pt, 200ms ease-out |
| **Status capsule pulse** | Agent complete/error | Capsule border briefly flashes agent identity color, 300ms |

### 11.4 Hover State Inventory

Every interactive element must have a hover state. This is the complete list:

| Element | Hover Effect | Timing |
|---------|-------------|--------|
| Button (all styles) | Background fill shift per style spec | 100ms ease-out |
| Tab pill (inactive) | bg-3 fill appears, close button fades in | 100ms |
| Tab pill (active) | Close button brightens | 100ms |
| Sidebar file row | bg-4 fill, action buttons appear at right | 100ms |
| Sidebar agent row | bg-4 fill, action buttons appear at right | 100ms |
| Sidebar diff row | bg-4 fill, stage/unstage buttons appear | 100ms |
| Split divider | 2pt border-default line appears | 150ms |
| Repo rail item | bg-4 square, text-primary text | 100ms |
| Worktree rail item | bg-3 pill, text-secondary text | 100ms |
| Status capsule | Opacity 80%→100%, expands to show details | 200ms |
| Toolbar button | bg-3 circle behind icon | 100ms |
| List row (any) | bg-4 background | 100ms |
| Command palette row | accent.subtle background | 100ms |
| Chip (clickable) | Slightly brighter background | 100ms |
| (+) FAB | accent.hover fill, scale 1.05 | 100ms |
| Breadcrumb segment | text-primary text, underline appears | 100ms |
| Disclosure triangle | text-secondary (from text-tertiary) | 100ms |
| File tree connector line | Slightly brighter (border-default from border-subtle) | 100ms |

### 11.5 Press State Inventory

| Element | Press Effect | Timing |
|---------|-------------|--------|
| Button (primary) | Darken 10%, scale 0.98 | 60ms |
| Button (secondary) | bg-4 fill, scale 0.98 | 60ms |
| Button (ghost) | bg-4 fill, scale 0.98 | 60ms |
| Tab pill | Scale 0.97 (for drag initiation detection) | 60ms |
| (+) FAB | accent.solid darkened, scale 0.95 | 60ms |
| List row (clickable) | bg-4 background (slightly darker than hover) | 60ms |
| Toolbar icon | Scale 0.9 | 60ms |

---

## Part 12: Density Mode Impact

All spatial values adjust based on density. The system scales, the design doesn't change.

| Token | Comfortable | Compact | Usage |
|-------|------------|---------|-------|
| Tab height | 34pt | 28pt | Tab bar |
| Sidebar row height | 32pt | 24pt | All sidebar lists |
| Button height | 34pt | 28pt | All buttons |
| List row height | 32pt | 24pt | All lists |
| Section padding | 16pt | 12pt | Panel/section insets |
| Icon size | 18pt | 14pt | Standard icons |
| Base UI font | 13pt | 12pt | Body text |
| Rail width | 44pt | 36pt | Repo rail |
| Repo item size | 32×32pt | 26×26pt | Rail items |
| Toolbar height | 28pt | 24pt | Panel toolbars |
| Status capsule padding | 8v×14h | 6v×10h | Status pill |

Density is a single environment value (`@Environment(\.devysDensity)`) that all components read. Switching density is instant — no restart needed.

---

## Part 13: Accessibility

### 13.1 Keyboard Navigation

Every surface is fully keyboard-navigable:

| Context | Keys | Action |
|---------|------|--------|
| Tab bar | `⌘1-9` | Select tab by position |
| Tab bar | `⌃Tab` / `⌃⇧Tab` | Next/previous tab |
| Panes | `⌘⌥←→↑↓` | Navigate focus between panes |
| Sidebar | `↑↓` | Navigate items |
| Sidebar | `Space` / `Enter` | Open/select item |
| Sidebar | `←→` | Collapse/expand folder |
| Command palette | `↑↓` | Navigate results |
| Command palette | `Enter` | Confirm selection |
| Command palette | `Escape` | Close |
| FAB menu | `↑↓` | Navigate options |
| FAB menu | `Enter` | Confirm |
| FAB menu | `Escape` | Close |

### 13.2 VoiceOver

- All components provide `accessibilityLabel` and `accessibilityValue`
- Tab pills: "[Title], [type] tab, [status]" (e.g., "ContentView, editor tab, modified")
- Agent rows: "[Name], agent, [status]" (e.g., "API Refactor, agent, running")
- Git status indicators: Spelled out ("Modified, unstaged changes")
- Status capsule: "Branch main, 2 commits ahead, 3 agents running"

### 13.3 Reduced Motion

When `@Environment(\.accessibilityReduceMotion)` is true:
- All springs become instant transitions (0ms)
- Pulses become static indicators (solid dot instead of pulsing)
- Scale effects are removed
- Fade transitions remain but at 100ms max

---

## Part 14: Implementation Phases

### Phase A: Token Foundation (Week 1)

Update all design tokens to match this spec:
1. Warm neutral color palette (dark + light)
2. Dual typography system (proportional UI + monospace code)
3. Revised spacing with breathing rule
4. Corner radii (xs–full)
5. Shadow presets (sm–xl)
6. Signature spring + micro-interaction timings
7. Density mode infrastructure
8. Agent color palette with 4 variants each

### Phase B: Wave 1 Atomic Components (Week 1-2)

Build or update the 11 atomic components. Each gets:
- All states (default, hover, press, focus, disabled)
- Density support
- Dark/light mode support
- Accessibility labels
- SwiftUI previews showing all variants

### Phase C: Wave 2 Container Components (Week 2)

Build the 10 container components. These compose Wave 1 atoms.

### Phase D: Wave 3 Feature Components (Week 2-3)

Build the 18 feature-adjacent components. This is the largest wave and includes:
- The redesigned tab pill and tab bar (critical path)
- File tree with connector lines and git status
- Agent rows with identity colors
- All drag-drop components

### Phase E: Wave 4 Composed Surfaces (Week 3)

Build the 4 composed surfaces:
- Command palette
- Status capsule
- Sidebar sections
- Command palette rows

### Phase F: Shell Migration (Week 3-4)

Wire everything together:
1. Replace titlebar buttons with (+) FAB
2. Replace full-width status bar with floating capsule
3. Replace single sidebar with two-tab sidebar
4. Replace file tree with new file rows + connector lines
5. Replace tab bar with redesigned tab pills
6. Replace git status letters with visual indicators
7. Add all hover states
8. Add all animations
9. Migrate split dividers to invisible-default pattern
10. Update repo rail with new items

### Phase G: Polish & Enforcement (Week 4)

1. Add lint rules for raw styling values
2. Build design system gallery (debug build)
3. Verify all states in both modes (dark/light) at both densities
4. Accessibility audit
5. Performance audit (ensure animations hit 120fps)

---

## Appendix A: What Moves to Command Palette

These items are currently permanent chrome but should move to `⌘K`:

| Item | Current Location | Reason |
|------|-----------------|--------|
| Branch switching | Status bar | Used ~2× per session |
| Theme switching | Settings tab | Used ~1× per month |
| Layout presets | Not implemented | Infrequent |
| Font size | Settings | Infrequent |
| Density toggle | Settings | Infrequent |
| Agent model selection | Harness picker sheet | Can be a command |
| Port management | Sidebar section | Rarely navigated directly |
| Run profile config | Status bar gear icon | Infrequent |
| Git fetch/pull/push | Status bar menu | Better in capsule hover + command palette |

## Appendix B: What Stays as Permanent Chrome

| Item | Location | Reason |
|------|----------|--------|
| Repo/worktree rail | Left edge, 44pt | Constant reference point for multi-project workflow |
| Content sidebar | Left, 260pt | Files and agents are navigated constantly |
| Tab strip | Top of each pane | Primary navigation within a pane |
| (+) FAB | Titlebar trailing | Creation is frequent enough for one button |
| Status capsule | Bottom center, floating | Ambient awareness of git state |
| Sidebar toggle | Titlebar leading | Frequently used |
| Breadcrumb | Titlebar center | Context awareness |

## Appendix C: File-to-Component Mapping

For every existing view file that needs migration, which new component(s) replace it:

| Existing File | Replaced By |
|--------------|-------------|
| `TabItemView.swift` | `DevysTabPill` |
| `TabBarView.swift` | `DevysTabBar` |
| `TabDragPreview.swift` | `DevysDragPreview` |
| `FileTreeRow.swift` | `DevysFileRow` + `DevysFolderRow` + `DevysConnectorLine` |
| `StatusBar.swift` | `DevysStatusCapsule` |
| `TitlebarToolbar.swift` (launcher buttons) | `DevysFABMenu` + `DevysBreadcrumb` |
| `FeatureRail.swift` | `DevysSegmentedControl` (sidebar tabs) |
| `UnifiedWorkspaceSidebar.swift` | `DevysSidebarSection` × 2 tabs |
| `SidebarContentView.swift` | Content sidebar with Files/Diffs + Agents/Workflows |
| `WorkspaceCreationSheet.swift` | Simplified `DevysSheet` (Add Repo + Add Worktree) |
| `AgentHarnessPickerSheet.swift` | Integrated into `DevysFABMenu` agent options |
| `HunkActionBar.swift` | Updated with `DevysButton` ghost style |
| `BranchPicker.swift` | `DevysBranchPicker` |
| `GitSidebarView.swift` | Diffs section of content sidebar |
| `CommitSheet.swift` | `DevysInlineCommit` + expanded `DevysSheet` variant |
| `WorkspaceSidebarRail.swift` | Repo rail with `DevysRepoItem` + `DevysWorktreeItem` |

## Appendix D: Design Decision Log

| Decision | Rationale |
|----------|-----------|
| (+) FAB instead of 4 buttons | Scales with new agent types, reduces chrome, single mental model |
| Two-tab sidebar instead of 4 sections | Separates "what's in the repo" from "what's running"; reduces scroll |
| Visual git indicators instead of letters | Accessible to non-git-experts, faster pattern recognition |
| Floating capsule instead of status bar | Reclaims 24pt of vertical space, auto-hides when not needed |
| Invisible split dividers | Reduces visual noise, tone shift is sufficient, dividers appear on hover |
| Repo rail as separate zone | Multi-project switching is high-frequency and deserves dedicated space |
| Simplified worktree creation | Power users use terminal; UI handles 80% case |
| Preview tabs with italic titles | VS Code pattern is well-understood, italic is subtle but clear signal |
| Agent identity colors on tab stripes | Color memory is faster than text reading for distinguishing agents |
| Breathing rule for spacing | Prevents the "Bloomberg terminal" feel without sacrificing density |
