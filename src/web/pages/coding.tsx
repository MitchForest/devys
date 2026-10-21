import { Code2, SquareTerminal } from "lucide-react";
import { lazy, Suspense, useCallback, useEffect, useState } from "react";
import { api, type CodingSession, type Commitment, type TerminalSession } from "../app/api.ts";
import { openTerminalWindow } from "./terminal-window.tsx";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { StatusChip, type Tone } from "../design/primitives.tsx";

export const providerName = (provider: CodingSession["provider"]) =>
  provider === "codex" ? "Codex" : "Claude Code";

export const stateChip: Record<CodingSession["state"], { tone: Tone; title: string }> = {
  working: { tone: "inProgress", title: "Working" },
  idle: { tone: "done", title: "Turn finished" },
  interrupted: { tone: "waiting", title: "Interrupted" },
  failed: { tone: "failed", title: "Failed" },
  unavailable: { tone: "waiting", title: "Mac host unavailable" },
};

// The session view carries the diff renderer and its highlighter; load it when opened.
const SessionView = lazy(() => import("./session.tsx"));

/** The "3 files changed, …" line of a diff stat. */
const changeLine = (diffStat: string) =>
  diffStat
    .split("\n")
    .find((line) => /files? changed/.test(line))
    ?.trim() ?? (diffStat ? `${diffStat.split("\n").length} files changed` : "No changes yet");

/** Polls a work item's coding sessions while it is shown; the provider is the source. */
function useSessions(businessId: string, workId: string) {
  const [sessions, setSessions] = useState<CodingSession[]>([]);
  const load = useCallback(
    () =>
      api
        .codingSessions(businessId, workId)
        .then((result) => setSessions(result.sessions))
        .catch(() => undefined),
    [businessId, workId],
  );
  useEffect(() => {
    void load();
    const timer = setInterval(() => void load(), 5_000);
    return () => clearInterval(timer);
  }, [load]);
  return { sessions, reload: load };
}

/** The coding sessions on a work item, each opening its session view. */
export function CodingSessions({ item }: { item: Commitment }) {
  const { businessId, actions } = useWorkspace();
  const { sessions } = useSessions(businessId, item.id);
  if (!sessions.length) return null;
  return (
    <div className="flex flex-col gap-1" data-testid="coding-sessions">
      <div className="flex items-center gap-2">
        <span className="text-label font-medium text-ink-3">Coding · {sessions.length}</span>
        {sessions.some((session) => session.purpose === "build") && (
          <DevysButton
            kind="quiet"
            compact
            onClick={() => void openTerminalWindow(businessId, { work: item.id })}
          >
            <SquareTerminal /> Open terminal
          </DevysButton>
        )}
      </div>
      {sessions.map((session) => {
        const chip = stateChip[session.state];
        return (
          <button
            key={session.id}
            type="button"
            onClick={() =>
              actions.openLayer({ kind: "session", workId: item.id, sessionId: session.id })
            }
            className="flex items-center gap-2 rounded-[8px] px-2 py-1.5 text-left hover:bg-sheet-tint"
          >
            <Code2 className="size-4 shrink-0 text-ink-3" />
            <span className="flex min-w-0 flex-col">
              <span className="truncate text-detail font-medium text-ink">
                {providerName(session.provider)}
                {session.purpose === "review" ? " · review" : ""}
              </span>
              <span className="truncate text-caption text-ink-3">
                {session.branch} · {changeLine(session.diffStat)}
              </span>
            </span>
            <span className="ml-auto shrink-0">
              <StatusChip tone={chip.tone} small>
                {chip.title}
              </StatusChip>
            </span>
          </button>
        );
      })}
    </div>
  );
}

/** One coding session as a layer, read live from its work item's sessions. */
export function SessionLayer({ workId, sessionId }: { workId: string; sessionId: string }) {
  const { businessId, work } = useWorkspace();
  const { sessions, reload } = useSessions(businessId, workId);
  const item = valueOf(work)?.find((w) => w.id === workId);
  const session = sessions.find((each) => each.id === sessionId);
  if (!item || !session) return <p className="p-4 text-body text-ink-3">Loading…</p>;
  return (
    <Suspense fallback={null}>
      <SessionView item={item} session={session} onChanged={() => void reload()} />
    </Suspense>
  );
}

/**
 * "New coding session": the owner drives a session from the start. It becomes a work item
 * owned by the chosen employee but taken over by the owner; handing it back lets the employee
 * verify and ship.
 */
export function NewCodingSession({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { businessId, employees, actions } = useWorkspace();
  const engineering = employees.find((e) => e.template === "engineering") ?? employees[0];
  const [employee, setEmployee] = useState(engineering?.id ?? "");
  const [provider, setProvider] = useState<"codex" | "claude">("codex");
  const [where, setWhere] = useState<"existing" | "new">("existing");
  const [repository, setRepository] = useState("");
  const [objective, setObjective] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [clientId] = useState(() => crypto.randomUUID());
  const start = async () => {
    try {
      const started = await api.startCoding(businessId, {
        clientId,
        employee: employee || engineering?.id || "",
        provider,
        objective: objective.trim(),
        ...(where === "existing"
          ? { repository: repository.trim() }
          : { newRepository: repository.trim() }),
      });
      actions.refresh();
      actions.openThread(started.work);
      onClose();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The session couldn't start.");
    }
  };
  const field =
    "rounded-[8px] bg-sheet-tint px-2.5 py-1.5 text-body text-ink outline-none focus-visible:ring-2 focus-visible:ring-indigo/40";
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogTitle>New coding session</DialogTitle>
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Coding agent
            <select
              className={field}
              value={provider}
              onChange={(e) => setProvider(e.target.value as "codex" | "claude")}
            >
              <option value="codex">Codex</option>
              <option value="claude">Claude Code</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Repository
            <select
              className={field}
              value={where}
              onChange={(e) => setWhere(e.target.value as "existing" | "new")}
            >
              <option value="existing">An existing repository on the Mac</option>
              <option value="new">A new, empty repository</option>
            </select>
            <input
              className={field}
              aria-label={where === "existing" ? "Repository path" : "New repository name"}
              placeholder={where === "existing" ? "/Users/you/Code/project" : "my-app"}
              value={repository}
              onChange={(e) => setRepository(e.target.value)}
            />
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            What to build
            <Textarea
              value={objective}
              onChange={(e) => setObjective(e.target.value)}
              placeholder="Describe the change and how to check it"
            />
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Hand it to, when you hand back
            <select
              className={field}
              value={employee}
              onChange={(e) => setEmployee(e.target.value)}
            >
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.name}
                </option>
              ))}
            </select>
          </label>
          {error && <span className="text-detail text-ink-2">{error}</span>}
          <DevysButton
            disabled={!objective.trim() || !repository.trim()}
            onClick={() => void start()}
          >
            Start session
          </DevysButton>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** The business's open terminals, any of which a device can reopen; and a new one. */
export function Terminals() {
  const { businessId } = useWorkspace();
  const [terminals, setTerminals] = useState<TerminalSession[]>([]);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    const load = () =>
      api
        .terminals(businessId)
        .then((result) => setTerminals(result.terminals.filter((t) => !t.exit)))
        .catch(() => setTerminals([]));
    void load();
    const timer = setInterval(() => void load(), 10_000);
    return () => clearInterval(timer);
  }, [businessId]);
  return (
    <div className="flex flex-col gap-1.5" data-testid="terminals">
      <div className="flex items-center gap-2">
        {terminals.length > 0 && (
          <span className="text-label font-medium text-ink-3">Terminals · {terminals.length}</span>
        )}
        <DevysButton
          kind="quiet"
          compact
          onClick={() =>
            void openTerminalWindow(businessId, {}).catch((cause: unknown) =>
              setError(cause instanceof Error ? cause.message : "The terminal couldn't open."),
            )
          }
        >
          <SquareTerminal /> New terminal
        </DevysButton>
      </div>
      {error && <span className="text-detail text-ink-2">{error}</span>}
      {terminals.map((terminal) => (
        <a
          key={terminal.id}
          href={`/terminal/${businessId}/${terminal.id}`}
          target="_blank"
          rel="noopener"
          className="flex items-center gap-2 rounded-[8px] px-2 py-1.5 text-detail text-ink hover:bg-sheet-tint"
        >
          <SquareTerminal className="size-4 text-ink-3" />
          <span className="truncate">{terminal.title}</span>
          <span className="ml-auto truncate text-caption text-ink-3">{terminal.cwd}</span>
        </a>
      ))}
    </div>
  );
}
