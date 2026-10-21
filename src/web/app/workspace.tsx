import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  api,
  ApiError,
  type AccessList,
  type Artifact,
  type Business,
  type Commitment,
  type CommitmentState,
  type ConversationKey,
  type ConversationSummary,
  type Decision,
  type Employee,
  type MemoryClaim,
  type ModelCatalog,
  type NewTask,
  type Person,
  type RoleTemplate,
  type SettableLook,
  type RuntimeState,
  type AppEntry,
  type Home,
  type Message,
  type Project,
  type ProjectChange,
  type ProjectItem,
  type StartingRole,
} from "./api.ts";
import { useConversation } from "./conversation.ts";
import { downscale } from "./images.ts";
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

/**
 * Where the owner is: always a conversation. Home is the direct chat with Operations; a
 * project is its channel; a thread is a work item's conversation.
 */
export type Place =
  | { kind: "home" }
  | { kind: "direct"; employeeId: string }
  | { kind: "project"; id: string }
  | { kind: "thread"; workId: string };
export type PlaceKind = Place["kind"];

/** A temporary view stacked over the right panel's permanent view. */
export type Layer =
  | { kind: "artifact"; id: string; updatedBy?: string }
  | { kind: "file"; path: string }
  | { kind: "app"; app: string }
  | { kind: "session"; workId: string; sessionId: string }
  | { kind: "browser"; workId: string };
/** `auto`: it opened on its own, so the next one may replace it. */
export type OpenLayer = Layer & { auto?: boolean };

export const samePlace = (a: Place, b: Place) => JSON.stringify(a) === JSON.stringify(b);

/** The conversation a place shows: Home's is the direct chat with Operations. */
export const conversationOf = (
  place: Place,
  operations: string | undefined,
): ConversationKey | undefined =>
  place.kind === "home"
    ? operations
      ? `direct:${operations}`
      : undefined
    : place.kind === "direct"
      ? `direct:${place.employeeId}`
      : place.kind === "project"
        ? `project:${place.id}`
        : `work:${place.workId}`;

/** Whether each kind of place shows its permanent view; the owner's choice is remembered. */
const panelDefaults: Record<PlaceKind, boolean> = {
  home: true,
  direct: false,
  project: true,
  thread: true,
};
const savedPanels = (): Record<PlaceKind, boolean> => {
  try {
    return { ...panelDefaults, ...JSON.parse(localStorage.getItem("panels") ?? "{}") };
  } catch {
    return panelDefaults;
  }
};

/** What a layer is, in words, for its header and the reference sent with a message. */
export function layerReference(layer: Layer, names: { artifact: (id: string) => string }) {
  switch (layer.kind) {
    case "artifact":
      return { title: names.artifact(layer.id), ref: `page artifact:${layer.id}` };
    case "file":
      return { title: layer.path.split("/").at(-1)!, ref: `file ${layer.path}` };
    case "app":
      return { title: appTitle(layer.app), ref: `the ${appTitle(layer.app)} app` };
    case "session":
      return {
        title: "Coding session",
        ref: `coding session ${layer.sessionId} on work:${layer.workId}`,
      };
    case "browser":
      return { title: "Browser", ref: "the business's browser" };
  }
}
const appTitle = (app: string) => app.charAt(0).toUpperCase() + app.slice(1);

export const filterOf = (state: CommitmentState) =>
  state === "needs_decision"
    ? "needsYou"
    : state === "waiting"
      ? "waiting"
      : state === "completed" || state === "cancelled"
        ? "done"
        : "inProgress";

/** Opening "New task" from a project or an employee fills in what it can. */
export interface TaskDefaults {
  owner?: string;
  projectId?: string;
}

export type Loadable<T> =
  | { status: "loading" }
  | { status: "loaded"; value: T }
  | { status: "failed"; message: string };
const loading = { status: "loading" } as const;
const loaded = <T,>(value: T): Loadable<T> => ({ status: "loaded", value });
export const valueOf = <T,>(item: Loadable<T>) =>
  item.status === "loaded" ? item.value : undefined;

const unfinished = (state: RuntimeState | undefined) =>
  state?.inbox.some((i) => i.status !== "done" && i.status !== "failed") ?? false;

function useWorkspaceState() {
  const [person, setPerson] = useState<Person>();
  const [businesses, setBusinesses] = useState<Business[]>([]);
  const [businessId, setBusinessId] = useState("");
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [members, setMembers] = useState<Person[]>([]);
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [statuses, setStatuses] = useState<Record<string, Loadable<RuntimeState>>>({});
  const [summaries, setSummaries] = useState<Record<string, ConversationSummary>>({});
  const [work, setWork] = useState<Loadable<Commitment[]>>(loading);
  const [decisions, setDecisions] = useState<Loadable<Decision[]>>(loading);
  const [projects, setProjects] = useState<Loadable<Project[]>>(loading);
  const [apps, setApps] = useState<Loadable<AppEntry[]>>(loading);
  const [home, setHome] = useState<Loadable<Home>>(loading);
  const [memory, setMemory] = useState<Loadable<MemoryClaim[]>>(loading);
  const [models, setModels] = useState<Loadable<ModelCatalog>>(loading);
  const [roles, setRoles] = useState<Loadable<RoleTemplate[]>>(loading);
  const [access, setAccess] = useState<{ employeeId: string; list: Loadable<AccessList> }>();
  const [artifactTexts, setArtifactTexts] = useState<Record<string, Loadable<string>>>({});
  const [place, setPlace] = useState<Place>({ kind: "home" });
  /** Places the owner came from, for Back (a thread opened from a channel). */
  const [history, setHistory] = useState<Place[]>([]);
  const [layers, setLayers] = useState<OpenLayer[]>([]);
  const [panels, setPanels] = useState(savedPanels);
  const [wide, setWide] = useState(false);
  /**
   * Too narrow for the conversation and the panel side by side: the panel lies over the
   * conversation, so its permanent view opens only when asked for, never by itself.
   */
  const [narrow, setNarrow] = useState(false);
  const [overlay, setOverlay] = useState(false);
  const [sidebarVisible, setSidebarVisible] = useState(true);
  /** Whether the open layer goes with the next message as a reference. */
  const [referencing, setReferencing] = useState(true);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsSection, setSettingsSection] = useState<string>();
  const [hireOpen, setHireOpen] = useState(false);
  const [projectOpen, setProjectOpen] = useState(false);
  const [taskDefaults, setTaskDefaults] = useState<TaskDefaults>();
  /** Counts finished turns, so open layers read their records again. */
  const [turns, setTurns] = useState(0);
  const [notice, setNotice] = useState<string>();
  const [signedOut, setSignedOut] = useState(false);
  const [ownerPhoto, setOwnerPhoto] = useState<string>();
  const current = useRef("");
  current.current = businessId;
  const [voice, setVoiceState] = useState<VoicePhase>({ kind: "idle" });
  const voiceRef = useRef<VoicePhase>({ kind: "idle" });
  const setVoice = (next: VoicePhase) => {
    voiceRef.current = next;
    setVoiceState(next);
  };
  const [conversationMode, setConversationModeState] = useState(false);
  const conversationRef = useRef(false);
  const setConversationMode = (on: boolean) => {
    conversationRef.current = on;
    setConversationModeState(on);
  };
  const draftUsedVoice = useRef(false);
  const [volatileText, setVolatileText] = useState("");
  const [level, setLevel] = useState(0);
  const [voiceError, setVoiceError] = useState<string>();
  const capture = useRef<{ finish: () => void; cancel: () => void }>(undefined);

  const operations = employees.find((e) => e.template === "operations") ?? employees[0];

  const failed = useCallback((error: unknown) => {
    if (error instanceof ApiError && error.status === 401) setSignedOut(true);
  }, []);

  const loadAccount = useCallback(async () => {
    try {
      const me = await api.me();
      setPerson(me.person);
      setBusinesses(me.businesses);
      setSignedOut(false);
      setBusinessId((id) =>
        me.businesses.some((b) => b.id === id) ? id : (me.businesses[0]?.id ?? ""),
      );
    } catch (error) {
      failed(error);
    }
  }, [failed]);

  const loadBusiness = useCallback(
    async (id: string) => {
      if (!id) return;
      try {
        const detail = await api.business(id);
        if (current.current !== id) return;
        setEmployees(detail.employees);
        setMembers(detail.members);
        setArtifacts(detail.artifacts);
      } catch (error) {
        failed(error);
      }
    },
    [failed],
  );

  const loadWork = useCallback(
    async (id: string) => {
      if (!id) return;
      try {
        const [w, d, p, h] = await Promise.all([
          api.work(id),
          api.decisions(id),
          api.projects(id),
          api.home(id),
        ]);
        if (current.current !== id) return;
        setWork(loaded(w.commitments));
        setDecisions(loaded(d.decisions));
        setProjects(loaded(p.projects));
        setHome(loaded(h));
      } catch (error) {
        failed(error);
      }
    },
    [failed],
  );

  const loadApps = useCallback(
    async (id: string) => {
      if (!id) return;
      try {
        const result = await api.apps(id);
        if (current.current === id) setApps(loaded(result.apps));
      } catch (error) {
        failed(error);
      }
    },
    [failed],
  );

  /** Last messages and unread counts for the sidebar's chats, channels and threads. */
  const loadSummaries = useCallback(
    async (id: string) => {
      if (!id) return;
      try {
        const { conversations } = await api.conversations(id);
        if (current.current !== id) return;
        setSummaries(Object.fromEntries(conversations.map((c) => [c.key, c])));
      } catch (error) {
        failed(error);
      }
    },
    [failed],
  );

  const loadStatus = useCallback(
    async (id: string, employeeId: string) => {
      try {
        const result = await api.status(id, employeeId);
        if (current.current !== id) return;
        setStatuses((all) => ({ ...all, [employeeId]: loaded(result.state) }));
        return result.state;
      } catch (error) {
        failed(error);
        setStatuses((all) =>
          all[employeeId]?.status === "loaded"
            ? all
            : {
                ...all,
                [employeeId]: { status: "failed", message: "The server isn't reachable." },
              },
        );
        return undefined;
      }
    },
    [failed],
  );

  useEffect(() => {
    void loadAccount();
  }, [loadAccount]);

  const loadOwnerPhoto = useCallback(async () => {
    const response = await fetch(api.profilePhotoUrl, { cache: "no-store" }).catch(() => undefined);
    setOwnerPhoto(response?.ok ? URL.createObjectURL(await response.blob()) : undefined);
  }, []);
  useEffect(() => {
    if (person) void loadOwnerPhoto();
  }, [person, loadOwnerPhoto]);
  // The deployment's models and role templates are the same for every business.
  const signedIn = Boolean(person);
  useEffect(() => {
    if (!signedIn) return;
    api
      .models()
      .then((catalog) => setModels(loaded(catalog)))
      .catch(() => setModels({ status: "failed", message: "Models are unavailable." }));
    api
      .roles()
      .then((list) => setRoles(loaded(list.roles)))
      .catch(() => setRoles({ status: "failed", message: "Roles are unavailable." }));
  }, [signedIn]);

  // A new business: reset everything that belongs to the last one, then load.
  useEffect(() => {
    setEmployees([]);
    setArtifacts([]);
    setStatuses({});
    setSummaries({});
    setWork(loading);
    setDecisions(loading);
    setProjects(loading);
    setApps(loading);
    setHome(loading);
    setMemory(loading);
    setAccess(undefined);
    setArtifactTexts({});
    setLayers([]);
    if (!businessId) return;
    void loadBusiness(businessId);
    void loadWork(businessId);
    void loadApps(businessId);
    void loadSummaries(businessId);
    api
      .memory(businessId)
      .then((m) => current.current === businessId && setMemory(loaded(m.items)))
      .catch(() => setMemory({ status: "failed", message: "Memory is unavailable." }));
  }, [businessId, loadBusiness, loadWork, loadSummaries, loadApps]);

  // Every employee's runtime, so presence and spend are real for the whole team.
  const team = employees.map((e) => e.id).join(",");
  const teamRef = useRef<string[]>([]);
  teamRef.current = employees.map((e) => e.id);
  useEffect(() => {
    if (!businessId) return;
    for (const id of teamRef.current) void loadStatus(businessId, id);
  }, [businessId, team, loadStatus]);

  // Refreshed every five seconds as on native; open conversations poll themselves.
  useEffect(() => {
    if (!businessId) return;
    const timer = setInterval(() => {
      if (document.hidden) return;
      for (const id of teamRef.current) void loadStatus(businessId, id);
      void loadWork(businessId);
      void loadSummaries(businessId);
      // Looks and pauses changed from another client show here within one tick.
      void loadAccount();
      void loadBusiness(businessId);
    }, 5_000);
    return () => clearInterval(timer);
  }, [businessId, loadStatus, loadWork, loadSummaries, loadAccount, loadBusiness]);

  const statusOf = (employeeId: string | undefined): Loadable<RuntimeState> =>
    (employeeId && statuses[employeeId]) || loading;
  const runningOf = (employeeId: string | undefined) => {
    const state = valueOf(statusOf(employeeId));
    return Boolean(state?.run && !state.run.stopped);
  };

  /** Reads an answer aloud when the owner asked for it (hands-free or "Read replies aloud"). */
  const answered = (message: { text: string }) => {
    const phase = voiceRef.current;
    if (phase.kind !== "awaitingReply" && phase.kind !== "idle") return;
    setVoice({ kind: "speaking" });
    void speak(message.text, loadVoiceSettings()).then(() => {
      if (voiceRef.current.kind !== "speaking") return;
      setVoice({ kind: "idle" });
      if (conversationRef.current) beginCapture("handsFree");
    });
  };
  const mainKey = conversationOf(place, operations?.id);
  const main = useConversation(mainKey, {
    businessId,
    employees,
    running: runningOf,
    loadStatus: (employeeId: string) => loadStatus(businessId, employeeId),
    failed,
    read: (key: ConversationKey) =>
      setSummaries((all) => (all[key] ? { ...all, [key]: { ...all[key]!, unread: 0 } } : all)),
    answered,
    visible: true,
  });
  const targetRef = useRef(main);
  targetRef.current = main;

  // A turn finished: open layers read their records again.
  const answering = main.working.length > 0;
  const wasAnswering = useRef(false);
  useEffect(() => {
    if (wasAnswering.current && !answering) setTurns((n) => n + 1);
    wasAnswering.current = answering;
  }, [answering]);

  // A page published in the conversation on screen opens on its own unless the owner opened
  // a layer themselves; a new version of the open page replaces it in place.
  const artifactsRef = useRef(artifacts);
  artifactsRef.current = artifacts;
  const seen = useRef<{ key?: string; ids: Set<string> }>({ ids: new Set() });
  const history_ = valueOf(main.messages);
  useEffect(() => {
    if (!history_) return;
    const known = seen.current;
    const fresh = known.key === mainKey;
    const arrived = fresh ? history_.filter((m) => !known.ids.has(m.id)) : [];
    seen.current = { key: mainKey, ids: new Set(history_.map((m) => m.id)) };
    const page = arrived.filter((m) => m.kind === "event" && m.ref?.startsWith("artifact:")).at(-1);
    if (page) void pageArrived(page);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [history_, mainKey]);
  async function pageArrived(message: Message) {
    const id = message.ref!.slice("artifact:".length);
    const author = message.author.startsWith("employee:")
      ? employees.find((e) => `employee:${e.id}` === message.author)?.name
      : undefined;
    // A version is recognised by its page's name, so the list must already hold the new page.
    let known = artifactsRef.current;
    if (!known.some((a) => a.id === id)) {
      known = await api.business(businessId).then(
        (detail) => detail.artifacts,
        () => known,
      );
      setArtifacts(known);
    }
    const name = (artifactId: string) => known.find((a) => a.id === artifactId)?.filename;
    setLayers((open) => {
      const top = open.at(-1);
      if (top?.kind === "artifact" && name(top.id) !== undefined && name(top.id) === name(id))
        return [...open.slice(0, -1), { ...top, id, ...(author ? { updatedBy: author } : {}) }];
      if (top && !top.auto) return open;
      return [{ kind: "artifact", id, auto: true }];
    });
    setReferencing(true);
  }

  const refreshAfter = useCallback(
    async (change: () => Promise<unknown>, failure: string) => {
      let ok = true;
      try {
        await change();
      } catch (error) {
        ok = false;
        failed(error);
        setNotice(
          error instanceof ApiError && error.status === 409
            ? `${failure} It changed; showing the latest.`
            : failure,
        );
      }
      await Promise.all([loadWork(businessId), loadBusiness(businessId)]);
      return ok;
    },
    [businessId, failed, loadBusiness, loadWork],
  );

  /** Sends in the conversation on screen; replies are read aloud when asked for. */
  const sendText = (text: string, viaVoice: boolean) =>
    targetRef.current.send(text, {
      viaVoice,
      speak: conversationRef.current || loadVoiceSettings().speaksReplies,
    });

  /** Starts listening, as native `startCapture`; results flow into the draft or a hands-free turn. */
  function beginCapture(mode: SpeechMode) {
    setVoice({ kind: "starting", mode });
    setVoiceError(undefined);
    setVolatileText("");
    const base = mode === "handsFree" ? "" : targetRef.current.draft;
    const conversation = targetRef.current;
    capture.current = startCapture(mode, {
      listening: () => setVoice({ kind: "listening", mode }),
      transcript: (finalized, volatile) => {
        setVolatileText(volatile);
        if (mode === "dictation") {
          conversation.setDraft(mergeDraft(base, finalized));
          // Sending mid-dictation still tells the employee the words were spoken.
          if (finalized) draftUsedVoice.current = true;
        }
      },
      level: setLevel,
      endOfSpeech: () => setVoice({ kind: "finishing", mode }),
      finished: (text) => {
        capture.current = undefined;
        setVolatileText("");
        if (mode === "dictation") {
          conversation.setDraft(mergeDraft(base, text));
          draftUsedVoice.current = true;
          setVoice({ kind: "idle" });
          return;
        }
        if (!sendText(text, true)) return setVoice({ kind: "idle" });
        setVoice({ kind: "awaitingReply" });
      },
      failed: (error) => {
        capture.current = undefined;
        setVolatileText("");
        setVoice({ kind: "idle" });
        // Silence is normal in a conversation; keep listening.
        if (mode === "handsFree" && conversationRef.current && error === "noSpeech")
          return beginCapture("handsFree");
        if (error !== "cancelled" && error !== "noSpeech") setVoiceError(errorMessage[error]);
        if (
          error === "microphoneDenied" ||
          error === "unsupportedLocale" ||
          error === "unavailable"
        )
          setConversationMode(false);
      },
    });
  }

  const endConversation = () => {
    setConversationMode(false);
    capture.current?.cancel();
    capture.current = undefined;
    if (voiceRef.current.kind === "speaking") stopSpeaking();
    setVoice({ kind: "idle" });
  };
  const business = businesses.find((b) => b.id === businessId);
  const artifactName = (id: string) =>
    artifacts.find((a) => a.id === id)?.filename.replace(/\.html$/, "") ?? "Page";
  const topLayer = layers.at(-1);
  /** The open layer, in words, sent with the next message unless the owner removed it. */
  const reference =
    topLayer && topLayer.kind !== "app" && referencing
      ? layerReference(topLayer, { artifact: artifactName })
      : undefined;
  const actions = {
    selectBusiness: (id: string) => {
      if (id === businessId) return;
      setBusinessId(id);
      setPlace({ kind: "home" });
      setHistory([]);
    },
    /** Goes to a place from the sidebar: the layers close, Back starts over. */
    selectPlace: (next: Place) => {
      setOverlay(false);
      setHistory([]);
      setLayers([]);
      setWide(false);
      setPlace(next);
    },
    /** Opens the DM with an employee. */
    message: (employeeId: string) => actions.selectPlace({ kind: "direct", employeeId }),
    /** Moves into a work item's thread; Back returns to where the owner was. */
    openThread: (workId: string) => {
      if (place.kind === "thread" && place.workId === workId) return;
      setHistory((h) => [...h, place]);
      setLayers([]);
      setPlace({ kind: "thread", workId });
    },
    back: () => {
      const previous = history.at(-1);
      if (!previous) return;
      setHistory((h) => h.slice(0, -1));
      setLayers([]);
      setPlace(previous);
    },
    /** Stacks a layer over the right panel; opening what is already on top does nothing. */
    openLayer: (layer: Layer) => {
      setReferencing(true);
      setLayers((open) =>
        open.length && JSON.stringify({ ...open.at(-1), auto: undefined }) === JSON.stringify(layer)
          ? open
          : [...open, layer],
      );
    },
    /** Replaces the top layer (a file opened from the Documents app keeps one level). */
    replaceLayer: (layer: Layer) => setLayers((open) => [...open.slice(0, -1), layer]),
    /** Back one layer. */
    popLayer: () => setLayers((open) => open.slice(0, -1)),
    /** Back to the permanent view. */
    closeLayers: () => {
      setLayers([]);
      setWide(false);
    },
    /** Shows or hides the right panel for this kind of place, remembered across visits. */
    togglePanel: () => {
      if (layers.length) return actions.closeLayers();
      if (narrow) return setOverlay((v) => !v);
      setPanels((all) => {
        const next = { ...all, [place.kind]: !all[place.kind] };
        try {
          localStorage.setItem("panels", JSON.stringify(next));
        } catch {
          // A remembered panel is a convenience only.
        }
        return next;
      });
    },
    toggleWide: () => setWide((v) => !v),
    setNarrow,
    setReferencing,
    /** Hear each milestone of a work item (and keep it in the sidebar), or only its outcome. */
    setFollowing: async (workId: string, on: boolean) => {
      const key = `work:${workId}` as ConversationKey;
      setSummaries((all) => ({
        ...all,
        [key]: { key, last: all[key]?.last ?? null, unread: all[key]?.unread ?? 0, following: on },
      }));
      try {
        await api.follow(businessId, key, on);
      } catch (error) {
        failed(error);
      }
    },
    toggleSidebar: () => setSidebarVisible((v) => !v),
    setPaletteOpen,
    setSettingsOpen: (open: boolean, section?: string) => {
      setSettingsSection(section);
      setSettingsOpen(open);
    },
    setHireOpen,
    setProjectOpen,
    newTask: (defaults: TaskDefaults = {}) => setTaskDefaults(defaults),
    closeNewTask: () => setTaskDefaults(undefined),
    dismissNotice: () => setNotice(undefined),
    stop: (employeeId = operations?.id) =>
      employeeId &&
      void api
        .stop(businessId, employeeId)
        .then(() => setNotice("Stop requested. Work already sent cannot be unsent."))
        .then(() => loadStatus(businessId, employeeId)),
    /**
     * Sends the draft, marking it dictated if it was. The layer the owner is looking at goes
     * with it as a reference line, so "this" means what is on screen.
     */
    sendDraft: () => {
      const conversation = main;
      if (!conversation.draft.trim()) return;
      if (modeOf(voice) === "dictation") {
        capture.current?.cancel();
        capture.current = undefined;
        setVoice({ kind: "idle" });
      }
      const text = reference
        ? `${conversation.draft.trim()}\n\n_Viewing: ${reference.title} (${reference.ref})_`
        : conversation.draft;
      conversation.send(text, {
        viaVoice: draftUsedVoice.current,
        speak: loadVoiceSettings().speaksReplies,
      });
      draftUsedVoice.current = false;
      conversation.setDraft("");
      setReferencing(false);
    },
    /** Quotes a selection from a layer into the draft: the owner edits by asking. */
    ask: (quote: string) => {
      const lines = quote
        .trim()
        .split("\n")
        .slice(0, 12)
        .map((line) => `> ${line}`);
      main.setDraft(`${lines.join("\n")}\n\n${main.draft}`);
    },
    /**
     * Starts a thread on a message: a work item owned by whoever it addressed, in the
     * project it was said in, titled from the message.
     */
    startThread: async (message: { text: string; author: string; mentions: string[] }) => {
      const author = message.author.startsWith("employee:")
        ? message.author.slice("employee:".length)
        : undefined;
      const owner = author ?? message.mentions[0] ?? main.to[0] ?? operations?.id;
      if (!owner) return;
      const projectId =
        place.kind === "project"
          ? place.id
          : place.kind === "thread"
            ? (valueOf(work)?.find((w) => w.id === place.workId)?.project_id ?? undefined)
            : undefined;
      const text = message.text.replace(/\n\n_Viewing: [^\n]*_$/, "").trim();
      try {
        const created = await api.createCommitment(businessId, {
          title: text.split("\n")[0]!.slice(0, 80),
          owner,
          objective: text.slice(0, 4000),
          ...(projectId ? { projectId } : {}),
        });
        await loadWork(businessId);
        // The owner started it, so they follow it: it stays in the sidebar under its project.
        void actions.setFollowing(created.id, true);
        actions.openThread(created.id);
      } catch (error) {
        failed(error);
        setNotice("That thread couldn't be started.");
      }
    },
    /** The composer's mic; voice serves the conversation on screen. */
    micTapped: () => {
      if (voice.kind === "idle") {
        beginCapture("dictation");
      } else if (modeOf(voice) === "dictation" && voice.kind !== "finishing") {
        setVoice({ kind: "finishing", mode: "dictation" });
        capture.current?.finish();
      }
    },
    conversationToggled: () => {
      if (conversationRef.current) return endConversation();
      setConversationMode(true);
      if (voiceRef.current.kind === "idle") beginCapture("handsFree");
    },
    stopSpeaking: () => {
      stopSpeaking();
      if (voiceRef.current.kind === "speaking") {
        setVoice({ kind: "idle" });
        if (conversationRef.current) beginCapture("handsFree");
      }
    },
    dismissVoiceError: () => setVoiceError(undefined),
    answer: (decisionId: string, approve: boolean) => {
      setDecisions((items) =>
        items.status === "loaded" ? loaded(items.value.filter((d) => d.id !== decisionId)) : items,
      );
      void refreshAfter(
        () => api.answer(businessId, decisionId, approve),
        "That request was already answered or has expired.",
      );
    },
    /** A task with an owner, objective, due date and project; opens its thread once saved. */
    createTask: async (task: NewTask) => {
      const created = await api.createCommitment(businessId, task);
      await loadWork(businessId);
      void actions.setFollowing(created.id, true);
      actions.openThread(created.id);
    },
    setCommitmentState: (item: Commitment, state: CommitmentState) =>
      void refreshAfter(
        () => api.updateCommitment(businessId, item, { state }),
        "That commitment changed.",
      ),
    /** Edits what's next, what it waits on and when it's due, at the revision on screen. */
    editCommitment: (
      item: Commitment,
      change: { nextAction?: string; waitCondition?: string | null; dueAt?: string | null },
    ) =>
      refreshAfter(
        () => api.updateCommitment(businessId, item, change),
        "That work couldn't be saved.",
      ),
    /** Hands the work to another employee; it starts ready so the dispatcher hands it over. */
    reassign: (item: Commitment, owner: string) =>
      void refreshAfter(
        () => api.updateCommitment(businessId, item, { owner, state: "ready" }),
        "That work couldn't be reassigned.",
      ),
    toggleTakeover: (item: Commitment) =>
      void refreshAfter(
        () => api.setTakeover(businessId, item.id, item.taken_over_by === null),
        "Couldn't change who handles that work.",
      ),
    createProject: async (project: ProjectChange & { name: string }) => {
      const name = project.name.trim().slice(0, 80);
      if (!name) return false;
      try {
        const created = await api.createProject(businessId, { ...project, name });
        await loadWork(businessId);
        actions.selectPlace({ kind: "project", id: created.id });
        return true;
      } catch (error) {
        failed(error);
        setNotice("The project couldn't be created.");
        return false;
      }
    },
    updateProject: (id: string, change: ProjectChange) =>
      refreshAfter(
        () => api.updateProject(businessId, id, change),
        "The project couldn't be saved.",
      ),
    addToProject: (projectId: string, kind: ProjectItem["kind"], ref: string) =>
      void refreshAfter(
        () => api.addToProject(businessId, projectId, kind, ref),
        "That couldn't be added to the project.",
      ),
    removeFromProject: (projectId: string, itemId: string) =>
      void refreshAfter(
        () => api.removeFromProject(businessId, projectId, itemId),
        "That couldn't be removed.",
      ),
    installApp: async (app: string, on: boolean) => {
      try {
        await api.installApp(businessId, app, on);
      } catch (error) {
        failed(error);
        setNotice(on ? "That app couldn't be installed." : "That app couldn't be removed.");
      }
      await loadApps(businessId);
    },
    pinApp: async (app: string, pinned: boolean) => {
      setApps((all) =>
        all.status === "loaded"
          ? loaded(all.value.map((a) => (a.id === app ? { ...a, pinned } : a)))
          : all,
      );
      await api.pinApp(businessId, app, pinned).catch(failed);
      await loadApps(businessId);
    },
    openArtifact: (id: string) => {
      if (artifactTexts[id]) return;
      setArtifactTexts((texts) => ({ ...texts, [id]: loading }));
      api
        .artifactText(businessId, id)
        .then((text) => setArtifactTexts((texts) => ({ ...texts, [id]: loaded(text) })))
        .catch(() =>
          setArtifactTexts((texts) => ({
            ...texts,
            [id]: { status: "failed", message: "This file couldn't be opened." },
          })),
        );
    },
    loadAccess: (employeeId: string) => {
      setAccess((previous) =>
        previous?.employeeId === employeeId ? previous : { employeeId, list: loading },
      );
      api
        .access(businessId, employeeId)
        .then((list) => setAccess({ employeeId, list: loaded(list) }))
        .catch(failed);
    },
    grant: (employeeId: string, capability: string, mode: "auto" | "ask") =>
      void refreshAfter(
        () => api.grant(businessId, employeeId, capability, mode),
        "That access change didn't go through.",
      ).then(() => actions.loadAccess(employeeId)),
    revoke: (employeeId: string, grantId: string) =>
      void refreshAfter(
        () => api.revoke(businessId, employeeId, grantId),
        "That access change didn't go through.",
      ).then(() => actions.loadAccess(employeeId)),
    togglePause: (employee: Employee) => {
      setEmployees((items) =>
        items.map((e) => (e.id === employee.id ? { ...e, paused: !e.paused } : e)),
      );
      void refreshAfter(
        () => api.setPaused(businessId, employee.id, !employee.paused),
        `Couldn't ${employee.paused ? "resume" : "pause"} that employee.`,
      );
    },
    /** Hires from a template and opens the new employee's page. */
    hire: async (input: {
      template: string;
      name?: string;
      responsibilities?: string;
      model?: string;
    }) => {
      const hired = await api.hire(businessId, input);
      await loadBusiness(businessId);
      actions.message(hired.id);
      return hired;
    },
    /** Renames an employee or rewrites their responsibilities; false if the server refused. */
    setProfile: async (
      employee: Employee,
      change: { name?: string; responsibilities?: string },
    ) => {
      setEmployees((items) =>
        items.map((e) =>
          e.id === employee.id
            ? {
                ...e,
                ...(change.name ? { name: change.name } : {}),
                ...(change.responsibilities ? { role: change.responsibilities } : {}),
              }
            : e,
        ),
      );
      try {
        await api.setProfile(businessId, employee.id, change);
        return true;
      } catch (error) {
        failed(error);
        setEmployees((items) => items.map((e) => (e.id === employee.id ? employee : e)));
        return false;
      } finally {
        void loadBusiness(businessId);
      }
    },
    /** Retires an employee; their open work moves to the successor, whose page opens. */
    retire: async (employee: Employee, successor: string) => {
      try {
        await api.retire(businessId, employee.id, successor);
      } catch (error) {
        failed(error);
        setNotice(
          error instanceof ApiError && error.status === 409
            ? "The Head of Operations can't be retired."
            : `${employee.name} couldn't be retired.`,
        );
        return false;
      }
      await Promise.all([loadBusiness(businessId), loadWork(businessId)]);
      actions.message(successor);
      return true;
    },
    /** Shows the new model at once and puts the old one back if the server refuses. */
    setEmployeeModel: async (employee: Employee, model: string) => {
      const set = (value: string) =>
        setEmployees((items) =>
          items.map((e) => (e.id === employee.id ? { ...e, model: value } : e)),
        );
      set(model);
      try {
        await api.setEmployeeModel(businessId, employee.id, model);
        return true;
      } catch (error) {
        failed(error);
        set(employee.model);
        return false;
      }
    },
    /** Looks live on the server, so every client shows the same one. */
    setEmployeeLook: (employeeId: string, look: SettableLook) => {
      setEmployees((items) => items.map((e) => (e.id === employeeId ? { ...e, look } : e)));
      void refreshAfter(
        () => api.setEmployeeLook(businessId, employeeId, look),
        "That look couldn't be saved.",
      );
    },
    setBusinessLook: async (id: string, look: SettableLook) => {
      setBusinesses((items) => items.map((b) => (b.id === id ? { ...b, look } : b)));
      await api.setBusinessLook(id, look).catch(() => setNotice("That look couldn't be saved."));
      await loadAccount();
    },
    /** Renames a business or rewrites its brief. */
    updateBusiness: async (id: string, change: { name?: string; brief?: string }) => {
      await api.updateBusiness(id, change);
      await loadAccount();
    },
    uploadLookPhoto: async (target: { businessId: string; employeeId?: string }, file: Blob) => {
      const path = target.employeeId
        ? api.employeePath(target.businessId, target.employeeId)
        : api.businessPath(target.businessId);
      try {
        await api.uploadLookPhoto(path, await downscale(file, 512));
      } catch {
        setNotice("That photo couldn't be used. Try a JPEG or PNG.");
      }
      await Promise.all([loadAccount(), loadBusiness(businessId)]);
    },
    uploadOwnerPhoto: async (file: Blob) => {
      await api.uploadProfilePhoto(await downscale(file, 1024));
      await loadOwnerPhoto();
    },
    removeOwnerPhoto: async () => {
      await api.removeProfilePhoto();
      await loadOwnerPhoto();
    },
    refresh: () => {
      void loadAccount();
      void loadBusiness(businessId);
      void loadWork(businessId);
      void loadSummaries(businessId);
      void loadApps(businessId);
      for (const id of teamRef.current) void loadStatus(businessId, id);
      main.refresh();
    },
    /** Creates a business with its brief and starting team, then switches to it. */
    createBusiness: async (input: { name: string; brief: string; team: StartingRole[] }) => {
      const created = await api.createBusiness({
        name: input.name.trim(),
        brief: input.brief.trim(),
        team: input.team,
      });
      await loadAccount();
      setBusinessId(created.business.id);
      setPlace({ kind: "home" });
      setHistory([]);
    },
    signIn: async (token: string) => {
      await api.enroll(token);
      setSignedOut(false);
      await loadAccount();
    },
    signOut: async () => {
      await api.logout();
      setSignedOut(true);
      setPerson(undefined);
      setBusinesses([]);
      setBusinessId("");
    },
  };

  const status = statusOf(operations?.id);
  const isRunning = runningOf(operations?.id);
  const homeValue = valueOf(home);
  /** Whether the place's permanent view has anything: an empty one is never shown. */
  const hasPermanent =
    place.kind !== "home" ||
    Boolean(
      homeValue &&
      (homeValue.needsYou.length ||
        homeValue.glance.moving.length ||
        homeValue.glance.stuck.length),
    );
  const panelOpen = layers.length > 0 || (hasPermanent && (narrow ? overlay : panels[place.kind]));
  return {
    person,
    businesses,
    business,
    businessId,
    employees,
    members,
    operations,
    artifacts,
    status,
    statuses,
    summaries,
    main,
    work,
    decisions,
    projects,
    apps,
    home,
    memory,
    models,
    roles,
    access,
    artifactTexts,
    place,
    history,
    layers,
    panelOpen,
    hasPermanent,
    wide: wide && layers.length > 0,
    reference,
    turns,
    sidebarVisible,
    paletteOpen,
    settingsOpen,
    settingsSection,
    hireOpen,
    projectOpen,
    taskDefaults,
    notice,
    signedOut,
    ownerPhoto,
    voice,
    conversationMode,
    volatileText,
    level,
    voiceError,
    isRunning,
    statusOf,
    runningOf,
    /** Whether an employee is working or about to answer something sent from here. */
    workingOf: (employeeId: string) =>
      runningOf(employeeId) ||
      main.working.includes(employeeId) ||
      unfinished(valueOf(statusOf(employeeId))),
    unreadOf: (key: ConversationKey) => summaries[key]?.unread ?? 0,
    /** Work items the signed-in person follows, by id. */
    followed: Object.values(summaries)
      .filter((summary) => summary.following && summary.key.startsWith("work:"))
      .map((summary) => summary.key.slice("work:".length)),
    modelOf: (id: string) => valueOf(models)?.models.find((m) => m.id === id),
    employeeName: (id: string) => employees.find((e) => e.id === id)?.name ?? "A former employee",
    artifactName,
    actions,
  };
}

export type WorkspaceState = ReturnType<typeof useWorkspaceState>;
const Context = createContext<WorkspaceState | undefined>(undefined);

export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const state = useWorkspaceState();
  return <Context.Provider value={useMemo(() => state, [state])}>{children}</Context.Provider>;
}

export function useWorkspace() {
  const state = useContext(Context);
  if (!state) throw new Error("useWorkspace needs a WorkspaceProvider");
  return state;
}
