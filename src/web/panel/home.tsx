import { ChevronRight, Plug } from "lucide-react";
import { useState } from "react";
import type { NeedsYouItem, NeedsYouRequest, WorkCard } from "../../app/wire.ts";
import { ownerRequest, spendOf } from "../../authority/contract.ts";
import { ref } from "../../protocol/ref.ts";
import { useApps, useEmployees, useHome, useWork } from "../app/data.ts";
import { useAnswer, useConnectApp } from "../app/mutations.ts";
import { AppLogo } from "./layers/team-app.tsx";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useNav } from "../app/navigation.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import { decisionFields, decisionTitle, RequestActions, RequestDetails } from "./work.tsx";
import { PanelBody, PanelHeader, PanelSection } from "./panel.tsx";
import { RoutineProposal } from "./routines.tsx";

/**
 * Home's permanent view, all from one read of `/home`: everything waiting on the owner, then
 * what is moving and what is stuck. Each row opens its thread; a decision is answered right here.
 */
export function NeedsYou({ close }: { close: () => void }) {
  const value = useHome().data;
  if (!value) return null;
  const { moving, stuck } = value.glance;
  return (
    <section aria-label="Needs you" className="flex h-full flex-col">
      <PanelHeader title={value.needs_you.length ? "Needs you" : "At a glance"} close={close} />
      <PanelBody>
        {value.needs_you.length > 0 && (
          <div className="flex flex-col gap-2">
            {value.needs_you.map((item) =>
              item.kind === "reconnect" ? (
                <ReconnectRow key={`reconnect-${item.app.id}`} app={item.app} />
              ) : item.kind === "work" ? (
                <NeedsYouRow key={`${item.kind}-${item.id}`} item={item} />
              ) : item.kind === "connect" && item.app ? (
                <ConnectRow key={item.id} decision={item} app={item.app} />
              ) : item.routine ? (
                <RoutineProposal key={item.id} decision={item} routine={item.routine} />
              ) : (
                <DecisionRow key={item.id} decision={item} />
              ),
            )}
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
      </PanelBody>
    </section>
  );
}

/** An app an employee asks the owner to connect: its logo, name and why, and Connect. */
function ConnectRow({
  decision,
  app,
}: {
  decision: NeedsYouRequest;
  app: { id: string; name: string; logo: string | null };
}) {
  const employees = useEmployees();
  const answer = useAnswer();
  const connect = useConnectApp();
  const nav = useNav();
  const employee = employees.find((e) => e.id === decision.employee_id);
  const request = ownerRequest(decision);
  const state = useApps().data?.find((each) => each.id === app.id)?.state;
  return (
    <div
      className="flex flex-col gap-2 rounded-card border border-hairline bg-sheet p-3 shadow-resting"
      data-testid="connect-request"
    >
      <div className="flex items-center gap-2.5">
        <AppLogo logo={app.logo} name={app.name} size={30} />
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-control font-semibold text-ink">{app.name}</span>
          <span className="line-clamp-2 text-caption text-ink-3">
            {employee?.name ?? "An employee"}: {request?.kind === "connect" ? request.why : ""}
          </span>
        </div>
      </div>
      <div className="flex w-full items-center gap-1.5">
        {state === "review" ? (
          <Button
            variant="aurora"
            size="compact"
            onClick={() => nav.openLayer({ kind: "record", ref: ref("team", "app", app.id) })}
          >
            Review
          </Button>
        ) : (
          <Button variant="aurora" size="compact" onClick={() => connect(app.id)}>
            <Plug /> Connect
          </Button>
        )}
        <Button size="compact" onClick={() => answer.mutate({ id: decision.id, approve: false })}>
          Decline
        </Button>
        <span className="ml-auto" />
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

/** A remote app whose sign-in stopped working: Reconnect. */
function ReconnectRow({ app }: { app: { id: string; name: string; logo: string | null } }) {
  const connect = useConnectApp();
  return (
    <div
      className="flex items-center gap-2.5 rounded-card border border-hairline bg-sheet px-3 py-2.5 shadow-resting"
      data-testid="reconnect"
    >
      <AppLogo logo={app.logo} name={app.name} size={26} />
      <span className="min-w-0 flex-1 truncate text-control text-ink">Reconnect {app.name}</span>
      <Button variant="aurora" size="compact" onClick={() => connect(app.id)}>
        <Plug /> Reconnect
      </Button>
    </div>
  );
}

/** One request, answered in place; its input unfolds on demand. */
function DecisionRow({ decision }: { decision: NeedsYouRequest }) {
  const employees = useEmployees();
  const work = useWork().data;
  const nav = useNav();
  const [open, setOpen] = useState(false);
  const employee = employees.find((e) => e.id === decision.employee_id);
  const item = work?.find((w) => w.id === decision.work_item_id);
  const request = ownerRequest(decision);
  // A draft or steps to approve are what is approved: shown without asking for details.
  const hasPreview = request?.kind === "approve" && Boolean(request.preview || request.steps);
  return (
    <div className="flex flex-col gap-2 rounded-card border border-hairline bg-sheet p-3 shadow-resting">
      <div className="flex items-center gap-2">
        {employee && <EmployeePortrait employee={employee} size={22} />}
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-control font-semibold text-ink">
            {item?.title ?? (decision.app ? decision.title : decisionTitle(decision))}
          </span>
          <span className="truncate text-caption text-ink-3">
            {employee?.name ?? "An employee"} asks
            {item ? ` · ${decision.app ? decision.title : decisionTitle(decision)}` : ""}
          </span>
        </div>
      </div>
      {(open || spendOf(decision) || hasPreview) && <RequestDetails decision={decision} compact />}
      <RequestActions decision={decision} compact>
        {!spendOf(decision) && !hasPreview && decisionFields(decision).length > 0 && (
          <button
            type="button"
            onClick={() => setOpen(!open)}
            aria-expanded={open}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            {open ? "Hide details" : "Details"}
          </button>
        )}
        {decision.work_item_id && (
          <button
            type="button"
            onClick={() => nav.openThread(decision.work_item_id!)}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            Thread
          </button>
        )}
      </RequestActions>
    </div>
  );
}

function NeedsYouRow({ item }: { item: Extract<NeedsYouItem, { kind: "work" }> }) {
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
      : item.progress;
  return (
    <button
      type="button"
      onClick={() => nav.openThread(item.id)}
      className="-mx-2 flex items-center gap-2.5 rounded-small px-2 py-1.5 text-left hover:bg-sheet-tint"
    >
      {employee && <EmployeePortrait employee={employee} size={20} />}
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-detail font-medium text-ink">{item.title}</span>
        {note && (
          <span
            className={cn("truncate text-caption", tone === "stuck" ? "text-red" : "text-ink-3")}
          >
            {note}
          </span>
        )}
      </span>
    </button>
  );
}
