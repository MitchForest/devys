import { env } from "cloudflare:workers";
import { workChat } from "../src/channels/work.ts";
import type { ConversationKey } from "../src/conversations/contract.ts";
import { expect, it } from "vitest";
import type { SessionsProbe } from "./fixtures/sessions.ts";
import { scopeName } from "../src/identity/contract.ts";
import { withoutMemory } from "../src/runtime/memory.ts";

type Entry = { kind: string; model?: { content?: unknown }[] };

function employee() {
  const scope = { businessId: crypto.randomUUID(), employeeId: crypto.randomUUID() };
  const agent = (
    env as unknown as { SESSIONS: DurableObjectNamespace<SessionsProbe> }
  ).SESSIONS.getByName(scopeName(scope));
  const app = `app:${scope.businessId}:${scope.employeeId}`;
  const work = (id: string) => workChat(scope, id);
  return { scope, agent, app, work };
}

async function until<T>(read: () => Promise<T>, done: (value: T) => boolean) {
  for (let attempt = 0; attempt < 200; attempt++) {
    const value = await read();
    if (done(value)) return value;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("Timed out waiting for the agent");
}

async function send(
  { scope, agent }: ReturnType<typeof employee>,
  messageId: string,
  chatId: string,
  text: string,
) {
  const result = await agent.receive(scope, { messageId, senderId: "owner", chatId, text });
  return result;
}

const answered = (target: ReturnType<typeof employee>, messageId: string) =>
  until(
    () => target.agent.outbox(messageId),
    (outbox) => outbox?.status === "sent",
  );

/** One conversation's said turns, oldest first, read from Pi's entries. */
const turns = async (
  { scope, agent }: ReturnType<typeof employee>,
  conversation?: ConversationKey,
) =>
  (JSON.parse(await agent.history(scope, undefined, conversation)) as { entries: Entry[] }).entries
    .flatMap((entry) => {
      const content = entry.model?.[0]?.content;
      const text =
        typeof content === "string"
          ? content
          : Array.isArray(content)
            ? content
                .flatMap((part: { type?: string; text?: string }) =>
                  part.type === "text" && part.text ? [part.text] : [],
                )
                .join("\n\n")
            : "";
      if (!text.trim() || (entry.kind !== "pi.user" && entry.kind !== "pi.assistant")) return [];
      return [
        {
          role: entry.kind === "pi.user" ? "owner" : "agent",
          text: entry.kind === "pi.user" ? withoutMemory(text) : text,
        },
      ];
    })
    .reverse();

it("each context keeps its own conversation and the direct chat is unchanged", async () => {
  const target = employee();
  await send(target, "m-direct", target.app, "Hello there");
  await send(target, "m-project", `${target.app}:project:launch`, "Plan the launch");
  await send(target, "m-work", target.work("c-1"), "Draft the brochure");
  await send(target, "m-app-work", `${target.app}:work:c-1`, "Make it shorter");
  for (const id of ["m-direct", "m-project", "m-work", "m-app-work"]) await answered(target, id);

  expect(await turns(target)).toEqual([
    { role: "owner", text: "Hello there" },
    { role: "agent", text: "Re: Hello there" },
  ]);
  expect((await turns(target, "project:launch")).map((t) => t.text)).toEqual([
    "Plan the launch",
    "Re: Plan the launch",
  ]);
  // Dispatched work and the app's view of the same work item share one session.
  expect(await turns(target, "work:c-1")).toEqual([
    expect.objectContaining({ text: "Draft the brochure" }),
    expect.objectContaining({ text: "Re: Draft the brochure" }),
    expect.objectContaining({ text: "Make it shorter" }),
    expect.objectContaining({ text: "Re: Make it shorter" }),
  ]);
  expect(JSON.parse(await target.agent.history(target.scope, undefined, "work:unknown"))).toEqual({
    entries: [],
    nextBefore: null,
  });
  expect(await target.agent.sessionCount()).toBe(3);

  // Every model turn is counted, whichever session it ran in.
  const status = JSON.parse(await target.agent.inspect(target.scope));
  expect(status.usage.models["google/gemini-3.8-flash"]).toMatchObject({ input: 4, output: 4 });
  expect(status.run).toBeNull();
  expect(status.inbox.map((item: { status: string }) => item.status)).toEqual([
    "done",
    "done",
    "done",
    "done",
  ]);
});

it("a repeated message id is admitted once in its context", async () => {
  const target = employee();
  const chat = `${target.app}:project:ops`;
  expect(await send(target, "m-once", chat, "Check the stock")).toEqual({ accepted: true });
  expect(await send(target, "m-once", chat, "Check the stock")).toEqual({ accepted: false });
  await answered(target, "m-once");
  expect((await turns(target, "project:ops")).map((t) => t.text)).toEqual([
    "Check the stock",
    "Re: Check the stock",
  ]);
});

it("stop aborts work running in a work session", async () => {
  const target = employee();
  await send(target, "m-slow", target.work("c-9"), "Do the slow thing");
  const [running] = await until(
    () => target.agent.runningWork(),
    (operations) => operations.length === 1,
  );
  const id = await target.agent.idOf("m-slow");
  expect(running).toMatchObject({ operationId: id });
  expect(running!.session).not.toBe("1");
  expect(JSON.parse(await target.agent.inspect(target.scope)).run).toMatchObject({ id });
  // A tool in the work session acts for its work item; the direct chat serves none.
  expect(await target.agent.workItemIn(running!.session)).toBe("c-9");
  expect(await target.agent.workItemIn("1")).toBeNull();

  await target.agent.stop(target.scope);
  await until(
    () => target.agent.runningWork(),
    (operations) => operations.length === 0,
  );
  expect(await target.agent.cancels()).toBe(1);
  const status = JSON.parse(await target.agent.inspect(target.scope));
  expect(status.run).toBeNull();
  expect(status.inbox).toEqual([expect.objectContaining({ id, status: "failed" })]);
});

it("a turn without words posts nothing; a failed one is Devys's notice, not the employee's", async () => {
  const target = employee();
  await send(target, "m-quiet", target.app, "Do it quietly");
  const id = await target.agent.idOf("m-quiet");
  await until(
    async () => JSON.parse(await target.agent.inspect(target.scope)).inbox,
    (inbox: { id: string; status: string }[]) =>
      inbox.some((item) => item.id === id && item.status === "done"),
  );
  expect(await target.agent.outbox("m-quiet")).toBeNull();

  await send(target, "m-broken", target.app, "This is broken");
  expect(await answered(target, "m-broken")).toMatchObject({ notice: "failed", text: "" });
});

it("a message in a work item's thread acts for that work item", async () => {
  const target = employee();
  await send(target, "m-thread", `${target.app}:work:c-7`, "Do the slow thing");
  const [running] = await until(
    () => target.agent.runningWork(),
    (operations) => operations.length === 1,
  );
  // The owner talking in the thread is fenced by the work item, as dispatched work is.
  expect(await target.agent.workItemIn(running!.session)).toBe("c-7");
  await target.agent.stop(target.scope);
  await until(
    () => target.agent.runningWork(),
    (operations) => operations.length === 0,
  );
});

it("memory observes what the owner said in every session", async () => {
  const target = employee();
  await send(target, "m-root", target.app, "Our office opens at nine");
  await send(target, "m-project-fact", `${target.app}:project:sales`, "Our launch is on Friday");
  await send(target, "m-work-fact", target.work("c-2"), "The supplier is Acme");
  for (const id of ["m-root", "m-project-fact", "m-work-fact"]) await answered(target, id);

  let observed: { id: string; content: string }[] = [];
  for (let pass = 0; pass < 3; pass++) observed = await target.agent.catchUp();
  expect(observed.map((item) => item.content).sort()).toEqual([
    "Our launch is on Friday",
    "Our office opens at nine",
    "The supplier is Acme",
  ]);
  // Evidence ids name the conversation they came from, so sessions cannot collide.
  expect(new Set(observed.map((item) => item.id.split(":")[2])).size).toBe(3);
  expect((await target.agent.catchUp()).length).toBe(3);
});
