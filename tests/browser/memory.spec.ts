import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { randomBytes, createHash } from "node:crypto";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const exec = promisify(execFile);
test("authenticated memory APIs and portable CLI migrate between isolated businesses", async ({
  request,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const temp = await mkdtemp(join(tmpdir(), "devys-memory-"));
  const users = await Promise.all(
    [0, 1].map(async () => ({
      ...(await stores.owner("Memory migration")),
      session: Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join(""),
    })),
  );
  const first = users[0]!,
    second = users[1]!;
  for (const user of users)
    await sql.run(
      "INSERT INTO web_sessions(token_hash,person_id,expires_at) VALUES ($1,$2, '2999-01-01T00:00:00.000Z')",
      [createHash("sha256").update(user.session).digest("hex"), user.person],
    );
  const memory = (user: { business: string }) => `/api/businesses/${user.business}/memory`;
  const headers = (session: string) => ({
    cookie: `__Host-devys=${session}`,
    origin: "http://127.0.0.1:5173",
  });
  const cli = (command: string, path: string, user: { session: string; business: string }) =>
    exec("bun", ["scripts/memory.ts", command, path], {
      env: {
        ...process.env,
        DEVYS_URL: "http://127.0.0.1:5173",
        DEVYS_SESSION: user.session,
        DEVYS_BUSINESS: user.business,
      },
      timeout: 30000,
    });
  try {
    expect((await request.get(memory(first))).status()).toBe(401);
    for (let i = 0; i < 17; i++) {
      const response = await request.post(`${memory(first)}/remember`, {
        headers: { ...headers(first.session), "idempotency-key": `save-${i}` },
        data: { key: `preference-${i}`, content: `Preference ${i}`, source: "user" },
      });
      expect(response.status()).toBe(200);
    }
    const stale = await request.post(`${memory(first)}/remember`, {
      headers: { ...headers(first.session), "idempotency-key": "stale" },
      data: { key: "preference-0", content: "Changed", source: "user", expected_revision: 0 },
    });
    expect(stale.status()).toBe(409);
    const file = join(temp, "memory.ndjson");
    expect((await cli("export", file, first)).stdout).toContain("Exported");
    const exported = await readFile(file, "utf8");
    expect(exported).toContain('"kind":"complete"');
    expect(exported).not.toContain(first.person);
    expect(exported).not.toContain(first.session);
    const broken = join(temp, "incomplete.ndjson");
    await writeFile(broken, exported.replace('{"kind":"complete"}\n', ""));
    await expect(cli("import", broken, second)).rejects.toThrow();
    expect(
      (await (await request.get(memory(second), { headers: headers(second.session) })).json())
        .items,
    ).toHaveLength(0);
    expect((await cli("import", file, second)).stdout).toContain("Imported");
    await cli("import", file, second);
    const copy = await (
      await request.get(memory(second), { headers: headers(second.session) })
    ).json();
    expect(copy.items).toHaveLength(17);
    expect(
      (
        await request.post(`${memory(second)}/forget`, {
          headers: {
            ...headers(second.session),
            origin: "https://attacker.invalid",
            "idempotency-key": "forget",
          },
          data: { keys: ["preference-0"] },
        })
      ).status(),
    ).toBe(403);
    expect(
      (
        await request.post(`${memory(second)}/forget`, {
          headers: { ...headers(second.session), "idempotency-key": "forget" },
          data: { keys: ["preference-0"] },
        })
      ).status(),
    ).toBe(200);
    expect(
      (await (await request.get(memory(second), { headers: headers(second.session) })).json())
        .items,
    ).toHaveLength(16);
    expect(
      (await (await request.get(memory(first), { headers: headers(first.session) })).json()).items,
    ).toHaveLength(17);
  } finally {
    await stores.remove(users);
    await stores.dispose();
    await rm(temp, { recursive: true, force: true });
  }
});
