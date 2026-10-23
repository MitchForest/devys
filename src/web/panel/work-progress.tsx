import { Circle, CircleAlert, CircleCheck, CircleDot } from "lucide-react";
import {
  progressText,
  type WorkItem,
  type WorkResult,
  type WorkStep,
} from "../../work/contract.ts";
import { useWork } from "../app/data.ts";
import { cn } from "@/lib/utils";

const stepIcon = {
  todo: <Circle className="size-3.5 shrink-0 text-ink-3" />,
  doing: <CircleDot className="size-3.5 shrink-0 text-indigo" />,
  done: <CircleCheck className="size-3.5 shrink-0 text-green" />,
  blocked: <CircleAlert className="size-3.5 shrink-0 text-red" />,
} satisfies Record<WorkStep["state"], unknown>;

/** The plan an employee shows while the work takes time, each step with where it stands. */
export function WorkSteps({ steps }: { steps: readonly WorkStep[] }) {
  return (
    <ol className="flex flex-col gap-1" aria-label="Steps">
      {steps.map((step, index) => (
        <li
          key={index}
          data-state={step.state}
          className={cn(
            "flex items-center gap-2 text-detail",
            step.state === "todo" ? "text-ink-3" : "text-ink",
            step.state === "doing" && "font-medium",
          )}
        >
          {stepIcon[step.state]}
          <span className="min-w-0 truncate">{step.title}</span>
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

/** What the work achieved, in the words of `resultText`: label · value, its link and its mark. */
export function WorkResults({ results }: { results: readonly WorkResult[] }) {
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

/** Steps and results as a work item has them now; nothing when it has neither. */
export function WorkProgress({ item }: { item: WorkItem }) {
  if (!item.steps.length && !item.results.length) return null;
  return (
    <div className="flex flex-col gap-2.5">
      {item.steps.length > 0 && <WorkSteps steps={item.steps} />}
      {item.results.length > 0 && <WorkResults results={item.results} />}
    </div>
  );
}

/**
 * A work item's card in its thread: one per item, drawn from the item as it is now, so each
 * change to its steps or results updates it in place.
 */
export function WorkProgressCard({ id, text }: { id: string; text: string }) {
  const item = useWork().data?.find((w) => w.id === id);
  return (
    <div
      data-testid="work-progress"
      className="mx-auto flex w-full max-w-[520px] flex-col gap-2 rounded-card border border-hairline bg-sheet px-3 py-2.5 shadow-resting"
    >
      <span className="truncate text-caption font-medium text-ink-3">
        {item ? (progressText(item.steps) ?? "Results") : text}
      </span>
      {item && <WorkProgress item={item} />}
    </div>
  );
}
