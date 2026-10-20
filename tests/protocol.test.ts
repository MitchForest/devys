import { describe, expect, it } from "vitest";
import { Effect, Schema } from "effect";
import { capability, CapabilityError, Invocation, FilePath } from "../src/protocol/capability.ts";

const input = Schema.Struct({ value: Schema.Number });
const output = Schema.Struct({ doubled: Schema.Number });
const double = capability({
  name: "double",
  description: "Double a number",
  effect: "read",
  replay: "read",
  input,
  output,
  execute: ({ value }) => Effect.succeed({ doubled: value * 2 }),
});

const invocation = Invocation.of({
  businessId: "trusted-business",
  employeeId: "trusted-employee",
  operationId: "op-1",
  authorize: () => Effect.void,
  assertActive: () => Effect.void,
});

describe("Effect capability boundary", () => {
  it("rejects invalid input before executing", async () => {
    const result = await Effect.runPromise(
      double
        .execute({ value: "2" })
        .pipe(Effect.provideService(Invocation, invocation), Effect.flip),
    );
    expect(result.code).toBe("invalid_input");
  });
  it("asks the trusted host to authorize the validated input; model arguments cannot", async () => {
    const seen: unknown[] = [];
    const result = await Effect.runPromise(
      double.execute({ value: 2, grants: ["double"] }).pipe(
        Effect.provideService(Invocation, {
          ...invocation,
          authorize: (contract, input) => {
            seen.push([contract.name, input]);
            return Effect.fail(new CapabilityError({ code: "forbidden", message: "Not granted" }));
          },
        }),
        Effect.flip,
      ),
    );
    expect(result.code).toBe("forbidden");
    expect(seen).toEqual([["double", { value: 2 }]]);
  });
  it("runs validated operations", async () => {
    expect(
      await Effect.runPromise(
        double.execute({ value: 4 }).pipe(Effect.provideService(Invocation, invocation)),
      ),
    ).toEqual({ doubled: 8 });
  });
  it.each(["workspace/file", "/workspace/../other", "/workspace/./file", "/workspace/x\u0000y"])(
    "rejects invalid file path %s",
    (path) => {
      expect(() => Schema.decodeUnknownSync(FilePath)(path)).toThrow();
    },
  );
});
