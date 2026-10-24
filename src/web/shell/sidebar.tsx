import {
  CirclePause,
  CirclePlay,
  EyeOff,
  MessageCircle,
  PanelLeft,
  Pencil,
  Pin,
  PinOff,
  Search,
  UserMinus,
  type LucideIcon,
} from "lucide-react";
import { useState } from "react";
import { tints } from "../../identity/contract.ts";
import type { Employee } from "../../identity/contract.ts";
import {
  useChiefOfStaff,
  useDecisions,
  useEmployees,
  useHome,
  useOwnerPhoto,
  usePerson,
  useSidebar,
  type SidebarRow,
  useActiveWork,
} from "../app/data.ts";
import { useSetProfile, useSidebarMark, useTogglePause } from "../app/mutations.ts";
import { conversationOf, useNav, usePlace, useWorkInPanel } from "../app/navigation.ts";
import { templateTitle } from "../app/names.ts";
import { ui } from "../app/ui.ts";
import { useMood } from "../app/workspace.tsx";
import { BusinessTile, PersonPortrait } from "../design/face.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { RetireDialog } from "../panel/desk.tsx";
import { useWorkLine } from "../panel/work-card.tsx";
import type { WorkItem } from "../../work/contract.ts";
import { listTime } from "../lib/format.ts";
import { PlaceLink } from "./links.tsx";
import { ConnectAppsButton } from "./connect-apps.tsx";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

/** A project's tile color, from its place in the list, the same everywhere it shows. */
export const projectTint = (index: number) => tints[(index + 1) % tints.length]!;

/**
 * The sidebar, as Messages lays one out: pinned tiles, then Projects (only while there are
 * any), then Chats with everyone else, most recent first. At the bottom, the owner (Settings)
 * and Connect apps. Above it, the toolbar: the sidebar toggle and Search (⌘K); nothing is
 * created from here, ⌘K does that. On a phone it is the list a conversation goes back to.
 */
export function Sidebar({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex h-full flex-col">
      {!compact && (
        <div
          role="toolbar"
          aria-label="Toolbar"
          className="flex items-center gap-0.5 px-3 pt-2.5 pb-1.5"
        >
          <SidebarButton label="Hide sidebar (⌃⌘S)" onClick={ui.toggleSidebar}>
            <PanelLeft className="size-[15px]" />
          </SidebarButton>
          <SearchButton />
        </div>
      )}
      <nav aria-label="Sidebar" className="flex min-h-0 flex-1 flex-col">
        <div className="min-h-0 flex-1 overflow-y-auto px-2.5 pb-3 [scrollbar-width:none]">
          <SidebarList />
        </div>
        <SidebarFooter />
      </nav>
    </div>
  );
}

function SidebarButton({
  label,
  children,
  ...props
}: React.ComponentProps<"button"> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label.replace(/ \(.*\)$/, "")}
      title={label}
      className="grid size-8 place-items-center rounded-full text-ink-2 transition hover:bg-track hover:text-ink"
      {...props}
    >
      {children}
    </button>
  );
}

/** The toolbar's search, beside the sidebar toggle: it opens ⌘K. */
export function SearchButton() {
  return (
    <SidebarButton label="Search (⌘K)" onClick={() => ui.setPaletteOpen(true)}>
      <Search className="size-[15px]" strokeWidth={2.1} />
    </SidebarButton>
  );
}

/** The owner's face (Settings) and Connect apps. */
function SidebarFooter() {
  const nav = useNav();
  const person = usePerson();
  const photo = useOwnerPhoto();
  return (
    <div className="flex shrink-0 items-center gap-2.5 px-3 pt-1.5 pb-3">
      <button
        type="button"
        aria-label="Settings"
        title="Settings"
        onClick={() => nav.openSettings()}
        className="shrink-0 rounded-full transition hover:opacity-85"
      >
        <PersonPortrait name={person?.display_name ?? ""} {...(photo ? { photo } : {})} size={34} />
      </button>
      <ConnectAppsButton />
    </div>
  );
}

/**
 * Team, Work (while any is going) and Projects (while one is active): the sidebar's body. Each
 * section has what the owner pinned at its top.
 */
function SidebarList() {
  const { team, projects } = useSidebar();
  const work = useActiveWork();
  return (
    <div className="flex flex-col gap-0.5">
      <SectionLabel>Team</SectionLabel>
      {team.map((row) => (
        <ChatRow key={row.key} row={row} />
      ))}
      {work.length > 0 && <SectionLabel>Work</SectionLabel>}
      {work.map(({ item, pinned }) => (
        <WorkRow key={item.id} item={item} pinned={pinned} />
      ))}
      {projects.length > 0 && <SectionLabel>Projects</SectionLabel>}
      {projects.map((row) => (
        <ChatRow key={row.key} row={row} />
      ))}
    </div>
  );
}

/**
 * A work item: who is on it, its title and where it stands ("Your turn: Connect Ramp" in amber,
 * "Opening godaddy.com…" while it runs). It opens beside whatever conversation is on screen;
 * right-click pins it to the top of Work, or unpins it.
 */
function WorkRow({ item, pinned }: { item: WorkItem; pinned: boolean }) {
  const nav = useNav();
  const mark = useSidebarMark();
  const open = useWorkInPanel() === item.id;
  const owner = useEmployees().find((e) => e.id === item.owner_employee_id);
  const line = useWorkLine(item);
  return (
    <ContextMenu>
      <ContextMenuTrigger render={<div />}>
        <button
          type="button"
          data-testid="work-row"
          aria-label={`${item.title}, ${line.text}`}
          aria-current={open ? "true" : undefined}
          onClick={() => nav.openWork(item.id)}
          className={cn(
            "flex w-full items-center gap-2.5 rounded-card px-2 py-[7px] text-left transition-[background-color,box-shadow] duration-200",
            open ? "bg-sheet shadow-resting" : "hover:bg-sheet/60",
          )}
        >
          {owner ? <EmployeePortrait employee={owner} size={28} /> : <span className="size-7" />}
          <span className="flex min-w-0 flex-1 flex-col gap-px">
            <span
              className={cn(
                "truncate text-control text-ink",
                line.tone === "you" ? "font-semibold" : "font-medium",
              )}
            >
              {item.title}
            </span>
            <span
              className={cn(
                "truncate text-detail",
                line.tone === "you"
                  ? "text-amber"
                  : line.tone === "working"
                    ? "text-indigo"
                    : line.tone === "done"
                      ? "text-green"
                      : "text-ink-3",
              )}
            >
              {line.text}
            </span>
          </span>
        </button>
      </ContextMenuTrigger>
      <ContextMenuContent className="min-w-40">
        <ContextMenuItem
          onClick={() => mark.mutate({ key: `work:${item.id}`, mark: { pinned: !pinned } })}
        >
          {pinned ? <PinOff /> : <Pin />} {pinned ? "Unpin" : "Pin"}
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  );
}

function SectionLabel({ children }: { children: string }) {
  return <h3 className="px-2.5 pt-3 pb-1 text-label font-medium text-ink-3">{children}</h3>;
}

/** Whether the row's conversation is the one on screen. */
function useSelected(row: SidebarRow) {
  const place = usePlace();
  const chiefOfStaff = useChiefOfStaff();
  return conversationOf(place, chiefOfStaff?.id) === row.key;
}

/** What waits on the owner from this row: everything for the Chief of Staff (Home), else theirs. */
function useWaiting(row: SidebarRow) {
  const decisions = useDecisions().data ?? [];
  const all = useHome().data?.needs_you.length ?? 0;
  if (row.kind !== "employee") return 0;
  return row.place.kind === "home"
    ? all
    : decisions.filter((d) => d.employee_id === row.employee.id).length;
}

const labelOf = (row: SidebarRow, waiting: number) =>
  waiting
    ? `${row.title}, ${waiting}`
    : row.unread
      ? `${row.title}, ${row.unread} unread`
      : row.title;

/** A row's face: the employee's, with their mood, or the project's tile. */
function RowFace({ row, size }: { row: SidebarRow; size: number }) {
  return row.kind === "employee" ? (
    <EmployeeFace employee={row.employee} size={size} />
  ) : (
    <span
      className="grid place-items-center rounded-[30%] bg-sheet"
      style={{ width: size, height: size }}
    >
      <BusinessTile name={row.title} tint={projectTint(row.index)} size={size} />
    </span>
  );
}

function EmployeeFace({ employee, size }: { employee: Employee; size: number }) {
  const mood = useMood(employee);
  return (
    <EmployeePortrait employee={employee} size={size} mood={employee.paused ? "asleep" : mood} />
  );
}

/** Unread is a blue dot; something waiting on the owner an amber count. */
function Mark({
  unread,
  waiting,
  className,
}: {
  unread: number;
  waiting: number;
  className?: string;
}) {
  if (waiting)
    return (
      <span
        className={cn(
          "grid h-[17px] min-w-[17px] shrink-0 place-items-center rounded-full bg-amber px-1 text-[10.5px] font-bold text-white tabular-nums",
          className,
        )}
      >
        {waiting}
      </span>
    );
  if (unread)
    return (
      <span
        data-testid="unread"
        className={cn("size-2.5 shrink-0 rounded-full bg-indigo", className)}
      />
    );
  return null;
}

/** Markdown's marks and links, reduced to the words a one-line preview shows. */
const plain = (text: string) =>
  text
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[*_`#>]+/g, "")
    .replace(/\s+/g, " ")
    .trim();

/** One conversation: face, name, time, its last line and an unread dot, as in Messages. */
function ChatRow({ row }: { row: SidebarRow }) {
  const selected = useSelected(row);
  const waiting = useWaiting(row);
  const person = usePerson();
  const bold = row.unread > 0 || waiting > 0;
  const preview =
    row.kind === "employee" && row.employee.paused
      ? "Paused"
      : row.last
        ? `${row.last.author === `person:${person?.id}` ? "You: " : ""}${plain(row.last.text)}`
        : row.kind === "employee" && templateTitle(row.employee.template) !== row.title
          ? templateTitle(row.employee.template)
          : "";
  return (
    <RowMenus row={row}>
      <PlaceLink
        place={row.place}
        aria-label={labelOf(row, waiting)}
        aria-current={selected ? "page" : undefined}
        className={cn(
          "flex w-full items-center gap-2.5 rounded-card px-2 py-[7px] text-left transition-[background-color,box-shadow] duration-200",
          selected ? "bg-sheet shadow-resting" : "hover:bg-sheet/60",
        )}
      >
        <RowFace row={row} size={40} />
        <span className="flex min-w-0 flex-1 flex-col gap-px">
          <span className="flex items-baseline gap-2">
            <span
              className={cn(
                "truncate text-control text-ink",
                bold ? "font-semibold" : "font-medium",
              )}
            >
              {row.title}
            </span>
            {row.last && (
              <span className="ml-auto shrink-0 text-caption text-ink-3">
                {listTime(row.last.created_at)}
              </span>
            )}
          </span>
          <span className="flex items-center gap-2">
            <span className={cn("truncate text-detail", bold ? "text-ink-2" : "text-ink-3")}>
              {preview}
            </span>
            <Mark unread={row.unread} waiting={waiting} className="ml-auto" />
          </span>
        </span>
      </PlaceLink>
    </RowMenus>
  );
}

interface RowAction {
  label: string;
  icon: LucideIcon;
  run: () => void;
  destructive?: boolean;
}

/** A row's actions: Pin, Mark as unread, Rename, Pause, Hide from sidebar, and Retire. */
function useRowActions(row: SidebarRow, open: (dialog: "rename" | "retire") => void) {
  const mark = useSidebarMark();
  const togglePause = useTogglePause();
  const actions: RowAction[][] = [
    [
      row.pinned
        ? {
            label: "Unpin",
            icon: PinOff,
            run: () => mark.mutate({ key: row.key, mark: { pinned: false } }),
          }
        : {
            label: "Pin",
            icon: Pin,
            run: () => mark.mutate({ key: row.key, mark: { pinned: true } }),
          },
      ...(row.unread === 0
        ? [
            {
              label: "Mark as unread",
              icon: MessageCircle,
              run: () => mark.mutate({ key: row.key, mark: { unread: true } }),
            },
          ]
        : []),
      ...(row.kind === "employee"
        ? [
            { label: "Rename…", icon: Pencil, run: () => open("rename") },
            row.employee.paused
              ? {
                  label: "Resume",
                  icon: CirclePlay,
                  run: () => togglePause.mutate(row.employee),
                }
              : {
                  label: "Pause",
                  icon: CirclePause,
                  run: () => togglePause.mutate(row.employee),
                },
          ]
        : []),
      {
        label: "Hide from sidebar",
        icon: EyeOff,
        run: () => mark.mutate({ key: row.key, mark: { hidden: true } }),
      },
    ],
    // The Chief of Staff stays; anyone else can be retired.
    row.kind === "employee" && row.place.kind !== "home"
      ? [{ label: "Retire…", icon: UserMinus, run: () => open("retire"), destructive: true }]
      : [],
  ];
  return actions.filter((group) => group.length > 0);
}

/** A row's actions, on right-click (or a two-finger click), as Messages. */
function RowMenus({ row, children }: { row: SidebarRow; children: React.ReactNode }) {
  const [dialog, setDialog] = useState<"rename" | "retire">();
  const groups = useRowActions(row, setDialog);
  return (
    <div className="relative">
      <ContextMenu>
        <ContextMenuTrigger render={<div />}>{children}</ContextMenuTrigger>
        <ContextMenuContent className="min-w-48">
          {groups.map((group, index) => (
            <div key={index}>
              {index > 0 && <ContextMenuSeparator />}
              {group.map((action) => (
                <ContextMenuItem
                  key={action.label}
                  onClick={action.run}
                  {...(action.destructive ? { variant: "destructive" as const } : {})}
                >
                  <action.icon /> {action.label}
                </ContextMenuItem>
              ))}
            </div>
          ))}
        </ContextMenuContent>
      </ContextMenu>
      {row.kind === "employee" && dialog === "rename" && (
        <RenameDialog employee={row.employee} close={() => setDialog(undefined)} />
      )}
      {row.kind === "employee" && (
        <RetireDialog
          employee={row.employee}
          open={dialog === "retire"}
          onOpenChange={(open) => setDialog(open ? "retire" : undefined)}
        />
      )}
    </div>
  );
}

function RenameDialog({ employee, close }: { employee: Employee; close: () => void }) {
  const setProfile = useSetProfile();
  const [name, setName] = useState(employee.name);
  return (
    <Dialog open onOpenChange={(open) => !open && close()}>
      <DialogContent
        showCloseButton={false}
        className="w-[360px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[360px]"
      >
        <form
          className="flex flex-col gap-4 p-5"
          onSubmit={(event) => {
            event.preventDefault();
            const next = name.trim();
            if (next && next !== employee.name)
              setProfile.mutate({ employee, change: { name: next } });
            close();
          }}
        >
          <DialogTitle className="text-heading font-semibold text-ink">
            Rename {employee.name}
          </DialogTitle>
          <Input
            autoFocus
            aria-label="Name"
            value={name}
            maxLength={80}
            onChange={(event) => setName(event.target.value)}
          />
          <div className="flex justify-end gap-2">
            <Button variant="quiet" onClick={close}>
              Cancel
            </Button>
            <Button type="submit" disabled={!name.trim()} className="bg-ink! text-sheet!">
              Rename
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
