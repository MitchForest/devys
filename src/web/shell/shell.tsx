import {
  ChevronLeft,
  CircleCheck,
  FolderKanban,
  House,
  LayoutGrid,
  PanelLeft,
  PanelRight,
  Users,
  type LucideIcon,
} from "lucide-react";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useWorkspace, valueOf, type Place } from "../app/workspace.tsx";
import { placeTitle } from "../app/names.ts";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { PersonPortrait } from "../design/face.tsx";
import { BusinessPortrait, EmployeePortrait } from "../design/portrait.tsx";
import { RightPanel } from "../panel/panel.tsx";
import { ConversationPane } from "./conversation.tsx";
import { defaultPanel, layout, panelRange, sidebarWidth } from "./layout.ts";
import { HireSheet, NewProjectDialog, NewTaskDialog } from "./dialogs.tsx";
import { CommandPalette } from "./palette.tsx";
import { Settings } from "./settings.tsx";
import { Sidebar, SidebarSections } from "./sidebar.tsx";
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
    return Number(localStorage.getItem("panelWidth")) || defaultPanel;
  } catch {
    return defaultPanel;
  }
};

export function Shell() {
  const compact = useCompact();
  useShortcuts();
  return (
    <>
      {compact ? <CompactShell /> : <RegularShell />}
      <CommandPalette />
      <Settings />
      <HireSheet />
      <NewProjectDialog />
      <NewTaskDialog />
    </>
  );
}

/**
 * One gray frame (toolbar and business strip) around one rounded workspace: the sidebar, the
 * conversation in the middle, and the right panel showing what the conversation is about.
 */
function RegularShell() {
  const { sidebarVisible, panelOpen, wide, actions } = useWorkspace();
  const [ref, width] = useWidth<HTMLDivElement>();
  const [preferred, setPreferred] = useState(savedWidth);
  const columns = layout(width, sidebarVisible, panelOpen, wide, preferred);
  const narrow = layout(width, sidebarVisible, true, false, preferred).overlay;
  useEffect(() => actions.setNarrow(narrow), [narrow]);
  const motion =
    "transition-[width,opacity] duration-300 ease-[cubic-bezier(.3,1.1,.4,1)] motion-reduce:duration-150";
  return (
    <div className="flex h-dvh flex-col bg-frame">
      <Toolbar />
      <div className="flex min-h-0 flex-1">
        <BusinessStrip />
        <div className="mr-2 mb-2 min-w-0 flex-1 overflow-hidden rounded-workspace border border-hairline bg-sheet shadow-resting">
          <div ref={ref} className="relative flex h-full">
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
              className={cn("relative min-w-0 shrink-0 overflow-hidden bg-sheet", motion)}
              style={{ width: columns.conversation }}
            >
              <ConversationPane />
            </main>
            <ResizeHandle
              visible={columns.handle}
              width={preferred}
              onChange={(next) => {
                setPreferred(next);
                try {
                  localStorage.setItem("panelWidth", String(next));
                } catch {
                  // A remembered width is a convenience only.
                }
              }}
            />
            <aside
              className={cn(
                "shrink-0 overflow-hidden bg-sheet",
                motion,
                columns.overlay &&
                  "absolute inset-y-0 right-0 z-10 border-l border-hairline shadow-raised",
              )}
              style={{ width: columns.panel }}
              aria-label="Side panel"
              aria-hidden={columns.panel === 0}
            >
              <div className="h-full" style={{ width: Math.max(columns.panel, panelRange[0]) }}>
                {panelOpen && <RightPanel />}
              </div>
            </aside>
          </div>
        </div>
      </div>
    </div>
  );
}

/** The divider doubles as a drag handle for the right panel's width. */
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
  const clamp = (next: number) => Math.min(Math.max(next, panelRange[0]), panelRange[1]);
  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Side panel width"
      aria-valuenow={width}
      aria-valuemin={panelRange[0]}
      aria-valuemax={panelRange[1]}
      aria-hidden={!visible}
      tabIndex={visible ? 0 : -1}
      className={cn(
        "group grid shrink-0 cursor-col-resize place-items-center bg-sheet",
        visible ? "w-[9px]" : "pointer-events-none w-0 opacity-0",
      )}
      onDoubleClick={() => onChange(defaultPanel)}
      onKeyDown={(event) => {
        // The arrows move the divider; the panel grows as it moves left.
        const step = event.key === "ArrowLeft" ? 16 : event.key === "ArrowRight" ? -16 : 0;
        if (!step) return;
        event.preventDefault();
        onChange(clamp(width + step));
      }}
      onPointerDown={(event) => {
        const start = event.clientX;
        const origin = width;
        event.currentTarget.setPointerCapture(event.pointerId);
        setDragging(true);
        const move = (e: PointerEvent) => onChange(clamp(origin - (e.clientX - start)));
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

/**
 * The business, the place and, in a thread, the work item. Back returns from a thread to
 * where it was opened; the place's name shows or hides the right panel.
 */
function Toolbar() {
  const state = useWorkspace();
  const { actions, sidebarVisible, panelOpen, hasPermanent, layers, business, place, history } =
    state;
  const trail = placeTitle(state, place);
  return (
    <header className="flex h-[52px] shrink-0 items-center gap-1.5 pr-2.5 pl-[18px]">
      <ToolbarIconButton
        label={sidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)"}
        onClick={actions.toggleSidebar}
      >
        <PanelLeft />
      </ToolbarIconButton>
      {history.length > 0 && (
        <ToolbarIconButton label="Back (⌘[)" onClick={actions.back}>
          <ChevronLeft />
        </ToolbarIconButton>
      )}
      <nav
        aria-label="Breadcrumb"
        className="flex min-w-0 items-center gap-1.5 pl-1.5 text-control whitespace-nowrap"
      >
        <span className="text-ink-3">{business?.name}</span>
        <span className="text-ink-3">/</span>
        {trail.parent && (
          <>
            <button
              type="button"
              onClick={() => trail.parent && actions.selectPlace(trail.parent.place)}
              className="truncate text-ink-2 hover:text-ink"
            >
              {trail.parent.title}
            </button>
            <span className="text-ink-3">›</span>
          </>
        )}
        <span className="truncate font-semibold text-ink" data-testid="place-title">
          {trail.title}
        </span>
      </nav>
      <span className="ml-auto" />
      {(hasPermanent || layers.length > 0) && (
        <ToolbarIconButton
          label={panelOpen ? "Hide side panel (⌥⌘0)" : "Show side panel (⌥⌘0)"}
          onClick={actions.togglePanel}
        >
          <PanelRight />
        </ToolbarIconButton>
      )}
    </header>
  );
}

/** Tiles that switch businesses, and the account at the bottom. */
function BusinessStrip() {
  const state = useWorkspace();
  const { businesses, businessId, actions, person } = state;
  return (
    <nav
      aria-label="Businesses"
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
      <span className="mt-auto" />
      <AccountMenu side="right">
        <PersonPortrait
          name={person?.display_name ?? ""}
          {...(state.ownerPhoto ? { photo: state.ownerPhoto } : {})}
          size={30}
        />
      </AccountMenu>
    </nav>
  );
}

function AccountMenu({ side, children }: { side: "right" | "bottom"; children: React.ReactNode }) {
  const { person, actions } = useWorkspace();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger aria-label="Account" className="rounded-full">
        {children}
      </DropdownMenuTrigger>
      <DropdownMenuContent side={side} align="end" className="w-auto min-w-48">
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
        <DropdownMenuItem onClick={() => actions.setSettingsOpen(true)}>Settings…</DropdownMenuItem>
        <DropdownMenuItem onClick={() => actions.setSettingsOpen(true, "apps")}>
          Apps & connections…
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => void actions.signOut()}>
          Sign out of this device
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Hardware-keyboard shortcuts, as on macOS and iPad. */
function useShortcuts() {
  const { actions, paletteOpen, isRunning, businessId, layers, history } = useWorkspace();
  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (event.key === "Escape" && layers.length && !paletteOpen) {
        // Esc goes back one layer, unless something above the workspace handles it.
        if (document.querySelector("[role=dialog]")) return;
        event.preventDefault();
        actions.popLayer();
        return;
      }
      if (!event.metaKey) return;
      if (event.key === "k" && !event.ctrlKey) {
        event.preventDefault();
        actions.setPaletteOpen(!paletteOpen);
      } else if (event.key === "[" && history.length) {
        event.preventDefault();
        actions.back();
      } else if (event.ctrlKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        actions.toggleSidebar();
      } else if (event.altKey && event.code === "Digit0") {
        event.preventDefault();
        actions.togglePanel();
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
  }, [actions, paletteOpen, isRunning, businessId, layers.length, history.length]);
}

type Tab = "home" | "projects" | "team" | "apps";
const tabs: { value: Tab; title: string; icon: LucideIcon }[] = [
  { value: "home", title: "Home", icon: House },
  { value: "projects", title: "Projects", icon: FolderKanban },
  { value: "team", title: "Team", icon: Users },
  { value: "apps", title: "Apps", icon: LayoutGrid },
];
const tabOf = (place: Place): Tab =>
  place.kind === "home" ? "home" : place.kind === "direct" ? "team" : "projects";

/**
 * Phones, as native `CompactShell`: tabs of Home, Projects, Team and Apps. The conversation is
 * always full screen; the permanent view and layers open as sheets over it.
 */
function CompactShell() {
  const state = useWorkspace();
  const { actions, business, businesses, businessId, operations, place, layers, home } = state;
  // A tab's list shows until the owner opens something from it.
  const [list, setList] = useState<Tab | null>(null);
  const [sheet, setSheet] = useState(false);
  const selected = list ?? tabOf(place);
  const needsYou = valueOf(home)?.needsYou.length ?? 0;
  const showsSheet = sheet || layers.length > 0;
  const open = (next: Place) => {
    setList(null);
    actions.selectPlace(next);
  };
  const trail = placeTitle(state, place);
  return (
    <div className="flex h-dvh flex-col bg-sheet">
      <header className="flex h-12 shrink-0 items-center gap-2 px-4 pt-[env(safe-area-inset-top)]">
        {list === null && place.kind !== "home" ? (
          <button
            type="button"
            aria-label="Back"
            onClick={() => (state.history.length ? actions.back() : setList(tabOf(place)))}
            className="-ml-1.5 flex items-center gap-0.5 text-control text-indigo"
          >
            <ChevronLeft className="size-5" />
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
              <DropdownMenuItem onClick={() => actions.setProjectOpen(true)}>
                New project
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.setHireOpen(true)}>Hire</DropdownMenuItem>
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
        {list === null && place.kind !== "home" && (
          <button
            type="button"
            onClick={() => setSheet(true)}
            className="flex min-w-0 items-center gap-2 text-left"
          >
            {place.kind === "direct" && <PlaceFace employeeId={place.employeeId} />}
            <span className="truncate text-heading font-semibold text-ink">{trail.title}</span>
          </button>
        )}
        <span className="ml-auto" />
        {list === null && place.kind !== "home" && (
          <button
            type="button"
            aria-label="Details"
            onClick={() => setSheet(true)}
            className="grid size-8 place-items-center rounded-full text-ink-2"
          >
            <PanelRight className="size-[18px]" />
          </button>
        )}
        {list === null && place.kind === "home" && needsYou > 0 && (
          <button
            type="button"
            onClick={() => setSheet(true)}
            className="rounded-full bg-amber/15 px-3 py-1 text-caption font-semibold text-amber"
          >
            {needsYou} need you
          </button>
        )}
        {list === null && place.kind === "home" && operations && (
          <button type="button" aria-label={operations.name} onClick={() => setSheet(true)}>
            <EmployeePortrait employee={operations} size={28} />
          </button>
        )}
      </header>
      <main className={cn("min-h-0 flex-1", list !== null && "overflow-y-auto px-2.5 pb-24")}>
        {list === "apps" ? (
          <CompactApps />
        ) : list !== null ? (
          <div onClickCapture={() => setTimeout(() => setList(null))}>
            <SidebarSections />
          </div>
        ) : (
          <ConversationPane />
        )}
      </main>
      {(list !== null || place.kind === "home") && (
        <nav
          aria-label="Tabs"
          className="mx-4 mb-[calc(12px+env(safe-area-inset-bottom))] flex h-[54px] shrink-0 items-center justify-around rounded-full border border-hairline bg-sheet/80 shadow-raised backdrop-blur-xl"
        >
          {tabs.map(({ value, title, icon: Icon }) => {
            const active = value === selected;
            return (
              <button
                key={value}
                type="button"
                aria-current={active ? "page" : undefined}
                onClick={() => (value === "home" ? open({ kind: "home" }) : setList(value))}
                className={cn(
                  "flex flex-col items-center gap-0.5 px-3 text-[10px] font-medium",
                  active ? "text-indigo" : "text-ink-2",
                )}
              >
                <Icon className="size-5" strokeWidth={active ? 2.2 : 1.8} />
                {title}
              </button>
            );
          })}
        </nav>
      )}
      <Sheet
        open={showsSheet}
        onOpenChange={(next) => {
          if (next) return;
          setSheet(false);
          actions.closeLayers();
        }}
      >
        <SheetContent
          side="bottom"
          className="rounded-t-sheet bg-sheet p-0 data-[side=bottom]:h-[92dvh]"
          showCloseButton={false}
        >
          <SheetTitle className="sr-only">Details</SheetTitle>
          <RightPanel onClose={() => setSheet(false)} />
        </SheetContent>
      </Sheet>
    </div>
  );
}

function PlaceFace({ employeeId }: { employeeId: string }) {
  const { employees } = useWorkspace();
  const employee = employees.find((e) => e.id === employeeId);
  return employee ? <EmployeePortrait employee={employee} size={26} /> : null;
}

/** The phone's Apps tab: each installed app opens as a sheet over the conversation. */
function CompactApps() {
  const { apps, actions } = useWorkspace();
  return (
    <div className="flex flex-col gap-0.5 pt-2">
      {(valueOf(apps) ?? [])
        .filter((app) => app.visible)
        .map((app) => (
          <button
            key={app.id}
            type="button"
            onClick={() => actions.openLayer({ kind: "app", app: app.id })}
            className="flex items-center gap-3 rounded-[10px] px-2.5 py-2.5 text-left text-control text-ink hover:bg-sheet-tint"
          >
            <span className="font-medium">{app.name}</span>
            <span className="truncate text-detail text-ink-3">{app.summary}</span>
          </button>
        ))}
    </div>
  );
}
