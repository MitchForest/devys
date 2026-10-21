import type { RoleTemplateId } from "../../protocol/roles.ts";
import type { RoutineNotify, RoutineState, WorkItem, WorkItemState } from "../../work/contract.ts";
import type { Tone } from "../design/primitives.tsx";

/** Plain names for capabilities, as native `AccessNames`; the description carries the detail. */
const titles: Record<string, string> = {
  recall: "Recall memory",
  remember: "Remember facts",
  forget: "Forget facts",
  readPublicUrl: "Read public websites",
  readSkill: "Read skills",
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
  workList: "List work",
  workCreate: "Take on work",
  workUpdate: "Update work",
  workComplete: "Complete work",
  projectList: "List projects",
  projectCreate: "Create projects",
  projectUpdate: "Edit projects",
  projectAdd: "Keep in projects",
  routineList: "List routines",
  routinePropose: "Propose routines",
  routineActivate: "Activate routines",
  routinePause: "Pause routines",
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

export const chipFor = (state: WorkItemState): { title: string; tone: Tone } =>
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

/** A routine's state as the owner reads it. */
export const routineStateTitle: Record<RoutineState, string> = {
  active: "Active",
  paused: "Paused",
  proposed: "Proposed",
};

/** Whether a routine's runs speak always or only when they find something. */
export const notifyTitle: Record<RoutineNotify, string> = {
  always: "Always posts",
  when_found: "Posts only when something needs attention",
};

export const isOpen = (state: WorkItemState) => state !== "completed" && state !== "cancelled";

export const filterOf = (state: WorkItemState) =>
  state === "needs_decision"
    ? "needsYou"
    : state === "waiting"
      ? "waiting"
      : state === "completed" || state === "cancelled"
        ? "done"
        : "inProgress";

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
export function outcomeOf(evidence: WorkItem["evidence"]) {
  const coding = evidence.filter((entry) => entry.commit);
  if (!coding.length) return undefined;
  const check = coding.findLast((entry) => entry.check)?.check;
  const pullRequest = coding.findLast((entry) => entry.pull_request)?.pull_request;
  // The latest deploy to each stage: production shown before preview.
  const deploys = (["production", "preview"] as const).flatMap((stage) => {
    const entry = coding.findLast((each) => each.deploy?.stage === stage);
    return entry?.deploy ? [{ ...entry.deploy, commit: entry.commit!.slice(0, 7) }] : [];
  });
  return {
    deploys,
    commit: coding.at(-1)!.commit!.slice(0, 7),
    changes: coding.findLast((entry) => entry.changes)?.changes,
    check: check && { passed: check.exit_code === 0, command: check.command },
    pullRequest: pullRequest && {
      url: pullRequest,
      label: /\/pull\/(\d+)/.exec(pullRequest)?.[1]
        ? `PR #${/\/pull\/(\d+)/.exec(pullRequest)![1]}`
        : "Pull request",
    },
  };
}
