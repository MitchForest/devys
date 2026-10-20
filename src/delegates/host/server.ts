/**
 * Coding delegates on the trusted Mac host (local mode; .docs/COMPONENTS.md#coding-delegates).
 * Each assignment gets its own git worktree and a native session in its provider. Jobs are an
 * append-only JSON-lines file (the last line for an id wins). Events the supervising employee
 * must hear about wait in a small outbox file until the Worker accepts them, so a lost push
 * is sent again. Delegate processes stay in the host's process group: a host restart ends
 * them, and their assignments report interrupted. Nothing is replayed.
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
import { join } from "node:path";
import type {
  Accepted,
  DelegateEvent,
  DelegateStatus,
  Provider,
  StartRequest,
  Started,
} from "../contract.ts";
import { HostRefusal, type HostRoutes } from "../../protocol/host.ts";
import type { ProviderAdapter, ProviderEvents } from "./provider.ts";
import {
  commitAll,
  createWorktree,
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
  state: DelegateStatus["state"];
  reply: string | null;
  error: string | null;
  /** A check started by accept and not yet finished. */
  check: { id: string; commit: string; command: string } | null;
}

export interface DelegatesHostOptions {
  /** Each business works in `<work>/<businessId>`. */
  work: string;
  data: string;
  providers: (events: ProviderEvents) => Partial<Record<Provider, ProviderAdapter>>;
  /** Hands events to the Worker; resolving means they were accepted. */
  deliver(events: readonly DelegateEvent[]): Promise<void>;
  shell?: string;
  env?: NodeJS.ProcessEnv;
  checkTimeoutMs?: number;
  retryMs?: number;
  /** The ttys of the owner's terminals; cleanup never stops what runs in them. */
  spared?: () => Promise<string[]>;
}

const checkOutputBytes = 16_000;
const id = /^[A-Za-z0-9-]{1,64}$/;

function scopeOf(value: unknown): Scope {
  const scope = value as Partial<Scope> | undefined;
  if (!scope || !id.test(scope.businessId ?? "") || !id.test(scope.employeeId ?? ""))
    throw new HostRefusal(400, "Missing or invalid scope");
  return scope as Scope;
}

export function delegatesHost(options: DelegatesHostOptions): HostRoutes {
  mkdirSync(options.data, { recursive: true });
  const ledger = join(options.data, "delegates.jsonl");
  const outboxFile = join(options.data, "delegate-events.json");
  const jobs = new Map<string, Job>();
  const spared = () => options.spared?.().catch(() => []) ?? Promise.resolve([] as string[]);
  if (existsSync(ledger))
    for (const line of readFileSync(ledger, "utf8").split("\n").filter(Boolean)) {
      const job = JSON.parse(line) as Job;
      jobs.set(job.id, job);
    }
  let outbox: DelegateEvent[] = existsSync(outboxFile)
    ? (JSON.parse(readFileSync(outboxFile, "utf8")) as DelegateEvent[])
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
      try {
        await options.deliver(batch);
        const sent = new Set(batch.map((event) => event.id));
        outbox = outbox.filter((event) => !sent.has(event.id));
        saveOutbox();
      } catch {
        retry ??= setTimeout(() => {
          retry = undefined;
          void flush();
        }, options.retryMs ?? 15_000);
      }
    })().finally(() => {
      flushing = undefined;
    });
    return flushing;
  };
  const emit = (event: DelegateEvent) => {
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
      assignmentId: job.id,
      kind,
      text,
      diffStat: await statOf(job),
    });

  const events: ProviderEvents = {
    turnEnded({ sessionId, turnId, status, reply, error }) {
      const job = [...jobs.values()].find((candidate) => candidate.sessionId === sessionId);
      if (!job) return;
      const state = status === "completed" ? "idle" : status;
      save({ ...job, state, reply: reply ?? job.reply, error });
      void ended(
        job,
        status === "completed" ? "finished" : status,
        turnId,
        status === "completed"
          ? (reply ?? "Finished with no reply.")
          : (error ?? `The turn ${status}.`),
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
        assignmentId: job.id,
        kind: "interrupted",
        text: "The Mac host restarted while the session worked. Its changes so far are in the worktree; send a follow-up to continue.",
      });
    }
    if (job.check) {
      emit({
        id: `${job.id}:checked:${job.check.id}`,
        assignmentId: job.id,
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
    sessionId: job.sessionId,
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
        throw new HostRefusal(404, "A review needs the assignment it reviews");
      const { repository: path, baseCommit, branch, worktree } = build;
      place = { repository: path, baseCommit, branch, worktree };
    } else {
      const path = await repository(business, request.repository).catch((error: unknown) => {
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
      assignmentId: job.id,
      kind: "started",
      text: request.objective,
    });
    return startedOf(job);
  }

  function jobOf(input: Record<string, unknown>) {
    const scope = scopeOf(input.scope);
    const job = typeof input.id === "string" ? jobs.get(input.id) : undefined;
    if (!job || job.scope.businessId !== scope.businessId)
      throw new HostRefusal(404, "No such assignment");
    return job;
  }

  async function accept(job: Job, message: string, command: string): Promise<Accepted> {
    if (job.readOnly) throw new HostRefusal(409, "A review session has nothing to accept");
    if (job.state === "working") throw new HostRefusal(409, "The session is still working");
    if (job.check) throw new HostRefusal(409, "A check is already running");
    const commit = await commitAll(job.worktree, message);
    const check = { id: crypto.randomUUID(), commit, command };
    save({ ...job, check });
    const child = spawn(options.shell ?? "/bin/zsh", ["-lc", command], {
      cwd: job.worktree,
      env: options.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    const decoder = new TextDecoder();
    const keep = (chunk: Uint8Array) => {
      output = (output + decoder.decode(chunk, { stream: true })).slice(-checkOutputBytes);
    };
    child.stdout.on("data", keep);
    child.stderr.on("data", keep);
    const deadline = setTimeout(() => child.kill("SIGKILL"), options.checkTimeoutMs ?? 30 * 60_000);
    child.on("close", (exitCode) => {
      clearTimeout(deadline);
      const latest = jobs.get(job.id)!;
      if (latest.check?.id !== check.id) return;
      save({ ...latest, check: null });
      emit({
        id: `${job.id}:checked:${check.id}`,
        assignmentId: job.id,
        kind: "checked",
        text:
          exitCode === 0
            ? `\`${command}\` passed.`
            : `\`${command}\` failed (exit ${exitCode ?? "killed"}).`,
        check: { commit, command, exitCode, output },
      });
    });
    return {
      commit,
      diffStat: await statOf(job),
      patch: await patch(job.worktree, job.baseCommit),
    };
  }

  return {
    prefix: "/delegates/",
    async handle(path, input) {
      switch (path) {
        case "/delegates/start": {
          const request = input.request as StartRequest;
          scopeOf(request?.scope);
          if (!id.test(request.id ?? "")) throw new HostRefusal(400, "Invalid assignment id");
          const pending = starting.get(request.id) ?? start(request);
          starting.set(request.id, pending);
          try {
            return await pending;
          } finally {
            starting.delete(request.id);
          }
        }
        case "/delegates/inspect": {
          const job = jobOf(input);
          return {
            state: job.state,
            reply: job.reply,
            diffStat: await statOf(job),
            error: job.error,
          } satisfies DelegateStatus;
        }
        case "/delegates/send": {
          const job = jobOf(input);
          if (typeof input.text !== "string" || !input.text.trim())
            throw new HostRefusal(400, "Say what to do");
          const sent = await adapter(job.provider).send({
            sessionId: job.sessionId,
            cwd: job.worktree,
            text: input.text,
            readOnly: job.readOnly,
          });
          save({ ...jobs.get(job.id)!, state: "working", error: null });
          return { steered: sent.steered };
        }
        case "/delegates/interrupt": {
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
        case "/delegates/accept": {
          const job = jobOf(input);
          if (typeof input.message !== "string" || typeof input.check !== "string")
            throw new HostRefusal(400, "Give a commit message and a check command");
          return accept(job, input.message, input.check);
        }
        case "/delegates/diff": {
          const job = jobOf(input);
          return workingDiff(job.worktree, job.baseCommit);
        }
        case "/delegates/flush":
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
