/**
 * Where the owner is lives in the URL, so Back, forward, reload and links all work:
 *
 * - `/$business` is Home, the direct chat with the Chief of Staff
 * - `/$business/chat/$employee`, `/$business/project/$project`
 * - `/$business/settings/$section`, over the place it was opened from
 * - each `?layer=` stacks a view beside the conversation, in order: a record by its ref (a work
 *   item, a page, a file) or `browser:<work>`, the live browser of a work item.
 *
 * The history entry carries what a URL cannot: whether the top layer opened on its own.
 */
import { useRouter, useRouterState } from "@tanstack/react-router";
import { useMemo } from "react";
import type { ConversationKey } from "../../conversations/contract.ts";
import { parseRef, ref, type Ref } from "../../protocol/ref.ts";
import { ui, type PlaceKind } from "./ui.ts";

/**
 * Where the owner is: always a conversation with someone. Home is the direct chat with the Chief
 * of Staff; a project is its channel. Work opens beside it, as a layer.
 */
export type Place =
  | { kind: "home" }
  | { kind: "direct"; employeeId: string }
  | { kind: "project"; id: string };

/**
 * A view beside the conversation: a record (by its ref, shown by the layer registry for its
 * kind; a work item is its plan and its own conversation) or a work item's live browser. The
 * right panel shows only these.
 */
export type Layer = { kind: "record"; ref: Ref } | { kind: "browser"; workId: string };

/** A work item's layer: its card, plan and conversation, beside whatever chat is open. */
export const workLayer = (workId: string): Layer => ({
  kind: "record",
  ref: ref("work", "item", workId),
});

declare module "@tanstack/history" {
  interface HistoryState {
    /** The place Settings was opened over. */
    behind?: Place;
    /** The top layer opened on its own, so the next one may replace it. */
    auto?: boolean;
    /** Who published the version of the page on top. */
    updatedBy?: string;
  }
}

/** The layer stack as the URL holds it. */
export interface LayerSearch {
  layer?: string[];
}

/** `?layer=a&layer=b`, with refs left readable. */
export function parseSearch(text: string): Record<string, unknown> {
  const search: Record<string, unknown> = {};
  for (const [key, value] of new URLSearchParams(text)) {
    if (key === "layer") ((search.layer ??= []) as string[]).push(value);
    else search[key] = value;
  }
  return search;
}
export function stringifySearch(search: Record<string, unknown>) {
  const parts = Object.entries(search).flatMap(([key, value]) =>
    value === undefined || value === null
      ? []
      : (Array.isArray(value) ? value : [value]).map(
          (each) =>
            `${key}=${encodeURIComponent(String(each)).replace(/%3A/g, ":").replace(/%2F/g, "/")}`,
        ),
  );
  return parts.length ? `?${parts.join("&")}` : "";
}
export const validateLayerSearch = (search: Record<string, unknown>): LayerSearch =>
  Array.isArray(search.layer) && search.layer.length
    ? { layer: search.layer.filter((each): each is string => typeof each === "string") }
    : {};

export const samePlace = (a: Place, b: Place) => JSON.stringify(a) === JSON.stringify(b);

/** The conversation a place shows: Home's is the direct chat with the Chief of Staff. */
export const conversationOf = (
  place: Place,
  chiefOfStaff: string | undefined,
): ConversationKey | undefined =>
  place.kind === "home"
    ? chiefOfStaff
      ? `direct:${chiefOfStaff}`
      : undefined
    : place.kind === "direct"
      ? `direct:${place.employeeId}`
      : `project:${place.id}`;

/** The record a layer shows; the browser is not a record. */
export const refOfLayer = (layer: Layer): Ref | undefined =>
  layer.kind === "record" ? layer.ref : undefined;

/** The layer a URL entry names: a record's ref, or `browser:<work>`; undefined for anything else. */
export const layerOfRef = (value: string): Layer | undefined =>
  parseRef(value)
    ? { kind: "record", ref: value as Ref }
    : /^browser:[A-Za-z0-9-]{1,64}$/.test(value)
      ? { kind: "browser", workId: value.slice("browser:".length) }
      : undefined;

/** The stack a URL describes, bottom first. */
const layersOf = (search: LayerSearch): Layer[] =>
  (search.layer ?? []).flatMap((value) => layerOfRef(value) ?? []);

/** The URL's form of a stack, bottom first. */
function searchOf(layers: readonly Layer[]): LayerSearch {
  const entries = layers.map((layer) =>
    layer.kind === "browser" ? `browser:${layer.workId}` : layer.ref,
  );
  return entries.length ? { layer: entries } : {};
}

type Router = ReturnType<typeof useRouter>;
type RouterState = Router["state"];

const placeKey = (place: Place) =>
  place.kind === "home"
    ? "home:"
    : `${place.kind}:${place.kind === "direct" ? place.employeeId : place.id}`;
const placeOfKey = (key: string): Place => {
  const at = key.indexOf(":");
  const kind = key.slice(0, at) as PlaceKind;
  const id = key.slice(at + 1);
  return kind === "direct"
    ? { kind, employeeId: id }
    : kind === "project"
      ? { kind, id }
      : { kind: "home" };
};

function placeKeyOf(state: RouterState) {
  const match = state.matches.at(-1);
  const params = (match?.params ?? {}) as Record<string, string | undefined>;
  switch (match?.routeId) {
    case "/$business/chat/$employee":
      return `direct:${params.employee}`;
    case "/$business/project/$project":
      return `project:${params.project}`;
    case "/$business/settings/$section": {
      const behind = state.location.state.behind;
      return behind ? placeKey(behind) : "home:";
    }
    default:
      return "home:";
  }
}
const placeOf = (state: RouterState) => placeOfKey(placeKeyOf(state));
const searchIn = (state: RouterState) => validateLayerSearch(state.location.search);

/** The place on screen. */
export function usePlace(): Place {
  const key = useRouterState({ select: placeKeyOf });
  return useMemo(() => placeOfKey(key), [key]);
}

/** The settings section open over the place, if any. */
export const useSettingsSection = () =>
  useRouterState({
    select: (state) => {
      const match = state.matches.at(-1);
      return match?.routeId === "/$business/settings/$section"
        ? (match.params as { section: string }).section
        : undefined;
    },
  });

/** The layer stack in the right panel, and how its top layer came to be there. */
export function useLayers() {
  const key = useRouterState({
    select: (state) => {
      const { layer } = searchIn(state);
      const { auto, updatedBy } = state.location.state;
      return JSON.stringify([layer, auto, updatedBy]);
    },
  });
  return useMemo(() => {
    const [layer, auto, updatedBy] = JSON.parse(key) as [
      string[] | undefined,
      boolean | undefined,
      string | undefined,
    ];
    const layers = layersOf(layer ? { layer } : {});
    return { layers, top: layers.at(-1), auto: Boolean(auto), updatedBy };
  }, [key]);
}

/** The work item whose layer is in the panel's stack, nearest the top: what a file or session there serves. */
export function useWorkInPanel(): string | undefined {
  const { layers } = useLayers();
  for (const layer of layers.toReversed()) {
    if (layer.kind === "browser") return layer.workId;
    const parsed = parseRef(layer.ref);
    if (parsed?.app === "work" && parsed.kind === "item") return parsed.id;
  }
  return undefined;
}

/** The address of a place, for links and navigation. */
export function routeOf(business: string, place: Place) {
  switch (place.kind) {
    case "home":
      return { to: "/$business", params: { business } } as const;
    case "direct":
      return {
        to: "/$business/chat/$employee",
        params: { business, employee: place.employeeId },
      } as const;
    case "project":
      return {
        to: "/$business/project/$project",
        params: { business, project: place.id },
      } as const;
  }
}

/**
 * Moving around the workspace. The actions read where the owner is when they run, so the
 * object is made once per router and never changes.
 */
function makeNav(router: Router) {
  const now = () => {
    const state = router.state;
    const place = placeOf(state);
    const params = (state.matches.at(-1)?.params ?? {}) as { business?: string };
    return {
      business: params.business ?? "",
      place,
      layers: layersOf(searchIn(state)),
      history: state.location.state,
    };
  };
  const go = (place: Place, options: { business?: string; replace?: boolean } = {}) =>
    void router.navigate({
      ...routeOf(options.business ?? now().business, place),
      search: {} as never,
      state: {},
      ...(options.replace ? { replace: true } : {}),
    } as never);
  /** Changes the stack over the current place, keeping how the owner got there. */
  const setLayers = (
    layers: readonly Layer[],
    options: { replace?: boolean; auto?: boolean; updatedBy?: string } = {},
  ) => {
    const { history } = now();
    void router.navigate({
      to: ".",
      search: searchOf(layers) as never,
      state: {
        ...(history.behind ? { behind: history.behind } : {}),
        ...(options.auto ? { auto: true } : {}),
        ...(options.updatedBy ? { updatedBy: options.updatedBy } : {}),
      },
      ...(options.replace ? { replace: true } : {}),
    });
  };
  const nav = {
    selectBusiness: (id: string) => {
      if (id === now().business) return;
      ui.leftPlace();
      go({ kind: "home" }, { business: id });
    },
    /** Goes to a place from the sidebar: the layers close. */
    selectPlace: (place: Place) => {
      ui.leftPlace();
      go(place);
    },
    /** Opens the DM with an employee. */
    message: (employeeId: string) => nav.selectPlace({ kind: "direct", employeeId }),
    /**
     * Opens a work item beside the conversation on screen, whichever it is: its own stack, so
     * the panel shows it alone; opening the one already on top does nothing.
     */
    openWork: (workId: string) => {
      ui.openedLayer();
      const { layers } = now();
      const work = workLayer(workId);
      if (JSON.stringify(layers.at(-1)) === JSON.stringify(work)) return;
      setLayers([work]);
    },
    /** Opens a work item's live browser over the work, so closing it returns to the work. */
    openBrowser: (workId: string) => {
      ui.openedLayer();
      setLayers([workLayer(workId), { kind: "browser", workId }]);
    },
    /** Stacks a layer; opening what is on top does nothing. */
    openLayer: (layer: Layer) => {
      ui.openedLayer();
      const { layers } = now();
      if (JSON.stringify(layers.at(-1)) === JSON.stringify(layer)) return;
      setLayers([...layers, layer]);
    },
    /** Replaces the top layer, as stepping through a page's versions does. */
    replaceLayer: (layer: Layer) =>
      setLayers([...now().layers.slice(0, -1), layer], { replace: true }),
    /** Back one layer. */
    popLayer: () => setLayers(now().layers.slice(0, -1)),
    /** Closes the panel. */
    closeLayers: () => {
      ui.closedLayers();
      if (now().layers.length) setLayers([]);
    },
    /**
     * A page was published in the conversation on screen: it opens on its own unless the owner
     * opened a layer themselves; a new version of the open page replaces it in place.
     */
    pageArrived: (
      id: string,
      author: string | undefined,
      sameName: (a: string, b: string) => boolean,
    ) => {
      const { layers, history } = now();
      const top = layers.at(-1);
      ui.openedLayer();
      const page: Layer = { kind: "record", ref: ref("documents", "artifact", id) };
      const showing = top?.kind === "record" ? parseRef(top.ref) : undefined;
      if (showing?.kind === "artifact" && sameName(showing.id, id))
        return setLayers([...layers.slice(0, -1), page], {
          replace: true,
          ...(history.auto ? { auto: true } : {}),
          ...(author ? { updatedBy: author } : {}),
        });
      if (top && !history.auto) return;
      setLayers([page], { replace: true, auto: true });
    },
    openSettings: (section = "account") => {
      const { business, place } = now();
      void router.navigate({
        to: "/$business/settings/$section",
        params: { business, section },
        search: (current: Record<string, unknown>) => current as never,
        state: { behind: place },
      });
    },
    setSettingsSection: (section: string) =>
      void router.navigate({
        to: "/$business/settings/$section",
        params: { business: now().business, section },
        search: (current: Record<string, unknown>) => current as never,
        state: true,
        replace: true,
      }),
    closeSettings: () => {
      const { history } = now();
      if (history.behind && history.__TSR_index > 0) router.history.back();
      else go(history.behind ?? { kind: "home" }, { replace: true });
    },
  };
  return nav;
}
export type Nav = ReturnType<typeof makeNav>;

/** The navigation actions; the same object for the life of the page. */
export function useNav(): Nav {
  const router = useRouter();
  return useMemo(() => makeNav(router), [router]);
}
