/**
 * The workspace's live parts that are neither server records nor the URL: the conversation on
 * screen, and voice. Each sits in its own context or store, so the mic level, a poll or a
 * keystroke re-renders only what shows it.
 */
import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { BusinessDetail } from "../../app/wire.ts";
import type { ConversationKey, Message, ShownMessage } from "../../conversations/contract.ts";
import type { Employee } from "../../identity/contract.ts";
import { employeeOf } from "../../conversations/contract.ts";
import { parseRef } from "../../protocol/ref.ts";
import type { Mood } from "../design/face.tsx";
import { draft, useConversation, type Conversation } from "./conversation.ts";
import {
  isRunning,
  unfinished,
  useBusinessId,
  useEmployees,
  useOperations,
  useStatus,
} from "./data.ts";
import { conversationOf, refOfLayer, useLayers, useNav, usePlace } from "./navigation.ts";
import { queries } from "./query.ts";
import { createStore, useStore } from "./store.ts";
import { ui, useUi } from "./ui.ts";
import {
  errorMessage,
  loadVoiceSettings,
  mergeDraft,
  modeOf,
  speak,
  startCapture,
  stopSpeaking,
  type SpeechMode,
  type VoicePhase,
} from "./voice.ts";

const MainContext = createContext<Conversation | undefined>(undefined);
const MainKeyContext = createContext<ConversationKey | undefined>(undefined);
const WorkingContext = createContext<readonly string[]>([]);
const VoiceContext = createContext<VoiceActions | undefined>(undefined);

/** Voice, as the composer and Operations' face show it. */
const voiceStore = createStore<{
  phase: VoicePhase;
  conversationMode: boolean;
  volatileText: string;
  error: string | undefined;
}>({ phase: { kind: "idle" }, conversationMode: false, volatileText: "", error: undefined });
export const useVoice = <S,>(select: (state: ReturnType<typeof voiceStore.get>) => S) =>
  useStore(voiceStore, select);
export const useVoicePhase = () => useVoice((state) => state.phase.kind);

/** The microphone's level, 60 times a second: only the meters that draw it listen. */
const levelListeners = new Set<(level: number) => void>();
export function useMicLevel(active: boolean) {
  const [level, setLevel] = useState(0);
  useEffect(() => {
    if (!active) return;
    levelListeners.add(setLevel);
    return () => void levelListeners.delete(setLevel);
  }, [active]);
  return active ? level : 0;
}

type VoiceActions = ReturnType<typeof makeVoice>;

/** Voice serves the conversation on screen: dictation fills its draft; hands-free sends. */
function makeVoice(main: { current: Conversation }) {
  let capture: { finish: () => void; cancel: () => void } | undefined;
  const phase = () => voiceStore.get().phase;
  const setPhase = (next: VoicePhase) => voiceStore.set({ phase: next });
  const conversing = () => voiceStore.get().conversationMode;
  const setConversing = (on: boolean) => voiceStore.set({ conversationMode: on });

  /** Starts listening, as native `startCapture`; results flow into the draft or a hands-free turn. */
  function begin(mode: SpeechMode) {
    setPhase({ kind: "starting", mode });
    voiceStore.set({ error: undefined, volatileText: "" });
    const conversation = main.current;
    const base = mode === "handsFree" ? "" : draft.get(conversation.key).text;
    capture = startCapture(mode, {
      listening: () => setPhase({ kind: "listening", mode }),
      transcript: (finalized, volatile) => {
        voiceStore.set({ volatileText: volatile });
        // Sending mid-dictation still tells the employee the words were spoken.
        if (mode === "dictation")
          draft.set(conversation.key, mergeDraft(base, finalized), finalized ? true : undefined);
      },
      level: (level) => levelListeners.forEach((listener) => listener(level)),
      endOfSpeech: () => setPhase({ kind: "finishing", mode }),
      finished: (text) => {
        capture = undefined;
        voiceStore.set({ volatileText: "" });
        if (mode === "dictation") {
          draft.set(conversation.key, mergeDraft(base, text), true);
          setPhase({ kind: "idle" });
          return;
        }
        const sent = conversation.send(text, {
          viaVoice: true,
          speak: conversing() || loadVoiceSettings().speaksReplies,
        });
        setPhase(sent ? { kind: "awaitingReply" } : { kind: "idle" });
      },
      failed: (error) => {
        capture = undefined;
        voiceStore.set({ volatileText: "" });
        setPhase({ kind: "idle" });
        // Silence is normal in a conversation; keep listening.
        if (mode === "handsFree" && conversing() && error === "noSpeech") return begin("handsFree");
        if (error !== "cancelled" && error !== "noSpeech")
          voiceStore.set({ error: errorMessage[error] });
        if (
          error === "microphoneDenied" ||
          error === "unsupportedLocale" ||
          error === "unavailable"
        )
          setConversing(false);
      },
    });
  }
  const end = () => {
    setConversing(false);
    capture?.cancel();
    capture = undefined;
    if (phase().kind === "speaking") stopSpeaking();
    setPhase({ kind: "idle" });
  };
  return {
    /** The composer's mic: tap to dictate, tap again to finish. */
    micTapped: () => {
      const now = phase();
      if (now.kind === "idle") begin("dictation");
      else if (modeOf(now) === "dictation" && now.kind !== "finishing") {
        setPhase({ kind: "finishing", mode: "dictation" });
        capture?.finish();
      }
    },
    conversationToggled: () => {
      if (conversing()) return end();
      setConversing(true);
      if (phase().kind === "idle") begin("handsFree");
    },
    stopSpeaking: () => {
      stopSpeaking();
      if (phase().kind !== "speaking") return;
      setPhase({ kind: "idle" });
      if (conversing()) begin("handsFree");
    },
    /** Sending the draft ends dictation into it. */
    draftSent: () => {
      if (modeOf(phase()) !== "dictation") return;
      capture?.cancel();
      capture = undefined;
      setPhase({ kind: "idle" });
    },
    dismissError: () => voiceStore.set({ error: undefined }),
    /** Reads an answer aloud when the owner asked for it (hands-free or "Read replies aloud"). */
    answered: (message: Message) => {
      const now = phase();
      if (now.kind !== "awaitingReply" && now.kind !== "idle") return;
      setPhase({ kind: "speaking" });
      void speak(message.text, loadVoiceSettings()).then(() => {
        if (phase().kind !== "speaking") return;
        setPhase({ kind: "idle" });
        if (conversing()) begin("handsFree");
      });
    },
  };
}

type Detail = typeof BusinessDetail.Type;

/** The conversation on screen and voice, for everything inside one business's workspace. */
export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const businessId = useBusinessId();
  const place = usePlace();
  const operations = useOperations();
  const employees = useEmployees();
  const nav = useNav();
  const client = useQueryClient();
  const key = conversationOf(place, operations?.id);
  const voiceRef = useRef<VoiceActions>(undefined);

  /** A page published in the conversation on screen opens beside it. */
  const arrived = async (_key: ConversationKey, news: readonly ShownMessage[]) => {
    const page = news
      .filter((m) => m.kind === "event" && parseRef(m.ref)?.kind === "artifact")
      .at(-1);
    if (!page) return;
    const id = parseRef(page.ref)!.id;
    const author = employees.find((e) => e.id === employeeOf(page.author))?.name;
    // A new version is a page of the same name, so the list must already hold the new page.
    let detail = client.getQueryData<Detail>(queries.detail(businessId).queryKey);
    if (!detail?.artifacts.some((a) => a.id === id))
      detail = await client.fetchQuery(queries.detail(businessId)).catch(() => detail);
    const name = (artifact: string) => detail?.artifacts.find((a) => a.id === artifact)?.filename;
    nav.pageArrived(id, author, (a, b) => name(a) !== undefined && name(a) === name(b));
  };
  const main = useConversation(key, {
    businessId,
    employees,
    visible: true,
    arrived: (k, news) => void arrived(k, news),
    answered: (message) => voiceRef.current?.answered(message),
  });
  const mainRef = useRef(main);
  mainRef.current = main;
  const voice = useMemo(() => makeVoice(mainRef), []);
  voiceRef.current = voice;

  // A turn finished: open files read their contents again.
  const answering = main.working.length > 0;
  const wasAnswering = useRef(false);
  useEffect(() => {
    if (wasAnswering.current && !answering) ui.turnFinished();
    wasAnswering.current = answering;
  }, [answering]);

  return (
    <VoiceContext.Provider value={voice}>
      <MainKeyContext.Provider value={key}>
        <WorkingContext.Provider value={main.working}>
          <MainContext.Provider value={main}>{children}</MainContext.Provider>
        </WorkingContext.Provider>
      </MainKeyContext.Provider>
    </VoiceContext.Provider>
  );
}

/** The conversation in the middle of the screen. */
export function useMain() {
  const main = useContext(MainContext);
  if (!main) throw new Error("useMain needs a WorkspaceProvider");
  return main;
}
export const useMainKey = () => useContext(MainKeyContext);
/** Employees answering what was sent from the conversation on screen. */
export const useMainWorking = () => useContext(WorkingContext);
export function useVoiceActions() {
  const voice = useContext(VoiceContext);
  if (!voice) throw new Error("useVoiceActions needs a WorkspaceProvider");
  return voice;
}

/** Whether an employee is working or about to answer something sent from here. */
export function useWorking(employeeId: string) {
  const state = useStatus(employeeId).data;
  const answering = useMainWorking();
  return isRunning(state) || answering.includes(employeeId) || unfinished(state);
}

/** An employee's face: Operations follows the voice conversation; everyone else their runtime. */
export function useMood(employee: Employee): Mood {
  const operations = useOperations();
  const status = useStatus(employee.id);
  const working = useWorking(employee.id);
  const voice = useVoicePhase();
  if (employee.id === operations?.id) {
    // While talking by voice, Operations' face follows the conversation.
    if (voice === "starting" || voice === "listening" || voice === "finishing") return "listening";
    if (voice === "awaitingReply") return "thinking";
    if (voice === "speaking") return "working";
    if (status.isError) return "oops";
    if (status.isPending) return "thinking";
    return isRunning(status.data) ? "working" : "idle";
  }
  if (status.isError) return "oops";
  return working ? "working" : "idle";
}

/** The record on top of the panel, sent with the next message unless the owner removed it. */
export function useReference() {
  const { top } = useLayers();
  const referencing = useUi((state) => state.referencing);
  return top && referencing ? refOfLayer(top) : undefined;
}

/**
 * Sends the draft, marking it dictated if it was. The record the owner is looking at goes with
 * it as the message's ref, so "this" means what is on screen.
 */
export function useSendDraft() {
  const main = useMain();
  const reference = useReference();
  const voice = useVoiceActions();
  return () => {
    const current = draft.get(main.key);
    if (!current.text.trim()) return;
    voice.draftSent();
    main.send(current.text, {
      viaVoice: current.voiced,
      speak: loadVoiceSettings().speaksReplies,
      ...(reference ? { ref: reference } : {}),
    });
    draft.set(main.key, "", false);
    ui.setReferencing(false);
  };
}

/** Quotes a selection from a layer into the draft: the owner edits by asking. */
export function useAsk() {
  const key = useMainKey();
  return (quote: string) => {
    const lines = quote
      .trim()
      .split("\n")
      .slice(0, 12)
      .map((line) => `> ${line}`);
    draft.set(key, `${lines.join("\n")}\n\n${draft.get(key).text}`);
  };
}
