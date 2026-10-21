import type { Files } from "@cloudflare/sandbox";
import { readBounded } from "../protocol/bytes.ts";
import { isSkillName, parseSkill, skillBytes, type Skill } from "../protocol/skill.ts";
import type { SkillCatalog, WorkspaceSkill } from "./contract.ts";

/** The most skills an employee's instructions list. */
const listed = 32;

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
    .filter((entry) => entry.type === "directory" && isSkillName(entry.name))
    .sort((a, b) => a.name.localeCompare(b.name));
  if (entries.length > listed)
    catalog.warnings.push(
      `Only the first ${listed} skill directories are listed. Use run to inspect others.`,
    );
  for (const entry of entries.slice(0, listed)) {
    const path = `${root}/${entry.name}/SKILL.md`;
    try {
      const stat = await files.lstat(path, options);
      if (stat.type !== "file" || stat.size > BigInt(skillBytes)) {
        catalog.warnings.push(`${entry.name}: SKILL.md must be a regular file of at most 16 KB.`);
        continue;
      }
      const response = await files.readFile(path, options);
      if (!response.ok) throw new Error("Unreadable skill");
      const skill = parseSkill(
        entry.name,
        new TextDecoder().decode(await readBounded(response.body, skillBytes)),
      );
      if (!skill) {
        catalog.warnings.push(
          `${entry.name}: use matching name, a description of 1–300 characters, and instructions.`,
        );
        continue;
      }
      catalog.skills.push({ name: skill.name, description: skill.description, path });
    } catch {
      options.signal.throwIfAborted();
      // One broken user-authored skill must not hide valid neighbors.
      catalog.warnings.push(`${entry.name}: SKILL.md is missing, invalid or unreadable.`);
    }
  }
  return catalog;
}

/**
 * The skills an employee's instructions list: the business's own, then its installed apps'
 * (a business skill replaces an app skill of the same name), at most 32.
 */
export function availableSkills(own: readonly WorkspaceSkill[], bundled: readonly Skill[]) {
  const named = new Set(own.map((skill) => skill.name));
  return [...own, ...bundled.filter((skill) => !named.has(skill.name))]
    .slice(0, listed)
    .map(({ name, description }) => ({ name, description }));
}
