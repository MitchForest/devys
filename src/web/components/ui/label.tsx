import * as React from "react";
import { cn } from "@/lib/utils";

/** A form label in the Devys label style; wrapping its control names it. */
function Label({ className, ...props }: React.ComponentProps<"label">) {
  return (
    // oxlint-disable-next-line jsx-a11y/label-has-associated-control -- callers wrap or point at the control
    <label
      data-slot="label"
      className={cn("text-label font-medium text-ink-3", className)}
      {...props}
    />
  );
}

/** A labelled control: the label names it, and the hint sits below. */
function Field({
  label,
  hint,
  children,
  className,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
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

export { Field, Label };
