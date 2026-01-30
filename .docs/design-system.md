# Devys Design System

A calm, focused interface for AI-native development.

## Core Principles (Apply to BOTH Light and Dark)

### 1. Separation Through Background, Not Borders
- Use subtle background color shifts to define regions
- Borders should be barely visible (low contrast)
- No harsh dividers or heavy lines

### 2. Unified Surfaces
- Tab bar and sidebar share the SAME background color (surface level)
- Main content area uses a different level (base)
- This creates visual cohesion

### 3. Minimal Color Use
- Status colors (green, yellow, red) ONLY for actual status
- No decorative colors
- Accent color only for interactive focus states

### 4. Generous Whitespace
- Padding is generous, never cramped
- Let content breathe

### 5. Subtle Hierarchy
- Primary text is high contrast
- Secondary text is noticeably muted
- Tertiary text is very muted (placeholders, hints)

---

## Color Palette

### Light Mode
```
Hierarchy (light to dark depth):
├── base:        #FFFFFF    Main content background (white)
├── surface:     #F5F5F7    Sidebar, tab bar, cards (light gray)
├── elevated:    #EBEBEB    Hover states, elevated cards
└── pressed:     #E0E0E0    Active/pressed states

Borders:
├── subtle:      #E8E8E8    Barely visible (use this most)
├── default:     #D1D1D6    Standard borders (use sparingly)
└── strong:      #C7C7CC    Emphasized (rare)

Text:
├── primary:     #1C1C1E    Main text (near black)
├── secondary:   #6E6E73    Descriptions, labels
├── tertiary:    #AEAEB2    Placeholders, disabled
└── quaternary:  #C7C7CC    Very muted hints

Status:
├── success:     #34C759    Running, success (green)
├── warning:     #FF9500    Pending, caution (orange)
├── error:       #FF3B30    Error, failed (red)
└── info:        #007AFF    Links, info (blue)

Accent:
├── accent:      #007AFF    Focus rings, primary actions (blue)
└── accentMuted: #007AFF15  Subtle highlight backgrounds
```

### Dark Mode
```
Hierarchy (dark to light depth):
├── base:        #1C1C1E    Main content background (near black)
├── surface:     #2C2C2E    Sidebar, tab bar, cards (dark gray)
├── elevated:    #3A3A3C    Hover states, elevated cards
└── pressed:     #4A4A4C    Active/pressed states

Borders:
├── subtle:      #3A3A3C    Barely visible (use this most)
├── default:     #48484A    Standard borders (use sparingly)
└── strong:      #636366    Emphasized (rare)

Text:
├── primary:     #FFFFFF    Main text (white)
├── secondary:   #8E8E93    Descriptions, labels
├── tertiary:    #636366    Placeholders, disabled
└── quaternary:  #48484A    Very muted hints

Status:
├── success:     #32D74B    Running, success (green)
├── warning:     #FF9F0A    Pending, caution (orange)
├── error:       #FF453A    Error, failed (red)
└── info:        #0A84FF    Links, info (blue)

Accent:
├── accent:      #0A84FF    Focus rings, primary actions (blue)
└── accentMuted: #0A84FF26  Subtle highlight backgrounds
```

---

## Layout Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    [surface background]                      │
│  ┌──────┬─────────────────────────────────────────────────┐ │
│  │      │  Tab Bar (same surface as sidebar)              │ │
│  │ Side ├─────────────────────────────────────────────────┤ │
│  │ bar  │                                                 │ │
│  │      │           Content Area                          │ │
│  │      │           [base background]                     │ │
│  │      │                                                 │ │
│  │      │                                                 │ │
│  └──────┴─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

Key: Sidebar and Tab Bar share the SAME surface color
     Content area uses base color
     Separation is through color, not borders
```

---

## Border Usage Rules

### DO
- Use `subtle` border for most separations
- Let background color changes do the work
- Borders should be barely noticeable

### DON'T
- Use heavy 1px borders everywhere
- Use high-contrast border colors
- Add borders where background shift suffices

---

## Component Guidelines

### Sidebar
- Background: `surface`
- Icon color (default): `textSecondary`
- Icon color (hover): `textPrimary`
- Hover background: `elevated`
- No visible border on right (color shift handles it)

### Tab Bar
- Background: `surface` (SAME as sidebar)
- Active tab: `base` background (content color)
- Inactive tab: transparent
- Tab text: `textSecondary`, active: `textPrimary`
- Very subtle bottom border or none

### Content Area
- Background: `base`
- Cards within: can use `surface` for elevation
- Text follows text hierarchy

### Status Indicators
- Small dots (6-8px)
- Only use status colors for actual status
- Pulse animation optional for "running" state

---

## Typography

```
Font: SF Pro (system)
Mono: SF Mono (system)

Scale:
├── xs:     11px    Metadata, timestamps
├── sm:     12px    Secondary labels
├── base:   13px    Body text
├── md:     14px    Emphasized body
├── lg:     16px    Section headers
├── xl:     20px    Page titles
└── xxl:    24px    Large titles

Weights:
├── regular:   400  Body text
├── medium:    500  Labels, buttons
└── semibold:  600  Headings
```

---

## Spacing

```
Base unit: 4px

Scale:
├── space1:   4px   Tight (icon gaps)
├── space2:   8px   Default element gap
├── space3:  12px   Related groups
├── space4:  16px   Section padding
├── space5:  20px   Card padding
├── space6:  24px   Large gaps
├── space8:  32px   Page margins
```

---

## What We Got Wrong Before

1. **Heavy borders everywhere** - Should use background color shifts
2. **Different colors for sidebar vs tab bar** - Should be unified
3. **Dark mode as default** - Should support both equally
4. **High contrast borders** - Should be barely visible
5. **Too many divider lines** - Should rely on whitespace and color

---

## Implementation Checklist

- [ ] Sidebar and tab bar share same `surface` background
- [ ] Content area uses `base` background  
- [ ] Borders are `subtle` color (barely visible)
- [ ] Remove heavy divider lines
- [ ] Status colors only for status, not decoration
- [ ] Both modes follow identical principles
