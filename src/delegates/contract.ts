import type { Scope } from "../identity/contract.ts";

/** The coding harnesses Devys delegates to. Each owns its own sessions and transcripts. */
export const providers = ["codex", "claude"] as const;
export type Provider = (typeof providers)[number];

/** Why a session exists on a work item: to build the change, or to review it read-only. */
export type Purpose = "build" | "review";

/**
 * One coding assignment: a native session in its own worktree, serving one work item.
 * Devys records the reference and the accepted result; the provider owns the rest.
 */
export interface Assignment {
  id: string;
  commitment_id: string;
  employee_id: string;
  provider: Provider;
  purpose: Purpose;
  objective: string;
  /** Absolute path of the repository the worktree was made from. */
  repository: string;
  base_commit: string;
  branch: string;
  worktree: string;
  /** The provider's own session id, once it exists. */
  session_id: string | null;
  created_at: string;
}

/** What the host needs to begin an assignment. Starting the same id twice returns the first. */
export interface StartRequest {
  id: string;
  scope: Scope;
  provider: Provider;
  purpose: Purpose;
  /**
   * An absolute path to an existing repository, a new repository's name, or a GitHub repository
   * (`owner/name`) cloned into the business folder.
   */
  repository: { path: string } | { create: string } | { clone: string };
  objective: string;
  instructions: string;
  /** For a review: the build assignment whose worktree it reads. */
  reviews?: string;
}

export interface Started {
  sessionId: string;
  repository: string;
  baseCommit: string;
  branch: string;
  worktree: string;
}

/** Read from the provider and the worktree each time; never stored. */
export interface DelegateStatus {
  state: "working" | "idle" | "interrupted" | "failed";
  /** The provider's latest reply in the session. */
  reply: string | null;
  /** `git diff --stat` of the worktree against its base, including uncommitted changes. */
  diffStat: string;
  error: string | null;
}

/** A change in a session the supervising employee should hear about. */
export interface DelegateEvent {
  /** Stable, so delivering it twice is harmless. */
  id: string;
  assignmentId: string;
  kind: "started" | "finished" | "failed" | "interrupted" | "checked" | "deployed";
  /** The provider's reply, an error, or the check's or deploy's outcome. */
  text: string;
  diffStat?: string;
  /** For `checked`: the commit that was checked and how the check ended. */
  check?: { commit: string; command: string; exitCode: number | null; output: string };
  /** For `deployed`: what was deployed where, and whether it answered. */
  deploy?: Deployed;
}

/** Where a deploy goes: previews on Engineering's own authority, production by decision. */
export type Stage = "preview" | "production";

/**
 * Deploys a commit with the repository's own deploy command: the accepted, checked commit, or
 * (to roll back) an earlier one. `url` is checked afterwards; without it, the last https URL
 * the command printed is.
 */
export interface DeployRequest {
  stage: Stage;
  command: string;
  commit?: string;
  url?: string;
}

/** A finished deploy: its exit, the URL checked, and that URL's answer. */
export interface Deployed {
  stage: Stage;
  commit: string;
  command: string;
  exitCode: number | null;
  url: string | null;
  /** The HTTP status of a GET of `url` after deploying; null when it couldn't be reached. */
  status: number | null;
  /** Deployed and answering below 400. */
  live: boolean;
  /** The end of the command's output, with stage secrets redacted. */
  output: string;
}

/** Commits the worktree and starts the repository's check against that commit. */
export interface AcceptRequest {
  message: string;
  check: string;
}

export interface Accepted {
  commit: string;
  diffStat: string;
  /** The full patch against the base, bounded. */
  patch: string;
}

/** Publishes the accepted commit to the assignment's branch on GitHub with one pull request. */
export interface PublishRequest {
  /** `owner/name`; the repository's origin must be this repository. */
  repository: string;
  title: string;
  body: string;
}

export interface Published {
  repository: string;
  /** GitHub's id for the repository, stable across renames. */
  repositoryId: string;
  branch: string;
  /** The branch the pull request merges into: the repository's default. */
  base: string;
  commit: string;
  pullRequest: string;
}

/** The worktree's changes against its base, for review. */
export interface WorkingDiff {
  files: {
    path: string;
    status: "added" | "modified" | "deleted" | "renamed";
    added: number;
    removed: number;
  }[];
  /** A unified patch, cut off at a megabyte. */
  patch: string;
}

/**
 * One step of what a coding session did, read from the harness's own record on demand
 * (Devys keeps no copy): what it was told, its replies and plan, commands and file changes.
 */
export interface TranscriptEntry {
  kind: "prompt" | "reply" | "plan" | "command" | "files" | "tool";
  text: string;
  /** A command's output, a tool's result; cut short. */
  detail?: string;
  failed?: boolean;
}

/** The delegate runner: the trusted Mac host in local mode. */
export interface Delegates {
  diff(assignmentId: string): Promise<WorkingDiff>;
  /** The session's latest steps, at most 200, oldest first. */
  transcript(assignmentId: string): Promise<{ entries: TranscriptEntry[] }>;
  start(request: StartRequest): Promise<Started>;
  inspect(assignmentId: string): Promise<DelegateStatus>;
  send(assignmentId: string, text: string): Promise<{ steered: boolean }>;
  interrupt(assignmentId: string): Promise<void>;
  accept(assignmentId: string, request: AcceptRequest): Promise<Accepted>;
  publish(assignmentId: string, request: PublishRequest): Promise<Published>;
  /** Starts a deploy; its outcome arrives as a `deployed` event. */
  deploy(assignmentId: string, request: DeployRequest): Promise<{ commit: string }>;
}
