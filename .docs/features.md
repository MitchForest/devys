# Features

## Core Concept

A spatial orchestration interface for directing AI coding agents. The human becomes a conductor rather than a performer.

- **Traditional IDE**: Human → Code → Machine
- **This Canvas**: Human → Agents → Code → Machine

---

## 1. Canvas & Spatial Layout

| Feature | Description |
|---------|-------------|
| Infinite canvas | Pannable, zoomable workspace |
| Pane system | Draggable, resizable, snappable panes |
| Pane groups | Snap panes together into logical groups (e.g., "Backend Stack") |
| Hotkey expand | Fullscreen a pane, same key to restore |
| Layouts/presets | Save named layouts ("Review Mode", "Debug Mode", "Deploy Mode") |
| Mini-map | Birds-eye navigation for large canvas states |

---

## 2. Terminal Panes

| Feature | Description |
|---------|-------------|
| Multi-terminal | Spawn terminals anywhere on canvas |
| Persistent sessions | Terminals survive app restarts |
| Service labels | Tag terminals: "localhost:3000", "supabase", "ngrok" |
| Log streaming | Visual indicators for activity, errors |
| Terminal templates | One-click spawn "Next.js dev server @ 3000" |

---

## 3. Agent Panes

| Feature | Description |
|---------|-------------|
| Agent spawning | Start agent sessions with configurable context |
| Agent workspace binding | Each agent tied to a workspace/directory |
| Streaming output | Watch agent thinking/actions in real-time |
| Intervention points | Pause agent, inject guidance, resume |
| Parallel agents | Run multiple agents on different tasks simultaneously |
| Sequential workflows | Chain agents: Agent A → review → Agent B |

---

## 4. Diff & Git Integration

| Feature | Description |
|---------|-------------|
| Unified diff view | See all changes across agents in one pane |
| Per-file staging | Stage/unstage individual files or hunks |
| Revert controls | Revert agent changes easily |
| Commit attribution | Track which agent made which changes |
| PR review pane | Review PRs inline on canvas |
| Conflict resolution | Visual merge when agents conflict |

---

## 5. Workflow Automation

| Feature | Description |
|---------|-------------|
| Git hooks | Trigger agents on commit, push, PR open |
| Scheduled runs | "Run security review agent every night" |
| Workflow builder | Visual DAG for multi-step automations |
| Conditional logic | If tests fail → run fix agent |
| Approval gates | Require human approval before merge |

---

## 6. Prompt Library

| Feature | Description |
|---------|-------------|
| Prompt storage | Save prompts with names, tags |
| Prompt templates | Variables like `{{branch}}`, `{{files}}` |
| Quick paste | Hotkey to insert prompt into active agent |
| Prompt chains | Multi-prompt sequences |
| Sharing | Export/import prompt packs |

---

## 7. MCP Management

| Feature | Description |
|---------|-------------|
| MCP registry | List all available MCPs |
| Toggle enable/disable | Per-agent or global |
| MCP config editor | Edit server configs visually |
| MCP health | Status indicators, restart controls |

---

## 8. Agent Skills Integration

| Feature | Description |
|---------|-------------|
| Skills browser | Browse/install from agentskills.io |
| Per-agent skills | Assign skills to specific agents |
| Skill authoring | Create/edit skills on canvas |
| Skills library | Your org's private skills |

---

## 9. File System View

| Feature | Description |
|---------|-------------|
| Tree view pane | Collapsible folder structure |
| Change highlighting | Show which files agents modified |
| Quick preview | Hover to preview file content |
| File filters | Hide node_modules, show only changed |

---

## 10. Browser/Preview Panes

| Feature | Description |
|---------|-------------|
| Embedded browser | View localhost:3000, 3001, etc. on canvas |
| Live reload | Auto-refresh on file changes |
| Device frames | Preview in iPhone/tablet frames |
| Network inspector | See requests from embedded browser |

---

## 11. Cross-Platform

| Feature | Description |
|---------|-------------|
| Mac native | Primary development experience |
| iPhone companion | Monitor agents, approve gates, light control |
| Relay mode | Phone connects to Mac running agents |

---

## MVP Phases

### Phase 1: Canvas + Terminals
- Infinite canvas with pane system
- Terminal panes with persistence
- Layout save/restore
- Hotkey fullscreen toggle

### Phase 2: Agent Integration
- Claude Code / Codex pane type
- Agent output streaming
- Basic diff view of agent changes

### Phase 3: Git Workflows
- Staging/reverting from canvas
- Commit with attribution
- PR review pane

### Phase 4: Automation
- Git hook triggers
- Prompt library
- Workflow chains

### Phase 5: Polish & Mobile
- MCP management UI
- Skills integration
- iPhone companion app
