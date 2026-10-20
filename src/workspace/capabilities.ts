import { Effect, Schema } from "effect";
import { capability, Invocation, Text, FilePath } from "../protocol/capability.ts";
import { defaultLimits } from "../protocol/limits.ts";
import { rpc } from "../protocol/rpc.ts";
import type { Runner } from "./contract.ts";
const PathResult = Schema.Struct({ path: FilePath });

export function workspaceCapabilities(runner: Runner) {
  return [
    capability({
      name: "listSkills",
      description:
        "Discover reusable skills by name, description and path. Read the relevant SKILL.md before using or improving its scripts. Create new skills in your skills folder as <name>/SKILL.md; lowercase names with hyphens, YAML name/description, and Markdown instructions.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Struct({
        skills: Schema.Array(
          Schema.Struct({ name: Schema.String, description: Schema.String, path: FilePath }),
        ),
        warnings: Schema.Array(Schema.String),
      }),
      execute: () =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* rpc(() => runner(invocation).listSkills());
        }),
    }),
    capability({
      name: "importAttachment",
      description:
        "Copy a saved message attachment to a file, using its attachment id and an absolute path.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        id: Schema.String.check(Schema.isPattern(/^[a-f0-9]{64}$/)),
        path: FilePath,
      }),
      output: PathResult,
      execute: ({ id, path }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          yield* rpc(() =>
            runner(invocation).importFile(path, `${invocation.businessId}/inputs/${id}`),
          );
          return { path };
        }),
    }),
    capability({
      name: "read",
      description: "Read a UTF-8 file by absolute path (64 KB maximum).",
      effect: "read",
      replay: "read",
      input: PathResult,
      output: Schema.Struct({ path: FilePath, content: Text }),
      execute: ({ path }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          const { content } = yield* rpc(() => runner(invocation).read(path));
          return { path, content };
        }),
    }),
    capability({
      name: "write",
      description: "Write a UTF-8 file by absolute path. This replaces its contents.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ path: FilePath, content: Text }),
      output: PathResult,
      execute: ({ path, content }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          yield* rpc(() => runner(invocation).write(path, content));
          return { path };
        }),
    }),
    capability({
      name: "printPdf",
      description:
        "Print an HTML file to a PDF with a real browser, for documents meant to be read or sent as PDFs. Write the HTML (with its own styles) first; give absolute paths ending in .html and .pdf.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ source: FilePath, target: FilePath }),
      output: Schema.Struct({ path: FilePath, size: Schema.Number }),
      execute: ({ source, target }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* rpc(() => runner(invocation).printPdf(source, target));
        }),
    }),
    capability({
      name: "run",
      description:
        "Run a shell command where you work (your instructions say where). On an uncertain result, inspect existing state; never blindly repeat a side effect.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Struct({ command: Text }),
      output: Schema.Struct({
        status: Schema.Literals(["completed", "uncertain", "cancelled", "limited"]),
        exitCode: Schema.NullOr(Schema.Int),
        stdout: Schema.String,
        stderr: Schema.String,
      }),
      execute: ({ command }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* rpc(() =>
            runner(invocation).run(
              invocation.operationId,
              command,
              defaultLimits.maxCommandMs,
              defaultLimits.maxOutputBytes,
            ),
          );
        }),
    }),
  ];
}
