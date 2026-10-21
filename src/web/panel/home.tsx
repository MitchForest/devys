import { Check, ChevronRight } from "lucide-react";
import { useState } from "react";
import type { NeedsYouItem, WorkCard } from "../../app/wire.ts";
import type { Decision } from "../../authority/contract.ts";
import { useDecisions, useEmployees, useHome, useWork } from "../app/data.ts";
import { useAnswer } from "../app/mutations.ts";
import { useNav } from "../app/navigation.ts";
import { DevysButton } from "../design/buttons.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { decisionFields, decisionTitle } from "../pages/work.tsx";
import { PanelBody, PanelHeader, PanelSection } from "./panel.tsx";

const money = (cents: number) =>
  (cents / 100).toLocaleString(undefined, { style: "currency", currency: "USD" });

/**
 * Home's permanent view: everything waiting on the owner, then what is moving, what is stuck
 * and what it cost. Each row opens its thread; a decision is answered right here.
 */
export function NeedsYou({ close }: { close: () => void }) {
  const value = useHome().data;
  const pending = useDecisions().data ?? [];
  if (!value) return null;
  const { moving, stuck, spent_cents: spentCents } = value.glance;
  return (
    <section aria-label="Needs you" className="flex h-full flex-col">
      <PanelHeader title={value.needs_you.length ? "Needs you" : "At a glance"} close={close} />
      <PanelBody>
        {value.needs_you.length > 0 && (
          <div className="flex flex-col gap-2">
            {value.needs_you.map((item) => {
              const decision =
                item.kind === "decision" ? pending.find((d) => d.id === item.id) : undefined;
              return decision ? (
                <DecisionRow key={item.id} decision={decision} />
              ) : (
                <NeedsYouRow key={`${item.kind}-${item.id}`} item={item} />
              );
            })}
          </div>
        )}
        {moving.length > 0 && (
          <PanelSection title="Moving" count={moving.length}>
            {moving.map((item) => (
              <GlanceRow key={item.id} item={item} />
            ))}
          </PanelSection>
        )}
        {stuck.length > 0 && (
          <PanelSection title="Stuck" count={stuck.length}>
            {stuck.map((item) => (
              <GlanceRow key={item.id} item={item} tone="stuck" />
            ))}
          </PanelSection>
        )}
        {spentCents !== null && spentCents > 0 && (
          <p className="text-detail text-ink-3">{money(spentCents)} spent since you last looked</p>
        )}
      </PanelBody>
    </section>
  );
}

/** One request, answered in place; its input unfolds on demand. */
function DecisionRow({ decision }: { decision: Decision }) {
  const employees = useEmployees();
  const work = useWork().data;
  const nav = useNav();
  const answer = useAnswer();
  const [open, setOpen] = useState(false);
  const employee = employees.find((e) => e.id === decision.employee_id);
  const item = work?.find((w) => w.id === decision.work_item_id);
  return (
    <div className="flex flex-col gap-2 rounded-card border border-hairline bg-sheet p-3 shadow-resting">
      <div className="flex items-center gap-2">
        {employee && <EmployeePortrait employee={employee} size={22} />}
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-control font-semibold text-ink">
            {item?.title ?? decisionTitle(decision)}
          </span>
          <span className="truncate text-caption text-ink-3">
            {employee?.name ?? "An employee"} asks
            {item ? ` · ${decisionTitle(decision)}` : ""}
          </span>
        </div>
      </div>
      {open && (
        <div className="flex flex-col gap-1 rounded-control bg-well p-2.5">
          {decisionFields(decision.input).map(([key, value]) => (
            <div key={key} className="flex items-baseline gap-2">
              <span className="min-w-14 text-caption text-ink-3">{key}</span>
              <span className="line-clamp-6 min-w-0 text-detail break-words text-ink select-text">
                {value}
              </span>
            </div>
          ))}
        </div>
      )}
      <div className="flex items-center gap-1.5">
        <DevysButton
          kind="aurora"
          compact
          onClick={() => answer.mutate({ id: decision.id, approve: true })}
        >
          <Check /> Approve
        </DevysButton>
        <DevysButton compact onClick={() => answer.mutate({ id: decision.id, approve: false })}>
          Decline
        </DevysButton>
        <span className="ml-auto" />
        <button
          type="button"
          onClick={() => setOpen(!open)}
          aria-expanded={open}
          className="text-caption text-ink-3 hover:text-ink-2"
        >
          {open ? "Hide details" : "Details"}
        </button>
        {decision.work_item_id && (
          <button
            type="button"
            onClick={() => nav.openThread(decision.work_item_id!)}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            Thread
          </button>
        )}
      </div>
    </div>
  );
}

function NeedsYouRow({ item }: { item: NeedsYouItem }) {
  const nav = useNav();
  const employee = useEmployees().find((e) => e.id === item.employee_id);
  const opens = item.work_id ?? undefined;
  return (
    <button
      type="button"
      disabled={!opens}
      onClick={() => opens && nav.openThread(opens)}
      className="flex items-center gap-2.5 rounded-card border border-hairline bg-sheet px-3 py-2.5 text-left shadow-resting enabled:hover:bg-sheet-tint"
    >
      {employee && <EmployeePortrait employee={employee} size={22} />}
      <span className="min-w-0 flex-1 truncate text-control text-ink">{item.title}</span>
      {opens && <ChevronRight className="size-4 shrink-0 text-ink-3" />}
    </button>
  );
}

function GlanceRow({ item, tone }: { item: WorkCard; tone?: "stuck" }) {
  const nav = useNav();
  const employee = useEmployees().find((e) => e.id === item.employee_id);
  const note =
    tone === "stuck"
      ? item.wait_condition
        ? `Waiting on ${item.wait_condition}`
        : "No change in a day"
      : undefined;
  return (
    <button
      type="button"
      onClick={() => nav.openThread(item.id)}
      className="-mx-2 flex items-center gap-2.5 rounded-[9px] px-2 py-1.5 text-left hover:bg-sheet-tint"
    >
      {employee && <EmployeePortrait employee={employee} size={20} />}
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-detail font-medium text-ink">{item.title}</span>
        {note && <span className="truncate text-caption text-red">{note}</span>}
      </span>
    </button>
  );
}
