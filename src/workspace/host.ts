import type { Scope } from "../identity/contract.ts";
import type { Sealed } from "../vault/contract.ts";
import { hostCallMs, hostFailure, hostFetch, hostPost } from "../protocol/host.ts";
import type {
  Checkpoint,
  CommandResult,
  FileEntry,
  SkillCatalog,
  WorkspacePort,
} from "./contract.ts";

/** Where the Mac host listens (loopback), its token, and the bucket file transfers use. */
export interface HostConnection {
  url: string;
  token: string;
  files: Pick<R2Bucket, "get" | "put" | "head">;
  /** A folder file access must stay inside, symbolic links followed (the owner's file views). */
  within?: string;
  /** The business's named secrets, sealed, for the host to put in one command (the vault). */
  sealed?: (businessId: string, names: readonly string[]) => Promise<Sealed[]>;
}

const inputBytes = 20_000_000;

/**
 * The runner on the trusted Mac host (local mode). The host process owns commands, files
 * and receipts; this side only speaks to it and moves bytes between R2 and the Mac, so
 * the host never touches R2.
 */
export function hostRunner(host: HostConnection, scope: Scope): WorkspacePort {
  async function call(path: string, init: RequestInit = {}, ms = hostCallMs) {
    const response = await hostFetch(
      `${host.url}${path}`,
      { ...init, headers: { authorization: `Bearer ${host.token}`, ...init.headers } },
      ms,
      "files and commands are",
    );
    if (!response.ok) throw await hostFailure(response);
    return response;
  }
  const post = <T>(path: string, input: Record<string, unknown> = {}, ms?: number) =>
    hostPost<T>(host, path, { scope, within: host.within, ...input }, "files and commands are", ms);
  const file = (path: string, maximum?: number) =>
    `/file?business=${encodeURIComponent(scope.businessId)}&path=${encodeURIComponent(path)}${maximum ? `&max=${maximum}` : ""}${host.within ? `&within=${encodeURIComponent(host.within)}` : ""}`;

  return {
    skills: () => post<SkillCatalog>("/skills"),
    async run(operationId, command, timeoutMs, maxBytes, secrets = []) {
      if (secrets.length && !host.sealed) throw new Error("Secrets are not available here");
      // The command's own limit, plus time for the host to stop it and answer.
      return post<CommandResult>(
        "/run",
        {
          operationId,
          command,
          timeoutMs,
          maxBytes,
          ...(secrets.length ? { secrets: await host.sealed!(scope.businessId, secrets) } : {}),
        },
        timeoutMs + 30_000,
      );
    },
    cancel: () => post<{ stopped: boolean }>("/cancel"),
    write: (path, content, expectedRevision) =>
      post<{ path: string; revision: string }>("/write", {
        path,
        content,
        ...(expectedRevision !== undefined ? { expectedRevision } : {}),
      }),
    read: (path, maximum) =>
      post<{ path: string; content: string; revision: string }>("/read", { path, maximum }),
    list: (path) => post<FileEntry[]>("/list", { path }),
    printPdf: (source, target) =>
      post<{ path: string; size: number }>("/print", { source, target }),
    async importFile(path, objectKey, expectedRevision) {
      const object = await host.files.get(objectKey);
      if (!object || object.size > inputBytes)
        throw new Error("Input file unavailable or oversized");
      const query = expectedRevision === undefined ? "" : `&expected=${expectedRevision ?? "none"}`;
      await call(`${file(path)}${query}`, { method: "PUT", body: await object.arrayBuffer() });
    },
    async exportFile(path, objectKey, maximum) {
      const existing = await host.files.head(objectKey);
      if (existing) return { size: existing.size };
      const bytes = await (await call(file(path, Math.min(maximum, inputBytes)))).arrayBuffer();
      await host.files.put(objectKey, bytes);
      return { size: bytes.byteLength };
    },
    // Files on the Mac are already on its disk; there is no snapshot to take.
    checkpoint: async (): Promise<Checkpoint> => ({ kind: "durable" }),
  };
}
