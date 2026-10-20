import {
  CircleDollarSign,
  LayoutGrid,
  Link,
  ListChecks,
  MessageCircle,
  ScanFace,
  Search,
  Sun,
  UserRound,
  type LucideIcon,
} from "lucide-react";
import { useWorkspace, valueOf, type Page } from "../app/workspace.tsx";
import { Command, CommandEmpty, CommandItem, CommandList } from "@/components/ui/command";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Command as CommandPrimitive } from "cmdk";

interface Target {
  id: string;
  title: string;
  detail: string;
  icon: LucideIcon;
  /** A page to open, or a work item for the right panel. */
  page: Page | { work: string };
}

/** ⌘K: jump to any page in the current business by typing. */
export function CommandPalette() {
  const { paletteOpen, actions, spaces, employees, work } = useWorkspace();
  const targets: Target[] = [
    { id: "today", title: "Today", detail: "Home", icon: Sun, page: { kind: "today" } },
    {
      id: "approvals",
      title: "Approvals",
      detail: "Home",
      icon: ScanFace,
      page: { kind: "approvals" },
    },
    {
      id: "work",
      title: "Work",
      detail: "All commitments",
      icon: ListChecks,
      page: { kind: "work", filter: "all" },
    },
    {
      id: "money",
      title: "Money",
      detail: "Spend",
      icon: CircleDollarSign,
      page: { kind: "money" },
    },
    {
      id: "apps",
      title: "Apps",
      detail: "Installed",
      icon: LayoutGrid,
      page: { kind: "apps", section: "installed" },
    },
    {
      id: "connections",
      title: "Connections",
      detail: "Accounts",
      icon: Link,
      page: { kind: "apps", section: "connections" },
    },
    ...(valueOf(spaces) ?? []).map((s) => ({
      id: s.id,
      title: s.name,
      detail: "Space",
      icon: LayoutGrid,
      page: { kind: "space", id: s.id } as Page,
    })),
    ...employees.map((e) => ({
      id: `direct-${e.id}`,
      title: e.name,
      detail: "Direct message",
      icon: MessageCircle,
      page: { kind: "direct", employeeId: e.id } as Page,
    })),
    ...employees.map((e) => ({
      id: e.id,
      title: e.name,
      detail: "Team",
      icon: UserRound,
      page: { kind: "employee", id: e.id } as Page,
    })),
    ...(valueOf(work) ?? []).map((item) => ({
      id: item.id,
      title: item.title,
      detail: "Task",
      icon: ListChecks,
      page: { work: item.id },
    })),
  ];
  const go = (page: Target["page"]) => {
    if ("work" in page) actions.openWork(page.work);
    else actions.selectPage(page);
    actions.setPaletteOpen(false);
  };
  return (
    <Dialog open={paletteOpen} onOpenChange={actions.setPaletteOpen}>
      <DialogContent
        showCloseButton={false}
        className="top-[90px] w-[520px] max-w-[calc(100%-2rem)] translate-y-0 gap-0 overflow-hidden rounded-card! bg-sheet p-0 shadow-raised ring-0 sm:max-w-[520px]"
      >
        <DialogTitle className="sr-only">Jump to</DialogTitle>
        <Command className="rounded-none bg-transparent p-0" loop>
          <div className="flex items-center gap-2.5 border-b border-hairline p-4">
            <Search className="size-4 text-ink-3" />
            <CommandPrimitive.Input
              autoFocus
              placeholder="Jump to a page, space or employee"
              className="flex-1 bg-transparent text-heading text-ink outline-none placeholder:text-ink-3"
            />
          </div>
          <CommandList className="max-h-80 p-2">
            <CommandEmpty className="p-3 text-left text-body text-ink-3">No matches</CommandEmpty>
            {targets.map((target) => (
              <CommandItem
                key={target.id}
                value={`${target.title} ${target.detail} ${target.id}`}
                onSelect={() => go(target.page)}
                className="gap-3 rounded-[9px] px-3 py-2 text-control text-ink data-[selected=true]:bg-sheet-tint [&>svg:last-child]:hidden"
              >
                <target.icon className="size-4 w-5 text-ink-2" />
                <span>{target.title}</span>
                <span className="ml-auto text-ink-3">{target.detail}</span>
              </CommandItem>
            ))}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}
