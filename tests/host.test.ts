import { createHash } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { runnerFor } from "../src/app/runner.ts";
import type { WorkspacePort } from "../src/workspace/contract.ts";
import { hostRunner, type HostConnection } from "../src/workspace/host.ts";
import { startHost } from "../src/workspace/host/server.ts";
import { runnerConformance, runnerFiles, type RunnerHarness } from "./conformance/runner.ts";

const token = "test-token";
const scope = { businessId: "business-1", employeeId: "employee-1" };
const running: { close(): Promise<void> }[] = [];
afterAll(() => Promise.all(running.map((host) => host.close())));

/** An in-memory stand-in for the R2 calls the host adapter makes. */
function bucket(): HostConnection["files"] {
  const objects = new Map<string, ArrayBuffer>();
  const view = (bytes: ArrayBuffer) => ({ size: bytes.byteLength, arrayBuffer: async () => bytes });
  return {
    get: async (key: string) => (objects.has(key) ? view(objects.get(key)!) : null),
    head: async (key: string) => (objects.has(key) ? view(objects.get(key)!) : null),
    put: async (key: string, value: ArrayBuffer) => {
      objects.set(key, value);
      return view(value);
    },
  } as unknown as HostConnection["files"];
}

/** A real host process state in a temporary directory; `restart` keeps its receipts. */
async function host(output = "done") {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "devys-host-")));
  const bin = join(root, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "produce"), `#!/bin/sh\nprintf '%s' '${output}'\n`);
  chmodSync(join(bin, "produce"), 0o755);
  const options = {
    token,
    data: join(root, "data"),
    work: join(root, "work"),
    skills: join(root, "skills"),
    port: 0,
    shell: "/bin/sh",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
  };
  let spawned = 0;
  let current = await startHost(options);
  running.push({ close: () => current.close() });
  const files = bucket();
  const url = () => `http://127.0.0.1:${current.port}`;
  const port = (): WorkspacePort => hostRunner({ url: url(), token, files }, scope);
  return {
    root,
    url,
    files,
    port,
    spawned: () => spawned + current.spawned(),
    async restart() {
      spawned += current.spawned();
      await current.close();
      current = await startHost(options);
    },
    ledger: join(options.data, "receipts.jsonl"),
  };
}

runnerConformance("Mac host", async (output): Promise<RunnerHarness> => {
  const state = await host(output);
  // port() must be synchronous; the harness restarts the host inside interrupt().
  return {
    port: state.port,
    processes: state.spawned,
    async interrupt(operationId, command, timeoutMs, maxBytes) {
      const fingerprint = createHash("sha256")
        .update(JSON.stringify({ command, timeoutMs, maxBytes }))
        .digest("hex");
      const key = `${scope.businessId}/${scope.employeeId}/${operationId}`;
      appendFileSync(state.ledger, `${JSON.stringify({ key, fingerprint })}\n`);
      await state.restart();
    },
  };
});

describe("Mac host", () => {
  it("runs in the business folder and keeps receipts across a restart", async () => {
    const state = await host();
    const first = await state.port().run("pwd", "pwd", 5_000, 10_000);
    expect(first.stdout.trim()).toBe(join(state.root, "work", scope.businessId));
    await state.restart();
    expect(await state.port().run("pwd", "pwd", 5_000, 10_000)).toEqual(first);
    expect(state.spawned()).toBe(1);
  });

  it("runs a command once when the same operation arrives twice at the same moment", async () => {
    const state = await host();
    const [first, second] = await Promise.all([
      state.port().run("twice", "sleep 0.2; echo ran", 5_000, 10_000),
      state.port().run("twice", "sleep 0.2; echo ran", 5_000, 10_000),
    ]);
    expect(state.spawned()).toBe(1);
    expect([first.status, second.status].sort()).toEqual(["completed", "uncertain"]);
  });

  it("stops a running command", async () => {
    const state = await host();
    const runner = state.port();
    const pending = runner.run("long", "sleep 30", 60_000, 10_000);
    await new Promise((resolve) => setTimeout(resolve, 300));
    await runner.cancel();
    expect((await pending).status).toBe("cancelled");
  });

  it("times out a command as limited", async () => {
    const state = await host();
    expect((await state.port().run("slow", "sleep 5", 1_000, 10_000)).status).toBe("limited");
  });

  it("reads and writes owner files and moves bytes through R2", async () => {
    const state = await host();
    const runner = state.port();
    const path = join(state.root, "owner", "notes.md");
    await runner.write(path, "hello");
    expect((await runner.read(path)).content).toBe("hello");
    expect(await runner.exportFile(path, "artifact", 1_000)).toEqual({ size: 5 });
    await runner.importFile(join(state.root, "copy.md"), "artifact");
    expect(readFileSync(join(state.root, "copy.md"), "utf8")).toBe("hello");
    expect(await runner.checkpoint()).toEqual({ kind: "durable" });
  });

  it("keeps the owner's file views inside the business folder, links followed", async () => {
    const state = await host();
    const folder = join(state.root, "work", scope.businessId);
    mkdirSync(join(state.root, "private"), { recursive: true });
    mkdirSync(folder, { recursive: true });
    writeFileSync(join(state.root, "private", "key"), "secret");
    symlinkSync(join(state.root, "private"), join(folder, "linked"));
    const views = hostRunner(
      { url: state.url(), token, files: state.files, within: folder },
      scope,
    );
    await views.write(join(folder, "new", "notes.md"), "hello");
    expect((await views.read(join(folder, "new", "notes.md"))).content).toBe("hello");
    await expect(views.read(join(folder, "linked", "key"))).rejects.toThrow("inside");
    await expect(views.list(join(folder, "linked"))).rejects.toThrow("inside");
    await expect(views.write(join(folder, "linked", "planted"), "x")).rejects.toThrow("inside");
    await expect(views.exportFile(join(folder, "linked", "key"), "k", 100)).rejects.toThrow(
      "inside",
    );
    await expect(views.read(join(state.root, "private", "key"))).rejects.toThrow("inside");
    // Employees are not confined on the trusted host.
    expect((await state.port().read(join(folder, "linked", "key"))).content).toBe("secret");
  });

  it("refuses a wrong token and relative paths", async () => {
    const state = await host();
    const stranger = hostRunner({ url: state.url(), token: "wrong", files: state.files }, scope);
    await expect(stranger.run("x", "true", 1_000, 1_000)).rejects.toThrow("Unauthorized");
    await expect(state.port().read("relative/path")).rejects.toThrow("absolute");
  });
});

describe("runner selection", () => {
  const base = { FILES: bucket(), WORKSPACE: { getByName: (name: string) => ({ name }) } };
  it("uses the sandbox in cloud mode", () => {
    const runner = runnerFor({ ...base, DEVYS_MODE: "cloud" } as unknown as Env);
    expect(runner(scope)).toEqual({ name: JSON.stringify([scope.businessId, scope.employeeId]) });
  });
  it("uses the Mac host in local mode and says so when it is not configured", () => {
    const configured = runnerFor({
      ...base,
      DEVYS_MODE: "local",
      DEVYS_HOST_URL: "http://127.0.0.1:1",
      DEVYS_HOST_TOKEN: token,
    } as unknown as Env);
    expect(configured(scope).checkpoint).toBeTypeOf("function");
    const missing = runnerFor({ ...base, DEVYS_MODE: "local" } as unknown as Env);
    expect(() => missing(scope)).toThrow("not configured");
  });
  it("refuses an unknown mode", () => {
    expect(() => runnerFor({ ...base } as unknown as Env)).toThrow("DEVYS_MODE");
  });
});

runnerFiles("Mac host", async () => {
  const state = await host();
  return {
    port: state.port(),
    root: state.root,
    put: async (key, bytes) => void (await state.files.put(key, bytes.slice().buffer)),
  };
});

describe.skipIf(!existsSync("/Applications/Google Chrome.app"))("printing", () => {
  it("prints an HTML file to a PDF with Chrome", async () => {
    const state = await host();
    const runner = state.port();
    const source = join(state.root, "quote.html");
    await runner.write(source, "<h1>Quote</h1><p>Ten campaigns.</p>");
    const printed = await runner.printPdf(source, join(state.root, "out", "quote.pdf"));
    expect(printed.size).toBeGreaterThan(500);
    expect(
      readFileSync(join(state.root, "out", "quote.pdf"))
        .subarray(0, 4)
        .toString(),
    ).toBe("%PDF");
    await expect(runner.printPdf(source, join(state.root, "quote.txt"))).rejects.toThrow(/\.pdf/);
  }, 60_000);
});
