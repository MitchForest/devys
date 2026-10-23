import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { apiRoute } from "../src/app/http.ts";
import { spendTerms } from "../src/app/asking.ts";
import { modeOf } from "../src/app/mode.ts";
import { decisionRoute } from "../src/app/work.ts";
import { ref } from "../src/protocol/ref.ts";
import { decision, grant } from "../src/authority/service.ts";
import { endorsementPayload, spendPayload } from "../src/authority/signing.ts";
import type { Inbound } from "../src/channels/contract.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { createWorkItem } from "../src/work/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";
import { deviceKey } from "./fixtures/signing.ts";

/** Records what each employee runtime receives instead of running one. */
const received: { employee: string; input: Inbound }[] = [];
const bindings = {
  ...env,
  AGENT: {
    getByName: (name: string) => ({
      receive: async (_scope: unknown, input: Inbound) => {
        received.push({ employee: (JSON.parse(name) as string[])[1]!, input });
        return { accepted: true };
      },
    }),
  },
} as unknown as Env;
const askOwner = capabilities(bindings).find((item) => item.name === "askOwner")!;

/** An employee's turn, in a work item's thread when it has one. */
const as = (scope: { businessId: string; employeeId: string }, workItemId?: string) =>
  Effect.provideService(Invocation, {
    ...scope,
    ...(workItemId ? { workItemId, conversation: `work:${workItemId}` } : {}),
    operationId: crypto.randomUUID(),
    authorize: (capability, input) =>
      Effect.promise(() =>
        authorize(bindings, scope, capability, input, workItemId ? { workItemId } : {}),
      ).pipe(
        Effect.flatMap((outcome) =>
          outcome.outcome === "allow" ? Effect.void : Effect.fail(new Error(outcome.outcome)),
        ),
        Effect.orDie,
      ),
    assertActive: () => Effect.void,
  });

const token = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");

/** A signed-in device of the person: native (Bearer) or a browser (cookie, same origin). */
async function signedIn(person: string, label: string) {
  const value = token();
  const hash = await sha256(value);
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', $3)",
    [hash, person, label],
  );
  const call = (path: string, body?: unknown, browser = false) =>
    apiRoute(
      new Request(`https://devys.test/api${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: browser
          ? {
              cookie: `__Host-devys=${value}`,
              origin: "https://devys.test",
              "content-type": "application/json",
            }
          : { authorization: `Bearer ${value}`, "content-type": "application/json" },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      bindings,
    ).then((response) => response!);
  return { call, device: hash.slice(0, 16) };
}

async function owner() {
  const acme = await business("Asking");
  const { scope } = acme;
  await Effect.runPromise(grant(db, scope, { capability: askOwner, mode: "auto" }));
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Register the domain",
      createdBy: `person:${acme.person}`,
    }),
  );
  const mac = await signedIn(acme.person, "Mac");
  const at = (path: string) => `/businesses/${scope.businessId}${path}`;
  /** `null` asks outside any work item's thread. */
  const ask = (input: unknown, workItemId: string | null = work.id) =>
    Effect.runPromise(
      askOwner.execute(input).pipe(as(scope, workItemId ?? undefined)) as Effect.Effect<{
        request: string;
        state: string;
      }>,
    );
  /**
   * The thread, without hand-offs: under the full run another file's dispatcher may hand this
   * work item on and post its card here at any time.
   */
  const thread = async () =>
    (
      (await (
        await mac.call(at(`/conversations/${encodeURIComponent(`work:${work.id}`)}`))
      ).json()) as { messages: { text: string; mentions: string[]; ref: string | null }[] }
    ).messages.filter((message) => !message.ref?.startsWith("devys:work/item/"));
  return { ...acme, work, mac, at, ask, thread };
}

/** Why a call was refused. */
const refusal = (call: Promise<unknown>) =>
  call.then(
    () => "",
    (error: unknown) => (error instanceof Error ? error.message : String(error)),
  );

it("askOwner is asked in a work item's thread; elsewhere it refuses and says where", async () => {
  const { ask } = await owner();
  expect(
    await refusal(ask({ kind: "approve", action: "Merge", counterparty: "GitHub" }, null)),
  ).toContain("asked in a work item's thread");
  expect((await ask({ kind: "approve", action: "Merge", counterparty: "GitHub" })).state).toBe(
    "asked",
  );
  // A request is stated exactly: an unknown kind or an empty action is refused.
  for (const input of [
    { kind: "secret", name: "card" },
    { kind: "approve", action: "", counterparty: "GitHub" },
    { kind: "approve", action: "Buy", counterparty: "X", amount: { cents: 12.5, currency: "USD" } },
  ])
    expect(await refusal(ask(input))).toContain("Invalid arguments");
});

it("an approve is answered with a tap; the answer is said in the thread and asking again reads it", async () => {
  const { scope, ask, mac, at, thread } = await owner();
  const merge = { kind: "approve", action: "Merge pull request #12", counterparty: "GitHub" };
  const asked = await ask(merge);
  expect(asked.state).toBe("asked");
  expect((await ask(merge)).request).toBe(asked.request);
  const home = (await (await mac.call(at("/home"))).json()) as {
    needs_you: { id: string; kind: string; input: unknown }[];
  };
  expect(home.needs_you).toEqual([
    expect.objectContaining({ id: asked.request, kind: "approve", input: merge }),
  ]);
  received.length = 0;
  expect((await mac.call(at(`/decisions/${asked.request}/approve`), {})).status).toBe(200);
  expect((await thread()).at(-1)).toMatchObject({
    text: "Approved: Merge pull request #12 (GitHub). Go ahead, exactly as asked, once.",
    mentions: [scope.employeeId],
  });
  expect(received.map((each) => each.employee)).toEqual([scope.employeeId]);
  expect(await ask(merge)).toMatchObject({ request: asked.request, state: "approved" });
  // A declined request stands: asking again reads the answer instead of asking again.
  const deploy = { kind: "approve", action: "Deploy to production", counterparty: "Cloudflare" };
  const second = await ask(deploy);
  expect((await mac.call(at(`/decisions/${second.request}/reject`), {})).status).toBe(200);
  expect((await thread()).at(-1)?.text).toBe(
    "Declined: Deploy to production. Don't do it; find another way or ask me.",
  );
  expect(await ask(deploy)).toMatchObject({ request: second.request, state: "declined" });
});

it("a spend approval needs a device signature over exactly the request; the web cannot answer it", async () => {
  const { business: acme, work, mac, at, ask, thread, person } = await owner();
  const buy = {
    kind: "approve",
    action: "Register acme-plumbing.example for one year",
    counterparty: "Namecheap",
    amount: { cents: 1299, currency: "USD" },
    renewal: "Renews yearly at $14.99",
  };
  const asked = await ask(buy);
  const approve = (body: unknown, caller = mac.call, browser = false) =>
    caller(at(`/decisions/${asked.request}/approve`), body, browser);

  // The Mac enrolls its key (first key: active); a browser cannot enroll one.
  const macKey = await deviceKey();
  const browser = await signedIn(person, "Web browser");
  expect((await browser.call("/device-keys", { public_key: macKey.publicKey }, true)).status).toBe(
    403,
  );
  const enrolled = (await (
    await mac.call("/device-keys", { public_key: macKey.publicKey })
  ).json()) as { id: string; status: string; label: string };
  expect(enrolled).toMatchObject({ status: "active", label: "Mac" });

  const payload = spendTerms(
    (await Effect.runPromise(decision(db, acme.id, asked.request)))!,
    acme.id,
  )!;
  expect(JSON.parse(payload)).toMatchObject({
    decision: asked.request,
    business: acme.id,
    work_item: work.id,
    amount_cents: 1299,
    counterparty: "Namecheap",
    renewal: "Renews yearly at $14.99",
    type: "spend_approval",
  });
  // Without a signature, from the web, with an unknown key, another key's signature, or a
  // signature over a changed amount, merchant or action: refused, and still pending.
  expect((await approve({})).status).toBe(403);
  expect((await approve({}, browser.call, true)).status).toBe(403);
  const signature = await macKey.sign(payload);
  expect((await approve({ key_id: crypto.randomUUID(), signature })).status).toBe(403);
  const stranger = await deviceKey();
  expect(
    (await approve({ key_id: enrolled.id, signature: await stranger.sign(payload) })).status,
  ).toBe(403);
  const terms = JSON.parse(payload) as Record<string, unknown>;
  for (const changed of [
    { amount_cents: 1499 },
    { counterparty: "GoDaddy" },
    { action: "Register two domains" },
  ]) {
    const other = spendPayload({
      decision: asked.request,
      business: acme.id,
      workItem: work.id,
      action: String(changed.action ?? terms.action),
      counterparty: String(changed.counterparty ?? terms.counterparty),
      amountCents: Number(changed.amount_cents ?? terms.amount_cents),
      currency: "USD",
      renewal: "Renews yearly at $14.99",
      steps: [],
      preview: null,
      previewHash: null,
      expiresAt: String(terms.expires_at),
    });
    expect(
      (await approve({ key_id: enrolled.id, signature: await macKey.sign(other) })).status,
    ).toBe(403);
  }
  expect(
    (
      await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [
        asked.request,
      ])
    )?.status,
  ).toBe("pending");
  // The table itself refuses an unsigned approval.
  await expect(
    sql.run("UPDATE decisions SET status = 'approved' WHERE id = $1", [asked.request]),
  ).rejects.toThrow(/decisions_spend_signed/);

  // Signed on the Mac: approved once, with the key and signature kept; a replay conflicts.
  expect((await approve({ key_id: enrolled.id, signature })).status).toBe(200);
  expect((await approve({ key_id: enrolled.id, signature })).status).toBe(409);
  expect(
    await sql.row("SELECT status, signed_by, signature FROM decisions WHERE id = $1", [
      asked.request,
    ]),
  ).toEqual({ status: "approved", signed_by: enrolled.id, signature });
  expect((await thread()).at(-1)?.text).toBe(
    "Approved and signed: Register acme-plumbing.example for one year (Namecheap for 12.99 USD). Go ahead, exactly as asked, once.",
  );
  const home = (await (await mac.call(at("/home"))).json()) as { glance: { spent_cents: number } };
  expect(home.glance.spent_cents).toBe(1299);
  // A changed amount is a new request.
  expect((await ask({ ...buy, amount: { cents: 1499, currency: "USD" } })).state).toBe("asked");
});

it("a later device signs only once an enrolled one allows it; a signed-out device's key stops", async () => {
  const { person } = await owner();
  const mac = await signedIn(person, "Mac");
  const phone = await signedIn(person, "iPhone");
  const [macKey, phoneKey] = [await deviceKey(), await deviceKey()];
  const first = (await (
    await mac.call("/device-keys", { public_key: macKey.publicKey })
  ).json()) as { id: string; status: string };
  const second = (await (
    await phone.call("/device-keys", { public_key: phoneKey.publicKey })
  ).json()) as { id: string; status: string; device: string; public_key: string };
  expect([first.status, second.status]).toEqual(["active", "pending"]);
  const allow = endorsementPayload({
    person,
    key: second.id,
    device: phone.device,
    publicKey: phoneKey.publicKey,
  });
  // The pending key cannot allow itself; a signature over another key's payload is refused.
  expect(
    (
      await phone.call(`/device-keys/${second.id}/endorse`, {
        key_id: second.id,
        signature: await phoneKey.sign(allow),
      })
    ).status,
  ).toBe(403);
  expect(
    (
      await mac.call(`/device-keys/${second.id}/endorse`, {
        key_id: first.id,
        signature: await macKey.sign(allow.replace(phone.device, mac.device)),
      })
    ).status,
  ).toBe(403);
  const endorsed = await mac.call(`/device-keys/${second.id}/endorse`, {
    key_id: first.id,
    signature: await macKey.sign(allow),
  });
  expect(endorsed.status).toBe(200);
  const listed = (await (await phone.call("/device-keys")).json()) as {
    keys: { id: string; status: string; current: boolean }[];
  };
  expect(listed.keys).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ id: second.id, status: "active", current: true }),
      expect.objectContaining({ id: first.id, status: "active", current: false }),
    ]),
  );
  // Signing the Mac out (from the iPhone) revokes its key.
  expect((await phone.call(`/devices/${mac.device}/revoke`, {})).status).toBe(200);
  const after = (await (await phone.call("/device-keys")).json()) as { keys: { id: string }[] };
  expect(after.keys.map((key) => key.id)).toEqual([second.id]);
});

it("a take-over request is answered by taking the work over, and handing it back says it is done", async () => {
  const { scope, work, mac, at, ask, thread } = await owner();
  const signIn = {
    kind: "take_over",
    reason: "Sign in to the registrar (2FA)",
    url: "https://www.namecheap.com/myaccount/login/",
  };
  const asked = await ask(signIn);
  const home = (await (await mac.call(at("/home"))).json()) as {
    needs_you: { id: string; kind: string }[];
  };
  expect(home.needs_you).toEqual([
    expect.objectContaining({ id: asked.request, kind: "take_over" }),
  ]);
  // Approving is not how: the owner takes the work over.
  expect((await mac.call(at(`/decisions/${asked.request}/approve`), {})).status).toBe(409);
  expect((await mac.call(at(`/work/${work.id}/takeover`), {})).status).toBe(200);
  const taken = (await (await mac.call(at("/home"))).json()) as { needs_you: unknown[] };
  expect(taken.needs_you).toEqual([]);
  // While it is taken over the employee is fenced, and cannot ask there.
  expect(await refusal(ask(signIn))).not.toBe("");
  received.length = 0;
  expect((await mac.call(at(`/work/${work.id}/release`), {})).status).toBe(200);
  expect((await thread()).at(-1)).toMatchObject({
    text: "Done: Sign in to the registrar (2FA). I've handed the work back; carry on.",
    mentions: [scope.employeeId],
  });
  expect(received.some((each) => each.employee === scope.employeeId)).toBe(true);
  expect(await ask(signIn)).toMatchObject({ state: "asked" });
  expect(
    (
      await mac
        .call(at(`/decisions?work_item=${work.id}`))
        .then(
          (response) => response.json() as Promise<{ decisions: { id: string; status: string }[] }>,
        )
    ).decisions.find((each) => each.id === asked.request)?.status,
  ).toBe("used");
});

/** A page of the business, as an employee publishes it: a new version under the same name. */
async function publishPage(businessId: string, filename: string, text: string) {
  const id = crypto.randomUUID();
  const key = `${businessId}/artifacts/${id}`;
  await bindings.FILES.put(key, text);
  await sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ($1, $2, $3, $4, $5, 'text/html', $6)`,
    [id, businessId, crypto.randomUUID(), key, filename, text.length],
  );
  return ref("documents", "artifact", id);
}

it("an approve shows its draft and steps, bound by the draft's content: a changed draft voids it", async () => {
  const { business: acme, mac, at, ask, thread } = await owner();
  const draft = await publishPage(acme.id, "quote.html", "<p>Quote: $400</p>");
  const send = {
    kind: "approve",
    action: "Email the quote to Ada",
    counterparty: "ada@example.com",
    steps: ["Send the quote to ada@example.com", "Mark the lead quoted"],
    preview: draft,
  };
  const asked = await ask(send);
  // The draft's content is bound into the request (by the server, not the employee).
  const stored = (await Effect.runPromise(decision(db, acme.id, asked.request)))!;
  expect(stored.input).toMatchObject({ ...send, previewHash: await sha256("<p>Quote: $400</p>") });
  expect((await mac.call(at(`/decisions/${asked.request}/approve`), {})).status).toBe(200);
  expect((await thread()).at(-1)?.text).toBe(
    "Approved: Email the quote to Ada (ada@example.com). These steps: Send the quote to ada@example.com; Mark the lead quoted. Go ahead, exactly as asked, once.",
  );
  expect(await ask(send)).toMatchObject({ request: asked.request, state: "approved" });

  // Asked again with other steps, then the page changes before the owner answers.
  const resend = { ...send, steps: ["Send the quote to ada@example.com"] };
  const second = await ask(resend);
  expect(second.request).not.toBe(asked.request);
  await publishPage(acme.id, "quote.html", "<p>Quote: $450</p>");
  expect((await mac.call(at(`/decisions/${second.request}/approve`), {})).status).toBe(409);
  expect((await thread()).at(-1)?.text).toContain("That draft changed after you asked");
  // Asking again binds the draft as it is now: a new request.
  const third = await ask(resend);
  expect(third).toMatchObject({ state: "asked" });
  expect(third.request).not.toBe(second.request);
  // The approval already given no longer stands for the changed draft either.
  expect((await ask(send)).state).toBe("asked");
  // A draft is a page or file of this business.
  expect(
    await refusal(ask({ ...send, preview: ref("documents", "artifact", crypto.randomUUID()) })),
  ).toContain("Preview a page or a file");
  expect(
    await refusal(ask({ ...send, preview: ref("work", "item", crypto.randomUUID()) })),
  ).toContain("Invalid arguments");
});

it("a file request is answered with the file the owner chooses, put in the business folder", async () => {
  const { business: acme, person, mac, at, ask, thread } = await owner();
  const asked = await ask({
    kind: "file",
    purpose: "Your logo, for the site",
    accept: ["image/*"],
  });
  expect(asked.state).toBe("asked");
  // Approving is not how: the owner chooses the file.
  expect((await mac.call(at(`/decisions/${asked.request}/approve`), {})).status).toBe(409);

  const hostUrl = "http://127.0.0.1:1";
  const local = {
    ...bindings,
    DEVYS_MODE: "local",
    DEVYS_HOST_URL: hostUrl,
    DEVYS_HOST_TOKEN: "host-token",
    DEVYS_HOST_HOME: "/Users/owner",
  } as unknown as Env;
  const folder = modeOf(local).businessFolder(acme.id)!;
  const written: string[] = [];
  const realFetch = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.origin !== hostUrl) return realFetch(input, init);
    const path = url.searchParams.get("path")!;
    // logo.png is already there: it is never written over.
    if (path === `${folder}/Uploads/logo.png`)
      return new Response("Revision conflict: the file exists", { status: 409 });
    written.push(path);
    return Response.json({});
  });
  try {
    const choose = (type: string, name: string) =>
      decisionRoute(
        new Request(
          `https://devys.test/api/businesses/${acme.id}/decisions/${asked.request}/file?name=${encodeURIComponent(name)}`,
          { method: "POST", headers: { "content-type": type }, body: new Uint8Array([1, 2, 3]) },
        ),
        local,
        {
          person: { id: person } as never,
          business: { id: acme.id } as never,
          trusted: true,
          path: `/decisions/${asked.request}/file`,
        },
      );
    expect((await choose("application/pdf", "logo.pdf")).status).toBe(415);
    received.length = 0;
    expect((await choose("image/png", "logo.png")).status).toBe(200);
    const file = ref("documents", "file", `${folder}/Uploads/logo 2.png`);
    expect(written).toEqual([`${folder}/Uploads/logo 2.png`]);
    // The thread shows the file, and the employee alone is told its ref.
    const said = await thread();
    expect(said.at(-1)?.text).toBe("Here's the file: logo 2.png.");
    expect(said.at(-1)?.text).not.toContain(file);
    expect(said.some((message) => message.ref === file)).toBe(true);
    expect(received[0]!.input.text).toContain(file);
    expect(
      await ask({ kind: "file", purpose: "Your logo, for the site", accept: ["image/*"] }),
    ).toMatchObject({ request: asked.request, state: "done", file });
    expect((await choose("image/png", "logo.png")).status).toBe(409);
  } finally {
    vi.restoreAllMocks();
  }
});
