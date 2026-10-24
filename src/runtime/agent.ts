import { DurableObject } from "cloudflare:workers";
import { Lifecycle } from "agents/lifecycle";
import type { LifecycleJobContext } from "agents/lifecycle";
import { PiHarness } from "agents/harness/pi";
import { configure, createRegistry, Harness } from "@earendil-works/pi-durable";
import type { ModelThinkingLevel } from "@earendil-works/pi-ai";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { Option, Schema } from "effect";
import { Inbound, type Channel } from "../channels/contract.ts";
import { conversationKey, type ConversationKey } from "../conversations/contract.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import type { Memory } from "../memory/contract.ts";
import type { Runner } from "../workspace/contract.ts";
import type { Outcome } from "../authority/contract.ts";
import type { Capability } from "../protocol/capability.ts";
import { activity, turnEntries, workedOf } from "./activity.ts";
import { devysExtension, initialTools } from "./codemode.ts";
import { toolHost, type ActiveEmployee } from "./host.ts";
import { messageKey, operationsOf, type ChannelMessage } from "./delivery.ts";
import { channelInbox } from "./inbox.ts";
import { memoryUpkeep } from "./memory-upkeep.ts";
import { conversationOf, historyPage, sessionMap } from "./sessions.ts";
import { employeeStatus } from "./status.ts";

type HarnessModels = Parameters<typeof Harness.open>[1]["models"];

/** Supplied by application wiring; the runtime never selects adapters. */
export interface AgentDependencies {
  readonly capabilities: Capability[];
  readonly runner: Runner;
  /** Interrupts the employee's coding sessions; Stop must not leave one working. */
  readonly interruptCoding: (scope: Scope) => Promise<void>;
  /** Where this employee's files and commands live, for its instructions. */
  readonly workplace: string;
  readonly channel: Channel;
  readonly memory: (businessId: string, signal?: AbortSignal) => Memory;
  /** The employee while it and its business are active; otherwise nothing. */
  readonly employee: (scope: Scope) => Promise<ActiveEmployee | undefined>;
  /** Re-reads this employee's grant (and the work item it serves) for this exact input. */
  readonly authorize: (
    scope: Scope,
    capability: Capability,
    input: unknown,
    context: { workItemId?: string; conversation?: string },
  ) => Promise<Outcome>;
  /** Capability names this employee holds a grant for, for discovery. */
  readonly granted: (scope: Scope) => Promise<string[]>;
  /**
   * The business's remote apps' capabilities (MCP tools the owner turned on), which change as the
   * owner connects apps: discovered and called through `execute` with the same gate.
   */
  readonly remote: (scope: Scope) => Promise<Capability[]>;
  /** The skills the employee can load: its business's installed apps' and the business's own. */
  readonly skills: (scope: Scope) => Promise<readonly { name: string; description: string }[]>;
  readonly models: (beforeDispatch: (signal?: AbortSignal) => Promise<void>) => HarnessModels;
  /** The employee's chosen model and the effort it runs at. */
  readonly foregroundModel: (
    scope: Scope,
  ) => Promise<{ provider: string; id: string; thinkingLevel: ModelThinkingLevel }>;
}

/** The object's name: `scopeName` of the business employee it is. */
const ScopeName = Schema.fromJsonString(
  Schema.Tuple([Schema.NonEmptyString, Schema.NonEmptyString]),
);

/**
 * One business employee as a Durable Object: wires Pi, the channel inbox, memory upkeep and
 * the tool host, and answers the agent port.
 */
export abstract class AgentRuntime<
  Bindings extends { LOADER: WorkerLoader } = { LOADER: WorkerLoader },
> extends DurableObject<Bindings> {
  protected abstract dependencies(): AgentDependencies;
  private wired?: AgentDependencies;
  private get services() {
    return (this.wired ??= this.dependencies());
  }
  private named?: Scope;
  /** The object's name is its scope, so routing and identity cannot disagree. */
  private get scope(): Scope {
    if (this.named) return this.named;
    const name = Option.getOrUndefined(
      Schema.decodeUnknownOption(ScopeName)(this.ctx.id.name ?? ""),
    );
    if (!name) throw new Error("Agent must be addressed by its scope");
    const [businessId, employeeId] = name;
    return (this.named = { businessId, employeeId });
  }

  readonly lifecycle = Lifecycle.install(this);
  readonly harness: PiHarness = new PiHarness({
    harness: ({ storage, context }) => {
      const models = this.services.models((signal) => this.host.checkAccess(signal));
      const registry = createRegistry();
      const extension = this.extension;
      registry.install(extension);
      return Harness.open(
        storage,
        {
          models,
          registry,
          // Granted core tools are added before the session's first turn (configureIdle).
          conversationCreated: (tx, conversation) =>
            configure(tx, conversation.id, {
              tools: initialTools(extension, this.services.capabilities, new Set()),
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
  private readonly sessions = sessionMap(this.ctx.storage, this.harness);
  private readonly activity = activity(this.services.capabilities, () =>
    this.services.remote(this.scope),
  );
  private readonly employee = async () => this.services.employee(this.scope);
  private readonly memory = memoryUpkeep({
    storage: this.ctx.storage,
    jobs: this.lifecycle.jobs,
    harness: this.harness,
    sessions: this.sessions,
    memory: (signal) => this.services.memory(this.scope.businessId, signal),
    active: async () => Boolean(await this.employee()),
  });
  private readonly inbox = channelInbox({
    storage: this.ctx.storage,
    jobs: this.lifecycle.jobs,
    harness: this.harness,
    sessions: this.sessions,
    memory: this.memory,
    channel: this.services.channel,
    scope: () => this.scope,
    runner: () => this.services.runner(this.scope),
    paused: async () => (await this.employee())?.paused ?? false,
    interruptCoding: () => this.services.interruptCoding(this.scope),
    configureIdle: (session) => this.configureIdle(session),
    worked: async (session, operationIds) =>
      workedOf(await this.activity.worked(await turnEntries(this.harness, session, operationIds))),
  });
  protected readonly host = toolHost({
    storage: this.ctx.storage,
    harness: this.harness,
    memory: this.memory,
    scope: () => this.scope,
    employee: this.employee,
    stopping: this.inbox.stopping,
    workplace: this.services.workplace,
    authorize: (capability, input, context) =>
      this.services.authorize(this.scope, capability, input, context),
    granted: () => this.services.granted(this.scope),
    skills: () => this.services.skills(this.scope),
    remote: () => this.services.remote(this.scope),
  });
  private readonly extension = devysExtension(this.env, this.services.capabilities, this.host);

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);
    this.lifecycle.use(this.harness);
  }

  private async start(scope: Scope) {
    if (scopeName(scope) !== this.ctx.id.name) throw new Error("Scope routing mismatch");
    await this.lifecycle.start();
  }

  /**
   * A deployment may change operator settings. Pending and recovered work keeps its recorded
   * model and tools; settings apply at the session's next idle admission.
   */
  private async configureIdle(session: string) {
    if ((await this.harness.pending({ session })).length) return;
    const pi = await this.harness.pi();
    const conversation = await pi.conversation(conversationOf(session), BACKGROUND_CONTEXT);
    if (!conversation) throw new Error(`Unknown Pi session ${session}`);
    const model = await this.services.foregroundModel(this.scope);
    await conversation.configure(
      {
        model: { provider: model.provider, modelId: model.id },
        thinkingLevel: model.thinkingLevel,
        tools: initialTools(
          this.extension,
          this.services.capabilities,
          new Set(await this.services.granted(this.scope)),
        ),
      },
      BACKGROUND_CONTEXT,
    );
  }

  async receive(scope: Scope, raw: Inbound) {
    const input = Schema.decodeUnknownSync(Inbound)(raw);
    this.memory.yieldToWork();
    await this.start(scope);
    return this.inbox.receive(input);
  }

  async stop(scope: Scope) {
    await this.start(scope);
    await this.inbox.stop();
    return { stopped: true };
  }

  async inspect(scope: Scope) {
    await this.start(scope);
    return JSON.stringify(
      await employeeStatus(this.ctx.storage, this.harness, this.sessions, async (session, id) =>
        this.activity.doing(await turnEntries(this.harness, session, [id], 1)),
      ),
    );
  }

  /**
   * The steps the turn behind a reply took, in the owner's words: the reply's Pi operation (its
   * channel message, kept 30 days) and the follow-up asking for its words when there was one.
   */
  async turn(scope: Scope, operationId: string) {
    await this.start(scope);
    const message = await this.ctx.storage.get<ChannelMessage>(messageKey(operationId));
    if (!message) return null;
    const session = this.sessions.sessionIn(await this.sessions.all(), message.input.chatId);
    if (session === undefined) return null;
    return this.activity.worked(await turnEntries(this.harness, session, operationsOf(message)));
  }

  /** Pi's entries for one conversation, newest first; the employee's direct chat by default. */
  async history(scope: Scope, before?: number, conversation?: ConversationKey) {
    await this.start(scope);
    if (before !== undefined && (!Number.isSafeInteger(before) || before < 0))
      throw new Error("Invalid history cursor");
    const key = conversation === undefined ? undefined : conversationKey(conversation);
    if (conversation !== undefined && !key) throw new Error("Invalid conversation");
    const session = await this.sessions.known(key);
    if (session === undefined) return JSON.stringify({ entries: [], nextBefore: null });
    return JSON.stringify(await historyPage(this.harness, session, before));
  }

  /** A channel job prepares one input, waits for Pi, and delivers its answer. */
  async onJob({ job }: LifecycleJobContext) {
    if (job.fn === "memory") return this.memory.maintain();
    if (job.fn !== "channel" || typeof job.payload !== "string") return;
    return this.inbox.process(job.payload);
  }

  async onJobError({ job }: LifecycleJobContext) {
    if (job.fn === "memory") await this.memory.failed(job);
  }

  /** Forgets channel receipts older than 30 days, a batch at a time. */
  protected forgetOldMessages() {
    return this.inbox.forgetOldMessages();
  }
}
