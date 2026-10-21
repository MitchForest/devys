import { parse } from "yaml";

/**
 * Reusable instructions in the Agent Skills format: a folder whose `SKILL.md` has YAML
 * frontmatter (`name`, the folder's name; `description`) and Markdown instructions. A skill
 * grants nothing. Apps bundle some; a business keeps its own in its skills folder.
 */
export interface Skill {
  name: string;
  description: string;
  body: string;
}

/** Lowercase words joined by hyphens, at most 64 characters: also the folder's name. */
export const isSkillName = (name: string) =>
  /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name) && name.length <= 64;

/** The largest `SKILL.md` read, in bytes. */
export const skillBytes = 16_000;

/**
 * A `SKILL.md` in its folder `name`, or undefined unless its frontmatter names that folder,
 * its description is 1–300 characters and it has instructions.
 */
export function parseSkill(name: string, raw: string): Skill | undefined {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  let parsed: unknown;
  try {
    parsed = match ? parse(match[1]!, { maxAliasCount: 0 }) : undefined;
  } catch {
    return undefined;
  }
  if (!parsed || typeof parsed !== "object") return undefined;
  const { name: named, description } = parsed as Record<string, unknown>;
  const body = match![2]!.trim();
  if (
    !isSkillName(name) ||
    named !== name ||
    typeof description !== "string" ||
    !description.trim() ||
    description.length > 300 ||
    !body
  )
    return undefined;
  return { name, description: description.trim(), body };
}

/** A skill an app ships (`src/apps/<id>/skills/<name>/SKILL.md`); a bad one fails at load. */
export function bundledSkill(name: string, raw: string): Skill {
  const skill = raw.length <= skillBytes ? parseSkill(name, raw) : undefined;
  if (!skill) throw new Error(`The bundled skill ${name} is not a valid SKILL.md`);
  return skill;
}
