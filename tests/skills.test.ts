import { expect, it } from "vitest";
import { mkdtemp, mkdir, readFile, readdir, lstat, writeFile, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listWorkspaceSkills } from "../src/workspace/skills.ts";

async function workspace() {
  const root = await mkdtemp(join(tmpdir(), "devys-skills-"));
  const local = (path: string) => join(root, path.replace(/^\/workspace\/?/, ""));
  const type = (stat: { isDirectory(): boolean; isFile(): boolean }) =>
    stat.isDirectory()
      ? ("directory" as const)
      : stat.isFile()
        ? ("file" as const)
        : ("symlink" as const);
  return {
    root,
    local,
    files: {
      lstat: async (path: string) => {
        const stat = await lstat(local(path));
        return {
          type: type(stat),
          size: BigInt(stat.size),
          mode: stat.mode,
          uid: stat.uid,
          gid: stat.gid,
          accessedAt: stat.atime,
          modifiedAt: stat.mtime,
          changedAt: stat.ctime,
        };
      },
      readDirectory: async (path: string) =>
        (await readdir(local(path), { withFileTypes: true })).map((entry) => ({
          name: entry.name,
          type: type(entry),
        })),
      readFile: async (path: string) => new Response(await readFile(local(path), "utf8")),
    },
    save: async (name: string, text: string) => {
      await mkdir(local(`/workspace/skills/${name}`), { recursive: true });
      await writeFile(local(`/workspace/skills/${name}/SKILL.md`), text);
    },
  };
}

it("discovers fresh skill metadata without loading instructions into the catalog; owner workspaces stay separate", async () => {
  const a = await workspace(),
    b = await workspace();
  try {
    expect(await listWorkspaceSkills(a.files)).toEqual({ skills: [], warnings: [] });
    await a.save(
      "report",
      "---\nname: report\ndescription: Build my weekly report\n---\nRun the private report script.",
    );
    const catalog = await listWorkspaceSkills(a.files);
    expect(catalog.skills).toEqual([
      {
        name: "report",
        description: "Build my weekly report",
        path: "/workspace/skills/report/SKILL.md",
      },
    ]);
    expect(JSON.stringify(catalog)).not.toContain("private report script");
    expect((await listWorkspaceSkills(b.files)).skills).toEqual([]);
    await a.save(
      "report",
      "---\nname: report\ndescription: Updated report\n---\nUse the revised script.",
    );
    expect((await listWorkspaceSkills(a.files)).skills[0]?.description).toBe("Updated report");
  } finally {
    await Promise.all([
      rm(a.root, { recursive: true, force: true }),
      rm(b.root, { recursive: true, force: true }),
    ]);
  }
});

it("bounds malformed/oversized skills and skips symlinks without hiding valid neighbors", async () => {
  const w = await workspace();
  try {
    await w.save("good", "---\nname: good\ndescription: A useful skill\n---\nInstructions");
    await w.save("bad", "Missing frontmatter");
    await w.save("large", "x".repeat(17_000));
    await symlink(w.local("/workspace/skills/good"), w.local("/workspace/skills/link"));
    const catalog = await listWorkspaceSkills(w.files);
    expect(catalog.skills.map((s) => s.name)).toEqual(["good"]);
    expect(catalog.warnings).toHaveLength(2);
  } finally {
    await rm(w.root, { recursive: true, force: true });
  }
});
