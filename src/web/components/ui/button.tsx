import { Button as ButtonPrimitive } from "@base-ui/react/button";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

/**
 * The one button. Devys kinds: `aurora` sends an agent to work or approves; `raised` is the
 * default secondary; `quiet` sits in toolbars and rows; `dashed` is not real yet; `toolbar` is
 * a square icon button. The other variants serve the shadcn components built on it.
 */
const buttonVariants = cva(
  "group/button relative inline-flex shrink-0 items-center justify-center gap-1.5 overflow-hidden border border-transparent bg-clip-padding font-medium whitespace-nowrap transition duration-150 ease-out outline-none select-none focus-visible:ring-2 focus-visible:ring-indigo/40 disabled:pointer-events-none disabled:opacity-45 aria-invalid:border-destructive [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        raised:
          "rounded-full bg-sheet text-ink shadow-resting hover:-translate-y-px active:scale-[0.97]",
        aurora:
          "aurora rounded-full text-white shadow-[0_4px_8px_rgb(90_104_240/0.35)] hover:-translate-y-px active:scale-[0.97]",
        quiet: "rounded-full text-ink-2 hover:bg-track active:scale-[0.97]",
        dashed: "rounded-full border-[1.5px] border-dashed border-ink-3 text-ink-2",
        toolbar: "rounded-small text-ink-2 hover:bg-track hover:text-ink",
        default: "rounded-control bg-primary text-primary-foreground hover:bg-primary/80",
        outline:
          "rounded-control border-border bg-background hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:bg-transparent dark:hover:bg-input/30",
        secondary:
          "rounded-control bg-secondary text-secondary-foreground hover:bg-[color-mix(in_oklch,var(--secondary),var(--foreground)_5%)] aria-expanded:bg-secondary aria-expanded:text-secondary-foreground",
        ghost:
          "rounded-control hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:hover:bg-muted/50",
        destructive:
          "rounded-control bg-destructive/10 text-destructive hover:bg-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        regular: "px-3.5 py-2 text-control [&_svg:not([class*='size-'])]:size-[14px]",
        compact: "px-2.5 py-1.5 text-control [&_svg:not([class*='size-'])]:size-[14px]",
        toolbar: "size-[30px] p-0 [&_svg:not([class*='size-'])]:size-[15px]",
        default: "h-8 px-3 text-sm [&_svg:not([class*='size-'])]:size-4",
        xs: "h-6 gap-1 px-2.5 text-xs [&_svg:not([class*='size-'])]:size-3",
        sm: "h-7 gap-1 px-3 text-sm [&_svg:not([class*='size-'])]:size-4",
        lg: "h-9 px-4 text-sm [&_svg:not([class*='size-'])]:size-4",
        icon: "size-8 [&_svg:not([class*='size-'])]:size-4",
        "icon-xs": "size-6 [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-7 [&_svg:not([class*='size-'])]:size-4",
        "icon-lg": "size-9 [&_svg:not([class*='size-'])]:size-4",
      },
    },
    defaultVariants: {
      variant: "raised",
      size: "regular",
    },
  },
);

function Button({
  className,
  variant = "raised",
  size = "regular",
  children,
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    >
      {variant === "aurora" ? (
        <>
          <span className="pointer-events-none absolute inset-y-0 -left-16 w-14 bg-gradient-to-r from-transparent via-white/35 to-transparent transition-transform duration-700 ease-out group-hover/button:translate-x-48 motion-reduce:hidden" />
          <span className="relative inline-flex items-center gap-1.5">{children}</span>
        </>
      ) : (
        children
      )}
    </ButtonPrimitive>
  );
}

/** A square toolbar icon button, named by its label (also its tooltip). */
function ToolbarIconButton({
  label,
  ...props
}: Omit<ButtonPrimitive.Props, "aria-label"> & { label: string }) {
  return <Button variant="toolbar" size="toolbar" aria-label={label} title={label} {...props} />;
}

export { Button, buttonVariants, ToolbarIconButton };
