/** Git worktrees for coding sessions, through the owner's own `git`. */
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, realpath } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
const patchBytes = 1_000_000;

export async function git(cwd: string, ...args: string[]) {
  const { stdout } = await exec("git", ["-C", cwd, ...args], { maxBuffer: 8 * patchBytes });
  return stdout.trim();
}

/** A new repository's name: a folder name, nothing that walks out of it. */
const repositoryName = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

/**
 * The repository a coding session works on: an existing one at an absolute path, or a new empty
 * one under the business folder with a first commit to branch from.
 */
export async function repository(business: string, target: { path: string } | { create: string }) {
  if ("path" in target) return git(target.path, "rev-parse", "--show-toplevel");
  if (!repositoryName.test(target.create) || target.create.includes(".."))
    throw new Error("Name a new repository with letters, digits, dots, dashes or underscores");
  const path = join(business, "repos", target.create);
  if (existsSync(join(path, ".git"))) return path;
  await mkdir(path, { recursive: true });
  await git(path, "init", "--initial-branch=main");
  await git(path, "commit", "--allow-empty", "--message", "Start");
  return path;
}

/** Creates the coding session's worktree on its own branch from the repository's current head. */
export async function createWorktree(business: string, repositoryPath: string, id: string) {
  const worktree = join(business, "worktrees", id);
  const branch = `devys/${id.slice(0, 12)}`;
  // Made before a crash and not yet recorded: nothing has been committed on it yet.
  if (existsSync(worktree))
    return { worktree, branch, baseCommit: await git(worktree, "rev-parse", "HEAD") };
  const baseCommit = await git(repositoryPath, "rev-parse", "HEAD");
  await mkdir(join(business, "worktrees"), { recursive: true });
  await git(repositoryPath, "worktree", "add", "-b", branch, worktree, baseCommit);
  return { worktree, branch, baseCommit };
}

/** What changed against the base, including uncommitted and new files. */
export async function diffStat(worktree: string, base: string) {
  const [tracked, untracked] = await Promise.all([
    git(worktree, "-c", "core.quotepath=off", "diff", "--stat", base),
    git(worktree, "ls-files", "--others", "--exclude-standard"),
  ]);
  return [
    tracked,
    ...untracked
      .split("\n")
      .filter(Boolean)
      .map((file) => ` ${file} (new)`),
  ]
    .filter(Boolean)
    .join("\n");
}

/** Commits everything in the worktree as the owner; with nothing new, the head stays. */
export async function commitAll(worktree: string, message: string) {
  await git(worktree, "add", "--all");
  if (await git(worktree, "status", "--porcelain"))
    await git(worktree, "commit", "--message", message);
  return git(worktree, "rev-parse", "HEAD");
}

/** The committed change against the base, cut off at a megabyte. */
export async function patch(worktree: string, base: string) {
  const full = await git(worktree, "diff", `${base}..HEAD`);
  return full.length > patchBytes ? `${full.slice(0, patchBytes)}\n[patch truncated]` : full;
}

/** One changed file of a worktree against its base. */
export interface ChangedFile {
  path: string;
  status: "added" | "modified" | "deleted" | "renamed";
  added: number;
  removed: number;
}

/**
 * The worktree's changes against its base as a unified patch, uncommitted and new files
 * included, with a line count per file. The patch is cut off at a megabyte.
 */
export async function workingDiff(worktree: string, base: string) {
  const [numstat, names, untracked] = await Promise.all([
    git(worktree, "-c", "core.quotepath=off", "diff", "--numstat", base),
    git(worktree, "-c", "core.quotepath=off", "diff", "--name-status", base),
    git(worktree, "-c", "core.quotepath=off", "ls-files", "--others", "--exclude-standard"),
  ]);
  const status = new Map(
    names
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const [code, ...paths] = line.split("\t");
        const kind = code!.startsWith("A")
          ? "added"
          : code!.startsWith("D")
            ? "deleted"
            : code!.startsWith("R")
              ? "renamed"
              : "modified";
        return [paths.at(-1)!, kind] as const;
      }),
  );
  const files: ChangedFile[] = numstat
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [added, removed, ...rest] = line.split("\t");
      const path = rest
        .join("\t")
        .replace(/^.*=> /, "")
        .replace(/[{}]/g, "");
      return {
        path,
        status: status.get(path) ?? "modified",
        added: Number(added) || 0,
        removed: Number(removed) || 0,
      };
    });
  let text = await git(worktree, "diff", base);
  for (const path of untracked.split("\n").filter(Boolean)) {
    // `--no-index` exits 1 when the files differ, which is always here.
    const patchOfNew = await exec(
      "git",
      ["-C", worktree, "diff", "--no-index", "--", "/dev/null", path],
      {
        maxBuffer: 8 * patchBytes,
      },
    ).then(
      (result) => result.stdout,
      (error: { stdout?: string }) => error.stdout ?? "",
    );
    text += `${text ? "\n" : ""}${patchOfNew.trimEnd()}`;
    files.push({
      path,
      status: "added",
      added: patchOfNew.split("\n").filter((l) => l.startsWith("+") && !l.startsWith("+++")).length,
      removed: 0,
    });
  }
  return {
    files,
    patch: text.length > patchBytes ? `${text.slice(0, patchBytes)}\n[patch truncated]` : text,
  };
}

/**
 * Stops whatever still runs inside a worktree: commands a coding agent started keep going
 * after its turn is interrupted, or after the host itself died. A worktree belongs to one
 * coding session, so its directory names exactly that work.
 */
export async function stopProcessesIn(worktree: string, spared: readonly string[] = []) {
  const { stdout } = await exec("lsof", ["-d", "cwd", "-F", "pn"], {
    maxBuffer: 8 * patchBytes,
  }).catch((error: { stdout?: string }) => ({ stdout: error.stdout ?? "" }));
  // lsof reports real paths (/private/var/… for /var/…), so match the worktree's real path.
  const root = await realpath(worktree).catch(() => worktree);
  const inside: number[] = [];
  let pid = 0;
  for (const line of stdout.split("\n")) {
    if (line.startsWith("p")) pid = Number(line.slice(1));
    else if (line.startsWith("n") && pid !== process.pid) {
      const cwd = line.slice(1);
      if (cwd === root || cwd.startsWith(`${root}/`)) inside.push(pid);
    }
  }
  // The owner's own terminals in the worktree are spared, with everything running in them.
  const ttys = new Map<number, string>();
  if (inside.length && spared.length) {
    const { stdout: listed } = await exec("ps", ["-o", "pid=,tty=", "-p", inside.join(",")]).catch(
      () => ({ stdout: "" }),
    );
    for (const line of listed.split("\n")) {
      const [id, tty] = line.trim().split(/\s+/);
      if (id && tty) ttys.set(Number(id), tty);
    }
  }
  const stopped: number[] = [];
  for (const candidate of inside) {
    if (spared.includes(ttys.get(candidate) ?? "")) continue;
    try {
      process.kill(candidate, "SIGTERM");
      stopped.push(candidate);
    } catch {}
  }
  return stopped;
}
