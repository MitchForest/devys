import { ChevronLeft } from "lucide-react";
import { Link } from "@tanstack/react-router";
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  useBusiness,
  useBusinesses,
  useBusinessId,
  useChiefOfStaff,
  useWork,
} from "../app/data.ts";
import { useRefresh, useStop } from "../app/mutations.ts";
import { useCanGoBack, useLayers, useNav, usePlace } from "../app/navigation.ts";
import { ui, uiState, useUi } from "../app/ui.ts";
import { useStatus, isRunning } from "../app/data.ts";
import { BusinessPortrait } from "../design/portrait.tsx";
import { RightPanel } from "../panel/panel.tsx";
import { ConversationPane } from "./conversation.tsx";
import { ConnectAppsSheet } from "./connect-apps.tsx";
import { PlacePill } from "./header.tsx";
import { compactQuery, defaultPanel, layout, panelRange, sidebarWidth } from "./layout.ts";
import { NewEmployeeSheet, NewProjectDialog, NewWorkItemDialog } from "./dialogs.tsx";
import { CommandPalette } from "./palette.tsx";
import { Settings } from "./settings.tsx";
import { SearchButton, Sidebar } from "./sidebar.tsx";
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
  const query = compactQuery;
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
  return (
    <>
      {compact ? <CompactShell /> : <RegularShell />}
      <CommandPalette />
      <Settings />
      <NewEmployeeSheet />
      <NewProjectDialog />
      <NewWorkItemDialog />
      <ConnectAppsSheet />
    </>
  );
}

/**
 * The business strip and one rounded workspace: the sidebar, the conversation in the middle,
 * and the right panel only while the owner looks at something (a layer).
 */
function RegularShell() {
  const sidebarVisible = useUi((state) => state.sidebarVisible);
  const widened = useUi((state) => state.wide);
  const { layers } = useLayers();
  const nav = useNav();
  const [ref, width] = useWidth<HTMLDivElement>();
  const [preferred, setPreferred] = useState(savedWidth);
  const panelOpen = layers.length > 0;
  const wide = widened && panelOpen;
  const columns = layout(width, sidebarVisible, panelOpen, wide, preferred);
  const motion =
    "transition-[width,opacity] duration-300 ease-[cubic-bezier(.3,1.1,.4,1)] motion-reduce:duration-150";
  return (
    <>
      <Shortcuts closePanel={nav.closeLayers} />
      <div className="flex h-dvh bg-frame pt-2">
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
    </>
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

/** Tiles that switch businesses. */
function BusinessStrip() {
  const businesses = useBusinesses();
  const businessId = useBusinessId();
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
    </nav>
  );
}

/**
 * The employee of the conversation in view, whom ⌘. stops: Home's Chief of Staff, a direct
 * chat's employee, or the owner of a thread's work.
 */
function useSpeaking() {
  const place = usePlace();
  const chiefOfStaff = useChiefOfStaff();
  const work = useWork().data;
  return place.kind === "home"
    ? chiefOfStaff?.id
    : place.kind === "direct"
      ? place.employeeId
      : place.kind === "thread"
        ? work?.find((item) => item.id === place.workId)?.owner_employee_id
        : undefined;
}

/**
 * Hardware-keyboard shortcuts, as on macOS and iPad. The listener is attached once; it reads
 * what it needs when a key is pressed.
 */
function Shortcuts({ closePanel }: { closePanel: () => void }) {
  const nav = useNav();
  const refresh = useRefresh();
  const stop = useStop();
  const speaking = useSpeaking();
  const running = isRunning(useStatus(speaking).data);
  const { layers } = useLayers();
  const latest = useRef({ closePanel, refresh, stop, speaking, running, layered: false });
  latest.current = {
    closePanel,
    refresh,
    stop,
    speaking,
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
      } else if (event.altKey && event.code === "Digit0" && now.layered) {
        event.preventDefault();
        now.closePanel();
      } else if (event.key === "r" && !event.shiftKey && !event.altKey) {
        event.preventDefault();
        void now.refresh();
      } else if (event.key === "." && now.running && now.speaking) {
        event.preventDefault();
        now.stop.mutate(now.speaking);
      }
    };
    window.addEventListener("keydown", keys);
    return () => window.removeEventListener("keydown", keys);
  }, [nav]);
  return null;
}

/**
 * Phones, as Messages on iPhone: the list of conversations, or one conversation full screen with
 * Back to the list. The desk or project details and any layer open as sheets over it.
 */
function CompactShell() {
  const nav = useNav();
  const business = useBusiness();
  const place = usePlace();
  const { layers } = useLayers();
  const canGoBack = useCanGoBack();
  // The list shows until the owner opens something from it.
  const [list, setList] = useState(false);
  return (
    <>
      <Shortcuts closePanel={nav.closeLayers} />
      <div className="flex h-dvh flex-col bg-sheet">
        <header className="relative flex h-12 shrink-0 items-center justify-center px-4 pt-[env(safe-area-inset-top)]">
          {list ? (
            <>
              <span className="flex items-center gap-2">
                {business && <BusinessPortrait business={business} size={26} />}
                <span className="text-heading font-semibold text-ink">{business?.name}</span>
              </span>
              <span className="absolute right-3">
                <SearchButton />
              </span>
            </>
          ) : (
            <>
              <button
                type="button"
                aria-label="Back"
                onClick={() => (canGoBack ? nav.back() : setList(true))}
                className="absolute left-3 grid size-8 place-items-center rounded-full text-indigo"
              >
                <ChevronLeft className="size-5" />
              </button>
              <PlacePill key={JSON.stringify(place)} place={place} />
            </>
          )}
        </header>
        <main
          className={cn("min-h-0 flex-1", list && "bg-sheet-tint pb-[env(safe-area-inset-bottom)]")}
        >
          {list ? (
            <div
              className="h-full"
              // Opening a conversation from the list shows it full screen.
              onClickCapture={(event) => {
                if ((event.target as Element).closest("a")) setTimeout(() => setList(false));
              }}
            >
              <Sidebar compact />
            </div>
          ) : (
            <ConversationPane header={false} />
          )}
        </main>
        <Sheet open={layers.length > 0} onOpenChange={(next) => !next && nav.closeLayers()}>
          <SheetContent
            side="bottom"
            className="rounded-t-sheet bg-sheet p-0 data-[side=bottom]:h-[92dvh]"
            showCloseButton={false}
          >
            <SheetTitle className="sr-only">Details</SheetTitle>
            <RightPanel onClose={nav.closeLayers} />
          </SheetContent>
        </Sheet>
      </div>
    </>
  );
}
