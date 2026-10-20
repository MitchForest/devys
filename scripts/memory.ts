import { createReadStream } from "node:fs";
import { open } from "node:fs/promises";
import { createInterface } from "node:readline";
import { createHash } from "node:crypto";
import { Schema } from "effect";
import { PortableSchema } from "../src/memory/schema.ts";
import type { MemoryExportPage, PortableRecord } from "../src/memory/contract.ts";

const [command, path] = process.argv.slice(2);
if (!["export", "import"].includes(command ?? "") || !path)
  throw new Error(
    "Usage: bun scripts/memory.ts export|import file.ndjson (DEVYS_URL, DEVYS_SESSION and DEVYS_BUSINESS required)",
  );
const base = new URL(process.env.DEVYS_URL ?? "");
if (
  base.protocol !== "https:" &&
  !(base.protocol === "http:" && ["localhost", "127.0.0.1"].includes(base.hostname))
)
  throw new Error("Use HTTPS for a remote deployment");
const session = process.env.DEVYS_SESSION;
if (!session || !/^[a-f0-9]{64}$/.test(session))
  throw new Error(
    "DEVYS_SESSION must contain the private browser session token; do not put it in command arguments",
  );
const business = process.env.DEVYS_BUSINESS;
if (!business || !/^[A-Za-z0-9-]{1,64}$/.test(business))
  throw new Error("DEVYS_BUSINESS must name the business whose memory to move");
const memory = `/api/businesses/${business}/memory`;
async function request(route: string, body?: PortableRecord[], id?: string) {
  const response = await fetch(new URL(route, base.origin), {
    method: body ? "POST" : "GET",
    redirect: "error",
    signal: AbortSignal.timeout(30000),
    headers: {
      cookie: `__Host-devys=${session}`,
      origin: base.origin,
      ...(body ? { "content-type": "application/json", "idempotency-key": id! } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok)
    throw new Error(
      `Memory request failed (${response.status}). The session may have expired, or the destination may contain conflicting memories.`,
    );
  return response;
}
async function* records(file: string) {
  let manifest = false,
    complete = false;
  for await (const line of createInterface({
    input: createReadStream(file),
    crlfDelay: Infinity,
  })) {
    if (!line.trim()) continue;
    if (Buffer.byteLength(line) > 1_000_000)
      throw new Error("Memory record exceeds migration limit");
    const value = JSON.parse(line);
    if (!manifest) {
      if (value.kind !== "manifest" || value.format !== "devys-memory" || value.version !== 1)
        throw new Error("Unsupported memory export");
      manifest = true;
      continue;
    }
    if (complete) throw new Error("Unexpected records after completion marker");
    if (value.kind === "complete") {
      complete = true;
      continue;
    }
    Schema.decodeUnknownSync(PortableSchema)(value);
    if (value.kind === "claim" && value.claim.truncated)
      throw new Error("An excerpt cannot be migrated");
    yield value as PortableRecord;
  }
  if (!manifest || !complete)
    throw new Error("Incomplete memory export; no import should be started");
}
if (command === "export") {
  const output = await open(path!, "wx", 0o600);
  const write = (value: unknown) => output.writeFile(JSON.stringify(value) + "\n");
  try {
    await write({
      kind: "manifest",
      format: "devys-memory",
      version: 1,
      exportedAt: new Date().toISOString(),
    });
    let revision: number | undefined;
    let after: string | null = null,
      count = 0;
    do {
      const page = (await (
        await request(`${memory}/export${after ? `?after=${encodeURIComponent(after)}` : ""}`)
      ).json()) as MemoryExportPage;
      if (revision !== undefined && page.revision !== revision)
        throw new Error(
          "Memory changed during export. Retry while conversation and maintenance are idle.",
        );
      revision = page.revision;
      for (const record of page.items) {
        Schema.decodeUnknownSync(PortableSchema)(record);
        await write(record);
        count++;
      }
      after = page.next;
    } while (after);
    await write({ kind: "complete" });
    await output.sync();
    console.log(`Exported ${count} memory records.`);
  } finally {
    await output.close();
  }
} else {
  // Validate the complete stream before any mutation; retry identities derive from exact file bytes.
  let count = 0;
  for await (const _record of records(path!)) count++;
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path!)) hash.update(chunk);
  const digest = hash.digest("hex");
  let batch: PortableRecord[] = [],
    size = 0,
    page = 0;
  const flush = async () => {
    if (!batch.length) return;
    await request(`${memory}/import`, batch, `${digest}:${page++}`);
    batch = [];
    size = 0;
  };
  for await (const record of records(path!)) {
    const bytes = Buffer.byteLength(JSON.stringify(record));
    if (batch.length >= 30 || size + bytes > 1_000_000) await flush();
    batch.push(record);
    size += bytes;
  }
  await flush();
  console.log(
    `Imported ${count} memory records. Existing conflicting claims were not overwritten.`,
  );
}
