import { Effect, Schema } from "effect";
import { capability, CapabilityError, Invocation, Text, FilePath } from "../protocol/capability.ts";
import { defaultLimits } from "../protocol/limits.ts";
import { rpc } from "../protocol/rpc.ts";
import { isSkillName, parseSkill, type Skill } from "../protocol/skill.ts";
import type { Runner } from "./contract.ts";
const PathResult = Schema.Struct({ path: FilePath });

/** The Computer app: commands, files and skills where the employee works. */
export function workspaceCapabilities(
  runner: Runner,
  /** The skills the business's installed apps ship. */
  appSkills: (businessId: string) => Promise<readonly Skill[]>,
) {
  return [
    capability({
      name: "readSkill",
      description:
        "Load a skill listed in your instructions by name: its description and instructions. A business skill also gives the path of its SKILL.md; its scripts and files sit beside it.",
      effect: "read",
      replay: "read",
      core: true,
      input: Schema.Struct({ name: Schema.String.check(Schema.makeFilter(isSkillName)) }),
      output: Schema.Struct({
        name: Schema.String,
        description: Schema.String,
        body: Schema.String,
        path: Schema.optional(FilePath),
      }),
      execute: ({ name }) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          const port = runner(invocation);
          // The business's own skill wins over an app's of the same name.
          const own = (yield* rpc(() => port.skills())).skills.find((skill) => skill.name === name);
          if (own) {
            const skill = parseSkill(name, (yield* rpc(() => port.read(own.path))).content);
            if (skill) return { ...skill, path: own.path };
          }
          const bundled = (yield* rpc(() => appSkills(invocation.businessId))).find(
            (skill) => skill.name === name,
          );
          if (bundled) return bundled;
          return yield* new CapabilityError({
            code: "invalid_input",
            message: `No skill is named ${name}; your instructions list the skills you have.`,
          });
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
      core: true,
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
      core: true,
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
      core: true,
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
