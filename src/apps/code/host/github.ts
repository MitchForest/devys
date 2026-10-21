/**
 * The business's GitHub repositories, through the owner's own `git` and `gh` logins on the trusted
 * Mac (.docs/CODING_AGENTS.md). Cloning reuses a folder only when its origin is the same
 * repository; publishing pushes an accepted commit to the coding session's branch and opens one pull
 * request for it, finding the existing one first so a retry never opens a second.
 */
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import type { Published, PublishRequest } from "../contract.ts";
import { git } from "./worktree.ts";

const exec = promisify(execFile);

/** `owner/name` as GitHub spells repositories. */
export const githubName = /^[A-Za-z0-9-]{1,39}\/[A-Za-z0-9._-]{1,100}$/;

/** The `owner/name` an origin URL points at on github.com, if it does. */
export function githubRepository(url: string) {
  return /github\.com[:/]([A-Za-z0-9-]+\/[A-Za-z0-9._-]+?)(?:\.git)?\/?$/i.exec(url)?.[1];
}

const same = (a: string | undefined, b: string) => a?.toLowerCase() === b.toLowerCase();

// The configured URL, not one rewritten by `insteadOf`.
const origin = (cwd: string) => git(cwd, "config", "--get", "remote.origin.url").catch(() => "");

/** Clones `owner/name` into the business folder, or reuses the clone already there. */
export async function cloneRepository(business: string, name: string) {
  if (!githubName.test(name) || name.includes(".."))
    throw new Error("Name a GitHub repository as owner/name");
  const path = join(business, "repos", name.split("/")[1]!);
  if (existsSync(join(path, ".git"))) {
    const current = await origin(path);
    if (!same(githubRepository(current), name))
      throw new Error(`${path} already holds ${current || "a repository with no origin"}`);
    return path;
  }
  await mkdir(join(business, "repos"), { recursive: true });
  await git(join(business, "repos"), "clone", `https://github.com/${name}.git`, path);
  return path;
}

/** Pushes the accepted commit to its branch and opens (or finds) the pull request for it. */
export async function publishBranch(
  place: { worktree: string; branch: string; commit: string },
  request: PublishRequest,
  gh = "gh",
): Promise<Published> {
  const configured = await origin(place.worktree);
  if (!same(githubRepository(configured), request.repository))
    throw new Error(
      `This repository's origin is ${configured || "not set"}, not github.com/${request.repository}`,
    );
  const commit = place.commit;
  const run = async (...args: string[]) =>
    (await exec(gh, args, { cwd: place.worktree, maxBuffer: 4_000_000 })).stdout.trim();
  const repository = JSON.parse(
    await run("repo", "view", request.repository, "--json", "id,defaultBranchRef"),
  ) as { id: string; defaultBranchRef: { name: string } };
  const base = repository.defaultBranchRef.name;
  // Never forced: a branch that moved on GitHub refuses rather than losing someone's commits.
  await git(place.worktree, "push", "origin", `${commit}:refs/heads/${place.branch}`);
  const open = JSON.parse(
    await run(
      "pr",
      "list",
      "--repo",
      request.repository,
      "--head",
      place.branch,
      "--state",
      "open",
      "--json",
      "url",
      "--limit",
      "1",
    ),
  ) as { url: string }[];
  const pullRequest =
    open[0]?.url ??
    (
      await run(
        "pr",
        "create",
        "--repo",
        request.repository,
        "--head",
        place.branch,
        "--base",
        base,
        "--title",
        request.title,
        "--body",
        request.body,
      )
    )
      .split("\n")
      .at(-1)!;
  return {
    repository: request.repository,
    repositoryId: repository.id,
    branch: place.branch,
    base,
    commit,
    pullRequest,
  };
}
