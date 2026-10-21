import * as React from "react";
import { cn } from "@/lib/utils";
import { fieldLook } from "./input";

function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(fieldLook, "flex min-h-16 resize-y leading-[1.4]", className)}
      {...props}
    />
  );
}

export { Textarea };
