import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Text inputs, text areas and selects share one inset look, as native form fields. */
export const fieldClass =
  "w-full min-w-0 rounded-control bg-well px-2.5 py-[7px] text-body text-ink outline-none placeholder:text-ink-3 focus-visible:ring-2 focus-visible:ring-indigo/40";

/** A labelled control; the label alone names it, and the hint sits below. */
export function Field({
  label,
  hint,
  children,
  className,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <label className="flex flex-col gap-1.5">
        <span className="text-label font-medium text-ink-3">{label}</span>
        {children}
      </label>
      {hint && <span className="text-detail text-ink-3">{hint}</span>}
    </div>
  );
}

/** An on/off switch with its label, as native `Toggle`. */
export function Switch({
  checked,
  onChange,
  children,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  children: ReactNode;
}) {
  return (
    <label className="flex w-fit cursor-pointer items-center gap-2.5 text-control text-ink">
      <input
        type="checkbox"
        role="switch"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className="peer sr-only"
      />
      <span className="relative h-[22px] w-[38px] shrink-0 rounded-full bg-track transition-colors peer-checked:bg-green peer-focus-visible:ring-2 peer-focus-visible:ring-indigo after:absolute after:top-0.5 after:left-0.5 after:size-[18px] after:rounded-full after:bg-white after:shadow-resting after:transition-transform peer-checked:after:translate-x-4" />
      {children}
    </label>
  );
}
