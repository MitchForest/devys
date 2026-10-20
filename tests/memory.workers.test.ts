import { expect, it } from "vitest";
import { env } from "cloudflare:workers";
import { business, db, sql } from "./fixtures/postgres.ts";
import { Effect } from "effect";
import { createMemory } from "../src/memory/service.ts";
import type {
  Change,
  CompleteMemory,
  Memory,
  Observation,
  PortableRecord,
} from "../src/memory/contract.ts";
import { memoryRoute } from "../src/memory/http.ts";
import { catchUpMemory, observations } from "../src/runtime/memory.ts";
import type { EntryRecord } from "@earendil-works/pi-durable";
const run = Effect.runPromise;
/** Memory keys by scope (a business id); no other records are needed. */
async function owner(complete?: CompleteMemory) {
  const id = crypto.randomUUID();
  return { id, memory: createMemory(db, id, complete) };
}
const source = (
  id: string,
  content = "My home address is 123 Example Street.",
  offset = -1000,
): Observation => ({
  id,
  kind: "owner",
  observedAt: new Date(Date.now() + offset).toISOString(),
  content,
});
async function remember(
  memory: Memory,
  key: string,
  evidence: string,
  content = "123 Example Street",
  op: string = crypto.randomUUID(),
) {
  const prior = (await run(memory.inspect())).items.find((c) => c.key === key);
  return run(
    memory.remember(
      {
        key,
        content,
        source: "user",
        evidenceIds: [evidence],
        scope: "home",
        expectedRevision: prior?.revision ?? 0,
      },
      op,
    ),
  );
}
async function portable(memory: Memory) {
  const result: PortableRecord[] = [];
  let after: string | undefined;
  do {
    const page = await run(memory.export(after));
    result.push(...page.items);
    after = page.next ?? undefined;
  } while (after);
  return result;
}
it("captures once, distinguishes acceptance from extraction, and preserves authenticated attribution", async () => {
  let calls = 0;
  const { memory } = await owner(async ({ observations }) => {
    calls++;
    return [
      {
        key: "home",
        content: observations[0]!.content,
        source: "user",
        evidenceIds: [observations[0]!.id],
      },
    ];
  });
  expect(await run(memory.observe([source("first")], 8))).toEqual({ status: "accepted" });
  expect((await run(memory.inspect())).items).toEqual([]);
  await run(memory.observe([source("first", "spoofed replacement")], 3));
  expect(await run(memory.progress())).toEqual({ cursor: 8 });
  expect(await run(memory.maintain({ maxSources: 4 }))).toEqual({ processed: 1, more: false });
  expect((await run(memory.search({ query: "home address" }))).items[0]).toMatchObject({
    source_kind: "user",
    content: "My home address is 123 Example Street.",
    evidence: [{ id: "first", kind: "owner" }],
  });
  await run(memory.observe([source("first")], 8));
  await run(memory.maintain({ maxSources: 4 }));
  expect(calls).toBe(1);
  const inferred = await run(
    memory.remember({ key: "guess", content: "Likes aisle seats", source: "user" }, "guess"),
  );
  expect(inferred.claim.source_kind).toBe("inference");
  const other = await owner();
  const rejected = await run(
    other.memory
      .remember({ key: "stolen", content: "x", evidenceIds: ["first"] }, "x")
      .pipe(Effect.flip),
  );
  expect(rejected.code).toBe("invalid");
  expect((await run(other.memory.search({ query: "address" }))).items).toEqual([]);
});
it("corrections are immediate, stale replays cannot reverse them, and revisions reject lost updates", async () => {
  const { memory } = await owner();
  await run(memory.observe([source("old"), source("new", "My home is now 456 New Street.")]));
  const first = await remember(memory, "home", "old", "123 Example Street", "op1");
  const updated = await run(
    memory.remember(
      {
        key: "home",
        content: "456 New Street",
        source: "user",
        evidenceIds: ["new"],
        expectedRevision: first.claim.revision,
      },
      "op2",
    ),
  );
  expect(updated.claim.revision).toBe(2);
  await remember(memory, "home", "old", "123 Example Street", "op1");
  expect((await run(memory.context({ query: "address" }))).text).toContain("456 New Street");
  expect((await run(memory.search({ query: "123 Example" }))).items).toEqual([]);
  expect(
    (
      await run(
        memory
          .remember({ key: "home", content: "stale", expectedRevision: 1 }, "op3")
          .pipe(Effect.flip),
      )
    ).code,
  ).toBe("conflict");
});
it("a correction during consolidation wins and leaves the observations retryable", async () => {
  let release!: (changes: Change[]) => void;
  let started!: () => void;
  const ready = new Promise<void>((resolve) => {
    started = resolve;
  });
  const { memory } = await owner(async () => {
    started();
    return new Promise<Change[]>((resolve) => {
      release = resolve;
    });
  });
  await run(memory.observe([source("old")]));
  const maintaining = run(memory.maintain({ maxSources: 1 }).pipe(Effect.flip));
  await ready;
  await remember(memory, "home", "old", "Corrected address");
  release([{ key: "home", content: "Stale address", evidenceIds: ["old"], source: "user" }]);
  expect((await maintaining).code).toBe("conflict");
  expect((await run(memory.search({ query: "Corrected" }))).items).toHaveLength(1);
});
it("forget excludes every historical source and dependent claim, including after export/import", async () => {
  const { memory, id } = await owner();
  await run(
    memory.observe([
      source("original"),
      source("correction"),
      source("unrelated", "I like aisle seats."),
    ]),
  );
  await remember(memory, "home", "original");
  await remember(memory, "home", "correction", "456 New Street");
  await remember(memory, "city", "original", "Example City");
  await remember(memory, "seat", "unrelated", "Aisle");
  const records = await portable(memory);
  const target = await owner();
  for (let i = 0; i < records.length; i += 30)
    await run(target.memory.import(records.slice(i, i + 30), `import${i}`));
  await run(target.memory.forget(["home"], "forget"));
  expect((await run(target.memory.inspect())).items.map((c) => c.key)).toEqual(["seat"]);
  await run(target.memory.observe([source("original"), source("correction")]));
  expect(await run(target.memory.maintain({ maxSources: 4 }))).toEqual({
    processed: 0,
    more: false,
  });
  const forgotten = await portable(target.memory);
  expect(
    forgotten
      .filter((r) => r.kind === "excluded-source")
      .map((r) => r.id)
      .sort(),
  ).toEqual(["correction", "original"]);
  expect(JSON.stringify(forgotten)).not.toContain("New Street");
  expect(JSON.stringify(records)).not.toContain(id);
  // Importing an old snapshot cannot defeat exclusions already in the destination.
  for (let i = 0; i < records.length; i += 30)
    await run(target.memory.import(records.slice(i, i + 30), `older${i}`));
  expect((await run(target.memory.inspect())).items.map((c) => c.key)).toEqual(["seat"]);
});
it("forget racing with extraction cannot be undone, and key exclusions suppress later aliases of the same key", async () => {
  let release!: (changes: Change[]) => void;
  let started!: () => void;
  const ready = new Promise<void>((r) => {
    started = r;
  });
  const { memory } = await owner(async () => {
    started();
    return new Promise((r) => {
      release = r;
    });
  });
  await run(memory.observe([source("a")]));
  await remember(memory, "home", "a");
  const maintaining = run(memory.maintain({ maxSources: 1 }).pipe(Effect.flip));
  await ready;
  await run(memory.forget(["home"], "forget"));
  release([{ key: "home", content: "123 Example Street", evidenceIds: ["a"] }]);
  expect(["conflict", "invalid"]).toContain((await maintaining).code);
  expect((await run(memory.inspect())).items).toEqual([]);
});
it("expired and future context stays out of current recall; search is bounded and paginates without omission", async () => {
  const { memory } = await owner();
  await run(
    memory.remember(
      { key: "expired", content: "Hotel address", validUntil: "2000-01-01T00:00:00.000Z" },
      "expired",
    ),
  );
  await run(
    memory.remember(
      { key: "future", content: "Future home", validFrom: "2999-01-01T00:00:00.000Z" },
      "future",
    ),
  );
  for (let i = 0; i < 35; i++)
    await run(
      memory.remember(
        { key: `seat-${String(i).padStart(2, "0")}`, content: "Aisle seat " + "x".repeat(3500) },
        `op${i}`,
      ),
    );
  let after: string | undefined;
  const keys: string[] = [];
  do {
    const page = await run(memory.search({ query: "seat", after, maxChars: 8000 }));
    expect(JSON.stringify(page.items).length).toBeLessThanOrEqual(8000);
    keys.push(...page.items.map((c) => c.key));
    after = page.next ?? undefined;
  } while (after);
  expect(new Set(keys).size).toBe(35);
  expect((await run(memory.search({ query: "Hotel" }))).items).toEqual([]);
  const context = await run(memory.context({ maxChars: 4000 }));
  expect(context.text.length).toBeLessThanOrEqual(4000);
  expect(context.text).not.toContain("Hotel");
  expect(context.text).not.toContain("Future home");
  const tiny = await run(memory.search({ query: "seat", maxChars: 2048 }));
  expect(tiny.items[0]?.truncated).toBe(true);
  await run(memory.remember({ key: "escaped", content: '"\n'.repeat(1900) }, "escaped"));
  const escaped = await run(memory.search({ query: "escaped", maxChars: 2048 }));
  expect(escaped.items).toHaveLength(1);
  expect(escaped.items[0]?.content.length).toBeGreaterThan(0);
  expect(escaped.items[0]?.truncated).toBe(true);
  expect(JSON.stringify(escaped.items).length).toBeLessThanOrEqual(2048);
  await run(
    memory.remember(
      {
        key: "\u0001".repeat(200),
        subject: "\u0001".repeat(300),
        scope: "\u0001".repeat(300),
        content: "metadata " + '"\n'.repeat(1900),
      },
      "\u0001".repeat(200),
    ),
  );
  const metadata = await run(memory.search({ query: "metadata", maxChars: 2048 }));
  expect(metadata.items).toHaveLength(1);
  expect(metadata.items[0]?.key).toBe("\u0001".repeat(200));
  expect(JSON.stringify(metadata.items).length).toBeLessThanOrEqual(2048);
  expect(JSON.stringify(tiny.items).length).toBeLessThanOrEqual(2048);
});
it("portable pages validate versions, reject excerpts and overwrite conflicts, and preserve legacy provenance", async () => {
  const { memory, id } = await owner();
  await sql.run(
    "INSERT INTO memories(scope_id,key,content,source_kind,source_operation_id) VALUES ($1,'legacy','old context','user','old-tool-call')",
    [id],
  );
  const data = await portable(memory);
  expect(data[0]).toMatchObject({
    kind: "claim",
    claim: { evidence: [{ id: "old-tool-call", kind: "legacy" }] },
  });
  const other = await owner();
  await run(other.memory.import(data, "import"));
  await run(other.memory.import(data, "import"));
  expect(await portable(other.memory)).toEqual([
    ...data,
    {
      version: 1,
      kind: "evidence-link",
      key: "legacy",
      evidence: (data[0] as Extract<PortableRecord, { kind: "claim" }>).claim.evidence[0],
    },
  ]);
  const bad = await run(
    other.memory
      .import([{ version: 2, kind: "excluded-key", key: "x" } as unknown as PortableRecord], "bad")
      .pipe(Effect.flip),
  );
  expect(bad.code).toBe("invalid");
  await run(
    other.memory.remember({ key: "legacy", content: "changed", expectedRevision: 1 }, "change"),
  );
  expect((await run(other.memory.import(data, "overwrite").pipe(Effect.flip))).code).toBe(
    "conflict",
  );
});
it("catch-up survives restart and ignores assistant, compaction, and tool text", async () => {
  const entries = [
    {
      id: 1,
      conversationId: 1,
      kind: "pi.user",
      model: [{ role: "user", content: "My address is 123 Example Street", timestamp: 1000 }],
    },
    {
      id: 2,
      conversationId: 1,
      kind: "pi.assistant",
      model: [{ role: "assistant", content: [{ type: "text", text: "invented" }] }],
    },
    {
      id: 3,
      conversationId: 1,
      kind: "pi.compaction",
      model: [{ role: "user", content: "summary", timestamp: 1000 }],
    },
    {
      id: 61,
      conversationId: 1,
      kind: "pi.user",
      model: [{ role: "user", content: "I prefer aisle seats.", timestamp: 2000 }],
    },
  ] as unknown as EntryRecord[];
  expect(observations(entries, "source-a")[0]!.id).not.toBe(
    observations(entries, "source-b")[0]!.id,
  );
  expect(observations(entries, "source-a").map((o) => o.content)).toEqual([
    "My address is 123 Example Street",
    "I prefer aisle seats.",
  ]);
  const { memory, id } = await owner();
  const scan = async (min: number, max: number | undefined, limit: number) =>
    entries
      .filter((e) => e.id >= min && (max === undefined || e.id <= max))
      .sort((a, b) => b.id - a.id)
      .slice(0, limit);
  await catchUpMemory(memory, scan, "source-a");
  const restarted = createMemory(db, id);
  for (let i = 0; i < 20 && (await catchUpMemory(restarted, scan, "source-a")); i++);
  expect(await run(restarted.progress())).toEqual({ cursor: 61 });
  expect(await catchUpMemory(restarted, scan, "source-a")).toBe(false);
  expect(await sql.rows("SELECT id FROM memory_sources WHERE scope_id=$1", [id])).toHaveLength(2);
});
it("management API uses authenticated identity, origin checks, and explicit idempotency", async () => {
  const a = await owner(),
    b = await owner();
  const factory = (id: string) => {
    expect(id).toBe(a.id);
    return a.memory;
  };
  const request = (path: string, origin: string, body: unknown) =>
    new Request(`https://devys.test/api/memory/${path}`, {
      method: "POST",
      headers: { origin, "content-type": "application/json", "idempotency-key": path },
      body: JSON.stringify(body),
    });
  expect(
    (await memoryRoute(request("remember", "https://evil.test", {}), a.id, "/remember", factory))
      .status,
  ).toBe(403);
  const saved = await memoryRoute(
    request("remember", "https://devys.test", {
      ownerId: b.id,
      key: "seat",
      content: "Aisle",
      source: "user",
    }),
    a.id,
    "/remember",
    factory,
  );
  expect(saved.status).toBe(200);
  expect((await run(a.memory.inspect())).items).toHaveLength(1);
  expect((await run(b.memory.inspect())).items).toHaveLength(0);
  const removed = await memoryRoute(
    request("forget", "https://devys.test", { keys: ["seat"] }),
    a.id,
    "/forget",
    factory,
  );
  expect(removed.status).toBe(200);
  expect((await run(a.memory.inspect())).items).toHaveLength(0);
});

it.skipIf(!(env as { DEVYS_MODEL_GATEWAY_KEY?: string }).DEVYS_MODEL_GATEWAY_KEY)(
  "real model learns scoped delivery and flight preferences from ordinary conversation",
  async () => {
    const { memoryFor } = await import("../src/app/memory.ts");
    // Production memory is business-wide and refuses an inactive or unknown business.
    const { id } = (await business("Live memory")).business;
    const memory = memoryFor(
      {
        HYPERDRIVE: db,
        DEVYS_MODEL_GATEWAY_KEY: (env as { DEVYS_MODEL_GATEWAY_KEY: string })
          .DEVYS_MODEL_GATEWAY_KEY,
      },
      id,
    );
    await run(
      memory.observe([
        source(
          "live-home",
          "My home address is 123 Example Street, apartment 4. Send the Amazon order there.",
        ),
        source(
          "live-hotel",
          "For this gift only, ship to my sister at 789 Sample Road. This is not my home address.",
        ),
        source(
          "live-flight",
          "When flying I generally prefer aisle seats and nonstop flights. For this overnight flight, choose a window so I can sleep. That is just for this trip.",
        ),
      ]),
    );
    const result = await run(memory.maintain({ maxSources: 4 }));
    expect(result.processed).toBe(3);
    const claims = (await run(memory.inspect())).items;
    expect(
      claims.some((c) => c.content.includes("123 Example Street") && c.source_kind === "user"),
    ).toBe(true);
    expect(claims.some((c) => /aisle/i.test(c.content) && /prefer/i.test(c.content))).toBe(true);
    expect(claims.some((c) => /nonstop|non-stop/i.test(c.content))).toBe(true);
    expect(
      claims
        .filter((c) => c.content.includes("789 Sample Road"))
        .every((c) => /sister|gift|one.?time|this/i.test(`${c.subject} ${c.scope} ${c.content}`)),
    ).toBe(true);
    expect(
      claims
        .filter((c) => /window/i.test(c.content))
        .every((c) => /overnight|trip|exception|this/i.test(`${c.scope} ${c.content}`)),
    ).toBe(true);
    for (const c of claims) expect(c.evidence.length).toBeGreaterThan(0);
  },
  60000,
);

it("mutation identities reject changed payloads and cannot make forgetting falsely succeed", async () => {
  const { memory } = await owner();
  await run(memory.remember({ key: "seat", content: "Aisle" }, "same"));
  expect(
    (
      await run(
        memory
          .remember({ key: "seat", content: "Window", expectedRevision: 1 }, "same")
          .pipe(Effect.flip),
      )
    ).code,
  ).toBe("conflict");
  expect((await run(memory.forget(["seat"], "same").pipe(Effect.flip))).code).toBe("conflict");
  expect((await run(memory.search({ query: "Aisle" }))).items).toHaveLength(1);
});
it("background catch-up cannot reverse a newer imported conclusion", async () => {
  const { memory } = await owner(async ({ observations }) => [
    {
      key: "home",
      content: observations[0]!.content,
      source: "user",
      evidenceIds: [observations[0]!.id],
    },
  ]);
  await run(memory.observe([source("newer", "New home", 1000)]));
  await run(memory.maintain({ maxSources: 1 }));
  await run(memory.observe([source("older", "Old home", -10000)]));
  await run(memory.maintain({ maxSources: 1 }));
  expect((await run(memory.search({ query: "New home" }))).items[0]?.content).toBe("New home");
});
it("cancellation or revocation before commit leaves a maintenance batch unprocessed", async () => {
  let active = true;
  const { id } = await owner();
  const memory = createMemory(
    db,
    id,
    async ({ observations }) => {
      active = false;
      return [{ key: "home", content: "123 Example Street", evidenceIds: [observations[0]!.id] }];
    },
    async () => {
      if (!active) throw new Error("cancelled");
    },
  );
  await run(memory.observe([source("one")]));
  await expect(run(memory.maintain({ maxSources: 1 }))).rejects.toThrow();
  expect((await run(memory.inspect())).items).toEqual([]);
  expect(
    (
      await sql.row<{ processed: boolean }>(
        "SELECT processed FROM memory_sources WHERE scope_id=$1 AND id='one'",
        [id],
      )
    )?.processed,
  ).toBe(false);
});
it("maintenance budgets whole observations without truncating facts or marking skipped sources processed", async () => {
  let received: string[] = [];
  const { memory } = await owner(async ({ observations }) => {
    received = observations.map((o) => o.id);
    expect(observations.reduce((n, o) => n + o.content.length, 0)).toBeLessThanOrEqual(64000);
    expect(observations[0]!.content.endsWith("THE END")).toBe(true);
    return [];
  });
  await run(
    memory.observe([
      source("a", "x".repeat(63990) + "THE END", -2000),
      source("b", "Second message THE END", -1000),
    ]),
  );
  expect(await run(memory.maintain({ maxSources: 4 }))).toEqual({ processed: 1, more: true });
  expect(received).toEqual(["a"]);
  expect(await run(memory.maintain({ maxSources: 4 }))).toEqual({ processed: 1, more: false });
  expect(received).toEqual(["b"]);
});
it("relationship lookup brings a partner's preferences into task context without a graph database", async () => {
  const { memory } = await owner();
  await run(
    memory.remember(
      {
        key: "partner",
        content: "Alex is my partner",
        subject: "owner",
        relations: [{ predicate: "partner", target: "person:alex" }],
      },
      "relationship",
    ),
  );
  await run(
    memory.remember(
      { key: "alex-food", content: "Vegetarian", subject: "person:alex", scope: "dining" },
      "food",
    ),
  );
  await run(
    memory.remember(
      { key: "unrelated", content: "Private project notes", subject: "project:other" },
      "other",
    ),
  );
  const found = await run(memory.search({ query: "partner" }));
  expect(found.items.map((c) => c.key).sort()).toEqual(["alex-food", "partner"]);
});
it("forgetting legacy knowledge with unknown provenance fences historical re-learning without deleting other current facts", async () => {
  const { memory, id } = await owner();
  await sql.run(
    "INSERT INTO memories(scope_id,key,content,source_kind,source_operation_id) VALUES ($1,'legacy-home','Old address','user','legacy-call')",
    [id],
  );
  await run(memory.remember({ key: "seat", content: "Aisle" }, "seat"));
  await run(memory.forget(["legacy-home"], "forget-legacy"));
  await run(memory.observe([source("historical", "Old address", -50000)]));
  expect(await run(memory.maintain({ maxSources: 4 }))).toEqual({ processed: 0, more: false });
  expect((await run(memory.inspect())).items.map((c) => c.key)).toEqual(["seat"]);
  const snapshot = await portable(memory);
  expect(snapshot.some((r) => r.kind === "excluded-before")).toBe(true);
  const next = await owner();
  await run(next.memory.import(snapshot, "import"));
  await run(next.memory.observe([source("different-old-id", "Old address", -50000)]));
  expect(await run(next.memory.maintain({ maxSources: 4 }))).toEqual({ processed: 0, more: false });
  await run(next.memory.observe([source("fresh", "I now live elsewhere.", 1000)]));
  await expect(run(next.memory.maintain({ maxSources: 4 }))).rejects.toThrow(
    "consolidation model is unavailable",
  );
});
it("consolidation merges duplicates and preserves all sources for later forgetting", async () => {
  let pass = 0;
  const { memory } = await owner(async ({ observations, existing }) => {
    pass++;
    if (pass < 3)
      return [
        {
          key: `seat-${pass}`,
          content: "Prefers aisle seats",
          source: "user",
          evidenceIds: [observations[0]!.id],
        },
      ];
    expect(existing.map((c) => c.key)).toContain("seat-2");
    return [
      {
        key: "seat-1",
        content: "Prefers aisle seats",
        source: "user",
        evidenceIds: [observations[0]!.id, "choice-2"],
        supersedes: ["seat-2"],
      },
    ];
  });
  for (let i = 1; i <= 3; i++) {
    await run(memory.observe([source(`choice-${i}`, "I prefer aisle seats.", i * 1000)]));
    await run(memory.maintain({ maxSources: 1 }));
  }
  expect((await run(memory.inspect())).items.map((c) => c.key)).toEqual(["seat-1"]);
  await run(memory.forget(["seat-1"], "forget"));
  const snapshot = await portable(memory);
  expect(snapshot.filter((r) => r.kind === "excluded-source")).toHaveLength(3);
});
