import * as React from "react";
import { Switch as SwitchPrimitive } from "@base-ui/react/switch";
import { cn } from "@/lib/utils";

/** An on/off switch with its label beside it, as native `Toggle`. */
function Switch({
  checked,
  onCheckedChange,
  children,
  className,
}: {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  children?: React.ReactNode;
  className?: string;
}) {
  const id = React.useId();
  return (
    <span
      className={cn(
        "flex w-fit cursor-pointer items-center gap-2.5 text-control text-ink",
        className,
      )}
    >
      <SwitchPrimitive.Root
        data-slot="switch"
        checked={checked}
        onCheckedChange={(next) => onCheckedChange(next)}
        aria-labelledby={children ? id : undefined}
        className="relative h-[22px] w-[38px] shrink-0 cursor-pointer rounded-full bg-track transition-colors outline-none focus-visible:ring-2 focus-visible:ring-indigo data-checked:bg-green"
      >
        <SwitchPrimitive.Thumb className="absolute top-0.5 left-0.5 size-[18px] rounded-full bg-white shadow-resting transition-transform data-checked:translate-x-4" />
      </SwitchPrimitive.Root>
      {children && (
        <span id={id} onClick={() => onCheckedChange(!checked)}>
          {children}
        </span>
      )}
    </span>
  );
}

export { Switch };
