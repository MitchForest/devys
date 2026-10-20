import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Aurora sends an agent to work or approves; raised is the default secondary; quiet sits in toolbars. */
export function DevysButton({
  kind = "raised",
  compact,
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  kind?: "aurora" | "raised" | "quiet" | "dashed";
  compact?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      className={cn(
        "group relative inline-flex shrink-0 items-center gap-1.5 overflow-hidden rounded-full text-control font-medium transition duration-150 ease-out active:scale-[0.97] disabled:pointer-events-none disabled:opacity-45 [&_svg]:size-[14px]",
        compact ? "px-2.5 py-1.5" : "px-3.5 py-2",
        kind === "aurora" &&
          "aurora text-white shadow-[0_4px_8px_rgb(90_104_240/0.35)] hover:-translate-y-px",
        kind === "raised" && "bg-sheet text-ink shadow-resting hover:-translate-y-px",
        kind === "quiet" && "text-ink-2 hover:bg-track",
        kind === "dashed" && "border-[1.5px] border-dashed border-ink-3 text-ink-2",
        className,
      )}
      {...props}
    >
      {kind === "aurora" && (
        <span className="pointer-events-none absolute inset-y-0 -left-16 w-14 bg-gradient-to-r from-transparent via-white/35 to-transparent transition-transform duration-700 ease-out group-hover:translate-x-48 motion-reduce:hidden" />
      )}
      <span className="relative inline-flex items-center gap-1.5">{children}</span>
    </button>
  );
}

/** A 30px square toolbar icon button with a quiet hover fill. */
export function ToolbarIconButton({
  label,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className="grid size-[30px] place-items-center rounded-[9px] text-ink-2 transition duration-150 hover:bg-track hover:text-ink [&_svg]:size-[15px]"
      {...props}
    >
      {children}
    </button>
  );
}
