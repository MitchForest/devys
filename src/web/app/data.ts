/**
 * The business's records as components read them: each hook subscribes to one query, so a
 * component re-renders only when what it shows changed.
 */
import { useQueries, useQuery } from "@tanstack/react-query";
import { useParams } from "@tanstack/react-router";
import { useCallback } from "react";
import type { Home, Me as MeSchema, NeedsYouRequest, RuntimeState } from "../../app/wire.ts";
import type { ConversationKey, ConversationSummary } from "../../conversations/contract.ts";
import type { Employee } from "../../identity/contract.ts";
import type { Project, WorkItem } from "../../work/contract.ts";
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
/** The Connect apps sheet's list: official outside apps, by category. */
export const useListedApps = () =>
  useQuery({ ...queries.listed(useBusinessId()), select: (d) => d.apps });
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
const workUnreadOf = (d: { conversations: readonly { key: string; unread: number }[] }) =>
  new Map(
    d.conversations
      .filter((summary) => summary.key.startsWith("work:"))
      .map((summary) => [summary.key.slice("work:".length), summary.unread] as const),
  );
const workPinnedOf = (d: { conversations: readonly { key: string; pinned: boolean }[] }) =>
  new Set(
    d.conversations
      .filter((summary) => summary.pinned && summary.key.startsWith("work:"))
      .map((summary) => summary.key.slice("work:".length)),
  );
const day = 24 * 60 * 60_000;

/**
 * The work in the sidebar: what the owner pinned first, whatever its state, until unpinned; then
 * everything open, and finished work until the owner has seen how it ended (its last word unread)
 * for at most a day; it is archived after that, still found with ⌘K. Those waiting on the owner
 * first, then the ones running, then the rest, newest first.
 */
export function useActiveWork(): { item: WorkItem; pinned: boolean }[] {
  const work = useWork().data ?? [];
  const unread = useQuery({ ...queries.summaries(useBusinessId()), select: workUnreadOf }).data;
  const pinned = useQuery({ ...queries.summaries(useBusinessId()), select: workPinnedOf }).data;
  const asked = new Set((useDecisions().data ?? []).flatMap((d) => d.work_item_id ?? []));
  const now = Date.now();
  const shown = work.filter(
    (item) =>
      !pinned?.has(item.id) &&
      (item.state === "completed"
        ? (unread?.get(item.id) ?? 0) > 0 && now - Date.parse(item.updated_at) < day
        : item.state !== "cancelled"),
  );
  const rank = (item: WorkItem) =>
    asked.has(item.id) || item.state === "proposed" || item.state === "needs_decision"
      ? 0
      : item.state === "in_progress" || item.state === "ready"
        ? 1
        : item.state === "completed"
          ? 3
          : 2;
  return [
    ...work.filter((item) => pinned?.has(item.id)).map((item) => ({ item, pinned: true })),
    ...shown
      .toSorted((a, b) => rank(a) - rank(b) || b.updated_at.localeCompare(a.updated_at))
      .map((item) => ({ item, pinned: false })),
  ];
}

/** Work items the signed-in person follows, by id. */
export const useFollowed = (): readonly string[] =>
  useQuery({ ...queries.summaries(useBusinessId()), select: followedOf }).data ?? none;

/**
 * One conversation in the sidebar: an employee's direct chat (the Chief of Staff's is Home) or a
 * project's channel, with how the signed-in person keeps it.
 */
export type SidebarRow = {
  key: ConversationKey;
  place: Place;
  title: string;
  last: ConversationSummary["last"];
  unread: number;
  pinned: boolean;
  hidden: boolean;
} & (
  | { kind: "employee"; employee: Employee }
  | { kind: "project"; project: Project; index: number }
);

const summariesOf = (d: { conversations: readonly ConversationSummary[] }) => d.conversations;
/**
 * The sidebar: every employee and project, whether or not anything was said yet, joined with
 * the person's marks. Each section has its pinned rows first; hidden rows are left out until
 * something new is said; the rest of the team is most recent first.
 */
export function useSidebar() {
  const employees = useEmployees();
  const chiefOfStaff = useChiefOfStaff();
  const projects = useProjects().data ?? none;
  const summaries =
    useQuery({ ...queries.summaries(useBusinessId()), select: summariesOf }).data ?? none;
  const summary = (key: string) => summaries.find((c) => c.key === key);
  const rows: SidebarRow[] = [
    ...employees.map((employee): SidebarRow => {
      const key = `direct:${employee.id}` as ConversationKey;
      const found = summary(key);
      return {
        kind: "employee",
        employee,
        key,
        place:
          employee.id === chiefOfStaff?.id
            ? { kind: "home" }
            : { kind: "direct", employeeId: employee.id },
        title: employee.name,
        last: found?.last ?? null,
        unread: found?.unread ?? 0,
        pinned: found?.pinned ?? false,
        hidden: found?.hidden ?? false,
      };
    }),
    ...projects.map((project, index): SidebarRow => {
      const key = `project:${project.id}` as ConversationKey;
      const found = summary(key);
      return {
        kind: "project",
        project,
        index,
        key,
        place: { kind: "project", id: project.id },
        title: project.name,
        last: found?.last ?? null,
        unread: found?.unread ?? 0,
        pinned: found?.pinned ?? false,
        hidden: found?.hidden ?? false,
      };
    }),
  ];
  const latest = (row: SidebarRow) => row.last?.created_at ?? "";
  const shown = rows.filter((row) => !row.hidden);
  const employeeRows = shown.filter((row) => row.kind === "employee");
  const projectRows = shown.filter((row) => row.kind === "project");
  return {
    // Pinned first, in the team's order; then most recent first, those nobody has spoken in
    // yet keeping the team's order after them.
    team: [
      ...employeeRows.filter((row) => row.pinned),
      ...employeeRows
        .filter((row) => !row.pinned)
        .map((row, order) => ({ row, order }))
        .sort((a, b) => latest(b.row).localeCompare(latest(a.row)) || a.order - b.order)
        .map(({ row }) => row),
    ],
    projects: [
      ...projectRows.filter((row) => row.pinned),
      ...projectRows.filter((row) => !row.pinned),
    ],
  };
}

/** One employee's runtime, read every five seconds so presence and spend are real. */
export const useStatus = (employeeId: string | undefined) =>
  useQuery({
    ...queries.status(useBusinessId(), employeeId ?? ""),
    enabled: Boolean(employeeId),
    select: (d) => d.state,
  });

/** Employees running a turn in this conversation now, whoever sent what woke them. */
export function useRunningIn(key: string | undefined) {
  const businessId = useBusinessId();
  const employees = useEmployees();
  const statuses = useQueries({
    queries: employees.map((employee) => ({
      ...queries.status(businessId, employee.id),
      enabled: key !== undefined,
    })),
  });
  return employees
    .filter((_, index) => {
      const run = statuses[index]?.data?.state.run;
      return key !== undefined && run && !run.stopped && run.conversation === key;
    })
    .map((employee) => employee.id);
}

/** An employee's runtime has a run going. */
export const isRunning = (state: RuntimeState | undefined) =>
  Boolean(state?.run && !state.run.stopped);
/** An employee's runtime has something in its inbox it hasn't finished. */
export const unfinished = (state: RuntimeState | undefined) =>
  state?.inbox.some((i) => i.status !== "done" && i.status !== "failed") ?? false;

/** A place's title: the employee's or project's name. */
export function usePlaceTitle(place: Place): string {
  const employees = useEmployees();
  const projects = useProjects().data;
  switch (place.kind) {
    case "home":
      // Home is the Chief of Staff's chat, named for them.
      return employees.find((e) => e.template === "chief-of-staff")?.name ?? "Home";
    case "direct":
      return employees.find((e) => e.id === place.employeeId)?.name ?? "Message";
    case "project":
      return projects?.find((p) => p.id === place.id)?.name ?? "Project";
  }
}
