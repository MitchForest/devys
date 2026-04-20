# Devys AI Employees: Host-First, Swappable Runtime Architecture

Status: future design brief

Updated: 2026-04-19

## Purpose

This document defines the target architecture for turning Devys into the environment where a solo founder runs a software company with a small staff of persistent AI employees.

It is a future design brief, not an active work plan. When this slice becomes active, move this document into `../active/` and turn it into the working plan.

This brief does not override the repo reference docs. It is written to fit the existing doctrine:

- TCA owns app-domain presentation, intent, and navigation in the native clients
- host runtimes execute effects but do not become UI-facing owners in the clients
- no mirrored ownership between reducers and runtime stores
- app hosts stay thin

Verification for work that lands from this brief must use the repo's supported entrypoints:

- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `swift test` inside the touched package for package-local validation
- `swift run devys-host --selftest` once the host target exists

## High-Level Goals

Devys should be both:

- the native local coding shell for day-to-day development work
- the control plane for AI-first companies run with persistent agents

The primary user-facing scenes are:

- `Solo`
- `Team`

The target experience:

- a user composes a team of AI employees on a canvas
  - nodes are agents
  - edges are delegation, hierarchy, communication, and escalation relationships
- each agent has a persistent identity, voice, skills, tools, memory, triggers, permissions, and goals
- a shared kanban board carries tasks owned by the user or by specific agents
- agents keep working while the user sleeps
  - cron triggers fire
  - webhook triggers fire
  - scheduled workflows resume across host restarts
- the user sees the same team, kanban, approvals, and run activity on macOS and iOS
- agents and their durable state live outside the repositories they work on

Concrete first-wave agents this architecture must support:

- personal assistant
- engineering manager
- pr reviewer
- pr closeout
- content creator
- ads manager
- twitter manager

Non-goals for this slice:

- turning Devys into a multi-tenant hosted service
- shipping agents that act without allowlists, approvals, or auditability
- building a parallel architecture for laptop-only users and Mac mini users
- locking the product model to one permanent harness, one permanent memory backend, or one permanent workflow engine

## Canonical Terminology

The product needs a hard language boundary between repo-scoped work and long-lived company-scoped work.

### Scenes

- `Solo`
  - the repo and worktree-scoped coding scene
- `Team`
  - the persistent company and employee scene

The app stays one app with one shell framework. `Solo` and `Team` are separate scenes inside that app, not separate apps.

### `Solo` Terms

Use these in the repo-scoped scene:

- repository
- worktree
- session
- repo agent
- repo workflow

`Solo` is where coding, terminals, diffs, repo-scoped agent chats, and repo-scoped workflows live.

### `Team` Terms

Use these in the persistent company scene:

- employee
- team canvas
- board
- automation
- resource
- host
- run

`Team` is where long-lived AI employees, boards, approvals, triggers, and company-level runs live.

### Naming Rules

- do not call long-lived employees and repo-scoped chat sessions by the same user-facing name
- do not use `workspace` as the user-facing term for a repo checkout in this slice; use `worktree`
- use `employee` as the user-facing term for a durable AI worker
- `agent` may remain the technical term in runtime abstractions, APIs, and compatibility layers where that is convenient
- use `session` for one repo-scoped interactive chat or execution thread
- use `automation` for durable Team-side trigger and run behavior
- use `repo workflow` for workflow behavior that belongs to one repo or worktree in `Solo`

## Product Position

Devys is the place a solo founder runs their company.

The shell remains the repo rail, the content sidebar, the split-pane cards, the command palette, and the floating status capsule.

The app should present two scenes inside one shell:

- `Solo`
  - the existing repo and worktree shell
  - repo rail
  - content sidebar with `Files` and `Agents`
  - editor, terminal, diff, repo agent, and repo workflow surfaces
- `Team`
  - a separate persistent scene for long-lived employees
  - entered from a scene switch at the top of the rail above repositories
  - reuses the same shell grammar of rail, sidebar, panes, tabs, and inspectors
  - does not treat long-lived employees as repo-scoped tabs or repo sidebar content

The critical rule is:

- repo-scoped `Agents` in `Solo` are not the same thing as long-lived `Employees` in `Team`

The `Team` scene should be the primary surface for:

- browsing the employee roster
- opening the team canvas
- viewing boards, approvals, runs, resources, and hosts
- inspecting an employee's soul, charter, memory, skills, tools, permissions, and triggers

The board is a first-class `Team` surface. It does not belong to a single repo or worktree.

Remote work stays terminal-first per `../ssh-plan.md`. Agents that need to operate on remote dev boxes should use the existing SSH transport and remote repository model rather than inventing a parallel remote protocol.

## Team Scene UI Model

The `Team` scene should reuse the same shell grammar as `Solo`:

- rail for primary context switching
- sidebar for section navigation
- main pane for working surfaces
- optional inspector for the selected object

The rail should not become a dumping ground for all navigation. It should stay focused on context switching.

### Team Rail

The `Team` rail should be:

- scene switcher circle at the top
- divider
- `Home`
- one circle per employee
- bottom action: `Add Member`

The top scene switcher should:

- show the current scene as the main icon
- show a bottom-right SF Symbol badge indicating the other scene is one click away
- include a divider below it before the rest of the rail content

The rail rules are:

- `Solo` rail switches repository and worktree contexts
- `Team` rail switches team-wide context or one employee context
- `Settings` should not be a rail item in `Team`
- boards, inbox, automations, resources, and hosts should not be rail items in `Team`

### Team Home Context

`Home` is the team-wide context for anything not owned by a single employee.

The `Home` sidebar should contain:

- `Overview`
- `Board`
- `Inbox`
- `Automations`
- `Resources`
- `Hosts`
- `Settings`

`Home > Overview` should answer:

- what needs attention now
- what is blocked
- what is running
- who is overloaded
- what changed recently

Expected `Home > Overview` content:

- approvals requiring action
- active runs
- blocked tasks
- recent outputs and artifacts
- host health
- automation failures
- quick team snapshot

`Home > Board` is the shared kanban surface for user-owned and employee-owned tasks.

`Home > Inbox` is the queue for:

- approvals
- escalations
- mentions
- failures
- notifications

`Home > Automations` is the team-wide surface for:

- cron triggers
- webhook triggers
- internal events
- run history
- pause, retry, and disable actions

`Home > Resources` is the shared integrations and grant surface.

`Home > Hosts` is the machine and runtime-health surface for local and remote hosts.

`Home > Settings` is the team-wide policy surface.

### Employee Context

Selecting an employee in the rail switches the scene into one employee context.

The employee sidebar should contain:

- `Overview`
- `Work`
- `Memory`
- `Tools`
- `Automations`
- `Access`
- `Activity`

The employee sidebar should stay focused on stable sections. It should not explode each primitive into a top-level navigation item.

`Employee > Overview` should show:

- current status
- active goals
- assigned tasks
- recent runs
- pending approvals
- quick actions such as message, assign task, pause, and edit

`Employee > Work` is the execution surface for:

- assigned tasks
- backlog
- open runs
- outputs and artifacts
- linked repositories and projects

`Employee > Memory` is the memory editing and recall surface:

- curated memory
- recent notes
- remembered preferences and facts
- search and recall
- manual memory edits

`Employee > Tools` is the capability and runtime surface:

- enabled skills
- tool bindings
- model and runtime profile
- integration bindings

`Employee > Automations` is the employee-specific trigger and run surface.

`Employee > Access` is the permissions surface:

- repository access
- external account access
- approvals policy
- destructive-action policy

`Employee > Activity` is the audit and timeline surface:

- runs
- tool calls
- failures
- approvals
- comments
- artifacts

### Soul, Charter, Goals, And Style

These should not each become sidebar sections in v1.

Instead:

- surface summary cards in `Employee > Overview`
- provide editable detail tabs or segmented controls in the main pane:
  - `Identity`
  - `Charter`
  - `Goals`
  - `Style`

This keeps the sidebar stable while still exposing the core employee primitives.

### Settings Model

There are three settings scopes:

- `App Settings`
  - Devys-wide app behavior such as appearance, keyboard behavior, and app notifications
- `Team Settings`
  - shared policy under `Home > Settings`
- `Employee Settings`
  - employee-specific settings expressed through `Overview`, `Tools`, and `Access`

`Team Settings` should include:

- team identity
- default runtime policy
- approval defaults
- notification defaults
- host pairing and device access
- shared integrations
- spend and rate limits
- audit, export, and retention policy

### Main Pane Surfaces

The `Team` scene should preserve the shell principle that the main area is a working surface, not a static dashboard.

Common `Team` pane content types should include:

- team overview
- board
- inbox item
- automation detail
- resource detail
- host detail
- employee overview
- task detail
- run detail
- memory note

This keeps `Team` consistent with the existing pane and tab model without forcing long-lived employees into repo-scoped tabs.

## Team User Flows

The plan should explicitly support these first-wave flows.

### 1. Create The First Employee

- enter `Team`
- land on an empty-state `Home`
- click `Add Member`
- choose blank or template
- set name, role, avatar, initial tools, and approval mode
- land on that employee's `Overview`

### 2. Assign Work

- open `Home > Board` or `Employee > Work`
- create a task
- assign it to self or to an employee
- optionally attach repositories or external resources
- allow the employee to pick it up or start a run manually

### 3. Review A Blocked Action

- open `Home > Inbox`
- inspect the approval request
- review diff, preview, and context
- approve, reject, or request revision

### 4. Tune An Employee

- open the employee
- update charter, goals, or style
- add or remove tools
- adjust permissions
- add memory notes
- enable or disable automations

### 5. Debug A Failure

- open `Inbox` or `Activity`
- inspect the failed run
- review trigger, steps, tool calls, and artifacts
- retry or edit the employee or automation configuration

### 6. Manage Shared Team Setup

- open `Home > Resources`, `Hosts`, or `Settings`
- connect integrations
- set defaults
- manage host and device state

### 7. Jump Between `Solo` And `Team`

- start in `Solo` when the work is repo-scoped
- switch to `Team` when the work should become durable employee-owned work
- assign or create the task in `Team`
- jump back into a repository when execution requires repo-scoped coding or review

## Supported Deployment Shapes

Two supported shapes. The architecture is the same; only the host location changes.

### Shape A: Local Solo Host

- `devys-host` and `mac-client` run on the same machine
- host binds to `127.0.0.1`
- host is registered as a LaunchAgent and starts on login
- the MacBook is authoritative for agent state
- iOS is optional; if used, it connects when the laptop is reachable

### Shape B: Mac Mini Home Host

- `devys-host` runs on the Mac mini, registered as a LaunchAgent
- host binds to `127.0.0.1` and to a trusted remote interface
- `mac-client` on the laptop and `ios-client` on the phone both connect to that host
- the Mac mini is authoritative for agent state and keeps running while the laptop sleeps

No third deployment shape is supported in this slice. No hosted Devys cloud. No multi-user sharing.

## First Principles

### 1. One durable authority

There is one durable authority for agents, tasks, triggers, runs, approvals, and memory: `devys-host`.

The native clients do not own those domains. They own:

- selection
- presentation
- navigation
- local draft state
- approval intent
- reducer-owned summaries of host state

### 2. Agent identity outlives any repo

An agent is not a worktree.

An agent may operate across many repos, accounts, and external systems. Its identity, memory, tools, and triggers cannot live inside a repository checkout. Repos are resources an agent can access, not the home of the agent.

### 3. Durable workflows are infrastructure

If the system needs retries, sleeps, waits for approval, cron, webhooks, replay, and resume-on-restart, it needs a durable workflow engine. This must live in the host. It must not be reconstructed through reducer timers or ad hoc background tasks in the clients.

### 4. Swappable infrastructure, stable product model

The product model must remain stable if the underlying technology changes.

That means the following are implementation choices behind boundaries:

- harness
- workflow engine
- memory storage backend
- tool runtime
- sandbox mechanism
- model provider

The user-facing primitives are the product:

- employees
- skills
- tools
- triggers
- permissions
- tasks
- boards
- runs
- approvals

### 5. Human approval is a first-class primitive

Useful agents will eventually:

- send messages
- merge PRs
- edit ads
- move money
- change calendars
- write into repos

Approval policy must be modeled as data, not buried in prompt text.

### 6. Build the smallest thing that can survive contact with real use

The first implementation should optimize for:

- explicit ownership
- clear boundaries
- fast iteration
- low operational complexity

It should not over-optimize for:

- many production harness backends on day one
- plugin ecosystems before the core model is proven
- a maximal sandbox story before the agent loop is useful
- package splitting before the boundaries are real in code

## Canonical Primitives

These are the concrete product primitives the system should be built around.

### AgentEmployee

A durable worker with:

- stable ID
- display name
- avatar
- role
- goals
- runtime profile
- tool bindings
- trigger bindings
- permission policy
- memory references
- current status

### Soul

`SOUL.md` is the durable identity file.

It holds the agent's worldview, personality, instincts, preferences, and long-lived orientation.

### Charter

`CHARTER.md` holds operating rules:

- scope
- responsibilities
- escalation behavior
- approval policy
- forbidden actions
- success criteria

This is intentionally separate from repo `AGENTS.md` files so there is no filename collision between repo guidance and agent identity.

### Style

`STYLE.md` is optional. Use it when the agent needs explicit communication, writing, or formatting habits distinct from its soul.

### SkillDefinition

A skill is a directory with a `SKILL.md` file plus optional scripts, references, and assets.

The format should stay compatible with OpenClaw-style skill folders so Devys can import or reuse that ecosystem.

### ToolBinding

A tool binding describes:

- tool kind
- credential source
- allowed resources
- approval behavior
- rate limits
- sandbox policy

Examples:

- CLI
- MCP server
- repo/worktree access
- browser
- GitHub
- Gmail
- Calendar
- Slack
- ads APIs

### Trigger

A trigger wakes an agent or workflow:

- manual
- cron
- webhook
- internal event
- task-assigned
- pr-review-requested
- ci-failed

Triggers should create host-side events. They must not invoke UI logic directly.

### RuntimeProfile

A runtime profile selects how an agent executes:

- harness kind
- model preferences
- reasoning level
- fallback chain
- session policy
- sandbox mode
- network policy

The key rule: `RuntimeProfile` is stable even if the underlying harness changes.

### ResourceGrant

A resource grant maps an agent to allowed scope:

- repo path
- GitHub repo or org
- Gmail account
- Slack workspace or channel
- ad account
- remote host

### Task

A task is assignable to either a human or an agent and includes:

- title
- status
- assignee
- dependencies
- artifacts
- due date or SLA
- source
- owning board
- linked runs

### Board

A board is the shared work-management surface for humans and agents.

### Run

A run is one concrete execution of work with:

- run ID
- trigger
- actor agent
- linked task
- step history
- retry history
- artifacts
- approvals
- final outcome

### ApprovalRequest

An approval request contains:

- reason
- requested action
- risk level
- diff or preview
- approver
- expiration
- outcome

## Filesystem Model

Agent state lives outside repos under a user-scoped root.

Suggested initial layout:

```text
~/.devys/
  host.db
  host.log
  config/
    host.json
    profiles.json
  agents/
    <slug>/
      SOUL.md
      CHARTER.md
      STYLE.md
      agent.yaml
      avatar.png
      skills/
        <name>/SKILL.md
      memory/
        MEMORY.md
        skill.md
      runs/
        <run-id>/
          transcript.md
  skills/
    <name>/SKILL.md
  secrets/
    <key>.ref
```

Storage rules:

- markdown is canonical where humans benefit from reading and editing directly
- SQLite is canonical for query-heavy and durable runtime data
- files on disk are reconciled through the host, not by direct client mutation
- secrets do not live in markdown files

## Required Boundaries

These boundaries are mandatory because they keep the product swappable without over-engineering the first implementation.

### AgentHarness

Responsible for:

- create session
- append input
- stream events
- interrupt
- persist session linkage
- expose artifacts

The first implementation may use ACP if that is the fastest path to useful Codex and Claude-style agents. ACP is an implementation choice, not product doctrine.

Possible future implementations:

- ACP harness adapter
- PI harness adapter
- provider-native harnesses

### WorkflowEngine

Responsible for:

- durable step execution
- retries
- waits
- replay
- cancellation
- resume-on-restart

The first implementation should be a small local Swift engine in `devys-host` because that is the simplest thing likely to ship and learn quickly.

Possible future implementations:

- local journaled Swift engine
- Inngest adapter
- another durable execution backend

### MemoryStore

Responsible for:

- curated memory
- run summaries
- user model
- search and recall
- compaction

The first implementation should use markdown plus SQLite FTS.

### ToolRuntime

Responsible for:

- tool discovery
- allowlists
- resource-grant enforcement
- credentials lookup
- execution
- audit logging

### SandboxProvider

Responsible for:

- execution isolation
- filesystem boundaries
- network policy
- secret injection policy

The first version should not overreach. Start with approval-first execution and explicit resource scoping. Add stronger container or VM isolation once the basic loop is proven useful.

## Design Decisions

### Decision 1: Introduce `devys-host` As A Long-Running Process

`devys-host` is the durable authority for:

- agent catalog
- task board
- triggers
- workflow runs
- approvals
- memory
- host API

Clients become projections over host state. This keeps the native apps aligned with the TCA boundary rule instead of inventing a second durable owner.

### Decision 2: The Product Model Is Harness-Agnostic

Devys does not standardize the product on ACP, PI, or any other single harness.

For v1, it is acceptable to start with one harness implementation if that materially speeds up delivery. The initial recommendation is:

- use ACP first if it is the fastest path to useful coding agents in this repo

But the boundary remains `AgentHarness`, not `ACPClientKit`.

This keeps the door open for:

- PI later
- direct provider harnesses later
- replacement of ACP if it stops being the best option

### Decision 3: The Workflow Engine Is Swappable, But V1 Should Be Local And Small

Devys should not encode Inngest, Temporal, Trigger.dev, or any other workflow product into the product model.

For v1, the recommended implementation is:

- build a small journaled workflow engine in Swift inside `devys-host`

Reason:

- it is operationally simpler
- it keeps the first iteration in one language
- it is enough for one-user or one-team scale

This is not a ban on Inngest or other engines. It is a sequencing decision. If later technology is materially better, it should plug into the `WorkflowEngine` boundary instead of rewriting the product model.

### Decision 4: Agents Live Outside Repositories

Agents live at `~/.devys/agents/<slug>/`.

Workspace-scoped skills may exist under a repo-local `.devys/skills` directory, but repo-local skills do not imply repo-local agents.

### Decision 5: Clients Project Host State; They Do Not Own It

The client reducers own:

- selection
- presentation
- navigation
- local drafts
- approval intent

They do not own:

- agent catalog
- runs
- memory
- tasks
- triggers

Host data reaches clients through an explicit `HostAPIClient` dependency plus streaming updates.

At the UI level, this should project into:

- `Solo` client state for repo and worktree-scoped coding work
- `Team` client state for employees, boards, automations, approvals, and runs

### Decision 6: One Host Per User, Local-First, Remote-Optional

There is one host per user installation.

The user may run it:

- locally on a MacBook
- remotely on a Mac mini

That is one architecture, not two products.

### Decision 7: Skill Format Compatibility Matters

Devys should stay compatible with OpenClaw-style skill folders and `SKILL.md` conventions where practical.

That buys:

- easier import of community skills
- easier portability for users
- less reinvention around skill packaging

### Decision 8: Security Starts With Explicit Grants And Approvals

The first version should enforce:

- per-agent tool allowlists
- per-agent resource grants
- approval requirements for destructive actions
- audit logs for tool calls and outputs

A full container or VM sandbox should be treated as an important hardening step, not a precondition for building the first useful product.

### Decision 9: One API Contract For Clients

There should be one shared contract between host and clients:

- HTTP for requests
- SSE or equivalent streaming for updates
- one pairing and token model

No ad hoc sockets. No special-case protocol for one platform.

### Decision 10: Reuse Existing Repo Seams Before Adding New Ones

This repo already has useful seams:

- `Packages/AppFeatures/Workflows`
- `Packages/AppFeatures/SharedDependencies/WorkflowExecutionClient.swift`
- `Packages/AppFeatures/SharedDependencies/AgentLauncherClient.swift`
- `Packages/Canvas`
- `Packages/UI`
- `Packages/SSH`

The plan should extend these seams where possible instead of bypassing them with a parallel stack.

## Target Codebase Shape

Start simpler than the previous package-heavy sketch.

### `Apps/devys-host` (new)

- long-running Swift binary
- LaunchAgent
- composition root

### `Packages/HostAPI` (new)

- shared request and response types
- event envelopes
- client contract consumed by macOS, iOS, and host

### `Packages/HostRuntime` (new, host-only)

Initial home for:

- agent catalog
- storage
- triggers
- workflow engine
- tool runtime
- memory store
- harness adapters

If clear stable boundaries emerge later, this package can split. Do not pre-split it into many host-only packages before the seams are proven in code.

### `Packages/AppFeatures` (extended, client-side)

Add reducer slices for:

- team scene routing and presentation
- employees directory and detail
- team canvas
- kanban board
- approvals inbox
- activity feed
- host connection state

These reducers project host state. They do not become long-lived owners of host domains.

### Existing Packages Reused

- `Packages/Canvas` remains the node and connector rendering/mechanics layer
- `Packages/UI` remains the only design-system source of truth
- `Packages/SSH` remains the remote execution transport for repo and terminal work
- `Packages/ACPClientKit` remains available as an initial harness implementation if chosen

## HostAPI Surface (Sketch)

This is illustrative, not exhaustive.

```text
GET   /v1/agents
POST  /v1/agents
GET   /v1/agents/{slug}
PATCH /v1/agents/{slug}
POST  /v1/agents/{slug}/run

GET   /v1/tasks
POST  /v1/tasks
PATCH /v1/tasks/{id}

GET   /v1/runs
GET   /v1/runs/{id}
POST  /v1/runs/{id}/cancel
POST  /v1/runs/{id}/retry

GET   /v1/triggers
POST  /v1/triggers
DELETE /v1/triggers/{id}
POST  /v1/hooks/{webhook-id}

GET   /v1/skills
GET   /v1/skills/{name}

GET   /v1/memory/{agent}/recall?q=
POST  /v1/memory/{agent}/note

GET   /v1/canvas
PATCH /v1/canvas

GET   /v1/stream
```

Authentication:

- per-device pairing token
- stored in the client keychain
- revocable from the host

## Implementation Guidance For This Repo

### 1. Update Docs Before Code

Before implementation begins:

- update `../reference/architecture.md`
- update any other affected `../reference/*.md` docs
- move this brief into `../active/` and rewrite it into concrete active plan docs if the scope is too large for one file

No active plan currently covers first-class remote agent surfaces or structured remote agent persistence. Scope those intentionally when this slice begins.

### 2. Reuse Existing Workflow Models

Do not throw away the workflow models already in `Packages/AppFeatures/Workflows`.

Recommended approach:

- reuse and extend `WorkflowRun`, `WorkflowRunAttempt`, and related models
- move durable ownership of runs to the host
- let the client reducers own only presentation and intent

### 3. Reuse `Packages/Canvas`

Do not build a second graph stack.

Recommended approach:

- keep node and connector mechanics in `Packages/Canvas`
- adapt team-canvas state into that rendering boundary
- keep graph truth reducer-owned in `AppFeatures`

### 4. Keep `AgentLauncherClient` And `WorkflowExecutionClient` As Seams

These existing dependencies are useful because they already express the right kind of boundary:

- a reducer depends on explicit execution clients
- not on runtime singletons

They may evolve into, or be complemented by:

- `HostAPIClient`
- `AgentHarnessClient`
- `WorkflowEngineClient`

### 5. Keep Tooling Explicit

For the first version:

- allowlisted CLI
- MCP integration
- explicit resource grants
- explicit approvals

Do not start by implementing the maximal sandbox matrix. Start with the simplest safe path that makes useful agents possible.

## Migration Path

Phased, with each phase shippable on its own.

### Phase 0: Lock The Decisions

Deliverables:

- this brief is accepted as the future direction
- `cx-plan.md` is removed so there is one future plan for this slice
- no code changes

Acceptance:

- there is one future plan for agent architecture
- the plan is consistent with repo doctrine

### Phase 1: Host Boundary And App-Domain Primitives

Deliverables:

- `Packages/HostAPI` exists
- shared models for employees, tasks, approvals, triggers, and run summaries exist
- `HostAPIClient` dependency exists in `Packages/AppFeatures`
- reducer tests cover projection behavior

Acceptance:

- macOS and iOS can compile against the host contract without a real host yet

### Phase 2: `devys-host` Scaffold

Deliverables:

- `Apps/devys-host` target exists
- host boots, binds locally, and responds to empty collections
- host storage root is created under `~/.devys`
- `swift run devys-host --selftest` exists

Acceptance:

- a developer can start the host and fetch empty resources from the clients

### Phase 3: Agent Catalog And Files On Disk

Deliverables:

- `~/.devys/agents/<slug>/` loads into host models
- `SOUL.md`, `CHARTER.md`, optional `STYLE.md`, and `agent.yaml` are supported
- clients can list employees and create them through the host

Acceptance:

- a hand-authored employee appears in the clients
- an employee created in the UI round-trips to disk

### Phase 4: Skills, Memory, And Tasks

Deliverables:

- skill loader for OpenClaw-style `SKILL.md` directories
- markdown plus SQLite memory store
- host-owned task board
- client projections for employee detail and board views

Acceptance:

- skills can be discovered from user and employee directories
- tasks can be assigned to employees
- memory survives host restart

### Phase 5: Tool Runtime And Approval Flow

Deliverables:

- allowlisted CLI and MCP tool runtime
- resource grants
- approval queue for destructive actions
- audit logging

Acceptance:

- an agent can perform allowed read operations
- destructive actions are blocked until approved

### Phase 6: Durable Workflow Engine

Deliverables:

- local journaled Swift workflow engine
- retries with backoff
- replay and resume-on-restart
- trigger integration

Acceptance:

- a workflow resumes after host restart without losing completed steps

### Phase 7: First Harness Implementation

Deliverables:

- first `AgentHarness` implementation lands
- if ACP is still the fastest path, ship `ACPAgentHarness` first
- runtime profile selects that implementation

Acceptance:

- at least one useful agent can execute end-to-end through the host

### Phase 8: Native Client Surfaces

Deliverables:

- `Solo` and `Team` scene routing in one app shell
- scene switch in the rail above repositories
- `Team` rail with `Home`, employee contexts, and `Add Member`
- `Team Home` sections for `Overview`, `Board`, `Inbox`, `Automations`, `Resources`, `Hosts`, and `Settings`
- employee sections for `Overview`, `Work`, `Memory`, `Tools`, `Automations`, `Access`, and `Activity`
- employee canvas
- kanban board
- approvals inbox
- activity feed
- host connection UI

Acceptance:

- users can switch between `Solo` and `Team` without leaving the app shell
- users can move between `Home` and employee contexts from the rail without ambiguity about scope
- users can manage the team and its work from the `Team` scene

### Phase 9: Remote Home-Host Mode

Deliverables:

- Mac mini host support
- remote pairing flow
- iOS client connectivity
- APNs or equivalent completion notifications

Acceptance:

- the same team and board appear on MacBook and iPhone against one host

### Phase 10: Hardening And Optional Swaps

Deliverables:

- stronger sandbox implementation if needed
- additional harness adapters if justified
- alternative workflow engine adapter if justified
- memory compaction and retention policy

Acceptance:

- hardening work does not change the product model or client ownership story

### Phase 11: First Concrete Agents

Land these one at a time:

- personal assistant
- engineering manager
- pr reviewer
- pr closeout
- content creator
- ads manager
- twitter manager

Acceptance per agent:

- works on the happy path
- uses explicit grants and approvals
- grows memory across sessions

## Non-Negotiable Rules For This Slice

- no NotificationCenter command bus between host and client
- no service locator on the client
- no mirrored ownership between host state and client reducer state
- no hard-coded design primitives outside `Packages/UI`
- no permanent migration shims
- strict Swift concurrency on host and clients
- one app, one shell framework, two scenes
- one API contract between host and clients
- the product model must not depend on one permanent harness or one permanent workflow vendor

## Strict Acceptance Criteria

The full slice is complete only when all of the following are true:

- a new employee can be authored by editing files under `~/.devys/agents/<slug>/` and shows up on both clients without a restart
- a new employee can also be authored through the UI and round-trips to the same files on disk
- `Solo` remains repo and worktree-scoped and does not expose long-lived employees as repo sidebar content
- `Team` holds the persistent employee roster, boards, approvals, automations, and runs
- solo-MacBook users can run the full stack without a second machine
- Mac mini users can run one host and pair both laptop and phone to it
- a cron trigger fires while the primary interactive user session is not active
- a webhook routes to the correct workflow and the resulting run is visible on both clients
- a workflow that fails in the middle resumes correctly after a host restart
- a destructive tool call is blocked until approved
- an agent's memory grows across sessions and supports cross-session recall
- agent state, memory, and runs live outside the repositories the agent operates on
- no client-side code owns agent, run, task, or memory state as its source of truth
- swapping the harness or workflow engine implementation does not require rewriting the product model
- app hosts stay thin; host-side business logic lives in `devys-host` and host runtime code

## Verification Expectations

At minimum, every landed phase must:

- pass `swift test` in every touched package
- pass `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- pass `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- pass `swift run devys-host --selftest` after the host exists

Manual verification expected at slice closeout:

- install the host as a LaunchAgent and reboot
- confirm the host starts on login
- fire a cron trigger and confirm the resulting run persists
- create an employee, assign it a task, observe the task run, observe memory updated
- switch between `Solo` and `Team` from the rail and confirm the shell preserves the correct scope in each scene
- pair an iPhone and observe a completion notification
- disconnect the remote host and confirm clients degrade clearly
- reconnect and confirm streaming resumes without data loss

## Open Questions

- how long do we retain raw run history before compaction
- which trusted remote transport should be the default for Mac mini mode
- when do we add a stronger sandbox provider
- when is a second harness implementation justified
- when is a workflow engine swap justified
- do we encrypt host data at rest, and if so with what key material

## References

Internal:

- `../reference/architecture.md`
- `../reference/ui-ux.md`
- `../reference/legacy-inventory.md`
- `../active/README.md`
