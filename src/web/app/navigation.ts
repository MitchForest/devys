/**
 * Where the owner is lives in the URL, so Back, forward, reload and links all work:
 *
 * - `/$business` is Home, the direct chat with Operations
 * - `/$business/chat/$employee`, `/$business/project/$project`, `/$business/thread/$work`
 * - `/$business/settings/$section`, over the place it was opened from
 * - `?app=code` opens an app beside the conversation (`?app=browser` the live browser of the
 *   thread's work), and each `?layer=<ref>` stacks a record over it, in order.
 *
 * The history entry carries what a URL cannot: the places a thread was opened from (for the
 * toolbar's Back) and whether the top layer opened on its own.
 */
import { useRouter, useRouterState } from "@tanstack/react-router";
import { useMemo } from "react";
import type { ConversationKey } from "../../conversations/contract.ts";
import { parseRef, ref, type Ref } from "../../protocol/ref.ts";
import { ui, type PlaceKind } from "./ui.ts";

/**
 * Where the owner is: always a conversation. Home is the direct chat with Operations; a
 * project is its channel; a thread is a work item's conversation.
 */
export type Place =
  | { kind: "home" }
  | { kind: "direct"; employeeId: string }
  | { kind: "project"; id: string }
  | { kind: "thread"; workId: string };

/** A temporary view stacked over the right panel's permanent view. */
export type Layer =
  | { kind: "artifact"; id: string }
  | { kind: "file"; path: string }
  | { kind: "app"; app: string }
  | { kind: "session"; workId: string; sessionId: string }
  | { kind: "browser"; workId: string };

declare module "@tanstack/history" {
  interface HistoryState {
    /** The places a thread was opened from, newest last: the toolbar's Back. */
    trail?: Place[];
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
  app?: string;
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
export const validateLayerSearch = (search: Record<string, unknown>): LayerSearch => ({
  ...(typeof search.app === "string" && search.app ? { app: search.app } : {}),
  ...(Array.isArray(search.layer) && search.layer.length
    ? { layer: search.layer.filter((each): each is string => typeof each === "string") }
    : {}),
});

export const samePlace = (a: Place, b: Place) => JSON.stringify(a) === JSON.stringify(b);

/** The conversation a place shows: Home's is the direct chat with Operations. */
export const conversationOf = (
  place: Place,
  operations: string | undefined,
): ConversationKey | undefined =>
  place.kind === "home"
    ? operations
      ? `direct:${operations}`
      : undefined
    : place.kind === "direct"
      ? `direct:${place.employeeId}`
      : place.kind === "project"
        ? `project:${place.id}`
        : `work:${place.workId}`;

/** The record a layer shows, as a ref; an app or the browser is not a record. */
function refOfLayer(layer: Layer): Ref | undefined {
  switch (layer.kind) {
    case "artifact":
      return ref("documents", "artifact", layer.id);
    case "file":
      return ref("documents", "file", layer.path);
    case "session":
      return ref("code", "session", layer.sessionId);
    default:
      return undefined;
  }
}

/** The layer that shows a page or a file, from its ref. */
export function layerOfRef(value: Ref): Layer | undefined {
  const parts = parseRef(value);
  if (parts?.app !== "documents") return undefined;
  return parts.kind === "artifact"
    ? { kind: "artifact", id: parts.id }
    : { kind: "file", path: parts.id };
}

/** What a layer is, in words and as a ref, for its header and the line sent with a message. */
export function layerReference(layer: Layer, names: { artifact: (id: string) => string }) {
  const title =
    layer.kind === "artifact"
      ? names.artifact(layer.id)
      : layer.kind === "file"
        ? layer.path.split("/").at(-1)!
        : layer.kind === "app"
          ? appTitle(layer.app)
          : layer.kind === "session"
            ? "Coding session"
            : "Browser";
  return { title, ref: refOfLayer(layer) };
}
const appTitle = (app: string) => app.charAt(0).toUpperCase() + app.slice(1);

/** The stack a URL describes. A coding session and the browser belong to the thread's work. */
function layersOf(search: LayerSearch, place: Place): Layer[] {
  const work = place.kind === "thread" ? place.workId : undefined;
  const base: Layer[] =
    search.app === "browser"
      ? work
        ? [{ kind: "browser", workId: work }]
        : []
      : search.app
        ? [{ kind: "app", app: search.app }]
        : [];
  return [
    ...base,
    ...(search.layer ?? []).flatMap((value): Layer[] => {
      const parts = parseRef(value);
      if (parts?.app === "documents")
        return [
          parts.kind === "artifact"
            ? { kind: "artifact", id: parts.id }
            : { kind: "file", path: parts.id },
        ];
      if (parts?.app === "code" && work)
        return [{ kind: "session", workId: work, sessionId: parts.id }];
      return [];
    }),
  ];
}

/** The URL's form of a stack: its app (always at the bottom), then each record's ref. */
function searchOf(layers: readonly Layer[]): LayerSearch {
  const app = layers.find((layer) => layer.kind === "app" || layer.kind === "browser");
  const refs = layers.flatMap((layer) => refOfLayer(layer) ?? []);
  return {
    ...(app ? { app: app.kind === "app" ? app.app : "browser" } : {}),
    ...(refs.length ? { layer: refs } : {}),
  };
}

type Router = ReturnType<typeof useRouter>;
type RouterState = Router["state"];

const placeKey = (place: Place) =>
  place.kind === "home"
    ? "home:"
    : `${place.kind}:${place.kind === "direct" ? place.employeeId : place.kind === "project" ? place.id : place.workId}`;
const placeOfKey = (key: string): Place => {
  const at = key.indexOf(":");
  const kind = key.slice(0, at) as PlaceKind;
  const id = key.slice(at + 1);
  return kind === "direct"
    ? { kind, employeeId: id }
    : kind === "project"
      ? { kind, id }
      : kind === "thread"
        ? { kind, workId: id }
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
    case "/$business/thread/$work":
      return `thread:${params.work}`;
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

/** The layer stack over the right panel, and how its top layer came to be there. */
export function useLayers() {
  const place = usePlace();
  const key = useRouterState({
    select: (state) => {
      const { app, layer } = searchIn(state);
      const { auto, updatedBy } = state.location.state;
      return JSON.stringify([app, layer, auto, updatedBy]);
    },
  });
  return useMemo(() => {
    const [app, layer, auto, updatedBy] = JSON.parse(key) as [
      string | undefined,
      string[] | undefined,
      boolean | undefined,
      string | undefined,
    ];
    const layers = layersOf({ ...(app ? { app } : {}), ...(layer ? { layer } : {}) }, place);
    return { layers, top: layers.at(-1), auto: Boolean(auto), updatedBy };
  }, [key, place]);
}

/** Whether the toolbar's Back has somewhere to go. */
export const useCanGoBack = () =>
  useRouterState({ select: (state) => (state.location.state.trail?.length ?? 0) > 0 });

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
    case "thread":
      return { to: "/$business/thread/$work", params: { business, work: place.workId } } as const;
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
      layers: layersOf(searchIn(state), place),
      history: state.location.state,
    };
  };
  const go = (
    place: Place,
    options: { trail?: Place[]; business?: string; replace?: boolean } = {},
  ) =>
    void router.navigate({
      ...routeOf(options.business ?? now().business, place),
      search: {},
      state: options.trail?.length ? { trail: options.trail } : {},
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
        ...(history.trail ? { trail: history.trail } : {}),
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
    /** Goes to a place from the sidebar: the layers close, Back starts over. */
    selectPlace: (place: Place) => {
      ui.leftPlace();
      go(place);
    },
    /** Opens the DM with an employee. */
    message: (employeeId: string) => nav.selectPlace({ kind: "direct", employeeId }),
    /** Moves into a work item's thread; Back returns to where the owner was. */
    openThread: (workId: string) => {
      const { place, history } = now();
      if (place.kind === "thread" && place.workId === workId) return;
      go({ kind: "thread", workId }, { trail: [...(history.trail ?? []), place] });
    },
    back: () => {
      const trail = now().history.trail ?? [];
      const previous = trail.at(-1);
      if (previous) go(previous, { trail: trail.slice(0, -1) });
    },
    /** Stacks a layer; an app starts a new stack, and opening what is on top does nothing. */
    openLayer: (layer: Layer) => {
      ui.openedLayer();
      const { layers } = now();
      if (JSON.stringify(layers.at(-1)) === JSON.stringify(layer)) return;
      setLayers(layer.kind === "app" || layer.kind === "browser" ? [layer] : [...layers, layer]);
    },
    /** Replaces the top layer, as stepping through a page's versions does. */
    replaceLayer: (layer: Layer) =>
      setLayers([...now().layers.slice(0, -1), layer], { replace: true }),
    /** Back one layer. */
    popLayer: () => setLayers(now().layers.slice(0, -1)),
    /** Back to the permanent view. */
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
      if (top?.kind === "artifact" && sameName(top.id, id))
        return setLayers([...layers.slice(0, -1), { kind: "artifact", id }], {
          replace: true,
          ...(history.auto ? { auto: true } : {}),
          ...(author ? { updatedBy: author } : {}),
        });
      if (top && !history.auto) return;
      setLayers([{ kind: "artifact", id }], { replace: true, auto: true });
    },
    openSettings: (section = "account") => {
      const { business, place, history } = now();
      void router.navigate({
        to: "/$business/settings/$section",
        params: { business, section },
        search: (current: Record<string, unknown>) => current as never,
        state: { ...(history.trail ? { trail: history.trail } : {}), behind: place },
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
