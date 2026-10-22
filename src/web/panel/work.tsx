import {
  Check,
  ChevronDown,
  CircleCheck,
  CircleX,
  Clock,
  Hand,
  KeyRound,
  Pencil,
  Redo2,
  Undo2,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { api } from "../app/api.ts";
import { ownerRequest, spendOf, type Decision } from "../../authority/contract.ts";
import type { NeedsYouRequest } from "../../app/wire.ts";
import type { WorkItem } from "../../work/contract.ts";
import { employeeOf } from "../../conversations/contract.ts";
import { dateTime, dueDate, upcoming } from "../lib/format.ts";
import {
  accessTitle,
  chipFor,
  isOpen,
  outcomeOf,
  takeoverTitle,
  templateTitle,
} from "../app/names.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import {
  useBusinessId,
  useDecisions,
  useEmployeeName,
  useEmployees,
  useMembers,
  usePerson,
} from "../app/data.ts";
import { useAnswer, useTakeOverRequest, useTakeover, useUpdateWorkItem } from "../app/mutations.ts";
import { useNav } from "../app/navigation.ts";
import { SecretEntrySheet } from "../shell/secret-entry.tsx";
import { keys } from "../app/query.ts";

/** The owner's changes to a work item, as the menus and buttons apply them. */
function useWorkChanges() {
  const update = useUpdateWorkItem();
  const takeover = useTakeover();
  return {
    setState: (item: WorkItem, state: WorkItem["state"]) =>
      update.mutate({ item, change: { state }, failure: "That work item changed." }),
    reassign: (item: WorkItem, owner: string) =>
      update.mutate({
        item,
        change: { owner, state: "ready" },
        failure: "That work couldn't be reassigned.",
      }),
    toggleTakeover: (item: WorkItem) => takeover.mutate(item),
  };
}
import { StatusChip, Card } from "../design/primitives.tsx";
import { endOfDay } from "../shell/dialogs.tsx";
import { BrowserSection } from "./layers/browser.tsx";
import { CodingSessions } from "./coding.tsx";
import { RoutineProposal } from "./routines.tsx";
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
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";

/**
 * What the owner can do to a work item from a row: take it over or hand it back. Changing it by
 * hand (marking it, cancelling, reopening) is for work they have taken over, which fences its
 * employee; otherwise they ask in its thread (owner decision 2026-10-21).
 */
function WorkActions({ item, extra }: { item: WorkItem; extra?: ReactNode }) {
  const actions = useWorkChanges();
  const mine = useHandEditing(item);
  const person = usePerson();
  const takeover = item.taken_over_by === null || item.taken_over_by === person?.id;
  return (
    <>
      {isOpen(item.state) && takeover && (
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
      )}
      {mine && !isOpen(item.state) && (
        <ContextMenuItem onClick={() => actions.setState(item, "ready")}>
          <Undo2 /> Reopen
        </ContextMenuItem>
      )}
      {mine && isOpen(item.state) && (
        <>
          <ContextMenuSeparator />
          {item.state !== "ready" && (
            <ContextMenuItem onClick={() => actions.setState(item, "ready")}>
              <Redo2 /> Mark ready
            </ContextMenuItem>
          )}
          {item.state !== "waiting" && (
            <ContextMenuItem onClick={() => actions.setState(item, "waiting")}>
              <Clock /> Mark waiting
            </ContextMenuItem>
          )}
          <ContextMenuItem onClick={() => actions.setState(item, "completed")}>
            <CircleCheck /> Mark done
          </ContextMenuItem>
          <ContextMenuItem
            variant="destructive"
            onClick={() => actions.setState(item, "cancelled")}
          >
            <CircleX /> Cancel
          </ContextMenuItem>
        </>
      )}
      {extra}
    </>
  );
}

/** Whether the signed-in person has taken this work over, so they may change it by hand. */
export function useHandEditing(item: WorkItem) {
  const person = usePerson();
  return item.taken_over_by !== null && item.taken_over_by === person?.id;
}

/** Right-click (or long-press) a work item to act on it. */
function WithWorkActions({
  item,
  extra,
  children,
}: {
  item: WorkItem;
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

/** One work item: what, who, what's next and its state. Click to open its thread. */
export function WorkRow({
  item,
  extra,
  compact,
}: {
  item: WorkItem;
  extra?: ReactNode;
  /** In a panel: smaller, flush with the panel's edge. */
  compact?: boolean;
}) {
  const employeeName = useEmployeeName();
  const nav = useNav();
  const person = usePerson();
  const members = useMembers();
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const owner = employeeName(item.owner_employee_id);
  const done = item.evidence[item.evidence.length - 1];
  const waiting = item.state === "waiting" ? waitingNote(item) : "";
  const detail = waiting
    ? `${owner} · ${waiting}`
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
        onClick={() => nav.openThread(item.id)}
        className={
          compact
            ? "-mx-2 flex w-[calc(100%+16px)] items-center gap-2.5 rounded-small px-2 py-1.5 text-left transition-colors duration-150 hover:bg-sheet-tint"
            : "flex w-full items-center gap-3 rounded-row px-3 py-2.5 text-left transition-colors duration-150 hover:bg-sheet-tint"
        }
      >
        <div className="flex min-w-0 flex-col gap-0.5">
          <span
            className={
              compact
                ? "truncate text-detail font-medium text-ink"
                : "text-body font-semibold text-ink"
            }
          >
            {item.title}
          </span>
          <span
            className={
              compact ? "truncate text-caption text-ink-3" : "line-clamp-2 text-detail text-ink-2"
            }
          >
            {detail}
          </span>
        </div>
        <span className="ml-auto" />
        {takeover && isOpen(item.state) && (
          <span className="shrink-0 text-caption text-ink-3">{takeover}</span>
        )}
        <StatusChip tone={chip.tone} small={compact}>
          {chip.title}
        </StatusChip>
      </button>
    </WithWorkActions>
  );
}

/**
 * What waiting work waits on and when it looks again, in a row: "waiting on the press kit until
 * Thu 9:00 AM", "waiting until Tomorrow 9:00 AM"; empty when neither is known.
 */
export function waitingNote(item: WorkItem) {
  const until = item.wake_at ? `until ${upcoming(item.wake_at)}` : "";
  if (item.wait_condition) return `waiting on ${item.wait_condition}${until ? ` ${until}` : ""}`;
  return until && `waiting ${until}`;
}

/** An amount as the owner reads it: "$12.99", or "12.99 EUR" in another currency. */
export const money = (amount: { cents: number; currency: string }) =>
  amount.currency === "USD"
    ? `$${(amount.cents / 100).toFixed(2)}`
    : `${(amount.cents / 100).toFixed(2)} ${amount.currency}`;

/** A decision's exact input as label/value rows; an `askOwner` request in its own words. */
export function decisionFields(decision: Pick<Decision, "kind" | "input">): [string, string][] {
  const request = ownerRequest(decision);
  if (request?.kind === "approve")
    return [
      ["Action", request.action],
      ["With", request.counterparty],
      ...(request.amount ? ([["Amount", money(request.amount)]] as [string, string][]) : []),
      ...(request.renewal ? ([["Renews", request.renewal]] as [string, string][]) : []),
    ];
  if (request?.kind === "take_over")
    return [
      ["Do", request.reason],
      ...(request.url ? ([["Site", request.url]] as [string, string][]) : []),
    ];
  if (request?.kind === "secret")
    return [
      ["Name", request.name],
      ["Why", request.why],
    ];
  if (request?.kind === "connect") return [["Why", request.why]];
  const { input } = decision;
  if (input && typeof input === "object" && !Array.isArray(input))
    return Object.entries(input).map(([key, value]) => [
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    ]);
  return [["input", JSON.stringify(input)]];
}

/**
 * What a decision asks for, in words: a proposed hire names the person and role; an `askOwner`
 * request says what to approve, or what to do in the browser.
 */
export function decisionTitle(decision: Decision) {
  const request = ownerRequest(decision);
  if (request?.kind === "approve")
    return request.amount ? `Spend ${money(request.amount)}: ${request.action}` : request.action;
  if (request?.kind === "take_over") return `Sign in / take over: ${request.reason}`;
  if (request?.kind === "secret") return `${request.spend ? "Card" : "Secret"}: ${request.name}`;
  if (request?.kind === "connect") return "Connect an app";
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

/**
 * How the owner answers a request: Approve or Decline; a take over takes the work over and opens
 * its live browser; a spend approval is signed on the owner's Mac or iPhone, so the web only
 * says so (.docs/AUTHORITY.md).
 */
export function RequestActions({
  decision,
  compact,
  children,
}: {
  decision: Decision;
  compact?: boolean;
  children?: ReactNode;
}) {
  const answer = useAnswer();
  const takeOver = useTakeOverRequest();
  const businessId = useBusinessId();
  const [entering, setEntering] = useState(false);
  const size = compact ? "compact" : "regular";
  const secret = ownerRequest(decision);
  if (spendOf(decision))
    return (
      <div className="flex w-full items-center gap-1.5">
        <span className="text-detail text-ink-2" data-testid="sign-elsewhere">
          Approve on your Mac or iPhone
        </span>
        <span className="ml-auto" />
        {children}
      </div>
    );
  return (
    <div className="flex w-full items-center gap-1.5">
      {secret?.kind === "secret" ? (
        <>
          <Button variant="aurora" size={size} onClick={() => setEntering(true)}>
            <KeyRound /> Add {secret.spend ? "card" : "secret"}
          </Button>
          <SecretEntrySheet
            businessId={businessId}
            open={entering}
            onClose={() => setEntering(false)}
            fixed={{ name: secret.name, spend: secret.spend ?? false }}
          />
        </>
      ) : decision.kind === "take_over" ? (
        <Button
          variant="aurora"
          size={size}
          disabled={!decision.work_item_id}
          onClick={() => decision.work_item_id && takeOver.mutate(decision.work_item_id)}
        >
          <Hand /> Take over
        </Button>
      ) : (
        <Button
          variant="aurora"
          size={size}
          onClick={() => answer.mutate({ id: decision.id, approve: true })}
          title="Allows this exact request once."
        >
          <Check /> Approve
        </Button>
      )}
      <Button size={size} onClick={() => answer.mutate({ id: decision.id, approve: false })}>
        Decline
      </Button>
      <span className="ml-auto" />
      {children}
    </div>
  );
}

/**
 * One exact request: who asked, what they will do, and the input it will run with. A routine's
 * activation reads as its proposal.
 */
export function DecisionCard({ decision }: { decision: NeedsYouRequest }) {
  // A connect request is its app's card, already in the thread.
  if (decision.kind === "connect") return null;
  if (decision.routine) return <RoutineProposal decision={decision} routine={decision.routine} />;
  return <RequestCard decision={decision} />;
}

function RequestCard({ decision }: { decision: Decision }) {
  const employeeName = useEmployeeName();
  return (
    <Card>
      <div className="flex flex-col items-start gap-2.5">
        <StatusChip tone="needsYou">Needs you</StatusChip>
        <span className="text-heading font-semibold text-ink">{decisionTitle(decision)}</span>
        <span className="text-detail text-ink-2">
          {employeeName(decision.employee_id)}{" "}
          {decision.kind === "decision" ? "asked to run this exactly:" : "asks you:"}
        </span>
        <div className="flex w-full flex-col gap-1 rounded-control bg-well p-2.5">
          {decisionFields(decision).map(([key, value]) => (
            <div key={key} className="flex items-baseline gap-2">
              <span className="min-w-16 text-caption text-ink-3">{key}</span>
              <span className="line-clamp-6 min-w-0 text-body break-words text-ink select-text">
                {value}
              </span>
            </div>
          ))}
        </div>
        <div className="flex w-full gap-2 pt-0.5">
          <RequestActions decision={decision} />
        </div>
      </div>
    </Card>
  );
}

/** How a request was answered: a take over is taken, then done; a spend approval was signed. */
const answeredAs = (decision: Decision) =>
  decision.status === "rejected"
    ? "Declined"
    : decision.kind === "secret"
      ? "Added"
      : decision.kind === "connect"
        ? "Connected"
        : decision.kind === "take_over"
          ? decision.status === "used"
            ? "Done"
            : "Taken over"
          : `Approved${decision.signed_by ? " and signed" : ""}${decision.status === "used" ? " · used" : ""}`;

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
function WorkPlan({ item, editable }: { item: WorkItem; editable: boolean }) {
  const update = useUpdateWorkItem();
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
      ...(next.trim() !== item.next_action ? { next_action: next.trim() } : {}),
      ...(waiting.trim() !== (item.wait_condition ?? "")
        ? { wait_condition: waiting.trim() || null }
        : {}),
      ...(due !== dateField(item.due_at) ? { due_at: due ? endOfDay(due) : null } : {}),
    };
    if (Object.keys(change).length === 0) return setEditing(false);
    setBusy(true);
    const saved = await update
      .mutateAsync({ item, change, failure: "That work couldn't be saved." })
      .then(
        () => true,
        () => false,
      );
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
          {item.state === "waiting" && item.wake_at && (
            <>
              <dt className="text-ink-3">Waiting until</dt>
              <dd className="text-ink">{upcoming(item.wake_at)}</dd>
            </>
          )}
          <dt className="text-ink-3">Due</dt>
          <dd className="text-ink">{item.due_at ? dueDate(item.due_at) : "No due date"}</dd>
        </dl>
        {editable && (
          <Button
            variant="quiet"
            size="compact"
            onClick={edit}
            aria-label="Edit next, waiting on and due"
          >
            <Pencil /> Edit
          </Button>
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
        <Input
          autoFocus
          value={next}
          maxLength={1000}
          onChange={(event) => setNext(event.target.value)}
        />
      </Field>
      <Field label="Waiting on">
        <Input
          value={waiting}
          maxLength={1000}
          placeholder="Nothing"
          onChange={(event) => setWaiting(event.target.value)}
        />
      </Field>
      <Field label="Due">
        <Input type="date" value={due} onChange={(event) => setDue(event.target.value)} />
      </Field>
      {error && (
        <p role="alert" className="text-detail text-ink-2">
          {error}
        </p>
      )}
      <div className="flex gap-1.5">
        <Button size="compact" type="submit" disabled={busy}>
          {busy ? "Saving…" : "Save"}
        </Button>
        <Button variant="quiet" size="compact" onClick={() => setEditing(false)}>
          Cancel
        </Button>
      </div>
    </form>
  );
}

/** A work item's answered requests, reloaded when the item changes. */
function useAnswered(item: WorkItem) {
  const businessId = useBusinessId();
  return (
    useQuery({
      queryKey: keys.workDecisions(businessId, item.id, item.revision),
      queryFn: () => api.workDecisions(businessId, item.id),
      select: (result) => result.decisions.filter((d) => d.status !== "pending"),
    }).data ?? []
  );
}

/**
 * One work item, as its thread's work card shows it: who owns it, where it stands, what's
 * next, its evidence and decisions, with takeover and handing it to another employee.
 */
export function WorkDetail({ item }: { item: WorkItem }) {
  const employees = useEmployees();
  const actions = useWorkChanges();
  const employeeName = useEmployeeName();
  const person = usePerson();
  const members = useMembers();
  const decisions = useDecisions().data;
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const waiting = (decisions ?? []).filter((d) => d.work_item_id === item.id);
  const answered = useAnswered(item);
  const owner = employees.find((e) => e.id === item.owner_employee_id);
  const chip = chipFor(item.state);
  const open = isOpen(item.state);
  // Read-only until taken over; then the owner changes it by hand until they hand it back.
  const mine = useHandEditing(item);
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusChip tone={chip.tone} small>
          {chip.title}
        </StatusChip>
        {takeover && <span className="text-caption text-ink-3">{takeover}</span>}
      </div>
      {item.objective && <p className="text-body text-ink-2">{item.objective}</p>}
      <div className="flex flex-col gap-2.5 rounded-card bg-sheet-tint px-3 py-2.5">
        <div className="flex items-center gap-2.5">
          {owner && <EmployeePortrait employee={owner} size={26} />}
          <div className="flex min-w-0 flex-col">
            <span className="text-caption text-ink-3">Owner</span>
            <span
              className="truncate text-body font-semibold text-ink"
              data-testid="work-item-owner"
            >
              {employeeName(item.owner_employee_id)}
            </span>
          </div>
          <span className="ml-auto" />
          {open && mine && (
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="quiet" size="compact" aria-label="Reassign">
                    Reassign <ChevronDown />
                  </Button>
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
        <WorkPlan item={item} editable={open && mine} />
      </div>
      <div className="flex flex-wrap gap-1.5">
        {open && (item.taken_over_by === null || mine) && (
          <Button size="compact" onClick={() => actions.toggleTakeover(item)}>
            {mine ? (
              <>
                <Undo2 /> Hand back
              </>
            ) : (
              <>
                <Hand /> Take over
              </>
            )}
          </Button>
        )}
        {mine && open && (
          <>
            <Button size="compact" onClick={() => actions.setState(item, "completed")}>
              <CircleCheck /> Mark done
            </Button>
            {item.state !== "waiting" && (
              <Button size="compact" onClick={() => actions.setState(item, "waiting")}>
                <Clock /> Waiting
              </Button>
            )}
            <Button
              variant="quiet"
              size="compact"
              onClick={() => actions.setState(item, "cancelled")}
            >
              <CircleX /> Cancel
            </Button>
          </>
        )}
        {mine && !open && (
          <Button size="compact" onClick={() => actions.setState(item, "ready")}>
            <Undo2 /> Reopen
          </Button>
        )}
      </div>
      {waiting.length > 0 && (
        <div className="flex flex-col gap-2">
          <span className="text-label font-medium text-ink-3">
            Waiting on you · {waiting.length}
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
              {answeredAs(decision)}: {decisionTitle(decision)}
            </p>
          ))}
        </div>
      )}
      <CodingSessions item={item} />
      <BrowserSection item={item} />
      <Evidence item={item} />
    </div>
  );
}

/**
 * What was done: for coding work one line (check, files changed, pull request, commit) that
 * opens the full record; otherwise the evidence notes themselves.
 */
function Evidence({ item }: { item: WorkItem }) {
  const employeeName = useEmployeeName();
  const [open, setOpen] = useState(false);
  const outcome = outcomeOf(item.evidence);
  if (!item.evidence.length) return null;
  const notes = (
    <div className="flex flex-col gap-1">
      {item.evidence.map((entry, index) => (
        <div key={index} className="flex flex-col gap-px py-1">
          <span className="text-detail text-ink">{entry.note}</span>
          <span className="text-caption text-ink-3">
            {employeeOf(entry.by)
              ? employeeName(employeeOf(entry.by)!)
              : entry.by === "devys"
                ? "Devys"
                : "You"}{" "}
            · {dateTime(entry.at)}
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
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-control bg-sheet-tint px-3 py-2 text-detail">
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
        {outcome.deploys.map((deploy) =>
          deploy.live && deploy.url ? (
            <a
              key={deploy.stage}
              href={deploy.url}
              target="_blank"
              rel="noreferrer"
              className="font-medium text-ink hover:underline"
              title={`${deploy.commit} is live`}
            >
              {deploy.stage === "production" ? "Live" : "Preview"} ↗
            </a>
          ) : (
            <span key={deploy.stage} className="text-red">
              {deploy.stage === "production" ? "Production" : "Preview"} deploy failed
            </span>
          ),
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
