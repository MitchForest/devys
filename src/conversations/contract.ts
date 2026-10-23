import { Schema } from "effect";
import { Ref } from "../protocol/ref.ts";
import { Timestamp } from "../protocol/time.ts";

/**
 * The shared record of what was said in a DM, a project's channel or a work item's thread. Pi keeps
 * each employee's own reasoning; a conversation is what everyone in it reads.
 */
type ConversationKind = "direct" | "project" | "work";

/** `direct:<employee>`, `project:<project>` or `work:<workItem>`: the one rule for a key. */
export const ConversationKey = Schema.TemplateLiteral([
  Schema.Literals(["direct", "project", "work"]),
  ":",
  Schema.String,
]).check(Schema.isPattern(/^(direct|project|work):[A-Za-z0-9-]{1,64}$/));
export type ConversationKey = `${ConversationKind}:${string}`;

const isConversationKey = Schema.is(ConversationKey);
export const conversationKey = (value: unknown): ConversationKey | undefined =>
  isConversationKey(value) ? value : undefined;

export const kindOf = (key: ConversationKey) => key.slice(0, key.indexOf(":")) as ConversationKind;
/** The id a key names: the employee, project or work item. */
export const idOf = (key: ConversationKey) => key.slice(key.indexOf(":") + 1);

/**
 * One entry in a conversation: something someone said, an event such as a hand-off, or a card,
 * which shows its record (`ref`) as it is now and so is updated in place, never reposted.
 */
export const Message = Schema.Struct({
  id: Schema.String,
  conversation: ConversationKey,
  /** `person:<id>`, `employee:<id>` or `system`. */
  author: Schema.String,
  kind: Schema.Literals(["message", "event", "card"]),
  text: Schema.String,
  reply_to: Schema.NullOr(Schema.String),
  /** Employee ids this message addresses. */
  mentions: Schema.Array(Schema.String),
  via_voice: Schema.Boolean,
  /** The record an event is about: the work item a hand-off card opens, a page, a session. */
  ref: Schema.NullOr(Ref),
  /** Short answers its employee offers; the owner's clients show them while it is the latest word. */
  replies: Schema.Array(Schema.String),
  created_at: Timestamp,
});
export type Message = typeof Message.Type;

/** A message as the owner's clients show it, with the reactions on it. */
export const ShownMessage = Schema.Struct({
  ...Message.fields,
  reactions: Schema.Array(Schema.String),
});
export type ShownMessage = typeof ShownMessage.Type;

/** A conversation in the owner's list: its last message and what they haven't read. */
export const ConversationSummary = Schema.Struct({
  key: ConversationKey,
  last: Schema.NullOr(Message),
  unread: Schema.Int,
  /** The person follows it: a work thread they hear each milestone of. */
  following: Schema.Boolean,
});
export type ConversationSummary = typeof ConversationSummary.Type;

export const employeeOf = (author: string) =>
  author.startsWith("employee:") ? author.slice("employee:".length) : undefined;

/** `@Name` mentions of the business's employees in a message, longest names first. */
export function mentionsIn(text: string, employees: readonly { id: string; name: string }[]) {
  const lower = text.toLowerCase();
  return [...employees]
    .sort((a, b) => b.name.length - a.name.length)
    .filter((employee) => lower.includes(`@${employee.name.toLowerCase()}`))
    .map((employee) => employee.id);
}

/** How a message's author is named to an employee, given the business's employees. */
export const namer = (employees: readonly { id: string; name: string }[]) => (author: string) =>
  employees.find((employee) => employee.id === employeeOf(author))?.name ??
  (author.startsWith("person:") ? "Owner" : "Devys");

/**
 * Who answers a new message, by the conversation's rules:
 *
 * 1. An owner's message is always answered: by the employees it mentions; otherwise by
 *    the employee it replies to; otherwise by whoever is talking (the last employee who spoke,
 *    within the last hour); otherwise by the conversation's default (a DM's employee, a
 *    project's lead, a work item's owner).
 * 2. An employee's message wakes the employees it mentions, and the asker when it answers
 *    a message that mentioned it. Nothing else an employee writes wakes anyone.
 * 3. At most `limit` employee turns in a row between two owner messages.
 */
export function responders(input: {
  message: Pick<Message, "author" | "mentions" | "reply_to">;
  /** The conversation before this message, oldest first. */
  history: readonly Pick<Message, "id" | "author" | "mentions" | "kind" | "created_at">[];
  defaultResponder: string | undefined;
  /** The time the new message is sent, to tell who is still talking. */
  now: Date;
  limit?: number;
}): string[] {
  const { message, history, defaultResponder, now } = input;
  const author = employeeOf(message.author);
  const replied = message.reply_to
    ? history.find((earlier) => earlier.id === message.reply_to)
    : undefined;
  const unique = (ids: readonly (string | undefined)[]) => [
    ...new Set(ids.filter((id): id is string => Boolean(id) && id !== author)),
  ];
  if (!author) {
    if (message.mentions.length) return unique(message.mentions);
    return unique([
      (replied && employeeOf(replied.author)) ?? talking(history, now) ?? defaultResponder,
    ]);
  }
  let streak = 0;
  for (const earlier of [...history].reverse()) {
    if (earlier.author.startsWith("person:")) break;
    if (employeeOf(earlier.author)) streak++;
  }
  if (streak + 1 >= (input.limit ?? 3)) return [];
  const asker =
    replied && author && replied.mentions.includes(author) ? employeeOf(replied.author) : undefined;
  return unique([...message.mentions, asker]);
}

/** How long after speaking an employee still holds the floor without an @. */
const talkingFor = 60 * 60_000;

/**
 * Whoever is talking: the employee who spoke last, if within the last hour. One who spoke
 * yesterday does not take the owner's next message.
 */
function talking(history: readonly Pick<Message, "author" | "kind" | "created_at">[], now: Date) {
  const last = [...history]
    .reverse()
    .find((earlier) => earlier.kind === "message" && employeeOf(earlier.author));
  return last && now.getTime() - Date.parse(last.created_at) <= talkingFor
    ? employeeOf(last.author)
    : undefined;
}

/** Who answers the owner's next message if they neither reply to nor mention anyone. */
export const nextResponder = (
  history: readonly Pick<Message, "author" | "kind" | "created_at">[],
  defaultResponder: string | undefined,
  now: Date,
) => talking(history, now) ?? defaultResponder;
