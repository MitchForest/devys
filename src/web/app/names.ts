import type { Commitment, CommitmentState, Employee, RoleTemplateId } from "./api.ts";
import type { Tone } from "../design/primitives.tsx";
import type { Mood } from "../design/face.tsx";
import type { Place, WorkspaceState } from "./workspace.tsx";
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
  projectList: "List projects",
  projectCreate: "Create projects",
  projectUpdate: "Edit projects",
  projectAdd: "Keep in projects",
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

/**
 * A place's title, and in a thread the place above it (its project) so the breadcrumb reads
 * "Launch › Fix sitemap".
 */
export function placeTitle(
  state: WorkspaceState,
  place: Place,
): { title: string; parent?: { title: string; place: Place } } {
  switch (place.kind) {
    case "home":
      return { title: "Home" };
    case "direct":
      return { title: state.employees.find((e) => e.id === place.employeeId)?.name ?? "Message" };
    case "project":
      return { title: valueOf(state.projects)?.find((p) => p.id === place.id)?.name ?? "Project" };
    case "thread": {
      const item = valueOf(state.work)?.find((w) => w.id === place.workId);
      const project =
        item?.project_id && valueOf(state.projects)?.find((p) => p.id === item.project_id);
      return {
        title: item?.title ?? "Thread",
        ...(project
          ? { parent: { title: project.name, place: { kind: "project", id: project.id } as Place } }
          : {}),
      };
    }
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

/** A coding result at a glance, from a work item's evidence; undefined when it has none. */
export function outcomeOf(evidence: Commitment["evidence"]) {
  const coding = evidence.filter((entry) => entry.commit);
  if (!coding.length) return undefined;
  const check = coding.findLast((entry) => entry.check)?.check;
  const pullRequest = coding.findLast((entry) => entry.pullRequest)?.pullRequest;
  // The latest deploy to each stage: production shown before preview.
  const deploys = (["production", "preview"] as const).flatMap((stage) => {
    const entry = coding.findLast((each) => each.deploy?.stage === stage);
    return entry?.deploy ? [{ ...entry.deploy, commit: entry.commit!.slice(0, 7) }] : [];
  });
  return {
    deploys,
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
