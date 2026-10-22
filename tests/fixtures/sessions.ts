import type { LifecycleJobContext } from "agents/lifecycle";
import { createModels } from "@earendil-works/pi-ai/models";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import type { AssistantMessage, TranscriptContext } from "@earendil-works/pi-ai";
import { Effect } from "effect";
import { AgentRuntime, type AgentDependencies } from "../../src/runtime/agent.ts";
import type { Observation } from "../../src/memory/contract.ts";
import { sha256 } from "../../src/protocol/bytes.ts";

const usage = {
  input: 1,
  output: 1,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 2,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

const textOf = (message: TranscriptContext["messages"][number] | undefined) =>
  !message || message.role !== "user"
    ? ""
    : typeof message.content === "string"
      ? message.content
      : message.content.map((part) => (part.type === "text" ? part.text : "")).join("");

/**
 * The employee runtime with scripted adapters: the model echoes the latest user turn (a turn
 * saying "slow" waits until aborted), and memory, channel and runner record into storage.
 */
export class SessionsProbe extends AgentRuntime {
  protected dependencies(): AgentDependencies {
    const storage = this.ctx.storage;
    const respond = (
      _model: unknown,
      transcript: TranscriptContext,
      options?: { signal?: AbortSignal },
    ) => {
      const stream = createAssistantMessageEventStream();
      const turn = textOf(transcript.messages.findLast((message) => message.role === "user"));
      const owner = turn.slice(turn.lastIndexOf("\n") + 1);
      const message = (text: string, stopReason: AssistantMessage["stopReason"]) =>
        ({
          role: "assistant",
          api: "google-generative-ai",
          provider: "google",
          model: "gemini-3.8-flash",
          timestamp: Date.now(),
          content: [{ type: "text", text }],
          stopReason,
          usage,
        }) satisfies AssistantMessage;
      if (owner.includes("slow")) {
        const aborted = () =>
          stream.push({ type: "error", reason: "aborted", error: message("", "aborted") });
        if (options?.signal?.aborted) aborted();
        else options?.signal?.addEventListener("abort", aborted, { once: true });
      } else {
        stream.push({ type: "done", reason: "stop", message: message(`Re: ${owner}`, "stop") });
      }
      return stream;
    };
    return {
      capabilities: [],
      workplace: "Test workplace.",
      skills: async () => [],
      remote: async () => [],
      interruptCoding: async () => {},
      runner: () =>
        ({
          cancel: async () => {
            await storage.put("cancels", ((await storage.get<number>("cancels")) ?? 0) + 1);
            return { stopped: true };
          },
          checkpoint: async () => ({ kind: "durable" }),
        }) as unknown as ReturnType<AgentDependencies["runner"]>,
      channel: {
        id: "app",
        inputKey: (input) => input.messageId,
        binding: async () => ({ personId: "owner", ...this.scopeOf() }),
        readText: async (input) => input.text ?? "",
        prepare: async (_scope, input) => input.text ?? "",
        send: async () => ({ status: "sent", guid: null }),
      },
      memory: () => ({
        progress: () =>
          Effect.promise(async () => ({
            cursor: (await storage.get<number>("memoryCursor")) ?? 0,
          })),
        observe: (batch: Observation[], cursor?: number) =>
          Effect.promise(async () => {
            const seen = (await storage.get<Observation[]>("observed")) ?? [];
            await storage.put("observed", [...seen, ...batch]);
            if (cursor !== undefined) await storage.put("memoryCursor", cursor);
            return { status: "accepted" as const };
          }),
        context: () => Effect.succeed({ text: "Earlier fact.", revision: 0 }),
        maintain: () => Effect.succeed({ processed: 0, more: false }),
        ...({} as Omit<
          ReturnType<AgentDependencies["memory"]>,
          "progress" | "observe" | "context" | "maintain"
        >),
      }),
      employee: async () => ({
        name: "Ada",
        responsibilities: "Operations.",
        businessName: "Probe",
        colleagues: [],
        brief: "",
        paused: false,
      }),
      authorize: async () =>
        ({ outcome: "allow" }) as Awaited<ReturnType<AgentDependencies["authorize"]>>,
      granted: async () => [],
      models: () => {
        const models = createModels({
          authContext: { env: async () => "test", fileExists: async () => false },
        });
        models.setProvider({ ...googleProvider(), stream: respond, streamSimple: respond });
        return models;
      },
      foregroundModel: async () => ({
        provider: "google",
        id: "gemini-3.8-flash",
        thinkingLevel: "low",
      }),
    };
  }

  private scopeOf() {
    const [businessId, employeeId] = JSON.parse(this.ctx.id.name!) as [string, string];
    return { businessId, employeeId };
  }

  /** The runtime's own id for a channel message id. */
  idOf(messageId: string) {
    return sha256(messageId);
  }

  async outbox(messageId: string) {
    const id = await this.idOf(messageId);
    return (await this.ctx.storage.get<{ status: string; text: string }>(`outbox:${id}`)) ?? null;
  }

  async runningWork() {
    return (await this.harness.pending()).filter((operation) => operation.status === "running");
  }

  /** The work item a tool running in `session` would act for. */
  async workItemIn(session: string) {
    return (await this.host.authority(undefined, session)).workItemId ?? null;
  }

  async sessionCount() {
    return (await this.harness.sessions.list()).length;
  }

  async cancels() {
    return (await this.ctx.storage.get<number>("cancels")) ?? 0;
  }

  /** One memory catch-up pass, as the scheduled memory job runs it. */
  async catchUp() {
    await this.onJob({ job: { fn: "memory", payload: { failures: 0 } } } as LifecycleJobContext);
    return (await this.ctx.storage.get<Observation[]>("observed")) ?? [];
  }
}
