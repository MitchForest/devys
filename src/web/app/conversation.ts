import type { Ref } from "../../protocol/ref.ts";
import {
  useInfiniteQuery,
  useQueries,
  useQueryClient,
  type InfiniteData,
} from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { api, ApiError } from "./api.ts";
import { expireOn401, keys, problemOf, queries } from "./query.ts";
import { createStore, useStore } from "./store.ts";
import type { ConversationPage, Conversations } from "../../app/wire.ts";
import {
  employeeOf,
  mentionsIn,
  type ConversationKey,
  type Message,
  type ShownMessage,
} from "../../conversations/contract.ts";
import type { Employee } from "../../identity/contract.ts";
import type { Unsent } from "./timeline.ts";

/** A page is 50 messages; a full one means there may be earlier ones. */
const pageSize = 50;
/** After a send, poll quickly until the answer arrives, as native does. */
const fastFor = 90_000;
/** Until then, everyone it went to shows as answering even before their run starts. */
const startingFor = 6_000;

/** A message sent from this browser that the conversation doesn't show yet. */
export interface Pending extends Unsent {
  mentions: string[];
  /** The stored message, once the server accepted it. */
  posted?: string;
}

interface Waiting {
  to: readonly string[];
  since: number;
  /** When the owner's message was stored; answers come after it. */
  after: string;
  /** Whether the first answer should be read aloud. */
  speak: boolean;
}

/** What one conversation holds on this browser only, reset when the conversation changes. */
interface Local {
  key: ConversationKey | undefined;
  pending: Pending[];
  replyingTo: string | undefined;
  /** The employee picked from the To chip; they answer instead of anyone else. */
  picked: string | undefined;
  waiting: Waiting | undefined;
}
const fresh = (key: ConversationKey | undefined): Local => ({
  key,
  pending: [],
  replyingTo: undefined,
  picked: undefined,
  waiting: undefined,
});

/**
 * The owner's draft, kept apart from the conversation so typing re-renders only the composer.
 * It belongs to one conversation: another one starts empty.
 */
const drafts = createStore<{ key: ConversationKey | undefined; text: string; voiced: boolean }>({
  key: undefined,
  text: "",
  voiced: false,
});
export const useDraft = (key: ConversationKey | undefined) =>
  useStore(drafts, (state) => (state.key === key ? state.text : ""));
export const draft = {
  get: (key: ConversationKey | undefined) => {
    const state = drafts.get();
    return state.key === key ? state : { key, text: "", voiced: false };
  },
  /** `voiced`: some of it was dictated, so the employee is told it was spoken. */
  set: (key: ConversationKey | undefined, text: string, voiced?: boolean) =>
    drafts.set((state) => ({
      key,
      text,
      voiced: voiced ?? (state.key === key ? state.voiced : false),
    })),
};

type Pages = InfiniteData<typeof ConversationPage.Type, string | undefined>;

interface Options {
  businessId: string;
  employees: readonly Employee[];
  /** Whether the owner can see this conversation, so it counts as read. */
  visible: boolean;
  /** Messages that arrived in this conversation since it was last read. */
  arrived?: (key: ConversationKey, messages: readonly ShownMessage[]) => void;
  /** An answer to a message sent by voice (or with "Read replies aloud") arrived. */
  answered?: (message: Message) => void;
}

/**
 * One conversation: its messages (pages read with TanStack Query, polled faster while an
 * answer is coming), who answers next, the owner's reply and pick, and what was sent from here.
 */
export function useConversation(key: ConversationKey | undefined, options: Options) {
  const { businessId, visible } = options;
  const client = useQueryClient();
  const [stored, setLocal] = useState<Local>(() => fresh(key));
  // A new conversation starts with nothing carried over.
  const local = stored.key === key ? stored : fresh(key);
  if (stored.key !== key) setLocal(local);
  const latest = useRef({ local, options });
  latest.current = { local, options };
  const update = useCallback(
    (change: (current: Local) => Partial<Local>) =>
      setLocal((current) => ({ ...current, ...change(current) })),
    [],
  );

  const queryKey = keys.conversation(businessId, key ?? ("direct:" as ConversationKey));
  const query = useInfiniteQuery({
    queryKey,
    enabled: Boolean(key && businessId),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last: typeof ConversationPage.Type) =>
      last.messages.length === pageSize ? last.messages[0]?.id : undefined,
    queryFn: async ({ pageParam }) => {
      const page = await api.conversation(businessId, key!, pageParam);
      if (pageParam === undefined) {
        // Messages arrive here: compared with what was read before, each new one is news.
        const before = client.getQueryData<Pages>(queryKey);
        if (before) {
          const known = new Set(before.pages.flatMap((p) => p.messages.map((m) => m.id)));
          const news = page.messages.filter((m) => !known.has(m.id));
          if (news.length) arrived(key!, news);
        }
      }
      return page;
    },
    refetchInterval: () => {
      const wait = latest.current.local.waiting;
      return wait && Date.now() - wait.since < fastFor ? 2_000 : 5_000;
    },
  });
  function arrived(target: ConversationKey, news: readonly ShownMessage[]) {
    const { local: now, options: current } = latest.current;
    if (now.key !== target) return;
    current.arrived?.(target, news);
    const wait = now.waiting;
    if (!wait?.speak) return;
    const answer = news.find((m) => m.created_at > wait.after && employeeOf(m.author));
    if (!answer) return;
    current.answered?.(answer);
    update((state) => (state.waiting ? { waiting: { ...state.waiting, speak: false } } : {}));
  }

  const pages = query.data?.pages;
  const messages = useMemo(() => {
    if (!pages) return undefined;
    const seen = new Set<string>();
    return pages
      .toReversed()
      .flatMap((page) => page.messages)
      .filter((m) => !seen.has(m.id) && Boolean(seen.add(m.id)));
  }, [pages]);
  const respondent = pages?.[0]?.respondent ?? null;

  // Who it went to: their runtimes say whether they are still answering.
  const waiting = local.waiting;
  const statuses = useQueries({
    queries: (waiting?.to ?? []).map((id) => ({
      ...queries.status(businessId, id),
      refetchInterval: 2_000,
    })),
  });
  const [, tick] = useReducer((n: number) => n + 1, 0);
  // The waiting window and the starting grace end by time, not by a read.
  useEffect(() => {
    if (!waiting) return;
    const elapsed = Date.now() - waiting.since;
    const timers = [startingFor, fastFor]
      .filter((at) => at > elapsed)
      .map((at) => setTimeout(tick, at - elapsed + 50));
    return () => timers.forEach(clearTimeout);
  }, [waiting]);
  const now = Date.now();
  const answeredBy = (id: string) =>
    messages?.some((m) => waiting && m.created_at > waiting.after && employeeOf(m.author) === id);
  /** Employees answering what was sent from here: running, or about to start. */
  const working =
    waiting && now - waiting.since < fastFor
      ? waiting.to.filter((id, index) => {
          const run = statuses[index]?.data?.state.run;
          return (
            Boolean(run && !run.stopped) || (now - waiting.since < startingFor && !answeredBy(id))
          );
        })
      : [];
  const workingKey = working.join(",");
  const workingIds = useMemo(() => (workingKey ? workingKey.split(",") : []), [workingKey]);

  // History shows a sent message once it's stored; it stops being pending then.
  const pending = useMemo(() => {
    const ids = new Set(messages?.map((m) => m.id));
    return local.pending.filter((item) => !item.posted || !ids.has(item.posted));
  }, [local.pending, messages]);

  // Read while visible: the newest message's time moves the owner's read position.
  const newest = messages?.at(-1)?.created_at;
  const lastRead = useRef<string>(undefined);
  useEffect(() => {
    if (!key || !newest || !visible || lastRead.current === `${key}@${newest}`) return;
    if (document.hidden) return;
    lastRead.current = `${key}@${newest}`;
    client.setQueryData<typeof Conversations.Type>(
      keys.summaries(businessId),
      (all) =>
        all && {
          conversations: all.conversations.map((c) => (c.key === key ? { ...c, unread: 0 } : c)),
        },
    );
    // A read position that didn't stick is moved by the next visit; only a 401 matters.
    api.markRead(businessId, key, newest).catch((error: unknown) => expireOn401(client, error));
  }, [businessId, client, key, newest, visible]);

  const deliver = useCallback(
    async (message: Pending, speak: boolean) => {
      const target = latest.current.local.key;
      if (!target) return;
      const change = (patch: Partial<Pending>) =>
        update((state) =>
          state.key === target
            ? {
                pending: state.pending.map((item) =>
                  item.id === message.id ? { ...item, ...patch } : item,
                ),
              }
            : {},
        );
      try {
        const result = await api.post(businessId, target, {
          id: message.id,
          text: message.text,
          ...(message.replyTo ? { reply_to: message.replyTo } : {}),
          ...(message.mentions.length ? { mentions: message.mentions } : {}),
          ...(message.viaVoice ? { via_voice: true } : {}),
          ...(message.ref ? { ref: message.ref } : {}),
        });
        change({ delivery: "delivered", posted: result.message.id });
        update((state) =>
          state.key === target
            ? {
                waiting: {
                  to: result.to,
                  since: Date.now(),
                  after: result.message.created_at,
                  speak,
                },
              }
            : {},
        );
        void client.invalidateQueries({ queryKey: keys.conversation(businessId, target) });
      } catch (error) {
        change({
          delivery: "failed",
          ...(error instanceof ApiError && error.status === 409 ? { error: error.message } : {}),
        });
      }
    },
    [businessId, client, update],
  );

  /** Sends text here; returns the client id, or undefined when there was nothing to send. */
  const send = useCallback(
    (text: string, sending: { viaVoice?: boolean; speak?: boolean; ref?: Ref } = {}) => {
      const trimmed = text.trim();
      const { local: now, options: current } = latest.current;
      if (!trimmed || !now.key) return undefined;
      const message: Pending = {
        id: crypto.randomUUID(),
        text: trimmed,
        ...(now.replyingTo ? { replyTo: now.replyingTo } : {}),
        mentions: now.picked ? [now.picked] : mentionsIn(trimmed, current.employees),
        ...(sending.viaVoice ? { viaVoice: true } : {}),
        ...(sending.ref ? { ref: sending.ref } : {}),
        delivery: "sending",
      };
      update((state) => ({
        replyingTo: undefined,
        picked: undefined,
        pending: [...state.pending, message],
      }));
      void deliver(message, sending.speak ?? false);
      return message.id;
    },
    [deliver, update],
  );

  const retry = useCallback(
    (id: string) => {
      const message = latest.current.local.pending.find((item) => item.id === id);
      if (!message) return;
      const { error: _error, ...rest } = message;
      const again: Pending = { ...rest, delivery: "sending" };
      update((state) => ({
        pending: state.pending.map((item) => (item.id === id ? again : item)),
      }));
      void deliver(again, false);
    },
    [deliver, update],
  );

  /** Reactions belong to the employee who wrote the message. */
  const react = useCallback(
    (messageId: string, emoji: string) => {
      const target = latest.current.local.key;
      const data = target && client.getQueryData<Pages>(keys.conversation(businessId, target));
      const message = data && data.pages.flatMap((p) => p.messages).find((m) => m.id === messageId);
      const author = message && employeeOf(message.author);
      if (!target || !message || !author) return;
      const removing = message.reactions.includes(emoji);
      const changes = [
        ...message.reactions.map((e) => ({ emoji: e, on: false })),
        ...(removing ? [] : [{ emoji, on: true }]),
      ];
      client.setQueryData<Pages>(
        keys.conversation(businessId, target),
        (all) =>
          all && {
            ...all,
            pages: all.pages.map((page) => ({
              ...page,
              messages: page.messages.map((m) =>
                m.id === messageId ? { ...m, reactions: removing ? [] : [emoji] } : m,
              ),
            })),
          },
      );
      void (async () => {
        for (const change of changes)
          await api
            .react(businessId, author, {
              target_id: message.id,
              target_text: message.text,
              ...change,
            })
            .catch((error: unknown) => expireOn401(client, error));
      })();
    },
    [businessId, client],
  );

  const { fetchNextPage, refetch } = query;
  const replied = messages?.find((m) => m.id === local.replyingTo);
  return useMemo(
    () => ({
      key,
      messages,
      status: query.status,
      problem: query.isError
        ? problemOf(query.error, "Couldn't load the conversation.")
        : undefined,
      respondent,
      hasOlder: query.hasNextPage,
      pending,
      replyingTo: replied,
      picked: local.picked,
      working: workingIds,
      send,
      retry,
      react,
      reply: (messageId: string) => update(() => ({ replyingTo: messageId })),
      cancelReply: () => update(() => ({ replyingTo: undefined })),
      /** The To chip: this employee answers the next message instead. */
      pick: (employeeId: string | undefined) => update(() => ({ picked: employeeId })),
      loadOlder: () => fetchNextPage().then(() => undefined),
      refresh: () => void refetch(),
    }),
    [
      key,
      messages,
      query.status,
      query.isError,
      query.error,
      respondent,
      query.hasNextPage,
      pending,
      replied,
      local.picked,
      workingIds,
      send,
      retry,
      react,
      update,
      fetchNextPage,
      refetch,
    ],
  );
}

export type Conversation = ReturnType<typeof useConversation>;

/**
 * Who answers the next message, as the server decides: those mentioned (or picked), else the
 * author of the message replied to, else whoever answers this conversation.
 */
export function answerersOf(
  conversation: Pick<Conversation, "picked" | "replyingTo" | "respondent">,
  text: string,
  employees: readonly Employee[],
) {
  const mentions = conversation.picked ? [conversation.picked] : mentionsIn(text, employees);
  const replied = conversation.replyingTo && employeeOf(conversation.replyingTo.author);
  const to: string[] = mentions.length
    ? mentions
    : replied
      ? [replied]
      : conversation.respondent
        ? [conversation.respondent]
        : [];
  return { mentions, to };
}
