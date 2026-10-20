# Working on Devys

Read `.docs/DEVYS.md` for product principles and
`.docs/plans/AUTONOMOUS_BUSINESS.md` for the authoritative roadmap.
The 2026-10-19 owner direction supersedes field-service-first and Personal-first
delivery. Read `.docs/README.md` for document ownership. README records what runs
today; target design and historical evidence must remain distinguishable.

## Product priority and model policy

- Build Devys for businesses operated by agents. The first dogfood business's launch is
  the first release; a second business is the next test of generality.
- The delivery plan owns launch sequencing and business-specific work. Do not encode
  one business's tasks into core rules. Field-service parity and wearables remain
  deferred vertical references.
- Support native macOS, iPhone, iPad and web. Surface rule (2026-10-20): web everywhere
  (one `src/surfaces` implementation, hosted in WKWebView on Apple) unless Apple maintains
  the native component (SwiftUI shell and conversation, PDFKit, QuickLook, Speech); the one
  exception is the terminal, native Ghostty on macOS and iOS. Spaces combine persistent app views and
  discussion; apps and records retain domain ownership. Employees operate the
  same capabilities as people. A space is not an implicit permission grant.
- Keep companies independent. A dogfood business integrates through authenticated remote APIs
  and its own domain rules, never sibling imports, direct SQL, shared environment
  files or impersonated human sessions. An SDK is optional.
- Devys ships a built-in tool registry (providers, modelled capabilities, relay
  endpoints, CLI tools, skill bundles) modelled on treg and Executor v2. Neither is
  a dependency; see `.docs/COMPONENTS.md`. Anything consequential is a modelled
  capability, not a relay.
  Check licenses before source reuse. Do not build a speculative marketplace/framework.
- Devys is intended to be open source and use existing models. No model training
  or fine-tuning. Keep Pi's installed provider/configuration boundary: models and
  providers are declared once in `config/models.ts`; employees pick one at setup. Coding
  harness SDKs are explicit delegate adapters, not a new foreground model router.
- Prefer general tools, context, compute, and feedback. Add reasoning scaffolding
  for observed failures, record evidence, and reevaluate it as models improve.
- Preserve separate principals and private context. Memory and external replies
  do not grant authority. Broad account access cannot override task conditions.
- Devys runs in exactly one of two deployment modes, never mixed: **local** (the
  owner's Mac, reached over Tailscale; the owner's default) and **cloud** (Cloudflare).
  Each is one declarative file (`wrangler.local.jsonc`, `infra/api.ts`); `src/app`
  maps `DEVYS_MODE` to an adapter set. No per-component adapter settings.
- Keep self-hosted and hosted versions on the same core contracts. Managed/cloud
  monetization is a hypothesis; arbitrary-infrastructure hosting is not yet promised.

## Simplicity and ownership

- Every major slice passes the [slice gate](.docs/COMPONENTS.md#slice-gate) before
  implementation and before it is marked verified: named need, existing tool
  first, one owner per state, smallest contract, explicit code, no compatibility
  layers, acyclic dependencies, behavioural tests. Record the answers in the plan.
- No backwards compatibility or technical debt: replace, then delete. No dual
  writes, shims, legacy modules or flags for old paths.
- Over-engineering is forbidden. Use supported public library/provider APIs
  before building substitutes.
- Pi owns each employee's working transcript, inbox, steering, model loop,
  compaction, retries, task state and recovery. Derive execution status from Pi. The
  conversations component owns the shared record of what was said in DMs, spaces and
  work threads; employees read it through deliveries and write it through the channel.
- Codex/Claude Code own their delegated coding sessions. Devys owns assignment
  scope, runner handles, authority and accepted artifacts; do not mirror provider
  turns into a second agent run ledger or silently replay uncertain side effects.
- Business records use Postgres through Hyperdrive (PlanetScale in cloud mode, local
  Postgres 17 in local mode), following Closekit's business-data pattern, with plain
  SQL and no ORM. Pi owns Durable Object execution storage; R2 owns bytes. One
  writable authority.
- Use Bidnight's actual PiHarness/Pi Durable pattern. Closekit's request-scoped
  assistant run records are not a Pi runtime implementation.
- Business commitments, outboxes and reconciliation survive stopped agents.
  The dispatcher is wiring: it submits due work to Pi under a stable operation id
  and relies on Pi's idempotent `submit`. No handoff ledger or second scheduler.
  One Durable Object per business employee. Its Pi sessions (one per DM, space or
  work item it takes part in) hold that employee's own reasoning; the shared
  conversation everyone reads is the conversations component's record in Postgres.
- Components are swappable and encapsulated. Each exposes one vendor-free
  `contract.ts`; other modules import nothing else from it. Only `src/app` selects
  adapters. A port exists where a vendor sits behind the boundary or two
  implementations are planned, and every port has a conformance suite run against
  each adapter. Extend `tests/architecture.test.ts` when adding a component.
- Keep domain SQL/migrations, rules and capabilities encapsulated. Use small
  functions, concrete types and explicit dependencies; abstractions need an actual
  boundary or demonstrated reuse.
- Memory callers use its contract. Preserve evidence, revision checks, forgetting
  exclusions and portable migration; adapters cannot query another domain's tables.
- Effect 4 is the Devys capability language. Share validation and authority across
  native tools, Code Mode, HTTP/MCP, views, browser actions and coding delegates.
- Use supported Code Mode and sandbox APIs. Report arbitrary interrupted programs
  truthfully; do not add automatic nested replay or dependency patches to promise
  stronger recovery. Preserve bounded execution, stop and durable-result receipts.
- Keep stable prompt instructions first and automatic context bounded. Discover
  brief capability/skill descriptions, then selected interfaces/instructions.
  Measure context/outcomes before claiming performance gains.
- Reusable abilities are ordinary skills and scripts. Generated code/instructions
  cannot grant authority, change the trusted host or widen connection access.
- Do not add a workflow engine around Pi, a universal business schema, a model
  router, or speculative service layers. Identify the user-visible failure, existing
  library feature and smallest gap before adding machinery.

## Authority and external effects

- Standing delegation authorizes routine work; do not repeatedly ask for permission.
  Preserve narrower conditions, exact recipients/CC, resources, spending limits
  and policy revisions. Owner decisions bind concrete proposal revisions.
- Provider setup and routine implementation are authorized. Missing credentials,
  MFA, CAPTCHA, business verification and provider enablement are external
  dependencies; use secure owner handoffs rather than inventing substitutes.
- `.docs/AUTHORITY.md` owns vocabulary and semantics: grants with capability-typed
  constraints, commitment conditions that only narrow, owner decisions signed by
  Secure Enclave device keys, and credentials held by the broker.
- Payment credentials and connection secrets stay out of models, logs, screenshots,
  ordinary workspaces and generated UI. The broker injects them; agents hold handles.
  Never put secrets in sandbox environment variables. The trusted Mac host (local
  mode) is the stated exception for the owner's own CLI/coding logins and the
  dedicated Devys Chrome profile; payment credentials never reach it.
- Ramp and Stripe Link are distinct supported payment routes. Do not assume a
  Ramp-through-Link chain or silently substitute a payment source. Provider-required
  approval remains required even when Devys business authority exists.
- Record intent, dispatch identity, receipts and uncertainty. Inspect uncertain
  sends, charges, domain orders, account creation and deployments before retry.
  Stop/revocation cannot undo an effect already accepted remotely.
- Use one coding worktree per assignment. Isolation guarantees belong to sandboxed
  runners; the trusted Mac host claims only behaviour guarantees. Separate edit
  authority from repository publication, deployment, purchases and policy changes.
- Account ownership must remain explicit: Devys email is not automatically a business's
  email. A shared owner or local machine does not merge businesses.
- Do not buy subscriptions, publish broadly, accept supplier terms or send through
  personal accounts beyond the relevant authorization. Prepare reviewable results
  before asking for a genuinely missing decision.

## Delivery and verification

Use: planned, implemented, verified locally, verified live, accepted for a stated
release scope, and explicit deferred delivery. Preserve historical evidence.
A screenshot, protocol announcement, fixture or local test is not live acceptance.
Keep provider/interoperability research dated and recheck before integration.
Do not select a release license or claim ready open-source distribution silently.

Use installed versions/current upstream docs; do not silently change the stack.
Add focused regression checks for meaningful behavior. Runtime changes require
`bun run check`, `bun run test`, `bun run test:workers`, and `bun run build`.
`bun run verify` includes format/lint. Use browser/channel checks when affected.
An explicitly requested full closeout uses `bun run closeout`, including browser,
real-model simulated-channel and Docker workspace checks. Optional live Workers
checks use `DEVYS_LIVE_MODEL=1`; report them separately from default-suite skips.

See `.docs/COMPONENTS.md`, `.docs/AUTHORITY.md`, `.docs/CODING_AGENTS.md`,
`.docs/APPS_AND_CAPABILITIES.md` and `.docs/PRODUCT_EXPERIENCE.md` before
implementing their respective boundaries.
