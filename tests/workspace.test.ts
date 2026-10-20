import { expect, it, vi } from "vitest";
import { Workspace } from "../src/workspace/workspace.ts";
import type { Env } from "../infra/api.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { runnerConformance, runnerFiles, runnerIsolation } from "./conformance/runner.ts";

/** The sandbox's file API, in memory. */
const sandboxFiles = vi.hoisted(() => new Map<string, string>());
vi.mock("@cloudflare/sandbox", () => ({
  DirectoryBackup: class {},
  Files: class {
    async readFile(path: string) {
      const text = sandboxFiles.get(path);
      const bytes = new TextEncoder().encode(text ?? "");
      return {
        ok: text !== undefined,
        body: new Response(bytes).body,
        arrayBuffer: async () => bytes.buffer,
      };
    }
    async writeFile(path: string, content: string) {
      sandboxFiles.set(path, content);
    }
    async readDirectory(path: string) {
      const names = new Map<string, "file" | "directory">();
      for (const file of sandboxFiles.keys()) {
        if (!file.startsWith(`${path}/`)) continue;
        const [name, ...rest] = file.slice(path.length + 1).split("/");
        names.set(name!, rest.length ? "directory" : "file");
      }
      return [...names].map(([name, type]) => ({ name, type }));
    }
    async lstat(path: string) {
      return { size: BigInt(new TextEncoder().encode(sandboxFiles.get(path) ?? "").length) };
    }
  },
}));

function fixture(output = "done") {
  const data = new Map<string, unknown>();
  const stream = (text: string) =>
    new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(text));
        controller.close();
      },
    });
  const container = {
    running: true,
    images: { workspace: "fixture-image" },
    destroy: vi.fn(async () => {
      container.running = false;
    }),
    start: vi.fn((_options?: { enableInternet?: boolean }) => {
      container.running = true;
    }),
    interceptOutboundHttps: vi.fn(async (_host: string, _egress: unknown) => {}),
    setInactivityTimeout: vi.fn(async () => {}),
    exec: vi.fn(async () => ({
      stdout: stream(output),
      stderr: stream(""),
      exitCode: Promise.resolve(0),
    })),
  };
  const storage = {
    get: async (key: string) => data.get(key),
    put: async (key: string | Record<string, unknown>, value?: unknown) => {
      if (typeof key === "string") data.set(key, structuredClone(value));
      else for (const [name, item] of Object.entries(key)) data.set(name, structuredClone(item));
    },
    delete: async (key: string) => data.delete(key),
  };
  const ctx = {
    storage,
    container,
    id: { name: "owner" },
    exports: { PublicEgress: {} },
  } as unknown as DurableObjectState;
  const objects = new Map<string, Uint8Array>();
  const files = {
    get: async (key: string) =>
      objects.has(key)
        ? { size: objects.get(key)!.length, body: new TextDecoder().decode(objects.get(key)!) }
        : null,
  };
  return {
    data,
    container,
    objects,
    workspace: () => new Workspace(ctx, { FILES: files } as unknown as Env),
  };
}

const interrupt = async (
  data: Map<string, unknown>,
  operationId: string,
  command: string,
  timeoutMs: number,
  maxBytes: number,
) => {
  data.set(`command:${operationId}`, {
    fingerprint: await sha256(JSON.stringify({ command, timeoutMs, maxBytes })),
  });
  data.set("active-command", { key: `command:${operationId}`, boot: "lost-parent" });
};

function sandboxHarness(output?: string) {
  const state = fixture(output);
  return {
    port: state.workspace,
    interrupt: (operationId: string, command: string, timeoutMs: number, maxBytes: number) =>
      interrupt(state.data, operationId, command, timeoutMs, maxBytes),
    processes: () => state.container.exec.mock.calls.length,
    egress: () =>
      state.container.start.mock.calls.some(([options]) => options?.enableInternet !== false)
        ? "all"
        : state.container.interceptOutboundHttps.mock.calls.map(([host]) => host),
  };
}

runnerConformance("Cloudflare Sandbox", sandboxHarness);
runnerIsolation("Cloudflare Sandbox", () => sandboxHarness());

it("restores the last checkpoint after fencing an interrupted process", async () => {
  const state = fixture();
  await interrupt(state.data, "old", "touch important", 1_000, 1_000);
  state.data.set("snapshot", "last-checkpoint");
  const recovered = state.workspace();
  await recovered.run("old", "touch important", 1_000, 1_000);
  expect(state.container.destroy).toHaveBeenCalledTimes(1);
  await recovered.run("new", "ls", 1_000, 1_000);
  expect(state.container.start).toHaveBeenCalledWith(
    expect.objectContaining({ containerSnapshot: { id: "last-checkpoint" } }),
  );
});

it("terminates the container on output exhaustion", async () => {
  const state = fixture("x".repeat(2_000));
  await state.workspace().run("large", "produce output", 1_000, 1_000);
  expect(state.container.destroy).toHaveBeenCalledTimes(1);
});

it("keeps sandbox paths under /workspace", async () => {
  await expect(fixture().workspace().read("/etc/passwd")).rejects.toThrow("/workspace");
});

runnerFiles("Cloudflare Sandbox", async () => {
  const state = fixture();
  return {
    port: state.workspace(),
    root: `/workspace/files-${crypto.randomUUID()}`,
    put: async (key, bytes) => void state.objects.set(key, bytes),
  };
});
