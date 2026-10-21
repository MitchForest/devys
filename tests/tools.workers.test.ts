import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { devysExtension, initialTools, describeCapabilities } from "../src/runtime/codemode.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { identityText } from "../src/runtime/host.ts";

it("keeps initial schemas smaller and returns only requested integration interfaces", () => {
  const bindings = { DEVYS_MODE: "cloud" } as Env;
  const contracts = capabilities(bindings);
  const extension = devysExtension(bindings, contracts, {
    identity: async () => "You are a test employee.",
    granted: async () => new Set(contracts.map((contract) => contract.name)),
    skills: async () => [],
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
  const everything = new Set(contracts.map((contract) => contract.name));
  const initial = schemaBytes(initialTools(extension, contracts, everything));
  // The granted core capabilities and the two harness controls, from `core` on each capability.
  expect(
    initialTools(extension, contracts, new Set(["run", "remember"]))
      .map((tool) => tool.name)
      .sort(),
  ).toEqual(["describe_capabilities", "execute", "remember", "run"].sort());
  expect(
    initialTools(extension, contracts, everything)
      .map((tool) => tool.name)
      .sort(),
  ).toEqual(
    [
      "describe_capabilities",
      "execute",
      "forget",
      "read",
      "readSkill",
      "recall",
      "remember",
      "run",
      "write",
    ].sort(),
  );
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
    skills: async () => [],
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

it("the instructions list the available skills by name and description, and point at readSkill", async () => {
  const bindings = { DEVYS_MODE: "cloud" } as Env;
  const contracts = capabilities(bindings);
  const extension = devysExtension(bindings, contracts, {
    identity: async () => "You are a test employee.",
    granted: async () => new Set(),
    skills: async () => [
      { name: "weekly-report", description: "Build the weekly report" },
      { name: "writing-pages", description: "Write a page" },
    ],
    authority: async () => {
      throw new Error("Instructions must not invoke a capability");
    },
  });
  const render = extension.sections![0]!.render as unknown as () => Promise<string>;
  const text = await render();
  expect(text).toContain("readSkill");
  expect(text).not.toContain("listSkills");
  expect(text).toMatch(
    /Skills:\n- weekly-report — Build the weekly report\n- writing-pages — Write a page$/,
  );
});

it("an employee's prompt names each colleague with the employee id work and projects take", () => {
  const text = identityText(
    {
      name: "Head of Operations",
      responsibilities: "Runs the business.",
      businessName: "Acme",
      brief: "",
      paused: false,
      colleagues: [{ id: "emp-growth-1", name: "Growth", does: "Finds customers" }],
    },
    "You work on the owner's Mac.",
  );
  expect(text).toContain("Your colleagues: Growth (employee id emp-growth-1; Finds customers).");
  expect(text).toContain("naming them by employee id");
});
