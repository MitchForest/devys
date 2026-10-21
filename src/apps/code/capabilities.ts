import { Effect, Schema } from "effect";
import type { Database } from "../../data/database.ts";
import type { Scope } from "../../identity/contract.ts";
import { sha256 } from "../../protocol/bytes.ts";
import { capability, CapabilityError, Invocation } from "../../protocol/capability.ts";
import { Ref, ref } from "../../protocol/ref.ts";
import { rpc } from "../../protocol/rpc.ts";
import {
  providers,
  type Assignment,
  type Delegates,
  type Provider,
  type Stage,
} from "./contract.ts";
import { assignment, assignmentsFor, recordAssignment, recordStarted } from "./service.ts";

export interface DelegateDependencies {
  db: Database;
  delegates: (scope: Scope) => Delegates;
  /** Shows a line in the work item's thread without waking anyone. */
  note(
    scope: Scope,
    commitmentId: string,
    note: { clientId: string; text: string; ref?: Ref },
  ): Promise<void>;
  /** Appends evidence to the work item. */
  evidence(
    scope: Scope,
    commitmentId: string,
    entry: { note: string; commit: string; changes?: string; pullRequest?: string },
  ): Promise<void>;
  /** Commits this work item's evidence names (accepted, checked or deployed): rollback targets. */
  knownCommits(scope: Scope, commitmentId: string): Promise<string[]>;
}

export const providerName = (provider: Provider) =>
  provider === "codex" ? "Codex" : "Claude Code";

const Text = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));
const AssignmentId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{1,64}$/));
const ProviderInput = Schema.Literals(providers);
const GitHubName = Schema.String.check(
  Schema.isPattern(/^[A-Za-z0-9-]{1,39}\/(?!.*\.\.)[A-Za-z0-9._-]{1,100}$/),
);
const Status = Schema.Struct({
  assignment: Schema.String,
  provider: Schema.String,
  purpose: Schema.String,
  branch: Schema.NullOr(Schema.String),
  worktree: Schema.NullOr(Schema.String),
  state: Schema.String,
  reply: Schema.NullOr(Schema.String),
  diffStat: Schema.String,
  error: Schema.NullOr(Schema.String),
});

/** Standing instructions for a delegated session; the objective is its first message. */
export const delegateInstructions = (purpose: "build" | "review") =>
  [
    "You are working for a business through Devys, delegated by one of its employees.",
    purpose === "build"
      ? "Work only in this git worktree. Do not commit, push, merge, open pull requests or deploy: Devys commits the change it accepts, and publishing is a separate decision."
      : "Review only: read the code and its changes against the base commit and run read-only checks. Do not edit files.",
    "Run the project's own tests and checks before you say you are done, and say exactly what you ran and how it ended.",
    "Never print, copy or move credentials, tokens or secrets.",
  ].join("\n");

/** Fails unless the call acts for a work item, which is where coding sessions live. */
const workItem = Effect.gen(function* () {
  const invocation = yield* Invocation;
  if (!invocation.commitmentId)
    return yield* new CapabilityError({
      code: "invalid_input",
      message:
        "Start and steer coding sessions from a work item, so the work has a thread and an owner.",
    });
  return { invocation, commitmentId: invocation.commitmentId };
});

export function delegateCapabilities(dependencies: DelegateDependencies) {
  const { db } = dependencies;
  const owned = (id: string) =>
    Effect.gen(function* () {
      const { invocation, commitmentId } = yield* workItem;
      const found = yield* rpc(() => Effect.runPromise(assignment(db, invocation.businessId, id)));
      if (!found || found.commitment_id !== commitmentId || !found.session_id)
        return yield* new CapabilityError({
          code: "invalid_input",
          message: "No coding session with that id on this work item",
        });
      return { invocation, commitmentId, found };
    });
  const statusOf = (scope: Scope, item: Assignment) =>
    rpc(async () => {
      const status = await dependencies.delegates(scope).inspect(item.id);
      return {
        assignment: item.id,
        provider: item.provider,
        purpose: item.purpose,
        branch: item.branch,
        worktree: item.worktree,
        ...status,
      };
    });

  return [
    capability({
      name: "codingStart",
      description:
        "Delegate coding on this work item to Codex or Claude Code. It works in its own git worktree of the repository (an absolute path on the owner's Mac), of the business's GitHub repository (cloneRepository: owner/name, cloned into the business folder the first time), or of a new empty repository (newRepository: a folder name). Write the objective as a complete brief: what to build or change, the acceptance checks, and anything it must not do. It runs on its own; you are told when its turn ends. purpose 'review' starts a read-only session on another assignment's worktree (pass reviews).",
      effect: "change",
      replay: "idempotent",
      constraints: {
        schema: Schema.Struct({
          providers: Schema.optional(Schema.Array(ProviderInput)),
          repositories: Schema.optional(
            Schema.Array(Schema.String.check(Schema.isMaxLength(1024))).check(
              Schema.isMaxLength(50),
            ),
          ),
        }),
        // Without repositories, any repository on the Mac or GitHub and new ones; with them, only
        // those (paths, or owner/name for GitHub).
        allows: ({ providers: allowed, repositories }, input) =>
          (!allowed || allowed.includes(input.provider)) &&
          (!repositories ||
            repositories.some(
              (root) =>
                (input.repository !== undefined &&
                  (input.repository === root || input.repository.startsWith(`${root}/`))) ||
                input.cloneRepository?.toLowerCase() === root.toLowerCase(),
            )),
      },
      input: Schema.Struct({
        provider: ProviderInput,
        objective: Text(8000),
        repository: Schema.optional(
          Schema.String.check(Schema.isPattern(/^\/(?!.*(?:^|\/)\.\.?(?:\/|$)).{0,1023}$/)),
        ),
        newRepository: Schema.optional(
          Schema.String.check(Schema.isPattern(/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/)),
        ),
        cloneRepository: Schema.optional(GitHubName),
        purpose: Schema.optional(Schema.Literals(["build", "review"])),
        reviews: Schema.optional(AssignmentId),
      }),
      output: Schema.Struct({
        assignment: Schema.String,
        branch: Schema.String,
        worktree: Schema.String,
        ref: Ref,
      }),
      execute: (input) =>
        Effect.gen(function* () {
          const { invocation, commitmentId } = yield* workItem;
          const purpose = input.purpose ?? "build";
          const targets = [input.repository, input.newRepository, input.cloneRepository];
          if (purpose === "build" && targets.filter(Boolean).length !== 1)
            return yield* new CapabilityError({
              code: "invalid_input",
              message:
                "Give exactly one of repository (an absolute path), cloneRepository (owner/name) or newRepository (a name).",
            });
          if (purpose === "review" && !input.reviews)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "A review names the assignment it reviews.",
            });
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const digest = yield* Effect.promise(() =>
            sha256(`${invocation.businessId}:${invocation.operationId}`),
          );
          const id = `${digest.slice(0, 8)}-${digest.slice(8, 12)}-${digest.slice(12, 16)}-${digest.slice(16, 20)}-${digest.slice(20, 32)}`;
          yield* rpc(() =>
            Effect.runPromise(
              recordAssignment(db, invocation.businessId, {
                id,
                commitmentId,
                employeeId: invocation.employeeId,
                provider: input.provider,
                purpose,
                objective: input.objective,
                ...(input.reviews ? { reviews: input.reviews } : {}),
              }),
            ),
          );
          const started = yield* rpc(() =>
            dependencies.delegates(scope).start({
              id,
              scope,
              provider: input.provider,
              purpose,
              repository: input.repository
                ? { path: input.repository }
                : input.cloneRepository
                  ? { clone: input.cloneRepository }
                  : { create: input.newRepository ?? "unused" },
              objective: input.objective,
              instructions: delegateInstructions(purpose),
              ...(input.reviews ? { reviews: input.reviews } : {}),
            }),
          );
          yield* rpc(() =>
            Effect.runPromise(recordStarted(db, invocation.businessId, id, started)),
          );
          return {
            assignment: id,
            branch: started.branch,
            worktree: started.worktree,
            ref: ref("code", "session", id),
          };
        }),
    }),
    capability({
      name: "codingStatus",
      description:
        "Show this work item's coding sessions, or one of them: state, its latest reply, and what changed in its worktree.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ assignment: Schema.optional(AssignmentId) }),
      output: Schema.Struct({ sessions: Schema.Array(Status) }),
      execute: ({ assignment: id }) =>
        Effect.gen(function* () {
          const { invocation, commitmentId } = yield* workItem;
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const items = (yield* rpc(() =>
            Effect.runPromise(assignmentsFor(db, invocation.businessId, commitmentId)),
          )).filter((item) => item.session_id && (!id || item.id === id));
          const sessions = [];
          for (const item of items) sessions.push(yield* statusOf(scope, item));
          return { sessions };
        }),
    }),
    capability({
      name: "codingSend",
      description:
        "Tell a coding session something: while it works this steers the running turn; otherwise it starts its next turn. Be specific about what to change and how to verify it.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Struct({ assignment: AssignmentId, text: Text(8000) }),
      output: Schema.Struct({ steered: Schema.Boolean }),
      execute: ({ assignment: id, text }) =>
        Effect.gen(function* () {
          const { invocation, commitmentId, found } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const sent = yield* rpc(() => dependencies.delegates(scope).send(id, text));
          yield* rpc(() =>
            dependencies.note(scope, commitmentId, {
              clientId: `delegate-send:${invocation.operationId}`,
              text: `→ ${providerName(found.provider)}: ${text}`,
              ref: ref("code", "session", id),
            }),
          );
          return sent;
        }),
    }),
    capability({
      name: "codingStop",
      description:
        "Interrupt a coding session's running turn. Its changes so far stay in its worktree.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ assignment: AssignmentId }),
      output: Schema.Struct({ interrupted: Schema.Boolean }),
      execute: ({ assignment: id }) =>
        Effect.gen(function* () {
          const { invocation } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          yield* rpc(() => dependencies.delegates(scope).interrupt(id));
          return { interrupted: true };
        }),
    }),
    capability({
      name: "codingAccept",
      description:
        "Accept a coding session's work: Devys commits its worktree on its branch and runs the repository's check command (for example `bun run verify`) against that commit. You are told how the check ended, and the commit and result are recorded as evidence. Publishing (codingPublish), merging and deploying are separate.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Struct({
        assignment: AssignmentId,
        message: Text(500),
        check: Text(2000),
      }),
      output: Schema.Struct({ commit: Schema.String, diffStat: Schema.String }),
      execute: ({ assignment: id, message, check }) =>
        Effect.gen(function* () {
          const { invocation, commitmentId, found } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const accepted = yield* rpc(() =>
            dependencies.delegates(scope).accept(id, { message, check }),
          );
          yield* rpc(() =>
            dependencies.evidence(scope, commitmentId, {
              commit: accepted.commit,
              changes:
                accepted.diffStat
                  .split("\n")
                  .find((line) => /files? changed/.test(line))
                  ?.trim() ?? "",
              note: `Committed ${accepted.commit.slice(0, 12)} on ${found.branch} in ${found.repository}: ${message}\n${accepted.diffStat}`.slice(
                0,
                2000,
              ),
            }),
          );
          return { commit: accepted.commit, diffStat: accepted.diffStat };
        }),
    }),
    capability({
      name: "codingPublish",
      description:
        "Publish a coding session's accepted work for review: Devys pushes the accepted commit to the session's branch on the business's GitHub repository (owner/name, which must be the repository's origin) and opens a pull request into the default branch, or returns the one already open. Accept the work and let its check pass first. Merging and deploying are separate decisions.",
      effect: "external",
      replay: "reconcile",
      constraints: {
        schema: Schema.Struct({
          repositories: Schema.optional(Schema.Array(GitHubName).check(Schema.isMaxLength(50))),
        }),
        allows: ({ repositories }, input) =>
          !repositories ||
          repositories.some((name) => name.toLowerCase() === input.repository.toLowerCase()),
      },
      input: Schema.Struct({
        assignment: AssignmentId,
        repository: GitHubName,
        title: Text(200),
        body: Text(8000),
      }),
      output: Schema.Struct({
        pullRequest: Schema.String,
        branch: Schema.String,
        commit: Schema.String,
      }),
      execute: ({ assignment: id, repository, title, body }) =>
        Effect.gen(function* () {
          const { invocation, commitmentId } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const published = yield* rpc(() =>
            dependencies.delegates(scope).publish(id, { repository, title, body }),
          );
          yield* rpc(() =>
            dependencies.evidence(scope, commitmentId, {
              commit: published.commit,
              pullRequest: published.pullRequest,
              note: `Published ${published.commit.slice(0, 12)} to ${published.branch} on github.com/${published.repository} (repository ${published.repositoryId}), pull request into ${published.base}: ${published.pullRequest}`,
            }),
          );
          return {
            pullRequest: published.pullRequest,
            branch: published.branch,
            commit: published.commit,
          };
        }),
    }),
    deployTo("preview"),
    deployTo("production"),
  ];

  /**
   * One stage's deploy. Two capabilities rather than one because a grant has one mode:
   * Engineering deploys previews on its own and asks for production.
   */
  function deployTo(stage: Stage) {
    return capability({
      name: stage === "preview" ? "deployPreview" : "deployProduction",
      description:
        stage === "preview"
          ? "Deploy a coding session's accepted, checked commit to a preview with the repository's own deploy command (for example `bunx wrangler deploy --env preview`), then check the URL it prints (or the one you give) answers. The result arrives in this work item. To roll back, name an earlier commit this work item accepted or deployed."
          : "Deploy a coding session's accepted, checked commit to production with the repository's own production deploy command, then check its URL answers. The owner approves each production deploy. To roll back, name an earlier commit this work item accepted or deployed.",
      effect: "external",
      replay: "reconcile",
      constraints: {
        schema: Schema.Struct({
          commands: Schema.optional(Schema.Array(Text(500)).check(Schema.isMaxLength(20))),
        }),
        allows: ({ commands }, input) => !commands || commands.includes(input.command),
      },
      input: Schema.Struct({
        assignment: AssignmentId,
        command: Text(500),
        commit: Schema.optional(Schema.String.check(Schema.isPattern(/^[0-9a-f]{7,40}$/))),
        url: Schema.optional(Schema.String.check(Schema.isPattern(/^https:\/\/\S{1,500}$/))),
      }),
      output: Schema.Struct({ deploying: Schema.String }),
      execute: ({ assignment: id, command, commit, url }) =>
        Effect.gen(function* () {
          const { invocation, commitmentId } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          if (commit) {
            const known = yield* rpc(() => dependencies.knownCommits(scope, commitmentId));
            if (!known.some((full) => full.startsWith(commit)))
              return yield* new CapabilityError({
                code: "invalid_input",
                message:
                  "Roll back only to a commit this work item accepted or deployed (see its evidence).",
              });
          }
          const started = yield* rpc(() =>
            dependencies.delegates(scope).deploy(id, {
              stage,
              command,
              ...(commit ? { commit } : {}),
              ...(url ? { url } : {}),
            }),
          );
          return { deploying: started.commit };
        }),
    });
  }
}
