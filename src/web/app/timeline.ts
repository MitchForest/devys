import type { Ref } from "../../protocol/ref.ts";
import type { ShownMessage, Worked } from "../../conversations/contract.ts";

/** A conversation as Messages lays it out: grouped bubbles, with a heading when time passes. */
type Position = "single" | "first" | "middle" | "last";
export interface Bubble {
  id: string;
  /** `person:<id>`, `employee:<id>` or `system`. */
  author: string;
  /** Whether the signed-in person wrote it, so it sits on the right. */
  mine: boolean;
  /** A card shows its record as it is now (a work item's steps and results). */
  kind: "message" | "event" | "card";
  text: string;
  /** The message it answers, quoted only when that isn't the message right above it. */
  replyTo: string | null;
  viaVoice: boolean;
  reactions: readonly string[];
  /** What an event or card opens: a work item, a page, a coding session. */
  ref: Ref | null;
  /**
   * A question card's answers, offered on the latest employee message until the owner says
   * anything; its title, and whether several may be picked.
   */
  replies: readonly string[];
  question: string | null;
  pickMany: boolean;
  /** An employee's reply that took steps: how long and how many. */
  worked: Worked | null;
  sentAt?: Date;
  position: Position;
  /** Set for messages sent from this browser that the conversation doesn't show yet. */
  delivery?: "sending" | "delivered" | "failed";
  /** Why a send failed, in the server's words. */
  error?: string;
}
type TimelineItem =
  | { kind: "heading"; id: string; date: Date }
  | { kind: "bubble"; id: string; bubble: Bubble };

/** A message sent from this browser, as the timeline needs it. */
export interface Unsent {
  id: string;
  text: string;
  replyTo?: string;
  viaVoice?: boolean;
  /** The record the owner was viewing, sent as the message's ref. */
  ref?: Ref;
  delivery: "sending" | "delivered" | "failed";
  error?: string;
}

export const endsGroup = (bubble: Bubble) =>
  bubble.position === "single" || bubble.position === "last";
export const startsGroup = (bubble: Bubble) =>
  bubble.position === "single" || bubble.position === "first";

const groupGap = 5 * 60_000;
const headingGap = 60 * 60_000;
const sameDay = (a: Date, b: Date) => a.toDateString() === b.toDateString();

/**
 * The message whose question card shows: the latest message (or Devys's notice offering
 * "Ask again"), skipping other events, when an employee wrote it and nothing has been sent from
 * here since.
 */
export function offering(history: readonly ShownMessage[], unsent: readonly Unsent[]) {
  if (unsent.length) return undefined;
  const notice = (m: ShownMessage) => m.kind === "event" && m.replies.length > 0;
  const latest = history.findLast((m) => m.kind === "message" || notice(m));
  return latest &&
    (notice(latest) || latest.author.startsWith("employee:")) &&
    latest.replies.length
    ? latest
    : undefined;
}

/** `me` is the signed-in person's author string, `person:<id>`. */
export function timeline(
  history: ShownMessage[],
  unsent: Unsent[],
  me: string,
  now: Date,
): TimelineItem[] {
  const offered = offering(history, unsent);
  const bubbles: Bubble[] = [
    ...history.map((m, index) => ({
      id: m.id,
      author: m.author,
      mine: m.author === me,
      kind: m.kind,
      text: m.text,
      replyTo: m.reply_to === history[index - 1]?.id ? null : m.reply_to,
      viaVoice: m.via_voice,
      reactions: m.reactions,
      ref: m.ref,
      replies: m === offered ? m.replies : [],
      question: m === offered ? m.question : null,
      pickMany: m === offered && m.pick_many,
      worked: m.worked,
      sentAt: new Date(m.created_at),
      position: "single" as const,
    })),
    ...unsent.map((p) => ({
      id: p.id,
      author: me,
      mine: true,
      kind: "message" as const,
      text: p.text,
      replyTo: p.replyTo ?? null,
      viaVoice: p.viaVoice ?? false,
      reactions: [],
      ref: p.ref ?? null,
      replies: [],
      question: null,
      pickMany: false,
      worked: null,
      sentAt: now,
      position: "single" as const,
      delivery: p.delivery,
      ...(p.error ? { error: p.error } : {}),
    })),
  ];
  const items: TimelineItem[] = [];
  let previous: Bubble | undefined;
  for (const bubble of bubbles) {
    const gap =
      previous?.sentAt && bubble.sentAt
        ? bubble.sentAt.getTime() - previous.sentAt.getTime()
        : undefined;
    const newDay =
      previous?.sentAt && bubble.sentAt ? !sameDay(previous.sentAt, bubble.sentAt) : false;
    if (bubble.sentAt && (!previous || newDay || (gap ?? 0) > headingGap)) {
      items.push({
        kind: "heading",
        id: `heading-${bubble.sentAt.getTime()}`,
        date: bubble.sentAt,
      });
      previous = undefined;
    }
    const last = items[items.length - 1];
    // Consecutive messages from one author group; events always stand alone.
    if (
      previous &&
      previous.kind === "message" &&
      bubble.kind === "message" &&
      previous.author === bubble.author &&
      (gap ?? 0) <= groupGap &&
      last?.kind === "bubble"
    ) {
      last.bubble.position = last.bubble.position === "single" ? "first" : "middle";
      bubble.position = "last";
    }
    items.push({ kind: "bubble", id: bubble.id, bubble });
    previous = bubble;
  }
  return items;
}
