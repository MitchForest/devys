import type { Scope } from "../identity/contract.ts";
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
}

const inputBytes = 20_000_000;

/**
 * The runner on the trusted Mac host (local mode). The host process owns commands, files
 * and receipts; this side only speaks to it and moves bytes between R2 and the Mac, so
 * the host never touches R2.
 */
export function hostRunner(host: HostConnection, scope: Scope): WorkspacePort {
  async function call(path: string, init: RequestInit = {}) {
    let response: Response;
    try {
      response = await fetch(`${host.url}${path}`, {
        ...init,
        headers: { authorization: `Bearer ${host.token}`, ...init.headers },
      });
    } catch {
      throw new Error("The Mac host is not running, so files and commands are unavailable.");
    }
    if (!response.ok)
      throw new Error((await response.text()) || `Mac host error ${response.status}`);
    return response;
  }
  const post = async <T>(path: string, input: Record<string, unknown> = {}) =>
    (await (
      await call(path, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ scope, within: host.within, ...input }),
      })
    ).json()) as T;
  const file = (path: string, maximum?: number) =>
    `/file?path=${encodeURIComponent(path)}${maximum ? `&max=${maximum}` : ""}${host.within ? `&within=${encodeURIComponent(host.within)}` : ""}`;

  return {
    skills: () => post<SkillCatalog>("/skills"),
    run: (operationId, command, timeoutMs, maxBytes) =>
      post<CommandResult>("/run", { operationId, command, timeoutMs, maxBytes }),
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
