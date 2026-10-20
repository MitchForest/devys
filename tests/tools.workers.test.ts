import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { devysExtension, initialTools, describeCapabilities } from "../src/runtime/codemode.ts";
import { capabilities } from "../src/app/capabilities.ts";

it("keeps initial schemas smaller and returns only requested integration interfaces", () => {
  const bindings = { DEVYS_MODE: "cloud" } as Env;
  const contracts = capabilities(bindings);
  const extension = devysExtension(bindings, contracts, {
    identity: async () => "You are a test employee.",
    granted: async () => new Set(contracts.map((contract) => contract.name)),
    authority: async () => {
      throw new Error("Discovery must not invoke a capability");
    },
  });
  const schemaBytes = (tools: typeof extension.tools) =>
    new TextEncoder().encode(
      JSON.stringify(
        tools?.map(({ name, description, parameters }) => ({ name, description, parameters })),
      ),
    ).byteLength;
  const initial = schemaBytes(initialTools(extension));
  const all = schemaBytes(extension.tools);
  expect(initial).toBeLessThan(all * 0.75);
  const catalog = JSON.parse(describeCapabilities(contracts));
  expect(catalog.find((c: { name: string }) => c.name === "driveRead")).toEqual({
    name: "driveRead",
    description: expect.any(String),
  });
  const selected = describeCapabilities(contracts, ["driveRead"]);
  expect(selected).toContain("driveRead");
  expect(selected).not.toContain("driveCreate");
  expect(() => describeCapabilities(contracts, ["unknown"])).toThrow("Unknown capability");
});

it("discovery lists and enables only capabilities the employee is granted", async () => {
  const bindings = { DEVYS_MODE: "cloud" } as Env;
  const contracts = capabilities(bindings);
  const extension = devysExtension(bindings, contracts, {
    identity: async () => "You are a test employee.",
    granted: async () => new Set(["recall", "driveRead"]),
    authority: async () => {
      throw new Error("Discovery must not invoke a capability");
    },
  });
  const describe = extension.tools?.find((tool) => tool.name === "describe_capabilities");
  const run = (names?: string[]) =>
    describe!.execute(
      names ? { names } : {},
      { taskId: "t" } as never,
      { abortSignal: undefined } as never,
    ) as Promise<{ content: { text: string }[]; control?: { addTools: string[] } }>;
  const catalog = JSON.parse((await run()).content[0]!.text) as { name: string }[];
  expect(catalog.map((item) => item.name).sort()).toEqual(["driveRead", "recall"]);
  const selected = await run(["driveRead", "driveCreate"]);
  expect(selected.control?.addTools).toEqual(["driveRead"]);
  expect(selected.content[0]!.text).not.toContain("driveCreate");
});
