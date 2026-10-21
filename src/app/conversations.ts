import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appChat, composeAppMessage } from "../channels/app.ts";
import { employeeChatOf, type Binding } from "../channels/contract.ts";
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
import { markSeen, messages, postMessage, unseenBy, messageIn } from "../conversations/service.ts";
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
 * Hands a message to the employees it addresses. Each sees what was said since it last
 * looked, then the message, in its own Pi session for this conversation.
 */
async function deliver(
  env: Env,
  businessId: string,
  key: ConversationKey,
  message: Message,
  targets: readonly string[],
  /** Where the conversation is, told to each employee it reaches. */
  place: string,
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
    const earlier = (
      await Effect.runPromise(
        unseenBy(env.HYPERDRIVE, businessId, key, `employee:${target}`, catchUp + 1),
      )
    ).filter((item) => item.id !== message.id && employeeOf(item.author) !== target);
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
        text: message.text,
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
) {
  const { message } = await Effect.runPromise(postMessage(env.HYPERDRIVE, businessId, key, input));
  // The history before this message, so a repeated post answers to the same people.
  const history = await Effect.runPromise(
    messages(env.HYPERDRIVE, businessId, key, { before: message.id, limit: 50 }),
  );
  const resolved = await resolve(env, businessId, key);
  const to = responders({ message, history, defaultResponder: resolved?.defaultResponder });
  // Delivered on a repeat too: a retry after a failed delivery must still wake whoever answers,
  // and the runtime admits each message id once.
  await deliver(env, businessId, key, message, to, resolved?.place ?? "");
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
  });
  const answering = employees.filter((employee) => targets.includes(employee.id));
  if (targets.length && answering.every((employee) => employee.paused))
    return {
      refused: answering.length
        ? `${answering.map((employee) => employee.name).join(" and ")} is paused. Resume them to send.`
        : "Nobody here can answer: mention an employee of this business.",
    };
  const posted = await post(env, businessId, key, {
    author: `person:${personId}`,
    text: input.text,
    clientId: input.id,
    replyTo: input.replyTo ?? null,
    mentions: [...new Set(mentions)],
    viaVoice: input.viaVoice === true,
    ref: input.ref ?? null,
  });
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

/** A system event, such as work being handed to an employee. Posting twice is harmless. */
export const postEvent = (
  env: Env,
  businessId: string,
  key: ConversationKey,
  event: { clientId: string; text: string; ref?: Ref },
) =>
  Effect.runPromise(
    postMessage(env.HYPERDRIVE, businessId, key, {
      author: "system",
      kind: "event",
      text: event.text,
      clientId: event.clientId,
      ref: event.ref ?? null,
    }),
  );

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
    respondent: nextResponder(recent, await defaultResponder(env, businessId, key)) ?? null,
  };
}
