import { cn } from "@/lib/utils";
import { Code2, Hand, MessageSquarePlus, Send, Square, SquareTerminal, Undo2 } from "lucide-react";
import { useEffect, useState } from "react";
import {
  api,
  ApiError,
  type CodingSession,
  type Commitment,
  type WorkingDiff,
  type TranscriptEntry,
} from "../app/api.ts";
import { useWorkspace } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { MarkdownView } from "../design/markdown.tsx";
import { StatusChip } from "../design/primitives.tsx";
import { Textarea } from "@/components/ui/textarea";
import {
  DiffSurface,
  hunkHash,
  hunkText,
  reviewBundle,
  type DiffComment,
  type DiffSelection,
} from "../../surfaces/diff.tsx";
import { takeoverTitle } from "../app/names.ts";
import { useDark } from "../app/theme.ts";
import { providerName, stateChip } from "./coding.tsx";
import { openTerminalWindow } from "./terminal-window.tsx";

/**
 * One coding session: its latest reply, the running diff with line comments, and a composer
 * that talks to the session directly once the owner has taken the work item over. Comments are
 * always sendable: with the owner's message while they drive, otherwise as one message in the
 * work item's thread for its employee.
 */
export default function SessionView({
  item,
  session,
  onChanged,
}: {
  item: Commitment;
  session: CodingSession;
  onChanged: () => void;
}) {
  const { businessId, person, members, actions, main, employeeName } = useWorkspace();
  const dark = useDark();
  const [diff, setDiff] = useState<WorkingDiff | null>(null);
  const [selection, setSelection] = useState<DiffSelection | null>(null);
  const [draftComment, setDraftComment] = useState("");
  const [comments, setComments] = useState<DiffComment[]>([]);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const mine = item.taken_over_by !== null && item.taken_over_by === person?.id;
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const chip = stateChip[session.state];

  useEffect(() => {
    let live = true;
    const load = () =>
      api
        .sessionDiff(businessId, item.id, session.id)
        .then((result) => live && setDiff(result))
        .catch(() => undefined);
    void load();
    const timer = setInterval(() => void load(), session.state === "working" ? 5_000 : 30_000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [businessId, item.id, session.id, session.state]);

  const addComment = async () => {
    if (!selection || !draftComment.trim() || !diff) return;
    const hunk = await hunkHash(hunkText(diff.patch, selection));
    setComments((items) => [
      ...items,
      {
        ...selection,
        hunk,
        ...(session.base_commit ? { base: session.base_commit } : {}),
        text: draftComment.trim(),
      },
    ]);
    setDraftComment("");
    setSelection(null);
  };
  const send = async () => {
    const message = [comments.length ? reviewBundle(item.title, comments) : "", text.trim()]
      .filter(Boolean)
      .join("\n");
    if (!message) return;
    try {
      await api.steerSession(businessId, item.id, session.id, message);
      setText("");
      setComments([]);
      setError(null);
      onChanged();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "That couldn't be sent.");
    }
  };
  /** Until the owner drives, comments go to the work item's employee in its thread. */
  const sendComments = async () => {
    if (!comments.length) return;
    try {
      await api.post(businessId, `work:${item.id}`, {
        id: crypto.randomUUID(),
        text: reviewBundle(item.title, comments),
        mentions: [item.owner_employee_id],
      });
      setComments([]);
      setError(null);
      if (main.key === `work:${item.id}`) main.refresh();
    } catch (cause) {
      // A 409 says everyone who would read them is paused.
      setError(
        cause instanceof ApiError && cause.status === 409
          ? `${employeeName(item.owner_employee_id)} is paused, so the comments weren't sent.`
          : "The comments couldn't be sent.",
      );
    }
  };
  const count = `${comments.length} comment${comments.length === 1 ? "" : "s"}`;

  return (
    <div className="@container flex h-full flex-col" data-testid="session-view">
      <div className="flex flex-wrap items-center gap-2 border-b border-hairline px-4 py-3">
        <Code2 className="size-4 text-ink-3" />
        <span className="text-body font-semibold text-ink">
          {providerName(session.provider)}
          {session.purpose === "review" ? " · review" : ""}
        </span>
        <StatusChip tone={chip.tone} small>
          {chip.title}
        </StatusChip>
        <span className="truncate text-caption text-ink-3" title={session.worktree ?? undefined}>
          {session.branch}
        </span>
        <span className="ml-auto" />
        <DevysButton
          compact
          onClick={() => void openTerminalWindow(businessId, { resume: session.id })}
        >
          <SquareTerminal /> Open in {providerName(session.provider)}
        </DevysButton>
        {session.state === "working" && (
          <DevysButton
            compact
            onClick={() => void api.stopSession(businessId, item.id, session.id).then(onChanged)}
          >
            <Square /> Stop
          </DevysButton>
        )}
        <DevysButton compact onClick={() => actions.toggleTakeover(item)}>
          {item.taken_over_by === null ? (
            <>
              <Hand /> Take over
            </>
          ) : (
            <>
              <Undo2 /> Hand back
            </>
          )}
        </DevysButton>
      </div>
      <div className="grid min-h-0 flex-1 grid-cols-1 @3xl:grid-cols-[minmax(260px,34%)_1fr]">
        <div className="flex min-h-0 flex-col gap-3 overflow-y-auto border-b border-hairline p-4 @3xl:border-r @3xl:border-b-0">
          <span className="text-label font-medium text-ink-3">Latest reply</span>
          {session.reply ? (
            <MarkdownView text={session.reply} />
          ) : (
            <span className="text-detail text-ink-3">
              {session.state === "working" ? "Working on its first turn…" : "No reply yet."}
            </span>
          )}
          {session.error && <span className="text-detail text-ink-2">{session.error}</span>}
          <span className="text-label font-medium text-ink-3">Objective</span>
          <p className="text-detail whitespace-pre-wrap text-ink-2">{session.objective}</p>
          <SessionSteps businessId={businessId} workId={item.id} session={session} />
        </div>
        <div className="h-full min-h-0 p-3">
          {diff === null ? (
            <span className="text-detail text-ink-3">Loading changes…</span>
          ) : (
            <DiffSurface
              patch={diff.patch}
              comments={comments}
              dark={dark}
              onSelect={setSelection}
            />
          )}
        </div>
      </div>
      <div className="flex flex-col gap-2 border-t border-hairline px-4 py-3">
        {selection && (
          <div className="flex items-center gap-2">
            <span className="shrink-0 text-caption text-ink-3">
              {selection.path}{" "}
              {selection.start === selection.end
                ? `line ${selection.start}`
                : `lines ${selection.start}–${selection.end}`}
            </span>
            <input
              autoFocus
              value={draftComment}
              onChange={(event) => setDraftComment(event.target.value)}
              onKeyDown={(event) => event.key === "Enter" && void addComment()}
              placeholder="Comment on these lines"
              aria-label="Comment on the selected lines"
              className="min-w-0 flex-1 rounded-[8px] bg-sheet-tint px-2.5 py-1.5 text-detail text-ink outline-none focus-visible:ring-2 focus-visible:ring-indigo/40"
            />
            <DevysButton compact onClick={() => void addComment()}>
              <MessageSquarePlus /> Add
            </DevysButton>
          </div>
        )}
        {comments.length > 0 &&
          (mine ? (
            <span className="text-caption text-ink-3">{count} will be sent with your message.</span>
          ) : (
            <div className="flex items-center gap-2">
              <span className="text-caption text-ink-3">
                {count} for {employeeName(item.owner_employee_id)}, in this work item's thread.
              </span>
              <DevysButton compact onClick={() => void sendComments()}>
                <Send /> Send {count}
              </DevysButton>
            </div>
          ))}
        {mine ? (
          <div className="flex items-end gap-2">
            <Textarea
              value={text}
              onChange={(event) => setText(event.target.value)}
              placeholder={`Tell ${providerName(session.provider)} what to do`}
              aria-label="Message to the coding session"
              className="min-h-[44px] flex-1"
            />
            <DevysButton onClick={() => void send()}>Send</DevysButton>
          </div>
        ) : (
          <span className="text-detail text-ink-3">
            {takeover
              ? `${takeover}; they steer this session.`
              : "Take over the work item to steer this session yourself; until then its employee steers it."}
          </span>
        )}
        {error && <span className="text-detail text-ink-2">{error}</span>}
      </div>
    </div>
  );
}

const stepLabel: Record<TranscriptEntry["kind"], string> = {
  prompt: "Told",
  reply: "Said",
  plan: "Plan",
  command: "Ran",
  files: "Edited",
  tool: "Used",
};

/**
 * What the session actually did, closed until asked for: read from the harness's own record
 * each time it opens (and while it works), never kept by Devys.
 */
function SessionSteps({
  businessId,
  workId,
  session,
}: {
  businessId: string;
  workId: string;
  session: CodingSession;
}) {
  const [open, setOpen] = useState(false);
  const [entries, setEntries] = useState<TranscriptEntry[] | null>(null);
  const [problem, setProblem] = useState<string>();
  useEffect(() => {
    if (!open) return;
    let live = true;
    const load = () =>
      api
        .sessionTranscript(businessId, workId, session.id)
        .then((result) => live && (setEntries(result.entries), setProblem(undefined)))
        .catch(
          (cause: unknown) =>
            live && setProblem(cause instanceof Error ? cause.message : "Unavailable"),
        );
    void load();
    const timer = session.state === "working" ? setInterval(() => void load(), 5_000) : undefined;
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [open, businessId, workId, session.id, session.state]);
  return (
    <div className="flex flex-col gap-1.5">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className="self-start text-label font-medium text-ink-3 hover:text-ink-2"
      >
        {open ? "Hide details" : "Details"}
      </button>
      {open &&
        (problem ? (
          <span className="text-detail text-ink-3">{problem}</span>
        ) : entries === null ? (
          <span className="text-detail text-ink-3">Loading…</span>
        ) : (
          <ol className="flex flex-col gap-1.5" data-testid="session-steps">
            {entries.map((entry, index) => (
              <li key={index} className="flex flex-col gap-0.5">
                <span className={cn("text-caption", entry.failed ? "text-red" : "text-ink-3")}>
                  {stepLabel[entry.kind]}
                </span>
                <span
                  className={cn(
                    "text-detail whitespace-pre-wrap text-ink-2",
                    (entry.kind === "command" || entry.kind === "files") &&
                      "font-mono text-caption",
                  )}
                >
                  {entry.text}
                </span>
                {entry.detail && (
                  <details className="text-caption text-ink-3">
                    <summary className="cursor-pointer">Output</summary>
                    <pre className="max-h-48 overflow-auto font-mono whitespace-pre-wrap">
                      {entry.detail}
                    </pre>
                  </details>
                )}
              </li>
            ))}
          </ol>
        ))}
    </div>
  );
}
