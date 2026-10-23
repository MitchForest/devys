/**
 * Changes the owner makes, each a TanStack Query mutation: it shows the change at once where
 * that is safe, puts it back if the server refuses, says why in the notice, and reads again
 * what it touched.
 */
import {
  useMutation,
  useQueryClient,
  type QueryClient,
  type QueryKey,
} from "@tanstack/react-query";
import type { BusinessDetail, Conversations, Home, Me, Routines } from "../../app/wire.ts";
import type { RemotePolicy } from "../../apps/contract.ts";
import type { ConversationKey } from "../../conversations/contract.ts";
import type { Employee, SettableLook } from "../../identity/contract.ts";
import type { Ref } from "../../protocol/ref.ts";
import type {
  NewWorkItem,
  ProjectChange,
  Routine,
  WorkItem,
  WorkItemState,
} from "../../work/contract.ts";
import { api, ApiError, type StartingRole } from "./api.ts";
import { useBusinessId } from "./data.ts";
import { downscale } from "./images.ts";
import { useNav } from "./navigation.ts";
import { invalidate, keys, meQuery } from "./query.ts";
import { ui } from "./ui.ts";

type Detail = typeof BusinessDetail.Type;

/** A refusal as the owner reads it: a 409 means it changed meanwhile and the latest shows. */
const refusal = (error: unknown, failure: string) =>
  error instanceof ApiError && error.status === 409
    ? `${failure} It changed; showing the latest.`
    : failure;

/** A change to this business that, refused, says so in the notice; it reads `settles` again. */
function useChange<V, R>(
  run: (business: string, value: V) => Promise<R>,
  {
    failure,
    settles,
    optimistic,
    succeeded,
  }: {
    failure?: string | ((value: V, error: unknown) => string);
    settles: (business: string, value: V) => QueryKey[];
    /** Shows the change before the server answers; returns how to put it back. */
    optimistic?: (client: QueryClient, business: string, value: V) => () => void;
    succeeded?: (result: R, value: V) => void;
  },
) {
  const client = useQueryClient();
  const business = useBusinessId();
  return useMutation({
    mutationFn: (value: V) => run(business, value),
    onMutate: async (value: V) => {
      if (!optimistic) return undefined;
      await client.cancelQueries({ queryKey: keys.business(business) });
      return optimistic(client, business, value);
    },
    onError: (error, value, rollback) => {
      rollback?.();
      if (failure)
        ui.notify(typeof failure === "string" ? refusal(error, failure) : failure(value, error));
    },
    onSuccess: (result, value) => succeeded?.(result, value),
    onSettled: (_result, _error, value) => invalidate(client, ...settles(business, value)),
  });
}

/** Changes the team as it shows, until the server answers. */
const editEmployees = (
  client: QueryClient,
  business: string,
  change: (employee: Employee) => Employee,
) => {
  const before = client.getQueryData<Detail>(keys.detail(business));
  client.setQueryData<Detail>(
    keys.detail(business),
    (detail) => detail && { ...detail, employees: detail.employees.map(change) },
  );
  return () => client.setQueryData(keys.detail(business), before);
};
const workSettles = (b: string) => [keys.work(b), keys.detail(b), keys.home(b)];

export function useAnswer() {
  return useChange(
    (b, { id, approve }: { id: string; approve: boolean }) => api.answer(b, id, approve),
    {
      failure: "That request was already answered or has expired.",
      // Approving a routine's activation changes it once its employee activates it.
      settles: (b) => [...workSettles(b), keys.routines(b)],
      optimistic: (client, b, { id }) => {
        const before = client.getQueryData<Home>(keys.home(b));
        client.setQueryData<Home>(
          keys.home(b),
          (home) =>
            home && {
              ...home,
              needs_you: home.needs_you.filter((d) => d.kind === "reconnect" || d.id !== id),
            },
        );
        return () => client.setQueryData(keys.home(b), before);
      },
    },
  );
}

/** A file request answered with the file the owner chose. */
export function useSendFile() {
  return useChange((b, { id, file }: { id: string; file: File }) => api.sendFile(b, id, file), {
    failure: "That file wasn't sent.",
    settles: (b) => workSettles(b),
    optimistic: (client, b, { id }) => {
      const before = client.getQueryData<Home>(keys.home(b));
      client.setQueryData<Home>(
        keys.home(b),
        (home) =>
          home && {
            ...home,
            needs_you: home.needs_you.filter((d) => d.kind === "reconnect" || d.id !== id),
          },
      );
      return () => client.setQueryData(keys.home(b), before);
    },
  });
}

type WorkChange = {
  state?: WorkItemState;
  owner?: string;
  next_action?: string;
  wait_condition?: string | null;
  due_at?: string | null;
};
/** A change to a work item at the revision on screen. */
export function useUpdateWorkItem() {
  return useChange(
    (b, { item, change }: { item: WorkItem; change: WorkChange; failure: string }) =>
      api.updateWorkItem(b, item, change),
    { failure: ({ failure }, error) => refusal(error, failure), settles: workSettles },
  );
}

export function useTakeover() {
  return useChange(
    (b, item: WorkItem) => api.setTakeover(b, item.id, item.taken_over_by === null),
    { failure: "Couldn't change who handles that work.", settles: workSettles },
  );
}

/**
 * The owner takes the work over (which fences its employee) and the business's own Chrome comes
 * to the front on the Mac; where it can't (no host here), the live browser opens beside the
 * thread. Hand back returns it.
 */
export function useOpenChrome() {
  const nav = useNav();
  return useChange(
    async (b, workId: string) => {
      await api.setTakeover(b, workId, true);
      return api.browserFront(b).then(
        () => true,
        () => false,
      );
    },
    {
      failure: "Couldn't take that work over.",
      settles: workSettles,
      succeeded: (fronted, workId) => {
        if (!fronted) nav.openBrowser(workId);
      },
    },
  );
}

/** Start on a proposed plan: shown started at once, handed to its employee by the server. */
export function useStartWork() {
  return useChange((b, item: WorkItem) => api.startWork(b, item.id), {
    failure: "That plan has already started.",
    settles: workSettles,
    optimistic: (client, b, item) => {
      const before = client.getQueryData<{ work_items: WorkItem[] }>(keys.work(b));
      client.setQueryData<{ work_items: WorkItem[] }>(
        keys.work(b),
        (work) =>
          work && {
            ...work,
            work_items: work.work_items.map((each) =>
              each.id === item.id ? { ...each, state: "ready" } : each,
            ),
          },
      );
      return () => client.setQueryData(keys.work(b), before);
    },
  });
}

/** Hear each milestone of a work item (and keep it in the sidebar), or only its outcome. */
export function useFollow() {
  return useChange(
    (b, { workId, on }: { workId: string; on: boolean }) =>
      api.follow(b, `work:${workId}` as ConversationKey, on),
    {
      settles: (b) => [keys.summaries(b)],
      optimistic: (client, b, { workId, on }) => {
        const key = `work:${workId}` as ConversationKey;
        const before = client.getQueryData<typeof Conversations.Type>(keys.summaries(b));
        client.setQueryData<typeof Conversations.Type>(keys.summaries(b), (all) => {
          const list = all?.conversations ?? [];
          const found = list.find((c) => c.key === key);
          return {
            conversations: found
              ? list.map((c) => (c.key === key ? { ...c, following: on } : c))
              : [
                  ...list,
                  { key, last: null, unread: 0, following: on, pinned: false, hidden: false },
                ],
          };
        });
        return () => client.setQueryData(keys.summaries(b), before);
      },
    },
  );
}

/** A work item the owner started: they follow it, and its thread opens. */
export function useCreateWorkItem() {
  const nav = useNav();
  const follow = useFollow();
  return useChange((b, workItem: NewWorkItem) => api.createWorkItem(b, workItem), {
    settles: workSettles,
    succeeded: (created) => {
      follow.mutate({ workId: created.id, on: true });
      nav.openThread(created.id);
    },
  });
}

/**
 * Starts a thread on a message: a work item owned by whoever it addressed, in the project it
 * was said in, titled from the message.
 */
export function useStartThread() {
  const nav = useNav();
  const follow = useFollow();
  return useChange(
    (b, { text, owner, projectId }: { text: string; owner: string; projectId?: string }) => {
      const body = text.trim();
      return api.createWorkItem(b, {
        title: body.split("\n")[0]!.slice(0, 80),
        owner,
        objective: body.slice(0, 4000),
        ...(projectId ? { project_id: projectId } : {}),
      });
    },
    {
      failure: "That thread couldn't be started.",
      settles: workSettles,
      succeeded: (created) => {
        follow.mutate({ workId: created.id, on: true });
        nav.openThread(created.id);
      },
    },
  );
}

export function useCreateProject() {
  const nav = useNav();
  return useChange(
    (b, project: ProjectChange & { name: string }) => api.createProject(b, project),
    {
      failure: "The project couldn't be created.",
      settles: workSettles,
      succeeded: (created) => nav.selectPlace({ kind: "project", id: created.id }),
    },
  );
}
/** Keeps a record on a project's overview, or stops keeping it. */
export function useKeep() {
  return useChange(
    (
      b,
      keep: { projectId: string; add: Ref } | { projectId: string; remove: string },
    ): Promise<unknown> =>
      "add" in keep
        ? api.addToProject(b, keep.projectId, keep.add)
        : api.removeFromProject(b, keep.projectId, keep.remove),
    {
      failure: (keep, error) =>
        refusal(
          error,
          "add" in keep ? "That couldn't be added to the project." : "That couldn't be removed.",
        ),
      settles: (b) => [keys.projects(b)],
    },
  );
}

export function useInstallApp() {
  return useChange((b, { app, on }: { app: string; on: boolean }) => api.installApp(b, app, on), {
    failure: ({ on }) => (on ? "That app couldn't be installed." : "That app couldn't be removed."),
    settles: (b) => [keys.apps(b)],
  });
}
export function usePinApp() {
  return useChange(
    (b, { app, pinned }: { app: string; pinned: boolean }) => api.pinApp(b, app, pinned),
    {
      settles: (b) => [keys.apps(b)],
      optimistic: (client, b, { app, pinned }) => {
        type Apps = Awaited<ReturnType<typeof api.apps>>;
        const before = client.getQueryData<Apps>(keys.apps(b));
        client.setQueryData<Apps>(
          keys.apps(b),
          (all) => all && { apps: all.apps.map((a) => (a.id === app ? { ...a, pinned } : a)) },
        );
        return () => client.setQueryData(keys.apps(b), before);
      },
    },
  );
}

export function useGrant() {
  return useChange(
    (b, grant: { employeeId: string; capability: string; mode: "auto" | "ask" }) =>
      api.grant(b, grant.employeeId, grant.capability, grant.mode),
    {
      failure: "That access change didn't go through.",
      settles: (b, { employeeId }) => [keys.access(b, employeeId), ...workSettles(b)],
    },
  );
}
export function useRevoke() {
  return useChange(
    (b, { employeeId, grantId }: { employeeId: string; grantId: string }) =>
      api.revoke(b, employeeId, grantId),
    {
      failure: "That access change didn't go through.",
      settles: (b, { employeeId }) => [keys.access(b, employeeId), ...workSettles(b)],
    },
  );
}

export function useTogglePause() {
  return useChange((b, employee: Employee) => api.setPaused(b, employee.id, !employee.paused), {
    failure: (employee) => `Couldn't ${employee.paused ? "resume" : "pause"} that employee.`,
    settles: workSettles,
    optimistic: (client, b, employee) =>
      editEmployees(client, b, (e) => (e.id === employee.id ? { ...e, paused: !e.paused } : e)),
  });
}

/** Pauses an active routine, or resumes a paused one at the revision the owner approved. */
export function useToggleRoutine() {
  return useChange(
    (b, routine: Routine) => api.setRoutinePaused(b, routine.id, routine.state === "active"),
    {
      failure: (routine) =>
        `Couldn't ${routine.state === "active" ? "pause" : "resume"} that routine.`,
      settles: (b) => [keys.routines(b), keys.home(b)],
      optimistic: (client, b, routine) => {
        const before = client.getQueryData<typeof Routines.Type>(keys.routines(b));
        const state = routine.state === "active" ? "paused" : "active";
        client.setQueryData<typeof Routines.Type>(
          keys.routines(b),
          (list) =>
            list && {
              routines: list.routines.map((r) => (r.id === routine.id ? { ...r, state } : r)),
            },
        );
        return () => client.setQueryData(keys.routines(b), before);
      },
    },
  );
}

/** Hires from a template and opens the new employee's chat. */
export function useHire() {
  const nav = useNav();
  return useChange(
    (b, input: { template: string; name?: string; responsibilities?: string; model?: string }) =>
      api.hire(b, input),
    { settles: (b) => [keys.detail(b)], succeeded: (hired) => nav.message(hired.id) },
  );
}

/** Renames an employee or rewrites their responsibilities. */
export function useSetProfile() {
  return useChange(
    (
      b,
      {
        employee,
        change,
      }: { employee: Employee; change: { name?: string; responsibilities?: string } },
    ) => api.setProfile(b, employee.id, change),
    {
      settles: (b) => [keys.detail(b)],
      optimistic: (client, b, { employee, change }) =>
        editEmployees(client, b, (e) =>
          e.id === employee.id
            ? {
                ...e,
                ...(change.name ? { name: change.name } : {}),
                ...(change.responsibilities ? { responsibilities: change.responsibilities } : {}),
              }
            : e,
        ),
    },
  );
}

/** Retires an employee; their open work moves to the successor, whose chat opens. */
export function useRetire() {
  const nav = useNav();
  return useChange(
    (b, { employee, successor }: { employee: Employee; successor: string }) =>
      api.retire(b, employee.id, successor),
    {
      failure: ({ employee }, error) =>
        error instanceof ApiError && error.status === 409
          ? "The Chief of Staff can't be retired."
          : `${employee.name} couldn't be retired.`,
      settles: workSettles,
      succeeded: (_result, { successor }) => nav.message(successor),
    },
  );
}

/** Shows the new model at once and puts the old one back if the server refuses. */
export function useSetEmployeeModel() {
  return useChange(
    (b, { employee, model }: { employee: Employee; model: string }) =>
      api.setEmployeeModel(b, employee.id, model),
    {
      settles: (b) => [keys.detail(b)],
      optimistic: (client, b, { employee, model }) =>
        editEmployees(client, b, (e) => (e.id === employee.id ? { ...e, model } : e)),
    },
  );
}

/** Looks live on the server, so every client shows the same one; any business's employee. */
export function useSetEmployeeLook() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ employee, look }: { employee: Employee; look: SettableLook }) =>
      api.setEmployeeLook(employee.business_id, employee.id, look),
    onMutate: ({ employee, look }) =>
      editEmployees(client, employee.business_id, (e) =>
        e.id === employee.id ? { ...e, look } : e,
      ),
    onError: (_error, _value, rollback) => {
      rollback?.();
      ui.notify("That look couldn't be saved.");
    },
    onSettled: (_r, _e, { employee }) => invalidate(client, keys.detail(employee.business_id)),
  });
}

export function useSetBusinessLook() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, look }: { id: string; look: SettableLook }) => api.setBusinessLook(id, look),
    onMutate: ({ id, look }) => {
      const before = client.getQueryData<typeof Me.Type | null>(keys.me);
      client.setQueryData<typeof Me.Type | null>(
        keys.me,
        (me) =>
          me && { ...me, businesses: me.businesses.map((b) => (b.id === id ? { ...b, look } : b)) },
      );
      return () => client.setQueryData(keys.me, before);
    },
    onError: (_error, _value, rollback) => {
      rollback?.();
      ui.notify("That look couldn't be saved.");
    },
    onSettled: () => invalidate(client, keys.me),
  });
}

/** Renames a business or rewrites its brief. */
export function useUpdateBusiness() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, change }: { id: string; change: { name?: string; brief?: string } }) =>
      api.updateBusiness(id, change),
    onSettled: () => invalidate(client, keys.me),
  });
}

/** A photo for a business's or an employee's look, downscaled before it is sent. */
export function useUploadLookPhoto() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({
      target,
      file,
    }: {
      target: { businessId: string; employeeId?: string };
      file: Blob;
    }) => {
      const path = target.employeeId
        ? api.employeePath(target.businessId, target.employeeId)
        : api.businessPath(target.businessId);
      return api.uploadLookPhoto(path, await downscale(file, 512));
    },
    onError: () => ui.notify("That photo couldn't be used. Try a JPEG or PNG."),
    onSettled: (_r, _e, { target }) => invalidate(client, keys.me, keys.detail(target.businessId)),
  });
}

/** The owner's own photo: set from a file, or removed. */
export function useOwnerPhotoChange() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (file: Blob | null) =>
      file ? api.uploadProfilePhoto(await downscale(file, 1024)) : api.removeProfilePhoto(),
    onSettled: () => client.invalidateQueries({ queryKey: ["owner-photo"] }),
  });
}

/** The name the signed-in person goes by. */
export function useRename() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => api.rename(name.trim()),
    onSuccess: (me) => client.setQueryData(keys.me, me),
  });
}

/** Creates a business with its brief and starting team, then switches to it. */
export function useCreateBusiness() {
  const client = useQueryClient();
  const nav = useNav();
  return useMutation({
    mutationFn: (input: { name: string; brief: string; team: StartingRole[] }) =>
      api.createBusiness({ name: input.name.trim(), brief: input.brief.trim(), team: input.team }),
    onSuccess: async (created) => {
      await client.refetchQueries({ queryKey: keys.me });
      nav.selectBusiness(created.business.id);
    },
  });
}

/** Signs this browser out; everything read for the last person is dropped. */
export function useSignOut() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.logout(),
    onSuccess: () => {
      client.clear();
      client.setQueryData(meQuery.queryKey, null);
    },
  });
}

/** Stops an employee's current run. */
export function useStop() {
  return useChange((b, employeeId: string) => api.stop(b, employeeId), {
    settles: (b, employeeId) => [keys.status(b, employeeId)],
    succeeded: () => ui.notify("Stop requested. Work already sent cannot be unsent."),
  });
}

/** Reads everything of this business again (⌘R). */
export function useRefresh() {
  const client = useQueryClient();
  const business = useBusinessId();
  return () => invalidate(client, keys.me, keys.business(business));
}

const appSettles = (b: string, app?: string) => [
  keys.apps(b),
  keys.home(b),
  ...(app ? [keys.appReview(b, app)] : []),
];

/** Adds a remote app (by what search found, or its address), not yet connected. */
export function useAddApp() {
  return useChange((b, app: string) => api.addApp(b, app), {
    failure: (_app, error) =>
      error instanceof ApiError && error.status < 500 && error.message
        ? error.message
        : "That app couldn't be added.",
    settles: (b) => appSettles(b),
  });
}

/**
 * Connects a remote app with its provider's own sign-in, in a popup opened by the click itself
 * (a popup opened later is blocked). When the popup closes, what it changed is read again.
 */
export function useConnectApp() {
  const client = useQueryClient();
  const business = useBusinessId();
  return (app: string) => {
    const popup = window.open("", "devys-connect", "popup,width=520,height=720");
    void api.connectApp(business, app).then(
      ({ url }) => {
        const settle = () => invalidate(client, ...appSettles(business, app));
        if (!url || !popup) {
          popup?.close();
          if (url) window.location.assign(url);
          return settle();
        }
        popup.location.href = url;
        const watch = window.setInterval(() => {
          if (!popup.closed) return;
          window.clearInterval(watch);
          void settle();
        }, 500);
      },
      (error: unknown) => {
        popup?.close();
        ui.notify(
          error instanceof ApiError && error.status < 500 && error.message
            ? error.message
            : "That app couldn't be connected.",
        );
      },
    );
  };
}

/** The owner turns a remote app on (or changes it): their choices are its policy. */
export function useAcceptApp() {
  return useChange(
    (b, { app, acceptance }: { app: string; acceptance: RemotePolicy }) =>
      api.acceptApp(b, app, acceptance),
    {
      failure: "That app couldn't be turned on.",
      settles: (b, { app }) => [...appSettles(b, app), keys.work(b)],
    },
  );
}
