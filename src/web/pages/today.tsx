import { Square } from "lucide-react";
import { EmployeePortrait } from "../design/portrait.tsx";
import { operationsMood } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { EmptyNote, LiveTag, PageBody, SectionHeader } from "../design/primitives.tsx";
import { DecisionCard, WorkRow } from "./work.tsx";

const isToday = (timestamp: string) =>
  new Date(timestamp).toDateString() === new Date().toDateString();

/** The briefing: a greeting, Operations' live state, what needs you, who is working, and what finished today. */
export function TodayPage() {
  return (
    <PageBody>
      <TodayGreeting />
      <TodayWork />
    </PageBody>
  );
}

/** The greeting and what Operations is doing, with Stop while it works. */
export function TodayGreeting() {
  const state = useWorkspace();
  const { operations, person, isRunning, actions } = state;
  const hour = new Date().getHours();
  const part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  const first = person?.display_name.split(" ")[0];
  const status = state.status;
  const running = valueOf(status)?.inbox.find((i) => i.id === valueOf(status)?.run?.id);
  const line =
    status.status === "loading"
      ? "Checking in with Operations…"
      : status.status === "failed"
        ? status.message
        : isRunning && running
          ? `Operations is working on “${running.text ?? "your message"}”.`
          : isRunning
            ? "Operations is working."
            : "Operations is available.";
  return (
    <div className="flex flex-col gap-3 pt-2">
      <h1 className="text-greeting font-bold tracking-tight text-ink">
        {first ? `${part}, ${first}.` : `${part}.`}
      </h1>
      <div className="flex flex-wrap items-center gap-2.5">
        {operations && (
          <EmployeePortrait
            employee={operations}
            size={28}
            mood={operationsMood(state)}
            label={operations.name}
          />
        )}
        <span className="text-body text-ink-2">{line}</span>
        {isRunning && (
          <DevysButton compact onClick={() => actions.stop()} title="Stop the current work (⌘.)">
            <Square className="fill-current" /> Stop
          </DevysButton>
        )}
        <LiveTag />
      </div>
    </div>
  );
}

/** What needs the owner, what's in motion and what finished today. */
export function TodayWork() {
  const { decisions, work } = useWorkspace();
  const pending = valueOf(decisions) ?? [];
  const all = valueOf(work) ?? [];
  const blocked = all.filter((item) => item.state === "needs_decision");
  const moving = all.filter((item) => ["in_progress", "ready", "waiting"].includes(item.state));
  const done = all.filter((item) => item.state === "completed" && isToday(item.updated_at));
  return (
    <>
      {(pending.length > 0 || blocked.length > 0) && (
        <div className="flex flex-col gap-3">
          <SectionHeader title="Needs you" count={pending.length + blocked.length} />
          <div className="grid grid-cols-[repeat(auto-fill,minmax(260px,1fr))] gap-3">
            {pending.map((d) => (
              <DecisionCard key={d.id} decision={d} />
            ))}
          </div>
          {blocked.map((item) => (
            <WorkRow key={item.id} item={item} />
          ))}
        </div>
      )}
      <div className="flex flex-col gap-2">
        <SectionHeader title="In motion" count={moving.length} />
        {moving.length === 0 && (
          <EmptyNote>Nothing is in motion. Add work, or ask Operations.</EmptyNote>
        )}
        {moving.slice(0, 8).map((item) => (
          <WorkRow key={item.id} item={item} />
        ))}
      </div>
      {done.length > 0 && (
        <div className="flex flex-col gap-2">
          <SectionHeader title="Done today" count={done.length} />
          {done.map((item) => (
            <WorkRow key={item.id} item={item} />
          ))}
        </div>
      )}
    </>
  );
}
