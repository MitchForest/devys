import { useQuery } from "@tanstack/react-query";
import {
  FileText,
  LayoutGrid,
  ListChecks,
  MessageCircle,
  Search,
  type LucideIcon,
} from "lucide-react";
import { ref } from "../../protocol/ref.ts";
import { api } from "../app/api.ts";
import {
  useArtifacts,
  useBusinessId,
  useChiefOfStaff,
  useEmployees,
  useProjects,
  useWork,
} from "../app/data.ts";
import { keys } from "../app/query.ts";
import { useNav, type Layer, type Place } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { Command, CommandEmpty, CommandItem, CommandList } from "@/components/ui/command";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Command as CommandPrimitive } from "cmdk";

interface Target {
  id: string;
  title: string;
  detail: string;
  icon: LucideIcon;
  /** A conversation to go to, a thread to open, or a page or file to open beside it. */
  go: { place: Place } | { thread: string } | { layer: Layer };
}

/** ⌘K: jump to any conversation, thread, page or file in the current business by typing. */
export function CommandPalette() {
  const paletteOpen = useUi((state) => state.paletteOpen);
  const nav = useNav();
  const projects = useProjects().data;
  const employees = useEmployees();
  const work = useWork().data;
  const chiefOfStaff = useChiefOfStaff();
  const artifacts = useArtifacts();
  const businessId = useBusinessId();
  // The business folder's top level: what the owner and employees keep there.
  const files =
    useQuery({
      queryKey: keys.folder(businessId, null),
      queryFn: () => api.files(businessId),
      enabled: paletteOpen && Boolean(businessId),
    }).data?.entries ?? [];
  const pages = artifacts.filter((a) => a.content_type === "text/html" && a.version === a.versions);
  const targets: Target[] = [
    ...employees.map((e) => ({
      id: `direct-${e.id}`,
      title: e.name,
      detail: "Chat",
      icon: MessageCircle,
      go: {
        place: (e.id === chiefOfStaff?.id
          ? { kind: "home" }
          : { kind: "direct", employeeId: e.id }) as Place,
      },
    })),
    ...(projects ?? []).map((p) => ({
      id: p.id,
      title: p.name,
      detail: "Project",
      icon: LayoutGrid,
      go: { place: { kind: "project", id: p.id } as Place },
    })),
    ...pages.map((page) => ({
      id: `page-${page.id}`,
      title: page.title,
      detail: "Page",
      icon: FileText,
      go: { layer: { kind: "record", ref: ref("documents", "artifact", page.id) } as Layer },
    })),
    ...files
      .filter((entry) => entry.kind === "file" && !entry.name.startsWith("."))
      .map((entry) => ({
        id: `file-${entry.path}`,
        title: entry.name,
        detail: "File",
        icon: FileText,
        go: { layer: { kind: "record", ref: ref("documents", "file", entry.path) } as Layer },
      })),
    ...(work ?? []).map((item) => ({
      id: item.id,
      title: item.title,
      detail: "Thread",
      icon: ListChecks,
      go: { thread: item.id },
    })),
  ];
  const go = (target: Target["go"]) => {
    if ("place" in target) nav.selectPlace(target.place);
    else if ("thread" in target) nav.openThread(target.thread);
    else nav.openLayer(target.layer);
    ui.setPaletteOpen(false);
  };
  return (
    <Dialog open={paletteOpen} onOpenChange={ui.setPaletteOpen}>
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
              placeholder="Jump to a chat, project, thread or file"
              className="flex-1 bg-transparent text-heading text-ink outline-none placeholder:text-ink-3"
            />
          </div>
          <CommandList className="max-h-80 p-2">
            <CommandEmpty className="p-3 text-left text-body text-ink-3">No matches</CommandEmpty>
            {targets.map((target) => (
              <CommandItem
                key={target.id}
                value={`${target.title} ${target.detail} ${target.id}`}
                onSelect={() => go(target.go)}
                className="gap-3 rounded-small px-3 py-2 text-control text-ink data-[selected=true]:bg-sheet-tint [&>svg:last-child]:hidden"
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
