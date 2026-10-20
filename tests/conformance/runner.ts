import { expect, it } from "vitest";
import type { WorkspacePort } from "../../src/workspace/contract.ts";
import { packageHosts } from "../../src/egress/contract.ts";

/**
 * What a Runner adapter exposes to the shared guarantees in .docs/COMPONENTS.md#runner.
 * Every adapter passes the behaviour suite; only sandboxed adapters claim isolation.
 */
export interface RunnerHarness {
  /** A fresh port over the same durable state, as after a host restart. */
  port(): WorkspacePort;
  /** Record `command` as started but never finished under `operationId`. */
  interrupt(
    operationId: string,
    command: string,
    timeoutMs: number,
    maxBytes: number,
  ): Promise<void>;
  processes(): number;
}

export interface IsolatedRunnerHarness extends RunnerHarness {
  /** Hosts the guest can reach after starting, or "all" when egress is open. */
  egress(): readonly string[] | "all";
}

export function runnerConformance(
  adapter: string,
  harness: (output?: string) => RunnerHarness | Promise<RunnerHarness>,
) {
  it(`${adapter}: replays a recorded result without starting another process`, async () => {
    const runner = await harness();
    expect((await runner.port().run("same", "echo done", 1_000, 1_000)).stdout.trim()).toBe("done");
    expect((await runner.port().run("same", "echo done", 1_000, 1_000)).status).toBe("completed");
    expect(runner.processes()).toBe(1);
  });

  it(`${adapter}: reports an interrupted command as uncertain and never reruns it`, async () => {
    const runner = await harness();
    await runner.interrupt("old", "touch important", 1_000, 1_000);
    const port = runner.port();
    expect((await port.run("old", "touch important", 1_000, 1_000)).status).toBe("uncertain");
    expect(runner.processes()).toBe(0);
    await port.run("new", "ls", 1_000, 1_000);
    expect(runner.processes()).toBe(1);
  });

  it(`${adapter}: bounds output and reports the limit`, async () => {
    const result = await (
      await harness("x".repeat(2_000))
    )
      .port()
      .run("large", "produce", 1_000, 1_000);
    expect(result.status).toBe("limited");
    expect(result.stdout).toHaveLength(1_000);
  });
}

export function runnerIsolation(adapter: string, harness: () => IsolatedRunnerHarness) {
  it(`${adapter}: keeps egress closed except package hosts`, async () => {
    const runner = harness();
    await runner.port().run("start", "true", 1_000, 1_000);
    const reachable = runner.egress();
    expect(reachable).not.toBe("all");
    for (const host of reachable) expect(packageHosts as readonly string[]).toContain(host);
  });
}

/** Files the owner browses and edits: folder listings and saves that refuse a stale revision. */
export function runnerFiles(
  adapter: string,
  harness: () => Promise<{
    port: WorkspacePort;
    root: string;
    put: (key: string, bytes: Uint8Array) => Promise<void>;
  }>,
) {
  it(`${adapter}: lists a folder and refuses a stale save`, async () => {
    const { port, root } = await harness();
    const path = `${root}/docs/plan.md`;
    // Creating names no revision (null): it must not exist yet.
    const created = await port.write(path, "# Plan\n", null);
    await expect(port.write(path, "# Other\n", null)).rejects.toThrow(/Revision conflict/);
    const read = await port.read(path);
    expect(read).toMatchObject({ content: "# Plan\n", revision: created.revision });
    const saved = await port.write(path, "# Plan\nMore.\n", read.revision);
    await expect(port.write(path, "# Stale\n", read.revision)).rejects.toThrow(/Revision conflict/);
    expect((await port.read(path)).revision).toBe(saved.revision);
    await port.write(`${root}/docs/notes/a.txt`, "a");
    const entries = await port.list(`${root}/docs`);
    expect(entries.map((entry) => [entry.name, entry.kind])).toEqual([
      ["notes", "directory"],
      ["plan.md", "file"],
    ]);
    expect(entries[1]).toMatchObject({ path, size: "# Plan\nMore.\n".length });
  });

  it(`${adapter}: saves bytes only over the revision it was read at`, async () => {
    const { port, root, put } = await harness();
    const path = `${root}/sheets/budget.xlsx`;
    await put("first", new Uint8Array([1, 2, 3]));
    await port.importFile(path, "first", null);
    await expect(port.importFile(path, "first", null)).rejects.toThrow(/Revision conflict/);
    const revision = (await port.read(path)).revision;
    await put("second", new Uint8Array([4, 5]));
    await port.importFile(path, "second", revision);
    await expect(port.importFile(path, "first", revision)).rejects.toThrow(/Revision conflict/);
  });
}
