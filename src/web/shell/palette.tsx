import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import {
  FileText,
  Keyboard,
  LayoutGrid,
  ListChecks,
  Plug,
  Search,
  UserPlus,
  type LucideIcon,
} from "lucide-react";
import type { Employee } from "../../identity/contract.ts";
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
import { templateTitle } from "../app/names.ts";
import { useNav, type Layer, type Place } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { BusinessTile } from "../design/face.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { sections as settingsSections } from "./settings.tsx";
import { projectTint } from "./sidebar.tsx";
import { Command, CommandEmpty, CommandItem, CommandList } from "@/components/ui/command";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Command as CommandPrimitive } from "cmdk";

/** What a row shows on its left: an icon, an employee's face, or a project's tile. */
type Mark =
  | { icon: LucideIcon }
  | { employee: Employee }
  | { project: { name: string; index: number } };

interface Row {
  id: string;
  title: string;
  detail?: string;
  mark: Mark;
  run: () => void;
}

/** The shortcuts the web has, for the Keyboard shortcuts sheet. */
const shortcuts: [string, string][] = [
  ["⌘K", "Search"],
  ["⌘1 – ⌘9", "Run a row in Search"],
  ["⌃⌘S", "Show or hide the sidebar"],
  ["⌘[", "Back"],
  ["Esc", "Close a sheet, or go back one layer"],
  ["⌥⌘0", "Close the side panel"],
  ["⌘R", "Refresh"],
  ["⌘.", "Stop the employee answering"],
  ["Enter", "Send"],
  ["⇧Enter", "New line"],
  ["A – F", "Answer a question card"],
];

/** An employee's role in a few words: its title, or, when that is its name, what it does. */
const roleOf = (e: Employee) => {
  const title = templateTitle(e.template);
  if (title !== e.name) return title;
  return e.responsibilities.split(/(?<=[.!?])\s|\n/)[0]?.trim() || title;
};

const matches = (row: Row, query: string) => {
  const text = `${row.title} ${row.detail ?? ""}`.toLowerCase();
  return query
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .every((word) => text.includes(word));
};

/**
 * ⌘K, after Grok Bot's: a search field over rows (a face or icon, a title, an optional grey
 * line, a shortcut). Empty, it offers the Chief of Staff, the actions, Settings and everyone
 * else; typing filters those and the threads, pages and files of the current business.
 */
export function CommandPalette() {
  const paletteOpen = useUi((state) => state.paletteOpen);
  const [shortcutsOpen, setShortcutsOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState("");
  // Each opening starts from an empty search.
  const [wasOpen, setWasOpen] = useState(paletteOpen);
  if (paletteOpen !== wasOpen) {
    setWasOpen(paletteOpen);
    if (paletteOpen) {
      setQuery("");
      setSelected("");
    }
  }
  const nav = useNav();
  const projects = useProjects().data ?? [];
  const employees = useEmployees();
  const work = useWork().data ?? [];
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

  const close = () => ui.setPaletteOpen(false);
  const goTo = (place: Place) => () => nav.selectPlace(place);
  const openLayer = (layer: Layer) => () => nav.openLayer(layer);
  const employeeRow = (e: Employee): Row => ({
    id: `direct-${e.id}`,
    title: e.name,
    detail: roleOf(e),
    mark: { employee: e },
    run: goTo(e.id === chiefOfStaff?.id ? { kind: "home" } : { kind: "direct", employeeId: e.id }),
  });
  const actions: Row[] = [
    {
      id: "new-employee",
      title: "New employee",
      mark: { icon: UserPlus },
      run: () => ui.setHireOpen(true),
    },
    {
      id: "new-project",
      title: "New project",
      mark: { icon: LayoutGrid },
      run: () => ui.setProjectOpen(true),
    },
    {
      id: "connect-apps",
      title: "Connect apps",
      mark: { icon: Plug },
      run: () => ui.openConnect(),
    },
    {
      id: "keyboard-shortcuts",
      title: "Keyboard shortcuts",
      mark: { icon: Keyboard },
      run: () => setShortcutsOpen(true),
    },
    ...settingsSections.map((s): Row => ({
      id: `settings-${s.value}`,
      title: `Settings: ${s.title}`,
      detail: "Settings",
      mark: { icon: s.icon },
      run: () => nav.openSettings(s.value),
    })),
  ];
  const people: Row[] = [
    ...employees.filter((e) => e.id !== chiefOfStaff?.id).map(employeeRow),
    ...projects.map((p, index): Row => ({
      id: `project-${p.id}`,
      title: p.name,
      detail: "Project",
      mark: { project: { name: p.name, index } },
      run: goTo({ kind: "project", id: p.id }),
    })),
  ];
  const records: Row[] = [
    ...pages.map((page): Row => ({
      id: `page-${page.id}`,
      title: page.title,
      detail: "Page",
      mark: { icon: FileText },
      run: openLayer({ kind: "record", ref: ref("documents", "artifact", page.id) }),
    })),
    ...files
      .filter((entry) => entry.kind === "file" && !entry.name.startsWith("."))
      .map((entry): Row => ({
        id: `file-${entry.path}`,
        title: entry.name,
        detail: "File",
        mark: { icon: FileText },
        run: openLayer({ kind: "record", ref: ref("documents", "file", entry.path) }),
      })),
    ...work.map((item): Row => ({
      id: `thread-${item.id}`,
      title: item.title,
      detail: "Thread",
      mark: { icon: ListChecks },
      run: () => nav.openThread(item.id),
    })),
  ];
  const all = [...(chiefOfStaff ? [employeeRow(chiefOfStaff)] : []), ...actions, ...people];
  const rows = query.trim() ? [...all, ...records].filter((row) => matches(row, query)) : all;
  const current = rows.some((row) => row.id === selected) ? selected : (rows[0]?.id ?? "");

  const run = (row: Row) => {
    close();
    row.run();
  };
  return (
    <>
      <Dialog open={paletteOpen} onOpenChange={ui.setPaletteOpen}>
        <DialogContent
          showCloseButton={false}
          className="top-[90px] w-[560px] max-w-[calc(100%-2rem)] translate-y-0 gap-0 overflow-hidden rounded-card! bg-sheet p-0 shadow-raised ring-1 ring-hairline sm:max-w-[560px]"
        >
          <DialogTitle className="sr-only">Search</DialogTitle>
          <Command
            className="rounded-none bg-transparent p-0"
            shouldFilter={false}
            loop
            value={current}
            onValueChange={setSelected}
            onKeyDown={(event) => {
              // ⌘1…⌘9 run the first nine rows shown.
              const digit = /^Digit([1-9])$/.exec(event.code)?.[1];
              if (!event.metaKey || !digit) return;
              const row = rows[Number(digit) - 1];
              if (!row) return;
              event.preventDefault();
              event.stopPropagation();
              run(row);
            }}
          >
            <div className="flex items-center gap-2.5 border-b border-hairline px-4 py-3.5">
              <Search className="size-4 text-ink-3" />
              <CommandPrimitive.Input
                autoFocus
                value={query}
                onValueChange={(next) => {
                  setQuery(next);
                  setSelected("");
                }}
                placeholder="Search"
                className="flex-1 bg-transparent text-heading text-ink outline-none placeholder:text-ink-3"
              />
            </div>
            <CommandList className="max-h-[min(420px,60dvh)] p-1.5">
              <CommandEmpty className="p-3 text-left text-body text-ink-3">No matches</CommandEmpty>
              {rows.map((row, index) => (
                <CommandItem
                  key={row.id}
                  value={row.id}
                  onSelect={() => run(row)}
                  className="gap-3 rounded-small px-2.5 py-1.5 text-control text-ink data-[selected=true]:bg-sheet-tint [&>svg:last-child]:hidden"
                >
                  <RowMark mark={row.mark} />
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate">{row.title}</span>
                    {row.detail && (
                      <span className="truncate text-detail text-ink-3">{row.detail}</span>
                    )}
                  </span>
                  {index < 9 && (
                    <kbd className="ml-auto shrink-0 rounded-[6px] bg-track px-1.5 py-0.5 font-sans text-caption text-ink-3">
                      ⌘{index + 1}
                    </kbd>
                  )}
                </CommandItem>
              ))}
            </CommandList>
          </Command>
        </DialogContent>
      </Dialog>
      <Dialog open={shortcutsOpen} onOpenChange={setShortcutsOpen}>
        <DialogContent className="w-[400px] max-w-[calc(100%-2rem)] gap-3 rounded-card! bg-sheet p-5 shadow-raised sm:max-w-[400px]">
          <DialogTitle className="text-heading font-semibold text-ink">
            Keyboard shortcuts
          </DialogTitle>
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-control">
            {shortcuts.map(([keys, what]) => (
              <div key={keys} className="contents">
                <dt>
                  <kbd className="rounded-[6px] bg-track px-1.5 py-0.5 font-sans text-caption text-ink-2">
                    {keys}
                  </kbd>
                </dt>
                <dd className="text-ink-2">{what}</dd>
              </div>
            ))}
          </dl>
        </DialogContent>
      </Dialog>
    </>
  );
}

function RowMark({ mark }: { mark: Mark }) {
  if ("employee" in mark) return <EmployeePortrait employee={mark.employee} size={26} />;
  if ("project" in mark)
    return (
      <BusinessTile name={mark.project.name} tint={projectTint(mark.project.index)} size={26} />
    );
  return (
    <span className="grid size-[26px] shrink-0 place-items-center">
      <mark.icon className="size-4 text-ink-2" />
    </span>
  );
}
