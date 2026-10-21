import * as React from "react";
import { Input as InputPrimitive } from "@base-ui/react/input";
import { cn } from "@/lib/utils";

/** Text inputs, text areas and selects share one inset look, as native form fields. */
export const fieldLook =
  "w-full min-w-0 rounded-control border border-transparent bg-well px-2.5 py-[7px] text-body text-ink transition-[color,box-shadow] duration-200 outline-none placeholder:text-ink-3 focus-visible:ring-2 focus-visible:ring-indigo/40 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive";
/** The smaller field that sits in a bar under a layer: a comment, a URL, a recipient. */
export const compactField = "rounded-small bg-sheet-tint py-1.5 text-detail";

/** `density="compact"` for a field in a bar; the regular field otherwise. */
export type Density = { density?: "regular" | "compact" };

function Input({
  className,
  type,
  density = "regular",
  ...props
}: React.ComponentProps<"input"> & Density) {
  return (
    <InputPrimitive
      type={type}
      data-slot="input"
      className={cn(
        fieldLook,
        density === "compact" && compactField,
        "file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground",
        className,
      )}
      {...props}
    />
  );
}

export { Input };
