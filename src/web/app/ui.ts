/**
 * The workspace's own client state, outside the server cache and the URL: whether the right
 * panel shows, the sheets and dialogs that are open, and the notice on screen. Each component
 * reads only the slice it shows.
 */
import { createStore, useStore } from "./store.ts";

export type PlaceKind = "home" | "direct" | "project" | "thread";

/** Opening "New work item" from a project or an employee fills in what it can. */
export interface WorkItemDefaults {
  owner?: string;
  projectId?: string;
}

/** The places with a permanent view: an employee's desk, a project's overview. */
type PermanentKind = Extract<PlaceKind, "direct" | "project">;

/** Whether each kind of place shows its permanent view; the owner's choice is remembered. */
const panelDefaults: Record<PermanentKind, boolean> = { direct: false, project: true };
const savedPanels = (): Record<PermanentKind, boolean> => {
  try {
    return { ...panelDefaults, ...JSON.parse(localStorage.getItem("panels") ?? "{}") };
  } catch {
    return panelDefaults;
  }
};

interface Ui {
  panels: Record<PermanentKind, boolean>;
  /** Too narrow for both columns: the permanent view lies over the conversation when asked. */
  overlay: boolean;
  wide: boolean;
  sidebarVisible: boolean;
  /** Whether the open layer goes with the next message as a reference. */
  referencing: boolean;
  paletteOpen: boolean;
  hireOpen: boolean;
  /** Counts openings, so each opening starts a fresh form. */
  hireOpenings: number;
  projectOpen: boolean;
  newWorkItem: (WorkItemDefaults & { opening: number }) | undefined;
  /** Counts "New work item" openings. */
  openings: number;
  notice: string | undefined;
  /** Counts finished turns, so open files read their contents again. */
  turns: number;
}

const store = createStore<Ui>({
  panels: savedPanels(),
  overlay: false,
  wide: false,
  sidebarVisible: true,
  referencing: true,
  paletteOpen: false,
  hireOpen: false,
  hireOpenings: 0,
  openings: 0,
  projectOpen: false,
  newWorkItem: undefined,
  notice: undefined,
  turns: 0,
});

export const useUi = <S>(select: (state: Ui) => S) => useStore(store, select);
export const uiState = store.get;

/** Stable actions on the client state; none of them re-render anything but its readers. */
export const ui = {
  notify: (notice: string) => store.set({ notice }),
  dismissNotice: () => store.set({ notice: undefined }),
  setReferencing: (referencing: boolean) => store.set({ referencing }),
  setPaletteOpen: (paletteOpen: boolean) => store.set({ paletteOpen }),
  togglePalette: () => store.set((s) => ({ paletteOpen: !s.paletteOpen })),
  setHireOpen: (hireOpen: boolean) =>
    store.set((s) => ({ hireOpen, hireOpenings: s.hireOpenings + (hireOpen ? 1 : 0) })),
  setProjectOpen: (projectOpen: boolean) => store.set({ projectOpen }),
  newWorkItem: (defaults: WorkItemDefaults = {}) =>
    store.set((s) => ({
      newWorkItem: { ...defaults, opening: s.openings + 1 },
      openings: s.openings + 1,
    })),
  closeNewWorkItem: () => store.set({ newWorkItem: undefined }),
  toggleSidebar: () => store.set((s) => ({ sidebarVisible: !s.sidebarVisible })),
  toggleWide: () => store.set((s) => ({ wide: !s.wide })),
  /** Leaving a place: the overlay closes and the panel is no longer widened. */
  leftPlace: () => store.set({ overlay: false, wide: false }),
  closedLayers: () => store.set({ wide: false }),
  openedLayer: () => store.set({ referencing: true }),
  /** Shows or hides the permanent view for this kind of place, remembered across visits. */
  togglePermanent: (kind: PermanentKind, narrow: boolean) => {
    if (narrow) return store.set((s) => ({ overlay: !s.overlay }));
    store.set((s) => {
      const panels = { ...s.panels, [kind]: !s.panels[kind] };
      try {
        localStorage.setItem("panels", JSON.stringify(panels));
      } catch {
        // A remembered panel is a convenience only.
      }
      return { panels };
    });
  },
  turnFinished: () => store.set((s) => ({ turns: s.turns + 1 })),
};
