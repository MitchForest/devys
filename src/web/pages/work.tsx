import {
  Check,
  ChevronDown,
  CircleCheck,
  CircleX,
  Clock,
  Code2,
  Hand,
  Pencil,
  Plus,
  Redo2,
  Undo2,
} from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { api, type Commitment, type Decision } from "../app/api.ts";
import {
  accessTitle,
  chipFor,
  filterTitle,
  isOpen,
  outcomeOf,
  takeoverTitle,
  templateTitle,
  workFilters,
} from "../app/names.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import { filterOf, useWorkspace, valueOf, type WorkFilter } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import {
  EmptyNote,
  PageBody,
  PageHeader,
  SectionHeader,
  StatusChip,
  Card,
} from "../design/primitives.tsx";
import { Field, fieldClass } from "../design/fields.tsx";
import { SegmentedTabs } from "../design/tabs.tsx";
import { endOfDay } from "../shell/dialogs.tsx";
import { CodingSessions, NewCodingSession, Terminals } from "./coding.tsx";
import { Spinner } from "../design/spinner.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuSub,
  ContextMenuSubContent,
  ContextMenuSubTrigger,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";

/** The same actions an employee has, applied by the owner at the revision on screen. */
export function WorkActions({ item, extra }: { item: Commitment; extra?: ReactNode }) {
  const { actions, spaces } = useWorkspace();
  const list = valueOf(spaces) ?? [];
  if (!isOpen(item.state))
    return (
      <>
        <ContextMenuItem onClick={() => actions.setCommitmentState(item, "ready")}>
          <Undo2 /> Reopen
        </ContextMenuItem>
        {extra}
      </>
    );
  return (
    <>
      {item.state !== "ready" && (
        <ContextMenuItem onClick={() => actions.setCommitmentState(item, "ready")}>
          <Redo2 /> Mark ready
        </ContextMenuItem>
      )}
      {item.state !== "waiting" && (
        <ContextMenuItem onClick={() => actions.setCommitmentState(item, "waiting")}>
          <Clock /> Mark waiting
        </ContextMenuItem>
      )}
      <ContextMenuItem onClick={() => actions.setCommitmentState(item, "completed")}>
        <CircleCheck /> Mark done
      </ContextMenuItem>
      <ContextMenuSeparator />
      <ContextMenuItem onClick={() => actions.toggleTakeover(item)}>
        {item.taken_over_by === null ? (
          <>
            <Hand /> Take over
          </>
        ) : (
          <>
            <Undo2 /> Hand back
          </>
        )}
      </ContextMenuItem>
      <ContextMenuItem
        variant="destructive"
        onClick={() => actions.setCommitmentState(item, "cancelled")}
      >
        <CircleX /> Cancel
      </ContextMenuItem>
      {list.length > 0 && (
        <ContextMenuSub>
          <ContextMenuSubTrigger>Add to space</ContextMenuSubTrigger>
          <ContextMenuSubContent>
            {list.map((space) => (
              <ContextMenuItem
                key={space.id}
                onClick={() => actions.addToSpace(space.id, "commitment", item.id)}
              >
                {space.name}
              </ContextMenuItem>
            ))}
          </ContextMenuSubContent>
        </ContextMenuSub>
      )}
      {extra}
    </>
  );
}

/** Right-click (or long-press) a commitment to act on it. */
export function WithWorkActions({
  item,
  extra,
  children,
}: {
  item: Commitment;
  extra?: ReactNode;
  children: ReactNode;
}) {
  return (
    <ContextMenu>
      <ContextMenuTrigger render={<div />} className="select-auto">
        {children}
      </ContextMenuTrigger>
      <ContextMenuContent>
        <WorkActions item={item} extra={extra} />
      </ContextMenuContent>
    </ContextMenu>
  );
}

/** One commitment: what, who, what's next and its state. Click to open it. */
export function WorkRow({ item, extra }: { item: Commitment; extra?: ReactNode }) {
  const { employeeName, actions, person, members } = useWorkspace();
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const owner = employeeName(item.owner_employee_id);
  const done = item.evidence[item.evidence.length - 1];
  const detail =
    item.wait_condition && item.state === "waiting"
      ? `${owner} · waiting on ${item.wait_condition}`
      : done && item.state === "completed"
        ? `${owner} · ${done.note}`
        : item.next_action
          ? `${owner} · ${item.next_action}`
          : owner;
  const chip = chipFor(item.state);
  return (
    <WithWorkActions item={item} extra={extra}>
      <button
        type="button"
        onClick={() => actions.openWork(item.id)}
        className="flex w-full items-center gap-3 rounded-[12px] px-3 py-2.5 text-left transition-colors duration-150 hover:bg-sheet-tint"
      >
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="text-body font-semibold text-ink">{item.title}</span>
          <span className="line-clamp-2 text-detail text-ink-2">{detail}</span>
        </div>
        <span className="ml-auto" />
        {takeover && isOpen(item.state) && (
          <span className="shrink-0 text-caption text-ink-3">{takeover}</span>
        )}
        <StatusChip tone={chip.tone}>{chip.title}</StatusChip>
      </button>
    </WithWorkActions>
  );
}

/** Pretty-prints a decision's exact input as key/value rows. */
function fields(input: unknown): [string, string][] {
  if (input && typeof input === "object" && !Array.isArray(input))
    return Object.entries(input).map(([key, value]) => [
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    ]);
  return [["input", JSON.stringify(input)]];
}

/** What a decision asks for, in words: a proposed hire names the person and role. */
export function decisionTitle(decision: Decision) {
  if (
    decision.capability === "hireEmployee" &&
    decision.input &&
    typeof decision.input === "object"
  ) {
    const input = decision.input as { name?: unknown; template?: unknown };
    const template = typeof input.template === "string" ? templateTitle(input.template) : "";
    const name = typeof input.name === "string" && input.name ? input.name : template;
    return template && template !== name ? `Hire ${name} · ${template}` : `Hire ${name}`;
  }
  return accessTitle(decision.capability);
}

/** One exact request: who asked, what they will do, and the input it will run with. */
export function DecisionCard({ decision }: { decision: Decision }) {
  const { actions, employeeName } = useWorkspace();
  return (
    <Card>
      <div className="flex flex-col items-start gap-2.5">
        <StatusChip tone="needsYou">Needs approval</StatusChip>
        <span className="text-heading font-semibold text-ink">{decisionTitle(decision)}</span>
        <span className="text-detail text-ink-2">
          {employeeName(decision.employee_id)} asked to run this exactly:
        </span>
        <div className="flex w-full flex-col gap-1 rounded-control bg-well p-2.5">
          {fields(decision.input).map(([key, value]) => (
            <div key={key} className="flex items-baseline gap-2">
              <span className="min-w-16 text-caption text-ink-3">{key}</span>
              <span className="line-clamp-6 min-w-0 text-body break-words text-ink select-text">
                {value}
              </span>
            </div>
          ))}
        </div>
        <div className="flex gap-2 pt-0.5">
          <DevysButton
            kind="aurora"
            onClick={() => actions.answer(decision.id, true)}
            title="Allows this exact request once. Face ID signing arrives with signed decisions."
          >
            <Check /> Approve once
          </DevysButton>
          <DevysButton onClick={() => actions.answer(decision.id, false)}>Reject</DevysButton>
        </div>
      </div>
    </Card>
  );
}

export function ApprovalsPage() {
  const { decisions } = useWorkspace();
  const list = valueOf(decisions) ?? [];
  return (
    <PageBody>
      <PageHeader title="Approvals" />
      {decisions.status === "loading" ? (
        <Spinner />
      ) : list.length === 0 ? (
        <EmptyNote>
          Nothing needs your approval. Requests appear here when an employee's access asks first.
        </EmptyNote>
      ) : (
        <div className="flex flex-col gap-3">
          <SectionHeader title="Waiting on you" count={list.length} />
          {list.map((d) => (
            <DecisionCard key={d.id} decision={d} />
          ))}
        </div>
      )}
    </PageBody>
  );
}

export function WorkPage({ filter }: { filter: WorkFilter }) {
  const { work, workLayout, actions, employeeName } = useWorkspace();
  const [coding, setCoding] = useState(false);
  const all = valueOf(work) ?? [];
  const items = filter === "all" ? all : all.filter((item) => filterOf(item.state) === filter);
  const columns = workFilters.filter(
    (c) => c.value !== "all" && items.some((item) => filterOf(item.state) === c.value),
  );
  return (
    <PageBody>
      <PageHeader title={filter === "all" ? "Work" : filterTitle(filter)}>
        <div className="flex items-center gap-2">
          <DevysButton compact onClick={() => actions.newTask()}>
            <Plus /> New task
          </DevysButton>
          <DevysButton compact onClick={() => setCoding(true)}>
            <Code2 /> New coding session
          </DevysButton>
          <SegmentedTabs
            label="Layout"
            value={workLayout}
            options={[
              { value: "list", title: "List" },
              { value: "board", title: "Board" },
            ]}
            onChange={actions.setWorkLayout}
          />
        </div>
      </PageHeader>
      <Terminals />
      <NewCodingSession open={coding} onClose={() => setCoding(false)} />
      {work.status === "loading" ? (
        <Spinner />
      ) : items.length === 0 ? (
        <EmptyNote>
          {filter === "all"
            ? "Nothing is owed yet. Create a task, or ask Operations to take something on."
            : "Nothing here."}
        </EmptyNote>
      ) : workLayout === "list" ? (
        <div className="flex flex-col gap-2">
          <SectionHeader title="Commitments" count={items.length} />
          {items.map((item) => (
            <WorkRow key={item.id} item={item} />
          ))}
        </div>
      ) : (
        <div className="flex items-start gap-3 overflow-x-auto">
          {columns.map((column) => {
            const cards = items.filter((item) => filterOf(item.state) === column.value);
            return (
              <div key={column.value} className="flex min-w-[150px] flex-1 flex-col gap-2">
                <SectionHeader title={column.title} count={cards.length} />
                {cards.map((item) => (
                  <WithWorkActions key={item.id} item={item}>
                    <button
                      type="button"
                      className="w-full text-left"
                      onClick={() => actions.openWork(item.id)}
                    >
                      <Card padding={12}>
                        <div className="flex flex-col gap-1.5">
                          <span className="text-body font-semibold text-ink">{item.title}</span>
                          {item.next_action && (
                            <span className="text-detail text-ink-2">{item.next_action}</span>
                          )}
                          <span className="text-detail text-ink-3">
                            {employeeName(item.owner_employee_id)}
                          </span>
                        </div>
                      </Card>
                    </button>
                  </WithWorkActions>
                ))}
              </div>
            );
          })}
        </div>
      )}
    </PageBody>
  );
}

const formatDue = (due: string) =>
  new Date(due).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
/** A due time as the date field shows it, in the owner's time zone. */
const dateField = (due: string | null) => {
  if (!due) return "";
  const date = new Date(due);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
};

/**
 * What's next, what it waits on and when it's due, edited as one change at the revision on
 * screen. If someone changed the item meanwhile, the latest loads and the draft stays to save again.
 */
function WorkPlan({ item, editable }: { item: Commitment; editable: boolean }) {
  const { actions } = useWorkspace();
  const [editing, setEditing] = useState(false);
  const [next, setNext] = useState("");
  const [waiting, setWaiting] = useState("");
  const [due, setDue] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const edit = () => {
    setNext(item.next_action);
    setWaiting(item.wait_condition ?? "");
    setDue(dateField(item.due_at));
    setError(undefined);
    setEditing(true);
  };
  const save = async () => {
    const change = {
      ...(next.trim() !== item.next_action ? { nextAction: next.trim() } : {}),
      ...(waiting.trim() !== (item.wait_condition ?? "")
        ? { waitCondition: waiting.trim() || null }
        : {}),
      ...(due !== dateField(item.due_at) ? { dueAt: due ? endOfDay(due) : null } : {}),
    };
    if (Object.keys(change).length === 0) return setEditing(false);
    setBusy(true);
    const saved = await actions.editCommitment(item, change);
    setBusy(false);
    if (saved) setEditing(false);
    else
      setError(
        "That wasn't saved. If it changed meanwhile, the latest is shown; save again to apply.",
      );
  };
  if (!editing)
    return (
      <div className="flex items-start gap-2">
        <dl className="grid flex-1 grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-detail">
          <dt className="text-ink-3">Next</dt>
          <dd className="text-ink">{item.next_action || "Not set"}</dd>
          {item.wait_condition && (
            <>
              <dt className="text-ink-3">Waiting on</dt>
              <dd className="text-ink">{item.wait_condition}</dd>
            </>
          )}
          <dt className="text-ink-3">Due</dt>
          <dd className="text-ink">{item.due_at ? formatDue(item.due_at) : "No due date"}</dd>
        </dl>
        {editable && (
          <DevysButton
            kind="quiet"
            compact
            onClick={edit}
            aria-label="Edit next, waiting on and due"
          >
            <Pencil /> Edit
          </DevysButton>
        )}
      </div>
    );
  return (
    <form
      aria-label="Edit work plan"
      className="flex flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        void save();
      }}
      onKeyDown={(event) => event.key === "Escape" && setEditing(false)}
    >
      <Field label="Next">
        <input
          autoFocus
          className={fieldClass}
          value={next}
          maxLength={1000}
          onChange={(event) => setNext(event.target.value)}
        />
      </Field>
      <Field label="Waiting on">
        <input
          className={fieldClass}
          value={waiting}
          maxLength={1000}
          placeholder="Nothing"
          onChange={(event) => setWaiting(event.target.value)}
        />
      </Field>
      <Field label="Due">
        <input
          type="date"
          className={fieldClass}
          value={due}
          onChange={(event) => setDue(event.target.value)}
        />
      </Field>
      {error && (
        <p role="alert" className="text-detail text-ink-2">
          {error}
        </p>
      )}
      <div className="flex gap-1.5">
        <DevysButton compact type="submit" disabled={busy}>
          {busy ? "Saving…" : "Save"}
        </DevysButton>
        <DevysButton kind="quiet" compact onClick={() => setEditing(false)}>
          Cancel
        </DevysButton>
      </div>
    </form>
  );
}

/** A work item's answered requests, reloaded when the item changes. */
function useAnswered(item: Commitment) {
  const { businessId } = useWorkspace();
  const [answered, setAnswered] = useState<Decision[]>([]);
  useEffect(() => {
    let live = true;
    api
      .workDecisions(businessId, item.id)
      .then((result) => live && setAnswered(result.decisions.filter((d) => d.status !== "pending")))
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [businessId, item.id, item.revision]);
  return answered;
}

/**
 * One work item, as the right panel shows it above its thread: who owns it, where it
 * stands, what's next, its evidence and decisions, with takeover and reassignment.
 */
export function WorkDetail({ item }: { item: Commitment }) {
  const { employees, actions, employeeName, spaces, person, members, decisions } = useWorkspace();
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const waiting = (valueOf(decisions) ?? []).filter((d) => d.commitment_id === item.id);
  const answered = useAnswered(item);
  const owner = employees.find((e) => e.id === item.owner_employee_id);
  const chip = chipFor(item.state);
  const inSpaces = (valueOf(spaces) ?? []).filter((s) =>
    s.items.some((i) => i.kind === "commitment" && i.ref === item.id),
  );
  const open = isOpen(item.state);
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusChip tone={chip.tone} small>
          {chip.title}
        </StatusChip>
        {takeover && <span className="text-caption text-ink-3">{takeover}</span>}
        {inSpaces.map((space) => (
          <button
            key={space.id}
            type="button"
            onClick={() => actions.selectPage({ kind: "space", id: space.id })}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            in {space.name}
          </button>
        ))}
      </div>
      {item.objective && <p className="text-body text-ink-2">{item.objective}</p>}
      <div className="flex flex-col gap-2.5 rounded-card bg-sheet-tint px-3 py-2.5">
        <div className="flex items-center gap-2.5">
          {owner && <EmployeePortrait employee={owner} size={26} />}
          <div className="flex min-w-0 flex-col">
            <span className="text-caption text-ink-3">Owner</span>
            <span className="truncate text-body font-semibold text-ink" data-testid="task-owner">
              {employeeName(item.owner_employee_id)}
            </span>
          </div>
          <span className="ml-auto" />
          {open && (
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <DevysButton kind="quiet" compact aria-label="Reassign">
                    Reassign <ChevronDown />
                  </DevysButton>
                }
              />
              <DropdownMenuContent align="end" className="w-auto min-w-48">
                {employees
                  .filter((e) => e.id !== item.owner_employee_id)
                  .map((employee) => (
                    <DropdownMenuItem
                      key={employee.id}
                      onClick={() => actions.reassign(item, employee.id)}
                    >
                      <EmployeePortrait employee={employee} size={18} />
                      {employee.name}
                      <span className="ml-auto pl-3 text-caption text-ink-3">
                        {templateTitle(employee.template)}
                      </span>
                    </DropdownMenuItem>
                  ))}
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
        <WorkPlan item={item} editable={open} />
      </div>
      <div className="flex flex-wrap gap-1.5">
        {open ? (
          <>
            <DevysButton compact onClick={() => actions.setCommitmentState(item, "completed")}>
              <CircleCheck /> Mark done
            </DevysButton>
            {item.state !== "waiting" && (
              <DevysButton compact onClick={() => actions.setCommitmentState(item, "waiting")}>
                <Clock /> Waiting
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
            <DevysButton
              kind="quiet"
              compact
              onClick={() => actions.setCommitmentState(item, "cancelled")}
            >
              <CircleX /> Cancel
            </DevysButton>
          </>
        ) : (
          <DevysButton compact onClick={() => actions.setCommitmentState(item, "ready")}>
            <Undo2 /> Reopen
          </DevysButton>
        )}
      </div>
      {waiting.length > 0 && (
        <div className="flex flex-col gap-2">
          <span className="text-label font-medium text-ink-3">
            Waiting on your approval · {waiting.length}
          </span>
          {waiting.map((decision) => (
            <DecisionCard key={decision.id} decision={decision} />
          ))}
        </div>
      )}
      {answered.length > 0 && (
        <div className="flex flex-col gap-1">
          <span className="text-label font-medium text-ink-3">Decided</span>
          {answered.map((decision) => (
            <p key={decision.id} className="text-caption text-ink-2">
              {decision.status === "rejected" ? "Declined" : "Approved"}: {decisionTitle(decision)}
              {decision.status === "used" ? " · used" : ""}
            </p>
          ))}
        </div>
      )}
      <CodingSessions item={item} />
      <Evidence item={item} />
    </div>
  );
}

/**
 * What was done: for coding work one line (check, files changed, pull request, commit) that
 * opens the full record; otherwise the evidence notes themselves.
 */
function Evidence({ item }: { item: Commitment }) {
  const { employeeName } = useWorkspace();
  const [open, setOpen] = useState(false);
  const outcome = outcomeOf(item.evidence);
  if (!item.evidence.length) return null;
  const notes = (
    <div className="flex flex-col gap-1">
      {item.evidence.map((entry, index) => (
        <div key={index} className="flex flex-col gap-px py-1">
          <span className="text-detail text-ink">{entry.note}</span>
          <span className="text-caption text-ink-3">
            {entry.by.startsWith("employee:")
              ? employeeName(entry.by.slice("employee:".length))
              : entry.by === "devys"
                ? "Devys"
                : "You"}{" "}
            ·{" "}
            {new Date(entry.at).toLocaleString(undefined, {
              dateStyle: "medium",
              timeStyle: "short",
            })}
          </span>
        </div>
      ))}
    </div>
  );
  if (!outcome)
    return (
      <div className="flex flex-col gap-1">
        <span className="text-label font-medium text-ink-3">Evidence</span>
        {notes}
      </div>
    );
  return (
    <div className="flex flex-col gap-1" data-testid="outcome">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-[10px] bg-sheet-tint px-3 py-2 text-detail">
        {outcome.check && (
          <StatusChip tone={outcome.check.passed ? "done" : "failed"} small>
            {outcome.check.passed ? "Check passed" : "Check failed"}
          </StatusChip>
        )}
        {outcome.changes && <span className="text-ink-2">{outcome.changes}</span>}
        {outcome.pullRequest && (
          <a
            href={outcome.pullRequest.url}
            target="_blank"
            rel="noreferrer"
            className="font-medium text-ink hover:underline"
          >
            {outcome.pullRequest.label}
          </a>
        )}
        <span className="font-mono text-caption text-ink-3">{outcome.commit}</span>
        <button
          type="button"
          onClick={() => setOpen(!open)}
          className="ml-auto text-caption text-ink-3 hover:text-ink-2"
          aria-expanded={open}
        >
          {open ? "Hide" : "Details"}
        </button>
      </div>
      {open && notes}
    </div>
  );
}
