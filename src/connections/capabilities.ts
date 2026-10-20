import { Effect, Schema } from "effect";
import { capability, CapabilityError, Invocation, Text } from "../protocol/capability.ts";

import { listDrive, readDrive, writeDrive } from "./drive.ts";
import type { GoogleBindings } from "./google.ts";

export function driveCapabilities(env: GoogleBindings) {
  const drive = <A>(operation: () => Promise<A>) =>
    Effect.tryPromise({
      try: operation,
      catch: (cause) =>
        new CapabilityError({
          code: "unavailable",
          message:
            cause instanceof Error &&
            /^(Connect |Choose |File |This capability |Updates support |Operation belongs|Google Drive |Connection changed)/.test(
              cause.message,
            )
              ? cause.message
              : "Google Drive unavailable; reconnect or inspect the file before repeating a write.",
        }),
    });
  const driveId = Schema.String.check(Schema.isPattern(/^[a-zA-Z0-9_-]{1,200}$/));
  const driveResult = Schema.Struct({
    id: driveId,
    status: Schema.Literals(["prepared", "uncertain", "completed"]),
    url: Schema.String,
  });
  return [
    capability({
      name: "driveList",
      description: "List Google Drive files selected for this business or created by Devys.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Array(
        Schema.Struct({ id: driveId, name: Schema.String, mimeType: Schema.String }),
      ),
      execute: () =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return yield* drive(() => listDrive(env, businessId));
        }),
    }),
    capability({
      name: "driveRead",
      description:
        "Read a selected text file or export a selected Google Doc as plain text, up to 64 KB. Retain etag when proposing a text-file update.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ id: driveId }),
      output: Schema.Struct({
        id: driveId,
        name: Schema.String,
        mimeType: Schema.String,
        content: Text,
        etag: Schema.String,
        url: Schema.String,
      }),
      execute: ({ id }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return yield* drive(() => readDrive(env, businessId, id));
        }),
    }),
    capability({
      name: "driveCreate",
      description:
        "Create a plain-text file in the connected Drive. If uncertain, inspect the returned file id; do not blindly create another copy.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(200)),
        content: Text,
      }),
      output: driveResult,
      execute: (input) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* drive(() =>
            writeDrive(env, invocation.businessId, invocation.operationId, input, () =>
              Effect.runPromise(invocation.assertActive()),
            ),
          );
        }),
    }),
    capability({
      name: "driveUpdate",
      description:
        "Replace the contents of a selected text file using the etag from driveRead. Native Google Docs updates are not supported. Inspect an uncertain outcome before another write.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        id: driveId,
        content: Text,
        etag: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(500)),
      }),
      output: driveResult,
      execute: (input) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* drive(() =>
            writeDrive(env, invocation.businessId, invocation.operationId, input, () =>
              Effect.runPromise(invocation.assertActive()),
            ),
          );
        }),
    }),
  ];
}
