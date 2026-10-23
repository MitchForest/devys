import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appChat, composeAppMessage } from "../channels/app.ts";
import {
  employeeChatOf,
  noticeReplies,
  noticeText,
  type Binding,
  type Notice,
} from "../channels/contract.ts";
import {
  employeeOf,
  mentionsIn,
  namer,
  kindOf,
  nextResponder,
  idOf,
  responders,
  type ConversationKey,
  type Message,
} from "../conversations/contract.ts";
import {
  markSeen,
  messages,
  postMessage,
  unseenBefore,
  messageIn,
} from "../conversations/service.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import { activePerson, employeesOf } from "../identity/service.ts";
import { ref, type Ref } from "../protocol/ref.ts";
import { workItem } from "../work/service.ts";
import { project } from "../work/projects.ts";

/** How much of a conversation an addressed employee is shown before the new message. */
const catchUp = 20;

/**
 * What a conversation key names in this business: its default responder (a DM's employee,
 * a project's lead, a work item's owner) and the line that tells an employee where a delivery
 * comes from. Undefined when it names nothing that can be talked in.
 */
async function resolve(env: Env, businessId: string, key: ConversationKey) {
  const id = idOf(key);
  switch (kindOf(key)) {
    case "direct": {
      const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId));
      return employees.some((employee) => employee.id === id)
        ? { defaultResponder: id as string | undefined, place: "" }
        : undefined;
    }
    case "project": {
      const found = await Effect.runPromise(project(env.HYPERDRIVE, businessId, id));
      if (!found) return undefined;
      const about = [
        found.goal && `goal: ${found.goal}`,
        found.deadline && `deadline ${found.deadline}`,
      ].filter(Boolean);
      return {
        defaultResponder: found.lead_employee_id ?? undefined,
        // A channel stays readable: progress goes in each work item's thread.
        place: `In the project "${found.name}" (${ref("work", "project", found.id)}${about.length ? `; ${about.join("; ")}` : ""}). This is its channel: say results, hand-offs and questions here; post progress in the work item's own thread.`,
      };
    }
    case "work": {
      const item = await Effect.runPromise(workItem(env.HYPERDRIVE, businessId, id));
      return item
        ? {
            defaultResponder: item.owner_employee_id as string | undefined,
            place: `In the thread of the work item "${item.title}" (${ref("work", "item", item.id)}).`,
          }
        : undefined;
    }
  }
}

const defaultResponder = async (env: Env, businessId: string, key: ConversationKey) =>
  (await resolve(env, businessId, key))?.defaultResponder;

/** Whether a conversation key names something of this business that can be talked in. */
export const conversationExists = async (env: Env, businessId: string, key: ConversationKey) =>
  Boolean(await resolve(env, businessId, key));

/**
 * Hands a message to the employees it addresses, once each. Each sees what was said before
 * it since it last looked, then the message, in its own Pi session for this conversation.
 */
async function deliver(
  env: Env,
  businessId: string,
  key: ConversationKey,
  message: Message,
  targets: readonly string[],
  /** Where the conversation is, told to each employee it reaches. */
  place: string,
  /** What only employees read, after the message: a secret's name the owner never sees. */
  forEmployees?: string,
) {
  if (!targets.length) return;
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId));
  const person = message.author.startsWith("person:")
    ? await Effect.runPromise(activePerson(env.HYPERDRIVE, message.author.slice("person:".length)))
    : undefined;
  const nameOf = namer(employees);
  for (const target of targets) {
    const employee = employees.find((candidate) => candidate.id === target);
    if (!employee || employee.paused) continue;
    const scope = { businessId, employeeId: target };
    const unseen = await Effect.runPromise(
      unseenBefore(env.HYPERDRIVE, businessId, key, `employee:${target}`, message.id, catchUp),
    );
    // Already handed over (its read position is at or after the message): a repeated post
    // must not compose a different delivery under the same message id.
    if (!unseen) continue;
    const earlier = unseen.filter((item) => employeeOf(item.author) !== target);
    const replied = message.reply_to
      ? await Effect.runPromise(messageIn(env.HYPERDRIVE, businessId, key, message.reply_to))
      : undefined;
    const about = [
      place,
      ...(earlier.length
        ? [
            "Since you last looked:",
            ...earlier.map((item) => `[${nameOf(item.author)}] ${item.text}`),
          ]
        : []),
      ...(replied
        ? [`Replying to ${nameOf(replied.author)}: "${replied.text.slice(0, 280)}"`]
        : []),
      ...(person ? [] : [`From your colleague ${nameOf(message.author)}.`]),
      // What the owner had open beside the conversation: "this" means it. A reference, not a
      // grant: read it with your own access.
      ...(message.ref ? [`Viewing: ${message.ref}`] : []),
    ]
      .filter(Boolean)
      .join("\n");
    const text = await Effect.runPromise(
      composeAppMessage(env.HYPERDRIVE, scope, {
        id: message.id,
        text: forEmployees ? `${message.text}\n${forEmployees}` : message.text,
        viaVoice: message.via_voice,
        ...(about ? { about } : {}),
      }),
    );
    // An employee's own DM is its root session; any other conversation is named.
    const own = key === `direct:${target}`;
    await env.AGENT.getByName(scopeName(scope)).receive(scope, {
      messageId: message.id,
      senderId: message.author,
      chatId: appChat(scope, own ? undefined : key),
      text,
    });
    await Effect.runPromise(
      markSeen(env.HYPERDRIVE, businessId, key, `employee:${target}`, { message: message.id }),
    );
  }
}

/** Posts a message and wakes whoever the rules say should answer. */
async function post(
  env: Env,
  businessId: string,
  key: ConversationKey,
  input: Parameters<typeof postMessage>[3],
  forEmployees?: string,
) {
  const { message } = await Effect.runPromise(postMessage(env.HYPERDRIVE, businessId, key, input));
  // The history before this message, so a repeated post answers to the same people.
  const history = await Effect.runPromise(
    messages(env.HYPERDRIVE, businessId, key, { before: message.id, limit: 50 }),
  );
  const resolved = await resolve(env, businessId, key);
  const to = responders({
    message,
    history,
    defaultResponder: resolved?.defaultResponder,
    now: new Date(message.created_at),
  });
  // Delivered on a repeat too, to whoever it has not reached: a retry after a failed delivery
  // must still wake them.
  await deliver(env, businessId, key, message, to, resolved?.place ?? "", forEmployees);
  return { message, to };
}

/** The owner (or another member) speaking. Mentions must be employees of the business. */
export async function postFromPerson(
  env: Env,
  businessId: string,
  personId: string,
  key: ConversationKey,
  input: {
    id: string;
    text: string;
    replyTo?: string;
    mentions?: string[];
    viaVoice?: boolean;
    /** The record the person was viewing as they wrote, checked to be the business's. */
    ref?: Ref;
    /** Added to what the employees it reaches receive, never shown: a secret's name. */
    forEmployees?: string;
  },
) {
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId));
  const mentions = [
    ...(input.mentions ?? []).filter((id) => employees.some((employee) => employee.id === id)),
    ...mentionsIn(input.text, employees),
  ];
  // Refuse plainly when nobody who would answer is working (paused or retired), rather
  // than post into silence.
  const targets = responders({
    message: { author: `person:${personId}`, mentions, reply_to: input.replyTo ?? null },
    history: await Effect.runPromise(messages(env.HYPERDRIVE, businessId, key, { limit: 50 })),
    defaultResponder: await defaultResponder(env, businessId, key),
    now: new Date(),
  });
  const answering = employees.filter((employee) => targets.includes(employee.id));
  if (targets.length && answering.every((employee) => employee.paused))
    return {
      refused: answering.length
        ? `${answering.map((employee) => employee.name).join(" and ")} is paused. Resume them to send.`
        : "Nobody here can answer: mention an employee of this business.",
    };
  const posted = await post(
    env,
    businessId,
    key,
    {
      author: `person:${personId}`,
      text: input.text,
      clientId: input.id,
      replyTo: input.replyTo ?? null,
      mentions: [...new Set(mentions)],
      viaVoice: input.viaVoice === true,
      ref: input.ref ?? null,
    },
    input.forEmployees,
  );
  await Effect.runPromise(
    markSeen(env.HYPERDRIVE, businessId, key, `person:${personId}`, {
      message: posted.message.id,
    }),
  );
  return posted;
}

/**
 * An employee's reply, arriving through its channel's `send`: posted in the conversation
 * the input came from, answering the message that started the turn. `@Name` mentions in
 * it wake those colleagues.
 */
export async function postFromEmployee(
  env: Env,
  chatId: string,
  text: string,
  operationId: string,
  inReplyTo?: string,
) {
  const chat = employeeChatOf(chatId);
  if (!chat) throw new Error(`No conversation for chat ${chatId}`);
  const key = chat.conversation ?? (`direct:${chat.scope.employeeId}` as const);
  await reply(env, chat.scope, key, text, operationId, inReplyTo);
}

/**
 * Devys's notice that an employee's turn ended without its answer (it took too long, failed, is
 * paused): an event in the conversation the input came from, never the employee's message.
 */
export async function postNotice(env: Env, chatId: string, notice: Notice, operationId: string) {
  const chat = employeeChatOf(chatId);
  if (!chat) throw new Error(`No conversation for chat ${chatId}`);
  const key = chat.conversation ?? (`direct:${chat.scope.employeeId}` as const);
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, chat.scope.businessId));
  const name = employees.find((employee) => employee.id === chat.scope.employeeId)?.name;
  await Effect.runPromise(
    postMessage(env.HYPERDRIVE, chat.scope.businessId, key, {
      author: "system",
      kind: "event",
      text: noticeText(notice, name),
      clientId: `notice:${operationId}`,
      replies: noticeReplies(notice),
    }),
  );
}

async function reply(
  env: Env,
  scope: Scope,
  key: ConversationKey,
  text: string,
  operationId: string,
  inReplyTo?: string,
) {
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, scope.businessId));
  await post(env, scope.businessId, key, {
    author: `employee:${scope.employeeId}`,
    text,
    clientId: `reply:${operationId}`,
    replyTo: inReplyTo ?? null,
    mentions: mentionsIn(
      text,
      employees.filter((employee) => employee.id !== scope.employeeId),
    ),
  });
}

/**
 * A person writing to an employee from another channel, such as iMessage. The employee
 * already receives it there, so it is recorded in their DM without waking anyone; both are
 * marked as having seen it.
 */
export async function recordChannelMessage(
  env: Env,
  binding: Binding,
  messageId: string,
  text: string,
) {
  const key = `direct:${binding.employeeId}` as const;
  const { message } = await Effect.runPromise(
    postMessage(env.HYPERDRIVE, binding.businessId, key, {
      author: `person:${binding.personId}`,
      text,
      clientId: `channel:${messageId}`,
    }),
  );
  for (const participant of [`person:${binding.personId}`, `employee:${binding.employeeId}`])
    await Effect.runPromise(
      markSeen(env.HYPERDRIVE, binding.businessId, key, participant, { message: message.id }),
    );
}

/** The employee's reply on that channel, kept in the same DM. Its mentions wake colleagues. */
export const recordChannelReply = (env: Env, scope: Scope, text: string, operationId: string) =>
  reply(env, scope, `direct:${scope.employeeId}`, text, operationId);

/**
 * A system event, such as work being handed to an employee, or a card, which clients show as
 * its record is now. Posting twice is harmless.
 */
export const postEvent = (
  env: Env,
  businessId: string,
  key: ConversationKey,
  event: { clientId: string; text: string; ref?: Ref; kind?: "event" | "card" },
) =>
  Effect.runPromise(
    postMessage(env.HYPERDRIVE, businessId, key, {
      author: "system",
      kind: event.kind ?? "event",
      text: event.text,
      clientId: event.clientId,
      ref: event.ref ?? null,
    }),
  );

/**
 * A work item's card in its thread, posted the first time its steps or results are set: clients
 * draw it from the item as it is now, so every later change updates this one card in place.
 */
export const showWorkCard = (env: Env, businessId: string, work: { id: string; title: string }) =>
  postEvent(env, businessId, `work:${work.id}`, {
    kind: "card",
    clientId: `card:${work.id}`,
    text: work.title,
    ref: ref("work", "item", work.id),
  }).then(() => undefined);

/** A conversation page and who would answer the owner's next plain message. */
export async function conversationPage(
  env: Env,
  businessId: string,
  key: ConversationKey,
  before?: string,
) {
  const page = await Effect.runPromise(
    messages(env.HYPERDRIVE, businessId, key, { ...(before ? { before } : {}), limit: 50 }),
  );
  const recent = before
    ? await Effect.runPromise(messages(env.HYPERDRIVE, businessId, key, { limit: 50 }))
    : page;
  return {
    messages: page,
    respondent:
      nextResponder(recent, await defaultResponder(env, businessId, key), new Date()) ?? null,
  };
}
