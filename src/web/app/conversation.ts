import { useCallback, useEffect, useRef, useState } from "react";
import {
  api,
  ApiError,
  type ConversationKey,
  type Employee,
  type Message,
  type RuntimeState,
  type ShownMessage,
} from "./api.ts";
import type { Unsent } from "./timeline.ts";

/** A page is 50 messages; a full one means there may be earlier ones. */
const pageSize = 50;
/** After a send, poll quickly until the answer arrives, as native does. */
const fastFor = 90_000;

export const employeeOf = (author: string) =>
  author.startsWith("employee:") ? author.slice("employee:".length) : undefined;

/** `@Name` mentions of employees in a draft, as the server reads them. */
export function mentionsIn(text: string, employees: readonly Pick<Employee, "id" | "name">[]) {
  const lower = text.toLowerCase();
  return [...employees]
    .sort((a, b) => b.name.length - a.name.length)
    .filter((employee) => lower.includes(`@${employee.name.toLowerCase()}`))
    .map((employee) => employee.id);
}

/** A message sent from this browser that the conversation doesn't show yet. */
export interface Pending extends Unsent {
  mentions: string[];
  /** The stored message, once the server accepted it. */
  posted?: string;
}

interface Waiting {
  to: string[];
  since: number;
  /** When the owner's message was stored; answers come after it. */
  after: string;
  /** Whether the first answer should be read aloud. */
  speak: boolean;
}

export interface ConversationDeps {
  businessId: string;
  employees: Employee[];
  /** Whether the owner can see this conversation, so it counts as read. */
  visible: boolean;
  running: (employeeId: string) => boolean;
  loadStatus: (employeeId: string) => Promise<RuntimeState | undefined>;
  failed: (error: unknown) => void;
  /** The conversation was read up to its newest message. */
  read: (key: ConversationKey) => void;
  /** An answer to a message sent by voice (or with "Read replies aloud") arrived. */
  answered: (message: Message) => void;
}

type Loadable<T> =
  | { status: "loading" }
  | { status: "loaded"; value: T }
  | { status: "failed"; message: string };

/**
 * One conversation: its messages, who answers next, the owner's draft, reply and
 * mention, and what was sent from here. The main pane and the work panel each have one.
 */
export function useConversation(key: ConversationKey | undefined, deps: ConversationDeps) {
  const { businessId, employees } = deps;
  const depsRef = useRef(deps);
  depsRef.current = deps;
  const [messages, setMessages] = useState<Loadable<ShownMessage[]>>({ status: "loading" });
  const [respondent, setRespondent] = useState<string | null>(null);
  const [hasOlder, setHasOlder] = useState(false);
  const [pending, setPending] = useState<Pending[]>([]);
  const [draft, setDraft] = useState("");
  const [replyingTo, setReplyingTo] = useState<string>();
  /** The employee picked from the To chip; they answer instead of anyone else. */
  const [picked, setPicked] = useState<string>();
  const [waiting, setWaitingState] = useState<Waiting>();
  const waitingRef = useRef<Waiting | undefined>(undefined);
  const setWaiting = (next: Waiting | undefined) => {
    waitingRef.current = next;
    setWaitingState(next);
  };
  const keyRef = useRef(key);
  keyRef.current = key;
  const kick = useRef<() => void>(() => undefined);
  const lastRead = useRef<string>(undefined);

  const refresh = useCallback(async () => {
    const target = keyRef.current;
    if (!target || !businessId) return;
    try {
      const page = await api.conversation(businessId, target);
      if (keyRef.current !== target) return;
      setRespondent(page.respondent);
      setMessages((previous) => {
        const known = previous.status === "loaded" ? previous.value : [];
        const first = page.messages[0]?.created_at;
        // Earlier pages already loaded stay in front of the newest one.
        const older = first ? known.filter((m) => m.created_at < first) : known;
        return { status: "loaded", value: [...older, ...page.messages] };
      });
      setHasOlder((older) => older || page.messages.length === pageSize);
      const wait = waitingRef.current;
      if (wait) {
        const answers = page.messages.filter(
          (m) => m.created_at > wait.after && employeeOf(m.author),
        );
        if (wait.speak && answers[0]) {
          depsRef.current.answered(answers[0]);
          setWaiting({ ...wait, speak: false });
        }
        await Promise.all(wait.to.map((id) => depsRef.current.loadStatus(id)));
        const done = wait.to.every(
          (id) => answers.some((m) => employeeOf(m.author) === id) && !depsRef.current.running(id),
        );
        if (done || Date.now() - wait.since > fastFor) setWaiting(undefined);
      }
    } catch (error) {
      depsRef.current.failed(error);
      if (keyRef.current !== target) return;
      setMessages((previous) =>
        previous.status === "loaded"
          ? previous
          : { status: "failed", message: "Couldn't load the conversation." },
      );
    }
  }, [businessId]);

  // A new conversation starts from its own history, with nothing carried over.
  useEffect(() => {
    setMessages({ status: "loading" });
    setRespondent(null);
    setHasOlder(false);
    setPending([]);
    setDraft("");
    setReplyingTo(undefined);
    setPicked(undefined);
    setWaiting(undefined);
    lastRead.current = undefined;
    if (!key || !businessId) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const tick = async () => {
      clearTimeout(timer);
      if (!document.hidden) await refresh();
      if (stopped) return;
      const wait = waitingRef.current;
      timer = setTimeout(
        () => void tick(),
        wait && Date.now() - wait.since < fastFor ? 2_000 : 5_000,
      );
    };
    kick.current = () => void tick();
    void tick();
    return () => {
      stopped = true;
      clearTimeout(timer);
      kick.current = () => undefined;
    };
  }, [businessId, key, refresh]);

  // History shows a sent message once it's stored; it stops being pending then.
  const history = messages.status === "loaded" ? messages.value : undefined;
  useEffect(() => {
    if (!history) return;
    const ids = new Set(history.map((m) => m.id));
    setPending((items) => {
      const kept = items.filter((item) => !item.posted || !ids.has(item.posted));
      return kept.length === items.length ? items : kept;
    });
  }, [history]);

  // Read while visible: the newest message's time moves the owner's read position.
  const newest = history?.[history.length - 1]?.created_at;
  useEffect(() => {
    if (!key || !newest || !deps.visible || lastRead.current === newest) return;
    if (typeof document !== "undefined" && document.hidden) return;
    lastRead.current = newest;
    depsRef.current.read(key);
    api.markRead(businessId, key, newest).catch(depsRef.current.failed);
  }, [businessId, key, newest, deps.visible]);

  const textMentions = mentionsIn(draft, employees);
  const mentions = picked ? [picked] : textMentions;
  const replied = history?.find((m) => m.id === replyingTo);
  /** Who answers the next message, as the server decides it. */
  const to: string[] = mentions.length
    ? mentions
    : replied && employeeOf(replied.author)
      ? [employeeOf(replied.author)!]
      : respondent
        ? [respondent]
        : [];

  const deliver = async (message: Pending, speak: boolean) => {
    const target = keyRef.current;
    if (!target) return;
    const update = (change: Partial<Pending>) =>
      setPending((items) =>
        items.map((item) => (item.id === message.id ? { ...item, ...change } : item)),
      );
    try {
      const result = await api.post(businessId, target, {
        id: message.id,
        text: message.text,
        ...(message.replyTo ? { replyTo: message.replyTo } : {}),
        ...(message.mentions.length ? { mentions: message.mentions } : {}),
        ...(message.viaVoice ? { viaVoice: true } : {}),
      });
      if (keyRef.current !== target) return;
      update({ delivery: "delivered", posted: result.message.id });
      setWaiting({
        to: result.to,
        since: Date.now(),
        after: result.message.created_at,
        speak,
      });
      for (const id of result.to) void depsRef.current.loadStatus(id);
      kick.current();
    } catch (error) {
      depsRef.current.failed(error);
      update({
        delivery: "failed",
        ...(error instanceof ApiError && error.status === 409 ? { error: error.message } : {}),
      });
    }
  };

  /** Sends text here; resolves to the client id, or undefined when there was nothing to send. */
  const send = (text: string, options: { viaVoice?: boolean; speak?: boolean } = {}) => {
    const trimmed = text.trim();
    if (!trimmed || !keyRef.current) return undefined;
    const message: Pending = {
      id: crypto.randomUUID(),
      text: trimmed,
      ...(replyingTo ? { replyTo: replyingTo } : {}),
      mentions: picked ? [picked] : mentionsIn(trimmed, employees),
      ...(options.viaVoice ? { viaVoice: true } : {}),
      delivery: "sending",
    };
    setReplyingTo(undefined);
    setPicked(undefined);
    setPending((items) => [...items, message]);
    void deliver(message, options.speak ?? false);
    return message.id;
  };

  const now = Date.now();
  /** Employees answering what was sent from here: running, or about to start. */
  const working = waiting
    ? waiting.to.filter(
        (id) =>
          deps.running(id) ||
          (now - waiting.since < 6_000 &&
            !history?.some((m) => m.created_at > waiting.after && employeeOf(m.author) === id)),
      )
    : [];

  return {
    key,
    messages,
    respondent,
    hasOlder,
    pending,
    draft,
    replyingTo: replied,
    picked,
    mentions,
    to,
    working,
    setDraft,
    send,
    reply: (messageId: string) => setReplyingTo(messageId),
    cancelReply: () => setReplyingTo(undefined),
    /** The To chip: this employee answers the next message instead. */
    pick: (employeeId: string | undefined) => setPicked(employeeId),
    retry: (id: string) => {
      const message = pending.find((item) => item.id === id);
      if (!message) return;
      const { error: _error, ...rest } = message;
      setPending((items) =>
        items.map((item) => (item.id === id ? { ...rest, delivery: "sending" } : item)),
      );
      void deliver({ ...rest, delivery: "sending" }, false);
    },
    /** Reactions belong to the employee who wrote the message. */
    react: (messageId: string, emoji: string) => {
      const message = history?.find((m) => m.id === messageId);
      const author = message && employeeOf(message.author);
      if (!message || !author) return;
      const removing = message.reactions.includes(emoji);
      const changes = [
        ...message.reactions.map((e) => ({ emoji: e, on: false })),
        ...(removing ? [] : [{ emoji, on: true }]),
      ];
      setMessages({
        status: "loaded",
        value: history!.map((m) =>
          m.id === messageId ? { ...m, reactions: removing ? [] : [emoji] } : m,
        ),
      });
      void (async () => {
        for (const change of changes)
          await api
            .react(businessId, author, {
              targetId: message.id,
              targetText: message.text,
              ...change,
            })
            .catch(() => undefined);
      })();
    },
    loadOlder: async () => {
      const target = keyRef.current;
      const oldest = history?.[0];
      if (!target || !oldest) return;
      const page = await api.conversation(businessId, target, oldest.id);
      if (keyRef.current !== target) return;
      setMessages((previous) => {
        const known = previous.status === "loaded" ? previous.value : [];
        const ids = new Set(known.map((m) => m.id));
        return {
          status: "loaded",
          value: [...page.messages.filter((m) => !ids.has(m.id)), ...known],
        };
      });
      setHasOlder(page.messages.length === pageSize);
    },
    refresh: () => kick.current(),
  };
}

export type Conversation = ReturnType<typeof useConversation>;
