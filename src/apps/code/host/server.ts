/**
 * Coding sessions on the trusted Mac host (local mode; .docs/CODING_AGENTS.md).
 * Each coding session gets its own git worktree and a native session in its provider. Jobs are an
 * append-only JSON-lines file (the last line for an id wins). Events the supervising employee
 * must hear about wait in a small outbox file until the Worker accepts them, so a lost push
 * is sent again. Harness processes stay in the host's process group: a host restart ends
 * them, and their coding sessions report interrupted. Nothing is replayed.
 */
import { spawn } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import type {
  Accepted,
  CodingEvent,
  CodingStatus,
  Provider,
  Published,
  Stage,
  StartRequest,
  Started,
} from "../contract.ts";
import { deploySecrets, redact, smoke, urlIn } from "./deploy.ts";
import { cloneRepository, githubName, publishBranch } from "./github.ts";
import { HostRefusal, hostId, scopeOf, type HostRoutes } from "../../../protocol/host.ts";
import { bounded, type ProviderAdapter, type ProviderEvents } from "./provider.ts";
import {
  commitAll,
  createWorktree,
  git,
  diffStat,
  patch,
  repository,
  stopProcessesIn,
  workingDiff,
} from "./worktree.ts";

type Scope = { businessId: string; employeeId: string };

interface Job {
  id: string;
  scope: Scope;
  provider: Provider;
  readOnly: boolean;
  repository: string;
  baseCommit: string;
  branch: string;
  worktree: string;
  sessionId: string;
  state: CodingStatus["state"];
  reply: string | null;
  error: string | null;
  /** A check started by accept and not yet finished. */
  check: { id: string; commit: string; command: string } | null;
  /** The last accepted commit and whether its check passed (null while it runs). */
  accepted?: { commit: string; passed: boolean | null };
  /** A deploy running now: its stage and commit. */
  deploying?: { stage: Stage; commit: string };
}

interface CodingHostOptions {
  /** Each business works in `<work>/<businessId>`. */
  work: string;
  data: string;
  providers: (events: ProviderEvents) => Partial<Record<Provider, ProviderAdapter>>;
  /** Hands events to the Worker; resolving means they were accepted. */
  /** Sends events to the Worker; resolves with the ids it delivered (the rest are retried). */
  deliver(events: readonly CodingEvent[]): Promise<readonly string[]>;
  shell?: string;
  env?: NodeJS.ProcessEnv;
  /** The `gh` the owner is logged in with; tests pass a stand-in. */
  gh?: string;
  checkTimeoutMs?: number;
  /** How long a deploy may run; 20 minutes unless set (tests). */
  deployTimeoutMs?: number;
  /** Checks a deployed URL: its HTTP status or null (tests stand in for the network). */
  smoke?: (url: string) => Promise<number | null>;
  retryMs?: number;
  /** The ttys of the owner's terminals; cleanup never stops what runs in them. */
  spared?: () => Promise<string[]>;
}

const checkOutputBytes = 16_000;
/**
 * A failure that reads like a missing or expired login, with how to fix it: the owner signs
 * the CLI in on the Mac (in a Devys terminal or their own); Devys never holds the login.
 */
function signInHint(provider: Provider, error: string) {
  if (
    !/not logged in|log ?in|logged out|unauthori[sz]ed|\b401\b|authenticat|api key|credential/i.test(
      error,
    )
  )
    return undefined;
  const command = provider === "codex" ? "codex login" : "claude, then /login";
  const name = provider === "codex" ? "Codex" : "Claude Code";
  return `${name} isn't signed in on this Mac (${error.slice(0, 200)}). Sign in with \`${command}\` in a terminal, then send the session a follow-up to continue.`;
}

export function codingHost(options: CodingHostOptions): HostRoutes {
  mkdirSync(options.data, { recursive: true });
  const ledger = join(options.data, "coding-sessions.jsonl");
  const outboxFile = join(options.data, "coding-events.json");
  const jobs = new Map<string, Job>();
  const spared = () => options.spared?.().catch(() => []) ?? Promise.resolve([] as string[]);
  if (existsSync(ledger))
    for (const line of readFileSync(ledger, "utf8").split("\n").filter(Boolean)) {
      const job = JSON.parse(line) as Job;
      jobs.set(job.id, job);
    }
  let outbox: CodingEvent[] = existsSync(outboxFile)
    ? (JSON.parse(readFileSync(outboxFile, "utf8")) as CodingEvent[])
    : [];

  const save = (job: Job) => {
    jobs.set(job.id, job);
    appendFileSync(ledger, `${JSON.stringify(job)}\n`);
  };
  const saveOutbox = () => {
    writeFileSync(`${outboxFile}.tmp`, JSON.stringify(outbox));
    renameSync(`${outboxFile}.tmp`, outboxFile);
  };

  let flushing: Promise<void> | undefined;
  let retry: ReturnType<typeof setTimeout> | undefined;
  const flush = () => {
    flushing ??= (async () => {
      const batch = [...outbox];
      if (!batch.length) return;
      let sent = new Set<string>();
      try {
        sent = new Set(await options.deliver(batch));
      } catch {}
      if (sent.size) {
        outbox = outbox.filter((event) => !sent.has(event.id));
        saveOutbox();
      }
      if (outbox.length)
        retry ??= setTimeout(() => {
          retry = undefined;
          void flush();
        }, options.retryMs ?? 15_000);
    })().finally(() => {
      flushing = undefined;
    });
    return flushing;
  };
  const emit = (event: CodingEvent) => {
    if (outbox.some((queued) => queued.id === event.id)) return;
    outbox.push(event);
    saveOutbox();
    void flush();
  };

  const statOf = (job: Job) => diffStat(job.worktree, job.baseCommit).catch(() => "");
  const ended = async (
    job: Job,
    kind: "finished" | "failed" | "interrupted",
    turn: string,
    text: string,
  ) =>
    emit({
      id: `${job.id}:${turn}:${kind}`,
      codingSessionId: job.id,
      kind,
      text,
      diffStat: await statOf(job),
    });

  // A turn can end before start() has saved its job (a fast failure); it is applied then.
  const early = new Map<string, Parameters<ProviderEvents["turnEnded"]>[0]>();
  const events: ProviderEvents = {
    turnEnded(end) {
      const { sessionId, turnId, status, reply, error } = end;
      const job = [...jobs.values()].find((candidate) => candidate.sessionId === sessionId);
      if (!job) {
        early.set(sessionId, end);
        setTimeout(() => early.delete(sessionId), 60_000).unref();
        return;
      }
      const state = status === "completed" ? "idle" : status;
      const failure = error && signInHint(job.provider, error);
      save({ ...job, state, reply: reply ?? job.reply, error: failure || error });
      void ended(
        job,
        status === "completed" ? "finished" : status,
        turnId,
        status === "completed"
          ? (reply ?? "Finished with no reply.")
          : failure || error || `The turn ${status}.`,
      );
    },
    lost(sessionIds) {
      for (const job of jobs.values())
        if (sessionIds.includes(job.sessionId) && job.state === "working") {
          save({ ...job, state: "interrupted", error: "The coding process exited mid-turn." });
          void ended(
            job,
            "interrupted",
            `lost-${Date.now()}`,
            "The coding process exited mid-turn. Its changes so far are in the worktree; send a follow-up to continue.",
          );
        }
    },
  };
  const adapters = options.providers(events);
  const adapter = (provider: Provider) => {
    const found = adapters[provider];
    if (!found) throw new HostRefusal(503, `${provider} is not available on this Mac`);
    return found;
  };

  // Anything working before this process began was cut off by the restart.
  for (const job of jobs.values()) {
    if (job.state === "working") {
      // Commands it started may still be running without the agent that started them.
      if (!job.readOnly) void spared().then((ttys) => stopProcessesIn(job.worktree, ttys));
      save({ ...job, state: "interrupted", error: "The Mac host restarted mid-turn." });
      emit({
        id: `${job.id}:restart-${Date.now()}:interrupted`,
        codingSessionId: job.id,
        kind: "interrupted",
        text: "The Mac host restarted while the session worked. Its changes so far are in the worktree; send a follow-up to continue.",
      });
    }
    if (job.check) {
      emit({
        id: `${job.id}:checked:${job.check.id}`,
        codingSessionId: job.id,
        kind: "checked",
        text: "The Mac host restarted during the check; it did not finish. Accept again to rerun it.",
        check: { commit: job.check.commit, command: job.check.command, exitCode: null, output: "" },
      });
      save({ ...jobs.get(job.id)!, check: null });
    }
  }
  void flush();

  const starting = new Map<string, Promise<Started>>();
  const startedOf = (job: Job): Started => ({
    providerSessionId: job.sessionId,
    repository: job.repository,
    baseCommit: job.baseCommit,
    branch: job.branch,
    worktree: job.worktree,
  });

  async function start(request: StartRequest): Promise<Started> {
    const existing = jobs.get(request.id);
    if (existing) return startedOf(existing);
    const business = join(options.work, request.scope.businessId);
    let place: Pick<Job, "repository" | "baseCommit" | "branch" | "worktree">;
    if (request.purpose === "review") {
      const build = request.reviews ? jobs.get(request.reviews) : undefined;
      if (!build || build.scope.businessId !== request.scope.businessId)
        throw new HostRefusal(404, "A review needs the coding session it reviews");
      const { repository: path, baseCommit, branch, worktree } = build;
      place = { repository: path, baseCommit, branch, worktree };
    } else {
      const target = request.repository;
      const path = await (
        "clone" in target ? cloneRepository(business, target.clone) : repository(business, target)
      ).catch((error: unknown) => {
        throw new HostRefusal(400, error instanceof Error ? error.message : "Not a repository");
      });
      const made = await createWorktree(business, path, request.id);
      place = { repository: path, ...made };
    }
    const readOnly = request.purpose === "review";
    const session = await adapter(request.provider).start({
      cwd: place.worktree,
      instructions: request.instructions,
      prompt: request.objective,
      readOnly,
    });
    const job: Job = {
      id: request.id,
      scope: request.scope,
      provider: request.provider,
      readOnly,
      ...place,
      sessionId: session.sessionId,
      state: "working",
      reply: null,
      error: null,
      check: null,
    };
    save(job);
    emit({
      id: `${job.id}:started`,
      codingSessionId: job.id,
      kind: "started",
      text: request.objective,
    });
    const ended = early.get(session.sessionId);
    if (ended) {
      early.delete(session.sessionId);
      events.turnEnded(ended);
    }
    return startedOf(jobs.get(job.id)!);
  }

  function jobOf(input: Record<string, unknown>) {
    const scope = scopeOf(input.scope);
    const job = typeof input.id === "string" ? jobs.get(input.id) : undefined;
    if (!job || job.scope.businessId !== scope.businessId)
      throw new HostRefusal(404, "No such coding session");
    return job;
  }

  async function accept(job: Job, message: string, command: string): Promise<Accepted> {
    if (job.readOnly) throw new HostRefusal(409, "A review session has nothing to accept");
    if (job.state === "working") throw new HostRefusal(409, "The session is still working");
    if (job.check) throw new HostRefusal(409, "A check is already running");
    const commit = await commitAll(job.worktree, message);
    const check = { id: crypto.randomUUID(), commit, command };
    save({ ...job, check, accepted: { commit, passed: null } });
    // Its own process group, so a timeout stops everything the check started.
    const child = spawn(options.shell ?? "/bin/zsh", ["-lc", command], {
      cwd: job.worktree,
      env: options.env ?? process.env,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stop = () => {
      try {
        process.kill(-child.pid!, "SIGKILL");
      } catch {}
    };
    let output = "";
    const decoder = new TextDecoder();
    const keep = (chunk: Uint8Array) => {
      output = (output + decoder.decode(chunk, { stream: true })).slice(-checkOutputBytes);
    };
    child.stdout.on("data", keep);
    child.stderr.on("data", keep);
    const deadline = setTimeout(stop, options.checkTimeoutMs ?? 30 * 60_000);
    let finished = false;
    const done = (exitCode: number | null) => {
      if (finished) return;
      finished = true;
      clearTimeout(deadline);
      // Anything the check left running in the background goes with it.
      stop();
      const latest = jobs.get(job.id)!;
      if (latest.check?.id !== check.id) return;
      save({ ...latest, check: null, accepted: { commit, passed: exitCode === 0 } });
      emit({
        id: `${job.id}:checked:${check.id}`,
        codingSessionId: job.id,
        kind: "checked",
        text:
          exitCode === 0
            ? `\`${command}\` passed.`
            : `\`${command}\` failed (exit ${exitCode ?? "killed"}).`,
        check: { commit, command, exitCode, output },
      });
    };
    child.on("error", () => done(null));
    child.on("close", done);
    return {
      commit,
      diffStat: await statOf(job),
      patch: await patch(job.worktree, job.baseCommit),
    };
  }

  /**
   * Deploys one commit (the accepted, checked one unless an earlier one is named) in its own
   * detached worktree, so uncommitted edits never ship; the outcome arrives as an event.
   */
  async function deploy(job: Job, input: Record<string, unknown>) {
    const { stage, command, url } = input;
    if (job.readOnly) throw new HostRefusal(409, "A review session has nothing to deploy");
    if (stage !== "preview" && stage !== "production")
      throw new HostRefusal(400, "Deploy to preview or production");
    if (typeof command !== "string" || !command.trim())
      throw new HostRefusal(400, "Give the repository's deploy command");
    if (url !== undefined && (typeof url !== "string" || !url.startsWith("https://")))
      throw new HostRefusal(400, "The URL to check must be https");
    if (job.deploying) throw new HostRefusal(409, "A deploy is already running");
    const commit =
      typeof input.commit === "string"
        ? input.commit
        : job.accepted?.passed
          ? job.accepted.commit
          : undefined;
    if (!commit)
      throw new HostRefusal(409, "Nothing accepted with a passing check yet: accept it first");
    const full = await git(job.repository, "rev-parse", "--verify", `${commit}^{commit}`).catch(
      () => {
        throw new HostRefusal(400, "That commit isn't in this repository");
      },
    );
    const place = join(
      options.work,
      job.scope.businessId,
      "deploys",
      `${job.id}-${full.slice(0, 12)}`,
    );
    await rm(place, { recursive: true, force: true });
    await git(job.repository, "worktree", "prune");
    await git(job.repository, "worktree", "add", "--detach", place, full);
    const secrets = await deploySecrets(options.data, job.scope.businessId, stage);
    save({ ...job, deploying: { stage, commit: full } });
    const child = spawn(options.shell ?? "/bin/zsh", ["-lc", command], {
      cwd: place,
      env: { ...(options.env ?? process.env), ...secrets },
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stop = () => {
      try {
        process.kill(-child.pid!, "SIGKILL");
      } catch {}
    };
    let output = "";
    const decoder = new TextDecoder();
    const keep = (chunk: Uint8Array) => {
      output = (output + decoder.decode(chunk, { stream: true })).slice(-checkOutputBytes);
    };
    child.stdout.on("data", keep);
    child.stderr.on("data", keep);
    const deadline = setTimeout(stop, options.deployTimeoutMs ?? 20 * 60_000);
    let finished = false;
    const done = async (exitCode: number | null) => {
      if (finished) return;
      finished = true;
      clearTimeout(deadline);
      stop();
      const shown = redact(output, secrets);
      const checked = exitCode === 0 ? ((url as string | undefined) ?? urlIn(shown)) : null;
      const status = checked ? await (options.smoke ?? smoke)(checked) : null;
      const live = exitCode === 0 && status !== null && status < 400;
      await git(job.repository, "worktree", "remove", "--force", place).catch(() => undefined);
      save({ ...jobs.get(job.id)!, deploying: undefined });
      emit({
        id: `${job.id}:deployed:${stage}:${full}:${Date.now()}`,
        codingSessionId: job.id,
        kind: "deployed",
        text:
          exitCode !== 0
            ? `Deploy to ${stage} failed (exit ${exitCode ?? "killed"}).`
            : live
              ? `Deployed ${full.slice(0, 7)} to ${stage}: ${checked} answers (${status}).`
              : checked
                ? `Deployed ${full.slice(0, 7)} to ${stage}, but ${checked} ${status === null ? "didn't answer" : `answered ${status}`}.`
                : `Deployed ${full.slice(0, 7)} to ${stage}; no URL to check was given or printed.`,
        deploy: {
          stage,
          commit: full,
          command,
          exitCode,
          url: checked,
          status,
          live,
          output: shown,
        },
      });
    };
    child.on("error", () => void done(null));
    child.on("close", (code) => void done(code));
    return { commit: full };
  }

  async function publish(job: Job, input: Record<string, unknown>): Promise<Published> {
    if (job.readOnly) throw new HostRefusal(409, "A review session has nothing to publish");
    if (job.state === "working") throw new HostRefusal(409, "The session is still working");
    if (job.check) throw new HostRefusal(409, "Wait for the check to finish");
    if (!job.accepted) throw new HostRefusal(409, "Nothing is accepted yet: accept the work first");
    if (!job.accepted.passed)
      throw new HostRefusal(409, "The accepted commit's check failed: fix it and accept again");
    const { repository: name, title, body } = input;
    if (typeof name !== "string" || !githubName.test(name))
      throw new HostRefusal(400, "Name the GitHub repository as owner/name");
    if (typeof title !== "string" || !title.trim() || typeof body !== "string")
      throw new HostRefusal(400, "Give the pull request a title and a body");
    return publishBranch(
      { ...job, commit: job.accepted.commit },
      { repository: name, title, body },
      options.gh,
    ).catch((error: unknown) => {
      throw new HostRefusal(409, error instanceof Error ? error.message : "Publishing failed");
    });
  }

  return {
    prefix: "/coding/",
    async handle(path, input) {
      switch (path) {
        case "/coding/start": {
          const request = input.request as StartRequest;
          scopeOf(request?.scope);
          if (!hostId.test(request.id ?? ""))
            throw new HostRefusal(400, "Invalid coding session id");
          const pending = starting.get(request.id) ?? start(request);
          starting.set(request.id, pending);
          try {
            return await pending;
          } finally {
            starting.delete(request.id);
          }
        }
        case "/coding/inspect": {
          const job = jobOf(input);
          return {
            state: job.state,
            reply: job.reply,
            diffStat: await statOf(job),
            error: job.error,
          } satisfies CodingStatus;
        }
        case "/coding/send": {
          const job = jobOf(input);
          if (typeof input.text !== "string" || !input.text.trim())
            throw new HostRefusal(400, "Say what to do");
          // Working before the turn starts, so a turn that ends at once is not overwritten.
          const before = jobs.get(job.id)!;
          save({ ...before, state: "working", error: null });
          const sent = await adapter(job.provider)
            .send({
              sessionId: job.sessionId,
              cwd: job.worktree,
              text: input.text,
              readOnly: job.readOnly,
            })
            .catch((error: unknown) => {
              if (jobs.get(job.id)!.state === "working")
                save({ ...jobs.get(job.id)!, state: before.state, error: before.error });
              throw error;
            });
          return { steered: sent.steered };
        }
        case "/coding/interrupt": {
          const job = jobOf(input);
          if (job.state === "working") await adapter(job.provider).interrupt(job.sessionId);
          // An interrupted turn can leave its command running. A review shares its build's
          // worktree, so only a build's own interrupt clears it.
          if (!job.readOnly)
            setTimeout(
              () => void spared().then((ttys) => stopProcessesIn(job.worktree, ttys)),
              2_000,
            ).unref();
          return { interrupted: true };
        }
        case "/coding/accept": {
          const job = jobOf(input);
          if (typeof input.message !== "string" || typeof input.check !== "string")
            throw new HostRefusal(400, "Give a commit message and a check command");
          return accept(job, input.message, input.check);
        }
        case "/coding/publish":
          return publish(jobOf(input), input);
        case "/coding/deploy":
          return deploy(jobOf(input), input);
        case "/coding/diff": {
          const job = jobOf(input);
          return workingDiff(job.worktree, job.baseCommit);
        }
        case "/coding/transcript": {
          const job = jobOf(input);
          const entries = await adapter(job.provider).transcript({
            sessionId: job.sessionId,
            cwd: job.worktree,
          });
          return { entries: bounded(entries) };
        }
        case "/coding/flush":
          await flush();
          return { pending: outbox.length };
        default:
          throw new HostRefusal(404, "Not found");
      }
    },
    async close() {
      clearTimeout(retry);
      await Promise.all(Object.values(adapters).map((each) => each?.close()));
    },
  };
}
