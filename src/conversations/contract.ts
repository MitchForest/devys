import type { Ref } from "../protocol/ref.ts";

/**
 * The shared record of what was said in a DM, a project's channel or a work item's thread. Pi keeps
 * each employee's own reasoning; a conversation is what everyone in it reads.
 */
export type ConversationKind = "direct" | "project" | "work";

/** `direct:<employee>`, `project:<project>` or `work:<workItem>`. */
export type ConversationKey = `${ConversationKind}:${string}`;

export const conversationKey = (value: unknown): ConversationKey | undefined =>
  typeof value === "string" && /^(direct|project|work):[A-Za-z0-9-]{1,64}$/.test(value)
    ? (value as ConversationKey)
    : undefined;

export const kindOf = (key: ConversationKey) => key.slice(0, key.indexOf(":")) as ConversationKind;
/** The id a key names: the employee, project or work item. */
export const idOf = (key: ConversationKey) => key.slice(key.indexOf(":") + 1);

export interface Message {
  id: string;
  conversation: ConversationKey;
  /** `person:<id>`, `employee:<id>` or `system`. */
  author: string;
  kind: "message" | "event";
  text: string;
  reply_to: string | null;
  /** Employee ids this message addresses. */
  mentions: string[];
  via_voice: boolean;
  /** The record an event is about: the work item a hand-off card opens, a page, a session. */
  ref: Ref | null;
  created_at: string;
}

export const employeeOf = (author: string) =>
  author.startsWith("employee:") ? author.slice("employee:".length) : undefined;

/**
 * Who answers a new message, by the conversation's rules:
 *
 * 1. An owner's message is always answered: by the employees it mentions; otherwise by
 *    the employee it replies to; otherwise by whoever last spoke here; otherwise by the
 *    conversation's default (a DM's employee, a project's lead, a work item's owner).
 * 2. An employee's message wakes the employees it mentions, and the asker when it answers
 *    a message that mentioned it. Nothing else an employee writes wakes anyone.
 * 3. At most `limit` employee turns in a row between two owner messages.
 */
export function responders(input: {
  message: Pick<Message, "author" | "mentions" | "reply_to">;
  /** The conversation before this message, oldest first. */
  history: readonly Pick<Message, "id" | "author" | "mentions" | "kind">[];
  defaultResponder: string | undefined;
  limit?: number;
}): string[] {
  const { message, history, defaultResponder } = input;
  const author = employeeOf(message.author);
  const replied = message.reply_to
    ? history.find((earlier) => earlier.id === message.reply_to)
    : undefined;
  const unique = (ids: (string | undefined)[]) => [
    ...new Set(ids.filter((id): id is string => Boolean(id) && id !== author)),
  ];
  if (!author) {
    if (message.mentions.length) return unique(message.mentions);
    const lastSpeaker = [...history]
      .reverse()
      .find((earlier) => earlier.kind === "message" && employeeOf(earlier.author));
    return unique([
      (replied && employeeOf(replied.author)) ??
        (lastSpeaker && employeeOf(lastSpeaker.author)) ??
        defaultResponder,
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

/** Who answers the owner's next message if they neither reply to nor mention anyone. */
export function nextResponder(
  history: readonly Pick<Message, "author" | "kind">[],
  defaultResponder: string | undefined,
) {
  const lastSpeaker = [...history]
    .reverse()
    .find((earlier) => earlier.kind === "message" && employeeOf(earlier.author));
  return (lastSpeaker && employeeOf(lastSpeaker.author)) ?? defaultResponder;
}
