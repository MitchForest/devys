import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Effect } from "effect";
import { afterAll, expect, it, vi } from "vitest";
import type { Env } from "../infra/api.ts";
import { filesRoute } from "../src/app/files.ts";
import { startHost } from "../src/workspace/host/server.ts";

// Work items, as the files route reads them: the owner ("p") has taken over "mine" only.
vi.mock("../src/work/service.ts", () => ({
  workItem: (_db: unknown, _business: string, id: string) =>
    Effect.succeed(
      id === "mine"
        ? { id, taken_over_by: "p" }
        : id === "theirs"
          ? { id, taken_over_by: null }
          : null,
    ),
}));

const token = "test-token";
const home = realpathSync(mkdtempSync(join(tmpdir(), "devys-files-")));
const business = { id: "business-1", name: "Business" };
const root = join(home, "Devys", business.id);
mkdirSync(join(root, "docs"), { recursive: true });
writeFileSync(join(root, "docs", "plan.md"), "# Plan\n");
writeFileSync(join(root, "report.pdf"), "%PDF-1.7 test");
const host = await startHost({
  token,
  data: join(home, "data"),
  work: join(home, "Devys"),
  port: 0,
});
afterAll(() => host.close());
const objects = new Map<string, ArrayBuffer>();
const view = (bytes: ArrayBuffer) => ({ size: bytes.byteLength, arrayBuffer: async () => bytes });
const env = {
  DEVYS_MODE: "local",
  DEVYS_HOST_URL: `http://127.0.0.1:${host.port}`,
  DEVYS_HOST_TOKEN: token,
  DEVYS_HOST_HOME: home,
  FILES: {
    get: async (key: string) => (objects.has(key) ? view(objects.get(key)!) : null),
    head: async (key: string) => (objects.has(key) ? view(objects.get(key)!) : null),
    put: async (key: string, value: ArrayBuffer) => void objects.set(key, value),
    delete: async (key: string) => void objects.delete(key),
  },
} as unknown as Env;

const call = async (path: string, init?: RequestInit & { trusted?: boolean }) => {
  const url = new URL(`http://devys.test${path}`);
  return (await filesRoute(new Request(url, init), env, {
    person: { id: "p", display_name: "Owner" } as never,
    business: business as never,
    trusted: init?.trusted ?? true,
    path: url.pathname,
  }))!;
};

it("lists the business folder, reads and saves text at a revision, and refuses a stale save", async () => {
  const listed = (await (await call("/files")).json()) as {
    root: string;
    entries: { name: string; kind: string }[];
  };
  expect(listed.root).toBe(root);
  expect(listed.entries.map((entry) => [entry.name, entry.kind])).toEqual([
    ["docs", "directory"],
    ["report.pdf", "file"],
  ]);
  const path = join(root, "docs", "plan.md");
  const read = (await (await call(`/files/text?path=${encodeURIComponent(path)}`)).json()) as {
    content: string;
    revision: string;
  };
  expect(read.content).toBe("# Plan\n");
  const save = (content: string, expectedRevision: string, work: string | null = "mine") =>
    call("/files/text", {
      method: "PUT",
      body: JSON.stringify({
        path,
        content,
        expected_revision: expectedRevision,
        ...(work === null ? {} : { work }),
      }),
    });
  // Layers are read-only: a save by hand needs a work item the owner has taken over.
  for (const work of [null, "theirs", "missing"]) {
    const refused = await save("# Plan\nMine.\n", read.revision, work);
    expect(refused.status).toBe(409);
    expect(await refused.text()).toContain("take over the work item");
  }
  expect((await save("# Plan\nOne.\n", read.revision)).status).toBe(200);
  const stale = await save("# Plan\nTwo.\n", read.revision);
  expect(stale.status).toBe(409);
  expect(((await stale.json()) as { current: { content: string } }).current.content).toBe(
    "# Plan\nOne.\n",
  );
});

it("serves raw bytes with their type, and stays inside the business folder", async () => {
  const raw = await call(`/files/raw?path=${encodeURIComponent(join(root, "report.pdf"))}`);
  expect(raw.headers.get("content-type")).toBe("application/pdf");
  expect(await raw.text()).toBe("%PDF-1.7 test");
  expect(objects.size).toBe(0);
  // Bytes save over the revision they were read at.
  const revision = raw.headers.get("x-devys-revision")!;
  const put = (body: string, expected: string) =>
    call(
      `/files/raw?path=${encodeURIComponent(join(root, "report.pdf"))}&expected_revision=${expected}&work=mine`,
      {
        method: "PUT",
        body,
      },
    );
  expect((await put("%PDF-1.7 edited", revision)).status).toBe(200);
  expect((await put("%PDF-1.7 stale", revision)).status).toBe(409);
  // A derived export carries no revision and overwrites; "none" only creates.
  const exported = (body: string, query = "") =>
    call(`/files/raw?path=${encodeURIComponent(join(root, "deck.pptx"))}&work=mine${query}`, {
      method: "PUT",
      body,
    });
  expect((await exported("one", "&expected_revision=none")).status).toBe(200);
  expect((await exported("two", "&expected_revision=none")).status).toBe(409);
  expect((await exported("three")).status).toBe(200);
  expect(
    (
      await call(`/files/raw?path=${encodeURIComponent(join(root, "deck.pptx"))}&work=theirs`, {
        method: "PUT",
        body: "four",
      })
    ).status,
  ).toBe(409);
  expect(objects.size).toBe(0);
  expect((await call(`/files?path=${encodeURIComponent(home)}`)).status).toBe(400);
  expect(
    (await call(`/files/text?path=${encodeURIComponent(`${root}/../other/secret.md`)}`)).status,
  ).toBe(400);
  expect((await call("/files/text", { method: "PUT", body: "{}", trusted: false })).status).toBe(
    403,
  );
});
