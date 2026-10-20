import type { Commitment, CommitmentState, Employee, RoleTemplateId } from "./api.ts";
import type { Tone } from "../design/primitives.tsx";
import type { Mood } from "../design/face.tsx";
import type { Page, WorkFilter, WorkspaceState } from "./workspace.tsx";
import { valueOf } from "./workspace.tsx";

/** Plain names for capabilities, as native `AccessNames`; the description carries the detail. */
const titles: Record<string, string> = {
  recall: "Recall memory",
  remember: "Remember facts",
  forget: "Forget facts",
  readPublicUrl: "Read public websites",
  listSkills: "List skills",
  importAttachment: "Import attachments",
  read: "Read workspace files",
  write: "Write workspace files",
  run: "Run commands",
  conversationHistory: "Read older conversation",
  publishArtifact: "Save files for you",
  driveList: "List Drive files",
  driveRead: "Read Drive files",
  driveCreate: "Create Drive files",
  driveUpdate: "Update Drive files",
  commitmentList: "List work",
  commitmentCreate: "Take on work",
  commitmentUpdate: "Update work",
  commitmentComplete: "Complete work",
  spaceList: "List spaces",
  spaceCreate: "Create spaces",
  spaceAdd: "Add to spaces",
  hireEmployee: "Propose hires",
};
export const accessTitle = (capability: string) => titles[capability] ?? capability;

const templateTitles: Record<RoleTemplateId, string> = {
  operations: "Head of Operations",
  engineering: "Engineering",
  growth: "Growth",
  "business-operations": "Business Operations",
  custom: "Custom role",
};
/** The role an employee was hired into, as a short title; responsibilities carry the detail. */
export const templateTitle = (template: string) =>
  templateTitles[template as RoleTemplateId] ?? template;

export const workFilters: { value: WorkFilter; title: string }[] = [
  { value: "all", title: "All work" },
  { value: "needsYou", title: "Needs you" },
  { value: "inProgress", title: "In progress" },
  { value: "waiting", title: "Waiting" },
  { value: "done", title: "Done" },
];
export const filterTitle = (filter: WorkFilter) =>
  workFilters.find((f) => f.value === filter)!.title;

export const chipFor = (state: CommitmentState): { title: string; tone: Tone } =>
  state === "needs_decision"
    ? { title: "Needs you", tone: "needsYou" }
    : state === "in_progress"
      ? { title: "In progress", tone: "inProgress" }
      : state === "waiting"
        ? { title: "Waiting", tone: "waiting" }
        : state === "completed"
          ? { title: "Done", tone: "done" }
          : state === "cancelled"
            ? { title: "Cancelled", tone: "waiting" }
            : { title: "Ready", tone: "waiting" };

export const isOpen = (state: CommitmentState) => state !== "completed" && state !== "cancelled";

export function pageTitle(state: WorkspaceState, page: Page = state.page): string {
  if (state.expanded && state.selectedWork)
    return valueOf(state.work)?.find((w) => w.id === state.selectedWork)?.title ?? "Task";
  switch (page.kind) {
    case "today":
      return "Today";
    case "approvals":
      return "Approvals";
    case "files":
      return "Files";
    case "direct":
      return state.employees.find((e) => e.id === page.employeeId)?.name ?? "Message";
    case "space":
      return valueOf(state.spaces)?.find((s) => s.id === page.id)?.name ?? "Space";
    case "employee":
      return state.employees.find((e) => e.id === page.id)?.name ?? "Team";
    case "inbox":
      return "Inbox";
    case "work":
      return page.filter === "all" ? "Work" : filterTitle(page.filter);
    case "money":
      return "Money";
    case "apps":
      return page.section === "installed" ? "Installed" : "Connections";
  }
}

/** An employee's face: Operations follows the voice conversation; everyone else their runtime. */
export function moodOf(state: WorkspaceState, employee: Employee): Mood {
  if (employee.id === state.operations?.id) return operationsMood(state);
  const status = state.statusOf(employee.id);
  if (status.status === "failed") return "oops";
  return state.workingOf(employee.id) ? "working" : "idle";
}

export function operationsMood(state: WorkspaceState): Mood {
  // While talking by voice, Operations' face follows the conversation.
  const voice = state.voice.kind;
  if (voice === "starting" || voice === "listening" || voice === "finishing") return "listening";
  if (voice === "awaitingReply") return "thinking";
  if (voice === "speaking") return "working";
  if (state.status.status === "failed") return "oops";
  if (state.status.status === "loading") return "thinking";
  return state.isRunning ? "working" : "idle";
}

export type Signal =
  | { kind: "working" }
  | { kind: "needsYou"; count: number }
  | { kind: "failed" }
  | { kind: "paused" };
export interface Presence {
  employee: Employee;
  signal: Signal;
  summary: string;
}

/** Teammates worth a glance: working, waiting on you, failed or paused. Idle ones aren't shown. */
export function presence(state: WorkspaceState): Presence[] {
  return state.employees.flatMap((employee) => {
    const status = valueOf(state.statusOf(employee.id));
    const decisions =
      valueOf(state.decisions)?.filter((d) => d.employee_id === employee.id).length ?? 0;
    const latest = [...(status?.inbox ?? [])].sort((a, b) => b.receivedAt - a.receivedAt)[0];
    let signal: Signal | undefined;
    if (employee.paused || status?.run?.stopped) signal = { kind: "paused" };
    else if (state.workingOf(employee.id)) signal = { kind: "working" };
    else if (decisions > 0) signal = { kind: "needsYou", count: decisions };
    else if (latest?.status === "failed") signal = { kind: "failed" };
    if (!signal) return [];
    const summary =
      signal.kind === "working"
        ? `${employee.name} is working`
        : signal.kind === "needsYou"
          ? `${employee.name} needs you · ${signal.count} decision${signal.count === 1 ? "" : "s"}`
          : signal.kind === "failed"
            ? `${employee.name} couldn't finish the last request`
            : `${employee.name} is paused`;
    return [{ employee, signal, summary }];
  });
}

export const moodFor = (signal: Signal): Mood =>
  signal.kind === "working"
    ? "working"
    : signal.kind === "needsYou"
      ? "waiting"
      : signal.kind === "failed"
        ? "oops"
        : "off";

export const formatBytes = (bytes: number) =>
  bytes < 1024
    ? `${bytes} bytes`
    : bytes < 1024 * 1024
      ? `${(bytes / 1024).toFixed(0)} KB`
      : `${(bytes / 1024 / 1024).toFixed(1)} MB`;

/**
 * Who has taken a work item over, as the signed-in person reads it; undefined while its
 * employee has it. The client knows only its own person's name, so anyone else is unnamed.
 */
export const takeoverTitle = (
  takenOverBy: string | null,
  me: string | undefined,
  members: readonly { id: string; display_name: string }[] = [],
) =>
  takenOverBy === null
    ? undefined
    : takenOverBy === me
      ? "You have it"
      : `Taken over by ${members.find((member) => member.id === takenOverBy)?.display_name ?? "another person"}`;

/** Inbox until a mailbox is connected, said the same on every client. */
export const inboxEmpty =
  "No mailbox is connected yet. The business's mail appears here once one is.";

/** A coding result at a glance, from a work item's evidence; undefined when it has none. */
export function outcomeOf(evidence: Commitment["evidence"]) {
  const coding = evidence.filter((entry) => entry.commit);
  if (!coding.length) return undefined;
  const check = coding.findLast((entry) => entry.check)?.check;
  const pullRequest = coding.findLast((entry) => entry.pullRequest)?.pullRequest;
  return {
    commit: coding.at(-1)!.commit!.slice(0, 7),
    changes: coding.findLast((entry) => entry.changes)?.changes,
    check: check && { passed: check.exitCode === 0, command: check.command },
    pullRequest: pullRequest && {
      url: pullRequest,
      label: /\/pull\/(\d+)/.exec(pullRequest)?.[1]
        ? `PR #${/\/pull\/(\d+)/.exec(pullRequest)![1]}`
        : "Pull request",
    },
  };
}
