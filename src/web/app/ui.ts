/**
 * The workspace's own client state, outside the server cache and the URL: the sheets and dialogs
 * that are open, what goes with the next message, and the notice on screen. Each component reads
 * only the slice it shows.
 */
import type { Ref } from "../../protocol/ref.ts";
import { createStore, useStore } from "./store.ts";

export type PlaceKind = "home" | "direct" | "project";

/** Opening "New work item" from a project or an employee fills in what it can. */
export interface WorkItemDefaults {
  owner?: string;
  projectId?: string;
}

interface Ui {
  wide: boolean;
  sidebarVisible: boolean;
  /** Whether the open layer goes with the next message as a reference. */
  referencing: boolean;
  /** A file or page the owner attached with the composer's +, sent with the next message. */
  attached: Ref | undefined;
  /** Counts requests to put the cursor in the composer ("Something else"). */
  composerFocus: number;
  paletteOpen: boolean;
  /** The New employee sheet; each opening counts, so each starts a fresh form. */
  hireOpen: boolean;
  hireOpenings: number;
  /** The Connect apps sheet, and whether it shows the connected apps. */
  connectOpen: boolean;
  connectedShown: boolean;
  projectOpen: boolean;
  newWorkItem: (WorkItemDefaults & { opening: number }) | undefined;
  /** Counts "New work item" openings. */
  openings: number;
  notice: string | undefined;
  /** Counts finished turns, so open files read their contents again. */
  turns: number;
}

const store = createStore<Ui>({
  wide: false,
  sidebarVisible: true,
  referencing: true,
  attached: undefined,
  composerFocus: 0,
  paletteOpen: false,
  hireOpen: false,
  hireOpenings: 0,
  connectOpen: false,
  connectedShown: false,
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
  attach: (attached: Ref | undefined) => store.set({ attached }),
  focusComposer: () => store.set((s) => ({ composerFocus: s.composerFocus + 1 })),
  setPaletteOpen: (paletteOpen: boolean) => store.set({ paletteOpen }),
  togglePalette: () => store.set((s) => ({ paletteOpen: !s.paletteOpen })),
  setHireOpen: (hireOpen: boolean) =>
    store.set((s) => ({ hireOpen, hireOpenings: s.hireOpenings + (hireOpen ? 1 : 0) })),
  /** Opens Connect apps, on the connected apps when asked. */
  openConnect: (connected = false) => store.set({ connectOpen: true, connectedShown: connected }),
  closeConnect: () => store.set({ connectOpen: false }),
  showConnected: (connectedShown: boolean) => store.set({ connectedShown }),
  setProjectOpen: (projectOpen: boolean) => store.set({ projectOpen }),
  newWorkItem: (defaults: WorkItemDefaults = {}) =>
    store.set((s) => ({
      newWorkItem: { ...defaults, opening: s.openings + 1 },
      openings: s.openings + 1,
    })),
  closeNewWorkItem: () => store.set({ newWorkItem: undefined }),
  toggleSidebar: () => store.set((s) => ({ sidebarVisible: !s.sidebarVisible })),
  toggleWide: () => store.set((s) => ({ wide: !s.wide })),
  /** Leaving a place: the panel is no longer widened and nothing stays attached. */
  leftPlace: () => store.set({ wide: false, attached: undefined }),
  closedLayers: () => store.set({ wide: false }),
  openedLayer: () => store.set({ referencing: true }),
  turnFinished: () => store.set((s) => ({ turns: s.turns + 1 })),
};
