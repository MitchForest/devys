import { publishArtifact } from "./service.ts";
import { Effect, Schema } from "effect";
import type { Env } from "../../infra/api.ts";
import type { Runner } from "../workspace/contract.ts";
import { capability, Invocation, FilePath } from "../protocol/capability.ts";

export function artifactCapabilities(env: Env, runner: Runner) {
  return [
    capability({
      name: "publishArtifact",
      description:
        "Save a file (absolute path) as a durable private downloadable artifact. The returned link requires a member login.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        path: FilePath,
        filename: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9_. -]{1,200}$/)),
        contentType: Schema.String.check(Schema.isPattern(/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/)),
      }),
      output: Schema.Struct({ id: Schema.String, url: Schema.String, bytes: Schema.Int }),
      execute: ({ path, filename, contentType }) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          return yield* publishArtifact(env, runner, { businessId, employeeId }, operationId, {
            path,
            filename,
            contentType,
          });
        }),
    }),
  ];
}
