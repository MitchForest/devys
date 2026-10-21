# Devys

**Devys is a platform for businesses operated by agents.** Delegate responsibilities
to employees that use real business software, build and deploy products, manage
accounts and purchases, and handle correspondence within your authority.

Devys is dogfooded by launching and operating real businesses through it. Native macOS/iOS
and web combine persistent app views with contextual conversation. Codex and Claude Code are
delegated coding specialists; Pi Durable is the employee runtime. [AGENTS.md](AGENTS.md)
contains the engineering rules; the design documents and delivery plan are kept outside
this repository.

**Product model.** A business in Devys is four things: its **Team** (employees, each with
ongoing responsibilities), its **Projects** (bounded initiatives with an optional goal,
deadline, budget and lead), its **Apps** (the business's records, the capabilities on them
and the accounts behind them, such as Documents and Code) and **Home**, the owner's seat:
what needs them, a briefing, and the conversation with the Head of Operations. The owner
delegates by talking and reviews by glancing: the conversation is always the middle of the
screen, and the right panel shows what it is about, with records, diffs and pages opening
on top of it.

## What runs today (2026-10-21)

Everything below is implemented and verified locally; employees publishing pull requests is
also verified live. No public product has launched.

- **Two deployment modes, never mixed.** Local mode runs everything on the owner's Mac
  and is reached over Tailscale ([local mode](#local-mode-the-owners-mac)); cloud mode
  runs on Cloudflare with PlanetScale ([cloud mode](#cloud-mode)). `DEVYS_MODE`
  (`local` or `cloud`) selects the whole adapter set in one switch, `src/app/mode.ts`. Local
  mode runs commands and file access on the trusted Mac host; cloud mode uses Cloudflare
  Sandbox.
- **Businesses and teams.** A business has a brief and a starting team. Role templates
  live in code (`src/app/team.ts`: Head of Operations, Engineering, Growth, Business
  Operations, Custom). Hiring copies a template and its grants; employees can be edited
  and retired (open work is handed to a colleague; Operations cannot be retired).
  Operations holds `hireEmployee` in `ask` mode, so its hire proposals arrive as
  decisions. Each employee is one Pi Durable Object running on its chosen model.
- **Authority.** Grants with typed limits in `auto` or `ask` mode; no grant denies.
  Single-use decisions bind the exact input and the work item and are approved in a
  signed-in session. Unanswered requests expire after
  24 hours, checked every minute; an owner's rejection stands for that time, so the same
  request is not asked again. Every call re-reads the grant and the employee, so revoke,
  pause and takeover apply to the next action. Hiring, creating a business and retiring
  are single transactions.
- **Asking the owner.** `askOwner`, a core capability of the Work app every role holds, is
  asked in a work item's thread and returns at once: **approve** an exact action (what, with
  whom, an amount and renewal for a spend) or **take over** (sign-in, 2FA, CAPTCHA in the
  business's browser). Requests are decisions with a kind, listed in Needs you; the answer is
  posted in the thread, which wakes the employee, and asking again with the same input reads
  it. An approve with an amount is a spend approval: only a signature by one of the owner's
  device keys over its canonical payload approves it (the web shows it and cannot sign). The
  Mac and iPhone apps hold a Secure Enclave P-256 key unlocked by Face ID or Touch ID (or the
  Mac's password without biometrics); a person's first key is active at once, a later one once
  an enrolled device allows it in Settings › Devices, and signing a device out revokes its key
  (`bun run local clear-keys` clears them all). Taking the work over answers a take-over
  request; Hand back says it is done. Home's spent is the sum of signed spend approvals (USD).
  Asking first is the employee's instruction and record for free browser or shell actions, not
  something the browser or shell enforces.
- **Projects and work.** Work items with an owner, next action, wait
  condition, conditions and evidence. A one-minute dispatcher hands ready work to its
  employee under `<work item>:<revision>`. A project has an optional goal, deadline,
  budget (a limit; spending arrives with P1), lead and team; its work items belong to it
  (`project_id`) and kept pages and files are references to them. A work item is changed and
  its coding steered only in its own thread (Operations changes work from anywhere). An
  employee's follow-up (`workUpdate` with state `waiting` and `wakeAt`) makes the work ready
  again once, at that time; a due date is only a deadline.
- **Routines.** An employee proposes recurring work (a five-field cron in a time zone,
  optionally within active hours) or work started by an event, for a responsibility or a
  project; the owner's decision in Needs you activates that exact revision. The minute tick
  runs each due slot once (`routine:<id>:<slot>`; missed slots run once, not as a backlog) in
  the project's channel or the employee's direct chat. A quiet routine that finds nothing
  posts nothing and is counted in the briefing. The owner pauses and resumes routines; a
  retired employee's routines pause. Event routing (`routeEvent`) has no source connected yet.
- **Apps.** `src/apps` lists Devys apps as literal manifests: Documents and Code are
  installed for every business. An app's capabilities are hidden from employees and refused unless the app is
  installed, as well as granted. The owner installs, removes and pins apps in Settings.
- **Home.** `GET /home` returns what needs the owner (pending decisions, work needing a
  decision) and the business at a glance (moving, stuck). When the owner returns after
  eight hours, Operations' briefing (done, moving, stuck) is posted in their direct chat
  from records, without starting any turn.
- **Conversations.** One shared record (Postgres) per direct chat (`direct:<employee>`),
  project channel (`project:<project>`) and work item thread (`work:<work item>`). Who answers: an owner message
  goes to those it @mentions, else to the employee it replies to, else to whoever last
  spoke, else to the default (the DM's employee, the project's lead, the work item's
  owner). An employee's message wakes only colleagues it @mentions, and the asker when
  it answers a request that mentioned it. At most three employee turns in a row between
  owner messages. An addressed employee sees up to 20 messages of catch-up in its own Pi
  session for that conversation; its reply returns through the channel into the same
  conversation. Posting where every responder is paused returns 409.
- **Channels.** The Devys apps (web, macOS, iPhone, iPad), the work dispatcher and
  iMessage through Photon. iMessage messages and the employee's iMessage replies are
  recorded in that employee's DM conversation. iMessage is optional and has not been
  tested against a real Photon account.
- **Clients.** One sidebar of Home (with what needs the owner), Projects (threads that
  need the owner or that they follow nested under each), Team (status and unread) and the
  business's apps. The middle is always a conversation: Home is the direct chat with
  Operations, then a project's channel, a direct chat or a work item's thread, with the
  face of whoever answers inside the field (tap to choose someone else), a placeholder
  naming them, @-autocomplete, a mic that dictates and, in an empty field, a button that
  starts a hands-free conversation. The right panel shows that conversation's permanent view (Needs
  you, the employee's desk, the project overview, the work card), remembered open or
  closed per kind, with layers stacked above it: pages with their versions, files, the
  Documents and Code apps, coding sessions and the live browser. A page published in reply
  opens on its own and a new version replaces it in place; **Start a thread** on a message
  creates a work item; **Ask** quotes a selection into the composer; the open layer goes
  with the next message as a reference. Phones have Home, Projects, Team and Apps tabs
  with the panel and layers as sheets. Dictation and hands-free voice, looks stored on the
  server, ⌘K and Settings (with Apps & connections).
- **Memory and files.** Business memory with evidence and forgetting; saved artifacts in
  R2; selected-file Google Drive access.
- **Coding sessions (local mode).** From a work item, an employee starts Codex (through
  `codex app-server`) or Claude Code (through the installed CLI) in its own git worktree
  and branch, on the owner's own logins (`DEVYS_CODEX_HOME`, `DEVYS_CLAUDE_CONFIG_DIR`).
  Each turn's end, failure, interruption and check is a card in the work item's thread and
  wakes the employee (not while a person holds the work: it is briefed once on hand-back), which
  steers with follow-ups, starts read-only reviews, and accepts:
  Devys commits on the branch, runs the repository's check and records commit and check as
  evidence. Employees can then push the accepted commit and open a pull request on the
  business's GitHub repository (`codingPublish`, through the owner's `gh` login, only after
  a passing check); nothing is merged or deployed. Completing work with a coding build also
  needs a passing check. The owner sees each session's latest reply and live diff on every
  client, takes over to steer it directly ("Taken over by <name>" for everyone else), hands
  back, or starts a **New coding session** from Work (web, macOS, iPad). A finished result
  reads as one line (check, files changed, pull request, commit) that opens the full evidence;
  a session's **Details** show what the agent did (prompts, replies, plan, commands, edits), read
  from Codex or Claude Code when opened and never stored. **Follow** a work item to keep it in
  the sidebar and see each step; a signed-out CLI says how to sign in, and approvals Codex asks
  for are declined and reported. Employees deploy accepted, checked work with the repository's
  own deploy command: previews on their own (`deployPreview`), production only with the owner's
  approval (`deployProduction`). Each deploy runs at exactly one commit in a fresh worktree, then
  Devys checks the URL answers and records stage, commit and URL; rolling back deploys an
  earlier commit of the same work item. Stage secrets live in a private host-side file per
  business (`bun run local deploy-env <business>`) and reach only that deploy process, redacted
  from its output. Diff line comments are always
  sendable: to the session while you have taken it over, otherwise as one review message in
  the work item's thread. A work item's panel shows its pending and decided requests. Stop
  interrupts sessions and stops what they left running. Cloud mode reports coding as
  unavailable.
- **Terminals (local mode).** A terminal on the owner's Mac (the business folder, a work item's
  worktree, or Codex/Claude Code's own CLI resumed on a coding session) opens in its own window on
  web, macOS and iPad and full screen on iPhone, rendered by Ghostty (native, or WebAssembly on the
  web). The Mac keeps the session; any device reattaches from where it left off and one types at a
  time (Take control). Opening one on a work item takes it over.
- **Files (local mode).** The business folder on the Mac on every client: markdown documents edit
  in place and save over the revision they were opened at (a change on the Mac refuses a stale
  save), and so do spreadsheets (Univer; xlsx, xls and CSV keep values and formulas, not styling),
  markdown slide decks (Marp slides beside the source, exported to `.pptx`) and Excalidraw
  whiteboards, on web, Mac, iPad and iPhone. PDFs, Word, presentations, code and images open in
  viewers (PDFKit and QuickLook on Apple). Any file can be kept in a project; comments on a text
  range or a PDF region go to an employee or a work item's thread as one message. Employees print HTML to PDF with the
  Mac's Chrome (`printPdf`).
- **Browser (local mode).** Each business has its own visible Chrome on the Mac with its own
  profile, so a site the owner signs in to once stays signed in for that business only. The host
  starts it and drives it, over its DevTools pipe (no debugging port), with Browser Use's
  [browser-harness-js](https://github.com/browser-use/browser-harness-js) (MIT). Employees run
  scripts against the page (`browserScript`: any DevTools Protocol command, in an isolate with
  no network, kept to web pages and the business's own folder), see it (`browserScreenshot`,
  a picture the model reads) and manage tabs (`browserTabs`); the Browser app's
  `using-the-browser` skill has the recipes. A work item driving the browser shows it on its
  panel with a live picture on every client, where Take over stops the employee, mid-script
  too, and lets the owner click and type (not recorded) until Hand back.
- **Pages.** Employees publish self-contained HTML pages (`artifactPage`, `artifactEdit`):
  reports, comparisons, dashboards. A card in the conversation opens the page in an
  opaque-origin sandbox that fetches nothing; **Keep** lists it on a project's overview.
- **Not built:** confining employee processes away from the host's own data folder
  (`~/Library/Application Support/Devys Server/host`), `askOwner` secret requests,
  scripted browser control with screenshots, secrets by name in a vault, event sources
  (mail), the Knowledge app and a learning loop, the event stream and push, connections for
  outside providers, mail, purchases, desktop control, the voice and ambient additions, cloud
  mode's coding runners, files, terminals and browser, community and custom apps, and
  distribution.

The prior Pi/Effect refinement and
iMessage acceptance guide retain foundation
evidence and relevant live checks; they no longer own product sequencing.

## Accounts and operating model

A self-hosting operator needs a key for the model gateway in `config/models.ts`
(TrueFoundry by default, `DEVYS_MODEL_GATEWAY_KEY`). Local mode needs nothing else
except Tailscale on the Mac and the owner's devices. Cloud mode also needs Cloudflare
and PlanetScale in the Alchemy profile. Photon (iMessage) and Google OAuth (Drive) are
optional in both.

See Accounts and operating model for ownership,
configuration, provider prerequisites, and the distinction between today's
operator-enrolled product and a future paid service. Open-source distribution is
an ongoing intent; the repository does not yet contain a project license.
Self-hosted and hosted versions share core contracts. Hosting, managed operations,
and support are monetization hypotheses; pricing remains open. Hosted signup,
billing, and automated customer provisioning are not implemented.

## Verification status

On 2026-10-21, on the owner's MacBook standing in for the Mac mini, after the alignment pass:
`bun run verify` (format, lint, types, 146 unit tests, 4 Bun host tests, 142 Workers tests of
which 4 more are live-model tests skipped by default, build), `bun run test:browser` (18),
`bun run test:apple` (DevysKit and DevysTerminal tests including 36 server-generated wire
fixtures, both builds, strict lint), `bun run test:channel` and `bun run test:workspace`.
The native apps have not been walked through on a simulator since the alignment pass.
Live: a conversation with real models routed by the rules (Engineering consulted Growth by
@mention and got the answer back), and an employee opened a real pull request through
Devys. Each slice's evidence is in the delivery plan.

Not yet verified:

- HTTPS Tailscale Serve and Funnel (the tailnet admin has not enabled Serve; the TCP
  forward works and the iPad signs in through it).
- The conversation-first, coding, terminal and document screens by hand on the physical
  iPad and Mac (the Mac app has not been driven by hand since the conversation-first shell),
  and an accessibility pass (VoiceOver, Dynamic Type, keyboard).
- A live run of projects, Home and kept pages with a real model.
- Plain HTTP to the tailnet name from a physical iPhone.
- iMessage end to end (no Photon credentials configured).
- A cloud deploy of the local-mode slices onward, a real reboot of the Mac, and a coding
  turn across the Mac sleeping.

Workers tests substitute workspace storage. `test:workspace` builds the actual
Linux image and checks script/file work and reuse across fresh containers with a
shared local test directory; it does not establish Cloudflare snapshots or R2
restoration. The channel test simulates Photon and sends no real iMessages.

## Current capability boundaries

- Public HTTPS reads are bounded raw content. No web search integration; the business
  browser is local-mode only.
- Recall uses the replaceable memory API (Postgres today), with bounded keyword and
  relationship lookup. Pi owns each employee's transcript and compaction.
  `conversationHistory` pages back through the shared conversation the current turn
  answers, 30 messages at a time; the trusted host picks the conversation, never the model.
- Google Drive supports selected text files and Google Docs exports up to 64 KB.
  Outputs are plain-text files; updates require the current file ETag. Native
  Google Docs editing, arbitrary binary files, and broad Drive access are excluded.
- In local mode, employees' commands run on the owner's Mac as the owner. In cloud mode,
  workspace restart uses a saved snapshot; automatic fallback to an R2 backup is not
  implemented and real Linux persistence has not passed live acceptance.

## Apps, capabilities and skills

Everything an employee or the owner can do is a capability owned by exactly one app
(`src/apps/<id>/app.ts`, declared with `defineApp`): the system apps Computer, Browser,
Web, Memory, Conversations, Work and Team, always installed, and the business apps
Documents and Code, installed per business. Records are referred to by one `Ref`,
`devys:<app>/<kind>/<id>`. Tests enforce that every capability belongs to exactly one app
and every `Ref` kind to exactly one app's records.

The initial direct tools are the `core` capabilities (`read`, `write`, `run`,
`readSkill`, `recall`, `remember`, `forget`) plus `describe_capabilities` and
`execute`. Discovery without names returns the granted capability catalog; selected
names return only those interfaces and activate native Pi tools. Both direct and
composed calls pass through Effect. New idle admissions return to the small tool set;
pending work keeps its loadout. Automatic memory context is capped at 4,000 characters,
with deeper `recall`.

Skills use the Agent Skills format: a folder with `SKILL.md` (YAML `name`, matching the
folder, lowercase letters/numbers and hyphens up to 64 characters, and a `description` of
at most 300 characters; at most 16 KB), followed by instructions and supporting scripts.
Apps ship skills in `src/apps/<id>/skills/` (Documents ships `writing-pages`); employees
write the business's own in `~/Devys/<business>/skills/` in local mode and
`/workspace/skills/` in cloud mode. Every employee's prompt lists up to 32 available
skills by name and description; `readSkill` loads one, and the business's skill wins over
an app's of the same name. Edits need no deployment. Skills cannot grant authority and
must not contain credentials.

## Model configuration

`config/models.ts` is the one place models and providers are declared. A provider is a
base URL plus the name of the secret holding its key; models are listed against it, each
with its API format, effort and a one-line summary. Models pi-ai already knows inherit
its catalog entry (effort mapping, caching, limits, price); others spell those out. The
defaults route Anthropic, OpenAI and Google models through one TrueFoundry gateway with
`DEVYS_MODEL_GATEWAY_KEY`; add an OpenRouter or direct-provider entry the same way.

Every employee runs on a model chosen when it is set up (`PUT …/employees/:id/model`
changes it; the apps show a picker with the price of a typical turn). New employees get
`defaults.employee` (Claude Opus 5.5); background work such as memory consolidation uses
`defaults.background` (GPT-6 Luna). Conversations compact before `workingContext`
(200k) tokens and a response may use up to `maxOutput` (32k). `GET /api/models` lists
the choices without keys. Run `bun run doctor` to check every model loads and its key
is present. Model arguments never select credentials.

## Active roadmap

Next is the **Launch path**: Devys builds only what agents cannot safely build for themselves
(trust boundaries, the ways the owner is brought in, a few strong general tools) and then runs
a real business launch with its employees. In order:

1. Confinement: employee processes on the Mac cannot reach the host's data (browser profiles,
   deploy secrets).
2. `askOwner`, one core capability for bringing the owner in: approve an exact action (with an
   amount, a spend approval signed with Face ID or Touch ID on the owner's Mac or iPhone), take
   over the business's browser (sign-in, 2FA, CAPTCHA), or enter a secret. All appear in Needs
   you. Built except secrets (above); its live step on the Mac and iPhone remains.
3. The business's browser driven through Browser Use's browser-harness-js (scripts,
   screenshots the model sees, tabs), replacing Playwright; the live view and Take over stay.
4. Secrets by name in an envelope vault (master key in the Mac's login Keychain, or a
   Cloudflare secret in cloud mode), injected by the host into one command, request or
   browser field and redacted from output; a card is filled only against a signed spend
   approval.
5. Minimal onboarding, and the empty "coming" apps removed.
6. The launch run itself: buying a domain, mail and DNS, a supplier inquiry, a website deploy,
   analytics, social accounts, and a change shipped through a pull request, CI and an
   approved merge.

Then the Knowledge app and a learning loop, a live event stream and push, voice, cloud mode
and coding runners, and distribution; connections in the app platform, mail, purchases,
desktop control and the app directory are built when a run shows the need.

## Native clients (macOS, iPhone, iPad)

`apple/` holds the SwiftUI clients: an XcodeGen project, the `DevysKit` Swift
package (design system, the Face, HTTP client, TCA26 features) and two app
targets, macOS and universal iOS. They need Xcode 27, `xcodegen` and `swiftlint`.

Everything the apps show is real server data; there is no sample data. Sign-in
exchanges a one-time code at `POST /api/native/session` for a bearer session kept in
the Keychain. The first code comes from `bun run local code` (local mode) or
`bun scripts/enroll.ts`; Settings → Devices then issues a ten-minute code as a QR code
and a `devys://enroll?server=…&code=…` link, which the iPhone and iPad open directly.
The device list signs any device out.

Settings (⌘, on macOS; the account or business menu on iPhone and iPad):

- **Account:** a profile photo, stored on the server at `/api/profile/photo` under
  the owner's key in R2.
- **Team and Businesses:** looks, which can be the Face (shape and color), an
  emoji on a tile, or a photo, stored on the server. Photos can be dropped onto the
  preview or chosen from Photos or a file.
- **Devices:** sign another device in; sign devices out.
- **Appearance:** system, light or dark.

The design system (`DevysDesignSystem`) follows
the design direction. Debug builds open a Design
Gallery from the Debug menu (⌥⌘G), or as the whole window with `DEVYS_GALLERY=1`.
`DEVYS_PLACE` (`direct:<id>`, `project:<id>`, `thread:<id>` or `palette`), `DEVYS_LAYER`
(`app:<id>`, `artifact:<id>`, `file:<path>`), `DEVYS_PANEL=open` and `DEVYS_SIDEBAR=hidden`
open a screen at launch, and `DEVYS_SETTINGS` (`account`, `apps`, `team`, `businesses`,
`appearance`) opens Settings, all for screenshots in debug builds.

```sh
bun run dev:local                     # development server on 127.0.0.1:5173
bun scripts/enroll.ts --name 'Your name' --out /tmp/devys-code.txt
cd apple && xcodegen generate && open Devys.xcodeproj
bun run test:apple                    # package tests, both builds, strict lint
```

Debug builds accept `DEVYS_ENROLL_SERVER` and `DEVYS_ENROLL_CODE` to sign in at
launch through the same exchange, for screenshots without UI scripting
(`SIMCTL_CHILD_` prefix for simulators).

Signing: put `DEVELOPMENT_TEAM = <your team>` in `apple/Local.xcconfig`
(gitignored). Without an Xcode account the Mac build has no keychain access
group, so the session uses an app-scoped login-Keychain item. Reads never show a
Keychain password prompt; an item macOS won't hand over silently reads as signed
out. A team-signed build keeps the same identity across rebuilds, so the session
survives them. Signing in to Xcode with an Apple ID enables provisioning, which
allows the data-protection Keychain.

## Development

Use Bun and Node 24 or newer:

```sh
bun install --frozen-lockfile
cp .env.example .env
bun run check
bun run test
bun run test:workers
bun run build
bun run closeout
```

Populate `.env` locally; never commit it. Vite's Cloudflare plugin copies dev
secrets to ignored `dist/server/.dev.vars`. Deploy through Alchemy rather than
sharing the build directory as an archive.

`bun run dev:local` starts a project-local Postgres 17 (`brew install postgresql@17`)
in `.pgdata/` on port 54331, applies migrations and serves the app through a local
Hyperdrive binding. No provider account is needed locally.

```sh
bun run dev:local
bun run db status   # also: start, stop, migrate, reset, url
```

`dev:local` uses its own cluster on port 54331, separate from local mode's (54330). It
does not start the Mac host, so file and command tools report that the host is not
configured; use `bun run local` for those. Cloud-mode Linux execution requires working
Docker and an Alchemy development stage.

Additional checks:

```sh
bun run test
bunx playwright install chromium
bun run test:browser
DEVYS_LIVE_MODEL=1 bun run test:workers tests/pi.workers.test.ts
bun run test:channel
bun run test:workspace
```

The opt-in Workers and channel checks make real model calls through the configured
gateway with the local key.
`closeout` runs format, lint, types, unit/Workers, build, browser, channel and
Docker workspace checks. The normal Workers suite skips its optional live-model
tests; enable them separately as shown above. Browser and
channel tests use the local Postgres database and clean up synthetic owners. The
browser uses `.wrangler/state` for R2; the channel test uses `.wrangler/channel-state`.
Workers tests recreate and migrate a separate `devys_test` database on each run and
reach it through the Workers pool's Hyperdrive binding, without external credentials. Workers
tests use pinned Vitest 4 for Cloudflare test-plugin compatibility; Vite+ handles
builds and formatting. Code Mode is unpatched.

## Local mode (the owner's Mac)

Local mode runs all of Devys on one always-on Mac and reaches it from other devices
over Tailscale (deployment modes). It uses
the same built Worker as cloud mode, in Wrangler's local Workers runtime, with its
own Postgres 17 cluster on port 54330 and its data in
`~/Library/Application Support/Devys Server` (outside the checkout). Employees work on
the Mac itself, as the owner: commands run in the owner's login shell with the owner's
tools and logins, starting in `~/Devys/<business>`, and can use any of the owner's files.

```sh
bun install --frozen-lockfile
bun run local install    # build, copy the app, publish on the tailnet, start at login
bun run local status     # shows the address other devices use
bun run local code       # a one-hour sign-in code and devys:// link for the owner
bun run local webhooks   # only when a provider must reach /webhooks/ (Tailscale Funnel)
bun run local backup     # also runs nightly at 03:00
bun run local uninstall  # stops it; data is kept
```

`install` reads secrets from `.env` like development does. Re-run it after pulling
changes. The launcher (`scripts/local.ts`) supervises two processes: the Worker on
127.0.0.1:8787 and the Mac host (`src/host.ts`) on 127.0.0.1:8788, which runs employees'
commands, file access, coding sessions and terminals behind a token. The token is written
to the Worker's vars file, not its command line. The host's environment excludes what
`.env` supplies (the model gateway key and other secrets) and its own `DEVYS_*` settings,
so employees' shells, coding sessions and terminals see neither. The launcher calls the
scheduled handler every minute so unanswered decisions expire, follow-ups wake, ready work is dispatched and due routines run.

Because employees work as the Mac's owner, only that person (the earliest active person,
the one `bun run local code` signs in) can create businesses and open coding sessions,
terminals and files on the Mac from the apps. The owner's file views stay inside the
business folder, with symbolic links resolved.

Other devices on the tailnet sign in to `http://<this Mac>:8787` (a Tailscale TCP
forward, encrypted by WireGuard, no admin step). When the tailnet admin enables Serve,
the launcher switches to the HTTPS name within ten minutes (it retries Serve every ten minutes); browsers need that, because
the web session cookie is `Secure`.

Prepare the Mac once: never sleep, restart after power failure, log in automatically
(FileVault off), Screen Sharing and Tailscale on. HTTPS Serve and Funnel have not yet
been verified on the owner's tailnet.

## Cloud mode

Provide Cloudflare and PlanetScale authentication in the Alchemy profile and
`DEVYS_MODEL_GATEWAY_KEY`. iMessage is optional: `PHOTON_HTTP_ADDRESS`, `PHOTON_TOKEN`
and `PHOTON_WEBHOOK_SECRET` default to empty, and without them `/webhooks/photon`
answers 503 while the apps keep working. `PHOTON_SERVER` names a dedicated instance.
`bun run doctor` checks every model loads and its key is present, and lists the optional
settings.

```sh
bun run doctor
bunx alchemy plan --stage dogfood --no-input
bunx alchemy deploy --stage dogfood
```

Each stage declares its own PlanetScale Postgres database (migrations applied by
Alchemy's migration role), a data-only application role, a Hyperdrive connection
with caching disabled so authority checks never read stale data, a private R2
bucket, the Pi agent Durable Object, a Dynamic Worker loader, a one-minute cron for the
dispatcher, and up to three Linux containers. There is no second durable Code Mode
runtime. Product enablement may be required; subscription purchases are not automated.
No stage has been deployed with the current slices.

To use iMessage, point Photon's signed Spectrum message webhook at `/webhooks/photon` on
the deployed URL. Only inbound one-to-one messages whose exact sender/chat pair is
bound to an employee can run work. Validate that native Spectrum event IDs map to the
message, sender, and chat identifiers expected by the Advanced iMessage HTTP client. The
simulated channel test does not prove compatibility with the provisioned Photon
service. See the iMessage acceptance guide.

Enroll the owner through the maintenance script:

```sh
bun scripts/enroll.ts --name 'Your name' --owner --out /private/path/devys-access-code
```

For a deployed stage, add `--database-url` with a PlanetScale connection string for
a role that may write identity records. The script writes a single-use access code
with mode `0600`, valid for one hour, and refuses to overwrite a file. `--owner` signs
in as the earliest active person; `--person UUID` issues a fresh code for an existing
active person.

After signing in, create a business from the apps or `POST /api/businesses` with a
`name`, optional `brief` and optional starting `team` (`engineering`, `growth`,
`business-operations`); its Head of Operations starts with the operations template's
grants. Bind an iMessage chat to an employee with
`POST /api/businesses/:id/employees/:employee/channels` and
`{"channel": "imessage", "sender": "+15551234567", "chat": "any;-;+15551234567"}`.
A chat already bound elsewhere is never transferred. Web enrollment creates a secure
HttpOnly same-site session lasting seven days.

## HTTP API

Everything under `/api/` needs a web session or a device bearer token; business routes
404 for non-members. Main routes:

- `/api/me`, `/api/models`, `/api/roles`, `/api/devices` (`/codes` issues a code),
  `/api/device-keys` (an app enrolls its signing key; `/:id/endorse`, `/:id/revoke`),
  `/api/profile/photo`, `POST /api/businesses`.
- `/api/businesses/:id`: `GET` (the business, its employees, `members` and artifacts)/`PUT`
  (name, brief), `/look`, `POST /employees` (hire), `/export`, `/memory`, `/work` (create,
  update at a revision, `takeover`, `release`), `GET /decisions` (pending;
  `?workItem=<id>` lists one work item's requests with their answers),
  `/decisions/:id/approve|reject` (a spend approval's approve carries the device signature),
  `/projects` (and `/projects/:id/items`), `/apps` (and
  `install`, `uninstall`, `pin`), `/home`, `GET /coding` (work with coding sessions),
  `/artifacts/:id`,
  `/connections/google/…`.
- `/api/businesses/:id/conversations`: `GET` lists conversations with unread counts;
  `GET …/:key` returns a page of messages and who would answer; `POST …/:key/messages`
  posts; `POST …/:key/read` marks it read.
- `/api/businesses/:id/employees/:employee`: `/profile`, `/look`, `/model`, `/retire`,
  `/status`, `/stop`, `/pause`, `/resume`, `/access`, `/channels`, `/reactions`.
- Unauthenticated: `/health`, `/api/enroll`, `/api/native/session`, `/api/logout`,
  `/webhooks/photon`.

## Google Drive setup

The operator configures one Google OAuth web application. Each owner then
connects their own account and chooses files in the private workspace.

1. Enable Google Drive API and Google Picker API in the same Google Cloud project.
2. Configure OAuth consent and an OAuth client of type **Web application**. During
   testing, add your Google account as a test user. Set the authorized redirect URI
   to `https://YOUR_DEPLOYED_HOST/api/connections/google/callback` and the authorized
   JavaScript origin to `https://YOUR_DEPLOYED_HOST`.
3. Put `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_PROJECT_NUMBER`, and
   `GOOGLE_PICKER_API_KEY` in `.env`. Restrict the Picker browser API key to your
   application origin and Google Picker API. It is intentionally sent to the browser.
4. Generate `CONNECTIONS_KEY` with `openssl rand -hex 32` and save it in `.env`.
   Keep this key stable and backed up privately. Replacing it makes stored grants
   unreadable; owners must reconnect. Redeploy through Alchemy.
5. Sign in to Devys, choose **Connect Google Drive**, grant the `drive.file` scope,
   then use **Choose files**. Only selected files and Devys-created files are
   available through tools. Ask an employee: “Use my selected documents to write
   a comparison and save it to Drive as comparison.txt.”
6. Follow up later to update that text file, then disconnect. Further Drive tool
   calls must fail while the conversation and private artifacts remain available.

OAuth uses `oauth4webapi`, state tied to the active owner/session, and PKCE.
Refresh tokens are encrypted in Postgres with owner/grant-bound AES-GCM. Models and
workspace programs never receive tokens. The authenticated Picker receives a
short-lived access token; it is not saved in browser storage. Disconnect removes
local access immediately and attempts Google's token revocation, reporting if
Google does not confirm it. A write already accepted remotely cannot be undone.

Writes record intent before network dispatch. An interrupted write returns an
uncertain outcome and its file ID; inspect that file before requesting another
write. Repeating the same operation only inspects an uncertain result. Updates
send `If-Match` with the ETag from `driveRead`; a changed file must be read again.
The real Google consent/Picker round trip and Drive ETag behavior still need
live validation with the configured OAuth application.

References: [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth),
[Google Picker](https://developers.google.com/workspace/drive/picker/guides/overview),
[OAuth web applications](https://developers.google.com/identity/protocols/oauth2/web-server).

## Execution and interruption

The channel adapter persists message preparation before acknowledging ingress.
Attachments are saved to R2, then imported into the workspace through an Effect
capability when the agent uses them. Preparation never writes into the active
workspace. Pi receives a stable operation ID, owns the queue, and deduplicates
submissions. Devys's channel job waits for Pi's answer and delivers it; it does
not run a second agent loop. Status derives from Pi's records.

Direct reads and idempotent capabilities use Pi's safe replay policy. Shell
execution and arbitrary Code Mode programs use its unsafe policy: interruption
is reported to the model rather than automatically replayed. The model must
inspect existing state before continuing. Shell receipts reuse recorded results
and report an unfinished command as uncertain. This does not promise exact
resumption of nested program calls.

Only the trusted host chooses the owner and workspace. Every capability checks
Effect schemas and authority. Code Mode has no direct networking. Public HTTPS
reads and package downloads pass through bounded host gateways without service
credentials or application cookies.

Exact `stop` or `/stop` messages cancel previously received work; `status` or
`/status` reports activity. Other messages enter Pi as follow-ups. Stop aborts
Pi and destroys an active workspace container. A pure JavaScript pass can take
up to its 120-second executor timeout to finish; cancelled capability calls
cannot start further authorized work.

Bounds: ten minutes from message receipt including queue time, 90-second model
requests with the configured output cap (`maxOutput`, 32k), up to two Pi retries, 80 capability calls per
Code Mode program, 60-second shell commands, 64 KB retained per output stream,
and 20 MB per artifact/attachment. Pi owns compaction and token/cost accounting.
These are execution limits, not a prepaid spending guarantee.

The reply adapter saves outbound intent before sending and reuses the same
Photon `clientMessageId`. A documented `duplicateMessage` response confirms the
prior send. After five unresolved attempts, delivery stays visibly uncertain.
Messaging access is rechecked before sending; sent does not mean recipient-read.

## Files and basic recovery

When Pi settles and the conversation is idle, the adapter attempts a workspace
checkpoint: `/workspace` to R2 through the Sandbox SDK, then a filesystem
snapshot. A new container starts from the stored snapshot. Snapshots do not
preserve processes or memory and expire; `restoreBackup()` is a trusted RPC for
restoring the last directory backup into a fresh image. Automatic fallback from
an unavailable snapshot is not implemented. Real restore validation is pending.
Important artifacts remain available independently of the container.

Postgres holds application records. Back up a deployed stage with PlanetScale's
backups or `pg_dump`, and restore into an empty database with dispatch paused
before relying on it. Keep dumps private. Alchemy owns remote migrations;
`bun run db migrate` applies them locally with the same migration table.

```sh
pg_dump "$(bun run --silent db url)" > /private/path/devys.sql
```

Pi and channel state live in Durable Object SQLite; Postgres backups do not
restore them. Use Cloudflare's supported object recovery when needed, pausing
admission and delivery before reconciling external effects. R2 files and their
Postgres metadata belong together. A comprehensive coordinated restore drill
and automatic backup retention are later operational work, not dogfood gates.

`GET /api/businesses/:id/export` streams one business as NDJSON: every shared
conversation message (direct chats, project channels, threads), each employee's own Pi history for its
direct chat, current memory, the artifact index and the selected Drive file index.
Credentials are excluded. Download artifact bytes separately. A final `complete`
record identifies a finished export. This is a data export, not a coordinated runtime
image.

To revoke a person, set `people.revoked_at = now()` in Postgres. Sessions, channel
lookup, model dispatch, and capabilities recheck it. Revocation cannot undo an
operation already accepted by an external destination.

## Modular memory

Memory is an owner-scoped, replaceable Effect subsystem. It learns useful facts
from authenticated conversations, applies explicit corrections immediately,
consolidates in the background, and injects bounded business context into Pi.
Claims preserve evidence, scope, dates and named relationships. Forgetting removes
selected knowledge and suppresses supporting sources from future learning;
original conversation retention is separate.

The architecture records module ownership and dependency
boundaries. The memory plan and API reference documents
management routes, budgets, failure behavior and portable export/import:

```sh
bun scripts/memory.ts export memory.ndjson
bun scripts/memory.ts import memory.ndjson
```

These commands use a private `DEVYS_URL` / `DEVYS_SESSION` environment. Apply
migrations before using new code. Local learning and migration checks remain
separate from the outstanding live-provider acceptance requirements above.
