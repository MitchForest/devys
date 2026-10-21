import * as React from "react";
import { cn } from "@/lib/utils";
import { compactField, fieldLook, type Density } from "./input";

/** A native select in the field look: the platform's own menu, keyboard and labels. */
function NativeSelect({
  className,
  density = "regular",
  ...props
}: React.ComponentProps<"select"> & Density) {
  return (
    <select
      data-slot="native-select"
      className={cn(fieldLook, density === "compact" && compactField, className)}
      {...props}
    />
  );
}

export { NativeSelect };
