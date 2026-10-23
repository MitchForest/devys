import { Schema } from "effect";
import type { Scope } from "../../identity/contract.ts";
import { Timestamp } from "../../protocol/time.ts";

/** The coding harnesses Devys runs coding sessions in. Each owns its own sessions and transcripts. */
export const providers = ["codex", "claude"] as const;
const Provider = Schema.Literals(providers);
export type Provider = typeof Provider.Type;

/** Why a session exists on a work item: to build the change, or to review it read-only. */
const Purpose = Schema.Literals(["build", "review"]);
export type Purpose = typeof Purpose.Type;

/**
 * One coding session: a native harness session in its own worktree, serving one work item.
 * Devys records the reference and the accepted result; the provider owns the rest.
 */
export const CodingSession = Schema.Struct({
  id: Schema.String,
  work_item_id: Schema.String,
  employee_id: Schema.String,
  provider: Provider,
  purpose: Purpose,
  objective: Schema.String,
  /** Absolute path of the repository the worktree was made from; null until it started. */
  repository: Schema.NullOr(Schema.String),
  /** The commit the session's branch started from, which its diff is against. */
  base_commit: Schema.NullOr(Schema.String),
  branch: Schema.NullOr(Schema.String),
  worktree: Schema.NullOr(Schema.String),
  /** The provider's own session id, once it exists. */
  provider_session_id: Schema.NullOr(Schema.String),
  created_at: Timestamp,
});
export type CodingSession = typeof CodingSession.Type;

/** What the host needs to begin a coding session. Starting the same id twice returns the first. */
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
  /** For a review: the build session whose worktree it reads. */
  reviews?: string;
}

/** Where the host started a session (the Mac host's protocol). */
export interface Started {
  providerSessionId: string;
  repository: string;
  baseCommit: string;
  branch: string;
  worktree: string;
}

/** Read from the provider and the worktree each time; never stored. */
export interface CodingStatus {
  state: "working" | "idle" | "interrupted" | "failed";
  /** The provider's latest reply in the session. */
  reply: string | null;
  /** `git diff --stat` of the worktree against its base, including uncommitted changes. */
  diffStat: string;
  error: string | null;
}

/**
 * A session as the owner sees it: the record plus its live state from the provider, or
 * `unavailable` with the error when the host could not be asked.
 */
export const LiveCodingSession = Schema.Struct({
  ...CodingSession.fields,
  state: Schema.Literals(["working", "idle", "interrupted", "failed", "unavailable"]),
  /** The provider's latest reply in the session. */
  reply: Schema.NullOr(Schema.String),
  /** `git diff --stat` of the worktree against its base, including uncommitted changes. */
  diff_stat: Schema.String,
  error: Schema.NullOr(Schema.String),
});
export type LiveCodingSession = typeof LiveCodingSession.Type;

/** A change in a session (or a repository's deploy) the supervising employee should hear about. */
export interface CodingEvent {
  /** Stable, so delivering it twice is harmless. */
  id: string;
  /** The coding session it is about; absent for a repository deployed without one. */
  codingSessionId?: string;
  /** For a repository deployed without a coding session: who deployed it, for which work item. */
  deployedFor?: { scope: Scope; workItemId: string };
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
  /** The business's secrets the deploy command needs, by name (set in its environment only). */
  secrets?: readonly string[];
}

/**
 * Deploys a repository as it is, with no coding session: its committed HEAD, in a clean
 * worktree. `commit`, when given, must be that HEAD (what the owner approved).
 */
export interface RepositoryDeployRequest extends DeployRequest {
  /** Names the deploy: stable for one call, so a repeated call reuses its place. */
  id: string;
  /** The repository's top folder, an absolute path on the owner's Mac. */
  repository: string;
  workItemId: string;
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
  /** The end of the command's output, with its secrets redacted. */
  output: string;
}

/** Commits the worktree and starts the repository's check against that commit. */
interface AcceptRequest {
  message: string;
  check: string;
}

export interface Accepted {
  commit: string;
  diffStat: string;
  /** The full patch against the base, bounded. */
  patch: string;
}

/** Publishes the accepted commit to the coding session's branch on GitHub with one pull request. */
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
export const WorkingDiff = Schema.Struct({
  files: Schema.Array(
    Schema.Struct({
      path: Schema.String,
      status: Schema.Literals(["added", "modified", "deleted", "renamed"]),
      added: Schema.Int,
      removed: Schema.Int,
    }),
  ),
  /** A unified patch, cut off at a megabyte. */
  patch: Schema.String,
});
export type WorkingDiff = typeof WorkingDiff.Type;

/**
 * One step of what a coding session did, read from the harness's own record on demand
 * (Devys keeps no copy): what it was told, its replies and plan, commands and file changes.
 */
const TranscriptEntry = Schema.Struct({
  kind: Schema.Literals(["prompt", "reply", "plan", "command", "files", "tool"]),
  text: Schema.String,
  /** A command's output, a tool's result; cut short. */
  detail: Schema.optionalKey(Schema.String),
  failed: Schema.optionalKey(Schema.Boolean),
});
export type TranscriptEntry = typeof TranscriptEntry.Type;
/** A session's latest steps, at most 200, oldest first. */
export const Transcript = Schema.Struct({ entries: Schema.Array(TranscriptEntry) });

/** The coding runner: the trusted Mac host in local mode. */
export interface CodingHost {
  diff(codingSessionId: string): Promise<WorkingDiff>;
  /** The session's latest steps, at most 200, oldest first. */
  transcript(codingSessionId: string): Promise<typeof Transcript.Type>;
  start(request: StartRequest): Promise<Started>;
  inspect(codingSessionId: string): Promise<CodingStatus>;
  send(codingSessionId: string, text: string): Promise<{ steered: boolean }>;
  interrupt(codingSessionId: string): Promise<void>;
  accept(codingSessionId: string, request: AcceptRequest): Promise<Accepted>;
  publish(codingSessionId: string, request: PublishRequest): Promise<Published>;
  /** Starts a deploy; its outcome arrives as a `deployed` event. */
  deploy(codingSessionId: string, request: DeployRequest): Promise<{ commit: string }>;
  /** Starts a deploy of a repository's committed HEAD without a coding session. */
  deployRepository(request: RepositoryDeployRequest): Promise<{ commit: string }>;
}
