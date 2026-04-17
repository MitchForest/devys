# Devys UI/UX Reference — Dia-Modeled Design System

Updated: 2026-04-15

## Purpose

This document specifies the canonical Devys visual design system, modeled on the Dia browser's design language: quiet confidence, layered surfaces, one consistent radius, monochrome warmth with optional accent tinting.

It pairs with:

- `architecture.md` for architecture and ownership rules
- `../plan/implementation-plan.md` for migration status
- `../adrs/0003-ui-rulebook.md` for the codified rules

The goal: someone opens Devys for the first time and thinks "this feels expensive." Not because it's flashy, but because every detail is consistent.

---

## Part 1: Design Principles

### 1.1 The Three Rules

**One radius.** Every rounded element in the app uses the same corner radius (12pt, continuous curvature). Cards, buttons, inputs, tabs, dropdowns, modals, popovers — all 12pt. The only exceptions are micro badges (4pt) and circles (avatars, status dots). This single decision creates more visual coherence than any other.

**Layered surfaces.** The app has exactly three depth levels: base, card, overlay. The base layer is the window background — the sidebar, rail, and gaps between panes all live here. Cards (each split pane) sit elevated on top of the base with rounded corners and subtle shadows. Overlays (modals, popovers, command palette) float above everything with backdrop blur. This is the "desk with papers on it" metaphor.

**Monochrome warmth.** The default theme is monochrome — warm off-blacks and off-whites with no accent color. A set of 10 theme colors is available that subtly tint the UI. The accent is never aggressive — it appears on toggles, active states, links, and as a gentle gradient wash at the top of focused content cards. The app should feel calm at rest, responsive in motion.

### 1.2 What Dia Gets Right (And We Steal)

| Dia Pattern | Devys Translation |
|-------------|-------------------|
| Unified base layer behind sidebar + splits | Rail + sidebar + pane gaps all share `base` surface |
| Split panes as elevated rounded cards | Each pane is a `card` surface with 12pt radius, 1pt border, subtle shadow |
| Visible gap between splits | 6pt gap filled with `base` surface color |
| One border radius everywhere | 12pt `.continuous` for all interactive/container elements |
| Monochrome default with theme color picker | Default accent is neutral gray; 10 theme colors available |
| Theme color as subtle gradient tint | Focused card gets a faint accent gradient at top edge |
| Dark mode = warm dark gray, not black | `#121110` base, not `#000000` |
| Light mode = warm cream, not white | `#F5F3F0` base, not `#FFFFFF` |
| Minimal button variants | Primary (filled) + Ghost (transparent). That's it. |
| iOS-style toggles with accent | Same |
| Clean sans-serif, not monospace for chrome | SF Pro for all UI chrome, SF Mono for code only |
| Generous spacing, everything breathes | Default to comfortable density with ample padding |

---

## Part 2: Color System

### 2.1 Surface Palette

Three surface levels. That's it.

#### Dark Mode

| Token | Hex | Role |
|-------|-----|------|
| `base` | `#121110` | Window background, sidebar, rail, gaps between panes |
| `card` | `#1C1B19` | Split pane content areas, elevated cards |
| `overlay` | `#252321` | Popovers, dropdowns, command palette, modals |

#### Light Mode

| Token | Hex | Role |
|-------|-----|------|
| `base` | `#F5F3F0` | Window background, sidebar, rail, gaps between panes |
| `card` | `#FFFFFF` | Split pane content areas, elevated cards |
| `overlay` | `#FFFFFF` | Popovers, dropdowns, command palette, modals |

#### Hover/Active States (derived, not separate tokens)

| State | Dark | Light |
|-------|------|-------|
| `hover` | `base` lightened 4% → `#1A1918` | `base` darkened 3% → `#ECEAE6` |
| `active` | `base` lightened 8% → `#222120` | `base` darkened 6% → `#E4E1DC` |
| `cardHover` | `card` lightened 4% → `#242321` | `card` darkened 2% → `#F9F8F6` |

These are computed from the three base surfaces, not independent tokens. Less to remember, impossible to get wrong.

### 2.2 Text Hierarchy

| Token | Dark | Light | Use |
|-------|------|-------|-----|
| `text` | `#EDEDEB` | `#1C1B19` | Primary text — headings, body, labels |
| `textSecondary` | `#9B9990` | `#7A7772` | Secondary text — descriptions, placeholders, metadata |
| `textTertiary` | `#5E5C57` | `#AFACA6` | Tertiary text — disabled items, hints, timestamps |

Three levels. Not four. If you need "disabled" text, use `textTertiary` at 60% opacity.

### 2.3 Borders

| Token | Dark | Light | Use |
|-------|------|-------|-----|
| `border` | `#2A2826` | `#E5E2DD` | Card edges, input borders, dividers — one border color |
| `borderFocus` | accent color at 50% | accent color at 50% | Focus rings on inputs, active card edge highlight |

Two border colors. Not three. The old subtle/strong distinction created ambiguity. One default border, one focus border.

### 2.4 Accent / Theme Colors

The default theme is **monochrome** — no accent color. The app looks great in pure warm gray.

Users can pick from 10 theme colors. Each has a `solid`, `muted` (15% opacity), and `subtle` (6% opacity) variant:

| Name | Hex | Character |
|------|-----|-----------|
| Graphite | `#8B8885` | Default monochrome — neutral gray |
| Blue | `#4A7FD4` | Calm, professional |
| Teal | `#3DBDA7` | Fresh, balanced |
| Green | `#5AAE6B` | Natural, affirming |
| Lime | `#8BBD5A` | Energetic, light |
| Yellow | `#D4B44A` | Warm, focused |
| Orange | `#D48A4A` | Vibrant, creative |
| Red | `#D45C5C` | Intense, alert |
| Pink | `#D46B96` | Playful, soft |
| Violet | `#9B7FD4` | Distinctive, modern |

When an accent is active, it appears in:
- Toggle switch track (on state)
- Active sidebar item indicator (left edge bar)
- Active tab bottom indicator
- Link text
- Primary button fill (replaces dark fill)
- Focus ring on inputs
- Subtle gradient wash at top of focused content card (6% opacity → transparent, 80pt tall)
- Status capsule active state

When no accent is active (Graphite), primary buttons are dark-filled (`text` color with `base` text), and the accent locations above use the `textSecondary` color instead. The app reads as purely monochrome.

### 2.5 Semantic Status Colors

| Token | Hex | Use |
|-------|-----|-----|
| `success` | `#5AAE6B` | Running, complete, staged, connected |
| `warning` | `#D4A54A` | Waiting, modified, behind remote |
| `error` | `#D45C5C` | Failed, conflict, disconnected |
| `info` | `#4A7FD4` | Informational, renamed, ahead of remote |

These are fixed — they don't change with theme color. Each has a `subtle` variant at 10% opacity for background tints.

### 2.6 Agent Identity Colors

Agents still get unique identity colors. The palette is the same 10 theme colors (minus Graphite). An agent's color appears on its tab stripe, sidebar dot, and chat accent. Agent colors are independent of the user's chosen theme color.

---

## Part 3: Corner Radius

### 3.1 The Scale

| Token | Value | Style | Use |
|-------|-------|-------|-----|
| `radius` | 12pt | `.continuous` | **Everything.** Buttons, inputs, cards, panels, tabs, dropdowns, modals, popovers, chips, badges, code blocks, search fields, command palette, sheets. |
| `radiusMicro` | 4pt | `.continuous` | Tiny inline elements only: checkbox squares, inline code spans, progress bar tracks. |
| `radiusFull` | 9999pt | `.continuous` | Circles: status dots, avatars, toggle tracks, the status capsule pill. |

That's it. Three values. When in doubt, use `radius` (12pt).

### 3.2 The Nesting Rule

Inner radius = outer radius − padding.

A card with `radius` (12pt) and 6pt internal padding means elements inside should use `12 − 6 = 6pt` radius. But we don't create a 6pt token — this is a computed value applied contextually. The system provides a helper:

```swift
Spacing.innerRadius(padding: 6) // → 6pt
```

If the padding is ≥ 12pt, inner elements just use `radius` (12pt) again — the nesting doesn't need adjustment at that scale.

### 3.3 Continuous Curvature (Mandatory)

Every `RoundedRectangle` in the app MUST use `style: .continuous`. This produces Apple's squircle — a superellipse with smooth curvature transitions instead of the visible kink where arc meets straight edge.

```swift
// CORRECT
RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)

// WRONG — never do this
RoundedRectangle(cornerRadius: 12)  // defaults to .circular
```

The design system provides `DevysShape` as the standard shape:

```swift
DevysShape()                    // 12pt continuous (default)
DevysShape(.micro)              // 4pt continuous
DevysShape(.full)               // 9999pt continuous (circle)
DevysShape(innerPadding: 6)     // computed inner radius
```

---

## Part 4: Typography

### 4.1 UI Chrome (SF Pro)

| Token | Size | Weight | Use |
|-------|------|--------|-----|
| `display` | 24pt | Bold | Welcome screen hero, empty state titles |
| `title` | 18pt | Semibold | Page titles (Settings, Personalization), modal titles |
| `heading` | 14pt | Semibold | Section headers, sidebar section titles, panel titles |
| `body` | 13pt | Regular | Primary UI text — menus, descriptions, file names, list items |
| `label` | 12pt | Medium | Button labels, tab titles, chip text, nav items |
| `caption` | 11pt | Regular | Timestamps, metadata, secondary descriptions |
| `micro` | 10pt | Medium | Badge counts, keyboard shortcut text |

7 sizes. The key constraint: **never use a size between these stops.** No 15pt, no 16pt, no 9pt. If a design needs something between `body` (13pt) and `heading` (14pt), use `heading`. Rounding up keeps the scale clean.

### 4.2 Code (SF Mono)

| Token | Size | Weight | Use |
|-------|------|--------|-----|
| `Code.base` | 13pt | Regular | Default editor text |
| `Code.sm` | 12pt | Regular | Inline code in chat, terminal compact |
| `Code.lg` | 14pt | Regular | Focused reading mode |
| `Code.gutter` | 11pt | Regular | Line numbers |

4 sizes for code. That's it.

### 4.3 Chat Typography

Chat uses slightly larger type for readability in conversational context:

| Token | Size | Weight | Use |
|-------|------|--------|-----|
| `Chat.body` | 15pt | Regular | Message text |
| `Chat.heading` | 17pt | Semibold | Message section headers |
| `Chat.caption` | 12pt | Regular | Timestamps, metadata |
| `Chat.code` | 14pt | Regular (mono) | Code blocks in chat |

4 sizes for chat.

---

## Part 5: Spacing

### 5.1 Base Scale (4px Grid)

| Token | Value |
|-------|-------|
| `space0` | 0pt |
| `space1` | 4pt |
| `space2` | 8pt |
| `space3` | 12pt |
| `space4` | 16pt |
| `space5` | 20pt |
| `space6` | 24pt |
| `space8` | 32pt |
| `space12` | 48pt |

9 values. Removed `space10` (40pt) and `space16` (64pt) — they were never used in practice.

### 5.2 Semantic Aliases

| Alias | Value | Use |
|-------|-------|-----|
| `tight` | 4pt | Icon-to-label gaps, tight element clusters |
| `normal` | 8pt | Default element gap, standard padding |
| `comfortable` | 12pt | Related groups, card internal padding when nesting matters |
| `relaxed` | 16pt | Section padding, card content padding |
| `spacious` | 24pt | Major section gaps, generous page margins |

### 5.3 The Gap

The gap between split panes is a first-class design token:

```swift
Spacing.paneGap = 6pt  // visible gap between cards, filled with base surface
```

This is the gap that makes the layered surface model work. It's always `base` colored, creating the "desk between papers" effect.

### 5.4 Layout Constants

| Token | Value |
|-------|-------|
| `repoRailWidth` | 48pt |
| `sidebarDefaultWidth` | 260pt |
| `sidebarMinWidth` | 180pt |
| `sidebarMaxWidth` | 400pt |
| `minPaneWidth` | 200pt |
| `minPaneHeight` | 200pt |
| `tabBarHeight` | 36pt |

---

## Part 6: Shadows & Elevation

### 6.1 Shadow Scale

| Token | Radius | Y-Offset | Opacity | Use |
|-------|--------|----------|---------|-----|
| `sm` | 4pt | 1pt | 6% black | Card surfaces (split panes) |
| `md` | 12pt | 4pt | 10% black | Popovers, dropdowns, tooltips |
| `lg` | 32pt | 12pt | 16% black | Modals, command palette, sheets |

3 shadows. Not 5.

### 6.2 Elevation Recipes

Each surface level has a complete recipe (background + border + shadow):

| Level | Background | Border | Shadow | Use |
|-------|-----------|--------|--------|-----|
| `base` | `base` | none | none | Window, sidebar, rail, pane gaps |
| `card` | `card` | `border` 1pt | `sm` | Split panes, settings panels |
| `overlay` | `overlay` | `border` 1pt | `lg` | Modals, command palette, sheets |
| `popover` | `overlay` | `border` 1pt | `md` | Popovers, dropdowns, tooltips, menus |

Applied via a single modifier:

```swift
.elevation(.card)    // sets background, border, shadow, corner radius all at once
.elevation(.overlay) // etc
```

This is the key — no one manually combines background + border + shadow + radius. One modifier, one level.

---

## Part 7: Animation

### 7.1 The Spring

One spring for all structural transitions:

```swift
Animation.spring(response: 0.35, dampingFraction: 0.86)
```

Used for: sidebar expand/collapse, split creation/destruction, command palette open/close, modal presentation, tab reorder, pane resize, popover appearance, segmented control slide, FAB menu.

### 7.2 Micro Timing

One timing for all micro-interactions:

```swift
Animation.easeOut(duration: 0.12)  // 120ms
```

Used for: hover background appear, press scale, focus ring, close button fade-in, action button reveal, tooltip appear.

### 7.3 Status Animations

| Animation | Trigger | Spec |
|-----------|---------|------|
| Running pulse | Agent working | Dot opacity 0.6→1.0, 2s cycle, ease-in-out |
| Complete glow | Agent finished | Dot scale 1→1.4→1, opacity 1→0 on glow ring, 300ms |
| Error shake | Agent errored | Dot shifts ±2pt horizontal, 300ms, one-shot |
| Waiting pulse | Needs approval | Dot opacity 0.7→1.0, 3s cycle (slower than running) |
| Dirty dot appear | File becomes dirty | Dot scales 0→1.2→1.0, 200ms spring |

### 7.4 Hover Spec (Universal)

Every interactive element gets a hover state. The effect is always the same: background shifts to `hover` surface. 120ms ease-out. No exceptions, no variation. Buttons, tabs, list rows, sidebar items, rail items, toolbar buttons, chips — all the same hover treatment.

Press state: scale 0.97, 120ms ease-out. Same for everything interactive.

---

## Part 8: App Shell — The Layered Surface Model

### 8.1 Window Anatomy

```
┌──────────────────────────────────────────────────────────────┐
│  Titlebar (unified compact toolbar) — base surface           │
│  [◀▶ sidebar] ─── [repo / branch breadcrumb] ─── [(+)] [⌘K] │
├────────┬─────────────────────────────────────────────────────┤
│        │  ┌──────────────────┐ 6pt ┌─────────────────────┐  │
│  Repo  │  │ Tab Strip        │ gap │ Tab Strip            │  │
│  Rail  │  ├──────────────────┤     ├─────────────────────┤  │
│        │  │                  │     │                      │  │
│  base  │  │   Card Surface   │     │   Card Surface       │  │
│  surf  │  │   (split pane)   │     │   (split pane)       │  │
│        │  │                  │     │                      │  │
│ ┌────┐ │  │                  │     │                      │  │
│ │side│ │  │                  │     │                      │  │
│ │bar │ │  │                  │     │                      │  │
│ │    │ │  └──────────────────┘     └─────────────────────┘  │
│ │base│ │           base surface (visible in gaps)            │
│ │surf│ │                                                     │
│ └────┘ │  ┌──────────────────────────────────────────────┐  │
│        │  │            [Status Capsule]                   │  │
│        │  └──────────────────────────────────────────────┘  │
├────────┴─────────────────────────────────────────────────────┤
│                     base surface                             │
└──────────────────────────────────────────────────────────────┘
```

**The critical insight:** The base surface is continuous. It extends behind the sidebar, behind the rail, and is visible in the gaps between split-pane cards. The cards sit ON TOP of this surface. The sidebar is part of the base — it's not a separate elevated surface.

### 8.2 Zone Model

| Zone | Width | Surface Level | Role |
|------|-------|---------------|------|
| **Repo Rail** | 48pt fixed | `base` | Project/worktree switching |
| **Content Sidebar** | 260pt default | `base` | Browse files, diffs, agents |
| **Split Pane Cards** | Flexible | `card` | Tabs + content where work happens |
| **Status Capsule** | Auto-width, floating | `overlay` | Branch, sync status, errors |

### 8.3 Split Pane Cards

Each split pane is rendered as a card:
- Background: `card` surface
- Corner radius: `radius` (12pt) on ALL four corners
- Border: `border` 1pt
- Shadow: `sm`
- Gap between adjacent cards: `paneGap` (6pt) — base surface visible in gap
- The tab strip is INSIDE the card, at the top
- The content (editor, terminal, agent) fills the card below the tab strip

When a pane is focused:
- If accent is active: a subtle gradient wash of `accent.subtle` (6% opacity) at the top of the card, fading to transparent over 80pt
- Border shifts to `borderFocus` on the top edge only

When a pane is unfocused:
- Slightly dimmed — the card `text` becomes `textSecondary` (this is very subtle)
- No accent wash

### 8.4 Titlebar

Uses `NSToolbar` with `.unifiedCompact` style. Background matches `base` surface.

**Leading:** Sidebar toggle button (chevron icon)
**Center:** Breadcrumb: `RepoName / branch-name` — clickable
**Trailing:** (+) FAB button + `⌘K` command palette trigger

### 8.5 Sidebar (Base Surface, Not Elevated)

The sidebar is NOT a card. It sits flush on the base surface. It's separated from the pane cards only by the fact that the pane cards are elevated and the sidebar is not.

A subtle 1pt `border` vertical line at the sidebar's right edge provides separation. That's all.

---

## Part 9: Components

### 9.1 Buttons

Two variants. Not four, not five. Two.

**Primary (Filled):**
- Background: `text` color (dark in light mode, light in dark mode). If accent is active: accent `solid` color.
- Text: `base` color (inverted)
- Radius: `radius` (12pt)
- Height: 36pt (comfortable) / 30pt (compact)
- Horizontal padding: 16pt
- Hover: lighten 8%
- Press: scale 0.97, darken 5%

**Ghost (Transparent):**
- Background: transparent
- Text: `textSecondary`
- Border: none (appears on hover: `border` 1pt)
- Radius: `radius` (12pt)
- Height: 36pt / 30pt
- Hover: `hover` background, `text` foreground, `border` 1pt
- Press: scale 0.97, `active` background

For destructive actions, the primary button uses `error` as background. This is not a separate variant — it's a color parameter on Primary.

**Loading state:** Spinner replaces label. Same dimensions. No shimmer, no skeleton.

### 9.2 Inputs

One input style:
- Background: `card` surface (or `base` if already on card)
- Border: `border` 1pt
- Radius: `radius` (12pt)
- Height: 36pt / 30pt
- Text: `text`, placeholder: `textTertiary`
- Focus: border becomes `borderFocus` (accent at 50%), subtle `accent.subtle` glow (2pt shadow)
- Error: border becomes `error`, subtle `error.subtle` glow

Search input: same as above, with leading magnifying glass icon in `textTertiary` and trailing clear button on content.

### 9.3 Tab Pills

Inside each split-pane card's tab strip:
- Pill shape with `radius` (12pt)
- Height: 28pt
- Horizontal padding: 10pt
- Icon (14pt) + title (12pt `label` weight) + close button (hidden until hover)

**States:**
- Inactive: transparent background, `textSecondary` title
- Inactive hover: `hover` background (within card context), close button fades in
- Active: `base` background (one level below card — creates the "tab is an opening in the card" effect), `text` title, bottom 2pt accent indicator
- Agent tabs: 2pt left-edge identity color stripe

### 9.4 Cards / Panels

Everything that contains content uses the elevation system:
- `.elevation(.card)` for split panes, settings panels, sidebar cards
- `.elevation(.overlay)` for modals, sheets
- `.elevation(.popover)` for dropdowns, menus, tooltips

No manual background/border/shadow/radius composition. One modifier.

### 9.5 Toggles

iOS-style toggle:
- Track: 44pt × 24pt, `radiusFull`
- Off: `border` 1pt, `hover` fill
- On: `accent.solid` fill (or `textSecondary` fill if no accent)
- Knob: 20pt circle, white, `shadow.sm`
- Transition: spring

### 9.6 Chips / Badges

- Background: `hover` (neutral) or `status.subtle` (semantic)
- Text: `textSecondary` (neutral) or status color (semantic)
- Radius: `radius` (12pt) — same as everything else
- Height: 22pt
- Horizontal padding: 8pt
- Font: `caption` (11pt)

### 9.7 Dividers

- Horizontal: 1pt line in `border` color
- That's it. No dashed variants, no ASCII dashes, no fancy separators.

### 9.8 Status Dot

- Size: 8pt
- Shape: circle (`radiusFull`)
- Color: semantic status color
- Running: pulse animation
- Complete: brief glow, then static `textTertiary`
- Error: brief shake, then static `error`

### 9.9 Command Palette

- Centered in window, 520pt wide, max 480pt tall
- `.elevation(.overlay)` — `overlay` background, 1pt `border`, `shadow.lg`, `radius` corners
- Entry: scale 95%→100% + fade, spring
- Exit: scale→97% + fade, 120ms ease-out
- Search field inside: same `radius`, `base` background (one level below overlay)
- Result rows: `radius` corners on hover highlight, 120ms

### 9.10 Modals / Sheets

- Centered, backdrop blur (20pt radius, 40% black overlay in dark, 30% black in light)
- `.elevation(.overlay)`
- Max width: 480pt (standard) or 640pt (wide)
- Title: `title` (18pt semibold)
- Content: `body` (13pt)
- Buttons: right-aligned, Primary + Ghost
- Entry/exit: spring

### 9.11 Popovers / Dropdowns / Menus

- `.elevation(.popover)` — `overlay` background, 1pt `border`, `shadow.md`
- `radius` corners
- Rows: 32pt height, `body` text, `textSecondary` trailing info
- Hover: `hover` background
- Active: `accent.muted` background (if accent active) or `active` background (monochrome)

### 9.12 Tooltips

- `.elevation(.popover)` but smaller
- Max width: 240pt
- Text: `caption` (11pt), `textSecondary`
- Delay: 600ms
- Appear: fade in 120ms
- Dismiss: fade out 80ms

---

## Part 10: Tab Strip Interactions

### 10.1 Tab Strip Location

The tab strip lives INSIDE each split-pane card, at the top. It's part of the card surface, not separate chrome.

Height: 36pt. Background: `card` surface (same as the pane content).

A (+) button at the right end of the tab strip opens the creation menu.

### 10.2 Tab States

| State | Background | Title Color | Close | Indicator |
|-------|-----------|-------------|-------|-----------|
| Inactive | transparent | `textSecondary` | hidden | none |
| Inactive + hover | `hover` | `textSecondary` | fades in | none |
| Active | `base` | `text` | visible | 2pt bottom accent bar |
| Preview | transparent | `textSecondary`, italic | hidden | none |
| Dirty | + amber 4pt dot left of close | | | |
| Agent running | + identity stripe left edge, pulse | | | |
| Agent complete | + identity stripe, static | | | |
| Agent error | + identity stripe → error color, shake | | | |

### 10.3 Tab Drag & Drop

The tab drag-and-drop interaction keeps the existing insertion and drop-zone behavior. Key visual changes:
- Lifted tab uses `shadow.md` (not lg)
- All corners remain `radius` (12pt)
- Drop zone overlays use `accent.subtle` (6% opacity)
- Insertion indicator: 2pt vertical line in `accent.solid` (or `textSecondary` if monochrome)

### 10.4 Tab Close

- Tab shrinks to 0 width, spring animation
- Adjacent tabs slide to fill, spring, 30ms delay
- If dirty: save prompt popover (not modal) below tab

---

## Part 11: Repository Rail

### 11.1 Layout

Width: 48pt. Background: `base` surface.

Border: 1pt `border` on right edge.

### 11.2 Repo Item

- 34pt × 34pt rounded square with `radius` (12pt)
- Two-letter abbreviation, `caption` font semibold
- Default: `hover` background, `textSecondary`
- Hover: `active` background, `text`
- Active: `accent.muted` background (or `active` if monochrome), `text`, 3pt left-edge accent indicator bar
- Spacing: 8pt between items

### 11.3 Worktree Item

- 34pt wide, 26pt tall
- Small dot (6pt) + branch name (`micro` font)
- Default: `textTertiary`
- Active: accent dot, `text`

---

## Part 12: Content Sidebar

### 12.1 Structure

Background: `base` surface. Not elevated. The sidebar and the gaps between pane cards are the same visual level.

Two-tab segmented control at top: **Files** | **Agents**

Segmented control: `radius` corners on the track, sliding active indicator with spring animation. Active segment: `card` background (elevated look). Inactive: transparent.

### 12.2 Files Tab

File tree with:
- 16pt indentation per level
- Subtle connector lines in `border` color via `Path`
- Disclosure chevrons: 9pt, `textTertiary`
- Folder names: `body` medium weight
- File names: `body` regular weight
- Git status indicators: colored symbols aligned with the current shared `GitStatusIndicator` treatment

Diffs section below with collapsible sections for Staged/Unstaged.

Inline commit area at bottom when staged files exist.

### 12.3 Agents Tab

Running agents with identity dots + status chips.
Recent agents dimmed.
Workflow cards live in the Agents tab alongside agent sessions.
They surface active runs first, recent runs second, and open definition/run tabs in the existing split/tab shell.

---

## Part 13: Status Capsule

Floating pill at bottom-center:
- `radiusFull` (pill shape)
- `.elevation(.popover)` treatment
- 80% opacity at rest, 100% on hover
- Content-sized width (no minWidth, no stretching)
- Branch name + ahead/behind + status + agent dots
- Expands on hover to reveal git actions: fetch, pull, commit, push
- Auto-hides after 3s inactivity

---

## Part 14: Density

Two modes: `comfortable` (default) and `compact`.

| Token | Comfortable | Compact |
|-------|------------|---------|
| Tab height | 36pt | 28pt |
| Button height | 36pt | 30pt |
| Sidebar row | 32pt | 24pt |
| List row | 32pt | 24pt |
| Toolbar | 44pt | 36pt |
| Standard padding | 16pt | 12pt |
| Icon size | 16pt | 14pt |
| Rail width | 48pt | 40pt |

Same design, same tokens, scaled proportionally.

---

## Part 15: Accessibility

### 15.1 Keyboard Navigation

Every surface is fully keyboard-navigable.

### 15.2 Reduced Motion

When `accessibilityReduceMotion` is true:
- All springs → instant (0ms)
- Pulses → static indicators
- Scale effects → removed
- Fades → 80ms max

### 15.3 High Contrast

When system high-contrast mode is active:
- Border opacity doubles
- Text contrast increases (tertiary becomes secondary)
- Shadows become borders (for card/overlay distinction without shadow perception)

---

## Part 16: What We Removed From The Legacy UI

| Legacy Pattern | Current Rule | Why |
|---------------|--------------|-----|
| 6-level background scale | 3 surfaces (`base`, `card`, `overlay`) | Too many near-identical levels created ambiguity |
| 6-level radius scale | 3 values (`radiusMicro`, `radius`, `radiusFull`) | One dominant radius creates coherence |
| 4 button variants | Filled + ghost | Fewer variants make intent clearer |
| Terminal-aesthetic effects and ASCII visuals | Deleted | They fought the warm layered-surface system |
| Bracket shortcut notation | Chip-style `ShortcutBadge` | Cleaner and more consistent with the rest of the UI |
| Separate chat-style color system | Unified design tokens | One design system, not parallel ones |
| Multi-level border and shadow scales | Minimal default + focus border, `sm/md/lg` shadows | Simpler and easier to apply consistently |
| Multiple micro-interaction timings | One `Animations.micro` timing | Lower mental overhead and more consistency |

---

## Part 17: Shared UI Inventory

Design-system primitives live in `Packages/UI/Sources/UI/Models/DesignSystem/` and include:

- `Colors`, `Typography`, `Spacing`, `Animations`, `Shadows`, `Density`
- `AgentColor`, `StatusHint`, `ChatTokens`
- `DevysShape`, `Elevation`

Shared SwiftUI component files live in `Packages/UI/Sources/UI/Views/Components/Common/`.

**Atomic components (10):**
`ActionButton`, `Icon`, `TextField`, `Toggle`, `Chip`, `Divider`, `ShortcutBadge`, `StatusDot`, `GitStatusIndicator`, `AgentIdentityStripe`

**Container components (9):**
`ListRow`, `SectionHeader`, `EmptyState`, `Panel`, `Popover`, `Sheet`, `SegmentedControl`, `Toolbar`, `Tooltip`

**Feature components (17):**
`TabPill`, `FileRow`, `FolderRow`, `ConnectorLine`, `AgentRow`, `DiffRow`, `RepoItem`, `WorktreeItem`, `NotificationToast`, `Breadcrumb`, `FABMenu`, `DropZoneOverlay`, `InsertionIndicator`, `DragPreview`, `InlineCommit`, `SavePromptPopover`, `RailAddButton`

**Composed surfaces (4):**
`CommandPalette`, `CommandPaletteRow`, `StatusCapsule`, `BranchPicker`

This is the current shared UI surface area. If repeated feature-local visuals appear outside this set, they are design-system debt.

---

## Appendix A: Visual Audit Checklist

Before any PR is approved, check:

- [ ] All corner radii use `Spacing.radius` (12pt), `Spacing.radiusMicro` (4pt), or `Spacing.radiusFull`
- [ ] All `RoundedRectangle` uses `style: .continuous`
- [ ] All surfaces use `.elevation()` modifier, not manual bg+border+shadow
- [ ] All colors come from `Theme`, not hardcoded hex
- [ ] All fonts come from `Typography`, not `.system(size:)`
- [ ] All spacing comes from `Spacing`, not raw numbers
- [ ] All animations use `Animations.spring` or `Animations.micro`
- [ ] Hover states present on every interactive element
- [ ] Works in both light and dark mode
- [ ] Works in both comfortable and compact density

## Appendix B: Legacy-To-Current Notes

| Legacy Item | Current Handling |
|-------------|------------------|
| `TerminalEffects.swift` | Deleted |
| `ASCIILogo.swift` | Deleted |
| legacy terminal command buttons | folded into `ActionButton` and shared button styling |
| legacy terminal divider variants | folded into `Divider` |
| package-local UI guidance | lives in `Packages/UI/AGENTS.md` and must match this reference |
