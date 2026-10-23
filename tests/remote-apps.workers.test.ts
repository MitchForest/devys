/**
 * LP6: remote apps. A fake MCP server behind its own OAuth 2.1 sign-in (tests/fixtures/mcp.ts) and
 * a fake MCP Registry stand in for the outside; the Mac host is its own vault and MCP routes run
 * in process; the database is real. The owner's browser signing in is a fetch of the provider's
 * authorize page, which redirects to Devys's callback.
 */
import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { usableIn } from "../src/app/apps.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { apiRoute } from "../src/app/http.ts";
import { remoteCapabilities } from "../src/app/remote-apps.ts";
import { spendTerms } from "../src/app/asking.ts";
import { decision, grant, grantsFor } from "../src/authority/service.ts";
import { mcpHost } from "../src/connections/host/mcp.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { Invocation, type Capability } from "../src/protocol/capability.ts";
import { envelopeKeyring } from "../src/vault/envelope.ts";
import { openFor, vaultHost } from "../src/vault/host/server.ts";
import { createWorkItem, workItem } from "../src/work/service.ts";
import { fakeMcp, logoPng, type FakeMcp } from "./fixtures/mcp.ts";
import { business, db, sql } from "./fixtures/postgres.ts";
import { deviceKey } from "./fixtures/signing.ts";

const hostUrl = "http://127.0.0.1:1";
const local = {
  ...env,
  AGENT: { getByName: () => ({ receive: async () => ({ accepted: true }) }) },
  DEVYS_MODE: "local",
  DEVYS_HOST_URL: hostUrl,
  DEVYS_HOST_TOKEN: "host-token",
  DEVYS_HOST_HOME: "/Users/owner",
  PUBLIC_URL: "https://devys.test",
} as unknown as Env;

const keyring = await envelopeKeyring(crypto.getRandomValues(new Uint8Array(32)));
const mcp = mcpHost({
  open: (business, sealed, kinds) => openFor(keyring, business, sealed, kinds),
  seal: (...args) => keyring.seal(...args),
});

/** The outside world: apps by origin, and the MCP Registry's listing. */
let apps: Record<string, FakeMcp> = {};
let registry: unknown[] = [];
/** What the stand-in host was asked, by path. */
const sent: { path: string; body: Record<string, unknown> }[] = [];
/** What the stand-in host answered the Worker, by path. */
const answers: { path: string; body: unknown }[] = [];
let fillAnswer: () => Response = () => new Response("No fills here", { status: 500 });

const listing = (name: string, title: string, origin: string, extra: object = {}) => ({
  name,
  title,
  description: `${title}, for tests`,
  version: "1.0.0",
  websiteUrl: origin,
  remotes: [{ type: "streamable-http", url: `${origin}/mcp` }],
  ...extra,
});

beforeEach(() => {
  sent.length = 0;
  answers.length = 0;
  apps = {};
  registry = [];
  const realFetch = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.origin === hostUrl) {
      const body = (await request.json()) as Record<string, unknown>;
      sent.push({ path: url.pathname, body });
      try {
        if (url.pathname.startsWith("/vault/"))
          return Response.json(await vaultHost(keyring).handle(url.pathname, body));
        if (url.pathname.startsWith("/mcp/")) {
          const answer = await mcp.routes.handle(url.pathname, body);
          answers.push({ path: url.pathname, body: answer });
          return Response.json(answer);
        }
      } catch (error) {
        const status = (error as { status?: number }).status ?? 500;
        return new Response((error as Error).message, { status });
      }
      if (url.pathname === "/browser/fill") return fillAnswer();
      return new Response("Not found", { status: 404 });
    }
    if (url.hostname === "cloudflare-dns.com")
      return Response.json({ Answer: [{ type: 1, data: "93.184.216.34" }] });
    if (url.origin === "https://registry.modelcontextprotocol.io") {
      const named = /^\/v0\.1\/servers\/([^/]+)\/versions\/latest$/.exec(url.pathname);
      if (named) {
        const server = registry.find(
          (entry) => (entry as { name: string }).name === decodeURIComponent(named[1]!),
        );
        return server ? Response.json({ server }) : new Response("Not found", { status: 404 });
      }
      const search = (url.searchParams.get("search") ?? "").toLowerCase();
      return Response.json({
        servers: registry
          .filter((entry) => JSON.stringify(entry).toLowerCase().includes(search))
          .map((server) => ({ server })),
        metadata: { count: registry.length },
      });
    }
    const app = apps[url.origin];
    if (app) return app.fetch(request);
    return realFetch(input, init);
  });
});
afterEach(() => vi.restoreAllMocks());

const failure = (run: Promise<unknown>) =>
  run.then(
    () => "",
    (error: unknown) => (error instanceof Error ? error.message : String(error)),
  );

/** A business, its owner signed in on the Mac, an employee and a work item. */
async function owner() {
  const acme = await business("Remote apps");
  const { scope, person } = acme;
  const catalog = capabilities(local);
  for (const name of ["askOwner", "appSearch", "browserFill"])
    await Effect.runPromise(
      grant(db, scope, { capability: catalog.find((c) => c.name === name)!, mode: "auto" }),
    );
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Pay the vendor",
      createdBy: `person:${person}`,
    }),
  );
  const session = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', 'Mac')",
    [await sha256(session), person],
  );
  const at = `/api/businesses/${scope.businessId}`;
  const call = (path: string, body?: unknown) =>
    apiRoute(
      new Request(`https://devys.test${path.startsWith("/api/") ? "" : at}${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: { authorization: `Bearer ${session}`, "content-type": "application/json" },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      local,
    ).then((response) => response!);
  const json = async <T>(path: string, body?: unknown) => {
    const response = await call(path, body);
    if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
    return (await response.json()) as T;
  };
  /** Runs a capability as the employee in the work item's thread, through the real gate. */
  const run = <T>(capability: Capability, input: unknown) =>
    Effect.runPromise(
      capability.execute(input).pipe(
        Effect.provideService(Invocation, {
          ...scope,
          workItemId: work.id,
          conversation: `work:${work.id}`,
          operationId: crypto.randomUUID(),
          authorize: (cap, value) =>
            Effect.promise(() => authorize(local, scope, cap, value, { workItemId: work.id })).pipe(
              Effect.flatMap((outcome) =>
                outcome.outcome === "allow"
                  ? Effect.void
                  : Effect.die(
                      new Error(outcome.outcome === "ask" ? "approval_required" : outcome.reason),
                    ),
              ),
            ),
          assertActive: () => Effect.void,
        }),
      ) as Effect.Effect<T>,
    );
  const use = <T>(name: string, input: unknown) =>
    run<T>(
      catalog.find((item) => item.name === name)!,
      input,
    );
  const remote = async (name: string) =>
    (await remoteCapabilities(local, scope.businessId)).find((item) => item.name === name);
  /**
   * The thread, without hand-offs: under the full run another file's dispatcher may hand this
   * work item on and post its card here at any time. The app's connect card stays.
   */
  const thread = async () =>
    (
      (await json(`/conversations/${encodeURIComponent(`work:${work.id}`)}`)) as {
        messages: { text: string; ref: string | null; kind: string }[];
      }
    ).messages.filter((message) => !message.ref?.startsWith("devys:work/item/"));
  /** The owner signs in at the provider: its authorize page sends them back to Devys. */
  const signIn = async (url: string) => {
    const authorized = await fetch(url, { redirect: "manual" });
    const back = new URL(authorized.headers.get("location")!);
    expect(back.origin).toBe("https://devys.test");
    return apiRoute(new Request(back.href), local).then((response) => response!);
  };
  return { ...acme, work, call, json, use, run, remote, thread, signIn };
}

it("an employee finds an app, asks to connect it; the owner signs in, reviews and turns it on", async () => {
  apps["https://books.example"] = fakeMcp("https://books.example");
  registry = [
    listing("example.books/acme", "Acme Books", "https://books.example"),
    // Needs an API key header: not something Devys connects by sign-in.
    listing("example.keys/keyed", "Keyed Books", "https://keys.example", {
      remotes: [
        {
          type: "streamable-http",
          url: "https://keys.example/mcp",
          headers: [{ name: "Authorization", isSecret: true }],
        },
      ],
    }),
  ];
  const { use, json, call, thread, signIn, scope, remote, run, business: acme } = await owner();

  // appSearch: the registry's match, ready for askOwner connect.
  const found = await use<{ apps: { app: string; name: string; installed: boolean }[] }>(
    "appSearch",
    { query: "books" },
  );
  expect(found.apps.map((each) => each.app)).toEqual(["example.books/acme"]);
  expect(found.apps[0]).toMatchObject({ name: "Acme Books", installed: false });

  // askOwner connect: the card in the thread and the request in Needs you.
  const ask = { kind: "connect", app: "example.books/acme", why: "To read and draft bills" };
  const asked = await use<{ request: string; kind: string; state: string }>("askOwner", ask);
  expect(asked).toMatchObject({ kind: "connect", state: "asked" });
  const card = (await thread()).find((message) => message.ref?.startsWith("devys:team/app/"));
  expect(card).toMatchObject({
    kind: "event",
    text: "To read and draft bills",
    ref: "devys:team/app/acmebooks",
  });
  const home = await json<{ needs_you: Record<string, unknown>[] }>("/home");
  expect(home.needs_you).toEqual([
    expect.objectContaining({
      id: asked.request,
      kind: "connect",
      title: "Acme Books",
      app: { id: "acmebooks", name: "Acme Books", logo: expect.any(String) },
    }),
  ]);
  // Only connecting answers it.
  expect((await call(`/decisions/${asked.request}/approve`, {})).status).toBe(409);

  // Connect: the provider's sign-in, discovered per the MCP spec; the tokens go to the vault.
  const connecting = await json<{ url: string; app: { state: string } }>(
    "/apps/acmebooks/connect",
    { native: false },
  );
  expect(new URL(connecting.url).origin).toBe("https://books.example");
  expect(new URL(connecting.url).searchParams.get("redirect_uri")).toBe(
    "https://devys.test/api/apps/callback",
  );
  const back = await signIn(connecting.url);
  expect(back.status).toBe(200);
  expect(await back.text()).toContain("Acme Books is connected");
  const vaulted = await sql.row<{ kind: string; ciphertext: string }>(
    "SELECT kind, ciphertext FROM secrets WHERE business_id = $1 AND name = 'app-acmebooks'",
    [scope.businessId],
  );
  expect(vaulted?.kind).toBe("connection");
  // The Worker never saw a token: the host answered with the sealed bundle only.
  const finished = answers.find((each) => each.path === "/mcp/finish")!;
  expect(JSON.stringify(finished.body)).not.toMatch(/access_token|"Bearer"/);
  const opened = JSON.parse(
    await keyring.open({
      business: scope.businessId,
      name: "app-acmebooks",
      kind: "connection",
      ...(finished.body as { sealed: { key: string; data: string } }).sealed,
    }),
  ) as { tokens: { access_token: string } };
  expect(opened.tokens.access_token).toMatch(/^[0-9a-f-]{36}$/);

  // The one review card, suggested from the tools' own hints; payment credentials never.
  const review = await json<{
    app: { state: string; logo: string | null };
    tools: { capability: string; title: string; line: string; fixed: boolean }[];
    employees: { id: string; uses: boolean }[];
  }>("/apps/acmebooks/review");
  expect(review.app.state).toBe("review");
  expect(review.tools).toEqual([
    expect.objectContaining({
      capability: "acmebooks_list_bills",
      title: "List bills",
      line: "own",
    }),
    expect.objectContaining({ capability: "acmebooks_create_bill", line: "ask", fixed: false }),
    expect.objectContaining({
      capability: "acmebooks_ramp_get_agent_card_creds",
      line: "never",
      fixed: true,
    }),
    expect.objectContaining({ capability: "acmebooks_ramp_mpp_creds", line: "never", fixed: true }),
  ]);
  expect(review.employees).toEqual([{ id: scope.employeeId, name: "Chief of Staff", uses: true }]);
  // Its logo: the icon its serverInfo names, fetched once and served by Devys.
  const logo = await call(review.app.logo!.replace(`/api/businesses/${acme.id}`, ""));
  expect(logo.headers.get("content-type")).toBe("image/png");
  expect(new Uint8Array(await logo.arrayBuffer())).toEqual(logoPng);

  // Turn on: the acceptance is the policy; asking to unlock a withheld tool is ignored.
  const accepted = await json<{ app: { state: string; capabilities: string[] } }>(
    "/apps/acmebooks/accept",
    {
      lines: Object.fromEntries(
        review.tools.map((tool) => [tool.capability, tool.fixed ? "own" : tool.line]),
      ),
      employees: [scope.employeeId],
    },
  );
  expect(accepted.app.state).toBe("on");
  expect(accepted.app.capabilities).toEqual(["acmebooks_list_bills", "acmebooks_create_bill"]);
  const grants = await Effect.runPromise(grantsFor(db, scope));
  expect(
    grants
      .filter((each) => each.capability.startsWith("acmebooks_"))
      .map((each) => [each.capability, each.mode]),
  ).toEqual([
    ["acmebooks_create_bill", "ask"],
    ["acmebooks_list_bills", "auto"],
  ]);
  expect((await thread()).at(-1)?.text).toBe(
    "Acme Books is on: find what it does with describe_capabilities.",
  );
  expect(await use<{ state: string }>("askOwner", ask)).toMatchObject({ state: "done" });

  // Gated calls: a read runs on its own; a write asks the owner; withheld tools don't exist.
  const usable = await usableIn(db, scope.businessId);
  expect(usable("acmebooks_list_bills")).toBe(true);
  expect(usable("acmebooks_ramp_get_agent_card_creds")).toBe(false);
  expect(await remote("acmebooks_ramp_get_agent_card_creds")).toBeUndefined();
  expect(await remote("acmebooks_ramp_mpp_creds")).toBeUndefined();
  const listed = await run<{ text: string; error: boolean }>(
    (await remote("acmebooks_list_bills"))!,
    {},
  );
  expect(listed).toMatchObject({ error: false });
  expect(listed.text).toContain("Paper Co");
  expect(
    await failure(run((await remote("acmebooks_create_bill"))!, { vendor: "Ink Co" })),
  ).toContain("approval_required");
  // Inputs are checked at the boundary: an object with the tool's required keys.
  expect(await failure(run((await remote("acmebooks_create_bill"))!, { amount: "1" }))).toContain(
    "Invalid arguments",
  );
  const pending = await json<{ needs_you: { kind: string; title: string; app: unknown }[] }>(
    "/home",
  );
  expect(pending.needs_you).toEqual([
    expect.objectContaining({
      kind: "decision",
      title: "Acme Books: Create a bill",
      app: expect.objectContaining({ id: "acmebooks" }),
    }),
  ]);
  // The directory lists it with its logo; the review is the same card, now accepted.
  const directory = await json<{
    apps: { id: string; state: string | null; logo: string | null }[];
  }>("/apps");
  expect(directory.apps.find((app) => app.id === "acmebooks")).toMatchObject({
    state: "on",
    logo: review.app.logo,
  });
});

it("a refresh keeps working, a lapsed sign-in shows in Needs you, and reconnecting restores it", async () => {
  const books = fakeMcp("https://books.example");
  apps["https://books.example"] = books;
  const { json, signIn, scope, remote, run } = await owner();
  // Added by its address (no registry entry), connected and turned on with the suggestions.
  const added = await json<{ app: { id: string; name: string } }>("/apps/add", {
    app: "https://books.example/mcp",
  });
  expect(added.app).toMatchObject({ id: "books", name: "Books" });
  await signIn((await json<{ url: string }>("/apps/books/connect", {})).url);
  const review = await json<{ tools: { capability: string; line: string }[] }>(
    "/apps/books/review",
  );
  await json("/apps/books/accept", {
    lines: Object.fromEntries(review.tools.map((tool) => [tool.capability, tool.line])),
    employees: [scope.employeeId],
  });
  // serverInfo names it.
  expect(
    (await json<{ apps: { id: string; name: string }[] }>("/apps")).apps.find(
      (app) => app.id === "books",
    )?.name,
  ).toBe("Acme Books");
  const before = await sql.row<{ ciphertext: string }>(
    "SELECT ciphertext FROM secrets WHERE business_id = $1 AND name = 'app-books'",
    [scope.businessId],
  );

  // The access token expires: the host refreshes it and the Worker keeps the resealed bundle.
  books.expireAccess();
  expect((await run<{ text: string }>((await remote("books_list_bills"))!, {})).text).toContain(
    "bill-1",
  );
  expect(books.refreshes()).toBe(1);
  const after = await sql.row<{ ciphertext: string }>(
    "SELECT ciphertext FROM secrets WHERE business_id = $1 AND name = 'app-books'",
    [scope.businessId],
  );
  expect(after!.ciphertext).not.toBe(before!.ciphertext);

  // The provider revokes it: the call says so, and the owner sees "Reconnect" in Needs you.
  books.revoke();
  expect(await failure(run((await remote("books_list_bills"))!, {}))).toContain("stopped working");
  const home = await json<{ needs_you: Record<string, unknown>[] }>("/home");
  expect(home.needs_you).toEqual([
    expect.objectContaining({ kind: "reconnect", app: expect.objectContaining({ id: "books" }) }),
  ]);
  expect((await usableIn(db, scope.businessId))("books_list_bills")).toBe(false);

  // Reconnecting: the same sign-in; the owner's policy stands, so it is on again.
  await signIn((await json<{ url: string }>("/apps/books/connect", {})).url);
  expect(
    (await json<{ apps: { id: string; state: string }[] }>("/apps")).apps.find(
      (app) => app.id === "books",
    )?.state,
  ).toBe("on");
  expect((await run<{ text: string }>((await remote("books_list_bills"))!, {})).text).toContain(
    "bill-1",
  );

  // Removing it ends its grants and takes its sign-in out of the vault.
  await json("/apps/books/uninstall", {});
  expect(
    (await Effect.runPromise(grantsFor(db, scope))).filter((each) =>
      each.capability.startsWith("books_"),
    ),
  ).toEqual([]);
  expect(
    await sql.row("SELECT 1 FROM secrets WHERE business_id = $1 AND name = 'app-books'", [
      scope.businessId,
    ]),
  ).toBeUndefined();
});

it("an app's identity: serverInfo, then the registry, then its site's icon, then a letter tile", async () => {
  // No icon of its own, none in the registry: its site's apple-touch-icon.
  apps["https://plain.example"] = fakeMcp("https://plain.example", {
    icons: false,
    title: "Plain",
  });
  // Nothing anywhere: no logo (clients draw its first letter).
  apps["https://bare.example"] = fakeMcp("https://bare.example", { icons: false, site: false });
  registry = [
    listing("example.plain/plain", "Plain Registry Name", "https://plain.example"),
    listing("example.bare/bare", "Bare", "https://bare.example"),
  ];
  const { json, signIn } = await owner();
  const plain = await json<{ app: { id: string; name: string; logo: string | null } }>(
    "/apps/add",
    {
      app: "example.plain/plain",
    },
  );
  // Before connecting: the registry's name, and the site's icon.
  expect(plain.app.name).toBe("Plain Registry Name");
  expect(plain.app.logo).not.toBeNull();
  await signIn((await json<{ url: string }>(`/apps/${plain.app.id}/connect`, {})).url);
  // After: what the server says it is.
  const connected = (
    await json<{ apps: { id: string; name: string; logo: string | null }[] }>("/apps")
  ).apps.find((app) => app.id === plain.app.id)!;
  expect(connected.name).toBe("Plain");
  expect(connected.logo).toBe(plain.app.logo);
  const bare = await json<{ app: { logo: string | null } }>("/apps/add", {
    app: "example.bare/bare",
  });
  expect(bare.app.logo).toBeNull();
});

it("a card from a card app: only against a signed approval, for its exact amount, never returned", async () => {
  apps["https://cards.example"] = fakeMcp("https://cards.example");
  const { json, signIn, scope, use, call, work, business: acme } = await owner();
  const added = await json<{ app: { id: string } }>("/apps/add", {
    app: "https://cards.example/mcp",
  });
  const id = added.app.id;
  await signIn((await json<{ url: string }>(`/apps/${id}/connect`, {})).url);
  const review = await json<{ tools: { capability: string; line: string }[] }>(
    `/apps/${id}/review`,
  );
  await json(`/apps/${id}/accept`, {
    lines: Object.fromEntries(review.tools.map((tool) => [tool.capability, tool.line])),
    employees: [scope.employeeId],
  });
  const fields = [{ selector: "#number", part: "number" }];
  const fill = (input: Record<string, unknown>) =>
    use<Record<string, unknown>>("browserFill", {
      card: { app: id, fund: "fund-1" },
      fields,
      ...input,
    });

  // Refused without an approval, and with an unsigned one.
  expect(await failure(fill({}))).toContain("is a card");
  const buy = {
    kind: "approve",
    action: "Register acme-cards.example for one year",
    counterparty: "Shop (shop.example)",
    amount: { cents: 1299, currency: "USD" },
  };
  const asked = await use<{ request: string }>("askOwner", buy);
  expect(await failure(fill({ approval: asked.request }))).toContain("No approved, signed");
  // Signed on the owner's Mac.
  const macKey = await deviceKey();
  const enrolled = (await (
    await call("/api/device-keys", { public_key: macKey.publicKey })
  ).json()) as {
    id: string;
  };
  const payload = spendTerms(
    (await Effect.runPromise(decision(db, acme.id, asked.request)))!,
    acme.id,
  )!;
  expect(
    (
      await call(`/decisions/${asked.request}/approve`, {
        key_id: enrolled.id,
        signature: await macKey.sign(payload),
      })
    ).status,
  ).toBe(200);

  // The host is asked for the app's card of exactly the approval's amount and merchant.
  fillAnswer = () =>
    Response.json({
      origin: "https://shop.example",
      submitted: true,
      last4: "4242",
      reference: "ramp-token-77",
    });
  const filled = await fill({ approval: asked.request, submit: { selector: "#pay" } });
  expect(filled).toEqual({ filled: 1, submitted: true, origin: "https://shop.example" });
  const asking = sent.find((each) => each.path === "/browser/fill")!.body as {
    issue: { tool: string; arguments: Record<string, unknown>; sealed: { name: string } };
    merchant: string;
  };
  expect(asking.merchant).toBe("Shop (shop.example)");
  expect(asking.issue.tool).toBe("ramp_get_agent_card_creds");
  expect(asking.issue.sealed.name).toBe(`app-${id}`);
  expect(asking.issue.arguments).toMatchObject({
    fund_id: "fund-1",
    amount: "12.99",
    currency_code: "USD",
    merchant_url: "https://shop.example",
    merchant_country_code: "US",
    idempotency_key: `devys-${asked.request}`,
  });
  const item = (await Effect.runPromise(workItem(db, scope.businessId, work.id)))!;
  expect(item.evidence.map((entry) => entry.note)).toContain(
    "A one-time card ending 4242 filled at https://shop.example and submitted, against the signed spend approval.",
  );
  // One approval, one card.
  expect(await failure(fill({ approval: asked.request }))).toContain("No approved, signed");
});
