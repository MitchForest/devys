/**
 * LP3: secrets by name and the card, from the Worker's side. The Mac host is stood in for by its
 * own vault route (sealing with a real keyring) and a recording browser; the database is real.
 */
import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { apiRoute } from "../src/app/http.ts";
import { spendTerms } from "../src/app/asking.ts";
import { secretsRoute } from "../src/app/vault.ts";
import { decision, grant } from "../src/authority/service.ts";
import type { Inbound } from "../src/channels/contract.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { Invocation } from "../src/protocol/capability.ts";
import type { Sealed } from "../src/vault/contract.ts";
import { envelopeKeyring } from "../src/vault/envelope.ts";
import { vaultHost } from "../src/vault/host/server.ts";
import { createWorkItem, workItem } from "../src/work/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";
import { deviceKey } from "./fixtures/signing.ts";

const received: { employee: string; input: Inbound }[] = [];
const agent = {
  getByName: (name: string) => ({
    receive: async (_scope: unknown, input: Inbound) => {
      received.push({ employee: (JSON.parse(name) as string[])[1]!, input });
      return { accepted: true };
    },
  }),
};
const hostUrl = "http://127.0.0.1:1";
/** Local mode, with the Mac host at `hostUrl` (answered below). */
const local = {
  ...env,
  AGENT: agent,
  DEVYS_MODE: "local",
  DEVYS_HOST_URL: hostUrl,
  DEVYS_HOST_TOKEN: "host-token",
  DEVYS_HOST_HOME: "/Users/owner",
} as unknown as Env;
/** Cloud mode, where no one holds the vault's key yet. */
const cloud = { ...env, AGENT: agent } as unknown as Env;

const keyring = await envelopeKeyring(crypto.getRandomValues(new Uint8Array(32)));
/** What the stand-in host was sent, by path. */
const sent: { path: string; body: Record<string, unknown> }[] = [];
/** How the stand-in browser answers a fill. */
let fillAnswer: () => Response = () =>
  Response.json({ origin: "https://shop.example", submitted: true, last4: "4242" });

beforeEach(() => {
  sent.length = 0;
  const realFetch = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.origin !== hostUrl) return realFetch(input, init);
    const body = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
    sent.push({ path: url.pathname, body });
    if (url.pathname.startsWith("/vault/"))
      return Response.json(await vaultHost(keyring).handle(url.pathname, body));
    if (url.pathname === "/browser/fill") return fillAnswer();
    return new Response("Not found", { status: 404 });
  });
});
afterEach(() => vi.restoreAllMocks());

const token = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");

/** A business with its owner signed in on the Mac, and an employee's work item. */
async function owner() {
  const acme = await business("Vault");
  const { scope, person } = acme;
  const catalog = capabilities(local);
  for (const name of ["askOwner", "browserFill", "run"])
    await Effect.runPromise(
      grant(db, scope, { capability: catalog.find((c) => c.name === name)!, mode: "auto" }),
    );
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Register the domain",
      createdBy: `person:${person}`,
    }),
  );
  const session = token();
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', 'Mac')",
    [await sha256(session), person],
  );
  const at = `/api/businesses/${scope.businessId}`;
  /** The API as the owner's Mac app calls it (cloud bindings: anyone may use the machine). */
  const call = (path: string, body?: unknown) =>
    apiRoute(
      new Request(`https://devys.test${path.startsWith("/api/") ? "" : at}${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: { authorization: `Bearer ${session}`, "content-type": "application/json" },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      cloud,
    ).then((response) => response!);
  /** Settings › Secrets on the Mac (local mode, its host standing in). */
  const secrets = (method: string, path = "/secrets", body?: string) =>
    secretsRoute(new Request(`https://devys.test${at}${path}`, { method, body }), local, {
      person: { id: person } as never,
      business: acme.business,
      trusted: true,
      path,
    });
  const capability = (name: string) => catalog.find((item) => item.name === name)!;
  /** One of the employee's capabilities, run in the work item's thread. */
  const use = <T>(name: string, input: unknown, workItemId: string | null = work.id) =>
    Effect.runPromise(
      capability(name)
        .execute(input)
        .pipe(
          Effect.provideService(Invocation, {
            ...scope,
            ...(workItemId ? { workItemId, conversation: `work:${workItemId}` } : {}),
            operationId: crypto.randomUUID(),
            authorize: (cap, value) =>
              Effect.promise(() =>
                authorize(local, scope, cap, value, workItemId ? { workItemId } : {}),
              ).pipe(Effect.asVoid),
            assertActive: () => Effect.void,
          }),
        ) as Effect.Effect<T>,
    );
  const thread = async () =>
    (
      (await (await call(`/conversations/${encodeURIComponent(`work:${work.id}`)}`)).json()) as {
        messages: { text: string }[];
      }
    ).messages;
  return { ...acme, work, call, secrets, use, thread };
}

const failure = (run: Promise<unknown>) =>
  run.then(
    () => "",
    (error: unknown) => (error instanceof Error ? error.message : String(error)),
  );

const card = {
  number: "4242424242424242",
  expiry: "04/31",
  cvc: "737",
  name: "Sam Owner",
  postal: "94107",
};

it("a secret goes in by name, is stored sealed, and no Worker response ever holds its value", async () => {
  const { scope, secrets, call } = await owner();
  const value = "devys-test-secret-value-0123456789";
  const added = await secrets(
    "POST",
    "/secrets",
    JSON.stringify({ name: "STRIPE_KEY", kind: "secret", value }),
  );
  expect(added.status).toBe(201);
  const text = await added.text();
  expect(text).not.toContain(value);
  expect(JSON.parse(text)).toMatchObject({ secrets: [{ name: "STRIPE_KEY", kind: "secret" }] });
  // Postgres holds ciphertext only; the host's keyring alone opens it, for this business only.
  const row = (await sql.row<{ data_key: string; ciphertext: string }>(
    "SELECT data_key, ciphertext FROM secrets WHERE business_id = $1 AND name = 'STRIPE_KEY'",
    [scope.businessId],
  ))!;
  expect(row.ciphertext + row.data_key).not.toContain(value);
  const sealed: Sealed = {
    business: scope.businessId,
    name: "STRIPE_KEY",
    kind: "secret",
    key: row.data_key,
    data: row.ciphertext,
  };
  expect(await keyring.open(sealed)).toBe(value);
  for (const moved of [
    { ...sealed, business: "another" },
    { ...sealed, name: "OTHER_KEY" },
    { ...sealed, kind: "spend" as const },
  ])
    await expect(keyring.open(moved)).rejects.toThrow();
  // Refusals never repeat what was sent; nor does listing; the size is bounded.
  for (const body of [
    { name: "lowercase", kind: "secret", value },
    { name: "STRIPE_KEY", kind: "secret", value: `${value}${"x".repeat(17_000)}` },
    { name: "RAMP_CARD", kind: "spend", card: { ...card, number: "4242424242424241" } },
    { name: "RAMP_CARD", kind: "spend", card: { ...card, expiry: "4/31" } },
  ]) {
    const refused = await secrets("POST", "/secrets", JSON.stringify(body));
    expect(refused.status).toBe(400);
    const said = await refused.text();
    expect(said).not.toContain(value);
    expect(said).not.toContain("424242424242");
  }
  expect(await (await call("/secrets")).text()).not.toContain(value);
  // Cloud mode has no keyring yet: listing works, adding is refused.
  expect((await call("/secrets", { name: "OTHER", kind: "secret", value: "x-value" })).status).toBe(
    503,
  );
  // Removed by name.
  expect((await secrets("DELETE", "/secrets/STRIPE_KEY")).status).toBe(200);
  expect((await secrets("DELETE", "/secrets/STRIPE_KEY")).status).toBe(404);
  expect(await (await call("/secrets")).json()).toEqual({ secrets: [] });
});

it("an employee asks for a secret; the owner enters it in the secure sheet; it is answered in the thread", async () => {
  const { use, call, secrets, thread, scope } = await owner();
  const ask = {
    kind: "secret",
    name: "RAMP_CARD",
    why: "The company card, for the domain",
    spend: true,
  };
  const asked = await use<{ request: string; state: string }>("askOwner", ask);
  expect(asked.state).toBe("asked");
  const home = (await (await call("/home")).json()) as {
    needs_you: { id: string; kind: string; input: unknown }[];
  };
  expect(home.needs_you).toEqual([
    expect.objectContaining({ id: asked.request, kind: "secret", input: ask }),
  ]);
  // Only adding the secret answers it; a plain secret of that name does not answer a card request.
  expect((await call(`/decisions/${asked.request}/approve`, {})).status).toBe(409);
  await secrets(
    "POST",
    "/secrets",
    JSON.stringify({ name: "RAMP_CARD", kind: "secret", value: "not-a-card" }),
  );
  expect((await use<{ state: string }>("askOwner", ask)).state).toBe("asked");
  received.length = 0;
  const entered = await secrets(
    "POST",
    "/secrets",
    JSON.stringify({ name: "RAMP_CARD", kind: "spend", card }),
  );
  expect(entered.status).toBe(201);
  expect(await entered.text()).not.toContain(card.number);
  expect((await thread()).at(-1)?.text).toBe("Added RAMP_CARD (a card): use it by name.");
  expect(received.map((each) => each.employee)).toEqual([scope.employeeId]);
  expect(await use<{ state: string }>("askOwner", ask)).toMatchObject({ state: "done" });
  // The thread, the transcript-facing results and Home hold the name only.
  expect(JSON.stringify(await thread())).not.toContain(card.number);
  expect(await (await call("/home")).text()).not.toContain(card.number);
});

it("run hands the host the named secrets sealed; a missing one is asked for by name", async () => {
  const { use, secrets, scope } = await owner();
  await secrets(
    "POST",
    "/secrets",
    JSON.stringify({ name: "API_TOKEN", kind: "secret", value: "tok-123456" }),
  );
  // The host's answer stands in; what matters is what it was sent.
  vi.mocked(globalThis.fetch).mockImplementation(async (input, init) => {
    const url = new URL(String(input));
    sent.push({ path: url.pathname, body: JSON.parse(String(init?.body)) });
    return Response.json({ status: "completed", exitCode: 0, stdout: "[redacted]\n", stderr: "" });
  });
  expect(await use("run", { command: "echo $API_TOKEN", secrets: ["API_TOKEN"] })).toMatchObject({
    stdout: "[redacted]\n",
  });
  const run = sent.find((each) => each.path === "/run")!;
  expect(JSON.stringify(run.body)).not.toContain("tok-123456");
  expect(run.body.secrets).toEqual([
    expect.objectContaining({ business: scope.businessId, name: "API_TOKEN", kind: "secret" }),
  ]);
  expect(await failure(use("run", { command: "true", secrets: ["NOT_ADDED"] }))).toContain(
    "No secret or card named NOT_ADDED",
  );
});

it("a card is filled only against a signed, unused spend approval of this work item, and only once", async () => {
  const { use, secrets, call, scope, work, business: acme } = await owner();
  await secrets("POST", "/secrets", JSON.stringify({ name: "RAMP_CARD", kind: "spend", card }));
  await secrets(
    "POST",
    "/secrets",
    JSON.stringify({ name: "SITE_PASSWORD", kind: "secret", value: "hunter2-pass" }),
  );
  const fields = [{ selector: "#number", part: "number" }];
  const fill = (input: Record<string, unknown>, workItemId: string | null = work.id) =>
    use<{ filled: number; submitted: boolean; origin: string }>(
      "browserFill",
      { secret: "RAMP_CARD", fields, ...input },
      workItemId,
    );

  // A password needs no approval.
  expect(
    await use("browserFill", {
      secret: "SITE_PASSWORD",
      fields: [{ selector: "#pw", part: "value" }],
    }),
  ).toMatchObject({ filled: 1 });
  // A card: not without an approval, not outside a thread, not with an unsigned or unknown one.
  expect(await failure(fill({}))).toContain("is a card");
  expect(await failure(fill({ approval: crypto.randomUUID() }, null))).toContain(
    "work item's thread",
  );
  const free = await use<{ request: string }>("askOwner", {
    kind: "approve",
    action: "Merge",
    counterparty: "GitHub",
  });
  expect((await call(`/decisions/${free.request}/approve`, {})).status).toBe(200);
  expect(await failure(fill({ approval: free.request }))).toContain("No approved, signed");
  const buy = {
    kind: "approve",
    action: "Register acme-vault.example for one year",
    counterparty: "Shop (shop.example)",
    amount: { cents: 1299, currency: "USD" },
  };
  const asked = await use<{ request: string }>("askOwner", buy);
  expect(await failure(fill({ approval: asked.request }))).toContain("No approved, signed");

  // The owner's Mac signs it with its device key.
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

  // The page isn't the merchant's: the host refuses before filling, and the approval stands.
  fillAnswer = () =>
    new Response("This page is on other.example, not shop.example, which the approval names", {
      status: 403,
    });
  expect(await failure(fill({ approval: asked.request }))).toContain("not shop.example");
  const fills = () => sent.filter((each) => each.path === "/browser/fill");
  expect(fills().at(-1)?.body).toMatchObject({ merchant: "Shop (shop.example)" });
  expect(JSON.stringify(fills().at(-1)?.body)).not.toContain(card.number);
  expect(
    (
      await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [
        asked.request,
      ])
    )?.status,
  ).toBe("approved");

  // On the merchant's page: filled, recorded, and the approval spent.
  fillAnswer = () =>
    Response.json({ origin: "https://shop.example", submitted: true, last4: "4242" });
  const filled = await fill({ approval: asked.request, submit: { selector: "#pay" } });
  expect(filled).toEqual({ filled: 1, submitted: true, origin: "https://shop.example" });
  expect(JSON.stringify(filled)).not.toContain(card.number);
  const item = (await Effect.runPromise(workItem(db, scope.businessId, work.id)))!;
  expect(item.evidence.map((entry) => entry.note)).toContain(
    `Card RAMP_CARD ending 4242 filled at https://shop.example and submitted, against spend approval ${asked.request}.`,
  );
  expect(
    (
      await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [
        asked.request,
      ])
    )?.status,
  ).toBe("used");
  // One approval, one fill.
  expect(await failure(fill({ approval: asked.request }))).toContain("No approved, signed");
  // Another work item cannot spend this work item's approval.
  const other = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Something else",
      createdBy: "person:x",
    }),
  );
  expect(await failure(fill({ approval: asked.request }, other.id))).toContain(
    "No approved, signed",
  );
});
