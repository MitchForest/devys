import { Effect, Schema } from "effect";
import type { Database } from "../../data/database.ts";
import type { Scope } from "../../identity/contract.ts";
import { stableId } from "../../protocol/bytes.ts";
import { capability, CapabilityError, Invocation } from "../../protocol/capability.ts";
import { Ref, RefOf, ref } from "../../protocol/ref.ts";
import { rpc, stored } from "../../protocol/rpc.ts";
import { SecretName } from "../../vault/contract.ts";
import {
  providers,
  type CodingSession,
  type CodingHost,
  type Provider,
  type Stage,
} from "./contract.ts";
import { codingSession, codingSessionsFor, recordCodingSession, recordStarted } from "./service.ts";

export interface CodingDependencies {
  db: Database;
  coding: (scope: Scope) => CodingHost;
  /** Shows a line in the work item's thread without waking anyone. */
  note(
    scope: Scope,
    workItemId: string,
    note: { clientId: string; text: string; ref?: Ref },
  ): Promise<void>;
  /** Appends evidence to the work item. */
  evidence(
    scope: Scope,
    workItemId: string,
    entry: { note: string; commit: string; changes?: string; pull_request?: string },
  ): Promise<void>;
  /** Commits this work item's evidence names (accepted, checked or deployed): rollback targets. */
  knownCommits(scope: Scope, workItemId: string): Promise<string[]>;
  /** Whether this employee directs others' work (the Head of Operations). */
  coordinates(scope: Scope): Promise<boolean>;
}

/** A deploy as the one step an owner's approval names: "Deploy a1b2c3 of site to production". */
export const deployStep = (commit: string, repository: string, stage: Stage) =>
  `Deploy ${commit} of ${repository} to ${stage}`;

export const providerName = (provider: Provider) =>
  provider === "codex" ? "Codex" : "Claude Code";

const Text = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));
const CodingSessionRef = RefOf("code", "session");
/** An absolute path on the owner's Mac that walks nowhere (no `.` or `..` parts). */
const RepositoryPath = Schema.String.check(
  Schema.isPattern(/^\/(?!.*(?:^|\/)\.\.?(?:\/|$)).{0,1023}$/),
);
const ProviderInput = Schema.Literals(providers);
const GitHubName = Schema.String.check(
  Schema.isPattern(/^[A-Za-z0-9-]{1,39}\/(?!.*\.\.)[A-Za-z0-9._-]{1,100}$/),
);
const Status = Schema.Struct({
  ref: Ref,
  provider: Schema.String,
  purpose: Schema.String,
  branch: Schema.NullOr(Schema.String),
  worktree: Schema.NullOr(Schema.String),
  state: Schema.String,
  reply: Schema.NullOr(Schema.String),
  diffStat: Schema.String,
  error: Schema.NullOr(Schema.String),
});

/** Standing instructions for a coding session; the objective is its first message. */
export const codingInstructions = (purpose: "build" | "review") =>
  [
    "You are working for a business through Devys, on behalf of one of its employees.",
    purpose === "build"
      ? "Work only in this git worktree. Do not commit, push, merge, open pull requests or deploy: Devys commits the change it accepts, and publishing is a separate decision."
      : "Review only: read the code and its changes against the base commit and run read-only checks. Do not edit files.",
    "Run the project's own tests and checks before you say you are done, and say exactly what you ran and how it ended.",
    "Never print, copy or move credentials, tokens or secrets.",
  ].join("\n");

/**
 * Fails unless the call is in a work item's thread, which is where its coding sessions are
 * started and steered: one place per work item, under that item's conditions. No one is exempt,
 * Operations included, since the item's conditions apply only there.
 */
const workItem = Effect.gen(function* () {
  const invocation = yield* Invocation;
  if (!invocation.workItemId)
    return yield* new CapabilityError({
      code: "conflict",
      message:
        "Coding sessions are started and steered in a work item's thread (devys:work/item/<id>): create the work item (workCreate) or continue in its thread.",
    });
  return { invocation, workItemId: invocation.workItemId };
});

export function codingCapabilities(dependencies: CodingDependencies) {
  const { db } = dependencies;
  const owned = (id: string) =>
    Effect.gen(function* () {
      const { invocation, workItemId } = yield* workItem;
      const found = yield* stored(codingSession(db, invocation.businessId, id));
      if (!found || !found.provider_session_id)
        return yield* new CapabilityError({
          code: "invalid_input",
          message: "No such coding session in this business",
        });
      if (found.work_item_id !== workItemId)
        return yield* new CapabilityError({
          code: "conflict",
          message: `This coding session belongs to another work item: steer it in that item's thread (${ref("work", "item", found.work_item_id)}).`,
        });
      // A session is steered by the employee who started it, or by Operations.
      const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
      if (
        found.employee_id !== invocation.employeeId &&
        !(yield* rpc(() => dependencies.coordinates(scope)))
      )
        return yield* new CapabilityError({
          code: "forbidden",
          message: "Another employee's coding session: ask them in this thread.",
        });
      return { invocation, workItemId, found };
    });
  const statusOf = (scope: Scope, item: CodingSession) =>
    rpc(async () => {
      const status = await dependencies.coding(scope).inspect(item.id);
      return {
        ref: ref("code", "session", item.id),
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
        "Start a coding session on this work item with Codex or Claude Code. It works in its own git worktree of the repository (an absolute path on the owner's Mac), of the business's GitHub repository (cloneRepository: owner/name, cloned into the business folder the first time), or of a new empty repository (newRepository: a folder name). Write the objective as a complete brief: what to build or change, the acceptance checks, and anything it must not do. It runs on its own; you are told when its turn ends. purpose 'review' starts a read-only session on another coding session's worktree (pass its ref as reviews). Steer, accept, publish and deploy a session by the ref this returns.",
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
        repository: Schema.optional(RepositoryPath),
        newRepository: Schema.optional(
          Schema.String.check(Schema.isPattern(/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/)),
        ),
        cloneRepository: Schema.optional(GitHubName),
        purpose: Schema.optional(Schema.Literals(["build", "review"])),
        reviews: Schema.optional(CodingSessionRef),
      }),
      output: Schema.Struct({ ref: Ref, branch: Schema.String, worktree: Schema.String }),
      execute: (input) =>
        Effect.gen(function* () {
          const { invocation, workItemId } = yield* workItem;
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
              message: "A review names the coding session it reviews.",
            });
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const id = yield* Effect.promise(() =>
            stableId(`${invocation.businessId}:${invocation.operationId}`),
          );
          yield* stored(
            recordCodingSession(db, invocation.businessId, {
              id,
              workItemId,
              employeeId: invocation.employeeId,
              provider: input.provider,
              purpose,
              objective: input.objective,
              ...(input.reviews ? { reviews: input.reviews } : {}),
            }),
          );
          const started = yield* rpc(() =>
            dependencies.coding(scope).start({
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
              instructions: codingInstructions(purpose),
              ...(input.reviews ? { reviews: input.reviews } : {}),
            }),
          );
          yield* stored(recordStarted(db, invocation.businessId, id, started));
          return {
            ref: ref("code", "session", id),
            branch: started.branch,
            worktree: started.worktree,
          };
        }),
    }),
    capability({
      name: "codingStatus",
      description:
        "Show this work item's coding sessions, or one of them (its ref): each one's ref, state, latest reply, and what changed in its worktree.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ session: Schema.optional(CodingSessionRef) }),
      output: Schema.Struct({ sessions: Schema.Array(Status) }),
      execute: ({ session: id }) =>
        Effect.gen(function* () {
          const { invocation, workItemId } = yield* workItem;
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const items = (yield* stored(
            codingSessionsFor(db, invocation.businessId, workItemId),
          )).filter((item) => item.provider_session_id && (!id || item.id === id));
          const sessions = [];
          for (const item of items) sessions.push(yield* statusOf(scope, item));
          return { sessions };
        }),
    }),
    capability({
      name: "codingSend",
      description:
        "Tell a coding session (its ref) something: while it works this steers the running turn; otherwise it starts its next turn. Be specific about what to change and how to verify it.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Struct({ session: CodingSessionRef, text: Text(8000) }),
      output: Schema.Struct({ steered: Schema.Boolean }),
      execute: ({ session: id, text }) =>
        Effect.gen(function* () {
          const { invocation, workItemId, found } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const sent = yield* rpc(() => dependencies.coding(scope).send(id, text));
          yield* rpc(() =>
            dependencies.note(scope, workItemId, {
              clientId: `coding-send:${invocation.operationId}`,
              // The instruction itself is in the session layer.
              text: `Sent ${providerName(found.provider)} a follow-up`,
              ref: ref("code", "session", id),
            }),
          );
          return sent;
        }),
    }),
    capability({
      name: "codingStop",
      description:
        "Interrupt a coding session's running turn (name the session by its ref). Its changes so far stay in its worktree.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ session: CodingSessionRef }),
      output: Schema.Struct({ interrupted: Schema.Boolean }),
      execute: ({ session: id }) =>
        Effect.gen(function* () {
          const { invocation } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          yield* rpc(() => dependencies.coding(scope).interrupt(id));
          return { interrupted: true };
        }),
    }),
    capability({
      name: "codingAccept",
      description:
        "Accept a coding session's work (by its ref): Devys commits its worktree on its branch and runs the repository's check command (for example `bun run verify`) against that commit. You are told how the check ended, and the commit and result are recorded as evidence. Publishing (codingPublish), merging and deploying are separate.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Struct({
        session: CodingSessionRef,
        message: Text(500),
        check: Text(2000),
      }),
      output: Schema.Struct({ commit: Schema.String, diffStat: Schema.String }),
      execute: ({ session: id, message, check }) =>
        Effect.gen(function* () {
          const { invocation, workItemId } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const accepted = yield* rpc(() =>
            dependencies.coding(scope).accept(id, { message, check }),
          );
          const changes =
            accepted.diffStat
              .split("\n")
              .find((line) => /files? changed/.test(line))
              ?.trim() ?? "";
          // The owner reads the note: what happened in words, no paths or ids.
          yield* rpc(() =>
            dependencies.evidence(scope, workItemId, {
              commit: accepted.commit,
              changes,
              note: `Committed ${accepted.commit.slice(0, 7)} on its branch${changes ? ` (${changes})` : ""}: ${message}`.slice(
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
        "Publish a coding session's accepted work (by its ref) for review: Devys pushes the accepted commit to the session's branch on the business's GitHub repository (owner/name, which must be the repository's origin) and opens a pull request into the default branch, or returns the one already open. Accept the work and let its check pass first. Merging and deploying are separate decisions.",
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
        session: CodingSessionRef,
        repository: GitHubName,
        title: Text(200),
        body: Text(8000),
      }),
      output: Schema.Struct({
        pullRequest: Schema.String,
        branch: Schema.String,
        commit: Schema.String,
      }),
      execute: ({ session: id, repository, title, body }) =>
        Effect.gen(function* () {
          const { invocation, workItemId } = yield* owned(id);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          const published = yield* rpc(() =>
            dependencies.coding(scope).publish(id, { repository, title, body }),
          );
          yield* rpc(() =>
            dependencies.evidence(scope, workItemId, {
              commit: published.commit,
              pull_request: published.pullRequest,
              note: `Opened a pull request for ${published.commit.slice(0, 7)} into ${published.base} on GitHub: ${published.pullRequest}`,
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
    const how =
      stage === "preview"
        ? "the repository's own deploy command (for example `bunx wrangler deploy --env preview`)"
        : "the repository's own production deploy command";
    return capability({
      name: stage === "preview" ? "deployPreview" : "deployProduction",
      description: [
        `Deploy to ${stage} with ${how}, then check the URL it prints (or the one you give) answers. Deploy either a coding session's accepted, checked commit (name the session by its ref), or, when the repository needs no change, the repository itself (repository: its absolute path) at its current commit: its worktree must be clean, and a repository this work item has a coding session on deploys through that session.`,
        "`secrets` names the business's secrets the command needs (each set as the variable of its name, redacted from the output). The result arrives in this work item.",
        stage === "production"
          ? "The owner approves each production deploy. To ask once for several steps (merge, then deploy), list this deploy in an askOwner approve's steps exactly as `Deploy <commit> of <repository> to production` (repository: the last part of its folder's path) and pass that commit here: that approval covers this deploy, once."
          : "",
        "To roll back a session's deploy, name an earlier commit this work item accepted or deployed.",
      ]
        .filter(Boolean)
        .join(" "),
      effect: "external",
      replay: "reconcile",
      constraints: {
        schema: Schema.Struct({
          commands: Schema.optional(Schema.Array(Text(500)).check(Schema.isMaxLength(20))),
        }),
        allows: ({ commands }, input) => !commands || commands.includes(input.command),
      },
      input: Schema.Struct({
        session: Schema.optional(CodingSessionRef),
        repository: Schema.optional(RepositoryPath),
        command: Text(500),
        commit: Schema.optional(Schema.String.check(Schema.isPattern(/^[0-9a-f]{7,40}$/))),
        url: Schema.optional(Schema.String.check(Schema.isPattern(/^https:\/\/\S{1,500}$/))),
        secrets: Schema.optional(Schema.Array(SecretName).check(Schema.isMaxLength(20))),
      }),
      output: Schema.Struct({ deploying: Schema.String }),
      // A production deploy of a named commit is one step an owner's approval can list.
      ...(stage === "production"
        ? {
            step: async (
              input: { session?: string; repository?: string; commit?: string },
              businessId: string,
            ) => {
              const path = input.session
                ? (await Effect.runPromise(codingSession(db, businessId, input.session)))
                    ?.repository
                : input.repository;
              const repository = path?.split("/").filter(Boolean).at(-1);
              return input.commit && repository
                ? deployStep(input.commit, repository, stage)
                : undefined;
            },
          }
        : {}),
      execute: ({ session: id, repository, command, commit, url, secrets }) =>
        Effect.gen(function* () {
          if (!id === !repository)
            return yield* new CapabilityError({
              code: "invalid_input",
              message:
                "Name a coding session (its ref) or a repository (its absolute path), not both.",
            });
          const request = {
            stage,
            command,
            ...(commit ? { commit } : {}),
            ...(url ? { url } : {}),
            ...(secrets?.length ? { secrets } : {}),
          };
          if (repository) {
            const { invocation, workItemId } = yield* workItem;
            const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
            // Work a session changed is deployed as accepted and checked, through that session.
            const sessions = yield* stored(
              codingSessionsFor(db, invocation.businessId, workItemId),
            );
            const own = sessions.find(
              (item) => item.purpose === "build" && item.repository === repository,
            );
            if (own)
              return yield* new CapabilityError({
                code: "conflict",
                message: `This work item has a coding session on that repository: deploy its accepted, checked commit by the session's ref (${ref("code", "session", own.id)}).`,
              });
            const id = yield* Effect.promise(() =>
              stableId(`${invocation.businessId}:${invocation.operationId}`),
            );
            const started = yield* rpc(() =>
              dependencies
                .coding(scope)
                .deployRepository({ ...request, id, repository, workItemId }),
            );
            return { deploying: started.commit };
          }
          const { invocation, workItemId } = yield* owned(id!);
          const scope = { businessId: invocation.businessId, employeeId: invocation.employeeId };
          if (commit) {
            const known = yield* rpc(() => dependencies.knownCommits(scope, workItemId));
            if (!known.some((full) => full.startsWith(commit)))
              return yield* new CapabilityError({
                code: "invalid_input",
                message:
                  "Roll back only to a commit this work item accepted or deployed (see its evidence).",
              });
          }
          const started = yield* rpc(() => dependencies.coding(scope).deploy(id!, request));
          return { deploying: started.commit };
        }),
    });
  }
}
