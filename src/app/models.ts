import { createModels, createProvider } from "@earendil-works/pi-ai/models";
import type { Provider } from "@earendil-works/pi-ai/models";
import type {
  Api,
  AssistantMessageEventStream,
  Model,
  ModelThinkingLevel,
  ProviderStreams,
} from "@earendil-works/pi-ai";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import { anthropicMessagesApi } from "@earendil-works/pi-ai/api/anthropic-messages.lazy";
import { googleGenerativeAIApi } from "@earendil-works/pi-ai/api/google-generative-ai.lazy";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { modelsConfig, type ModelConfig, type ModelsConfig } from "../../config/models.ts";

/** Secrets by name; `config/models.ts` says which name each provider's key uses. */
export type ModelSecrets = Record<string, unknown>;

/** pi-ai's own descriptions of known models, inherited by `catalog` entries. */
const catalog = new Map<string, Model<Api>>(
  [anthropicProvider(), openaiProvider(), googleProvider()].flatMap((provider) =>
    provider
      .getModels()
      .map((model) => [`${provider.id}/${model.id}`, model as Model<Api>] as const),
  ),
);

/**
 * OpenAI-compatible gateways can report `finish_reason: "stop"` on a reply that calls
 * tools (the TrueFoundry gateway does for Gemini). Pi runs tools only on `toolUse`, so a
 * finished reply that carries tool calls is reported as one.
 */
export function toolCallsStop(streams: ProviderStreams): ProviderStreams {
  const corrected = (source: AssistantMessageEventStream) => {
    const target = createAssistantMessageEventStream();
    void (async () => {
      for await (const event of source) {
        if (
          event.type === "done" &&
          event.reason === "stop" &&
          event.message.content.some((block) => block.type === "toolCall")
        ) {
          target.push({
            ...event,
            reason: "toolUse",
            message: { ...event.message, stopReason: "toolUse" },
          });
        } else target.push(event);
      }
      target.end();
    })();
    return target;
  };
  return {
    ...streams,
    stream: (model, context, options) => corrected(streams.stream(model, context, options)),
    streamSimple: (model, context, options) =>
      corrected(streams.streamSimple(model, context, options)),
  };
}

const apis = {
  "anthropic-messages": anthropicMessagesApi(),
  "openai-responses": openAIResponsesApi(),
  "openai-completions": toolCallsStop(openAICompletionsApi()),
  "google-generative-ai": googleGenerativeAIApi(),
};

// Models pi-ai does not know yet still need reasoning levels and safe defaults.
const plainReasoning = {
  off: null,
  minimal: null,
  low: "low",
  medium: "medium",
  high: "high",
  xhigh: null,
  max: null,
} as const;

function piModel(entry: ModelConfig, config: ModelsConfig): Model<Api> {
  const provider = config.providers[entry.provider];
  if (!provider) throw new Error(`Model ${entry.id} names unknown provider ${entry.provider}`);
  const base = entry.catalog ? catalog.get(entry.catalog) : undefined;
  if (entry.catalog && !base) throw new Error(`pi-ai has no catalog entry ${entry.catalog}`);
  const cost = entry.cost ?? base?.cost;
  const contextWindow = entry.contextWindow ?? base?.contextWindow;
  const maxTokens = entry.maxTokens ?? base?.maxTokens;
  if (!cost || !contextWindow || !maxTokens)
    throw new Error(`Model ${entry.id} needs cost, contextWindow and maxTokens or a catalog entry`);
  return {
    ...(base ?? {
      reasoning: true,
      input: ["text", "image"],
      thinkingLevelMap: plainReasoning,
      ...(entry.api === "openai-completions" ? { compat: { supportsDeveloperRole: false } } : {}),
    }),
    id: entry.model ?? entry.id,
    name: entry.label,
    api: entry.api,
    provider: entry.provider,
    baseUrl: provider.baseUrl,
    cost,
    // Pi compacts against this window, so it is the working limit, not the model's maximum.
    contextWindow: Math.min(contextWindow, config.workingContext),
    maxTokens,
    headers: undefined,
  } as Model<Api>;
}

/**
 * The deployment's models as pi-ai `Models`, one provider per `config/models.ts` provider.
 * `beforeDispatch` gates every request, including retries and compaction; pi observer hooks
 * cannot enforce authorization because their exceptions may only be reported.
 */
export function applicationModels(
  secrets: ModelSecrets,
  beforeDispatch?: (signal?: AbortSignal) => Promise<void>,
  config: ModelsConfig = modelsConfig,
) {
  const models = createModels({
    authContext: {
      env: async (name) => {
        const value = secrets[name];
        return typeof value === "string" && value ? value : undefined;
      },
      fileExists: async () => false,
    },
  });
  // Build every model first so a misconfigured entry fails loudly instead of disappearing.
  const built = config.models.map((entry) => piModel(entry, config));
  for (const [id, provider] of Object.entries(config.providers)) {
    const base: Provider = createProvider({
      id,
      name: provider.name,
      baseUrl: provider.baseUrl,
      auth: {
        apiKey: {
          name: `${provider.name} key`,
          resolve: async ({ ctx }) => {
            const key = await ctx.env(provider.key);
            return key ? { auth: { apiKey: key }, source: provider.key } : undefined;
          },
        },
      },
      models: built.filter((model) => model.provider === id),
      api: apis,
    });
    const limit = { maxTokens: config.maxOutput };
    models.setProvider(
      beforeDispatch
        ? {
            ...base,
            stream: (model, transcript, options) =>
              base.stream<Api>(model, transcript, {
                ...options,
                ...limit,
                onPayload: async (payload) => {
                  await beforeDispatch(options?.signal);
                  return options?.onPayload?.(payload, model);
                },
              }),
            streamSimple: (model, transcript, options) =>
              base.streamSimple(model, transcript, {
                ...options,
                ...limit,
                onPayload: async (payload) => {
                  await beforeDispatch(options?.signal);
                  return options?.onPayload?.(payload, model);
                },
              }),
          }
        : base,
    );
  }
  return models;
}

/** A configured model by its id: what pi needs to select it, and the effort it runs at. */
export function modelChoice(id: string, config: ModelsConfig = modelsConfig) {
  const entry = config.models.find((model) => model.id === id);
  if (!entry) throw new Error(`Model ${id} is not configured in config/models.ts`);
  return {
    provider: entry.provider,
    id: entry.model ?? entry.id,
    thinkingLevel: entry.effort satisfies ModelThinkingLevel,
  };
}

/** Whether a model id is one an employee may be given. */
export const isConfiguredModel = (id: unknown, config: ModelsConfig = modelsConfig): id is string =>
  typeof id === "string" && config.models.some((model) => model.id === id);

/** The model for background work, resolved and checked for a key. */
export function backgroundModel(
  models: ReturnType<typeof applicationModels>,
  secrets: ModelSecrets,
  config: ModelsConfig = modelsConfig,
) {
  const choice = modelChoice(config.defaults.background, config);
  const model = models.getModel(choice.provider, choice.id);
  if (!model) throw new Error(`Unknown background model ${config.defaults.background}`);
  const key = config.providers[choice.provider]!.key;
  if (!secrets[key]) throw new Error(`Missing ${key} for the background model`);
  return model;
}

/** What the apps show when choosing a model: no keys, prices per million tokens. */
export function modelCatalog(config: ModelsConfig = modelsConfig) {
  return {
    defaults: config.defaults,
    models: config.models.map((entry) => {
      const model = piModel(entry, config);
      return {
        id: entry.id,
        label: entry.label,
        vendor: entry.vendor,
        provider: config.providers[entry.provider]!.name,
        summary: entry.summary,
        effort: entry.effort,
        price: {
          input: model.cost.input,
          output: model.cost.output,
          cache_read: model.cost.cacheRead,
        },
        // A typical employee turn: 20k cached context, 3k new input, 1.5k output with thinking.
        typical_turn_usd:
          (20_000 * model.cost.cacheRead + 3_000 * model.cost.input + 1_500 * model.cost.output) /
          1_000_000,
      };
    }),
  };
}
