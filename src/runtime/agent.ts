import { DurableObject } from "cloudflare:workers";
import { Lifecycle } from "agents/lifecycle";
import type { LifecycleJobContext } from "agents/lifecycle";
import { PiHarness, ROOT_SESSION } from "agents/harness/pi";
import { configure, createRegistry, Harness } from "@earendil-works/pi-durable";
import type { ConversationId, EntryId } from "@earendil-works/pi-durable";
import type { ModelThinkingLevel } from "@earendil-works/pi-ai";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { Effect, Schema } from "effect";
import {
  contextOf,
  Inbound,
  type Channel,
  type ConversationContext,
} from "../channels/contract.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import type { Memory } from "../memory/contract.ts";
import type { Runner } from "../workspace/contract.ts";
import type { ChannelMessage, Outbox } from "./delivery.ts";
import type { Outcome } from "../authority/contract.ts";
import { CapabilityError, type Capability } from "../protocol/capability.ts";
import { defaultLimits } from "../protocol/limits.ts";
import { devysExtension, initialTools } from "./codemode.ts";
import { catchUpMemory, observations, withMemory } from "./memory.ts";
import { sha256 } from "../protocol/bytes.ts";

type HarnessModels = Parameters<typeof Harness.open>[1]["models"];

/** A harness session id as the Pi conversation it names. */
const conversationOf = (session: string) => Number(session) as ConversationId;

/** A context's key in this object's session map; direct chat has none and uses the root. */
const contextKey = (context: ConversationContext | undefined) =>
  context && `${context.kind}:${context.id}`;

/** Supplied by application wiring; the runtime never selects adapters. */
export interface AgentDependencies {
  readonly capabilities: Capability[];
  readonly runner: Runner;
  /** Interrupts the employee's coding sessions; Stop must not leave one working. */
  readonly interruptDelegates: (scope: Scope) => Promise<void>;
  /** Where this employee's files and commands live, for its instructions. */
  readonly workplace: string;
  readonly channel: Channel;
  readonly memory: (businessId: string, signal?: AbortSignal) => Memory;
  /** The employee while it and its business are active; otherwise nothing. */
  readonly employee: (scope: Scope) => Promise<
    | {
        name: string;
        role: string;
        businessName: string;
        brief: string;
        paused: boolean;
        /** The other employees, as "Name (what they do)". */
        colleagues: string[];
      }
    | undefined
  >;
  /** Re-reads this employee's grant (and the commitment it serves) for this exact input. */
  readonly authorize: (
    scope: Scope,
    capability: Capability,
    input: unknown,
    context: { commitmentId?: string; conversation?: string },
  ) => Promise<Outcome>;
  /** Capability names this employee holds a grant for, for discovery. */
  readonly granted: (scope: Scope) => Promise<string[]>;
  /** The skills the employee can load: its business's installed apps' and the business's own. */
  readonly skills: (scope: Scope) => Promise<readonly { name: string; description: string }[]>;
  readonly models: (beforeDispatch: (signal?: AbortSignal) => Promise<void>) => HarnessModels;
  /** The employee's chosen model and the effort it runs at. */
  readonly foregroundModel: (
    scope: Scope,
  ) => Promise<{ provider: string; id: string; thinkingLevel: ModelThinkingLevel }>;
}

export abstract class AgentRuntime<
  Bindings extends { LOADER: WorkerLoader } = { LOADER: WorkerLoader },
> extends DurableObject<Bindings> {
  protected abstract dependencies(): AgentDependencies;
  private wired?: AgentDependencies;
  private get services() {
    return (this.wired ??= this.dependencies());
  }
  readonly lifecycle = Lifecycle.install(this);
  private stopping = 0;
  private memoryAbort?: AbortController;
  private namespace?: string;
  private readonly extension = devysExtension(this.env, this.services.capabilities, this);
  readonly harness = new PiHarness({
    harness: ({ storage, context }) => {
      const models = this.services.models((signal) => this.checkAccess(signal));
      const registry = createRegistry();
      const extension = this.extension;
      registry.install(extension);
      return Harness.open(
        storage,
        {
          models,
          registry,
          conversationCreated: (tx, conversation) =>
            configure(tx, conversation.id, {
              tools: initialTools(extension, this.services.capabilities),
            }),
          settings: {
            toolExecution: "sequential",
            stream: { timeoutMs: 90_000, maxRetries: 0 },
            retry: { enabled: true, maxRetries: 2, baseDelayMs: 2_000 },
          },
        },
        context,
      );
    },
    // Select the model at admission so a configuration typo cannot disable stop/status.
    defaults: { thinkingLevel: "low" },
  });

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);
    this.lifecycle.use(this.harness);
  }

  private async sourceNamespace() {
    if (this.namespace) return this.namespace;
    this.namespace = await this.ctx.storage.transaction(async (tx) => {
      const existing = await tx.get<string>("memorySourceNamespace");
      if (existing) return existing;
      const value = crypto.randomUUID();
      await tx.put("memorySourceNamespace", value);
      return value;
    });
    return this.namespace;
  }

  /** The object's name is its scope, so routing and identity cannot disagree. */
  private scope(): Scope {
    const name = this.ctx.id.name;
    const [businessId, employeeId] = name ? (JSON.parse(name) as [string, string]) : [];
    if (!businessId || !employeeId) throw new Error("Agent must be addressed by its scope");
    return { businessId, employeeId };
  }

  async granted() {
    return new Set(await this.services.granted(this.scope()));
  }

  skills() {
    return this.services.skills(this.scope());
  }

  async identity() {
    const employee = await this.services.employee(this.scope());
    if (!employee) throw new Error("Employee access revoked");
    const about = employee.brief.trim()
      ? ` About ${employee.businessName}: ${employee.brief.trim()}`
      : "";
    const team = employee.colleagues.length
      ? ` Your colleagues: ${employee.colleagues.join("; ")}. To ask one, write @ and their name in your reply; their answer comes back to you. Hand over lasting work as a commitment they own.`
      : "";
    return `You are ${employee.name} at ${employee.businessName}, an employee operated by Devys.${about} Your responsibilities: ${employee.role}${team} Work toward the business's goals and the owner's requests. ${this.services.workplace}`;
  }

  /** Work Pi is running, in one session or, without one, in every session. */
  private async running(session?: string) {
    return (await this.harness.pending(session === undefined ? {} : { session })).filter(
      (operation) => operation.status === "running",
    );
  }

  /**
   * Model requests do not say which session they serve. Sessions run independently, so
   * without one, refuse only when every running input is cancelled or expired; Pi's abort
   * signal still stops the cancelled run itself.
   */
  private async checkAccess(signal?: AbortSignal, session?: string) {
    signal?.throwIfAborted();
    if (this.stopping) throw new Error("Stopping work");
    const employee = await this.services.employee(this.scope());
    if (!employee) throw new Error("Employee access revoked");
    if (employee.paused) throw new Error("Employee is paused");
    const messages = await Promise.all(
      (await this.running(session)).map((operation) =>
        this.ctx.storage.get<ChannelMessage>(`message:${operation.operationId}`),
      ),
    );
    if (
      messages.length &&
      messages.every(
        (message) =>
          message &&
          (message.cancelled || Date.now() >= message.receivedAt + defaultLimits.maxDurationMs),
      )
    )
      throw new Error("Message cancelled or expired");
    signal?.throwIfAborted();
    if (this.stopping) throw new Error("Stopping work");
  }

  /** The calling tool's session decides which input, and so which commitment, it acts for. */
  async authority(signal: AbortSignal | undefined, session: string) {
    await this.checkAccess(signal, session);
    const pi = await this.harness.pi();
    const [running] = await this.running(session);
    const latest = running
      ? await pi.commit(async (tx) => {
          const submission = await tx.submissionByRequest(
            conversationOf(running.session),
            running.operationId,
          );
          return submission?.entry === undefined ? undefined : tx.entry(submission.entry);
        }, BACKGROUND_CONTEXT)
      : undefined;
    const evidence = observations(latest ? [latest] : [], await this.sourceNamespace());
    // Work handed over by the dispatcher, or a message in a work item's thread, names its
    // commitment; the host, not the model, says so.
    const input = running
      ? (await this.ctx.storage.get<ChannelMessage>(`message:${running.operationId}`))?.input
      : undefined;
    const context = input ? contextOf(input.chatId) : undefined;
    const commitmentId = context?.kind === "work" ? context.id : undefined;
    const conversation = input
      ? context
        ? `${context.kind}:${context.id}`
        : `direct:${this.scope().employeeId}`
      : undefined;
    // Memory being down never stops work: a missed observation is caught up later, and only
    // observed evidence is cited.
    const observed =
      evidence.length &&
      (await Effect.runPromise(
        this.services.memory(this.scope().businessId).observe(evidence),
      ).then(
        () => true,
        (error: unknown) => {
          console.warn("Devys memory observation failed", error);
          return false;
        },
      ));
    const scope = this.scope();
    return {
      evidenceIds: observed ? evidence.map((item) => item.id) : [],
      ...scope,
      ...(commitmentId ? { commitmentId } : {}),
      ...(conversation ? { conversation } : {}),
      authorize: (capability: Capability, args: unknown) =>
        Effect.tryPromise({
          try: () =>
            this.services.authorize(scope, capability, args, {
              ...(commitmentId ? { commitmentId } : {}),
              ...(conversation ? { conversation } : {}),
            }),
          catch: () =>
            new CapabilityError({ code: "unavailable", message: "Authority is unavailable" }),
        }).pipe(
          Effect.flatMap((decision) =>
            decision.outcome === "allow"
              ? Effect.void
              : Effect.fail(
                  decision.outcome === "ask"
                    ? new CapabilityError({
                        code: "approval_required",
                        message: `${capability.name} needs the owner's approval for this request`,
                      })
                    : new CapabilityError({ code: "forbidden", message: decision.reason }),
                ),
          ),
        ),
      assertActive: () =>
        Effect.tryPromise({
          try: () => this.checkAccess(signal, session),
          catch: () =>
            new CapabilityError({
              code: "cancelled",
              message: "Work stopped, expired, or access was revoked",
            }),
        }),
    };
  }

  /** Business memory relevant to this turn's text. */
  private async memoryContext(query: string) {
    try {
      const result = await Effect.runPromise(
        this.services.memory(this.scope().businessId).context({ query, maxChars: 4000 }),
      );
      return result.text;
    } catch {
      return "Business memory is temporarily unavailable. Do not claim to recall or save unsupported information.";
    }
  }

  private scheduleMemory(time = Date.now() + 30_000, failures = 0) {
    return this.lifecycle.jobs.push({
      id: "memory",
      fn: "memory",
      payload: { failures },
      time,
      retry: { maxAttempts: 1 },
      singleflight: true,
      hungTimeoutSeconds: 120,
    });
  }

  private async maintainMemory() {
    if (!(await this.services.employee(this.scope()))) return;
    if ((await this.harness.pending()).some((item) => item.status === "running"))
      return { rescheduleAt: Date.now() + 30_000 };
    const controller = new AbortController();
    this.memoryAbort = controller;
    try {
      const memory = this.services.memory(this.scope().businessId, controller.signal);
      const pi = await this.harness.pi();
      const sessions = [ROOT_SESSION, ...(await this.contextSessions()).values()];
      // Pi allocates entry ids across every conversation, so one cursor orders all sessions.
      const more = await catchUpMemory(
        memory,
        (min, max, limit) =>
          pi.commit(async (tx) => {
            const entries = [];
            for (const session of sessions) {
              const page = await tx.scanEntries(
                {
                  conversationId: conversationOf(session),
                  minEntryId: min as EntryId,
                  ...(max === undefined ? {} : { maxEntryId: max as EntryId }),
                },
                limit,
              );
              entries.push(...page.items);
            }
            return entries.sort((a, b) => Number(b.id) - Number(a.id)).slice(0, limit);
          }, BACKGROUND_CONTEXT),
        await this.sourceNamespace(),
      );
      const result = await Effect.runPromise(memory.maintain({ maxSources: 4 }));
      await this.scheduleMemory(Date.now() + (more || result.more ? 30_000 : 24 * 60 * 60 * 1000));
      return;
    } catch (error) {
      if (controller.signal.aborted) return { rescheduleAt: Date.now() + 30_000 };
      throw error;
    } finally {
      if (this.memoryAbort === controller) this.memoryAbort = undefined;
    }
  }

  async onJobError({ job }: LifecycleJobContext) {
    if (job.fn === "memory") {
      const failures =
        typeof job.payload === "object" &&
        job.payload !== null &&
        "failures" in job.payload &&
        typeof job.payload.failures === "number"
          ? job.payload.failures + 1
          : 1;
      console.warn(
        failures >= 3
          ? "Memory maintenance paused after three failed passes; pending observations retained until the next input"
          : "Memory maintenance unavailable; pending observations retained for retry",
      );
      if (failures < 3) await this.scheduleMemory(Date.now() + failures * 5 * 60 * 1000, failures);
    }
  }

  private async start(scope: Scope) {
    if (scopeName(scope) !== this.ctx.id.name) throw new Error("Scope routing mismatch");
    await this.lifecycle.start();
  }

  private async configureIdleAgent(session: string) {
    // A deployment may change operator settings. Let pending/recovered work keep
    // its recorded model and tools; apply settings at the session's next idle admission.
    if ((await this.harness.pending({ session })).length) return;
    const pi = await this.harness.pi();
    const conversation = await pi.conversation(conversationOf(session), BACKGROUND_CONTEXT);
    if (!conversation) throw new Error(`Unknown Pi session ${session}`);
    const model = await this.services.foregroundModel(this.scope());
    await conversation.configure(
      {
        model: { provider: model.provider, modelId: model.id },
        thinkingLevel: model.thinkingLevel,
        tools: initialTools(this.extension, this.services.capabilities),
      },
      BACKGROUND_CONTEXT,
    );
  }

  private creating = new Map<string, Promise<string>>();

  /** Every context's Pi session, by context key. Direct chat is the root session. */
  private async contextSessions() {
    const stored = await this.ctx.storage.list<string>({ prefix: "session:" });
    return new Map([...stored].map(([key, session]) => [key.slice("session:".length), session]));
  }

  /** The session a chat's context already has, or undefined before its first input. */
  private sessionIn(sessions: Map<string, string>, chatId: string) {
    const key = contextKey(contextOf(chatId));
    return key ? sessions.get(key) : ROOT_SESSION;
  }

  private async knownSession(context: ConversationContext | undefined) {
    const key = contextKey(context);
    return key ? this.ctx.storage.get<string>(`session:${key}`) : ROOT_SESSION;
  }

  /** A context's session, created on its first input; concurrent first inputs share one. */
  private openSession(context: ConversationContext | undefined) {
    const key = contextKey(context);
    if (!key) return Promise.resolve(ROOT_SESSION);
    const existing = this.creating.get(key);
    if (existing) return existing;
    const opening = (async () => {
      const known = await this.ctx.storage.get<string>(`session:${key}`);
      if (known) return known;
      const { id } = await this.harness.sessions.create();
      await this.ctx.storage.put(`session:${key}`, id);
      return id;
    })().finally(() => this.creating.delete(key));
    this.creating.set(key, opening);
    return opening;
  }

  private schedule(messageId: string) {
    return this.lifecycle.jobs.push({
      id: `channel:${messageId}`,
      fn: "channel",
      payload: messageId,
      time: Date.now(),
      singleflight: true,
      hungTimeoutSeconds: 180,
    });
  }

  async receive(scope: Scope, raw: Inbound) {
    const input = Schema.decodeUnknownSync(Inbound)(raw);
    this.memoryAbort?.abort();
    await this.start(scope);
    const id = await sha256(this.services.channel.inputKey(input));
    let message = await this.ctx.storage.get<ChannelMessage>(`message:${id}`);
    if (message && message.input.text !== input.text)
      throw new Error("Message id already used for different text");
    let accepted = false;
    if (!message) {
      const text = (await this.services.channel.readText(input)).trim();
      const control = /^\/?stop$/i.test(text)
        ? "stop"
        : /^\/?status$/i.test(text)
          ? "status"
          : undefined;
      const targets = control === "stop" ? await this.stopTargets() : undefined;
      const candidate: ChannelMessage = {
        id,
        input,
        receivedAt: Date.now(),
        ...(control ? { control, text } : {}),
        ...(targets ? { targets } : {}),
      };
      message = await this.ctx.storage.transaction(async (tx) => {
        const previous = await tx.get<ChannelMessage>(`message:${id}`);
        if (previous) return previous;
        accepted = true;
        await tx.put(`message:${id}`, candidate);
        await tx.put(this.recentKey(candidate), id);
        return candidate;
      });
    }
    if (accepted) await this.forgetOldMessages();
    // Stop/status must not wait behind an attachment download or model response.
    // Intent is already durable, so a lost ingress response safely retries it.
    if (message.control) await this.processMessage(message.id);
    // Re-arm duplicates too: the previous request may have stopped after persistence.
    await this.schedule(message.id);
    return { accepted };
  }

  async stop(scope: Scope) {
    await this.start(scope);
    await this.cancelTargets(await this.stopTargets());
    return { stopped: true };
  }

  private async stopTargets() {
    const preparing = this.lifecycle.jobs
      .list()
      .filter((job) => job.fn === "channel" && typeof job.payload === "string")
      .map((job) => job.payload as string);
    return [
      ...new Set(
        preparing.concat((await this.harness.pending()).map((operation) => operation.operationId)),
      ),
    ];
  }

  private async cancelTargets(selected: string[]) {
    this.memoryAbort?.abort();
    const pending = await this.harness.pending();
    const pi = await this.harness.pi();
    const sessions = await this.contextSessions();
    this.stopping++;
    try {
      const targets: { operationId: string; session: string }[] = [];
      for (const id of selected) {
        const message = await this.ctx.storage.get<ChannelMessage>(`message:${id}`);
        const session =
          pending.find((item) => item.operationId === id)?.session ??
          (message ? this.sessionIn(sessions, message.input.chatId) : undefined);
        if (session !== undefined) targets.push({ operationId: id, session });
        const submission =
          session === undefined
            ? undefined
            : await pi.commit(
                (tx) => tx.submissionByRequest(conversationOf(session), id),
                BACKGROUND_CONTEXT,
              );
        if (submission?.status === "done" || submission?.status === "unanswered") continue;
        await this.ctx.storage.transaction(async (tx) => {
          const message = await tx.get<ChannelMessage>(`message:${id}`);
          if (message && !message.control)
            await tx.put(`message:${id}`, { ...message, cancelled: true });
        });
      }
      const active = pending.some(
        (item) => item.status === "running" && selected.includes(item.operationId),
      );
      await Promise.all([
        ...targets.map((target) => this.harness.abort(target)),
        ...(active ? [this.services.runner(this.scope()).cancel()] : []),
        this.services.interruptDelegates(this.scope()).catch(() => undefined),
      ]);
    } finally {
      this.stopping--;
    }
  }

  /** A channel input may act only through the employee it is bound to. */
  private reaches(binding: Scope | undefined) {
    const scope = this.scope();
    return binding?.businessId === scope.businessId && binding.employeeId === scope.employeeId;
  }

  /**
   * Channel receipts older than 30 days go, a batch at a time: redeliveries arrive within
   * minutes, and status shows only recent messages. Pi keeps the conversation itself.
   */
  protected async forgetOldMessages() {
    const cutoff = String(Date.now() - 30 * 24 * 60 * 60_000).padStart(16, "0");
    const old = await this.ctx.storage.list<string>({
      prefix: "recent:",
      end: `recent:${cutoff}`,
      limit: 50,
    });
    if (!old.size) return;
    await this.ctx.storage.delete([
      ...old.keys(),
      ...[...old.values()].flatMap((id) => [`message:${id}`, `outbox:${id}`]),
    ]);
  }

  private recentKey(message: ChannelMessage) {
    return `recent:${String(message.receivedAt).padStart(16, "0")}:${message.id}`;
  }

  async inspect(scope: Scope) {
    await this.start(scope);
    const pi = await this.harness.pi();
    const [pending, recent, checkpoint, usage, sessions] = await Promise.all([
      this.harness.pending(),
      this.ctx.storage.list<string>({ prefix: "recent:", reverse: true, limit: 100 }),
      this.ctx.storage.get("workspaceCheckpoint"),
      // Pi's usage is already the sum of every conversation's own ledger.
      pi.usage(BACKGROUND_CONTEXT),
      this.contextSessions(),
    ]);
    const ids = [...recent.values()];
    const [messages, outbox] = await Promise.all([
      ids.length
        ? this.ctx.storage.get<ChannelMessage>(ids.map((id) => `message:${id}`))
        : new Map<string, ChannelMessage>(),
      ids.length
        ? this.ctx.storage.get<Outbox>(ids.map((id) => `outbox:${id}`))
        : new Map<string, Outbox>(),
    ]);
    const inbox = await Promise.all(
      [...messages.values()].map(async (message) => {
        const session = this.sessionIn(sessions, message.input.chatId);
        const submission =
          session === undefined
            ? undefined
            : await pi.commit(
                (tx) => tx.submissionByRequest(conversationOf(session), message.id),
                BACKGROUND_CONTEXT,
              );
        const state = pending.find((item) => item.operationId === message.id)?.status;
        return {
          id: message.id,
          text: message.text,
          receivedAt: message.receivedAt,
          status:
            state ??
            (submission?.status === "unanswered" || message.cancelled
              ? "failed"
              : submission?.status === "done" ||
                  message.control ||
                  outbox.has(`outbox:${message.id}`)
                ? "done"
                : "queued"),
        };
      }),
    );
    const running = pending.find((item) => item.status === "running");
    const current =
      running && (await this.ctx.storage.get<ChannelMessage>(`message:${running.operationId}`));
    return JSON.stringify({
      run: running
        ? {
            id: running.operationId,
            stopped: Boolean(current?.cancelled),
            deadline: current ? current.receivedAt + defaultLimits.maxDurationMs : null,
          }
        : null,
      inbox,
      outbox: [...outbox.values()],
      checkpoint,
      usage,
    });
  }

  /** Pi's entries for one context's conversation, newest first; direct chat by default. */
  async history(scope: Scope, before?: number, context?: ConversationContext) {
    await this.start(scope);
    if (before !== undefined && (!Number.isSafeInteger(before) || before < 0))
      throw new Error("Invalid history cursor");
    if (
      context !== undefined &&
      (!["work", "project", "direct"].includes(context.kind) ||
        !/^[A-Za-z0-9-]{1,64}$/.test(context.id))
    )
      throw new Error("Invalid conversation context");
    const session = await this.knownSession(context);
    if (session === undefined) return JSON.stringify({ entries: [], nextBefore: null });
    const pi = await this.harness.pi();
    const page = await pi.commit(
      (tx) =>
        tx.scanEntries(
          {
            conversationId: conversationOf(session),
            ...(before === undefined ? {} : { maxEntryId: before as EntryId }),
          },
          50,
        ),
      BACKGROUND_CONTEXT,
    );
    return JSON.stringify({
      entries: page.items,
      nextBefore:
        page.items.length === 50
          ? Math.min(...page.items.map((entry) => Number(entry.id))) - 1
          : null,
    });
  }

  /** A channel job prepares one input, waits for Pi, and delivers its answer. */
  async onJob({ job }: LifecycleJobContext) {
    if (job.fn === "memory") return this.maintainMemory();
    if (job.fn !== "channel" || typeof job.payload !== "string") return;
    return this.processMessage(job.payload);
  }

  /** Answers one channel message: prepare it, run it in its session, then deliver the reply. */
  private async processMessage(id: string) {
    const key = `message:${id}`;
    let message = await this.ctx.storage.get<ChannelMessage>(key);
    if (!message) return;
    let output = await this.ctx.storage.get<Outbox>(`outbox:${message.id}`);
    if (output && output.status !== "pending") return;
    const context = contextOf(message.input.chatId);
    if (!this.reaches(await this.services.channel.binding(message.input))) {
      const session = await this.knownSession(context);
      if (session !== undefined) await this.harness.abort({ operationId: message.id, session });
      if (output)
        await this.ctx.storage.put(`outbox:${message.id}`, {
          ...output,
          status: output.attempts ? "uncertain" : "cancelled",
        });
      return;
    }
    if (!output) {
      if (!message.control) {
        const prepared = await this.prepare(message);
        if ("rescheduleAt" in prepared) return prepared;
        message = prepared.message;
      }
      const answer = await this.answer(message, context);
      if (typeof answer !== "string") return answer;
      const pending: Outbox = {
        id: message.id,
        chatId: message.input.chatId,
        text: answer.slice(0, 16_000),
        replyTo: message.input.messageId,
        attempts: 0,
        status: "pending",
      };
      output = await this.ctx.storage.transaction(async (tx) => {
        const existing = await tx.get<Outbox>(`outbox:${pending.id}`);
        if (existing) return existing;
        await tx.put(`outbox:${pending.id}`, pending);
        return pending;
      });
    }
    return this.deliver(message, output);
  }

  /** Reads a channel message's text once, giving up after three failed attempts. */
  private async prepare(
    message: ChannelMessage,
  ): Promise<{ message: ChannelMessage } | { rescheduleAt: number }> {
    if (
      message.text !== undefined ||
      message.cancelled ||
      Date.now() >= message.receivedAt + defaultLimits.maxDurationMs
    )
      return { message };
    const key = `message:${message.id}`;
    try {
      const prepared = await this.services.channel.prepare(this.scope(), message.input);
      return {
        message: await this.ctx.storage.transaction(async (tx) => {
          // A message forgotten meanwhile is treated as cancelled, never recreated.
          const latest = (await tx.get<ChannelMessage>(key)) ?? { ...message, cancelled: true };
          if (!latest.cancelled) {
            latest.text = prepared;
            await tx.put(key, latest);
          }
          return latest;
        }),
      };
    } catch {
      const latest = await this.ctx.storage.transaction(async (tx) => {
        const latest = await tx.get<ChannelMessage>(key);
        if (!latest) return { ...message, cancelled: true };
        latest.preparationAttempts = (latest.preparationAttempts ?? 0) + 1;
        if (latest.preparationAttempts >= 3) latest.cancelled = true;
        await tx.put(key, latest);
        return latest;
      });
      return latest.cancelled ? { message: latest } : { rescheduleAt: Date.now() + 5_000 };
    }
  }

  /** The reply text for a message, or when to look again while Pi is still working. */
  private async answer(
    message: ChannelMessage,
    context: ConversationContext | undefined,
  ): Promise<string | { rescheduleAt: number }> {
    if (message.control) {
      if (message.control === "stop") await this.cancelTargets(message.targets ?? []);
      return message.control === "stop"
        ? "Stopped work received before your stop message. Incomplete actions may need inspection."
        : (await this.harness.pending()).length
          ? "I'm working on your request."
          : "There is no active run.";
    }
    if (message.cancelled || Date.now() >= message.receivedAt + defaultLimits.maxDurationMs) {
      const session = await this.knownSession(context);
      const active = (await this.harness.pending()).some(
        (item) => item.operationId === message.id && item.status === "running",
      );
      await Promise.all([
        ...(session === undefined
          ? []
          : [this.harness.abort({ operationId: message.id, session })]),
        ...(active ? [this.services.runner(this.scope()).cancel()] : []),
      ]);
      return message.preparationAttempts && message.preparationAttempts >= 3
        ? "I couldn't read that message or its attachments. Please check the files and try again."
        : "That request was stopped or reached its time limit. Saved results remain available; incomplete actions need inspection.";
    }
    if ((await this.services.employee(this.scope()))?.paused)
      return "I'm paused by the owner, so I didn't act on that. Ask the owner to resume me.";
    return this.run(message, context);
  }

  /** Submits the turn to Pi in the context's session (idempotent by message id) and waits. */
  private async run(
    message: ChannelMessage,
    context: ConversationContext | undefined,
  ): Promise<string | { rescheduleAt: number }> {
    const session = await this.openSession(context);
    // Submitted once; the polls that follow only wait (no memory search per poll).
    if (!message.submitted) {
      await this.scheduleMemory();
      await this.configureIdleAgent(session);
      const turn = message.text ?? "";
      await this.harness.submit(withMemory(turn, await this.memoryContext(turn)), {
        session,
        operationId: message.id,
        whenBusy: "followUp",
      });
      await this.ctx.storage.transaction(async (tx) => {
        const latest = await tx.get<ChannelMessage>(`message:${message.id}`);
        if (latest) await tx.put(`message:${message.id}`, { ...latest, submitted: true });
      });
    }
    if ((await this.ctx.storage.get<ChannelMessage>(`message:${message.id}`))?.cancelled)
      await this.harness.abort({ operationId: message.id, session });
    const signal = AbortSignal.timeout(5_000);
    let text: string;
    try {
      const result = await this.harness.wait(message.id, { session, signal });
      text =
        result.status === "done"
          ? result.text || "Finished; there was no text response."
          : "I couldn't finish that request. Any incomplete actions need inspection before another attempt.";
    } catch (error) {
      if (signal.aborted) return { rescheduleAt: Date.now() + 1_000 };
      throw error;
    }
    // The workspace is shared by every session, so checkpoint only when all are idle.
    if (!(await this.harness.pending()).length) await this.checkpointWorkspace();
    return text;
  }

  private async checkpointWorkspace() {
    try {
      const checkpoint = await this.services.runner(this.scope()).checkpoint();
      await this.ctx.storage.put("workspaceCheckpoint", {
        status: "saved",
        at: Date.now(),
        ...checkpoint,
      });
    } catch {
      await this.ctx.storage.put("workspaceCheckpoint", {
        status: "failed",
        at: Date.now(),
        message:
          "Workspace checkpoint failed. Saved artifacts remain available; newer scratch files may be lost.",
      });
    }
  }

  /** Sends a queued reply through its channel, recording each attempt before it is made. */
  private async deliver(message: ChannelMessage, queued: Outbox) {
    let output = queued;
    if (output.status !== "pending") return;
    const key = `outbox:${message.id}`;
    // Check again immediately before a send: access may have changed while Pi ran.
    if (
      !this.reaches(
        await this.services.channel.binding({ ...message.input, chatId: output.chatId }),
      )
    ) {
      output.status = output.attempts ? "uncertain" : "cancelled";
      await this.ctx.storage.put(key, output);
      return;
    }
    // Record an attempted send before networking so a crash cannot later
    // make an unconfirmed send look as though it was never attempted.
    output = await this.ctx.storage.transaction(async (tx) => {
      // An outbox forgotten meanwhile is not sent.
      const latest = await tx.get<Outbox>(key);
      if (!latest) return { ...output, status: "cancelled" as const };
      if (latest.status !== "pending") return latest;
      if (latest.attempts >= 5) latest.status = "uncertain";
      else latest.attempts++;
      await tx.put(key, latest);
      return latest;
    });
    if (output.status !== "pending") return;
    const sent = await this.services.channel.send(
      this.scope(),
      output.chatId,
      output.text,
      output.id,
      output.replyTo,
    );
    output = await this.ctx.storage.transaction(async (tx) => {
      // Forgotten meanwhile: the send's outcome is still what is reported, not stored.
      const latest = (await tx.get<Outbox>(key)) ?? { ...output };
      if (sent.status === "sent") latest.status = "sent";
      else if (latest.status === "pending" && latest.attempts >= 5) latest.status = "uncertain";
      await tx.put(key, latest);
      return latest;
    });
    if (output.status === "pending")
      return { rescheduleAt: Date.now() + Math.min(60_000, 2_000 * 2 ** output.attempts) };
  }
}
