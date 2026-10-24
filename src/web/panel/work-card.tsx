import {
  ChevronRight,
  Circle,
  CircleAlert,
  CircleCheck,
  CircleDot,
  Clock,
  Play,
  Square,
  Undo2,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import type { NeedsYouRequest } from "../../app/wire.ts";
import { ownerRequest, spendOf } from "../../authority/contract.ts";
import type { WorkItem, WorkResult, WorkStep } from "../../work/contract.ts";
import { api } from "../app/api.ts";
import {
  useBusinessId,
  useDecisions,
  useEmployees,
  useMembers,
  usePerson,
  useStatus,
  useWork,
} from "../app/data.ts";
import { useStartWork, useStop, useTakeover } from "../app/mutations.ts";
import { takeoverTitle } from "../app/names.ts";
import { useNav } from "../app/navigation.ts";
import { keys, poll } from "../app/query.ts";
import { AppLogo } from "./layers/team-app.tsx";
import {
  decisionFields,
  requestTitle,
  RequestActions,
  RequestDetails,
  WithWorkActions,
} from "./work.tsx";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const stepIcon = {
  todo: <Circle className="size-3.5 shrink-0 text-ink-3" />,
  doing: <CircleDot className="size-3.5 shrink-0 text-indigo" />,
  done: <CircleCheck className="size-3.5 shrink-0 text-green" />,
  blocked: <CircleAlert className="size-3.5 shrink-0 text-red" />,
} satisfies Record<WorkStep["state"], unknown>;

/** The plan, each step with where it stands; the owner's own steps read "You: …". */
function WorkSteps({ steps }: { steps: readonly WorkStep[] }) {
  return (
    <ol className="flex flex-col gap-1" aria-label="Steps">
      {steps.map((step, index) => (
        <li
          key={index}
          data-state={step.state}
          className={cn(
            "flex items-center gap-2 text-detail",
            step.state === "todo" ? "text-ink-3" : "text-ink",
            step.state === "doing" && "font-semibold",
          )}
        >
          {stepIcon[step.state]}
          <span className="min-w-0 truncate">
            {step.by === "owner" ? `You: ${step.title}` : step.title}
          </span>
        </li>
      ))}
    </ol>
  );
}

/** A result's mark: held ✓, failed ✗, uncertain ?; nothing when there was nothing to check. */
function Mark({ ok }: { ok: WorkResult["ok"] }) {
  if (ok === undefined) return null;
  return ok === true ? (
    <span className="text-green">✓</span>
  ) : ok === false ? (
    <span className="text-red">✗</span>
  ) : (
    <span className="text-amber">?</span>
  );
}

/** What the work achieved: label · value, its link and its mark. */
function WorkResults({ results }: { results: readonly WorkResult[] }) {
  return (
    <ul className="flex flex-col gap-1" aria-label="Results">
      {results.map((result, index) => (
        <li key={index} className="flex min-w-0 flex-wrap items-baseline gap-x-1 text-detail">
          <span className="font-medium text-ink">{result.label}</span>
          {result.value && <span className="text-ink-2">· {result.value}</span>}
          {result.url && (
            <a
              href={result.url}
              target="_blank"
              rel="noreferrer"
              className="min-w-0 truncate text-indigo hover:underline"
            >
              {result.url}
            </a>
          )}
          <Mark ok={result.ok} />
        </li>
      ))}
    </ul>
  );
}

/** The one request this work waits on the owner for: the earliest still pending. */
function usePendingRequest(workId: string): NeedsYouRequest | undefined {
  return (useDecisions().data ?? [])
    .filter((d) => d.work_item_id === workId)
    .toSorted((a, b) => a.requested_at.localeCompare(b.requested_at))[0];
}

/** Whether the business's browser is being driven for this work right now. */
function useDriven(workId: string) {
  const businessId = useBusinessId();
  const status = useQuery({
    queryKey: keys.browser(businessId),
    queryFn: () => api.browserStatus(businessId),
    refetchInterval: poll,
    retry: false,
  }).data;
  return status?.open === true && status.driving && status.driver === workId;
}

/**
 * A work item, as one live card drawn from the item as it is now: its title, who is on it,
 * the plan with the current step, its results, and one line of state with its one action.
 * In its thread it is pinned above the composer; anywhere else it opens the thread.
 */
export function WorkCard({ id, text, inThread }: { id: string; text?: string; inThread: boolean }) {
  const item = useWork().data?.find((w) => w.id === id);
  const nav = useNav();
  const owner = useEmployees().find((e) => e.id === item?.owner_employee_id);
  const run = useStatus(item?.owner_employee_id).data?.run;
  const stop = useStop();
  const working =
    item !== undefined &&
    item.taken_over_by === null &&
    Boolean(run && !run.stopped) &&
    run?.conversation === `work:${id}`;
  const done = item?.steps.filter((step) => step.state === "done").length ?? 0;
  const total = item?.steps.length ?? 0;
  const step = total ? `Step ${Math.min(done + 1, total)} of ${total}` : undefined;
  const frame = cn(
    "flex w-full flex-col gap-2.5 rounded-card border border-hairline bg-sheet px-3.5 py-3 text-left shadow-resting",
    !inThread &&
      "mx-auto max-w-[520px] cursor-pointer transition-colors duration-150 hover:bg-sheet-tint",
  );
  if (!item)
    return (
      <div data-testid="work-card" className={frame}>
        <span className="truncate text-body font-semibold text-ink">{text ?? "Work"}</span>
      </div>
    );
  const open = () => nav.openThread(id);
  // Right-click (or long-press) to take it over, hand it back, or mark it by hand.
  return (
    <WithWorkActions item={item}>
      <div
        data-testid="work-card"
        className={frame}
        {...(inThread
          ? {}
          : {
              onClick: (event: React.MouseEvent) => {
                // Its buttons act; anywhere else on the card opens the thread.
                if (!(event.target as HTMLElement).closest("button, a, input")) open();
              },
            })}
      >
        <div className="flex items-start gap-2">
          <div className="flex min-w-0 flex-1 flex-col">
            {inThread ? (
              <span className="truncate text-body font-semibold text-ink">{item.title}</span>
            ) : (
              <button
                type="button"
                onClick={open}
                title="Open the thread"
                className="truncate text-left text-body font-semibold text-ink"
              >
                {item.title}
              </button>
            )}
            {owner && <span className="truncate text-caption text-ink-3">{owner.name}</span>}
          </div>
          {step && (
            <span className="shrink-0 pt-0.5 text-caption text-ink-3" data-testid="work-step">
              {step}
            </span>
          )}
          {working && owner && (
            <Button size="compact" onClick={() => stop.mutate(owner.id)} aria-label="Stop">
              <Square className="fill-current" /> Stop
            </Button>
          )}
          {!inThread && !working && <ChevronRight className="mt-0.5 size-4 shrink-0 text-ink-3" />}
        </div>
        {item.steps.length > 0 && <WorkSteps steps={item.steps} />}
        {item.results.length > 0 && <WorkResults results={item.results} />}
        <StateLine item={item} working={working ? (run?.doing ?? "Working") : undefined} />
      </div>
    </WithWorkActions>
  );
}

/**
 * The card's one line of state, with its one action. `working` is what its employee is doing
 * now, while it works on this item (the plan above shows the step).
 */
function StateLine({ item, working }: { item: WorkItem; working: string | undefined }) {
  const person = usePerson();
  const members = useMembers();
  const request = usePendingRequest(item.id);
  const driven = useDriven(item.id);
  const start = useStartWork();
  const takeover = useTakeover();
  const nav = useNav();
  if (item.state === "completed") return <Line tone="done">Done</Line>;
  if (item.state === "cancelled") return <Line tone="quiet">Cancelled</Line>;
  if (item.taken_over_by !== null)
    return item.taken_over_by === person?.id ? (
      <Line tone="you" action={<HandBack onClick={() => takeover.mutate(item)} />}>
        You have it
      </Line>
    ) : (
      <Line tone="quiet">{takeoverTitle(item.taken_over_by, person?.id, members)}</Line>
    );
  if (request) return <YourTurn request={request} />;
  if (item.state === "proposed")
    return (
      <Line
        tone="you"
        action={
          <Button
            variant="aurora"
            size="compact"
            disabled={start.isPending}
            onClick={() => start.mutate(item)}
          >
            <Play /> Start
          </Button>
        }
      >
        Ready when you are
      </Line>
    );
  if (working !== undefined)
    return (
      <Line
        tone="working"
        action={
          driven && (
            <button
              type="button"
              onClick={() => nav.openBrowser(item.id)}
              className="text-caption font-medium text-indigo hover:underline"
            >
              Watch
            </button>
          )
        }
      >
        {working}…
      </Line>
    );
  if (item.state === "needs_decision")
    return <Line tone="you">Your turn{item.next_action ? `: ${item.next_action}` : ""}</Line>;
  if (item.state === "waiting")
    return (
      <Line tone="quiet">
        {item.wait_condition ? `Waiting on ${item.wait_condition}` : "Waiting"}
      </Line>
    );
  return item.next_action ? <Line tone="quiet">Up next: {item.next_action}</Line> : null;
}

const lineTone = {
  you: { icon: <CircleAlert className="size-3.5 shrink-0" />, color: "text-amber" },
  working: {
    icon: <span className="size-2 shrink-0 animate-pulse rounded-full bg-indigo" />,
    color: "text-indigo",
  },
  done: { icon: <CircleCheck className="size-3.5 shrink-0" />, color: "text-green" },
  quiet: { icon: <Clock className="size-3.5 shrink-0" />, color: "text-ink-3" },
};

function Line({
  tone,
  action,
  children,
}: {
  tone: keyof typeof lineTone;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="flex min-h-7 items-center gap-2 border-t border-hairline pt-2.5">
      <span
        className={cn(
          "flex min-w-0 flex-1 items-center gap-1.5 text-detail font-medium",
          lineTone[tone].color,
        )}
      >
        {lineTone[tone].icon}
        <span className="min-w-0 truncate text-ink" data-testid="work-state">
          {children}
        </span>
      </span>
      {action}
    </div>
  );
}

function HandBack({ onClick }: { onClick: () => void }) {
  return (
    <Button variant="aurora" size="compact" onClick={onClick}>
      <Undo2 /> Hand back
    </Button>
  );
}

/** "Your turn: <the ask>", with the request's one action and, for an approval, what it covers. */
function YourTurn({ request }: { request: NeedsYouRequest }) {
  const asked = ownerRequest(request);
  const [open, setOpen] = useState(false);
  // What an approval covers is what is approved: shown without asking for details.
  const shown =
    Boolean(spendOf(request)) ||
    (asked?.kind === "approve" && Boolean(asked.preview || asked.steps));
  const detailed =
    request.kind === "approve" || request.kind === "decision" || request.kind === "take_over";
  return (
    <div className="flex flex-col gap-2 border-t border-hairline pt-2.5">
      <span className="flex min-w-0 items-center gap-1.5 text-detail font-medium text-amber">
        {request.kind === "connect" && request.app ? (
          <AppLogo logo={request.app.logo} name={request.app.name} size={16} />
        ) : (
          <CircleAlert className="size-3.5 shrink-0" />
        )}
        <span className="min-w-0 truncate text-ink" data-testid="work-state">
          Your turn: {requestTitle(request)}
        </span>
      </span>
      {detailed && (open || shown) && <RequestDetails decision={request} compact />}
      <RequestActions decision={request} compact>
        {detailed && !shown && decisionFields(request).length > 0 && (
          <button
            type="button"
            onClick={() => setOpen(!open)}
            aria-expanded={open}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            {open ? "Hide details" : "Details"}
          </button>
        )}
      </RequestActions>
    </div>
  );
}
