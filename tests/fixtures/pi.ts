import { DurableObject } from "cloudflare:workers";
import { Lifecycle } from "agents/lifecycle";
import { PiHarness } from "agents/harness/pi";
import { createModels } from "@earendil-works/pi-ai/models";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import type { AssistantMessage, TranscriptContext } from "@earendil-works/pi-ai";
import {
  configure,
  createRegistry,
  Harness,
  ROOT_CONVERSATION_ID,
} from "@earendil-works/pi-durable";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { devysExtension, initialTools } from "../../src/runtime/codemode.ts";
import { capabilities } from "../../src/app/capabilities.ts";
import { applicationModels } from "../../src/app/models.ts";

interface ProbeEnv {
  LOADER: WorkerLoader;
  DEVYS_MODEL_GATEWAY_KEY?: string;
}
export class PiRecoveryProbe extends DurableObject<ProbeEnv> {
  readonly lifecycle = Lifecycle.install(this);
  readonly harness = new PiHarness({
    harness: async ({ storage, context }) => {
      const real = await this.ctx.storage.get<boolean>("real");
      const direct = await this.ctx.storage.get<boolean>("direct");
      const discovery = await this.ctx.storage.get<boolean>("discovery");
      // The live probe runs on a configured model through the real gateway; others are scripted.
      const models = real
        ? applicationModels({ DEVYS_MODEL_GATEWAY_KEY: this.env.DEVYS_MODEL_GATEWAY_KEY })
        : createModels({ authContext: { env: async () => "test", fileExists: async () => false } });
      const google = googleProvider();
      const respond = (_model: unknown, transcript: TranscriptContext) => {
        const stream = createAssistantMessageEventStream();
        const lastResult = transcript.messages.findLast((message) => message.role === "toolResult");
        const inspect = lastResult?.isError === true;
        const summarizing = transcript.messages.some(
          (message) =>
            message.role === "system" &&
            typeof message.content === "string" &&
            message.content.includes("context summarization assistant"),
        );
        const activating = discovery && lastResult?.toolName === "describe_capabilities";
        const finished = summarizing || (Boolean(lastResult) && !inspect && !activating);
        const message: AssistantMessage = {
          role: "assistant",
          api: "google-generative-ai",
          provider: "google",
          model: "gemini-3.8-flash",
          timestamp: Date.now(),
          content: finished
            ? [
                {
                  type: "text",
                  text: summarizing
                    ? "The user saved a file and has older context available in the transcript."
                    : "Saved the file.",
                },
              ]
            : [
                {
                  type: "toolCall",
                  id: "write-1",
                  name: discovery
                    ? activating
                      ? "importAttachment"
                      : "describe_capabilities"
                    : inspect
                      ? "read"
                      : direct
                        ? "write"
                        : "execute",
                  arguments: discovery
                    ? activating
                      ? { id: "a".repeat(64), path: "/workspace/result.txt" }
                      : { names: ["importAttachment"] }
                    : inspect
                      ? { path: "/workspace/result.txt" }
                      : direct
                        ? { path: "/workspace/result.txt", content: "persistent" }
                        : {
                            code: 'async () => { await codemode.write({path:"/workspace/result.txt",content:"persistent"}); return await codemode.read({path:"/workspace/result.txt"}); }',
                          },
                },
              ],
          stopReason: finished ? "stop" : "toolUse",
          usage: {
            input: 1,
            output: 1,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: 2,
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
          },
        };
        stream.push({ type: "done", reason: message.stopReason as "stop" | "toolUse", message });
        return stream;
      };
      if (!real) models.setProvider({ ...google, stream: respond, streamSimple: respond });
      const env = {
        LOADER: this.env.LOADER,
        DEVYS_MODE: "cloud",
        WORKSPACE: {
          getByName: () => ({
            importFile: async (path: string) => {
              await this.ctx.storage.put({
                [path]: "persistent",
                writes: (await this.writes()) + 1,
              });
            },
            write: async (path: string, content: string) => {
              // Count invocations even when writing the same bytes; replay must not hide.
              await this.ctx.storage.put({ [path]: content, writes: (await this.writes()) + 1 });
              if (await this.ctx.storage.get("crash")) {
                await this.ctx.storage.delete("crash");
                await this.ctx.storage.sync();
                this.ctx.abort("Injected interruption after side effect");
              }
              return { path };
            },
            read: async (path: string) => ({
              path,
              content: (await this.ctx.storage.get<string>(path)) ?? "",
            }),
          }),
        },
      } as unknown as Env;
      const registry = createRegistry();
      const extension = devysExtension(env, capabilities(env), {
        identity: async () => "You are a test employee.",
        granted: async () => new Set(capabilities(env).map((contract) => contract.name)),
        skills: async () => [],
        authority: async () => ({
          businessId: "probe",
          employeeId: "probe",
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      });
      registry.install(extension);
      return Harness.open(
        storage,
        {
          models,
          registry,
          conversationCreated: (tx, conversation) =>
            configure(tx, conversation.id, {
              tools: initialTools(
                extension,
                capabilities(env),
                new Set(capabilities(env).map((contract) => contract.name)),
              ),
            }),
          settings: { compaction: { enabled: false, keepRecentTokens: 128 } },
        },
        context,
      );
    },
    defaults: { model: { provider: "google", id: "gemini-3.8-flash" } },
  });
  constructor(ctx: DurableObjectState, env: ProbeEnv) {
    super(ctx, env);
    this.lifecycle.use(this.harness);
  }
  async runLive() {
    await this.ctx.storage.put("real", true);
    await this.lifecycle.start();
    const root = await (await this.harness.pi()).root(BACKGROUND_CONTEXT);
    await root.configure(
      { model: { provider: "gateway", modelId: "gemini-3.8-flash" } },
      BACKGROUND_CONTEXT,
    );
    await this.harness.submit(
      'Use your capabilities to write exactly "persistent" to /workspace/result.txt, then read the file to verify it. Finish with a brief confirmation.',
      { operationId: "probe-run" },
    );
    return JSON.stringify(await this.harness.wait("probe-run"));
  }
  async run(crash: boolean, direct = false) {
    await this.ctx.storage.put("direct", direct);
    await this.lifecycle.start();
    if (crash) await this.ctx.storage.put("crash", true);
    await this.harness.submit("Save a file", { operationId: "probe-run" });
    return JSON.stringify(await this.harness.wait("probe-run"));
  }
  async discoverAndImport() {
    await this.ctx.storage.put("discovery", true);
    await this.lifecycle.start();
    const pi = await this.harness.pi();
    const root = await pi.root(BACKGROUND_CONTEXT);
    const before = (await root.agent(BACKGROUND_CONTEXT)).tools.map((tool) => tool.name);
    await this.harness.submit("Import my attachment", { operationId: "discovery" });
    const result = await this.harness.wait("discovery");
    const after = (await root.agent(BACKGROUND_CONTEXT)).tools.map((tool) => tool.name);
    return JSON.stringify({ before, after, result });
  }
  async resume() {
    await this.lifecycle.start();
    return JSON.stringify(await this.harness.wait("probe-run"));
  }
  async compactAndReadOlder() {
    await this.lifecycle.start();
    for (let index = 0; index < 3; index++) {
      await this.harness.submit(
        index === 0
          ? `Original detail: cobalt-2718. ${"Older conversation context. ".repeat(200)}`
          : `Continue the saved file work, turn ${index}.`,
        { operationId: `history-${index}` },
      );
      await this.harness.wait(`history-${index}`);
    }
    const pi = await this.harness.pi();
    const conversation = (await pi.conversation(ROOT_CONVERSATION_ID, BACKGROUND_CONTEXT))!;
    const task = await conversation.compact(undefined, BACKGROUND_CONTEXT);
    const result = await pi.waitForTask(task, BACKGROUND_CONTEXT);
    const active = await conversation.context(BACKGROUND_CONTEXT);
    const stored = await conversation.entries({}, 50, undefined, BACKGROUND_CONTEXT);
    return JSON.stringify({ result, active: active.messages, stored: stored.items });
  }
  async writes() {
    return (await this.ctx.storage.get<number>("writes")) ?? 0;
  }
  async messages() {
    await this.lifecycle.start();
    return JSON.stringify(await this.harness.messages());
  }
}
