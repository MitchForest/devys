import { parse } from "yaml";
import type { Files } from "@cloudflare/sandbox";
import { readBounded } from "../protocol/bytes.ts";

import type { SkillCatalog } from "./contract.ts";

/** Discover ordinary files afresh; no registration database or cached skill bodies. */
export async function listWorkspaceSkills(
  files: Pick<Files, "lstat" | "readDirectory" | "readFile">,
  root = "/workspace/skills",
): Promise<SkillCatalog> {
  const catalog: SkillCatalog = { skills: [], warnings: [] };
  const options = { signal: AbortSignal.timeout(10_000) };
  try {
    const stat = await files.lstat(root, options);
    if (stat.type !== "directory")
      return { skills: [], warnings: [`${root} must be a directory, not a symlink.`] };
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT")
      return catalog;
    throw error;
  }
  const entries = (await files.readDirectory(root, options))
    .filter(
      (entry) =>
        entry.type === "directory" &&
        /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(entry.name) &&
        entry.name.length <= 64,
    )
    .sort((a, b) => a.name.localeCompare(b.name));
  if (entries.length > 32)
    catalog.warnings.push(
      "Only the first 32 skill directories are listed. Use run to inspect others.",
    );
  for (const entry of entries.slice(0, 32)) {
    const path = `${root}/${entry.name}/SKILL.md`;
    try {
      const stat = await files.lstat(path, options);
      if (stat.type !== "file" || stat.size > 16_000n) {
        catalog.warnings.push(`${entry.name}: SKILL.md must be a regular file of at most 16 KB.`);
        continue;
      }
      const response = await files.readFile(path, options);
      if (!response.ok) throw new Error("Unreadable skill");
      const raw = new TextDecoder().decode(await readBounded(response.body, 16_000));
      const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
      const parsed = match ? parse(match[1]!, { maxAliasCount: 0 }) : null;
      if (
        !parsed ||
        parsed.name !== entry.name ||
        typeof parsed.description !== "string" ||
        parsed.description.length > 300 ||
        !parsed.description.trim() ||
        !match?.[2]?.trim()
      ) {
        catalog.warnings.push(
          `${entry.name}: use matching name, a description of 1–300 characters, and instructions.`,
        );
        continue;
      }
      catalog.skills.push({ name: parsed.name, description: parsed.description.trim(), path });
    } catch {
      options.signal.throwIfAborted();
      // One broken user-authored skill must not hide valid neighbors.
      catalog.warnings.push(`${entry.name}: SKILL.md is missing, invalid or unreadable.`);
    }
  }
  return catalog;
}
