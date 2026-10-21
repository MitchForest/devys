import { Tabs as TabsPrimitive } from "@base-ui/react/tabs";
import { cn } from "@/lib/utils";

/** Tabs: choices in an inset track; the selection rises out of it as a white thumb. */
function Tabs({ className, ...props }: TabsPrimitive.Root.Props) {
  return (
    <TabsPrimitive.Root data-slot="tabs" className={cn("flex flex-col", className)} {...props} />
  );
}

function TabsList({ className, ...props }: TabsPrimitive.List.Props) {
  return (
    <div className="max-w-full overflow-x-auto [scrollbar-width:none]">
      <TabsPrimitive.List
        data-slot="tabs-list"
        className={cn("inline-flex gap-0.5 rounded-workspace bg-well p-1", className)}
        {...props}
      />
    </div>
  );
}

function TabsTrigger({ className, ...props }: TabsPrimitive.Tab.Props) {
  return (
    <TabsPrimitive.Tab
      data-slot="tabs-trigger"
      className={cn(
        "cursor-pointer whitespace-nowrap rounded-control px-3.5 py-[7px] text-control font-medium text-ink-2 transition duration-200 ease-[cubic-bezier(.3,1.3,.5,1)] outline-none hover:text-ink focus-visible:ring-2 focus-visible:ring-indigo/40 data-active:bg-sheet data-active:text-ink data-active:shadow-[0_0.5px_0.5px_rgb(0_0_0/0.05),0_2px_6px_rgb(0_0_0/0.07)]",
        className,
      )}
      {...props}
    />
  );
}

function TabsContent({ className, ...props }: TabsPrimitive.Panel.Props) {
  return <TabsPrimitive.Panel data-slot="tabs-content" className={className} {...props} />;
}

export { Tabs, TabsContent, TabsList, TabsTrigger };
