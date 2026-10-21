import { env } from "cloudflare:workers";
import { Effect, Schema } from "effect";
import { expect, inject, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { codingRoute } from "../src/app/coding.ts";
import { postEvent } from "../src/app/conversations.ts";
import { browserRoute } from "../src/app/browser-route.ts";
import { filesRoute } from "../src/app/files.ts";
import { apiRoute } from "../src/app/http.ts";
import { terminalRoute } from "../src/app/terminals.ts";
import * as wire from "../src/app/wire.ts";
import { Transcript, WorkingDiff, type CodingHost } from "../src/apps/code/contract.ts";
import { recordCodingSession, recordStarted } from "../src/apps/code/service.ts";
import { grant } from "../src/authority/service.ts";
import { BrowserStatus, PageState, Screenshot } from "../src/browser/contract.ts";
import { DeviceCode, DeviceList, Employee } from "../src/identity/contract.ts";
import { DeviceSession } from "../src/identity/http.ts";
import { ClaimPage } from "../src/memory/contract.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { ref } from "../src/protocol/ref.ts";
import { TerminalSession } from "../src/terminal/contract.ts";
import { Project, ProjectItem, WorkItem } from "../src/work/contract.ts";
import { addEvidence } from "../src/work/service.ts";
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
  const { person, business: acme, operations, scope } = await business("Acme Plumbing");
  [person, acme.id, operations.id].forEach(register);
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
  await keep("device-code", DeviceCode, await call("/api/devices/codes", "POST", {}));
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
      lead: operations.id,
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
  // Work moving: the site's work item is in progress.
  const moving = (await (
    await call(`${at}/work/${site.id}`, "POST", {
      expected_revision: site.revision + 1,
      state: "in_progress",
    })
  ).json()) as { state: string };
  expect(moving.state).toBe("in_progress");
  const supplier = await keep(
    "work-item-updated",
    WorkItem,
    await call(`${at}/work`, "POST", {
      title: "Order fittings",
      owner: operations.id,
      project_id: launch.id,
    }).then(async (created) => {
      const item = (await created.json()) as { id: string; revision: number };
      register(item.id);
      return call(`${at}/work/${item.id}`, "POST", {
        expected_revision: item.revision,
        state: "waiting",
        wait_condition: "The supplier confirms the price",
      });
    }),
  );

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

  // Conversations: the owner's message, an employee's reply, an event that points at a record.
  const posted = await keep(
    "posted",
    wire.Posted,
    await call(
      `${at}/conversations/${encodeURIComponent(`direct:${operations.id}`)}/messages`,
      "POST",
      {
        id: crypto.randomUUID(),
        text: "What's left before the launch? @Ada please check the site.",
      },
    ),
  );
  register(posted.message.id);
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
    await call(`${at}/conversations/${encodeURIComponent(`direct:${operations.id}`)}`),
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

  // The business at a glance.
  await keep("work", wire.WorkItems, await call(`${at}/work`));
  await keep("projects", wire.Projects, await call(`${at}/projects`));
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
    },
    "/browser/screenshot": { jpeg: "/9j/4AAQSkZJRg==", width: 1280, height: 800 },
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
    operations: { id: string };
    team: { id: string }[];
  };
  [body.business.id, body.operations.id, ...body.team.map((member) => member.id)].forEach(register);
  await keep("business-created", wire.BusinessCreated, created);

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
  run: { id: "message-2", stopped: false, deadline: 1_800_000_600_000 },
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
