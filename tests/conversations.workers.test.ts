import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import {
  postFromEmployee,
  recordChannelMessage,
  recordChannelReply,
} from "../src/app/conversations.ts";
import { authorize } from "../src/app/authorize.ts";
import { apiRoute } from "../src/app/http.ts";
import { grant } from "../src/authority/service.ts";
import { Effect } from "effect";
import { hire, hireInput } from "../src/identity/team.ts";
import { hiring } from "../src/app/team.ts";
import { capabilities } from "../src/app/capabilities.ts";
import type { Inbound } from "../src/channels/contract.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { business, sql } from "./fixtures/postgres.ts";

/** Records what each employee runtime receives instead of running one. */
function recording() {
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
  return { received, bindings };
}

async function owner() {
  const acme = await business("Conversations");
  const { received, bindings } = recording();
  const team = hiring(() => capabilities(bindings));
  const growth = await hire(
    bindings.HYPERDRIVE,
    acme.business.id,
    hireInput({ template: "growth" }, team) as Exclude<ReturnType<typeof hireInput>, string>,
    team,
  );
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), acme.person],
  );
  const as = (path: string, init: RequestInit = {}) =>
    apiRoute(
      new Request(`https://devys.test/api/businesses/${acme.business.id}${path}`, {
        ...init,
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      }),
      bindings,
    ).then((response) => response ?? new Response(null, { status: 404 }));
  const say = async (key: string, body: Record<string, unknown>) =>
    (await (
      await as(`/conversations/${key}/messages`, { method: "POST", body: JSON.stringify(body) })
    ).json()) as { message: { id: string }; to: string[] };
  return { acme, growth, received, bindings, as, say };
}

it("a DM continues with its employee; a reply from the employee lands in the same DM", async () => {
  const { acme, received, bindings, as, say } = await owner();
  const ops = acme.operations.id;
  const first = await say(`direct:${ops}`, { id: "dm-message-0001", text: "What is next?" });
  expect(first.to).toEqual([ops]);
  expect(received.at(-1)?.input.chatId).toBe(`app:${acme.business.id}:${ops}`);
  // Retrying the same post stores it once and delivers it again under the same message id
  // (the runtime admits it once), so a retry after a failed delivery still wakes the employee.
  await say(`direct:${ops}`, { id: "dm-message-0001", text: "What is next?" });
  expect(received).toHaveLength(2);
  expect(received[1]!.input.messageId).toBe(received[0]!.input.messageId);

  await postFromEmployee(
    bindings,
    received[0]!.input.chatId,
    "Launch plan first.",
    "op-1",
    first.message.id,
  );
  await postFromEmployee(
    bindings,
    received[0]!.input.chatId,
    "Launch plan first.",
    "op-1",
    first.message.id,
  );
  const page = (await (await as(`/conversations/direct:${ops}`)).json()) as {
    messages: { author: string; text: string; reply_to: string | null }[];
    respondent: string;
  };
  expect(page.messages.map((m) => [m.author, m.text])).toEqual([
    [`person:${acme.person}`, "What is next?"],
    [`employee:${ops}`, "Launch plan first."],
  ]);
  expect(page.messages[1]?.reply_to).toBe(first.message.id);
  expect(page.respondent).toBe(ops);
});

it("in a project the lead answers first, then whoever spoke last, and a mention brings someone in", async () => {
  const { acme, growth, received, bindings, as, say } = await owner();
  const ops = acme.operations.id;
  const project = (await (
    await as("/projects", {
      method: "POST",
      body: JSON.stringify({ name: "Launch", goal: "Go live", deadline: "2026-12-01" }),
    })
  ).json()) as { id: string };
  const key = `project:${project.id}`;
  expect((await say(key, { id: "project-message-01", text: "Plan?" })).to).toEqual([ops]);
  const opsChat = received.at(-1)!.input.chatId;
  expect(opsChat).toBe(`app:${acme.business.id}:${ops}:project:${project.id}`);
  expect(received.at(-1)!.input.text).toContain(
    `In the project "Launch" (devys:work/project/${project.id}; goal: Go live; deadline 2026-12-01). This is its channel: say results, hand-offs and questions here; post progress in the work item's own thread.`,
  );
  await postFromEmployee(
    bindings,
    opsChat,
    "Domain, then site.",
    "op-2",
    received.at(-1)!.input.messageId,
  );
  // No mention: Operations spoke last, so Operations continues.
  expect((await say(key, { id: "project-message-02", text: "Go on." })).to).toEqual([ops]);
  // Mentioning Growth by name brings Growth in, with what it missed.
  const asked = await say(key, { id: "project-message-03", text: "@Growth which channel?" });
  expect(asked.to).toEqual([growth.id]);
  const delivered = received.at(-1)!;
  expect(delivered.employee).toBe(growth.id);
  expect(delivered.input.text).toContain("Since you last looked:");
  expect(delivered.input.text).toContain("[Head of Operations] Domain, then site.");
});

it("an employee asks a colleague in the open, and the answer comes back to it", async () => {
  const { acme, growth, received, bindings, say } = await owner();
  const ops = acme.operations.id;
  const start = await say(`direct:${ops}`, { id: "ask-message-0001", text: "Get us a tagline." });
  const opsChat = received.at(-1)!.input.chatId;
  await postFromEmployee(
    bindings,
    opsChat,
    "@Growth please draft a tagline.",
    "op-3",
    start.message.id,
  );
  const toGrowth = received.at(-1)!;
  expect(toGrowth.employee).toBe(growth.id);
  // Growth works in Operations' DM, as its own context there.
  expect(toGrowth.input.chatId).toBe(`app:${acme.business.id}:${growth.id}:direct:${ops}`);
  expect(toGrowth.input.senderId).toBe(`employee:${ops}`);
  expect(toGrowth.input.text).toContain("From your colleague Head of Operations.");
  await postFromEmployee(
    bindings,
    toGrowth.input.chatId,
    "Write it down.",
    "op-4",
    toGrowth.input.messageId,
  );
  const back = received.at(-1)!;
  expect(back.employee).toBe(ops);
  expect(back.input.text).toContain("Write it down.");
  // Operations' thanks wakes nobody.
  const before = received.length;
  await postFromEmployee(bindings, opsChat, "Thanks, Growth.", "op-5", back.input.messageId);
  expect(received).toHaveLength(before);
});

it("refuses to post into a conversation whose only responder is paused", async () => {
  const { acme, as } = await owner();
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [acme.operations.id]);
  const response = await as(`/conversations/direct:${acme.operations.id}/messages`, {
    method: "POST",
    body: JSON.stringify({ id: "paused-dm-00001", text: "Hello?" }),
  });
  expect(response.status).toBe(409);
});

it("iMessage is another way into the employee's DM: both sides are kept there, once", async () => {
  const { acme, received, bindings, as } = await owner();
  const ops = acme.operations.id;
  const binding = { businessId: acme.business.id, employeeId: ops, personId: acme.person };
  await recordChannelMessage(bindings, binding, "photon-guid-1", "Book the domain");
  await recordChannelMessage(bindings, binding, "photon-guid-1", "Book the domain");
  await recordChannelReply(bindings, binding, "Booked.", "op-imessage-1");
  await recordChannelReply(bindings, binding, "Booked.", "op-imessage-1");
  // The employee already received it on iMessage; nobody is woken again.
  expect(received).toHaveLength(0);
  const page = (await (await as(`/conversations/direct:${ops}`)).json()) as {
    messages: { author: string; text: string }[];
  };
  expect(page.messages.map((m) => [m.author, m.text])).toEqual([
    [`person:${acme.person}`, "Book the domain"],
    [`employee:${ops}`, "Booked."],
  ]);
});

it("approving a request says so where the employee asked, which wakes it", async () => {
  const { acme, growth, received, bindings, as } = await owner();
  const scope = { businessId: acme.business.id, employeeId: growth.id };
  const create = capabilities(bindings).find((item) => item.name === "driveCreate")!;
  await Effect.runPromise(grant(bindings.HYPERDRIVE, scope, { capability: create, mode: "ask" }));
  const asked = await authorize(
    bindings,
    scope,
    create,
    { name: "plan.md", content: "Launch" },
    { conversation: `direct:${growth.id}` },
  );
  expect(asked.outcome).toBe("ask");
  const id = asked.outcome === "ask" ? asked.decisionId! : "";
  expect((await as(`/decisions/${id}/approve`, { method: "POST", body: "{}" })).status).toBe(200);
  const page = (await (await as(`/conversations/direct:${growth.id}`)).json()) as {
    messages: { author: string; text: string }[];
  };
  expect(page.messages.at(-1)?.text).toMatch(/^Approved: driveCreate/);
  expect(received.at(-1)).toMatchObject({ employee: growth.id });
  expect(received.at(-1)?.input.chatId).toBe(`app:${acme.business.id}:${growth.id}`);
});

it("client ids are per conversation, and read positions follow insertion order", async () => {
  const { postMessage, markSeen, unseenBy } = await import("../src/conversations/service.ts");
  const { db } = await import("./fixtures/postgres.ts");
  const { scope } = await business("Reads");
  const post = (key: `direct:${string}` | `project:${string}`, text: string) =>
    Effect.runPromise(
      postMessage(db, scope.businessId, key, { author: "system", text, clientId: "same-id" }),
    );
  const a = await post(`direct:${scope.employeeId}`, "In the DM");
  const b = await post("project:s1", "In a project");
  expect(b.created).toBe(true);
  expect(b.message.id).not.toBe(a.message.id);
  // Two messages stored in the same millisecond: reading the first leaves the second unread.
  const key = "project:s2" as const;
  const [first, second] = ["one", "two"].map(() => crypto.randomUUID());
  await sql.run("INSERT INTO conversations (business_id, key) VALUES ($1, $2)", [
    scope.businessId,
    key,
  ]);
  for (const [id, text] of [
    [first, "one"],
    [second, "two"],
  ])
    await sql.run(
      `INSERT INTO messages (id, business_id, conversation, author, text, client_id, created_at)
       VALUES ($1, $2, $3, 'system', $4, $1, '2026-10-20T12:00:00.000Z')`,
      [id, scope.businessId, key, text],
    );
  await Effect.runPromise(markSeen(db, scope.businessId, key, "employee:x", { message: first! }));
  const unseen = await Effect.runPromise(unseenBy(db, scope.businessId, key, "employee:x", 10));
  expect(unseen.map((message) => message.text)).toEqual(["two"]);
});

it("the record the owner is viewing goes with a message as its ref, and only a record of the business", async () => {
  const { acme, received, as, say } = await owner();
  const ops = acme.operations.id;
  const project = (await (
    await as("/projects", { method: "POST", body: JSON.stringify({ name: "Launch" }) })
  ).json()) as { id: string };
  const viewing = `devys:work/project/${project.id}`;
  const posted = await say(`direct:${ops}`, {
    id: "dm-viewing-0001",
    text: "Is this on track?",
    ref: viewing,
  });
  expect(posted.to).toEqual([ops]);
  // The text stays what the owner wrote; the employee is told what was on screen.
  const page = (await (await as(`/conversations/direct:${ops}`)).json()) as {
    messages: { text: string; ref: string | null }[];
  };
  expect(page.messages.at(-1)).toMatchObject({ text: "Is this on track?", ref: viewing });
  expect(received.at(-1)!.input.text).toContain(`Viewing: ${viewing}`);
  // Another business's record, or a ref that names nothing here, is refused.
  for (const ref of [`devys:work/project/${crypto.randomUUID()}`, "devys:nothing/at/all"]) {
    const refused = await as(`/conversations/direct:${ops}/messages`, {
      method: "POST",
      body: JSON.stringify({ id: crypto.randomUUID(), text: "This?", ref }),
    });
    expect(refused.status).toBe(400);
  }
});
