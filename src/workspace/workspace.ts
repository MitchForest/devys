import { DurableObject } from "cloudflare:workers";
import { DirectoryBackup, Files } from "@cloudflare/sandbox";
import type { DirectoryBackupRecord } from "@cloudflare/sandbox";
import { Schema } from "effect";
import { FilePath } from "../protocol/capability.ts";
import { captureOutput, readBounded, sha256, sha256Bytes } from "../protocol/bytes.ts";
import { withinCommandLimits } from "../protocol/limits.ts";
import { packageHosts } from "../egress/contract.ts";

import {
  revisionConflict,
  type Checkpoint,
  type CommandResult,
  type FileEntry,
  type WorkspacePort,
} from "./contract.ts";
import { listWorkspaceSkills } from "./skills.ts";

interface CommandRecord {
  fingerprint: string;
  result?: CommandResult;
}

/** The sandbox keeps every file path under /workspace. */
function sandboxPath(path: string) {
  Schema.decodeUnknownSync(FilePath)(path);
  if (path !== "/workspace" && !path.startsWith("/workspace/"))
    throw new Error("Workspace paths must be under /workspace");
}

/** A private workspace. Only trusted Worker/agent bindings may reach this class. */
export class Workspace extends DurableObject<{ FILES: R2Bucket }> implements WorkspacePort {
  private active = false;
  private stopped = false;
  private readonly boot = crypto.randomUUID();

  private async reconcileInterruptedCommand() {
    const lease = await this.ctx.storage.get<{ key: string; boot: string }>("active-command");
    if (!lease) return;
    const record = await this.ctx.storage.get<CommandRecord>(lease.key);
    if (record && !record.result) {
      if (this.ctx.container?.running) await this.ctx.container.destroy();
      await this.ctx.storage.put(lease.key, {
        ...record,
        result: {
          status: "uncertain",
          exitCode: null,
          stdout: "",
          stderr:
            "The interrupted command was stopped. Files will restart from the latest checkpoint; unsaved workspace changes may be lost. The command will not be replayed automatically.",
        } satisfies CommandResult,
      });
    }
    await this.ctx.storage.delete("active-command");
  }

  private async container(): Promise<Container> {
    const container = this.ctx.container;
    if (!container) throw new Error("Workspace container is not configured");
    if (!this.active) await this.reconcileInterruptedCommand();
    if (!container.running) {
      const snapshot = await this.ctx.storage.get<string>("snapshot");
      const image = Object.values(container.images)[0];
      if (!snapshot && !image) throw new Error("Workspace image is not configured");
      container.start({
        ...(snapshot ? { containerSnapshot: { id: snapshot } } : { image: image! }),
        enableInternet: false,
        entrypoint: ["sleep", "infinity"],
      });
      const egress = (this.ctx.exports as unknown as { PublicEgress: Fetcher }).PublicEgress;
      for (const host of packageHosts) await container.interceptOutboundHttps(host, egress);
      await container.setInactivityTimeout(15 * 60_000);
    }
    return container;
  }

  async run(
    operationId: string,
    command: string,
    timeoutMs: number,
    maxBytes: number,
  ): Promise<CommandResult> {
    if (!withinCommandLimits(command, timeoutMs, maxBytes))
      throw new Error("Invalid command limits");
    const key = `command:${operationId}`;
    const fingerprint = await sha256(JSON.stringify({ command, timeoutMs, maxBytes }));
    const previous = await this.ctx.storage.get<CommandRecord>(key);
    if (previous) {
      if (previous.fingerprint !== fingerprint)
        throw new Error("Operation identity reused for a different command");
      if (!previous.result && !this.active) await this.reconcileInterruptedCommand();
      return (
        (await this.ctx.storage.get<CommandRecord>(key))?.result ?? {
          status: "uncertain",
          exitCode: null,
          stdout: "",
          stderr:
            "The command was admitted before interruption. It will not be run again automatically.",
        }
      );
    }
    if (this.active) throw new Error("Workspace is busy");
    this.active = true;
    this.stopped = false;
    try {
      await this.reconcileInterruptedCommand();
      await this.ctx.storage.put({
        [key]: { fingerprint },
        "active-command": { key, boot: this.boot },
      });
      const container = await this.container();
      if (this.stopped) {
        const result: CommandResult = {
          status: "cancelled",
          exitCode: null,
          stdout: "",
          stderr: "Stopped before execution",
        };
        await this.ctx.storage.put(key, { fingerprint, result });
        return result;
      }
      // GNU timeout owns process-group termination even if the Worker disappears.
      const process = await container.exec(
        [
          "timeout",
          "--signal=TERM",
          "--kill-after=2s",
          `${Math.ceil(timeoutMs / 1000)}s`,
          "bash",
          "-lc",
          command,
        ],
        { cwd: "/workspace", signal: AbortSignal.timeout(timeoutMs + 2_000) },
      );
      let result: CommandResult;
      const stdout = captureOutput(process.stdout, maxBytes);
      const stderr = captureOutput(process.stderr, maxBytes);
      let deadline: ReturnType<typeof setTimeout> | undefined;
      try {
        const [, , exitCode] = await Promise.race([
          Promise.all([stdout.done, stderr.done, process.exitCode]),
          new Promise<never>((_resolve, reject) => {
            deadline = setTimeout(
              () => reject(new Error("Command deadline exceeded")),
              timeoutMs + 2_000,
            );
          }),
        ]);
        result = {
          status: this.stopped
            ? "cancelled"
            : [124, 137].includes(exitCode)
              ? "limited"
              : "completed",
          exitCode,
          stdout: stdout.text(),
          stderr: stderr.text(),
        };
      } catch {
        // Destroy the whole sandbox so descendants cannot outlive a claimed stop.
        await container.destroy();
        await Promise.allSettled([stdout.done, stderr.done]);
        result = {
          status: this.stopped ? "cancelled" : "limited",
          exitCode: null,
          stdout: stdout.text(),
          stderr: `${stderr.text()}\nExecution stopped; output exceeded its budget or the process stream failed. Unsaved workspace changes may be lost.`,
        };
      } finally {
        if (deadline !== undefined) clearTimeout(deadline);
      }
      await this.ctx.storage.put<CommandRecord>(key, { fingerprint, result });
      await this.ctx.storage.delete("active-command");
      return result;
    } finally {
      this.active = false;
    }
  }

  async cancel(): Promise<{ stopped: boolean }> {
    this.stopped = true;
    const container = this.ctx.container;
    if (container?.running) await container.destroy();
    return { stopped: true };
  }

  async write(
    path: string,
    content: string,
    expectedRevision?: string | null,
  ): Promise<{ path: string; revision: string }> {
    sandboxPath(path);
    if (new TextEncoder().encode(content).byteLength > 1_000_000)
      throw new Error("File exceeds the text write limit");
    if (this.active) throw new Error("Workspace is busy");
    const files = new Files(await this.container());
    // The Durable Object handles one call at a time, so compare and write are not interleaved.
    if (expectedRevision !== undefined) {
      const current = await files.readFile(path);
      const revision = current.ok ? await sha256Bytes(await current.arrayBuffer()) : null;
      if (revision !== expectedRevision)
        throw new Error(`${revisionConflict}: the file changed since it was read`);
    }
    await files.writeFile(path, content);
    return { path, revision: await sha256(content) };
  }

  async read(
    path: string,
    maximum = 64_000,
  ): Promise<{ path: string; content: string; revision: string }> {
    sandboxPath(path);
    const response = await new Files(await this.container()).readFile(path);
    if (!response.ok) throw new Error("Workspace file is unavailable");
    const bytes = await readBounded(response.body, Math.min(maximum, 1_000_000));
    return { path, content: new TextDecoder().decode(bytes), revision: await sha256Bytes(bytes) };
  }

  async printPdf(): Promise<{ path: string; size: number }> {
    throw new Error("Printing to PDF runs on the owner's Mac (local mode) for now.");
  }

  async list(path: string): Promise<FileEntry[]> {
    sandboxPath(path);
    const files = new Files(await this.container());
    const entries = await files.readDirectory(path);
    const listed = await Promise.all(
      entries.map(async (entry) => {
        const child = `${path.replace(/\/$/, "")}/${entry.name}`;
        const kind: FileEntry["kind"] =
          entry.type === "directory" ? "directory" : entry.type === "file" ? "file" : "other";
        const size = kind === "file" ? Number((await files.lstat(child)).size) : 0;
        return { name: entry.name, path: child, kind, size };
      }),
    );
    return listed.sort((a, b) =>
      a.kind === b.kind ? a.name.localeCompare(b.name) : a.kind === "directory" ? -1 : 1,
    );
  }

  async listSkills() {
    if (this.active) throw new Error("Workspace is busy");
    return listWorkspaceSkills(new Files(await this.container()));
  }

  async importFile(
    path: string,
    objectKey: string,
    expectedRevision?: string | null,
  ): Promise<void> {
    sandboxPath(path);
    if (this.active) throw new Error("Workspace is busy");
    const object = await this.env.FILES.get(objectKey);
    if (!object || object.size > 20_000_000) throw new Error("Input file unavailable or oversized");
    const files = new Files(await this.container());
    if (expectedRevision !== undefined) {
      const current = await files.readFile(path);
      const revision = current.ok ? await sha256Bytes(await current.arrayBuffer()) : null;
      if (revision !== expectedRevision)
        throw new Error(`${revisionConflict}: the file changed since it was read`);
    }
    await files.writeFile(path, object.body);
  }

  async exportFile(path: string, objectKey: string, maximum: number): Promise<{ size: number }> {
    sandboxPath(path);
    if (this.active) throw new Error("Workspace is busy");
    const existing = await this.env.FILES.head(objectKey);
    if (existing) return { size: existing.size };
    const response = await new Files(await this.container()).readFile(path);
    if (!response.ok) throw new Error("Workspace file is unavailable");
    const bytes = await readBounded(response.body, Math.min(maximum, 20_000_000));
    await this.env.FILES.put(objectKey, bytes);
    return { size: bytes.byteLength };
  }

  async checkpoint(): Promise<Checkpoint> {
    if (this.active) throw new Error("Cannot checkpoint a running command");
    if (!this.ctx.container?.running)
      return (
        (await this.ctx.storage.get<Checkpoint>("checkpoint")) ?? {
          kind: "snapshot",
          snapshotId: "",
          bytes: 0,
        }
      );
    const container = await this.container();
    const backup = await this.backups(container).backup({
      dir: "/workspace",
      name: "workspace",
      signal: AbortSignal.timeout(120_000),
    });
    await this.ctx.storage.put("backup", backup);
    const snapshot = await container.snapshotContainer({ name: "workspace" });
    await this.ctx.storage.put("snapshot", snapshot.id);
    const checkpoint: Checkpoint = {
      kind: "snapshot",
      snapshotId: snapshot.id,
      bytes: snapshot.size,
    };
    await this.ctx.storage.put("checkpoint", checkpoint);
    return checkpoint;
  }

  private backups(container: Container) {
    const exports = this.ctx.exports as unknown as {
      DirectoryBackupGateway: ConstructorParameters<typeof DirectoryBackup>[1];
    };
    return new DirectoryBackup(container, exports.DirectoryBackupGateway, {
      binding: "FILES",
      prefix: `${this.ctx.id.name}/workspace-backups/`,
    });
  }

  async restoreBackup(): Promise<{ restored: boolean }> {
    if (this.active) throw new Error("Cannot restore while a command is active");
    const backup = await this.ctx.storage.get<DirectoryBackupRecord>("backup");
    if (!backup) throw new Error("No workspace backup is available");
    await this.ctx.container?.destroy();
    await this.ctx.storage.delete("snapshot");
    await this.backups(await this.container()).restore(backup, {
      signal: AbortSignal.timeout(120_000),
    });
    return { restored: true };
  }
}
