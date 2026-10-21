/**
 * Server reads, one query key per resource. Every read goes through TanStack Query: polling
 * with `refetchInterval` (paused while the tab is hidden), shared requests, and the error a
 * failed read really had. A 401 from any read or change signs this browser out, here only.
 */
import {
  MutationCache,
  QueryCache,
  QueryClient,
  queryOptions,
  type QueryKey,
} from "@tanstack/react-query";
import type { ConversationKey } from "../../conversations/contract.ts";
import { api, ApiError } from "./api.ts";

/** How often what the shell shows is read again, as on native. */
export const poll = 5_000;

export const keys = {
  me: ["me"] as const,
  ownerPhoto: (person: string) => ["owner-photo", person] as const,
  models: ["models"] as const,
  roles: ["roles"] as const,
  devices: ["devices"] as const,
  /** Everything one business holds starts with this; ⌘R reads it all again. */
  business: (b: string) => ["business", b] as const,
  detail: (b: string) => ["business", b, "detail"] as const,
  work: (b: string) => ["business", b, "work"] as const,
  workDecisions: (b: string, work: string, revision: number) =>
    ["business", b, "decisions", work, revision] as const,
  projects: (b: string) => ["business", b, "projects"] as const,
  home: (b: string) => ["business", b, "home"] as const,
  apps: (b: string) => ["business", b, "apps"] as const,
  memory: (b: string) => ["business", b, "memory"] as const,
  summaries: (b: string) => ["business", b, "summaries"] as const,
  conversation: (b: string, key: ConversationKey) => ["business", b, "conversation", key] as const,
  status: (b: string, employee: string) => ["business", b, "status", employee] as const,
  access: (b: string, employee: string) => ["business", b, "access", employee] as const,
  folder: (b: string, path: string | null) => ["business", b, "folder", path] as const,
  file: (b: string, path: string, turn: number) => ["business", b, "file", path, turn] as const,
  artifact: (b: string, id: string) => ["business", b, "artifact", id] as const,
  codingWork: (b: string) => ["business", b, "coding"] as const,
  sessions: (b: string, work: string) => ["business", b, "sessions", work] as const,
  diff: (b: string, work: string, session: string) =>
    ["business", b, "sessions", work, session, "diff"] as const,
  transcript: (b: string, work: string, session: string) =>
    ["business", b, "sessions", work, session, "transcript"] as const,
  terminals: (b: string) => ["business", b, "terminals"] as const,
  browser: (b: string) => ["business", b, "browser"] as const,
  screenshot: (b: string) => ["business", b, "browser", "screenshot"] as const,
  google: (b: string) => ["business", b, "google"] as const,
};

/** The message a failed read shows the owner. */
export const problemOf = (error: unknown, fallback: string) =>
  error instanceof ApiError
    ? error.status === 404
      ? fallback
      : error.message || fallback
    : error instanceof TypeError
      ? "The server isn't reachable."
      : error instanceof Error
        ? error.message
        : fallback;

/** A 401 means this browser's session ended: everything shows signed out. */
export const expireOn401 = (client: QueryClient, error: unknown) => {
  if (!(error instanceof ApiError && error.status === 401)) return;
  void client.cancelQueries();
  client.setQueryData(keys.me, null);
};

/** One client per browser (and per server render); a 401 anywhere means signed out. */
export function makeQueryClient() {
  const expire = (error: unknown) => expireOn401(client, error);
  const client: QueryClient = new QueryClient({
    queryCache: new QueryCache({ onError: expire }),
    mutationCache: new MutationCache({ onError: expire }),
    defaultOptions: {
      queries: {
        staleTime: 2_000,
        // A refusal is the answer; only a network or server failure is worth one more try.
        retry: (count, error) => count < 1 && !(error instanceof ApiError && error.status < 500),
      },
    },
  });
  return client;
}

/** The signed-in person and their businesses; null when this browser is signed out. */
export const meQuery = queryOptions({
  queryKey: keys.me,
  queryFn: async () => {
    try {
      return await api.me();
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) return null;
      throw error;
    }
  },
  // Looks and pauses changed from another client show here within one tick.
  refetchInterval: poll,
});

export const queries = {
  detail: (b: string) =>
    queryOptions({
      queryKey: keys.detail(b),
      queryFn: () => api.business(b),
      refetchInterval: poll,
    }),
  work: (b: string) =>
    queryOptions({ queryKey: keys.work(b), queryFn: () => api.work(b), refetchInterval: poll }),
  projects: (b: string) =>
    queryOptions({
      queryKey: keys.projects(b),
      queryFn: () => api.projects(b),
      refetchInterval: poll,
    }),
  home: (b: string) =>
    queryOptions({ queryKey: keys.home(b), queryFn: () => api.home(b), refetchInterval: poll }),
  summaries: (b: string) =>
    queryOptions({
      queryKey: keys.summaries(b),
      queryFn: () => api.conversations(b),
      refetchInterval: poll,
    }),
  status: (b: string, employee: string) =>
    queryOptions({
      queryKey: keys.status(b, employee),
      queryFn: () => api.status(b, employee),
      refetchInterval: poll,
    }),
  apps: (b: string) => queryOptions({ queryKey: keys.apps(b), queryFn: () => api.apps(b) }),
  memory: (b: string) => queryOptions({ queryKey: keys.memory(b), queryFn: () => api.memory(b) }),
  models: queryOptions({ queryKey: keys.models, queryFn: api.models, staleTime: Infinity }),
  roles: queryOptions({ queryKey: keys.roles, queryFn: api.roles, staleTime: Infinity }),
};

/** Reads again everything a change may have touched. */
export const invalidate = (client: QueryClient, ...queryKeys: QueryKey[]) =>
  Promise.all(queryKeys.map((queryKey) => client.invalidateQueries({ queryKey })));
