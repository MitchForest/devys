import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { conversationKey } from "../conversations/contract.ts";
import type { Business, Person } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { readBounded, sha256Bytes } from "../protocol/bytes.ts";
import { revisionConflict } from "../workspace/contract.ts";
import { postFromPerson } from "./conversations.ts";
import { runnerFor } from "./runner.ts";

type Access = { person: Person; business: Business; trusted: boolean; path: string };
type LocalVariables = Partial<Record<"DEVYS_HOST_HOME", string>>;

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

/** One anchored comment: a markdown source range, PDF page rectangles, or diff lines. */
type Anchor =
  | { kind: "text"; start: number; end: number; quote: string }
  | { kind: "pdf"; page: number; rects: { x: number; y: number; width: number; height: number }[] }
  | { kind: "lines"; start: number; end: number };

/** A path in the business's folder on the Mac, or undefined (also outside local mode). */
export function businessFile(env: Env, businessId: string, candidate: unknown) {
  const home = (env as Env & LocalVariables).DEVYS_HOST_HOME;
  if (env.DEVYS_MODE !== "local" || !home) return undefined;
  const root = `${home}/Devys/${businessId}`;
  return typeof candidate === "string" &&
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
  const home = (env as Env & LocalVariables).DEVYS_HOST_HOME;
  if (env.DEVYS_MODE !== "local" || !home)
    return new Response("Files run in local mode only for now.", { status: 503 });
  const root = `${home}/Devys/${business.id}`;
  // Built when a file is touched, so comments work without asking the host anything.
  const runner = () => runnerFor(env, root)({ businessId: business.id, employeeId: "owner" });
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
    const input = (await request.json().catch(() => ({}))) as {
      path?: string;
      content?: string;
      expectedRevision?: string | null;
    };
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
    const input = (await request.json().catch(() => ({}))) as {
      id?: string;
      path?: string;
      employee?: string;
      comments?: { anchor: Anchor; text: string }[];
      message?: string;
    };
    const file = inside(input.path);
    const employee =
      typeof input.employee === "string"
        ? await Effect.runPromise(
            activeEmployee(env.HYPERDRIVE, { businessId: business.id, employeeId: input.employee }),
          )
        : undefined;
    const comments = (input.comments ?? []).filter(
      (comment) => typeof comment.text === "string" && comment.text.trim(),
    );
    if (!file || !employee || !comments.length || typeof input.id !== "string")
      return new Response("Send a file, an employee, a client id and at least one comment", {
        status: 400,
      });
    const key = conversationKey(`direct:${employee.id}`)!;
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
    return Response.json(posted, { status: "paused" in posted ? 409 : 201 });
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
