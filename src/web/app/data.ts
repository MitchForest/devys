/**
 * The business's records as components read them: each hook subscribes to one query, so a
 * component re-renders only when what it shows changed.
 */
import { useQuery } from "@tanstack/react-query";
import { useParams } from "@tanstack/react-router";
import { useCallback } from "react";
import type { Home, Me as MeSchema, NeedsYouRequest, RuntimeState } from "../../app/wire.ts";
import type { ConversationKey } from "../../conversations/contract.ts";
import type { Employee } from "../../identity/contract.ts";
import { api } from "./api.ts";
import type { Place } from "./navigation.ts";
import { meQuery, queries, keys } from "./query.ts";

const none: readonly never[] = [];

/** The business on screen, from the URL. */
export const useBusinessId = () =>
  useParams({ strict: false, select: (params) => params.business ?? "" });

export const useMe = () => useQuery(meQuery);
export const usePerson = () => useQuery({ ...meQuery, select: (me) => me?.person }).data;
export const useBusinesses = () =>
  useQuery({ ...meQuery, select: (me) => me?.businesses ?? none }).data ?? none;
export function useBusiness() {
  const id = useBusinessId();
  return useQuery({
    ...meQuery,
    select: useCallback((me: Me | null) => me?.businesses.find((b) => b.id === id), [id]),
  }).data;
}
type Me = typeof MeSchema.Type;

/** The owner's own photo, as a data URL; undefined when they have none. */
export function useOwnerPhoto() {
  const person = usePerson();
  return (
    useQuery({
      queryKey: keys.ownerPhoto(person?.id ?? ""),
      enabled: Boolean(person),
      staleTime: Infinity,
      queryFn: async () => {
        const response = await fetch(api.profilePhotoUrl, { cache: "no-store" });
        if (!response.ok) return null;
        const blob = await response.blob();
        return await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result as string);
          reader.onerror = () => reject(reader.error);
          reader.readAsDataURL(blob);
        });
      },
    }).data ?? undefined
  );
}

const useDetail = <T>(select: (detail: Awaited<ReturnType<typeof api.business>>) => T) =>
  useQuery({ ...queries.detail(useBusinessId()), select }).data;
const employeesOf = (d: { employees: readonly Employee[] }) => d.employees;
export const useEmployees = () => useDetail(employeesOf) ?? none;
export const useMembers = () => useDetail((d) => d.members) ?? none;
export const useArtifacts = () => useDetail((d) => d.artifacts) ?? none;
const chiefOfStaffOf = (d: { employees: readonly Employee[] }) =>
  d.employees.find((e) => e.template === "chief-of-staff") ?? d.employees[0];
/** The Chief of Staff: Home's conversation. */
export const useChiefOfStaff = () => useDetail(chiefOfStaffOf);

/** An employee's name by id, for rows that only hold the id. */
export function useEmployeeName() {
  const employees = useEmployees();
  return useCallback(
    (id: string) => employees.find((e) => e.id === id)?.name ?? "A former employee",
    [employees],
  );
}
export const useWork = () =>
  useQuery({ ...queries.work(useBusinessId()), select: (d) => d.work_items });
const decisionsOf = (home: Home) =>
  home.needs_you.filter(
    (item): item is NeedsYouRequest => item.kind !== "work" && item.kind !== "reconnect",
  );
/** Requests waiting on the owner, from Home: the one source of what needs them. */
export const useDecisions = () =>
  useQuery({ ...queries.home(useBusinessId()), select: decisionsOf });
export const useProjects = () =>
  useQuery({ ...queries.projects(useBusinessId()), select: (d) => d.projects });
export const useRoutines = () =>
  useQuery({ ...queries.routines(useBusinessId()), select: (d) => d.routines });
export const useApps = () => useQuery({ ...queries.apps(useBusinessId()), select: (d) => d.apps });
export const useAppReview = (app: string) => useQuery(queries.appReview(useBusinessId(), app));
export const useAppSearch = (query: string) =>
  useQuery({ ...queries.appSearch(useBusinessId(), query), select: (d) => d.apps });
export const useHome = () => useQuery(queries.home(useBusinessId()));
export const useMemory = () =>
  useQuery({ ...queries.memory(useBusinessId()), select: (d) => d.items });
export const useModels = () => useQuery(queries.models);
export const useRoles = () => useQuery({ ...queries.roles, select: (d) => d.roles });

/** Unread messages in one conversation. */
export function useUnread(key: ConversationKey | undefined) {
  return (
    useQuery({
      ...queries.summaries(useBusinessId()),
      select: useCallback(
        (d: { conversations: readonly { key: string; unread: number }[] }) =>
          d.conversations.find((c) => c.key === key)?.unread ?? 0,
        [key],
      ),
    }).data ?? 0
  );
}
const followedOf = (d: { conversations: readonly { key: string; following: boolean }[] }) =>
  d.conversations
    .filter((summary) => summary.following && summary.key.startsWith("work:"))
    .map((summary) => summary.key.slice("work:".length));
/** Work items the signed-in person follows, by id. */
export const useFollowed = (): readonly string[] =>
  useQuery({ ...queries.summaries(useBusinessId()), select: followedOf }).data ?? none;

/** One employee's runtime, read every five seconds so presence and spend are real. */
export const useStatus = (employeeId: string | undefined) =>
  useQuery({
    ...queries.status(useBusinessId(), employeeId ?? ""),
    enabled: Boolean(employeeId),
    select: (d) => d.state,
  });

/** An employee's runtime has a run going. */
export const isRunning = (state: RuntimeState | undefined) =>
  Boolean(state?.run && !state.run.stopped);
/** An employee's runtime has something in its inbox it hasn't finished. */
export const unfinished = (state: RuntimeState | undefined) =>
  state?.inbox.some((i) => i.status !== "done" && i.status !== "failed") ?? false;

/**
 * A place's title, and in a thread the place above it (its project) so the breadcrumb reads
 * "Launch › Fix sitemap".
 */
export function usePlaceTitle(place: Place): {
  title: string;
  parent?: { title: string; place: Place };
} {
  const employees = useEmployees();
  const projects = useProjects().data;
  const work = useWork().data;
  switch (place.kind) {
    case "home":
      // Home is the Chief of Staff's chat, named for them.
      return { title: employees.find((e) => e.template === "chief-of-staff")?.name ?? "Home" };
    case "direct":
      return { title: employees.find((e) => e.id === place.employeeId)?.name ?? "Message" };
    case "project":
      return { title: projects?.find((p) => p.id === place.id)?.name ?? "Project" };
    case "thread": {
      const item = work?.find((w) => w.id === place.workId);
      const project = item?.project_id && projects?.find((p) => p.id === item.project_id);
      return {
        title: item?.title ?? "Thread",
        ...(project
          ? { parent: { title: project.name, place: { kind: "project", id: project.id } } }
          : {}),
      };
    }
  }
}
