import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { filesRoute } from "../src/app/files.ts";
import { startHost } from "../src/workspace/host/server.ts";

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
  skills: join(home, "skills"),
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
  const save = (content: string, expectedRevision: string) =>
    call("/files/text", {
      method: "PUT",
      body: JSON.stringify({ path, content, expectedRevision }),
    });
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
      `/files/raw?path=${encodeURIComponent(join(root, "report.pdf"))}&expectedRevision=${expected}`,
      {
        method: "PUT",
        body,
      },
    );
  expect((await put("%PDF-1.7 edited", revision)).status).toBe(200);
  expect((await put("%PDF-1.7 stale", revision)).status).toBe(409);
  // A derived export carries no revision and overwrites; "none" only creates.
  const exported = (body: string, query = "") =>
    call(`/files/raw?path=${encodeURIComponent(join(root, "deck.pptx"))}${query}`, {
      method: "PUT",
      body,
    });
  expect((await exported("one", "&expectedRevision=none")).status).toBe(200);
  expect((await exported("two", "&expectedRevision=none")).status).toBe(409);
  expect((await exported("three")).status).toBe(200);
  expect(objects.size).toBe(0);
  expect((await call(`/files?path=${encodeURIComponent(home)}`)).status).toBe(400);
  expect(
    (await call(`/files/text?path=${encodeURIComponent(`${root}/../other/secret.md`)}`)).status,
  ).toBe(400);
  expect((await call("/files/text", { method: "PUT", body: "{}", trusted: false })).status).toBe(
    403,
  );
});
