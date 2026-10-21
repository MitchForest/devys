import { Schema } from "effect";
import type { Scope } from "../identity/contract.ts";
/** Provider adapters normalize identifiers before entering the agent host. */
const Id = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(512));
export const Inbound = Schema.Struct({
  messageId: Id,
  senderId: Id,
  chatId: Id,
  /** Channels that deliver text inline (the apps) carry it here; others read it from the provider. */
  text: Schema.optional(Schema.String.check(Schema.isMaxLength(64_000))),
});
export type Inbound = typeof Inbound.Type;
export type Delivery = { status: "sent"; guid: string | null } | { status: "uncertain" };
/** Who sent an input and which employee of which business it reaches. */
export interface Binding extends Scope {
  personId: string;
}
/**
 * A way people and work reach an employee: the Devys apps, iMessage, the dispatcher, and
 * later Telegram or Discord. Every chat id is `<channel id>:<address>`.
 */
export interface Channel {
  readonly id: string;
  inputKey(input: Inbound): string;
  binding(input: Inbound): Promise<Binding | undefined>;
  readText(input: Inbound): Promise<string>;
  prepare(scope: Scope, input: Inbound): Promise<string>;
  /**
   * Delivers the reply of the employee `scope` names. `inReplyTo` is the inbound message id
   * the reply answers, where the channel records it.
   */
  send(
    scope: Scope,
    chatId: string,
    text: string,
    operationId: string,
    inReplyTo?: string,
  ): Promise<Delivery>;
}

/** The channel a chat id belongs to: the part before the first colon. */
export const channelOf = (chatId: string) => chatId.slice(0, Math.max(0, chatId.indexOf(":")));

/** The channel's own address for a chat, without the channel prefix. */
export const addressOf = (chatId: string) => chatId.slice(chatId.indexOf(":") + 1);

/**
 * The context a conversation belongs to, beyond the employee's own direct chat: a work
 * item, a project's channel, or another employee's direct chat it was brought into.
 */
export type ConversationContext = { kind: "work" | "project" | "direct"; id: string };

/**
 * Which context a chat is about: a dispatched `work:<business>:<employee>:<commitment>`,
 * or a channel address ending `:work:<id>`, `:project:<id>` or `:direct:<id>`. Undefined is
 * the employee's own direct chat.
 */
export const contextOf = (chatId: string): ConversationContext | undefined => {
  const dispatched = commitmentOf(chatId);
  if (dispatched) return { kind: "work", id: dispatched.commitmentId };
  const match = /:(work|project|direct):([A-Za-z0-9-]{1,64})$/.exec(chatId);
  return match ? { kind: match[1] as ConversationContext["kind"], id: match[2]! } : undefined;
};

/** The commitment a dispatched `work:<business>:<employee>:<commitment>` input serves. */
export const commitmentOf = (chatId: string) => {
  if (!chatId.startsWith("work:")) return undefined;
  const [, businessId, employeeId, commitmentId, ...rest] = chatId.split(":");
  return businessId && employeeId && commitmentId && !rest.length
    ? { businessId, employeeId, commitmentId }
    : undefined;
};
