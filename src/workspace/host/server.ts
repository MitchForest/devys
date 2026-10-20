/**
 * The trusted Mac host side of the runner (local mode; .docs/COMPONENTS.md#runner). The
 * local launcher runs it as the owner, on loopback only, behind a per-install token.
 * Commands run in the owner's login shell with the owner's tools and logins, starting in
 * the business's working folder. Receipts are an append-only JSON-lines file: a repeated
 * operation returns its recorded result, and a command cut off by a restart reports
 * uncertain and is never run again. It uses only Node APIs, so Bun and tests both run it.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { lstat, mkdir, readdir, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { dirname, join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { Readable } from "node:stream";
import { HostRefusal as Refusal, scopeOf, type HostRoutes } from "../../protocol/host.ts";
import { withinCommandLimits } from "../../protocol/limits.ts";
import type { CommandResult } from "../contract.ts";
import { listWorkspaceSkills } from "../skills.ts";

export interface HostOptions {
  token: string;
  /** Where receipts live. */
  data: string;
  /** Each business works in `<work>/<businessId>`. */
  work: string;
  skills: string;
  port: number;
  shell?: string;
  env?: NodeJS.ProcessEnv;
  /** The browser that prints HTML to PDF. */
  chrome?: string;
  /** Other components' routes on this host, composed by `src/host.ts`. */
  routes?: readonly HostRoutes[];
}

interface Receipt {
  key: string;
  fingerprint: string;
  result?: CommandResult;
}

type Scope = { businessId: string; employeeId: string };

const inlineBytes = 64_000;
/** Documents the owner edits can be larger than what an employee reads at once. */
const textBytes = 1_000_000;
const revisionOf = (content: string | Buffer) => createHash("sha256").update(content).digest("hex");
const fileBytes = 20_000_000;

const sha256 = (value: string) => createHash("sha256").update(value).digest();

function absolute(path: unknown): string {
  if (
    typeof path !== "string" ||
    !path.startsWith("/") ||
    path.includes("\u0000") ||
    path.length > 1024 ||
    path.split("/").some((part) => part === "." || part === "..")
  )
    throw new Refusal(400, "Use an absolute path without . or .. segments");
  return path;
}

/**
 * `path` itself when it stays inside `within` after following symbolic links (a missing file
 * is judged by its nearest existing folder). Without `within` any absolute path is allowed:
 * employees on the trusted host work anywhere the owner can.
 */
async function confined(path: string, within: unknown) {
  if (within === undefined || within === null) return path;
  const root = await realpath(absolute(within)).catch(() => undefined);
  let existing = path;
  let real: string | undefined;
  for (;;) {
    real = await realpath(existing).catch(() => undefined);
    if (real || existing === "/") break;
    existing = dirname(existing);
  }
  const resolved = real && join(real, relative(existing, path));
  if (!root || !resolved || (resolved !== root && !resolved.startsWith(`${root}/`)))
    throw new Refusal(403, "Stay inside the business folder");
  return path;
}

async function body(request: IncomingMessage, limit: number) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += (chunk as Buffer).length;
    if (size > limit) throw new Refusal(413, "Request too large");
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}

/** The node:fs view the shared skill parser expects. */
const skillFiles = {
  async lstat(path: string) {
    const info = await lstat(path);
    return {
      type: info.isSymbolicLink() ? "symlink" : info.isDirectory() ? "directory" : "file",
      size: BigInt(info.size),
    };
  },
  async readDirectory(path: string) {
    return (await readdir(path, { withFileTypes: true })).map((entry) => ({
      name: entry.name,
      type: entry.isDirectory() ? "directory" : entry.isSymbolicLink() ? "symlink" : "file",
    }));
  },
  async readFile(path: string) {
    return new Response(await readFile(path));
  },
};

export async function startHost(options: HostOptions) {
  mkdirSync(options.data, { recursive: true });
  const ledger = join(options.data, "receipts.jsonl");
  const receipts = new Map<string, Receipt>();
  if (existsSync(ledger))
    for (const line of readFileSync(ledger, "utf8").split("\n").filter(Boolean)) {
      const receipt = JSON.parse(line) as Receipt;
      receipts.set(receipt.key, receipt);
    }
  const record = (receipt: Receipt) => {
    receipts.set(receipt.key, receipt);
    appendFileSync(ledger, `${JSON.stringify(receipt)}\n`);
  };
  // Anything started before this process began was interrupted.
  for (const receipt of receipts.values())
    if (!receipt.result)
      record({
        ...receipt,
        result: {
          status: "uncertain",
          exitCode: null,
          stdout: "",
          stderr:
            "The Mac host restarted while this command ran. Inspect its effects; it will not be run again automatically.",
        },
      });

  const active = new Map<string, { child: ChildProcess; stopped: boolean }>();
  const writing = new Map<string, Promise<unknown>>();
  /**
   * Writes a file if it is still at `expected` (its SHA-256; null: it must not exist yet;
   * undefined: overwrite). Writes to one path go one at a time, so a stale save cannot slip
   * in between the comparison and the write.
   */
  const compareAndWrite = (
    path: string,
    expected: string | null | undefined,
    content: string | Buffer,
  ) => {
    const done = (writing.get(path) ?? Promise.resolve()).then(async () => {
      if (expected !== undefined) {
        const current = await readFile(path).catch(() => undefined);
        if ((current === undefined ? null : revisionOf(current)) !== expected)
          throw new Refusal(409, "Revision conflict: the file changed since it was read");
      }
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, content);
    });
    const settled = done.catch(() => undefined);
    writing.set(path, settled);
    void settled.then(() => {
      if (writing.get(path) === settled) writing.delete(path);
    });
    return done;
  };
  let spawned = 0;
  const scopeKey = (scope: Scope) => `${scope.businessId}/${scope.employeeId}`;
  const stopGroup = (child: ChildProcess, signal: NodeJS.Signals) => {
    try {
      process.kill(-child.pid!, signal);
    } catch {}
  };

  async function run(input: Record<string, unknown>): Promise<CommandResult> {
    const scope = scopeOf(input.scope);
    const { operationId, command, timeoutMs, maxBytes } = input as {
      operationId: string;
      command: string;
      timeoutMs: number;
      maxBytes: number;
    };
    if (
      typeof operationId !== "string" ||
      !operationId ||
      typeof command !== "string" ||
      !withinCommandLimits(command, timeoutMs, maxBytes)
    )
      throw new Refusal(400, "Invalid command limits");
    const key = `${scopeKey(scope)}/${operationId}`;
    const fingerprint = createHash("sha256")
      .update(JSON.stringify({ command, timeoutMs, maxBytes }))
      .digest("hex");
    const previous = receipts.get(key);
    if (previous) {
      if (previous.fingerprint !== fingerprint)
        throw new Refusal(409, "Operation identity reused for a different command");
      return (
        previous.result ?? {
          status: "uncertain",
          exitCode: null,
          stdout: "",
          stderr: "The command is still running or was interrupted; it will not be run again.",
        }
      );
    }
    if (active.has(scopeKey(scope))) throw new Refusal(409, "Workspace is busy");
    const cwd = join(options.work, scope.businessId);
    // No await between the checks above and recording the receipt: a retried operation arriving
    // meanwhile must find it, not start the command a second time.
    mkdirSync(cwd, { recursive: true });
    record({ key, fingerprint });
    spawned++;
    const child = spawn(options.shell ?? "/bin/zsh", ["-lc", command], {
      cwd,
      env: options.env ?? process.env,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const job = { child, stopped: false };
    active.set(scopeKey(scope), job);
    let limited = false;
    const capture = (stream: Readable) => {
      const chunks: Buffer[] = [];
      let size = 0;
      stream.on("data", (chunk: Buffer) => {
        const room = maxBytes - size;
        if (room > 0) chunks.push(chunk.subarray(0, room));
        size += chunk.length;
        if (size > maxBytes && !limited) {
          limited = true;
          stopGroup(child, "SIGKILL");
        }
      });
      return () => Buffer.concat(chunks).toString("utf8");
    };
    const stdout = capture(child.stdout!);
    const stderr = capture(child.stderr!);
    const deadline = setTimeout(() => {
      limited = true;
      stopGroup(child, "SIGTERM");
      setTimeout(() => stopGroup(child, "SIGKILL"), 2_000).unref();
    }, timeoutMs);
    const exitCode = await new Promise<number | null>((resolve) => {
      child.on("error", () => resolve(null));
      child.on("close", (code) => resolve(code));
    });
    clearTimeout(deadline);
    active.delete(scopeKey(scope));
    const result: CommandResult = {
      status: job.stopped ? "cancelled" : limited ? "limited" : "completed",
      exitCode,
      stdout: stdout(),
      stderr: stderr(),
    };
    record({ key, fingerprint, result });
    return result;
  }

  async function route(request: IncomingMessage, response: ServerResponse) {
    const offered = sha256(request.headers.authorization ?? "");
    if (!timingSafeEqual(offered, sha256(`Bearer ${options.token}`)))
      throw new Refusal(401, "Unauthorized");
    const url = new URL(request.url ?? "/", "http://host");
    const json = (value: unknown) => {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(value));
    };
    const streamer = options.routes?.find(
      (routes) => routes.stream && url.pathname.startsWith(routes.prefix),
    );
    if (streamer && request.method === "GET") {
      const closed = new Promise<void>((resolve) => response.on("close", () => resolve()));
      // Headers go out with the first bytes, so a refusal before then is an ordinary error.
      const begin = () => {
        if (response.headersSent) return;
        response.writeHead(200, {
          "content-type": "application/octet-stream",
          "cache-control": "no-store",
        });
      };
      const write = (chunk: Uint8Array | null) => {
        begin();
        if (chunk === null) response.end();
        else response.write(chunk);
      };
      const answered = streamer.stream!(url.pathname, url, write, closed);
      if (answered === false) throw new Refusal(404, "Not found");
      if (answered === true) {
        begin();
        response.end();
      }
      return;
    }
    if (url.pathname === "/file" && request.method === "GET") {
      const path = await confined(
        absolute(url.searchParams.get("path")),
        url.searchParams.get("within"),
      );
      const maximum = Math.min(Number(url.searchParams.get("max") ?? fileBytes), fileBytes);
      const info = await stat(path).catch(() => undefined);
      if (!info?.isFile()) throw new Refusal(404, "File is unavailable");
      if (info.size > maximum) throw new Refusal(413, "File is larger than allowed");
      response.writeHead(200, { "content-type": "application/octet-stream" });
      response.end(await readFile(path));
      return;
    }
    if (url.pathname === "/file" && request.method === "PUT") {
      const path = await confined(
        absolute(url.searchParams.get("path")),
        url.searchParams.get("within"),
      );
      const bytes = await body(request, fileBytes);
      const expected = url.searchParams.get("expected");
      await compareAndWrite(
        path,
        expected === null ? undefined : expected === "none" ? null : expected,
        bytes,
      );
      return json({ path, revision: revisionOf(bytes) });
    }
    if (request.method !== "POST") throw new Refusal(404, "Not found");
    const input = JSON.parse((await body(request, 4 * textBytes)).toString("utf8")) as Record<
      string,
      unknown
    >;
    const owner = options.routes?.find((routes) => url.pathname.startsWith(routes.prefix));
    if (owner) return json(await owner.handle(url.pathname, input));
    switch (url.pathname) {
      case "/run":
        return json(await run(input));
      case "/cancel": {
        const job = active.get(scopeKey(scopeOf(input.scope)));
        if (job) {
          job.stopped = true;
          stopGroup(job.child, "SIGKILL");
        }
        return json({ stopped: true });
      }
      case "/read": {
        const path = await confined(absolute(input.path), input.within);
        const maximum = Math.min(Number(input.maximum ?? inlineBytes) || inlineBytes, textBytes);
        const info = await stat(path).catch(() => undefined);
        if (!info?.isFile()) throw new Refusal(404, "File is unavailable");
        if (info.size > maximum)
          throw new Refusal(
            413,
            `File exceeds ${Math.round(maximum / 1000)} KB; use run to inspect it`,
          );
        const bytes = await readFile(path);
        return json({
          path,
          content: new TextDecoder().decode(bytes),
          revision: revisionOf(bytes),
        });
      }
      case "/write": {
        const path = await confined(absolute(input.path), input.within);
        const content = typeof input.content === "string" ? input.content : "";
        if (Buffer.byteLength(content) > textBytes)
          throw new Refusal(413, "File exceeds the text write limit");
        await compareAndWrite(path, input.expectedRevision as string | null | undefined, content);
        return json({ path, revision: revisionOf(content) });
      }
      case "/print": {
        const source = absolute(input.source);
        const target = absolute(input.target);
        if (!/\.html?$/i.test(source) || !/\.pdf$/i.test(target))
          throw new Refusal(400, "Print an .html file to a .pdf file");
        if (!(await stat(source).catch(() => undefined))?.isFile())
          throw new Refusal(404, "File is unavailable");
        const chrome =
          options.chrome ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
        if (!existsSync(chrome))
          throw new Refusal(503, "Google Chrome is not installed on this Mac");
        await mkdir(dirname(target), { recursive: true });
        // A throwaway profile: printing never touches the owner's or a business's browser profile.
        const profile = join(options.data, `print-${randomUUID()}`);
        const exitCode = await new Promise<number | null>((resolve) => {
          const child = spawn(
            chrome,
            [
              "--headless",
              "--disable-gpu",
              "--no-pdf-header-footer",
              `--user-data-dir=${profile}`,
              `--print-to-pdf=${target}`,
              pathToFileURL(source).href,
            ],
            { stdio: "ignore" },
          );
          const timer = setTimeout(() => child.kill("SIGKILL"), 60_000);
          // A failed spawn is reported as a failed print rather than ending the host.
          child.on("error", () => {
            clearTimeout(timer);
            resolve(null);
          });
          child.on("close", (code) => {
            clearTimeout(timer);
            resolve(code);
          });
        });
        await rm(profile, { recursive: true, force: true });
        const printed = await stat(target).catch(() => undefined);
        if (exitCode !== 0 || !printed) throw new Refusal(500, "Chrome could not print that file");
        return json({ path: target, size: printed.size });
      }
      case "/list": {
        const path = await confined(absolute(input.path), input.within);
        const entries = await readdir(path, { withFileTypes: true }).catch(() => {
          throw new Refusal(404, "Folder is unavailable");
        });
        const listed = await Promise.all(
          entries.map(async (entry) => {
            const child = join(path, entry.name);
            const kind = entry.isDirectory() ? "directory" : entry.isFile() ? "file" : "other";
            const size =
              kind === "file" ? ((await stat(child).catch(() => undefined))?.size ?? 0) : 0;
            return { name: entry.name, path: child, kind, size };
          }),
        );
        return json(
          listed.sort((a, b) =>
            a.kind === b.kind ? a.name.localeCompare(b.name) : a.kind === "directory" ? -1 : 1,
          ),
        );
      }
      case "/skills":
        return json(
          await listWorkspaceSkills(
            skillFiles as unknown as Parameters<typeof listWorkspaceSkills>[0],
            options.skills,
          ),
        );
      default:
        throw new Refusal(404, "Not found");
    }
  }

  const server = createServer((request, response) => {
    route(request, response).catch((error: unknown) => {
      const status = error instanceof Refusal ? error.status : 500;
      response.writeHead(status, { "content-type": "text/plain" });
      response.end(error instanceof Error ? error.message : "Host error");
    });
  });
  await new Promise<void>((resolve) => server.listen(options.port, "127.0.0.1", resolve));
  const address = server.address();
  return {
    port: typeof address === "object" && address ? address.port : options.port,
    spawned: () => spawned,
    close: () =>
      Promise.all([
        new Promise<void>((resolve) => {
          for (const job of active.values()) stopGroup(job.child, "SIGKILL");
          server.close(() => resolve());
          server.closeAllConnections();
        }),
        ...(options.routes ?? []).map((routes) => routes.close()),
      ]).then(() => undefined),
  };
}
