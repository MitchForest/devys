import type { Scope } from "../identity/contract.ts";

/** Runner port. Adapters keep isolation, egress and receipts behind this contract. */
export interface CommandResult {
  status: "completed" | "uncertain" | "cancelled" | "limited";
  exitCode: number | null;
  stdout: string;
  stderr: string;
}

export interface WorkspaceSkill {
  name: string;
  description: string;
  path: string;
}

export interface SkillCatalog {
  skills: WorkspaceSkill[];
  warnings: string[];
}

/** One entry of a folder. */
export interface FileEntry {
  name: string;
  path: string;
  kind: "file" | "directory" | "repository" | "other";
  size: number;
}

/** A text file's revision: the SHA-256 of its UTF-8 bytes, in hex. */
export const revisionConflict = "Revision conflict";

/** What a checkpoint made durable: a sandbox snapshot, or files already on a real disk. */
export type Checkpoint =
  | { kind: "snapshot"; snapshotId: string; bytes: number }
  | { kind: "durable" };

export interface WorkspacePort {
  /** The business's own skills: its skills folder (local mode) or `/workspace/skills` (cloud). */
  skills(): Promise<SkillCatalog>;
  run(
    operationId: string,
    command: string,
    timeoutMs: number,
    maxBytes: number,
  ): Promise<CommandResult>;
  cancel(): Promise<{ stopped: boolean }>;
  /**
   * Writes text. Given `expectedRevision`, the write happens only if the file still has that
   * revision (null: only if it does not exist yet); otherwise it fails with a message starting
   * "Revision conflict".
   */
  write(
    path: string,
    content: string,
    expectedRevision?: string | null,
  ): Promise<{ path: string; revision: string }>;
  /** Reads text up to `maximum` bytes (64 KB unless asked; at most 1 MB). */
  read(
    path: string,
    maximum?: number,
  ): Promise<{ path: string; content: string; revision: string }>;
  /** The immediate entries of a folder. */
  list(path: string): Promise<FileEntry[]>;
  /** Prints an HTML file to a PDF with a real browser. */
  printPdf(source: string, target: string): Promise<{ path: string; size: number }>;
  /**
   * Copies bytes from R2 into a file. Given `expectedRevision` (the SHA-256 of the file's bytes;
   * null: only if new), it fails with "Revision conflict" when the file has changed.
   */
  importFile(path: string, objectKey: string, expectedRevision?: string | null): Promise<void>;
  exportFile(path: string, objectKey: string, maximum: number): Promise<{ size: number }>;
  checkpoint(): Promise<Checkpoint>;
}

/** The runner for one employee, chosen by application wiring from the deployment mode. */
export type Runner = (scope: Scope) => WorkspacePort;
