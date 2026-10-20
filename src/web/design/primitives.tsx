import { AlertCircle, Check, Clock, Ellipsis, X } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export type Tone =
  | "needsYou"
  | "inProgress"
  | "done"
  | "failed"
  | "expired"
  | "checking"
  | "waiting";
const toneColor: Record<Tone, string> = {
  needsYou: "text-amber",
  inProgress: "text-indigo",
  done: "text-green",
  failed: "text-red",
  expired: "text-gray",
  checking: "text-gray",
  waiting: "text-gray",
};
const toneFill: Record<Tone, string> = {
  needsYou: "bg-amber",
  inProgress: "bg-indigo",
  done: "bg-green",
  failed: "bg-red",
  expired: "bg-gray",
  checking: "bg-gray",
  waiting: "bg-gray",
};

function Glyph({ tone, size }: { tone: Tone; size: number }) {
  const icon = Math.round(size * 0.55);
  if (tone === "inProgress")
    return (
      <span
        className="animate-[spin_2.4s_linear_infinite] rounded-full border-[1.6px] border-dashed border-indigo"
        style={{ width: size, height: size }}
      />
    );
  const Icon =
    tone === "done"
      ? Check
      : tone === "needsYou"
        ? AlertCircle
        : tone === "failed"
          ? X
          : tone === "checking"
            ? Ellipsis
            : Clock;
  return (
    <span
      className={cn(
        "grid place-items-center text-white",
        toneFill[tone],
        tone === "done" ? "rounded-[4.5px]" : "rounded-full",
      )}
      style={{ width: size, height: size }}
    >
      <Icon size={icon} strokeWidth={3.5} />
    </span>
  );
}

/** Outcome status as an icon plus colored text on a white pill; never a filled block. */
export function StatusChip({
  children,
  tone,
  small,
}: {
  children: ReactNode;
  tone: Tone;
  small?: boolean;
}) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center rounded-full bg-sheet shadow-resting",
        toneColor[tone],
        small
          ? "gap-1 py-0.5 pr-[7px] pl-[3px] text-[10.5px] font-semibold"
          : "gap-1.5 py-1 pr-2.5 pl-[5px] text-caption font-medium",
      )}
    >
      <Glyph tone={tone} size={small ? 12 : 16} />
      {children}
    </span>
  );
}

export function LiveTag() {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-[5px] rounded-full bg-green-tint px-[9px] py-[3px] text-caption font-medium text-green"
      aria-label="Live data"
    >
      <span className="size-1.5 rounded-full bg-green" />
      Live
    </span>
  );
}

export function SectionHeader({
  title,
  count,
  children,
}: {
  title: string;
  count?: number;
  children?: ReactNode;
}) {
  return (
    <div className="flex items-baseline gap-2" role="heading" aria-level={2}>
      <span className="text-heading font-semibold text-ink">{title}</span>
      {count !== undefined && <span className="text-body text-ink-3">{count}</span>}
      {children && <span className="ml-auto self-center">{children}</span>}
    </div>
  );
}

/** Nothing here yet: quiet text inside a dashed outline. */
export function EmptyNote({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-card border-[1.2px] border-dashed border-ink-3/60 p-4 text-body text-ink-3">
      {children}
    </p>
  );
}

/** A resting card inside a sheet: tinted fill that lifts to white on hover. */
export function Card({
  children,
  className,
  padding = 16,
}: {
  children: ReactNode;
  className?: string;
  padding?: number;
}) {
  return (
    <div
      className={cn(
        "rounded-card bg-sheet-tint transition duration-150 ease-out hover:-translate-y-px hover:bg-sheet hover:shadow-raised",
        className,
      )}
      style={{ padding }}
    >
      {children}
    </div>
  );
}

export function Metric({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <Card>
      <div className="flex flex-col gap-1">
        <span className="text-detail text-ink-3">{label}</span>
        <span className="text-title font-semibold tabular-nums text-ink">{value}</span>
        <span className="truncate text-detail text-ink-2">{note}</span>
      </div>
    </Card>
  );
}

/** The page scaffold: generous margins, a readable column, consistent gaps. */
export function PageBody({ children }: { children: ReactNode }) {
  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[840px] animate-in fade-in slide-in-from-bottom-1.5 flex-col gap-8 px-10 pt-8 pb-10 duration-300 max-sm:px-4">
        {children}
      </div>
    </div>
  );
}

export function PageHeader({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex flex-col gap-0.5">
        <h1 className="text-title font-semibold text-ink">{title}</h1>
        {subtitle && <p className="text-body text-ink-2">{subtitle}</p>}
      </div>
      {children}
    </div>
  );
}
