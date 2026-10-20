/**
 * The models Devys employees can use, and where they run. This is the one place to change
 * providers or models: add a provider (a base URL and the name of the secret holding its
 * key), then list models against it. Keys themselves never live here; `key` names a
 * Worker secret (`.env` locally, a deployment secret in cloud mode).
 *
 * A model with `catalog` inherits pi-ai's built-in description of that model (how effort
 * maps to the provider, caching, input limits, compatibility flags, price); fields given
 * here override it. A model pi-ai does not know yet spells those fields out.
 *
 * Examples of other providers:
 *   openrouter: { name: "OpenRouter", baseUrl: "https://openrouter.ai/api/v1", key: "OPENROUTER_API_KEY" }
 *   anthropic: { name: "Anthropic", baseUrl: "https://api.anthropic.com", key: "ANTHROPIC_API_KEY" }
 */
export type ModelApi =
  | "anthropic-messages"
  | "openai-responses"
  | "openai-completions"
  | "google-generative-ai";
export type Effort = "low" | "medium" | "high";

export interface ProviderConfig {
  name: string;
  baseUrl: string;
  /** The Worker secret that holds this provider's API key. */
  key: string;
}

export interface ModelConfig {
  /** Stable id stored on employees; the wire model id unless `model` says otherwise. */
  id: string;
  label: string;
  /** Who makes the model, for grouping in the apps. */
  vendor: string;
  provider: string;
  /** The model id the provider expects, when it differs from `id`. */
  model?: string;
  /** A pi-ai catalog entry to inherit from, as `<pi provider>/<model id>`. */
  catalog?: string;
  api: ModelApi;
  effort: Effort;
  summary: string;
  /** Dollars per million tokens. */
  cost?: { input: number; output: number; cacheRead: number; cacheWrite: number };
  contextWindow?: number;
  maxTokens?: number;
}

export interface ModelsConfig {
  providers: Record<string, ProviderConfig>;
  models: ModelConfig[];
  /** The model new employees start with, and the one background work (memory) uses. */
  defaults: { employee: string; background: string };
  /**
   * Conversations compact before they reach this many tokens, whatever the model's window,
   * so cost per turn stays bounded (and OpenAI's long-context price tier is never hit).
   */
  workingContext: number;
  /** Most tokens one response may use, thinking included. */
  maxOutput: number;
}

export const modelsConfig = {
  providers: {
    gateway: {
      name: "TrueFoundry gateway",
      baseUrl: "https://tfy.promptlens.trilogy.com",
      key: "DEVYS_MODEL_GATEWAY_KEY",
    },
  },
  models: [
    {
      id: "claude-opus-5-5",
      label: "Claude Opus 5.5",
      vendor: "Anthropic",
      provider: "gateway",
      catalog: "anthropic/claude-opus-5-5",
      api: "anthropic-messages",
      effort: "medium",
      summary: "Best judgment and the most reliable long, tool-heavy work.",
    },
    {
      id: "claude-fable-5-1",
      label: "Claude Fable 5.1",
      vendor: "Anthropic",
      provider: "gateway",
      catalog: "anthropic/claude-fable-5-1",
      api: "anthropic-messages",
      effort: "medium",
      summary: "Anthropic's most capable model, for the hardest problems. Costs the most.",
    },
    {
      id: "gpt-6.1-sol",
      label: "GPT-6.1 Sol",
      vendor: "OpenAI",
      provider: "gateway",
      catalog: "openai/gpt-6.1-sol",
      api: "openai-responses",
      effort: "medium",
      summary: "Strong all-round reasoning at half the price of Opus.",
    },
    {
      id: "gpt-6-astra",
      label: "GPT-6 Astra",
      vendor: "OpenAI",
      provider: "gateway",
      catalog: "openai/gpt-6-astra",
      api: "openai-responses",
      effort: "medium",
      summary: "OpenAI's most capable model. About five times Sol's price.",
    },
    {
      id: "gpt-6-luna",
      label: "GPT-6 Luna",
      vendor: "OpenAI",
      provider: "gateway",
      catalog: "openai/gpt-6-luna",
      api: "openai-responses",
      effort: "low",
      summary: "Very fast and very cheap; suited to background and routine work.",
    },
    {
      id: "gemini-4-argon",
      label: "Gemini 4 Argon",
      vendor: "Google",
      provider: "gateway",
      api: "openai-completions",
      effort: "medium",
      summary: "Long documents and images. Introductory price until 30 November 2026.",
      // Not in pi-ai's catalog yet. $2/$10 until 2026-11-30, then $4/$20 (cache $0.20).
      cost: { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 0 },
      contextWindow: 1_048_576,
      maxTokens: 65_536,
    },
    {
      id: "gemini-3.8-flash",
      label: "Gemini 3.8 Flash",
      vendor: "Google",
      provider: "gateway",
      api: "openai-completions",
      effort: "medium",
      summary: "Quick and inexpensive, with a very large context.",
      cost: { input: 0.75, output: 3.75, cacheRead: 0.075, cacheWrite: 0 },
      contextWindow: 1_048_576,
      maxTokens: 65_536,
    },
  ],
  defaults: { employee: "claude-opus-5-5", background: "gpt-6-luna" },
  workingContext: 200_000,
  maxOutput: 32_000,
} satisfies ModelsConfig;
