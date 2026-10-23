import { Schema } from "effect";
import { conversationKey, type ConversationKey } from "../conversations/contract.ts";
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
/**
 * Why a turn ended without the employee's answer: it ran out of time, failed, the employee is
 * paused, or the message couldn't be read. Devys says so; the employee didn't speak.
 */
export type Notice = "too_long" | "failed" | "paused" | "unreadable";

/** A notice in plain words, naming the employee where the channel shows who it is about. */
export function noticeText(notice: Notice, employee?: string) {
  const who = employee ?? "This employee";
  switch (notice) {
    case "too_long":
      return `${who} stopped: it took too long.`;
    case "failed":
      return `${who} couldn't finish: something went wrong.`;
    case "paused":
      return `${who} is paused, so nothing was done.`;
    case "unreadable":
      return `${who} couldn't read that message or its attachments.`;
  }
}

/** What the owner can tap after a notice: asking again, where that could help. */
export const noticeReplies = (notice: Notice): string[] =>
  notice === "too_long" || notice === "failed" ? ["Ask again"] : [];

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
  /**
   * Says, as Devys and never as the employee, that a turn ended without the employee's answer
   * (the apps show it as an event, not a message).
   */
  notice(scope: Scope, chatId: string, notice: Notice, operationId: string): Promise<Delivery>;
}

/** The channel a chat id belongs to: the part before the first colon. */
export const channelOf = (chatId: string) => chatId.slice(0, Math.max(0, chatId.indexOf(":")));

/** The channel's own address for a chat, without the channel prefix. */
export const addressOf = (chatId: string) => chatId.slice(chatId.indexOf(":") + 1);

/**
 * The app and work channels address an employee directly: `<channel>:<business>:<employee>`,
 * followed by the conversation the input is in (`:direct:<id>`, `:project:<id>`,
 * `:work:<id>`). Without one it is the employee's own direct chat.
 */
export const employeeChat = (channel: string, scope: Scope, conversation?: ConversationKey) =>
  `${channel}:${scope.businessId}:${scope.employeeId}${conversation ? `:${conversation}` : ""}`;

/** The employee and the conversation an `employeeChat` id names, or undefined. */
export const employeeChatOf = (
  chatId: string,
): { channel: string; scope: Scope; conversation?: ConversationKey } | undefined => {
  const [channel, businessId, employeeId, ...rest] = chatId.split(":");
  if (!channel || !businessId || !employeeId) return undefined;
  if (!rest.length) return { channel, scope: { businessId, employeeId } };
  const conversation = conversationKey(rest.join(":"));
  return conversation ? { channel, scope: { businessId, employeeId }, conversation } : undefined;
};
