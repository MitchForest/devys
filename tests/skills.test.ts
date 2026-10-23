import { expect, it } from "vitest";
import { mkdtemp, mkdir, readFile, readdir, lstat, writeFile, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Effect } from "effect";
import { documents } from "../src/apps/documents/app.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { bundledSkill } from "../src/protocol/skill.ts";
import { workspaceCapabilities } from "../src/workspace/capabilities.ts";
import type { WorkspacePort } from "../src/workspace/contract.ts";
import { availableSkills, listWorkspaceSkills } from "../src/workspace/skills.ts";

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

it("a bundled app skill follows the same SKILL.md rules; a bad one is rejected", () => {
  expect(documents.skills.map((skill) => skill.name)).toEqual(["writing-pages"]);
  expect(documents.skills[0]!.body).toContain("artifactEdit");
  expect(() => bundledSkill("writing-pages", "No frontmatter")).toThrow("not a valid SKILL.md");
  expect(() =>
    bundledSkill("writing-pages", "---\nname: other\ndescription: Mismatch\n---\nBody"),
  ).toThrow();
  expect(() =>
    bundledSkill("Bad_Name", "---\nname: Bad_Name\ndescription: x\n---\nBody"),
  ).toThrow();
  expect(() =>
    bundledSkill("empty", "---\nname: empty\ndescription: Nothing to do\n---\n   "),
  ).toThrow();
});

const appSkill = { name: "writing-pages", description: "App version", body: "App body" };

it("the business's skill replaces an app's of the same name; at most 32 are listed", () => {
  const own = {
    name: "writing-pages",
    description: "Ours",
    path: "/b/skills/writing-pages/SKILL.md",
  };
  expect(availableSkills([own], [appSkill, { ...appSkill, name: "other" }])).toEqual([
    { name: "writing-pages", description: "Ours" },
    { name: "other", description: "App version" },
  ]);
  const many = Array.from({ length: 40 }, (_, i) => ({ ...appSkill, name: `skill-${i}` }));
  expect(availableSkills([], many)).toHaveLength(32);
});

it("readSkill loads the business's skill first, then an installed app's", async () => {
  const files = new Map([
    [
      "/b/skills/writing-pages/SKILL.md",
      "---\nname: writing-pages\ndescription: Ours\n---\nOur own way.",
    ],
  ]);
  const port = {
    skills: async () => ({
      skills: [...files.keys()].map((path) => ({
        name: path.split("/").at(-2)!,
        description: "Ours",
        path,
      })),
      warnings: [],
    }),
    read: async (path: string) => ({ path, content: files.get(path)!, revision: "r" }),
  } as unknown as WorkspacePort;
  const readSkill = workspaceCapabilities(
    () => port,
    async () => [appSkill, { ...appSkill, name: "app-only" }],
    async () => [],
  ).find((item) => item.name === "readSkill")!;
  const read = (name: string) =>
    Effect.runPromise(
      readSkill.execute({ name }).pipe(
        Effect.provideService(Invocation, {
          businessId: "b",
          employeeId: "e",
          operationId: "o",
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      ),
    );
  expect(await read("writing-pages")).toEqual({
    name: "writing-pages",
    description: "Ours",
    body: "Our own way.",
    path: "/b/skills/writing-pages/SKILL.md",
  });
  expect(await read("app-only")).toEqual({ ...appSkill, name: "app-only" });
  await expect(read("missing")).rejects.toThrow("No skill is named missing");
  expect(readSkill.core).toBe(true);
});

it("checking work, shipping code, accounts and email ship with their apps, short and general", async () => {
  const { computer } = await import("../src/apps/computer/app.ts");
  const { code } = await import("../src/apps/code/app.ts");
  const { browser } = await import("../src/apps/browser/app.ts");
  const { conversations } = await import("../src/apps/conversations/app.ts");
  const shipped = [
    [computer, "checking-your-work"],
    [code, "shipping-code"],
    [browser, "accounts-and-sign-ins"],
    [conversations, "emailing-for-the-business"],
  ] as const;
  for (const [app, name] of shipped) {
    const skill = app.skills.find((each) => each.name === name);
    expect(skill, name).toBeDefined();
    expect(skill!.body.split("\n").length, name).toBeLessThanOrEqual(60);
    // Each ends in what the owner glances at: the work item's results.
    expect(skill!.body, name).toMatch(/results/);
  }
});
