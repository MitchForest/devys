import { ROOT_SESSION, type PiHarness } from "agents/harness/pi";
import type { ConversationId, EntryId } from "@earendil-works/pi-durable";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { employeeChatOf } from "../channels/contract.ts";
import type { ConversationKey } from "../conversations/contract.ts";

/** A harness session id as the Pi conversation it names. */
export const conversationOf = (session: string) => Number(session) as ConversationId;

/**
 * The conversation an input is in, which keys its Pi session in this object; undefined is the
 * employee's own direct chat, the root session.
 */
export const conversationIn = (chatId: string) => employeeChatOf(chatId)?.conversation;

/**
 * The employee's Pi session for each conversation it takes part in, stored as
 * `session:<conversation key>`. Direct chat is the root session.
 */
export function sessionMap(storage: DurableObjectStorage, harness: PiHarness) {
  const creating = new Map<ConversationKey, Promise<string>>();

  /** Every conversation's Pi session, by conversation key; the root session is not listed. */
  const all = async () => {
    const stored = await storage.list<string>({ prefix: "session:" });
    return new Map([...stored].map(([key, session]) => [key.slice("session:".length), session]));
  };

  /** The session a chat's conversation already has, or undefined before its first input. */
  const sessionIn = (known: Map<string, string>, chatId: string) => {
    const key = conversationIn(chatId);
    return key ? known.get(key) : ROOT_SESSION;
  };

  const known = (key: ConversationKey | undefined) =>
    key ? storage.get<string>(`session:${key}`) : Promise.resolve(ROOT_SESSION);

  /** A conversation's session, created on its first input; concurrent first inputs share one. */
  const open = (key: ConversationKey | undefined) => {
    if (!key) return Promise.resolve(ROOT_SESSION);
    const existing = creating.get(key);
    if (existing) return existing;
    const opening = (async () => {
      const stored = await storage.get<string>(`session:${key}`);
      if (stored) return stored;
      const { id } = await harness.sessions.create();
      await storage.put(`session:${key}`, id);
      return id;
    })().finally(() => creating.delete(key));
    creating.set(key, opening);
    return opening;
  };

  return { all, sessionIn, known, open };
}

export type Sessions = ReturnType<typeof sessionMap>;

/** One page of a session's Pi entries, newest first, before entry `before` when given. */
export async function historyPage(harness: PiHarness, session: string, before?: number) {
  const pi = await harness.pi();
  const page = await pi.commit(
    (tx) =>
      tx.scanEntries(
        {
          conversationId: conversationOf(session),
          ...(before === undefined ? {} : { maxEntryId: before as EntryId }),
        },
        50,
      ),
    BACKGROUND_CONTEXT,
  );
  return {
    entries: page.items,
    nextBefore:
      page.items.length === 50
        ? Math.min(...page.items.map((entry) => Number(entry.id))) - 1
        : null,
  };
}
