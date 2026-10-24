/** The capability a remote app's tool becomes once the owner turns the app on. */
import { Effect, Schema } from "effect";
import { capability, Invocation } from "../protocol/capability.ts";
import { rpc } from "../protocol/rpc.ts";
import type { Line, RemoteTool, ToolResult } from "./contract.ts";

/** The most of a remote tool's answer the employee reads back. */
const resultChars = 20_000;

/**
 * A remote tool as a capability. Its effect follows the tool's own hint (a read, or a write to the
 * outside), its mode the owner's line (a grant's `auto` or `ask`, set when the owner turned the
 * app on), and a write is reconciled after an interruption, never replayed. The input is checked
 * at the boundary only (an object with the tool's required keys, at most 64 KB): JSON Schema is
 * the remote server's own language and it validates the rest.
 */
export function remoteCapability(
  name: string,
  app: { name: string },
  tool: RemoteTool,
  call: (businessId: string, args: Record<string, unknown>) => Promise<ToolResult>,
) {
  const required = Array.isArray(tool.input.required)
    ? tool.input.required.filter((key): key is string => typeof key === "string")
    : [];
  const reads = tool.hints.readOnlyHint === true;
  return capability({
    name,
    description: `${app.name}: ${tool.title ? `${tool.title}. ` : ""}${tool.description}`.slice(
      0,
      2_000,
    ),
    effect: reads ? "read" : "external",
    replay: reads ? "read" : "reconcile",
    activity: `Using ${app.name}`,
    remoteSchema: tool.input,
    input: Schema.Record(Schema.String, Schema.Unknown).check(
      Schema.makeFilter(
        (value) => JSON.stringify(value).length <= 64_000 || "At most 64 KB of arguments",
      ),
      Schema.makeFilter((value) => {
        const missing = required.filter((key) => !(key in value));
        return !missing.length || `Missing ${missing.join(", ")}`;
      }),
    ),
    output: Schema.Struct({
      text: Schema.String,
      data: Schema.optionalKey(Schema.Unknown),
      error: Schema.Boolean,
    }),
    execute: (args) =>
      Effect.gen(function* () {
        const { businessId } = yield* Invocation;
        const result = yield* rpc(() => call(businessId, args));
        const text =
          result.text.length > resultChars
            ? `${result.text.slice(0, resultChars)}… (cut: ask for less)`
            : result.text;
        const data =
          result.data !== undefined && JSON.stringify(result.data).length <= resultChars
            ? { data: result.data }
            : {};
        return { text, ...data, error: result.error };
      }),
  });
}

/** For tests and wiring: whether a line lets an employee use the tool at all. */
export const offered = (line: Line | undefined): line is Exclude<Line, "never"> =>
  line === "own" || line === "ask";
