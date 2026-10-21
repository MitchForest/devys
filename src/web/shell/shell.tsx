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
import { Link } from "@tanstack/react-router";
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  useApps,
  useBusiness,
  useBusinesses,
  useBusinessId,
  useEmployees,
  useHome,
  useOperations,
  useOwnerPhoto,
  usePerson,
  usePlaceTitle,
} from "../app/data.ts";
import { useRefresh, useSignOut, useStop } from "../app/mutations.ts";
import {
  routeOf,
  useCanGoBack,
  useLayers,
  useNav,
  usePlace,
  type Place,
} from "../app/navigation.ts";
import { ui, uiState, useUi } from "../app/ui.ts";
import { useStatus, isRunning } from "../app/data.ts";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { PersonPortrait } from "../design/face.tsx";
import { BusinessPortrait, EmployeePortrait } from "../design/portrait.tsx";
import { RightPanel } from "../panel/panel.tsx";
import { ConversationPane } from "./conversation.tsx";
import { PanelContext, usePanel } from "./panel-state.ts";
import { defaultPanel, layout, panelRange, sidebarWidth } from "./layout.ts";
import { HireSheet, NewProjectDialog, NewWorkItemDialog } from "./dialogs.tsx";
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

/** Whether the place's permanent view has anything: an empty one is never shown. */
function useHasPermanent(place: Place) {
  const home = useHome().data;
  return (
    place.kind !== "home" ||
    Boolean(
      home && (home.needs_you.length || home.glance.moving.length || home.glance.stuck.length),
    )
  );
}

/** The panel's state for a layout; `narrow`: it lies over the conversation. */
function usePanelState(narrow: boolean) {
  const place = usePlace();
  const { layers } = useLayers();
  const nav = useNav();
  const hasPermanent = useHasPermanent(place);
  const chosen = useUi((state) => (narrow ? state.overlay : state.panels[place.kind]));
  const layered = layers.length > 0;
  const toggle = () => (layered ? nav.closeLayers() : ui.togglePermanent(place.kind, narrow));
  return { open: layered || (hasPermanent && chosen), hasPermanent, toggle };
}

export function Shell() {
  const compact = useCompact();
  return (
    <>
      {compact ? <CompactShell /> : <RegularShell />}
      <CommandPalette />
      <Settings />
      <HireSheet />
      <NewProjectDialog />
      <NewWorkItemDialog />
    </>
  );
}

/**
 * One gray frame (toolbar and business strip) around one rounded workspace: the sidebar, the
 * conversation in the middle, and the right panel showing what the conversation is about.
 */
function RegularShell() {
  const sidebarVisible = useUi((state) => state.sidebarVisible);
  const widened = useUi((state) => state.wide);
  const { layers } = useLayers();
  const [ref, width] = useWidth<HTMLDivElement>();
  const [preferred, setPreferred] = useState(savedWidth);
  const narrow = layout(width, sidebarVisible, true, false, preferred).overlay;
  const panel = usePanelState(narrow);
  const panelOpen = panel.open;
  const wide = widened && layers.length > 0;
  const columns = layout(width, sidebarVisible, panelOpen, wide, preferred);
  const motion =
    "transition-[width,opacity] duration-300 ease-[cubic-bezier(.3,1.1,.4,1)] motion-reduce:duration-150";
  return (
    <PanelContext.Provider value={panel}>
      <Shortcuts togglePanel={panel.toggle} />
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
                  <StableSidebar />
                </div>
              </div>
              <div className={cn("shrink-0 bg-hairline", columns.sidebar ? "w-px" : "w-0")} />
              <main
                className={cn("relative min-w-0 shrink-0 overflow-hidden bg-sheet", motion)}
                style={{ width: columns.conversation }}
              >
                <StableConversation />
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
    </PanelContext.Provider>
  );
}

// The columns re-render with the layout; what they show re-renders only with its own data.
const StableSidebar = memo(Sidebar);
const StableConversation = memo(ConversationPane);

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
  const nav = useNav();
  const sidebarVisible = useUi((state) => state.sidebarVisible);
  const panel = usePanel();
  const { layers } = useLayers();
  const business = useBusiness();
  const place = usePlace();
  const canGoBack = useCanGoBack();
  const trail = usePlaceTitle(place);
  return (
    <header className="flex h-[52px] shrink-0 items-center gap-1.5 pr-2.5 pl-[18px]">
      <ToolbarIconButton
        label={sidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)"}
        onClick={ui.toggleSidebar}
      >
        <PanelLeft />
      </ToolbarIconButton>
      {canGoBack && (
        <ToolbarIconButton label="Back (⌘[)" onClick={nav.back}>
          <ChevronLeft />
        </ToolbarIconButton>
      )}
      <nav
        aria-label="Breadcrumb"
        className="flex min-w-0 items-center gap-1.5 pl-1.5 text-control whitespace-nowrap"
      >
        <span className="text-ink-3">{business?.name}</span>
        <span className="text-ink-3">/</span>
        {trail.parent && business && (
          <>
            <Link
              {...routeOf(business.id, trail.parent.place)}
              onClick={ui.leftPlace}
              className="truncate text-ink-2 hover:text-ink"
            >
              {trail.parent.title}
            </Link>
            <span className="text-ink-3">›</span>
          </>
        )}
        <span className="truncate font-semibold text-ink" data-testid="place-title">
          {trail.title}
        </span>
      </nav>
      <span className="ml-auto" />
      {(panel.hasPermanent || layers.length > 0) && (
        <ToolbarIconButton
          label={panel.open ? "Hide side panel (⌥⌘0)" : "Show side panel (⌥⌘0)"}
          onClick={panel.toggle}
        >
          <PanelRight />
        </ToolbarIconButton>
      )}
    </header>
  );
}

/** Tiles that switch businesses, and the account at the bottom. */
function BusinessStrip() {
  const businesses = useBusinesses();
  const businessId = useBusinessId();
  const person = usePerson();
  const photo = useOwnerPhoto();
  return (
    <nav
      aria-label="Businesses"
      className="flex w-[60px] shrink-0 flex-col items-center gap-1.5 pt-1 pb-3"
    >
      {businesses.map((b) => {
        const selected = b.id === businessId;
        return (
          <Link
            key={b.id}
            to="/$business"
            params={{ business: b.id }}
            title={b.name}
            aria-label={`Switch to ${b.name}`}
            aria-current={selected ? "page" : undefined}
            onClick={ui.leftPlace}
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
          </Link>
        );
      })}
      <span className="mt-auto" />
      <AccountMenu side="right">
        <PersonPortrait name={person?.display_name ?? ""} {...(photo ? { photo } : {})} size={30} />
      </AccountMenu>
    </nav>
  );
}

function AccountMenu({ side, children }: { side: "right" | "bottom"; children: React.ReactNode }) {
  const person = usePerson();
  const nav = useNav();
  const signOut = useSignOut();
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
        <DropdownMenuItem onClick={() => nav.openSettings()}>Settings…</DropdownMenuItem>
        <DropdownMenuItem onClick={() => nav.openSettings("apps")}>
          Apps & connections…
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => signOut.mutate()}>
          Sign out of this device
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/**
 * Hardware-keyboard shortcuts, as on macOS and iPad. The listener is attached once; it reads
 * what it needs when a key is pressed.
 */
function Shortcuts({ togglePanel }: { togglePanel: () => void }) {
  const nav = useNav();
  const refresh = useRefresh();
  const stop = useStop();
  const operations = useOperations();
  const running = isRunning(useStatus(operations?.id).data);
  const { layers } = useLayers();
  const latest = useRef({ togglePanel, refresh, stop, operations, running, layered: false });
  latest.current = {
    togglePanel,
    refresh,
    stop,
    operations,
    running,
    layered: layers.length > 0,
  };
  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      const now = latest.current;
      const paletteOpen = uiState().paletteOpen;
      if (event.key === "Escape" && now.layered && !paletteOpen) {
        // Esc goes back one layer, unless something above the workspace handles it.
        if (document.querySelector("[role=dialog]")) return;
        event.preventDefault();
        nav.popLayer();
        return;
      }
      if (!event.metaKey) return;
      if (event.key === "k" && !event.ctrlKey) {
        event.preventDefault();
        ui.togglePalette();
      } else if (event.key === "[" && history.state?.trail?.length) {
        event.preventDefault();
        nav.back();
      } else if (event.ctrlKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        ui.toggleSidebar();
      } else if (event.altKey && event.code === "Digit0") {
        event.preventDefault();
        now.togglePanel();
      } else if (event.key === "r" && !event.shiftKey && !event.altKey) {
        event.preventDefault();
        void now.refresh();
      } else if (event.key === "." && now.running && now.operations) {
        event.preventDefault();
        now.stop.mutate(now.operations.id);
      }
    };
    window.addEventListener("keydown", keys);
    return () => window.removeEventListener("keydown", keys);
  }, [nav]);
  return null;
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
  const nav = useNav();
  const business = useBusiness();
  const businesses = useBusinesses();
  const businessId = useBusinessId();
  const operations = useOperations();
  const place = usePlace();
  const { layers } = useLayers();
  const canGoBack = useCanGoBack();
  const signOut = useSignOut();
  const panel = usePanelState(true);
  // A tab's list shows until the owner opens something from it.
  const [list, setList] = useState<Tab | null>(null);
  const [sheet, setSheet] = useState(false);
  const selected = list ?? tabOf(place);
  const needsYou = useHome().data?.needs_you.length ?? 0;
  const showsSheet = sheet || layers.length > 0;
  const trail = usePlaceTitle(place);
  return (
    <PanelContext.Provider value={panel}>
      <Shortcuts togglePanel={panel.toggle} />
      <div className="flex h-dvh flex-col bg-sheet">
        <header className="flex h-12 shrink-0 items-center gap-2 px-4 pt-[env(safe-area-inset-top)]">
          {list === null && place.kind !== "home" ? (
            <button
              type="button"
              aria-label="Back"
              onClick={() => (canGoBack ? nav.back() : setList(tabOf(place)))}
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
                  <DropdownMenuItem key={b.id} onClick={() => nav.selectBusiness(b.id)}>
                    {b.id === businessId ? <CircleCheck /> : <span className="w-4" />} {b.name}
                  </DropdownMenuItem>
                ))}
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => ui.setProjectOpen(true)}>
                  New project
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => ui.setHireOpen(true)}>Hire</DropdownMenuItem>
                <DropdownMenuItem onClick={() => nav.openSettings()}>Settings</DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem variant="destructive" onClick={() => signOut.mutate()}>
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
            <StableConversation />
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
                  onClick={() => {
                    if (value !== "home") return setList(value);
                    setList(null);
                    nav.selectPlace({ kind: "home" });
                  }}
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
            nav.closeLayers();
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
    </PanelContext.Provider>
  );
}

function PlaceFace({ employeeId }: { employeeId: string }) {
  const employee = useEmployees().find((e) => e.id === employeeId);
  return employee ? <EmployeePortrait employee={employee} size={26} /> : null;
}

/** The phone's Apps tab: each installed app opens as a sheet over the conversation. */
function CompactApps() {
  const apps = useApps().data ?? [];
  const nav = useNav();
  return (
    <div className="flex flex-col gap-0.5 pt-2">
      {apps
        .filter((app) => app.visible)
        .map((app) => (
          <button
            key={app.id}
            type="button"
            onClick={() => nav.openLayer({ kind: "app", app: app.id })}
            className="flex items-center gap-3 rounded-[10px] px-2.5 py-2.5 text-left text-control text-ink hover:bg-sheet-tint"
          >
            <span className="font-medium">{app.name}</span>
            <span className="truncate text-detail text-ink-3">{app.summary}</span>
          </button>
        ))}
    </div>
  );
}
