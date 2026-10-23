import type { Inbound, Notice } from "../channels/contract.ts";
/** Adapter receipts only; Pi owns queued/running/completed work. */
export interface ChannelMessage {
  id: string;
  input: Inbound;
  receivedAt: number;
  text?: string;
  cancelled?: boolean;
  control?: "stop" | "status";
  targets?: string[];
  preparationAttempts?: number;
  /** Pi has the turn; later polls only wait for it. */
  submitted?: boolean;
  /** The turn ended without words, so Pi has one follow-up asking for the reply (`replyTurn`). */
  replyAsked?: boolean;
  /** Answered without words (its cards carry it, or it stayed empty even when asked). */
  silent?: boolean;
}
export interface Outbox {
  id: string;
  chatId: string;
  text: string;
  /** Set when Devys, not the employee, answers: the turn ended without the employee's words. */
  notice?: Notice;
  /** The inbound message the reply answers. */
  replyTo?: string;
  attempts: number;
  status: "pending" | "sent" | "uncertain" | "cancelled";
}

/** The operation id of the one follow-up that asks for a reply the turn did not write. */
export const replyTurn = (id: string) => `${id}:reply`;
/** The message an operation answers: its own id, or the id its reply follow-up names. */
export const messageOf = (operationId: string) => operationId.replace(/:reply$/, "");

export const messageKey = (id: string) => `message:${id}`;
export const outboxKey = (id: string) => `outbox:${id}`;
/** Receipts by arrival, so the oldest can be forgotten and status shows the latest. */
export const recentKey = (message: ChannelMessage) =>
  `recent:${String(message.receivedAt).padStart(16, "0")}:${message.id}`;
