import { createMemory } from "../src/memory/service.ts";
import { expect, it } from "vitest";
import { business, db, sql } from "./fixtures/postgres.ts";
import { redeemEnrollment } from "../src/identity/sessions.ts";
import type { Env } from "../infra/api.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { exportBusiness } from "../src/app/export.ts";
import { issueEnrollment } from "../src/identity/enrollment.ts";
import { Effect } from "effect";
import { bindChannel, channelBinding } from "../src/identity/service.ts";
import { postMessage } from "../src/conversations/service.ts";

const invocation = (scope: { businessId: string; employeeId: string }, operationId: string) =>
  Effect.provideService(Invocation, {
    ...scope,
    operationId,
    authorize: () => Effect.void,
    assertActive: () => Effect.void,
  });

it("memory corrections supersede prior facts, replays do not advance revision, and businesses stay isolated", async () => {
  const [first, second] = [crypto.randomUUID(), crypto.randomUUID()];
  const input = { key: "preference", content: "Morning", source: "user" as const };
  const saved = await Effect.runPromise(createMemory(db, first).remember(input, "one"));
  const replay = await Effect.runPromise(createMemory(db, first).remember(input, "one"));
  expect(replay.claim.revision).toBe(saved.claim.revision);
  const corrected = await Effect.runPromise(
    createMemory(db, first).remember(
      { ...input, content: "Evening", expectedRevision: saved.claim.revision },
      "two",
    ),
  );
  expect(corrected.claim.revision).toBe(saved.claim.revision + 1);
  const search = (scope: string, query: string) =>
    Effect.runPromise(createMemory(db, scope).search({ query }));
  expect((await search(first, "Morning")).items).toEqual([]);
  expect((await search(second, "Evening")).items).toEqual([]);
  expect((await search(first, "Evening")).items).toHaveLength(1);
});

it("a chat on a channel reaches exactly one employee, only while the person and employee are active", async () => {
  const acme = await business("Acme");
  await Effect.runPromise(
    bindChannel(db, {
      channel: "imessage",
      personId: acme.person,
      scope: acme.scope,
      sender: "s1",
      chat: "c1",
    }),
  );
  expect(await Effect.runPromise(channelBinding(db, "imessage", "s1", "other"))).toBeUndefined();
  expect(await Effect.runPromise(channelBinding(db, "imessage", "s1", "c1"))).toEqual({
    personId: acme.person,
    ...acme.scope,
  });
  await sql.run("UPDATE employees SET revoked_at = now() WHERE id = $1", [acme.scope.employeeId]);
  expect(await Effect.runPromise(channelBinding(db, "imessage", "s1", "c1"))).toBeUndefined();
  await sql.run("UPDATE employees SET revoked_at = NULL WHERE id = $1", [acme.scope.employeeId]);
  await sql.run("UPDATE people SET revoked_at = now() WHERE id = $1", [acme.person]);
  expect(await Effect.runPromise(channelBinding(db, "imessage", "s1", "c1"))).toBeUndefined();
});

it("a chat bound to one business cannot be moved to another, and binding needs membership", async () => {
  const acme = await business("Acme");
  const globex = await business("Globex");
  const chat = { sender: crypto.randomUUID(), chat: crypto.randomUUID() };
  await Effect.runPromise(
    bindChannel(db, {
      channel: "imessage",
      personId: acme.person,
      scope: acme.scope,
      ...chat,
    }),
  );
  await expect(
    Effect.runPromise(
      bindChannel(db, {
        channel: "imessage",
        personId: globex.person,
        scope: globex.scope,
        ...chat,
      }),
    ),
  ).rejects.toThrow();
  expect(
    (await Effect.runPromise(channelBinding(db, "imessage", chat.sender, chat.chat)))?.businessId,
  ).toBe(acme.scope.businessId);
  // Globex's owner is not a member of Acme, so cannot bind into it.
  await expect(
    Effect.runPromise(
      bindChannel(db, {
        channel: "imessage",
        personId: globex.person,
        scope: acme.scope,
        sender: "x",
        chat: "y",
      }),
    ),
  ).rejects.toThrow();
});

it("concurrent redemption creates exactly one session; expired and revoked codes create none", async () => {
  const person = crypto.randomUUID();
  await sql.run("INSERT INTO people(id, display_name) VALUES ($1, 'Enrollment')", [person]);
  for (const [token, expiry] of [
    ["race", "2999-01-01T00:00:00.000Z"],
    ["expired", "2000-01-01T00:00:00.000Z"],
    ["revoked", "2999-01-01T00:00:00.000Z"],
  ])
    await sql.run(
      "INSERT INTO enrollment_tokens(token_hash, person_id, expires_at) VALUES ($1, $2, $3)",
      [token, person, expiry],
    );
  const results = await Promise.all(
    Array.from({ length: 8 }, (_, i) =>
      Effect.runPromise(redeemEnrollment(db, "race", `session-${i}`, "Test device")),
    ),
  );
  expect(results.filter(Boolean)).toHaveLength(1);
  expect(
    (
      await sql.row<{ count: number }>(
        "SELECT count(*)::int AS count FROM web_sessions WHERE person_id = $1",
        [person],
      )
    )?.count,
  ).toBe(1);
  expect(
    await Effect.runPromise(redeemEnrollment(db, "expired", "expired-session", "Test device")),
  ).toBe(false);
  expect(
    await Effect.runPromise(redeemEnrollment(db, "missing", "missing-session", "Test device")),
  ).toBe(false);
  await sql.run("UPDATE people SET revoked_at = '2026-01-01' WHERE id = $1", [person]);
  expect(
    await Effect.runPromise(redeemEnrollment(db, "revoked", "revoked-session", "Test device")),
  ).toBe(false);
});

it("a failure while creating the session rolls back consumption and leaves the code usable", async () => {
  const person = crypto.randomUUID();
  await sql.run("INSERT INTO people(id, display_name) VALUES ($1, 'Rollback')", [person]);
  await sql.run(
    "INSERT INTO enrollment_tokens(token_hash, person_id, expires_at) VALUES ('rollback', $1, '2999-01-01T00:00:00.000Z')",
    [person],
  );
  await sql.run(`CREATE FUNCTION reject_session() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'injected failure'; END $$`);
  await sql.run(`CREATE TRIGGER reject_session BEFORE INSERT ON web_sessions
    FOR EACH ROW WHEN (NEW.token_hash = 'rollback-session') EXECUTE FUNCTION reject_session()`);
  try {
    await expect(
      Effect.runPromise(redeemEnrollment(db, "rollback", "rollback-session", "Test device")),
    ).rejects.toThrow();
    expect(
      await sql.row("SELECT token_hash FROM web_sessions WHERE token_hash='rollback-session'"),
    ).toBeUndefined();
    expect(
      (
        await sql.row<{ consumed_at: string | null }>(
          "SELECT consumed_at FROM enrollment_tokens WHERE token_hash='rollback'",
        )
      )?.consumed_at,
    ).toBeNull();
  } finally {
    await sql.run("DROP TRIGGER reject_session ON web_sessions");
    await sql.run("DROP FUNCTION reject_session");
  }
  expect(
    await Effect.runPromise(redeemEnrollment(db, "rollback", "rollback-session", "Test device")),
  ).toBe(true);
});

it("issuing access cannot reactivate a revoked person", async () => {
  const personId = crypto.randomUUID();
  await Effect.runPromise(issueEnrollment(db, { personId, name: "Owner", tokenHash: "issued" }));
  await sql.run("UPDATE people SET revoked_at='2026-01-01' WHERE id=$1", [personId]);
  await expect(
    Effect.runPromise(issueEnrollment(db, { personId, name: "Owner", tokenHash: "revived" })),
  ).rejects.toThrow();
  expect(
    await sql.row("SELECT token_hash FROM enrollment_tokens WHERE token_hash='revived'"),
  ).toBeUndefined();
});

it("artifact publication reuses saved metadata on replay and scopes identical operation ids by business", async () => {
  const scopes = [(await business()).scope, (await business()).scope];
  let exports = 0;
  const runtime = {
    HYPERDRIVE: db,
    PUBLIC_URL: "https://devys.test",
    DEVYS_MODE: "cloud",
    WORKSPACE: {
      getByName: () => ({
        exportFile: async () => {
          exports++;
          return { size: 12 };
        },
      }),
    },
  } as unknown as Env;
  const publish = capabilities(runtime).find((item) => item.name === "publishArtifact")!;
  const run = (scope: { businessId: string; employeeId: string }) =>
    Effect.runPromise(
      publish
        .execute({
          path: "/workspace/result.txt",
          filename: "result.txt",
          contentType: "text/plain",
        })
        .pipe(invocation(scope, "same-operation")),
    );
  const first = await run(scopes[0]!);
  expect(await run(scopes[0]!)).toEqual(first);
  expect(exports).toBe(1);
  expect(await run(scopes[1]!)).not.toEqual(first);
  expect(exports).toBe(2);
  const records = await sql.rows<{ byte_length: number }>(
    "SELECT business_id, byte_length FROM artifacts WHERE operation_id='same-operation'",
  );
  expect(records).toHaveLength(2);
  expect(records.every((row) => row.byte_length === 12)).toBe(true);
});

it("a business export pages through every employee's history, memory and artifacts without crossing businesses", async () => {
  const created = await business("Export");
  const other = await business("Other");
  await sql.run(
    `INSERT INTO memories(scope_id,key,content,source_kind,source_operation_id)
     SELECT $1, 'key-' || i, 'saved', 'user', 'op-' || i FROM generate_series(0, 54) i`,
    [created.business.id],
  );
  await sql.run(
    `INSERT INTO artifacts(id,business_id,operation_id,object_key,filename,content_type,byte_length)
     SELECT gen_random_uuid(), $1, 'artifact-' || i, $1 || '/' || i, 'file.txt', 'text/plain', 12
     FROM generate_series(0, 100) i`,
    [created.business.id],
  );
  await sql.run(
    `INSERT INTO artifacts(id,business_id,operation_id,object_key,filename,content_type,byte_length)
     VALUES (gen_random_uuid(), $1, 'elsewhere', $1 || '/x', 'other.txt', 'text/plain', 1)`,
    [other.business.id],
  );
  await Effect.runPromise(
    postMessage(db, created.business.id, `direct:${created.operations.id}`, {
      author: `person:${created.person}`,
      text: "Ship Friday",
      clientId: "export-message",
    }),
  );
  await Effect.runPromise(
    postMessage(db, other.business.id, `direct:${other.operations.id}`, {
      author: `person:${other.person}`,
      text: "Not ours",
      clientId: "export-other",
    }),
  );
  const histories: string[] = [];
  const runtime = {
    HYPERDRIVE: db,
    PUBLIC_URL: "https://devys.test",
    AGENT: {
      getByName: (name: string) => ({
        history: async () => {
          histories.push(name);
          return JSON.stringify({ entries: [{ id: 1 }], nextBefore: null });
        },
      }),
    },
  } as unknown as Env;
  const records = (await exportBusiness(runtime, created.business, [created.operations]).text())
    .trim()
    .split("\n")
    .map(
      (line: string) =>
        JSON.parse(line) as { kind: string; employee?: string; message?: { text: string } },
    );
  expect(records.filter((row) => row.kind === "message").map((row) => row.message?.text)).toEqual([
    "Ship Friday",
  ]);
  expect(records.filter((row) => row.kind === "memory")).toHaveLength(55);
  expect(records.filter((row) => row.kind === "artifact")).toHaveLength(101);
  expect(records.find((row) => row.kind === "conversation-entry")?.employee).toBe(
    created.operations.id,
  );
  expect(histories).toEqual([JSON.stringify([created.business.id, created.operations.id])]);
  expect(records.at(-1)).toEqual({ kind: "complete" });
});

it("conversation history reads the conversation the turn answers, never one the model names", async () => {
  const created = await business("History");
  const other = await business("Elsewhere");
  const ops = created.operations.id;
  const key = `direct:${ops}` as const;
  for (let i = 0; i < 35; i++)
    await Effect.runPromise(
      postMessage(db, created.business.id, key, {
        author: i % 2 ? `employee:${ops}` : `person:${created.person}`,
        text: `message ${i}`,
        clientId: `history-${i}`,
      }),
    );
  await Effect.runPromise(
    postMessage(db, other.business.id, `direct:${other.operations.id}`, {
      author: `person:${other.person}`,
      text: "secret",
      clientId: "history-other",
    }),
  );
  const service = capabilities({ DEVYS_MODE: "cloud", HYPERDRIVE: db } as unknown as Env).find(
    (contract) => contract.name === "conversationHistory",
  )!;
  const read = (args: object, conversation?: string) =>
    Effect.runPromise(
      service.execute(args).pipe(
        Effect.provideService(Invocation, {
          businessId: created.business.id,
          employeeId: ops,
          operationId: "history",
          ...(conversation ? { conversation } : {}),
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      ),
    ) as Promise<{ messages: { id: string; from: string; text: string }[]; before: string | null }>;
  const latest = await read({ conversation: `direct:${other.operations.id}` }, key);
  expect(latest.messages).toHaveLength(30);
  expect(latest.messages.at(-1)).toMatchObject({ from: "Owner", text: "message 34" });
  expect(latest.messages.at(-2)).toMatchObject({ from: "Head of Operations", text: "message 33" });
  expect(latest.messages[0]).toMatchObject({ from: "Head of Operations", text: "message 5" });
  const older = await read({ before: latest.before }, key);
  expect(older.messages.map((m) => m.text)).toEqual([0, 1, 2, 3, 4].map((i) => `message ${i}`));
  expect(older.before).toBeNull();
  await expect(read({})).rejects.toMatchObject({ code: "invalid_input" });
});

it("several components' writes commit together or not at all", async () => {
  const { atomically } = await import("../src/data/database.ts");
  const { createEmployee } = await import("../src/identity/service.ts");
  const { grantAll } = await import("../src/authority/service.ts");
  const { scope } = await business("Atomic");
  const input = {
    name: "Temp",
    responsibilities: "Helps",
    model: "m",
    template: "custom" as const,
  };
  let created = "";
  await expect(
    atomically(db, async (db) => {
      created = (await Effect.runPromise(createEmployee(db, scope.businessId, input))).id;
      await Effect.runPromise(
        grantAll(db, { businessId: scope.businessId, employeeId: created }, [
          { capability: { name: "x" } as never, mode: "auto" },
        ]),
      );
      throw new Error("A later step failed");
    }),
  ).rejects.toThrow("A later step failed");
  expect(created).not.toBe("");
  expect(await sql.row("SELECT id FROM employees WHERE id = $1", [created])).toBeUndefined();
  expect(await sql.row("SELECT id FROM grants WHERE employee_id = $1", [created])).toBeUndefined();
});
