import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import { conversationKey } from "../conversations/contract.ts";
import type { Business, Person } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { readBounded, sha256Bytes } from "../protocol/bytes.ts";
import { revisionConflict } from "../workspace/contract.ts";
import { workItem } from "../work/service.ts";
import { postFromPerson } from "./conversations.ts";
import { modeOf } from "./mode.ts";
import { body } from "./request.ts";

type Access = { person: Person; business: Business; trusted: boolean; path: string };

const types: Record<string, string> = {
  pdf: "application/pdf",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  svg: "image/svg+xml",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  csv: "text/csv",
  md: "text/markdown",
  txt: "text/plain",
  json: "application/json",
};
const rawBytes = 20_000_000;

const Offset = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
const Coordinate = Schema.Finite;
/** One anchored comment: a markdown source range, PDF page rectangles, or diff lines. */
const Anchor = Schema.Union([
  Schema.Struct({
    kind: Schema.Literal("text"),
    start: Offset,
    end: Offset,
    quote: Schema.String.check(Schema.isMaxLength(4_000)),
  }),
  Schema.Struct({
    kind: Schema.Literal("pdf"),
    page: Offset,
    rects: Schema.Array(
      Schema.Struct({ x: Coordinate, y: Coordinate, width: Coordinate, height: Coordinate }),
    ).check(Schema.isMaxLength(50)),
  }),
  Schema.Struct({ kind: Schema.Literal("lines"), start: Offset, end: Offset }),
]);
type Anchor = typeof Anchor.Type;
const Comments = Schema.Struct({
  id: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}$/)),
  path: Schema.String,
  employee: Schema.optional(Schema.String),
  /** A work item whose thread gets the comments, addressed to its owner, instead of a DM. */
  work: Schema.optional(Schema.String),
  comments: Schema.Array(
    Schema.Struct({ anchor: Anchor, text: Schema.String.check(Schema.isMaxLength(8_000)) }),
  ).check(Schema.isMinLength(1), Schema.isMaxLength(100)),
  message: Schema.optional(Schema.String.check(Schema.isMaxLength(8_000))),
});

/** A path in the business's folder on the Mac, or undefined (also outside local mode). */
export function businessFile(env: Env, businessId: string, candidate: unknown) {
  const root = modeOf(env).businessFolder(businessId);
  return root &&
    typeof candidate === "string" &&
    candidate.length <= 1024 &&
    (candidate === root || candidate.startsWith(`${root}/`)) &&
    !candidate.split("/").some((part) => part === ".." || part === ".")
    ? candidate
    : undefined;
}

/**
 * The business's files for the owner (.docs/PRODUCT_EXPERIENCE.md#files-and-documents): browsing
 * its folder on the Mac, reading and saving text at a revision, the bytes of anything for a
 * viewer, and comments sent to an employee as one message. Files stay where they are; the runner
 * owns them. Local mode only for now: in cloud mode each employee has its own workspace.
 */
export async function filesRoute(request: Request, env: Env, access: Access) {
  const { person, business, trusted, path } = access;
  if (path !== "/files" && !path.startsWith("/files/")) return undefined;
  const mode = modeOf(env);
  const root = mode.businessFolder(business.id);
  if (!root) return new Response("Files run in local mode only for now.", { status: 503 });
  // Built when a file is touched, so comments work without asking the host anything.
  const runner = () => mode.runner(root)({ businessId: business.id, employeeId: "owner" });
  const url = new URL(request.url);
  const inside = (candidate: unknown) => businessFile(env, business.id, candidate);
  const failure = (error: unknown) => {
    const message = error instanceof Error ? error.message : "The file is unavailable";
    return new Response(message, { status: /unavailable|ENOENT/i.test(message) ? 404 : 400 });
  };

  if (path === "/files" && request.method === "GET") {
    const folder = inside(url.searchParams.get("path") ?? root);
    if (!folder) return new Response("Stay inside the business folder", { status: 400 });
    try {
      return Response.json({ root, path: folder, entries: await runner().list(folder) });
    } catch (error) {
      // A business with no files yet has no folder.
      if (folder === root) return Response.json({ root, path: folder, entries: [] });
      return failure(error);
    }
  }
  if (path === "/files/text" && request.method === "GET") {
    const file = inside(url.searchParams.get("path"));
    if (!file) return new Response("Stay inside the business folder", { status: 400 });
    try {
      return Response.json(await runner().read(file, 1_000_000));
    } catch (error) {
      return failure(error);
    }
  }
  if (path === "/files/raw" && request.method === "GET") {
    const file = inside(url.searchParams.get("path"));
    if (!file) return new Response("Stay inside the business folder", { status: 400 });
    // The runner moves bytes through R2; this copy exists only for this response.
    const key = `${business.id}/file-views/${crypto.randomUUID()}`;
    try {
      await runner().exportFile(file, key, rawBytes);
      const object = await env.FILES.get(key);
      if (!object) return new Response("The file is unavailable", { status: 404 });
      const bytes = await object.arrayBuffer();
      await env.FILES.delete(key);
      const extension = file.split(".").at(-1)?.toLowerCase() ?? "";
      return new Response(bytes, {
        headers: {
          "content-type": types[extension] ?? "application/octet-stream",
          // Editors of binary files save over this revision.
          "x-devys-revision": await sha256Bytes(bytes),
          "content-disposition": `inline; filename="${file.split("/").at(-1)!.replace(/"/g, "")}"`,
          "x-content-type-options": "nosniff",
          "content-security-policy": "sandbox",
        },
      });
    } catch (error) {
      await env.FILES.delete(key).catch(() => undefined);
      return failure(error);
    }
  }
  if (!trusted) return new Response("Forbidden", { status: 403 });
  if (path === "/files/text" && request.method === "PUT") {
    // Text files open up to 1 MB; JSON escaping can double it.
    const input = await body<{ path: string; content: string; expectedRevision: string | null }>(
      request,
      2_000_000,
    );
    const file = inside(input.path);
    if (!file || typeof input.content !== "string")
      return new Response("Send a path inside the business folder and its text", { status: 400 });
    try {
      return Response.json(
        await runner().write(file, input.content, input.expectedRevision ?? null),
      );
    } catch (error) {
      if (error instanceof Error && error.message.startsWith(revisionConflict)) {
        // The newer text comes back, so the owner can see what changed before saving again.
        const current = await runner()
          .read(file, 1_000_000)
          .catch(() => null);
        return Response.json({ conflict: true, current }, { status: 409 });
      }
      return failure(error);
    }
  }
  if (path === "/files/raw" && request.method === "PUT") {
    const file = inside(url.searchParams.get("path"));
    if (!file) return new Response("Stay inside the business folder", { status: 400 });
    const expected = url.searchParams.get("expectedRevision");
    // Counted while it arrives, so an oversized upload is refused without holding all of it.
    const bytes = await readBounded(request.body, rawBytes).catch(() => undefined);
    if (!bytes) return new Response("The file is too large", { status: 413 });
    // The runner reads the bytes from R2; this copy exists only for this save.
    const key = `${business.id}/file-saves/${crypto.randomUUID()}`;
    await env.FILES.put(key, bytes);
    try {
      // No revision overwrites (a derived export); "none" means the file must not exist yet.
      await runner().importFile(
        file,
        key,
        expected === null ? undefined : expected === "none" ? null : expected,
      );
      return Response.json({ path: file, revision: await sha256Bytes(bytes) });
    } catch (error) {
      if (error instanceof Error && error.message.startsWith(revisionConflict))
        return Response.json({ conflict: true }, { status: 409 });
      return failure(error);
    } finally {
      await env.FILES.delete(key);
    }
  }
  if (path === "/files/comments" && request.method === "POST") {
    const decoded = Schema.decodeUnknownOption(Comments)(await body(request, 64_000));
    if (decoded._tag === "None")
      return new Response("Send a client id, a file and comments with their anchors", {
        status: 400,
      });
    const input = decoded.value;
    const file = inside(input.path);
    const work =
      typeof input.work === "string"
        ? await Effect.runPromise(workItem(env.HYPERDRIVE, business.id, input.work))
        : undefined;
    const employeeId = work?.owner_employee_id ?? input.employee;
    const employee =
      typeof employeeId === "string" && (work || input.work === undefined)
        ? await Effect.runPromise(
            activeEmployee(env.HYPERDRIVE, { businessId: business.id, employeeId }),
          )
        : undefined;
    const comments = input.comments.filter((comment) => comment.text.trim());
    if (!file || !employee || !comments.length)
      return new Response(
        "Send a file, an employee or a work item, a client id and at least one comment",
        { status: 400 },
      );
    const key = conversationKey(work ? `work:${work.id}` : `direct:${employee.id}`)!;
    const text = [
      `Comments on ${file}:`,
      ...comments.map((comment) => `- ${describe(comment.anchor)}: ${comment.text.trim()}`),
      input.message?.trim() ?? "",
    ]
      .filter(Boolean)
      .join("\n");
    const posted = await postFromPerson(env, business.id, person.id, key, {
      id: input.id,
      text: text.slice(0, 16_000),
      mentions: [employee.id],
    });
    if ("refused" in posted) return new Response(posted.refused, { status: 409 });
    return Response.json(posted, { status: 201 });
  }
  return new Response("Not found", { status: 404 });
}

/** How an anchor reads in the message that carries it. */
function describe(anchor: Anchor) {
  switch (anchor.kind) {
    case "text":
      return `"${anchor.quote.slice(0, 200)}" (characters ${anchor.start}–${anchor.end})`;
    case "lines":
      return anchor.start === anchor.end
        ? `line ${anchor.start}`
        : `lines ${anchor.start}–${anchor.end}`;
    case "pdf":
      return `page ${anchor.page}, ${anchor.rects
        .map(
          (rect) =>
            `region ${Math.round(rect.x)},${Math.round(rect.y)} ${Math.round(rect.width)}×${Math.round(rect.height)}`,
        )
        .join("; ")}`;
  }
}
