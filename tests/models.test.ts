import { expect, it, vi } from "vitest";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import { modelsConfig, type ModelsConfig } from "../config/models.ts";
import {
  applicationModels,
  backgroundModel,
  isConfiguredModel,
  modelCatalog,
  modelChoice,
  toolCallsStop,
} from "../src/app/models.ts";

const secrets = { DEVYS_MODEL_GATEWAY_KEY: "test" };

it("loads every configured model on its provider with the working context limit", () => {
  const models = applicationModels(secrets);
  for (const entry of modelsConfig.models) {
    const choice = modelChoice(entry.id);
    const model = models.getModel(choice.provider, choice.id)!;
    expect(model.api).toBe(entry.api);
    expect(model.baseUrl).toBe(modelsConfig.providers.gateway.baseUrl);
    expect(model.contextWindow).toBeLessThanOrEqual(modelsConfig.workingContext);
  }
  // Catalog entries keep pi-ai's own description, such as Opus 5.5's effort mapping.
  const opus = models.getModel("gateway", "claude-opus-5-5")!;
  expect(opus.thinkingLevelMap?.medium).toBe("medium");
  expect(opus.cost.input).toBe(4);
});

it("resolves employee models and refuses unknown ones", () => {
  expect(modelChoice("gpt-6.1-sol")).toEqual({
    provider: "gateway",
    id: "gpt-6.1-sol",
    thinkingLevel: "medium",
  });
  expect(() => modelChoice("not-configured")).toThrow("not configured");
  expect(isConfiguredModel("gemini-4-argon")).toBe(true);
  expect(isConfiguredModel("gpt-4o")).toBe(false);
  expect(isConfiguredModel(undefined)).toBe(false);
});

it("uses the configured background model and requires its provider key", () => {
  expect(backgroundModel(applicationModels(secrets), secrets).id).toBe("gpt-6-luna");
  expect(() => backgroundModel(applicationModels({}), {})).toThrow(
    "Missing DEVYS_MODEL_GATEWAY_KEY",
  );
});

it("describes models for the apps without keys", () => {
  const catalog = modelCatalog();
  expect(catalog.defaults).toEqual({ employee: "claude-opus-5-5", background: "gpt-6-luna" });
  const opus = catalog.models.find((model) => model.id === "claude-opus-5-5")!;
  expect(opus).toMatchObject({ vendor: "Anthropic", provider: "TrueFoundry gateway" });
  expect(opus.typical_turn_usd).toBeCloseTo(0.046, 3);
  expect(JSON.stringify(catalog)).not.toContain("DEVYS_MODEL_GATEWAY_KEY");
  expect(new Set(catalog.models.map((model) => model.vendor))).toEqual(
    new Set(["Anthropic", "OpenAI", "Google"]),
  );
});

it("rejects a model that names an unknown provider or lacks a price", () => {
  const broken = (patch: Partial<ModelsConfig["models"][number]>): ModelsConfig => ({
    ...modelsConfig,
    models: [{ ...modelsConfig.models[5]!, catalog: undefined, ...patch }],
  });
  expect(() => applicationModels(secrets, undefined, broken({ provider: "nowhere" }))).toThrow(
    "unknown provider",
  );
  expect(() => applicationModels(secrets, undefined, broken({ cost: undefined }))).toThrow(
    "needs cost",
  );
});

it.each(["claude-opus-5-5", "gpt-6.1-sol", "gemini-4-argon"])(
  "%s checks authority before either streaming API sends a request",
  async (id) => {
    const gate = vi.fn(async () => {
      throw new Error("Owner access revoked");
    });
    const models = applicationModels(secrets, gate);
    const choice = modelChoice(id);
    const model = models.getModel(choice.provider, choice.id)!;
    const fetch = vi.fn(async () => {
      throw new Error("Network must not run");
    });
    vi.stubGlobal("fetch", fetch);
    try {
      for (const stream of [models.stream.bind(models), models.streamSimple.bind(models)]) {
        const response = await stream(
          model,
          { messages: [{ role: "user", content: "Hello", timestamp: Date.now() }] },
          { maxRetries: 0 },
        ).result();
        expect(response.stopReason).toBe("error");
        expect(response.errorMessage).toContain("Owner access revoked");
      }
      expect(gate).toHaveBeenCalledTimes(2);
      expect(fetch).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
    }
  },
);

it("reports a finished reply that calls tools as tool use, and leaves plain replies alone", async () => {
  const reply = (content: AssistantMessage["content"]) => () => {
    const stream = createAssistantMessageEventStream();
    const message = { role: "assistant", content, stopReason: "stop" } as AssistantMessage;
    queueMicrotask(() => {
      stream.push({ type: "done", reason: "stop", message });
      stream.end();
    });
    return stream;
  };
  const call = { type: "toolCall", id: "1", name: "run", arguments: {} } as const;
  const text = { type: "text", text: "Done." } as const;
  const streams = (content: AssistantMessage["content"]) =>
    toolCallsStop({ stream: reply(content), streamSimple: reply(content) });
  const model = {} as never;
  const context = { messages: [] } as never;
  expect((await streams([call]).stream(model, context).result()).stopReason).toBe("toolUse");
  expect((await streams([text]).streamSimple(model, context).result()).stopReason).toBe("stop");
});
