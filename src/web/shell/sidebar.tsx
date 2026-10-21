import {
  Code2,
  FileText,
  House,
  LayoutGrid,
  ListChecks,
  Plus,
  Search,
  UserPlus,
  type LucideIcon,
} from "lucide-react";
import type { ReactNode } from "react";
import type { Commitment, Employee } from "../app/api.ts";
import { moodOf } from "../app/names.ts";
import { samePlace, useWorkspace, valueOf, type Layer, type Place } from "../app/workspace.tsx";
import { BusinessTile } from "../design/face.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

const tints = ["blue", "orange", "green", "purple", "pink"];
/** A project's tile color, from its place in the list, the same everywhere it shows. */
export const projectTint = (index: number) => tints[(index + 1) % tints.length]!;
/** The icon an app names in its manifest. */
export const appIcons: Record<string, LucideIcon> = {
  documents: FileText,
  code: Code2,
};

type Trailing = "none" | "working" | "needsYou" | "paused";

/**
 * One sidebar: Home, Projects, Team and the business's apps. Each row but an app opens a
 * conversation; an app opens as a layer beside the conversation on screen.
 */
export function Sidebar() {
  const state = useWorkspace();
  const { business, actions } = state;
  return (
    <nav aria-label="Sidebar" className="h-full overflow-y-auto px-2.5 pb-4 [scrollbar-width:none]">
      <div className="flex items-center gap-1 px-1 pt-2.5 pb-2">
        <h2 className="min-w-0 flex-1 truncate px-1.5 text-heading font-semibold text-ink">
          {business?.name}
        </h2>
        <button
          type="button"
          aria-label="Search"
          title="Search (⌘K)"
          onClick={() => actions.setPaletteOpen(true)}
          className="grid size-7 place-items-center rounded-[8px] text-ink-2 hover:bg-track hover:text-ink"
        >
          <Search className="size-[15px]" strokeWidth={2} />
        </button>
        <NewMenu />
      </div>
      <SidebarSections />
    </nav>
  );
}

/** **New**: a project, a hire or a task. A message needs nothing: the composer is always there. */
function NewMenu() {
  const { actions } = useWorkspace();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        aria-label="New"
        title="New"
        className="grid size-7 place-items-center rounded-[8px] text-ink-2 hover:bg-track hover:text-ink"
      >
        <Plus className="size-4" strokeWidth={2} />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-auto min-w-44">
        <DropdownMenuItem onClick={() => actions.setProjectOpen(true)}>
          <LayoutGrid /> New project
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => actions.newTask()}>
          <ListChecks /> New task
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => actions.setHireOpen(true)}>
          <UserPlus /> Hire
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** The sections, also the phone's lists. Headings appear only when they have rows. */
export function SidebarSections() {
  const state = useWorkspace();
  const { employees, actions, unreadOf, operations, home, apps } = state;
  const projects = valueOf(state.projects) ?? [];
  const needsYou = valueOf(home)?.needsYou.length ?? 0;
  const threads = useNestedThreads();
  const trailing = useTrailing();
  const shownApps = (valueOf(apps) ?? []).filter((app) => app.visible && app.pinned);
  return (
    <div className="flex flex-col gap-0.5">
      <PlaceRow
        place={{ kind: "home" }}
        title="Home"
        icon={House}
        count={needsYou}
        unread={operations ? unreadOf(`direct:${operations.id}`) : 0}
      />
      {threads(null).map((item) => (
        <ThreadRow key={item.id} item={item} />
      ))}
      {projects.length > 0 && (
        <SectionLabel action={{ label: "New project", run: () => actions.setProjectOpen(true) }}>
          Projects
        </SectionLabel>
      )}
      {projects.map((project, index) => (
        <div key={project.id} className="flex flex-col gap-0.5">
          <PlaceRow
            place={{ kind: "project", id: project.id }}
            title={project.name}
            unread={unreadOf(`project:${project.id}`)}
          >
            <BusinessTile name={project.name} tint={projectTint(index)} size={20} />
          </PlaceRow>
          {threads(project.id).map((item) => (
            <ThreadRow key={item.id} item={item} />
          ))}
        </div>
      ))}
      <SectionLabel action={{ label: "Hire", run: () => actions.setHireOpen(true) }}>
        Team
      </SectionLabel>
      {employees.map((employee) => (
        <PlaceRow
          key={employee.id}
          place={{ kind: "direct", employeeId: employee.id }}
          title={employee.name}
          trailing={trailing(employee)}
          unread={unreadOf(`direct:${employee.id}`)}
        >
          <EmployeePortrait employee={employee} size={20} mood={moodOf(state, employee)} />
        </PlaceRow>
      ))}
      {shownApps.length > 0 && <SectionLabel>Apps</SectionLabel>}
      {shownApps.map((app) => (
        <LayerRow
          key={app.id}
          layer={{ kind: "app", app: app.id }}
          title={app.name}
          icon={appIcons[app.id] ?? LayoutGrid}
        />
      ))}
    </div>
  );
}

/**
 * Threads the owner follows or that need the owner, under their project (or under Home when
 * they have none). Everything else stays in its channel.
 */
function useNestedThreads() {
  const { work, followed, decisions } = useWorkspace();
  const waiting = new Set((valueOf(decisions) ?? []).map((d) => d.commitment_id));
  const shown = (valueOf(work) ?? []).filter(
    (item) =>
      item.state !== "completed" &&
      item.state !== "cancelled" &&
      (followed.includes(item.id) || item.state === "needs_decision" || waiting.has(item.id)),
  );
  return (project: string | null) => shown.filter((item) => item.project_id === project);
}

function useTrailing() {
  const state = useWorkspace();
  return (employee: Employee): Trailing =>
    employee.paused
      ? "paused"
      : state.workingOf(employee.id)
        ? "working"
        : (valueOf(state.decisions) ?? []).some((d) => d.employee_id === employee.id)
          ? "needsYou"
          : "none";
}

function SectionLabel({
  children,
  action,
}: {
  children: ReactNode;
  action?: { label: string; run: () => void };
}) {
  return (
    <div className="group/label flex items-center">
      <h3 className="px-2.5 pt-3.5 pb-1 text-label font-medium text-ink-3">{children}</h3>
      {action && (
        <button
          type="button"
          aria-label={action.label}
          title={action.label}
          onClick={action.run}
          className="mr-2 ml-auto grid place-items-center pt-2.5 text-ink-3 opacity-0 transition-opacity group-hover/label:opacity-100 hover:text-ink-2 focus-visible:opacity-100"
        >
          <Plus className="size-3.5" />
        </button>
      )}
    </div>
  );
}

const rowClass = (selected: boolean, unread: boolean) =>
  cn(
    "flex w-full items-center gap-2.5 rounded-[9px] px-2.5 py-[7px] text-left text-control transition-[color,background-color,box-shadow] duration-200",
    selected ? "bg-sheet text-ink shadow-resting" : "text-ink-2 hover:text-ink",
    unread && !selected && "font-semibold text-ink",
  );

function PlaceRow({
  place,
  title,
  icon: Icon,
  count = 0,
  unread = 0,
  trailing = "none",
  children,
}: {
  place: Place;
  title: string;
  icon?: LucideIcon;
  /** Things waiting on the owner: an amber count. */
  count?: number;
  /** Messages the owner hasn't read: a filled badge. */
  unread?: number;
  trailing?: Trailing;
  children?: ReactNode;
}) {
  const { place: current, actions } = useWorkspace();
  const selected = samePlace(current, place);
  return (
    <button
      type="button"
      aria-label={unread ? `${title}, ${unread} unread` : count ? `${title}, ${count}` : title}
      aria-current={selected ? "page" : undefined}
      onClick={() => actions.selectPlace(place)}
      className={rowClass(selected, unread > 0)}
    >
      {Icon ? <Icon className="size-[15px] w-5 shrink-0" strokeWidth={1.9} /> : children}
      <span className="truncate">{title}</span>
      <span className="ml-auto" />
      {trailing === "working" && (
        <span className="size-1.5 shrink-0 rounded-full bg-indigo" aria-label="working" />
      )}
      {trailing === "needsYou" && (
        <span className="size-1.5 shrink-0 rounded-full bg-amber" aria-label="needs you" />
      )}
      {trailing === "paused" && <span className="text-caption text-ink-3">Paused</span>}
      {count > 0 && (
        <span className="grid h-[17px] min-w-[17px] shrink-0 place-items-center rounded-full bg-amber px-1 text-[10.5px] font-bold text-white tabular-nums">
          {count}
        </span>
      )}
      {unread > 0 && <UnreadBadge count={unread} />}
    </button>
  );
}

function UnreadBadge({ count }: { count: number }) {
  return (
    <span
      data-testid="unread"
      className="grid h-[17px] min-w-[17px] shrink-0 place-items-center rounded-full bg-indigo px-1 text-[10.5px] font-bold text-white tabular-nums"
    >
      {count}
    </span>
  );
}

/** A thread nested under its project: indented, opening the thread. */
function ThreadRow({ item }: { item: Commitment }) {
  const { place, actions, unreadOf } = useWorkspace();
  const selected = place.kind === "thread" && place.workId === item.id;
  const unread = unreadOf(`work:${item.id}`);
  return (
    <button
      type="button"
      aria-label={unread ? `${item.title}, ${unread} unread` : item.title}
      aria-current={selected ? "page" : undefined}
      onClick={() => actions.openThread(item.id)}
      className={cn(rowClass(selected, unread > 0), "py-[5px] pl-[38px]")}
    >
      <span className="truncate text-detail">{item.title}</span>
      <span className="ml-auto" />
      {item.state === "needs_decision" && (
        <span className="size-1.5 shrink-0 rounded-full bg-amber" aria-label="needs you" />
      )}
      {unread > 0 && <UnreadBadge count={unread} />}
    </button>
  );
}

/** An app: opens its records as a layer beside the conversation. */
function LayerRow({ layer, title, icon: Icon }: { layer: Layer; title: string; icon: LucideIcon }) {
  const { layers, actions } = useWorkspace();
  const top = layers.at(-1);
  const selected = top?.kind === "app" && layer.kind === "app" && top.app === layer.app;
  return (
    <button
      type="button"
      aria-current={selected ? "true" : undefined}
      onClick={() => (selected ? actions.closeLayers() : actions.openLayer(layer))}
      className={rowClass(selected, false)}
    >
      <Icon className="size-[15px] w-5 shrink-0" strokeWidth={1.9} />
      <span className="truncate">{title}</span>
    </button>
  );
}
