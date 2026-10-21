import { Effect } from "effect";
import type { Env } from "./env.ts";
import { memoryFor } from "./memory.ts";
import { listArtifacts } from "../apps/documents/service.ts";
import { exportDrive } from "../connections/drive.ts";
import { exportMessages } from "../conversations/service.ts";
import { scopeName, type Business, type Employee } from "../identity/contract.ts";

/** A business's portable data, streamed in bounded pages. This is not a live-runtime restore image. */
export function exportBusiness(env: Env, business: Business, employees: Employee[]) {
  async function* records() {
    yield {
      kind: "manifest",
      version: 1,
      business,
      employees,
      exportedAt: new Date().toISOString(),
      note: "Every DM, project channel and work-item thread, each employee's own Pi history for its direct chat, current memory, artifact index, and selected Drive file index. Credentials are excluded. Artifact bytes require separate downloads. Concurrent edits may appear during export.",
    };
    for (const employee of employees) {
      const scope = { businessId: business.id, employeeId: employee.id };
      let before: number | undefined;
      for (;;) {
        const page = JSON.parse(
          await env.AGENT.getByName(scopeName(scope)).history(scope, before),
        ) as { entries: unknown[]; nextBefore: number | null };
        for (const entry of page.entries)
          yield { kind: "conversation-entry", employee: employee.id, entry };
        if (page.nextBefore === null || page.nextBefore < 0) break;
        before = page.nextBefore;
      }
    }
    let seq = "0";
    for (;;) {
      const rows = await Effect.runPromise(exportMessages(env.HYPERDRIVE, business.id, seq));
      for (const { seq: _, ...message } of rows) yield { kind: "message", message };
      if (rows.length < 100) break;
      seq = rows.at(-1)!.seq;
    }
    let memoryCursor: string | undefined;
    do {
      const page = await Effect.runPromise(memoryFor(env, business.id).export(memoryCursor));
      for (const record of page.items)
        yield record.kind === "claim"
          ? { kind: "memory", memory: record.claim, version: record.version }
          : { kind: "memory-exclusion", record };
      memoryCursor = page.next ?? undefined;
    } while (memoryCursor !== undefined);
    let id = "00000000-0000-0000-0000-000000000000";
    for (;;) {
      const rows = await Effect.runPromise(listArtifacts(env.HYPERDRIVE, business.id, id));
      for (const artifact of rows)
        yield {
          kind: "artifact",
          artifact,
          download: `${env.PUBLIC_URL}/api/artifacts/${artifact.id}`,
        };
      if (rows.length < 100) break;
      id = rows.at(-1)!.id;
    }
    let driveId = "";
    for (;;) {
      const rows = await exportDrive(env.HYPERDRIVE, business.id, driveId);
      for (const file of rows) yield { kind: "drive-file", file };
      if (rows.length < 100) break;
      driveId = rows.at(-1)!.file_id;
    }
    yield { kind: "complete" };
  }
  const iterator = records();
  return new Response(
    new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          const item = await iterator.next();
          if (item.done) controller.close();
          else controller.enqueue(new TextEncoder().encode(`${JSON.stringify(item.value)}\n`));
        } catch {
          controller.error(
            new Error(
              "Export interrupted. Retry the download; only files ending with a complete record are complete.",
            ),
          );
        }
      },
      async cancel() {
        await iterator.return(undefined);
      },
    }),
    {
      headers: {
        "content-type": "application/x-ndjson",
        "content-disposition": 'attachment; filename="devys-export.ndjson"',
        "content-security-policy": "sandbox; default-src 'none'",
      },
    },
  );
}
