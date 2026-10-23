/**
 * Routines as the owner sees them: listed on an employee's desk and a project's overview, read
 * in their layer, and proposed in the chat where asked. A running routine changes only by a new decision,
 * so the owner pauses and resumes it here and changes it by asking its employee.
 */
import { Check, MessageSquareQuote, Repeat } from "lucide-react";
import { useState } from "react";
import type { Decision } from "../../authority/contract.ts";
import { ref } from "../../protocol/ref.ts";
import type { Routine } from "../../work/contract.ts";
import { useEmployees, useProjects, useRoutines } from "../app/data.ts";
import { useAnswer, useToggleRoutine } from "../app/mutations.ts";
import { notifyTitle, routineStateTitle } from "../app/names.ts";
import { useNav } from "../app/navigation.ts";
import { useAsk } from "../app/workspace.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import { relativeDay, upcoming } from "../lib/format.ts";
import { PanelSection } from "./panel.tsx";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const stateColor: Record<Routine["state"], string> = {
  active: "text-green",
  paused: "text-ink-3",
  proposed: "text-amber",
};

/** The routines given, as a section; absent when there are none. */
export function RoutinesSection({ routines }: { routines: readonly Routine[] }) {
  if (routines.length === 0) return null;
  return (
    <PanelSection title="Routines" count={routines.length}>
      {routines.map((routine) => (
        <RoutineRow key={routine.id} routine={routine} />
      ))}
    </PanelSection>
  );
}

/** One routine: what, when, its state, next run and last result. Click to open its layer. */
function RoutineRow({ routine }: { routine: Routine }) {
  const nav = useNav();
  const toggle = useToggleRoutine();
  const next =
    routine.state === "active" && routine.next_run_at
      ? `Next run ${upcoming(routine.next_run_at)}`
      : undefined;
  return (
    <div
      data-testid="routine-row"
      className="-mx-2 flex w-[calc(100%+16px)] items-center gap-2 rounded-small px-2 py-1.5 transition-colors duration-150 hover:bg-sheet-tint"
    >
      <button
        type="button"
        onClick={() => nav.openLayer({ kind: "record", ref: ref("work", "routine", routine.id) })}
        className="flex min-w-0 flex-1 items-start gap-2.5 text-left"
      >
        <Repeat className="mt-0.5 size-3.5 shrink-0 text-ink-3" aria-hidden />
        <span className="flex min-w-0 flex-col gap-px">
          <span className="flex items-baseline gap-1.5">
            <span className="truncate text-detail font-medium text-ink">{routine.title}</span>
            <span className={cn("shrink-0 text-caption", stateColor[routine.state])}>
              {routineStateTitle[routine.state]}
            </span>
          </span>
          <span className="truncate text-caption text-ink-3">{routine.schedule}</span>
          {(next || routine.last_result) && (
            <span className="truncate text-caption text-ink-2">
              {[next, routine.last_result && `Last: ${routine.last_result}`]
                .filter(Boolean)
                .join(" · ")}
            </span>
          )}
        </span>
      </button>
      {routine.state !== "proposed" && (
        <Button variant="quiet" size="compact" onClick={() => toggle.mutate(routine)}>
          {routine.state === "active" ? "Pause" : "Resume"}
        </Button>
      )}
    </div>
  );
}

/** A routine's facts, as its layer and its proposal show them alike. */
function RoutineFacts({ routine, more = false }: { routine: Routine; more?: boolean }) {
  const nav = useNav();
  const employee = useEmployees().find((e) => e.id === routine.employee_id);
  const project = useProjects().data?.find((p) => p.id === routine.project_id);
  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-detail">
      <dt className="text-ink-3">Schedule</dt>
      <dd className="text-ink">{routine.schedule}</dd>
      <dt className="text-ink-3">Notify</dt>
      <dd className="text-ink">{notifyTitle[routine.notify]}</dd>
      {more && routine.state === "active" && routine.next_run_at && (
        <>
          <dt className="text-ink-3">Next run</dt>
          <dd className="text-ink">{upcoming(routine.next_run_at)}</dd>
        </>
      )}
      {more && routine.last_run_at && (
        <>
          <dt className="text-ink-3">Last run</dt>
          <dd className="text-ink">{relativeDay(new Date(routine.last_run_at))}</dd>
        </>
      )}
      {more && routine.last_result && (
        <>
          <dt className="text-ink-3">Result</dt>
          <dd className="text-ink">{routine.last_result}</dd>
        </>
      )}
      {more && employee && (
        <>
          <dt className="text-ink-3">Employee</dt>
          <dd>
            <button
              type="button"
              onClick={() => nav.message(employee.id)}
              className="flex items-center gap-1.5 text-ink hover:underline"
            >
              <EmployeePortrait employee={employee} size={18} />
              {employee.name}
            </button>
          </dd>
        </>
      )}
      {project && (
        <>
          <dt className="text-ink-3">Project</dt>
          <dd>
            <button
              type="button"
              onClick={() => nav.selectPlace({ kind: "project", id: project.id })}
              className="text-ink hover:underline"
            >
              {project.name}
            </button>
          </dd>
        </>
      )}
    </dl>
  );
}

/** A routine, read-only: what it does, when, and what its last run said; Pause or Resume. */
export function RoutineLayer({ id }: { id: string }) {
  const routine = useRoutines().data?.find((r) => r.id === id);
  const toggle = useToggleRoutine();
  const ask = useAsk();
  if (!routine)
    return (
      <div className="h-full overflow-y-auto px-4 pt-3.5 pb-6">
        <EmptyNote>This routine no longer exists.</EmptyNote>
      </div>
    );
  return (
    <div
      aria-label="Routine"
      role="region"
      className="flex h-full flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-6"
    >
      <div className="flex flex-col gap-0.5">
        <span className="text-heading font-semibold text-ink">{routine.title}</span>
        <span className={cn("text-detail", stateColor[routine.state])}>
          {routineStateTitle[routine.state]}
          {routine.state === "proposed" && (
            <span className="text-ink-3"> · Waiting for your decision</span>
          )}
        </span>
      </div>
      <p className="text-body whitespace-pre-wrap text-ink select-text">{routine.instruction}</p>
      <RoutineFacts routine={routine} more />
      <div className="flex gap-1.5">
        {routine.state !== "proposed" && (
          <Button size="compact" onClick={() => toggle.mutate(routine)}>
            {routine.state === "active" ? "Pause" : "Resume"}
          </Button>
        )}
        <Button
          variant="quiet"
          size="compact"
          title="Quote this routine in the conversation to ask for a change"
          onClick={() => ask(`${routine.title} · ${routine.schedule}`)}
        >
          <MessageSquareQuote /> Ask
        </Button>
      </div>
    </div>
  );
}

/** Long instructions start folded, so the proposal reads at a glance. */
const long = (text: string) => text.length > 240 || text.split("\n").length > 4;

/**
 * An employee's proposed routine where it was asked, readable as a whole; approving activates exactly
 * this revision.
 */
export function RoutineProposal({ decision, routine }: { decision: Decision; routine: Routine }) {
  const employee = useEmployees().find((e) => e.id === decision.employee_id);
  const answer = useAnswer();
  const [open, setOpen] = useState(false);
  const folded = long(routine.instruction) && !open;
  return (
    <div
      data-testid="routine-proposal"
      className="flex flex-col gap-2.5 rounded-card border border-hairline bg-sheet p-3 shadow-resting"
    >
      <div className="flex items-center gap-2">
        {employee && <EmployeePortrait employee={employee} size={22} />}
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-caption text-ink-3">
            {employee?.name ?? "An employee"} proposes a routine
          </span>
          <span className="truncate text-control font-semibold text-ink">{routine.title}</span>
        </div>
      </div>
      <RoutineFacts routine={routine} />
      <div className="flex flex-col items-start gap-0.5">
        <p
          className={cn(
            "text-detail whitespace-pre-wrap text-ink-2 select-text",
            folded && "line-clamp-3",
          )}
        >
          {routine.instruction}
        </p>
        {long(routine.instruction) && (
          <button
            type="button"
            onClick={() => setOpen(!open)}
            aria-expanded={open}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            {open ? "Less" : "More"}
          </button>
        )}
      </div>
      <div className="flex items-center gap-1.5">
        <Button
          variant="aurora"
          size="compact"
          onClick={() => answer.mutate({ id: decision.id, approve: true })}
        >
          <Check /> Approve
        </Button>
        <Button size="compact" onClick={() => answer.mutate({ id: decision.id, approve: false })}>
          Decline
        </Button>
      </div>
    </div>
  );
}
