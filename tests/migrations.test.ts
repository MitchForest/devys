import { readdirSync, readFileSync } from "node:fs";
import pg from "pg";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createDatabase, databaseUrl, start } from "../scripts/db.ts";

const name = "devys_migration_test";
const projects = "20261023000000_projects";
const refs = "20261024000000_refs";
const names = "20261025000000_names";
const migrations = readdirSync("migrations").sort();
const apply = (client: pg.Client, only: (migration: string) => boolean) =>
  migrations
    .filter(only)
    .reduce(
      (done, migration) =>
        done.then(() =>
          client.query(readFileSync(`migrations/${migration}/migration.sql`, "utf8")),
        ),
      Promise.resolve() as Promise<unknown>,
    );

let client: pg.Client;
beforeAll(async () => {
  start();
  await createDatabase(name, true);
  client = new pg.Client({ connectionString: databaseUrl(name) });
  await client.connect();
  await apply(client, (migration) => migration < projects);
}, 60_000);
afterAll(() => client?.end());

it("U7 turns spaces into projects with their work, references, channel, reads and follows", async () => {
  const q = (text: string, values: unknown[] = []) => client.query(text, values);
  await q("INSERT INTO businesses (id, name) VALUES ('b1', 'Acme')");
  await q(
    "INSERT INTO employees (id, business_id, name, role, model) VALUES ('ops', 'b1', 'Ops', 'Runs it', 'm')",
  );
  await q(`INSERT INTO spaces (id, business_id, name, purpose, lead_employee_id, created_at) VALUES
    ('launch', 'b1', 'Launch', 'Go live', 'ops', '2026-10-01'),
    ('growth', 'b1', 'Growth', '', NULL, '2026-10-02')`);
  await q(`INSERT INTO commitments (id, business_id, owner_employee_id, title, created_by) VALUES
    ('w-both', 'b1', 'ops', 'Shown twice', 'person:p'),
    ('w-none', 'b1', 'ops', 'Shown nowhere', 'person:p')`);
  await q(`INSERT INTO space_items (id, business_id, space_id, kind, ref, created_at) VALUES
    ('i1', 'b1', 'growth', 'commitment', 'w-both', '2026-10-03'),
    ('i2', 'b1', 'launch', 'commitment', 'w-both', '2026-10-04'),
    ('i3', 'b1', 'launch', 'file', '/Users/o/Devys/b1/plan.md', '2026-10-05'),
    ('i4', 'b1', 'growth', 'artifact', 'a1', '2026-10-06')`);
  await q(
    "INSERT INTO conversations (business_id, key) VALUES ('b1', 'space:launch'), ('b1', 'direct:ops')",
  );
  await q(`INSERT INTO messages (id, business_id, conversation, author, text, client_id) VALUES
    ('m1', 'b1', 'space:launch', 'person:p', 'Plan?', 'c1'),
    ('m2', 'b1', 'direct:ops', 'person:p', 'Hi', 'c2')`);
  const seq = (await q("SELECT seq FROM messages WHERE id = 'm1'")).rows[0].seq;
  await q(
    "INSERT INTO conversation_reads (business_id, conversation, participant, seen_seq) VALUES ('b1', 'space:launch', 'person:p', $1)",
    [seq],
  );
  await q(
    "INSERT INTO follows (business_id, conversation, person_id) VALUES ('b1', 'space:launch', 'p')",
  );

  await apply(client, (migration) => migration >= projects && migration < refs);

  expect(
    (await q("SELECT id, name, goal, lead_employee_id FROM projects ORDER BY created_at")).rows,
  ).toEqual([
    { id: "launch", name: "Launch", goal: "Go live", lead_employee_id: "ops" },
    { id: "growth", name: "Growth", goal: null, lead_employee_id: null },
  ]);
  // A work item shown in two spaces moves into the one that showed it first.
  expect((await q("SELECT id, project_id FROM commitments ORDER BY id")).rows).toEqual([
    { id: "w-both", project_id: "growth" },
    { id: "w-none", project_id: null },
  ]);
  expect((await q("SELECT id, project_id, kind FROM project_items ORDER BY id")).rows).toEqual([
    { id: "i3", project_id: "launch", kind: "file" },
    { id: "i4", project_id: "growth", kind: "artifact" },
  ]);
  expect((await q("SELECT key FROM conversations ORDER BY key")).rows).toEqual([
    { key: "direct:ops" },
    { key: "project:launch" },
  ]);
  expect((await q("SELECT id, conversation FROM messages ORDER BY id")).rows).toEqual([
    { id: "m1", conversation: "project:launch" },
    { id: "m2", conversation: "direct:ops" },
  ]);
  expect((await q("SELECT conversation FROM conversation_reads")).rows).toEqual([
    { conversation: "project:launch" },
  ]);
  expect((await q("SELECT conversation FROM follows")).rows).toEqual([
    { conversation: "project:launch" },
  ]);
  // Every existing business has Documents and Code.
  expect((await q("SELECT app_id FROM app_installs ORDER BY app_id")).rows).toEqual([
    { app_id: "code" },
    { app_id: "documents" },
  ]);
  await expect(
    q("INSERT INTO conversations (business_id, key) VALUES ('b1', 'space:x')"),
  ).rejects.toThrow();
  await expect(
    q(
      "INSERT INTO project_items (id, business_id, project_id, kind, ref) VALUES ('i5', 'b1', 'launch', 'commitment', 'w-none')",
    ),
  ).rejects.toThrow();
});

it("U8 rewrites message refs and project items as Refs, and listSkills grants as readSkill", async () => {
  const q = (text: string, values: unknown[] = []) => client.query(text, values);
  await q(
    "INSERT INTO assignments (id, business_id, commitment_id, employee_id, provider, purpose, objective) VALUES ('s1', 'b1', 'w-both', 'ops', 'codex', 'build', 'Build')",
  );
  await q("INSERT INTO conversations (business_id, key) VALUES ('b1', 'work:w-both')");
  await q(`INSERT INTO messages (id, business_id, conversation, author, kind, text, ref, client_id) VALUES
    ('e1', 'b1', 'work:w-both', 'system', 'event', 'Took on', 'w-both', 'c-e1'),
    ('e2', 'b1', 'work:w-both', 'system', 'event', 'Page', 'artifact:a1', 'c-e2'),
    ('e3', 'b1', 'work:w-both', 'system', 'event', 'Codex', 's1', 'c-e3'),
    ('e4', 'b1', 'work:w-both', 'system', 'event', 'Gone', 'w-deleted', 'c-e4')`);
  await q(
    "INSERT INTO project_items (id, business_id, project_id, kind, ref) VALUES ('i5', 'b1', 'launch', 'file', '/Users/o/Devys/b1/Q3 plan (ü).md')",
  );
  await q(`INSERT INTO grants (id, business_id, employee_id, capability, mode) VALUES
    ('g1', 'b1', 'ops', 'listSkills', 'auto'), ('g2', 'b1', 'ops', 'read', 'auto')`);

  await apply(client, (migration) => migration >= refs && migration < names);

  expect(
    (await q("SELECT id, ref FROM messages WHERE ref IS NOT NULL OR id LIKE 'e%' ORDER BY id"))
      .rows,
  ).toEqual([
    { id: "e1", ref: "devys:work/item/w-both" },
    { id: "e2", ref: "devys:documents/artifact/a1" },
    { id: "e3", ref: "devys:code/session/s1" },
    { id: "e4", ref: null },
  ]);
  expect((await q("SELECT id, project_id, ref FROM project_items ORDER BY id")).rows).toEqual([
    {
      id: "i3",
      project_id: "launch",
      ref: "devys:documents/file/%2FUsers%2Fo%2FDevys%2Fb1%2Fplan.md",
    },
    { id: "i4", project_id: "growth", ref: "devys:documents/artifact/a1" },
    {
      id: "i5",
      project_id: "launch",
      ref: "devys:documents/file/%2FUsers%2Fo%2FDevys%2Fb1%2FQ3%20plan%20(%C3%BC).md",
    },
  ]);
  // The SQL encoding is encodeURIComponent's.
  expect(encodeURIComponent("/Users/o/Devys/b1/Q3 plan (ü).md")).toBe(
    "%2FUsers%2Fo%2FDevys%2Fb1%2FQ3%20plan%20(%C3%BC).md",
  );
  expect(
    (await q("SELECT capability, revoked_at IS NULL AS active FROM grants ORDER BY capability"))
      .rows,
  ).toEqual([
    { capability: "listSkills", active: false },
    { capability: "read", active: true },
    { capability: "readSkill", active: true },
  ]);
  // One Ref per project, and only artifacts and files.
  await expect(
    q(
      "INSERT INTO project_items (id, business_id, project_id, ref) VALUES ('i6', 'b1', 'growth', 'devys:documents/artifact/a1')",
    ),
  ).rejects.toThrow();
  await expect(
    q(
      "INSERT INTO project_items (id, business_id, project_id, ref) VALUES ('i7', 'b1', 'growth', 'devys:work/item/w-none')",
    ),
  ).rejects.toThrow();
  await expect(q("UPDATE messages SET ref = 'artifact:a1' WHERE id = 'e2'")).rejects.toThrow();
});

it("AL2 names work items and coding sessions, and reissues the work grants under their names", async () => {
  const q = (text: string, values: unknown[] = []) => client.query(text, values);
  await q(`INSERT INTO grants (id, business_id, employee_id, capability, mode) VALUES
    ('g3', 'b1', 'ops', 'commitmentList', 'auto'), ('g4', 'b1', 'ops', 'commitmentComplete', 'ask')`);
  await q("UPDATE assignments SET session_id = 'thread-1', worktree = '/w' WHERE id = 's1'");

  await apply(client, (migration) => migration >= names);

  expect(
    (await q("SELECT id, work_item_id, provider_session_id FROM coding_sessions")).rows,
  ).toEqual([{ id: "s1", work_item_id: "w-both", provider_session_id: "thread-1" }]);
  expect((await q("SELECT id FROM work_items ORDER BY id")).rows).toEqual([
    { id: "w-both" },
    { id: "w-none" },
  ]);
  expect(
    (
      await q(
        "SELECT capability, mode, revoked_at IS NULL AS active FROM grants WHERE capability ~ '^(commitment|work)' ORDER BY capability",
      )
    ).rows,
  ).toEqual([
    { capability: "commitmentComplete", mode: "ask", active: false },
    { capability: "commitmentList", mode: "auto", active: false },
    { capability: "workComplete", mode: "ask", active: true },
    { capability: "workList", mode: "auto", active: true },
  ]);
  // A coding session names a work item of its own business.
  await expect(
    q(
      "INSERT INTO coding_sessions (id, business_id, work_item_id, employee_id, provider, purpose, objective) VALUES ('s2', 'b1', 'w-missing', 'ops', 'codex', 'build', 'Build')",
    ),
  ).rejects.toThrow();
});
