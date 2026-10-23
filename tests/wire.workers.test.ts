import { env } from "cloudflare:workers";
import { Effect, Schema } from "effect";
import { expect, inject, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { codingRoute } from "../src/app/coding.ts";
import { postEvent, showWorkCard } from "../src/app/conversations.ts";
import { postMessage, suggestReplies } from "../src/conversations/service.ts";
import { browserRoute } from "../src/app/browser-route.ts";
import { filesRoute } from "../src/app/files.ts";
import { apiRoute } from "../src/app/http.ts";
import { terminalRoute } from "../src/app/terminals.ts";
import * as wire from "../src/app/wire.ts";
import { Transcript, WorkingDiff, type CodingHost } from "../src/apps/code/contract.ts";
import { recordCodingSession, recordStarted } from "../src/apps/code/service.ts";
import { askOwnerFor } from "../src/app/asking.ts";
import { secretsRoute } from "../src/app/vault.ts";
import { DeviceKey } from "../src/authority/contract.ts";
import { grant } from "../src/authority/service.ts";
import { BrowserStatus, PageState, Screenshot } from "../src/browser/contract.ts";
import {
  DeviceList,
  Employee,
  Hello,
  JoinRequest,
  JoinRequests,
} from "../src/identity/contract.ts";
import { DeviceSession, SignInLink } from "../src/identity/http.ts";
import { ClaimPage } from "../src/memory/contract.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { ref } from "../src/protocol/ref.ts";
import { TerminalSession } from "../src/terminal/contract.ts";
import { Project, ProjectItem, Routine, WorkItem } from "../src/work/contract.ts";
import { activateRoutine, proposeRoutine } from "../src/work/routines.ts";
import { addEvidence, createWorkItem, updateWorkItem, workItem } from "../src/work/service.ts";
import { addRemoteApp, connectedRemoteApp, lapseRemoteApp } from "../src/apps/remote.ts";
import { FileText } from "../src/workspace/contract.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

/**
 * Golden JSON for the native client (AL4): representative data through the real routes, each
 * response decoded with its schema, normalized and compared with the committed files that
 * `DevysClientTests` decode. `bun run wire:write` (`DEVYS_WRITE_WIRE=1`) rewrites them.
 */
const fixtures = import.meta.glob<string>(
  "../apple/Packages/DevysKit/Tests/DevysClientTests/Fixtures/wire/*.json",
  { eager: true, query: "?raw", import: "default" },
);
const committed = (name: string) =>
  fixtures[`../apple/Packages/DevysKit/Tests/DevysClientTests/Fixtures/wire/${name}.json`];

/** Ids become stable placeholders in the order they are first registered or met. */
const ids = new Map<string, string>();
const uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;
const register = (id: string) => {
  if (!ids.has(id))
    ids.set(id, `00000000-0000-4000-8000-${(ids.size + 1).toString().padStart(12, "0")}`);
  return ids.get(id)!;
};
const tokens = new Map<string, string>();
/** Random hex the server makes (device ids, codes, digests) becomes fixed hex of the same length. */
const token = (value: string) => {
  if (!tokens.has(value))
    tokens.set(value, (tokens.size + 1).toString(16).padStart(value.length, "0"));
  return tokens.get(value)!;
};
/**
 * Timestamps get a fixed value in their one form (ISO in UTC with milliseconds; the schemas
 * refuse any other), and a timestamp in any other form fails the comparison.
 */
const instant = /"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"/g;
const normalized = (value: unknown) =>
  `${JSON.stringify(value, null, 2)
    .replace(uuid, register)
    .replace(/\b[0-9a-f]{64}\b/g, token)
    .replace(/"([0-9a-f]{16})"/g, (_, hex: string) => `"${token(hex)}"`)
    .replace(instant, '"2026-01-01T00:00:00.000Z"')}\n`;

const sink = inject("wireSink");
const golden: { name: string; text: string }[] = [];
/** Decodes a response with its schema, then keeps it, normalized, as `<name>.json`. */
async function keep<T, E>(name: string, schema: Schema.Codec<T, E>, response: Response) {
  expect(response.ok, `${name}: ${response.status}`).toBe(true);
  const body: unknown = await response.json();
  const decoded = Schema.decodeUnknownSync(schema)(body, { onExcessProperty: "error" });
  golden.push({ name, text: normalized(body) });
  return decoded;
}

const hostUrl = "http://127.0.0.1:1";
const local = {
  ...env,
  DEVYS_MODE: "local",
  DEVYS_HOST_URL: hostUrl,
  DEVYS_HOST_TOKEN: "host-token",
  DEVYS_HOST_HOME: "/Users/owner",
} as unknown as Env;

it("every route the clients read answers in its wire schema; the golden files match", async () => {
  const { person, business: acme, chiefOfStaff, scope } = await business("Acme Plumbing");
  [person, acme.id, chiefOfStaff.id].forEach(register);
  const sessionToken = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', 'iPhone')",
    [await sha256(sessionToken), person],
  );
  const received: string[] = [];
  const bindings = {
    ...env,
    AGENT: {
      getByName: () => ({
        receive: async (_scope: unknown, input: { messageId: string }) => {
          received.push(input.messageId);
          return { accepted: true };
        },
        stop: async () => ({ stopped: true }),
        // The runtime's own state comes from Pi in a Durable Object; this is its shape.
        inspect: async () => JSON.stringify(runtimeState),
      }),
    },
  } as unknown as Env;
  const call = async (path: string, method = "GET", body?: unknown, headers = {}) =>
    (await apiRoute(
      new Request(`https://devys.test${path}`, {
        method,
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json",
          ...headers,
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      bindings,
    ))!;
  const at = `/api/businesses/${acme.id}`;

  // The person, the catalog and the team.
  await keep("me", wire.Me, await call("/api/me"));
  await keep("roles", wire.Roles, await call("/api/roles"));
  await keep("models", wire.ModelCatalog, await call("/api/models"));
  await keep("devices", DeviceList, await call("/api/devices"));
  await keep("hello", Hello, await call("/api/hello"));
  await keep("device-link", SignInLink, await call("/api/devices/link", "POST", {}));
  const engineer = await keep(
    "employee",
    Employee,
    await call(`${at}/employees`, "POST", { template: "engineering", name: "Ada" }),
  );
  register(engineer.id);
  await keep(
    "look",
    wire.LookChanged,
    await call(`${at}/employees/${engineer.id}/look`, "POST", {
      look: { kind: "face", palette: "teal", shape: "capsule", seed: 7 },
    }),
  );
  await keep(
    "business-updated",
    wire.BusinessUpdated,
    await call(at, "PUT", { brief: "Fixes leaks across the city, same day." }),
  );

  // A project with a lead, a member and a referenced record; work items in it.
  const launch = await keep(
    "project",
    Project,
    await call(`${at}/projects`, "POST", {
      name: "Spring launch",
      goal: "Open bookings for the spring season",
      deadline: "2026-12-01",
      budget: { cents: 250_000, currency: "USD" },
      lead: chiefOfStaff.id,
      members: [engineer.id],
    }),
  );
  register(launch.id);
  const artifactId = crypto.randomUUID();
  register(artifactId);
  await sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ($1, $2, 'wire', $3, 'launch-plan.md', 'text/markdown', 1840)`,
    [artifactId, acme.id, `${acme.id}/artifacts/${artifactId}`],
  );
  await bindings.FILES.put(`${acme.id}/artifacts/${artifactId}`, "# Launch plan\n");
  await keep(
    "project-item",
    ProjectItem,
    await call(`${at}/projects/${launch.id}/items`, "POST", {
      ref: ref("documents", "artifact", artifactId),
    }),
  );
  const site = await keep(
    "work-item",
    WorkItem,
    await call(`${at}/work`, "POST", {
      title: "Publish the booking page",
      owner: engineer.id,
      objective: "Customers book a visit online",
      next_action: "Deploy a preview",
      due_at: "2026-11-20T17:00:00.000Z",
      project_id: launch.id,
    }),
  );
  register(site.id);
  await Effect.runPromise(
    addEvidence(db, acme.id, site.id, {
      by: `employee:${engineer.id}`,
      note: "Deployed a preview and checked it answers.",
      commit: "a".repeat(40),
      check: { command: "bun test", exit_code: 0 },
      changes: "3 files changed, 42 insertions(+)",
      deploy: { stage: "preview", url: "https://preview.acme.test", live: true },
      source: "wire-fixture",
    }),
  );
  // Work moving: the site's work item is in progress. The owner changes work by hand only
  // while it is taken over; set directly so the revisions in the files stay as they were.
  const handling = (id: string, by: string | null) =>
    sql.run("UPDATE work_items SET taken_over_by = $2 WHERE id = $1", [id, by]);
  await handling(site.id, person);
  const moving = (await (
    await call(`${at}/work/${site.id}`, "POST", {
      expected_revision: site.revision + 1,
      state: "in_progress",
    })
  ).json()) as { state: string };
  expect(moving.state).toBe("in_progress");
  await handling(site.id, null);
  // Ada shows her steps and the results she checked: one card in the thread draws them.
  const before = (await Effect.runPromise(workItem(db, acme.id, site.id)))!;
  const shown = await Effect.runPromise(
    updateWorkItem(
      db,
      acme.id,
      site.id,
      before.revision,
      {
        steps: [
          { title: "Build the page", state: "done" },
          { title: "Deploy a preview", state: "doing" },
          { title: "Check the booking form", state: "todo" },
          { title: "Connect the calendar", state: "blocked" },
        ],
        results: [
          { label: "Preview", url: "https://preview.acme.test", ok: true },
          { label: "Booking form", value: "test booking received", ok: true },
          { label: "Calendar sync", ok: null },
          { label: "Pages", value: "3" },
        ],
      },
      { kind: "employee", id: engineer.id },
    ),
  );
  await showWorkCard(bindings, acme.id, shown!);
  const supplier = await keep(
    "work-item-updated",
    WorkItem,
    await call(`${at}/work`, "POST", {
      title: "Order fittings",
      owner: chiefOfStaff.id,
      project_id: launch.id,
    }).then(async (created) => {
      const item = (await created.json()) as { id: string; revision: number };
      register(item.id);
      await handling(item.id, person);
      return call(`${at}/work/${item.id}`, "POST", {
        expected_revision: item.revision,
        state: "waiting",
        wait_condition: "The supplier confirms the price",
      });
    }),
  );
  await handling(supplier.id, null);

  // A decision the owner is asked for, on the supplier's work item.
  const create = capabilities(bindings).find((item) => item.name === "driveCreate")!;
  await Effect.runPromise(grant(db, scope, { capability: create, mode: "ask" }));
  await authorize(
    bindings,
    scope,
    create,
    { name: "order.txt", content: "12 fittings" },
    { workItemId: supplier.id, conversation: `work:${supplier.id}` },
  );

  // What employees ask the owner (askOwner) on that work item: a spend to sign on a device, and
  // a sign-in only the owner can do in the browser.
  await Effect.runPromise(
    grant(db, scope, {
      capability: capabilities(bindings).find((item) => item.name === "askOwner")!,
      mode: "auto",
    }),
  );
  for (const request of [
    {
      kind: "approve",
      action: "Register acme-plumbing.example for one year",
      counterparty: "Namecheap",
      amount: { cents: 1299, currency: "USD" },
      renewal: "Renews yearly at $14.99",
    },
    {
      kind: "take_over",
      reason: "Sign in to the registrar (2FA)",
      url: "https://www.namecheap.com/myaccount/login/",
    },
    {
      kind: "secret",
      name: "RAMP_CARD",
      why: "The company card, to pay for the domain at Namecheap",
      spend: true,
    },
    {
      kind: "approve",
      action: "Send the launch plan to the supplier",
      counterparty: "orders@supplier.test",
      steps: ["Email the launch plan to orders@supplier.test", "Mark the order placed"],
      preview: ref("documents", "artifact", artifactId),
    },
    { kind: "file", purpose: "The signed supplier agreement", accept: ["application/pdf"] },
  ] as const) {
    // One request at a time per work item: each waits on its own step.
    const step = await Effect.runPromise(
      createWorkItem(db, acme.id, {
        id: crypto.randomUUID(),
        owner: chiefOfStaff.id,
        title: `Order fittings: ${request.kind}`,
        projectId: launch.id,
        createdBy: `person:${person}`,
      }),
    );
    register(step.id);
    await askOwnerFor(
      bindings,
      { ...scope, workItemId: step.id, conversation: `work:${step.id}` },
      request,
    );
  }

  // Routines: Ada proposes a weekly report for the launch and asks the owner to activate it; an
  // event routine the owner has paused.
  const report = crypto.randomUUID();
  register(report);
  const ada = { businessId: acme.id, employeeId: engineer.id };
  await Effect.runPromise(
    proposeRoutine(
      db,
      acme.id,
      report,
      {
        employeeId: engineer.id,
        projectId: launch.id,
        title: "Weekly bookings report",
        instruction: "Report last week's bookings and what changed on the booking page.",
        trigger: {
          kind: "cron",
          expression: "0 9 * * 1",
          timezone: "America/Chicago",
          hours: { start: "08:00", end: "18:00", days: ["mon"] },
        },
        notify: "always",
      },
      `employee:${engineer.id}`,
    ),
  );
  await authorize(
    bindings,
    ada,
    capabilities(bindings).find((item) => item.name === "routineActivate")!,
    { ref: report, revision: 1 },
    { conversation: `project:${launch.id}` },
  );
  const replies = crypto.randomUUID();
  register(replies);
  await Effect.runPromise(
    proposeRoutine(
      db,
      acme.id,
      replies,
      {
        employeeId: chiefOfStaff.id,
        projectId: null,
        title: "Supplier replies",
        instruction: "Answer supplier replies about prices.",
        trigger: {
          kind: "event",
          source: "mail",
          type: "received",
          filters: { from: "parts@supply.test" },
        },
        notify: "when_found",
      },
      `employee:${chiefOfStaff.id}`,
    ),
  );
  await Effect.runPromise(activateRoutine(db, acme.id, replies, 1, null));
  await keep("routine", Routine, await call(`${at}/routines/${replies}/pause`, "POST"));

  // Conversations: the owner's message, an employee's reply, an event that points at a record.
  const posted = await keep(
    "posted",
    wire.Posted,
    await call(
      `${at}/conversations/${encodeURIComponent(`direct:${chiefOfStaff.id}`)}/messages`,
      "POST",
      {
        id: crypto.randomUUID(),
        text: "What's left before the launch? @Ada please check the site.",
      },
    ),
  );
  register(posted.message.id);
  // Ada answers with a question and the replies she offers for it.
  const direct = `direct:${chiefOfStaff.id}` as const;
  await Effect.runPromise(suggestReplies(db, acme.id, direct, engineer.id, ["Ship it", "Wait"]));
  const answered = await Effect.runPromise(
    postMessage(db, acme.id, direct, {
      author: `employee:${engineer.id}`,
      text: "The site is ready. Ship it today?",
      clientId: "wire-answer",
      replyTo: posted.message.id,
    }),
  );
  register(answered.message.id);
  await postEvent(bindings, acme.id, `work:${site.id}`, {
    clientId: "wire-event",
    text: "Ada started a coding session.",
    ref: ref("work", "item", site.id),
  });
  await call(`${at}/conversations/${encodeURIComponent(`work:${site.id}`)}/follow`, "POST", {
    on: true,
  });
  await keep(
    "conversation",
    wire.ConversationPage,
    await call(`${at}/conversations/${encodeURIComponent(`direct:${chiefOfStaff.id}`)}`),
  );
  await keep(
    "conversation-work",
    wire.ConversationPage,
    await call(`${at}/conversations/${encodeURIComponent(`work:${site.id}`)}`),
  );
  const summaries = await call(`${at}/conversations`);
  const listed = (await summaries.clone().json()) as {
    conversations: { key: string; last: { created_at: string } | null }[];
  };
  // Conversations come in no defined order; sorted by their last message for a stable file.
  listed.conversations.sort((a, b) =>
    (a.last?.created_at ?? "").localeCompare(b.last?.created_at ?? ""),
  );
  await keep("conversations", wire.Conversations, Response.json(listed));

  // Remote apps: one asked for and not connected yet, one on whose sign-in lapsed.
  const books = await Effect.runPromise(
    addRemoteApp(
      db,
      acme.id,
      {
        name: "Acme Books",
        summary: "Bills and cards for Acme",
        url: "https://books.example/mcp",
        registryName: "example.books/acme",
        website: "https://books.example",
        logo: null,
        addedBy: `employee:${chiefOfStaff.id}`,
      },
      [],
    ),
  );
  await askOwnerFor(
    bindings,
    { ...scope, workItemId: supplier.id, conversation: `work:${supplier.id}` },
    { kind: "connect", app: books.id, why: "To read and draft the supplier's bills" },
  );
  const ledger = await Effect.runPromise(
    addRemoteApp(
      db,
      acme.id,
      {
        name: "Ledger",
        summary: "",
        url: "https://ledger.example/mcp",
        registryName: null,
        website: null,
        logo: "a".repeat(64),
        addedBy: `person:${person}`,
      },
      [],
    ),
  );
  await Effect.runPromise(
    connectedRemoteApp(db, acme.id, ledger.id, {
      server: { name: "ledger", title: "Ledger", description: "The books", icons: [] },
      tools: [
        {
          name: "list_entries",
          title: "List entries",
          description: "List ledger entries.",
          input: { type: "object", properties: {} },
          hints: { readOnlyHint: true },
        },
        {
          name: "post_entry",
          description: "Post a journal entry.",
          input: { type: "object", properties: { memo: { type: "string" } }, required: ["memo"] },
          hints: { destructiveHint: true },
        },
      ],
      logo: null,
    }),
  );
  await keep("app-review", wire.AppReview, await call(`${at}/apps/${ledger.id}/review`));
  await keep(
    "app-changed",
    wire.AppChanged,
    await call(`${at}/apps/${ledger.id}/accept`, "POST", {
      lines: { ledger_list_entries: "own", ledger_post_entry: "ask" },
      employees: [chiefOfStaff.id],
    }),
  );
  await Effect.runPromise(lapseRemoteApp(db, acme.id, ledger.id));
  // Search answers from the business's apps (the registry has nothing for this).
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) =>
    new URL(String(input instanceof Request ? input.url : input)).hostname === "cloudflare-dns.com"
      ? Response.json({ Answer: [{ type: 1, data: "93.184.216.34" }] })
      : Response.json({ servers: [], metadata: { count: 0 } }),
  );
  await keep("app-search", wire.AppSearch, await call(`${at}/apps/search?q=books`));
  vi.restoreAllMocks();
  await keep(
    "connecting",
    wire.Connecting,
    Response.json({
      url: "https://books.example/authorize?client_id=devys",
      app: {
        ...((await (await call(`${at}/apps`)).json()) as { apps: { id: string }[] }).apps.find(
          (app) => app.id === books.id,
        ),
      },
    }),
  );

  // The business at a glance.
  await keep("work", wire.WorkItems, await call(`${at}/work`));
  await keep("projects", wire.Projects, await call(`${at}/projects`));
  await keep("routines", wire.Routines, await call(`${at}/routines`));
  await keep("decisions", wire.Decisions, await call(`${at}/decisions`));
  await keep("home", wire.Home, await call(`${at}/home`));
  await keep("business", wire.BusinessDetail, await call(at));
  await keep("apps", wire.Apps, await call(`${at}/apps`));
  await keep("access", wire.AccessList, await call(`${at}/employees/${engineer.id}/access`));
  await keep("status", wire.RuntimeStatus, await call(`${at}/employees/${engineer.id}/status`));
  const remembered = await call(
    `${at}/memory/remember`,
    "POST",
    { key: "service-area", content: "Serves the north and east of the city", source: "user" },
    { "idempotency-key": "wire-memory" },
  );
  expect(remembered.status).toBe(200);
  await keep("memory", ClaimPage, await call(`${at}/memory`));
  await keep("google", wire.GoogleConnection, await call(`${at}/connections/google`));

  // The owner's Mac: a coding session on the site's work item, read through a fake host.
  const codingSessionId = crypto.randomUUID();
  register(codingSessionId);
  await Effect.runPromise(
    recordCodingSession(db, acme.id, {
      id: codingSessionId,
      workItemId: site.id,
      employeeId: engineer.id,
      provider: "codex",
      purpose: "build",
      objective: "Build the booking page",
    }),
  );
  const worktree = `/Users/owner/Devys/${acme.id}/worktrees/${codingSessionId}`;
  await Effect.runPromise(
    recordStarted(db, acme.id, codingSessionId, {
      providerSessionId: "thread-1",
      repository: "/Users/owner/Devys/acme/repos/site",
      baseCommit: "b".repeat(40),
      branch: "devys/booking-page",
      worktree,
    }),
  );
  const host: CodingHost = {
    start: async () => {
      throw new Error("not started here");
    },
    inspect: async () => ({
      state: "idle",
      reply: "The booking page is built and its tests pass.",
      diffStat: " 3 files changed, 42 insertions(+)",
      error: null,
    }),
    diff: async () => ({
      files: [{ path: "src/book.tsx", status: "added", added: 40, removed: 0 }],
      patch: "+export function Book() {}\n",
    }),
    transcript: async () => ({
      entries: [
        { kind: "prompt", text: "Build the booking page" },
        { kind: "command", text: "bun test", detail: "12 pass", failed: false },
        { kind: "reply", text: "Done." },
      ],
    }),
    send: async () => ({ steered: true }),
    interrupt: async () => {},
    accept: async () => ({ commit: "c".repeat(40), diffStat: "", patch: "" }),
    publish: async () => {
      throw new Error("not published here");
    },
    deploy: async () => ({ commit: "c".repeat(40) }),
    deployRepository: async () => ({ commit: "c".repeat(40) }),
  };
  const owner = { id: person, display_name: "Owner" };
  const access = (path: string) => ({ person: owner, business: acme, trusted: true, path });
  const coding = (path: string) =>
    codingRoute(new Request(`https://devys.test${at}${path}`), bindings, access(path), () => host);
  await keep("coded-work", wire.CodedWork, (await coding("/coding"))!);
  const sessions = `/work/${site.id}/sessions`;
  await keep("coding-sessions", wire.CodingSessions, (await coding(sessions))!);
  await keep(
    "transcript",
    Transcript,
    (await coding(`${sessions}/${codingSessionId}/transcript`))!,
  );
  await keep("diff", WorkingDiff, (await coding(`${sessions}/${codingSessionId}/diff`))!);

  // Terminals, files and the browser, through the Mac host's protocol.
  const folder = `/Users/owner/Devys/${acme.id}`;
  const answers: Record<string, unknown> = {
    "/terminals/list": [
      {
        id: crypto.randomUUID(),
        title: "Codex · devys/booking-page",
        cwd: worktree,
        coding_session_id: codingSessionId,
        cols: 120,
        rows: 32,
        started_at: new Date().toISOString(),
        offset: 2048,
        writer: null,
        exit: null,
      },
    ],
    "/list": [
      { name: "brief.md", path: `${folder}/brief.md`, kind: "file", size: 512 },
      { name: "repos", path: `${folder}/repos`, kind: "directory", size: 96 },
      { name: "site", path: `${folder}/site`, kind: "repository", size: 160 },
    ],
    "/read": { path: `${folder}/brief.md`, content: "# Acme\n", revision: "d".repeat(64) },
    "/browser/status": {
      open: true,
      url: "https://supplier.test/orders",
      title: "Orders",
      driver: `work:${supplier.id}`,
      driving: true,
    },
    "/browser/screenshot": { jpeg: "/9j/4AAQSkZJRg==", width: 1280, height: 800 },
    // The host seals what the secure entry sheet sends; the Worker stores only this.
    "/vault/seal": {
      business: acme.id,
      name: "STRIPE_KEY",
      kind: "secret",
      key: "d3JhcHBlZA==",
      data: "c2VhbGVk",
    },
  };
  const realFetch = globalThis.fetch;
  const fetching = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.origin !== hostUrl) return realFetch(input, init);
    return url.pathname in answers
      ? Response.json(answers[url.pathname])
      : new Response("Not found", { status: 404 });
  });
  try {
    const mac = (path: string, route: typeof terminalRoute) =>
      route(new Request(`https://devys.test${at}${path}`), local, access(path.split("?")[0]!));
    await keep("terminals", wire.Terminals, (await mac("/terminals", terminalRoute))!);
    await keep(
      "files",
      wire.Folder,
      (await mac(`/files?path=${encodeURIComponent(folder)}`, filesRoute))!,
    );
    await keep(
      "file-text",
      FileText,
      (await mac(`/files/text?path=${encodeURIComponent(`${folder}/brief.md`)}`, filesRoute))!,
    );
    await keep("browser", BrowserStatus, (await mac("/browser", browserRoute))!);
    await keep("screenshot", Screenshot, (await mac("/browser/screenshot", browserRoute))!);
    // Settings › Secrets: names, kinds and who added them; the value is never answered back.
    const added = await secretsRoute(
      new Request(`https://devys.test${at}/secrets`, {
        method: "POST",
        body: JSON.stringify({ name: "STRIPE_KEY", kind: "secret", value: "sk_test_never_echoed" }),
      }),
      local,
      access("/secrets"),
    );
    expect(await added.clone().text()).not.toContain("sk_test_never_echoed");
    await keep("secrets", wire.Secrets, added);
  } finally {
    fetching.mockRestore();
  }

  // A second business: what creating one answers.
  const created = await call("/api/businesses", "POST", {
    name: "Acme Roofing",
    brief: "Roof repairs.",
    team: ["engineering"],
  });
  const body = (await created.clone().json()) as {
    business: { id: string };
    chief_of_staff: { id: string };
    team: { id: string }[];
  };
  [body.business.id, body.chief_of_staff.id, ...body.team.map((member) => member.id)].forEach(
    register,
  );
  await keep("business-created", wire.BusinessCreated, created);

  // This iPhone's signing key (a fixed public key, so the file is stable).
  await keep(
    "device-key",
    DeviceKey,
    await call("/api/device-keys", "POST", {
      public_key:
        "BCDij9urh2sNUg0gg0DUgyk1/FXSWQPxIEaK1wHb+twTfTKW/vHV8w2KPznUuKJXdRUXyN+j6cl07cNRrc2aQoo=",
    }),
  );
  await keep("device-keys", wire.DeviceKeys, await call("/api/device-keys"));
  // A device asking to join, and this one allowing it with the new device's key. The two emoji
  // come from the request's random id, so the golden files show a fixed pair.
  const asked = Schema.decodeUnknownSync(JoinRequest)(
    await (
      await call("/api/joins", "POST", {
        name: "Wire iPhone",
        session_hash: await sha256(crypto.randomUUID()),
        public_key:
          "BM1xO69bs1+PCo25ktirivFF9T8AbiTyaPZED9nLJ5xzNn3ibtusfSsIF4TvlNU9E6G+eXxQ+e0NzXRnpyTQxuo=",
      })
    ).json(),
  );
  const joining = { ...asked, match: ["🦊", "🌵"] };
  await keep("join", JoinRequest, Response.json(joining));
  await keep("joins", JoinRequests, Response.json({ joins: [joining] }));
  await keep(
    "join-answered",
    wire.JoinAnswered,
    await call(`/api/joins/${asked.id}/allow`, "POST", {}),
  );

  // Also decoded, not kept: shapes whose values are random or the browser's own.
  expect(Schema.decodeUnknownSync(PageState)({ url: "https://a.test", title: "A" })).toBeTruthy();
  expect(
    Schema.decodeUnknownSync(DeviceSession)({ session_token: "t", expires_in_seconds: 1 }),
  ).toBeTruthy();
  expect(
    Schema.decodeUnknownSync(TerminalSession)((answers["/terminals/list"] as unknown[])[0]),
  ).toBeTruthy();
  expect(received.length).toBeGreaterThan(0);

  for (const { name, text } of golden) {
    if (sink) {
      const written = await fetch(`${sink}/${name}`, { method: "PUT", body: text });
      expect(written.status, name).toBe(204);
    } else
      expect(committed(name), `${name}.json differs; run bun run wire:write and review`).toBe(text);
  }
  if (!sink)
    expect(Object.keys(fixtures).length, "a committed wire file no route produces").toBe(
      golden.length,
    );
});

/** An employee runtime's status as its Durable Object reports it (`employeeStatus`). */
const runtimeState = {
  run: {
    id: "message-2",
    stopped: false,
    deadline: 1_800_000_600_000,
    conversation: "work:00000000-0000-4000-8000-000000000009",
  },
  inbox: [
    { id: "message-1", text: "What's left?", received_at: 1_800_000_000_000, status: "done" },
    {
      id: "message-2",
      text: "Check the site.",
      received_at: 1_800_000_300_000,
      status: "running",
    },
  ],
  outbox: [
    {
      id: "message-1",
      chat_id: "app:b:e",
      text: "The booking page and the fittings order.",
      reply_to: "message-1",
      attempts: 1,
      status: "sent",
    },
  ],
  checkpoint: { status: "saved", at: 1_800_000_100_000, kind: "durable" },
  usage: {
    models: {
      "anthropic/claude-opus-5-5": {
        input: 3000,
        output: 1500,
        cache_read: 20_000,
        cache_write: 0,
        total_tokens: 24_500,
        cost: { input: 0.015, output: 0.0375, cache_read: 0.01, cache_write: 0, total: 0.0625 },
      },
    },
    tools: {},
  },
};
