import {
  ChevronLeft,
  CircleCheck,
  CircleDollarSign,
  House,
  LayoutGrid,
  ListChecks,
  Maximize2,
  MessageCircle,
  Minimize2,
  Pause,
  Play,
  Search,
  ScanFace,
  Sparkles,
  Square,
  Inbox,
  Users,
  PanelLeft,
  PanelRight,
  UserRound,
  X,
  type LucideIcon,
  Bell,
  BellRing,
} from "lucide-react";
import { EmployeePortrait, BusinessPortrait } from "../design/portrait.tsx";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { moodFor, operationsMood, pageTitle, presence, type Presence } from "../app/names.ts";
import { useWorkspace, valueOf, type Destination } from "../app/workspace.tsx";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { PersonPortrait } from "../design/face.tsx";
import { EmptyNote, PageBody } from "../design/primitives.tsx";
import { ApprovalsPage, WorkDetail, WorkPage } from "../pages/work.tsx";
import { FilesPage } from "../pages/files.tsx";
import { TodayGreeting, TodayPage, TodayWork } from "../pages/today.tsx";
import { SpacePage } from "../pages/space.tsx";
import { EmployeePage } from "../pages/employee.tsx";
import { DirectPage } from "../pages/direct.tsx";
import { ArtifactViewer } from "../pages/artifact.tsx";
import { AppsPage, InboxPage, MoneyPage } from "../pages/other.tsx";
import { Composer, ConversationView } from "./chat.tsx";
import { inspectorRange, layout, minimumPage, sidebarWidth } from "./layout.ts";
import { HireSheet, NewTaskDialog } from "./dialogs.tsx";
import { CommandPalette } from "./palette.tsx";
import { Settings } from "./settings.tsx";
import { ConversationList, destinations, Sidebar } from "./sidebar.tsx";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

const destinationIcons: Record<Destination, LucideIcon> = {
  home: House,
  inbox: Inbox,
  work: ListChecks,
  team: Users,
  money: CircleDollarSign,
  apps: LayoutGrid,
};

function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    if (!ref.current) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry!.contentRect.width));
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return [ref, width] as const;
}

function useCompact() {
  const query = "(max-width: 700px)";
  const [compact, setCompact] = useState(
    () => typeof window !== "undefined" && window.matchMedia(query).matches,
  );
  useEffect(() => {
    const media = window.matchMedia(query);
    const change = () => setCompact(media.matches);
    media.addEventListener("change", change);
    return () => media.removeEventListener("change", change);
  }, []);
  return compact;
}

const savedWidth = () => {
  try {
    return Number(localStorage.getItem("inspectorWidth")) || 320;
  } catch {
    return 320;
  }
};

export function Shell() {
  const compact = useCompact();
  useShortcuts();
  return (
    <>
      {compact ? <CompactShell /> : <RegularShell />}
      <CommandPalette />
      <ArtifactViewer />
      <Settings />
      <HireSheet />
      <NewTaskDialog />
    </>
  );
}

/** One gray frame (toolbar and rail) around one rounded workspace holding the sidebar, the page and the inspector. */
function RegularShell() {
  const { sidebarVisible, inspectorVisible, expanded, selectedWork } = useWorkspace();
  const [ref, width] = useWidth<HTMLDivElement>();
  const [preferred, setPreferred] = useState(savedWidth);
  // The right panel holds the open work item and nothing else.
  const hasPanel = Boolean(selectedWork);
  const columns = layout(
    width,
    sidebarVisible,
    inspectorVisible && hasPanel,
    expanded && Boolean(selectedWork),
    preferred,
  );
  const motion =
    "transition-[width,opacity] duration-300 ease-[cubic-bezier(.3,1.1,.4,1)] motion-reduce:duration-150";
  return (
    <div className="flex h-dvh flex-col bg-frame">
      <Toolbar />
      <div className="flex min-h-0 flex-1">
        <Rail />
        <div className="mr-2 mb-2 min-w-0 flex-1 overflow-hidden rounded-workspace border border-hairline bg-sheet shadow-resting">
          <div ref={ref} className="flex h-full">
            <div
              className={cn("flex shrink-0 justify-end overflow-hidden bg-sheet-tint", motion)}
              style={{ width: columns.sidebar }}
            >
              <div className="h-full shrink-0" style={{ width: sidebarWidth }}>
                <Sidebar />
              </div>
            </div>
            <div className={cn("shrink-0 bg-hairline", columns.sidebar ? "w-px" : "w-0")} />
            <main
              className={cn(
                "shrink-0 overflow-hidden bg-sheet",
                motion,
                columns.page ? "opacity-100" : "opacity-0",
              )}
              style={{ width: columns.page }}
              aria-hidden={columns.page === 0}
            >
              <div
                className="relative h-full"
                style={{ width: Math.max(columns.page, minimumPage) }}
              >
                <MainPane />
              </div>
            </main>
            <ResizeHandle
              visible={columns.showsHandle}
              width={preferred}
              onChange={(next) => {
                setPreferred(next);
                try {
                  localStorage.setItem("inspectorWidth", String(next));
                } catch {
                  // A remembered width is a convenience only.
                }
              }}
            />
            <aside
              className={cn("shrink-0 overflow-hidden bg-sheet", motion)}
              style={{ width: columns.inspector }}
              aria-label="Inspector"
            >
              <div
                className="h-full"
                style={{ width: Math.max(columns.inspector, inspectorRange[0]) }}
              >
                <RightPanel />
              </div>
            </aside>
          </div>
        </div>
      </div>
    </div>
  );
}

/** The pane divider doubles as a drag handle for the side panel's width. */
function ResizeHandle({
  visible,
  width,
  onChange,
}: {
  visible: boolean;
  width: number;
  onChange: (width: number) => void;
}) {
  const [dragging, setDragging] = useState(false);
  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Side panel width"
      aria-valuenow={width}
      aria-valuemin={inspectorRange[0]}
      aria-valuemax={inspectorRange[1]}
      aria-hidden={!visible}
      tabIndex={visible ? 0 : -1}
      className={cn(
        "group grid shrink-0 cursor-col-resize place-items-center bg-sheet",
        visible ? "w-[9px]" : "pointer-events-none w-0 opacity-0",
      )}
      onDoubleClick={() => onChange(320)}
      onKeyDown={(event) => {
        // The arrows move the divider; the panel grows as it moves left.
        const step = event.key === "ArrowLeft" ? 16 : event.key === "ArrowRight" ? -16 : 0;
        if (!step) return;
        event.preventDefault();
        onChange(Math.min(Math.max(width + step, inspectorRange[0]), inspectorRange[1]));
      }}
      onPointerDown={(event) => {
        const start = event.clientX;
        const origin = width;
        event.currentTarget.setPointerCapture(event.pointerId);
        setDragging(true);
        const move = (e: PointerEvent) =>
          onChange(
            Math.min(Math.max(origin - (e.clientX - start), inspectorRange[0]), inspectorRange[1]),
          );
        const up = () => {
          setDragging(false);
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", up);
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
      }}
    >
      <span
        className={cn(
          "h-full transition-all duration-150",
          dragging
            ? "w-0.5 bg-ink-3/60"
            : "w-px bg-hairline group-hover:w-0.5 group-hover:bg-ink-3/60",
        )}
      />
    </div>
  );
}

function Toolbar() {
  const state = useWorkspace();
  const { actions, sidebarVisible, inspectorVisible, business, selectedWork } = state;
  return (
    <header className="flex h-[52px] shrink-0 items-center gap-1.5 pr-2.5 pl-[18px]">
      <ToolbarIconButton
        label={sidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)"}
        onClick={actions.toggleSidebar}
      >
        <PanelLeft />
      </ToolbarIconButton>
      <nav
        aria-label="Breadcrumb"
        className="flex items-center gap-1.5 pl-1.5 text-control whitespace-nowrap"
      >
        <span className="text-ink-3">{business?.name}</span>
        <span className="text-ink-3">/</span>
        <span className="font-semibold text-ink">{pageTitle(state)}</span>
      </nav>
      <span className="ml-auto" />
      <PresenceStrip />
      <button
        type="button"
        aria-label="Search"
        title="Search (⌘K)"
        onClick={() => actions.setPaletteOpen(true)}
        className="flex h-[30px] items-center gap-1.5 rounded-full bg-track px-3 text-ink-3 transition-colors hover:bg-track/80"
      >
        <Search className="size-3" strokeWidth={2.4} />
        <span className="text-caption">⌘K</span>
      </button>
      {/* The right panel only ever holds a work item, so its toggle shows only then. */}
      {selectedWork && (
        <ToolbarIconButton
          label={inspectorVisible ? "Hide inspector (⌥⌘0)" : "Show inspector (⌥⌘0)"}
          onClick={actions.toggleInspector}
        >
          <PanelRight />
        </ToolbarIconButton>
      )}
    </header>
  );
}

/** Who is working and who is waiting on you, as Faces. Click to act, hover to read, right-click for more. */
function PresenceStrip() {
  const state = useWorkspace();
  return (
    <div className="flex items-center gap-1">
      {presence(state)
        .slice(0, 4)
        .map((item) => (
          <PresenceFace key={item.employee.id} presence={item} />
        ))}
    </div>
  );
}

function PresenceFace({ presence: item }: { presence: Presence }) {
  const { actions, runningOf } = useWorkspace();
  // Needs-you opens the decisions; anyone else opens their chat.
  const open = () =>
    item.signal.kind === "needsYou"
      ? actions.selectPage({ kind: "approvals" })
      : actions.message(item.employee.id);
  return (
    <ContextMenu>
      <ContextMenuTrigger
        render={
          <button type="button" aria-label={item.summary} title={item.summary} onClick={open} />
        }
        className="relative rounded-[9px] p-1 transition-colors animate-in zoom-in-75 fade-in hover:bg-track"
      >
        <EmployeePortrait employee={item.employee} size={22} mood={moodFor(item.signal)} />
        {item.signal.kind === "working" && (
          <span className="pointer-events-none absolute inset-0.5 animate-spin rounded-[10px] border-[1.75px] border-transparent border-t-indigo border-r-indigo/40 [animation-duration:1.6s] motion-reduce:animate-none" />
        )}
        {item.signal.kind === "needsYou" && (
          <span className="absolute -top-0.5 -right-0.5 grid h-3.5 min-w-3.5 place-items-center rounded-full bg-amber px-1 text-[9px] font-bold text-white tabular-nums ring-[1.5px] ring-frame">
            {item.signal.count}
          </span>
        )}
        {item.signal.kind === "failed" && (
          <span className="absolute -top-0.5 -right-0.5 grid size-3.5 place-items-center rounded-full bg-red text-[8px] font-black text-white ring-[1.5px] ring-frame">
            !
          </span>
        )}
        {item.signal.kind === "paused" && (
          <span className="absolute -top-0.5 -right-0.5 grid size-[15px] place-items-center rounded-full bg-frame">
            <span className="h-[3px] w-2 rounded-full bg-gray" />
          </span>
        )}
      </ContextMenuTrigger>
      <ContextMenuContent>
        <ContextMenuItem onClick={() => actions.message(item.employee.id)}>
          <MessageCircle /> Message
        </ContextMenuItem>
        {item.signal.kind === "needsYou" && (
          <ContextMenuItem onClick={() => actions.selectPage({ kind: "approvals" })}>
            <ScanFace /> Review decisions
          </ContextMenuItem>
        )}
        <ContextMenuItem
          onClick={() => actions.selectPage({ kind: "employee", id: item.employee.id })}
        >
          <UserRound /> Open profile
        </ContextMenuItem>
        <ContextMenuSeparator />
        <ContextMenuItem onClick={() => actions.togglePause(item.employee)}>
          {item.employee.paused ? (
            <>
              <Play /> Resume
            </>
          ) : (
            <>
              <Pause /> Pause
            </>
          )}
        </ContextMenuItem>
        {runningOf(item.employee.id) && (
          <ContextMenuItem variant="destructive" onClick={() => actions.stop(item.employee.id)}>
            <Square /> Stop
          </ContextMenuItem>
        )}
      </ContextMenuContent>
    </ContextMenu>
  );
}

function Rail() {
  const state = useWorkspace();
  const { businesses, businessId, destination, actions, person } = state;
  return (
    <nav
      aria-label="Businesses and destinations"
      className="flex w-[60px] shrink-0 flex-col items-center gap-1.5 pt-1 pb-3"
    >
      {businesses.map((b) => {
        const selected = b.id === businessId;
        return (
          <button
            key={b.id}
            type="button"
            title={b.name}
            aria-label={`Switch to ${b.name}`}
            aria-pressed={selected}
            onClick={() => actions.selectBusiness(b.id)}
            className="relative"
          >
            {selected && (
              <span className="absolute top-1/2 -left-3 h-5 w-1 -translate-y-1/2 animate-in rounded-full bg-ink zoom-in" />
            )}
            <span
              className={cn(
                "block transition-[scale,opacity] duration-300",
                selected ? "scale-100" : "scale-[0.92] opacity-75 hover:opacity-100",
              )}
            >
              <BusinessPortrait business={b} size={36} />
            </span>
          </button>
        );
      })}
      <span className="my-2 h-px w-6 bg-hairline" />
      {destinations.map((d) => {
        const Icon = destinationIcons[d.value];
        const selected = destination === d.value;
        const count = 0;
        return (
          <button
            key={d.value}
            type="button"
            title={d.title}
            aria-label={count ? `${d.title}, ${count}` : d.title}
            aria-current={selected ? "page" : undefined}
            onClick={() => actions.selectDestination(d.value)}
            className={cn(
              "relative grid size-[38px] place-items-center rounded-[11px] transition-colors duration-150",
              selected
                ? "bg-sheet text-ink shadow-resting"
                : "text-ink-2 hover:bg-track hover:text-ink",
            )}
          >
            <Icon className="size-[17px]" strokeWidth={selected ? 2.2 : 1.8} />
            {count > 0 && (
              <span className="absolute top-[3px] right-[3px] grid h-[15px] min-w-[15px] place-items-center rounded-full bg-[var(--aurora-rose)] px-1 text-[9.5px] font-bold text-white">
                {count}
              </span>
            )}
          </button>
        );
      })}
      <span className="mt-auto" />
      <DropdownMenu>
        <DropdownMenuTrigger aria-label="Account" className="rounded-full">
          <PersonPortrait
            name={person?.display_name ?? ""}
            {...(state.ownerPhoto ? { photo: state.ownerPhoto } : {})}
            size={30}
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent side="right" align="end" className="w-auto min-w-48">
          <DropdownMenuGroup>
            {person && (
              <DropdownMenuLabel className="text-control text-ink">
                {person.display_name}
              </DropdownMenuLabel>
            )}
            <DropdownMenuLabel className="text-detail font-normal text-ink-3">
              {location.host}
            </DropdownMenuLabel>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => actions.setSettingsOpen(true)}>
            Settings…
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => void actions.signOut()}>
            Sign out of this device
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </nav>
  );
}

/** Routes the main pane. Each page owns its header and any tabs it needs. */
export function MainPane() {
  const { page, notice, actions } = useWorkspace();
  const key = JSON.stringify(page);
  return (
    <div className="relative h-full">
      <div key={key} className="h-full">
        {page.kind === "today" ? (
          <TodayPage />
        ) : page.kind === "approvals" ? (
          <ApprovalsPage />
        ) : page.kind === "files" ? (
          <FilesPage path={page.path} />
        ) : page.kind === "direct" ? (
          <DirectPage employeeId={page.employeeId} />
        ) : page.kind === "space" ? (
          <SpacePage id={page.id} />
        ) : page.kind === "employee" ? (
          <EmployeePage {...(page.id ? { id: page.id } : {})} />
        ) : page.kind === "inbox" ? (
          <InboxPage />
        ) : page.kind === "work" ? (
          <WorkPage filter={page.filter} />
        ) : page.kind === "money" ? (
          <MoneyPage />
        ) : (
          <AppsPage section={page.section} />
        )}
      </div>
      {notice && (
        <div role="status" className="absolute inset-x-0 top-3 flex justify-center px-4">
          <div className="flex animate-in items-center gap-2.5 rounded-full bg-sheet px-3.5 py-[9px] shadow-raised fade-in slide-in-from-top-2">
            <span className="text-body text-ink">{notice}</span>
            <button
              type="button"
              aria-label="Dismiss"
              className="text-ink-3 hover:text-ink-2"
              onClick={actions.dismissNotice}
            >
              ×
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * The right panel: the selected work item with its own thread and composer. Nothing else
 * opens it; who an employee or a space is lives in a popover on the conversation's header.
 */
export function RightPanel({ allowExpand = true }: { allowExpand?: boolean }) {
  const { selectedWork } = useWorkspace();
  return selectedWork ? <WorkPanel id={selectedWork} allowExpand={allowExpand} /> : null;
}

/** A work item: its detail above its thread (`work:<id>`), which has its own composer. */
function WorkPanel({ id, allowExpand }: { id: string; allowExpand: boolean }) {
  const { work, panel, expanded, actions, employeeName, followed } = useWorkspace();
  const item = valueOf(work)?.find((w) => w.id === id);
  const following = followed.includes(id);
  return (
    <section aria-label="Work item" className="flex h-full flex-col">
      <div className="flex items-center gap-2.5 px-3.5 pt-3.5 pb-2.5">
        <span className="grid size-[30px] shrink-0 place-items-center rounded-[9px] bg-well text-ink-2">
          <ListChecks className="size-4" />
        </span>
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-body font-semibold text-ink" data-testid="panel-title">
            {item?.title ?? "Task"}
          </span>
          <span className="truncate text-detail text-ink-3">
            {item ? `Owned by ${employeeName(item.owner_employee_id)}` : ""}
          </span>
        </div>
        <span className="ml-auto" />
        {item && (
          <ToolbarIconButton
            label={following ? "Following: told at each step. Stop following" : "Follow each step"}
            onClick={() => void actions.setFollowing(item.id, !following)}
          >
            {following ? <BellRing /> : <Bell />}
          </ToolbarIconButton>
        )}
        {allowExpand && (
          <ToolbarIconButton
            label={expanded ? "Move to side panel" : "Expand conversation"}
            onClick={actions.toggleExpanded}
          >
            {expanded ? <Minimize2 /> : <Maximize2 />}
          </ToolbarIconButton>
        )}
        <ToolbarIconButton label="Close work item" onClick={actions.closeWork}>
          <X />
        </ToolbarIconButton>
      </div>
      {!item ? (
        <div className="p-3.5">
          <EmptyNote>
            {work.status === "loading" ? "Loading…" : "This task no longer exists."}
          </EmptyNote>
        </div>
      ) : (
        <>
          <div
            className={cn(
              "max-h-[42%] shrink-0 overflow-y-auto border-b border-hairline px-3.5 pb-3",
              expanded && "mx-auto w-full max-w-[720px]",
            )}
          >
            <WorkDetail item={item} />
          </div>
          <div className="min-h-0 flex-1">
            <ConversationView
              conversation={panel}
              className={expanded ? "max-w-[720px]" : undefined}
              empty={<span className="text-body text-ink-3">No messages about this task yet.</span>}
            />
          </div>
          <Composer
            conversation={panel}
            which="panel"
            label={`Message about ${item.title}`}
            className={expanded ? "max-w-[740px]" : undefined}
          />
        </>
      )}
    </section>
  );
}

/** Hardware-keyboard shortcuts, as on macOS and iPad. */
function useShortcuts() {
  const { actions, paletteOpen, isRunning, businessId } = useWorkspace();
  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (!event.metaKey) return;
      const digit = Number(event.key);
      if (!event.altKey && !event.ctrlKey && digit >= 1 && digit <= destinations.length) {
        event.preventDefault();
        actions.selectDestination(destinations[digit - 1]!.value);
      } else if (event.key === "k" && !event.ctrlKey) {
        event.preventDefault();
        actions.setPaletteOpen(!paletteOpen);
      } else if (event.ctrlKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        actions.toggleSidebar();
      } else if (event.altKey && event.code === "Digit0") {
        event.preventDefault();
        actions.toggleInspector();
      } else if (event.key === "r" && !event.shiftKey && !event.altKey) {
        event.preventDefault();
        actions.refresh();
      } else if (event.key === "." && isRunning) {
        event.preventDefault();
        actions.stop();
      }
    };
    window.addEventListener("keydown", keys);
    return () => window.removeEventListener("keydown", keys);
  }, [actions, paletteOpen, isRunning, businessId]);
}

const compactDestinations: Destination[] = ["home", "inbox", "work", "team"];

/** The phone's Home, as native `CompactHome`: the greeting, what waits on approval, then every conversation. */
function CompactHome() {
  const { decisions, actions } = useWorkspace();
  const count = valueOf(decisions)?.length ?? 0;
  return (
    <PageBody>
      <TodayGreeting />
      {count > 0 && (
        <button
          type="button"
          onClick={() => actions.selectPage({ kind: "approvals" })}
          className="flex items-center gap-2 rounded-card bg-sheet p-3 text-left text-control text-ink shadow-resting"
        >
          <ScanFace className="size-4 shrink-0" /> {count} waiting for your approval
        </button>
      )}
      <div className="-mx-2">
        <ConversationList />
      </div>
      <TodayWork />
    </PageBody>
  );
}

/**
 * Phones, as native `CompactShell`: Home lists Direct messages and Spaces; a conversation
 * opens full screen; a work item pushes over it as a sheet.
 */
function CompactShell() {
  const state = useWorkspace();
  const { destination, actions, business, businesses, businessId, operations, page } = state;
  const selected = compactDestinations.includes(destination) ? destination : "home";
  const inConversation = page.kind === "direct" || page.kind === "space";
  return (
    <div className="flex h-dvh flex-col bg-sheet">
      <header className="flex h-12 shrink-0 items-center gap-2 px-4 pt-[env(safe-area-inset-top)]">
        {inConversation ? (
          <button
            type="button"
            aria-label="Back"
            onClick={() => actions.selectPage({ kind: "today" })}
            className="-ml-1.5 flex items-center gap-0.5 text-control text-indigo"
          >
            <ChevronLeft className="size-5" /> Home
          </button>
        ) : (
          <DropdownMenu>
            <DropdownMenuTrigger
              className="flex items-center gap-2"
              aria-label={`Switch business, currently ${business?.name ?? ""}`}
            >
              {business && <BusinessPortrait business={business} size={26} />}
              <span className="text-heading font-semibold text-ink">{business?.name}</span>
              <span className="text-[11px] text-ink-3">▾</span>
            </DropdownMenuTrigger>
            <DropdownMenuContent className="w-auto min-w-56">
              {businesses.map((b) => (
                <DropdownMenuItem key={b.id} onClick={() => actions.selectBusiness(b.id)}>
                  {b.id === businessId ? <CircleCheck /> : <span className="w-4" />} {b.name}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => actions.newTask()}>New task</DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.setHireOpen(true)}>Hire</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => actions.selectPage({ kind: "files" })}>
                Files
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.selectPage({ kind: "approvals" })}>
                Approvals
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.selectPage({ kind: "money" })}>
                Money
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() => actions.selectPage({ kind: "apps", section: "installed" })}
              >
                Apps and connections
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.setSettingsOpen(true)}>
                Settings
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem variant="destructive" onClick={() => void actions.signOut()}>
                Sign out of this device
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
        <span className="ml-auto" />
        {operations && !inConversation && (
          <button
            type="button"
            aria-label={`Message ${operations.name}`}
            onClick={() => actions.message(operations.id)}
            className="rounded-[9px]"
          >
            <EmployeePortrait
              employee={operations}
              size={28}
              mood={operationsMood(state)}
              label={operations.name}
            />
          </button>
        )}
      </header>
      <main className={cn("min-h-0 flex-1", !inConversation && "pb-24")}>
        {page.kind === "today" ? <CompactHome /> : <MainPane />}
      </main>
      {!inConversation && (
        <>
          <button
            type="button"
            aria-label="Ask Operations"
            onClick={() => operations && actions.message(operations.id)}
            className="aurora fixed right-[18px] bottom-[calc(74px+env(safe-area-inset-bottom))] grid size-[54px] place-items-center rounded-full text-white shadow-[0_8px_24px_rgb(110_123_255/0.45)]"
          >
            <Sparkles className="size-5" strokeWidth={2.4} />
          </button>
          <nav
            aria-label="Destinations"
            className="fixed inset-x-4 bottom-[calc(12px+env(safe-area-inset-bottom))] flex h-[54px] items-center justify-around rounded-full border border-hairline bg-sheet/80 shadow-raised backdrop-blur-xl"
          >
            {compactDestinations.map((value) => {
              const Icon = destinationIcons[value];
              const active = value === selected;
              return (
                <button
                  key={value}
                  type="button"
                  aria-current={active ? "page" : undefined}
                  onClick={() => actions.selectDestination(value)}
                  className={cn(
                    "flex flex-col items-center gap-0.5 px-3 text-[10px] font-medium",
                    active ? "text-indigo" : "text-ink-2",
                  )}
                >
                  <Icon className="size-5" strokeWidth={active ? 2.2 : 1.8} />
                  {destinations.find((d) => d.value === value)!.title}
                </button>
              );
            })}
          </nav>
        </>
      )}
      <Sheet
        open={Boolean(state.selectedWork)}
        onOpenChange={(open) => open || actions.closeWork()}
      >
        <SheetContent
          side="bottom"
          className="h-[92dvh] rounded-t-sheet bg-sheet p-0"
          showCloseButton={false}
        >
          <SheetTitle className="sr-only">Work item</SheetTitle>
          <RightPanel allowExpand={false} />
        </SheetContent>
      </Sheet>
    </div>
  );
}
