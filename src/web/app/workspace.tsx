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
  type Space,
  type SpaceItem,
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

/** Rail destinations; each has its own sidebar, as on native. */
export type Destination = "home" | "inbox" | "work" | "team" | "money" | "apps";
export type WorkFilter = "all" | "needsYou" | "inProgress" | "waiting" | "done";
export type Page =
  | { kind: "today" }
  | { kind: "approvals" }
  | { kind: "files"; path?: string }
  | { kind: "direct"; employeeId: string }
  | { kind: "space"; id: string }
  | { kind: "employee"; id?: string }
  | { kind: "inbox" }
  | { kind: "work"; filter: WorkFilter }
  | { kind: "money" }
  | { kind: "apps"; section: "installed" | "connections" };
export type EmployeeTab = "activity" | "responsibilities" | "memory" | "access";
export type SpaceTab = "conversation" | "overview" | "work" | "files";

/** The conversation a page shows in the main pane: a DM or a space's. */
export const conversationOf = (page: Page): ConversationKey | undefined =>
  page.kind === "direct"
    ? `direct:${page.employeeId}`
    : page.kind === "space"
      ? `space:${page.id}`
      : undefined;

export const destinationOf = (page: Page): Destination =>
  page.kind === "today" ||
  page.kind === "approvals" ||
  page.kind === "files" ||
  page.kind === "space" ||
  page.kind === "direct"
    ? "home"
    : page.kind === "employee"
      ? "team"
      : page.kind === "inbox"
        ? "inbox"
        : page.kind === "work"
          ? "work"
          : page.kind === "money"
            ? "money"
            : "apps";

/** Whether a destination's sidebar lists the page, so opening it keeps the owner there. */
const lists = (destination: Destination, page: Page) =>
  (destination === "home" && ["today", "approvals", "space", "direct"].includes(page.kind)) ||
  destinationOf(page) === destination;

export const filterOf = (state: CommitmentState): WorkFilter =>
  state === "needs_decision"
    ? "needsYou"
    : state === "waiting"
      ? "waiting"
      : state === "completed" || state === "cancelled"
        ? "done"
        : "inProgress";

/** Opening "New task" from a space or an employee fills in what it can. */
export interface TaskDefaults {
  owner?: string;
  spaceId?: string;
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
  const [spaces, setSpaces] = useState<Loadable<Space[]>>(loading);
  const [memory, setMemory] = useState<Loadable<MemoryClaim[]>>(loading);
  const [models, setModels] = useState<Loadable<ModelCatalog>>(loading);
  const [roles, setRoles] = useState<Loadable<RoleTemplate[]>>(loading);
  const [access, setAccess] = useState<{ employeeId: string; list: Loadable<AccessList> }>();
  const [artifactTexts, setArtifactTexts] = useState<Record<string, Loadable<string>>>({});
  const [page, setPage] = useState<Page>({ kind: "today" });
  const [destination, setDestination] = useState<Destination>("home");
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [inspectorVisible, setInspectorVisible] = useState(true);
  const [expanded, setExpanded] = useState(false);
  /** The work item open in the right panel, with its own thread. */
  const [selectedWork, setSelectedWork] = useState<string>();
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [hireOpen, setHireOpen] = useState(false);
  const [taskDefaults, setTaskDefaults] = useState<TaskDefaults>();
  const [employeeTab, setEmployeeTab] = useState<EmployeeTab>("activity");
  const [spaceTab, setSpaceTab] = useState<SpaceTab>("conversation");
  const [workLayout, setWorkLayout] = useState<"list" | "board">("list");
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
  /** Which composer voice serves: the main pane's conversation or the work panel's. */
  const [voiceTarget, setVoiceTarget] = useState<"main" | "panel">("main");
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
        const [w, d, s] = await Promise.all([api.work(id), api.decisions(id), api.spaces(id)]);
        if (current.current !== id) return;
        setWork(loaded(w.commitments));
        setDecisions(loaded(d.decisions));
        setSpaces(loaded(s.spaces));
      } catch (error) {
        failed(error);
      }
    },
    [failed],
  );

  /** Last messages and unread counts for the sidebar's DMs and spaces. */
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
    setSpaces(loading);
    setMemory(loading);
    setAccess(undefined);
    setArtifactTexts({});
    setSelectedWork(undefined);
    if (!businessId) return;
    void loadBusiness(businessId);
    void loadWork(businessId);
    void loadSummaries(businessId);
    api
      .memory(businessId)
      .then((m) => current.current === businessId && setMemory(loaded(m.items)))
      .catch(() => setMemory({ status: "failed", message: "Memory is unavailable." }));
  }, [businessId, loadBusiness, loadWork, loadSummaries]);

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
  const mainKey = conversationOf(page);
  const conversationDeps = {
    businessId,
    employees,
    running: runningOf,
    loadStatus: (employeeId: string) => loadStatus(businessId, employeeId),
    failed,
    read: (key: ConversationKey) =>
      setSummaries((all) => (all[key] ? { ...all, [key]: { ...all[key]!, unread: 0 } } : all)),
    answered,
  };
  const main = useConversation(mainKey, {
    ...conversationDeps,
    visible: page.kind === "direct" || (page.kind === "space" && spaceTab === "conversation"),
  });
  const panel = useConversation(selectedWork ? `work:${selectedWork}` : undefined, {
    ...conversationDeps,
    visible: inspectorVisible,
  });
  const target = voiceTarget === "panel" && panel.key ? panel : main;
  const targetRef = useRef(target);
  targetRef.current = target;
  /** Voice serves the composer it was started from. */
  const serve = (which: "main" | "panel") => {
    setVoiceTarget(which);
    targetRef.current = which === "panel" ? panel : main;
  };

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

  /** Sends in the conversation voice serves; replies are read aloud when asked for. */
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
  const answering = (employeeId: string) =>
    main.working.includes(employeeId) || panel.working.includes(employeeId);
  const actions = {
    selectBusiness: (id: string) => {
      if (id === businessId) return;
      setBusinessId(id);
      setPage({ kind: "today" });
      setDestination("home");
    },
    selectDestination: (next: Destination) => {
      if (next === destination) return;
      setDestination(next);
      setPage(
        next === "home"
          ? { kind: "today" }
          : next === "inbox"
            ? { kind: "inbox" }
            : next === "work"
              ? { kind: "work", filter: "all" }
              : next === "team"
                ? { kind: "employee", id: operations?.id }
                : next === "money"
                  ? { kind: "money" }
                  : { kind: "apps", section: "installed" },
      );
    },
    selectPage: (next: Page) => {
      setExpanded(false);
      // A space opens on its conversation.
      if (next.kind === "space" && !(page.kind === "space" && page.id === next.id))
        setSpaceTab("conversation");
      if (!lists(destination, next)) setDestination(destinationOf(next));
      setPage(next);
    },
    /** Opens the DM with an employee in the main pane. */
    message: (employeeId: string) => actions.selectPage({ kind: "direct", employeeId }),
    /** Opens a work item, with its thread, in the right panel. */
    openWork: (id: string) => {
      setSelectedWork(id);
      setInspectorVisible(true);
    },
    closeWork: () => {
      setSelectedWork(undefined);
      setExpanded(false);
    },
    toggleSidebar: () => setSidebarVisible((v) => !v),
    toggleInspector: () => (expanded ? setExpanded(false) : setInspectorVisible((v) => !v)),
    /** The work item's thread over the page, or back beside it. */
    toggleExpanded: () => {
      setExpanded((v) => !v);
      setInspectorVisible(true);
    },
    setPaletteOpen,
    setSettingsOpen,
    setHireOpen,
    newTask: (defaults: TaskDefaults = {}) => setTaskDefaults(defaults),
    closeNewTask: () => setTaskDefaults(undefined),
    setEmployeeTab,
    setSpaceTab,
    setWorkLayout,
    dismissNotice: () => setNotice(undefined),
    stop: (employeeId = operations?.id) =>
      employeeId &&
      void api
        .stop(businessId, employeeId)
        .then(() => setNotice("Stop requested. Work already sent cannot be unsent."))
        .then(() => loadStatus(businessId, employeeId)),
    /** Sends the draft of the conversation voice serves, marking it dictated if it was. */
    sendDraft: (conversation: typeof main) => {
      if (!conversation.draft.trim()) return;
      if (modeOf(voice) === "dictation") {
        capture.current?.cancel();
        capture.current = undefined;
        setVoice({ kind: "idle" });
      }
      const dictated = draftUsedVoice.current && conversation.key === targetRef.current.key;
      conversation.send(conversation.draft, {
        viaVoice: dictated,
        speak: loadVoiceSettings().speaksReplies,
      });
      draftUsedVoice.current = false;
      conversation.setDraft("");
    },
    /** The mic of the main pane's composer or the work panel's; voice then serves that one. */
    micTapped: (which: "main" | "panel") => {
      if (voice.kind === "idle") {
        serve(which);
        beginCapture("dictation");
      } else if (modeOf(voice) === "dictation" && voice.kind !== "finishing") {
        setVoice({ kind: "finishing", mode: "dictation" });
        capture.current?.finish();
      }
    },
    conversationToggled: (which: "main" | "panel") => {
      if (conversationRef.current) return endConversation();
      serve(which);
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
    /** A task with an owner, objective, due date and space; resolves once it is saved. */
    createTask: async (task: NewTask) => {
      await api.createCommitment(businessId, task);
      await loadWork(businessId);
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
    createSpace: async (space: { name: string; purpose?: string; lead?: string }) => {
      const name = space.name.trim().slice(0, 80);
      if (!name) return;
      try {
        const created = await api.createSpace(businessId, {
          name,
          ...(space.purpose?.trim() ? { purpose: space.purpose.trim().slice(0, 500) } : {}),
          ...(space.lead ? { lead: space.lead } : {}),
        });
        await loadWork(businessId);
        actions.selectPage({ kind: "space", id: created.id });
      } catch (error) {
        failed(error);
        setNotice("The space couldn't be created.");
      }
    },
    updateSpace: (id: string, change: { name?: string; purpose?: string; lead?: string }) =>
      refreshAfter(() => api.updateSpace(businessId, id, change), "The space couldn't be saved."),
    addToSpace: (spaceId: string, kind: SpaceItem["kind"], ref: string) =>
      void refreshAfter(
        () => api.addToSpace(businessId, spaceId, kind, ref),
        "That couldn't be added to the space.",
      ),
    removeFromSpace: (spaceId: string, itemId: string) =>
      void refreshAfter(
        () => api.removeFromSpace(businessId, spaceId, itemId),
        "That couldn't be removed.",
      ),
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
      actions.selectPage({ kind: "employee", id: hired.id });
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
      actions.selectPage({ kind: "employee", id: successor });
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
      for (const id of teamRef.current) void loadStatus(businessId, id);
      main.refresh();
      panel.refresh();
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
      setPage({ kind: "today" });
      setDestination("home");
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
    panel,
    selectedWork,
    work,
    decisions,
    spaces,
    memory,
    models,
    roles,
    access,
    artifactTexts,
    page,
    destination,
    sidebarVisible,
    inspectorVisible,
    expanded,
    paletteOpen,
    settingsOpen,
    hireOpen,
    taskDefaults,
    employeeTab,
    spaceTab,
    workLayout,
    notice,
    signedOut,
    ownerPhoto,
    voice,
    voiceTarget: target.key,
    conversationMode,
    volatileText,
    level,
    voiceError,
    isRunning,
    statusOf,
    runningOf,
    /** Whether an employee is working or about to answer something sent from here. */
    workingOf: (employeeId: string) =>
      runningOf(employeeId) || answering(employeeId) || unfinished(valueOf(statusOf(employeeId))),
    unreadOf: (key: ConversationKey) => summaries[key]?.unread ?? 0,
    modelOf: (id: string) => valueOf(models)?.models.find((m) => m.id === id),
    employeeName: (id: string) => employees.find((e) => e.id === id)?.name ?? "A former employee",
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
