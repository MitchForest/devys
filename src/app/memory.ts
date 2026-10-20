import { Effect } from "effect";
import type { Database } from "../data/database.ts";
import { businessName } from "../identity/service.ts";
import { createMemory } from "../memory/service.ts";
import { consolidation } from "../memory/consolidation.ts";
import type { Memory } from "../memory/contract.ts";
import { applicationModels, backgroundModel, type ModelSecrets } from "./models.ts";
/** The only production selection of a memory implementation; memory is business-wide. */
export function memoryFor(
  env: { HYPERDRIVE: Database } & ModelSecrets,
  businessId: string,
  signal?: AbortSignal,
): Memory {
  const active = async () => {
    if (!(await Effect.runPromise(businessName(env.HYPERDRIVE, businessId))))
      throw new Error("Business is unavailable");
  };
  return createMemory(
    env.HYPERDRIVE,
    businessId,
    consolidation(async (system, input) => {
      signal?.throwIfAborted();
      await active();
      const models = applicationModels(env);
      const model = backgroundModel(models, env);
      const response = await models.completeSimple(
        model,
        {
          systemPrompt: system,
          messages: [{ role: "user", content: input, timestamp: Date.now() }],
        },
        {
          maxTokens: 6000,
          signal: AbortSignal.any([AbortSignal.timeout(45000), ...(signal ? [signal] : [])]),
        },
      );
      if (response.stopReason !== "stop") throw new Error("Memory completion interrupted");
      signal?.throwIfAborted();
      await active();
      return response.content
        .filter((c) => c.type === "text")
        .map((c) => c.text)
        .join("\n");
    }),
    async () => {
      signal?.throwIfAborted();
      await active();
    },
  );
}
