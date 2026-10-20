import { Effect, Schema } from "effect";
import type { MemoryFactory, PortableRecord } from "./contract.ts";
import { MemoryError } from "./contract.ts";
import { ChangeSchema, ImportSchema, Key } from "./schema.ts";
import { sameOrigin } from "../protocol/http.ts";
import { readBounded, sha256 } from "../protocol/bytes.ts";

/**
 * The authenticated caller supplies the scope; body fields never select a tenant.
 * `path` is the part after the memory prefix: "", "/export", "/remember", "/forget" or "/import".
 */
export async function memoryRoute(
  request: Request,
  scope: string,
  path: string,
  factory: MemoryFactory,
  trusted = sameOrigin(request),
): Promise<Response> {
  const url = new URL(request.url),
    memory = factory(scope),
    after = url.searchParams.get("after") ?? undefined;
  try {
    if (request.method === "GET") {
      if (path === "") return Response.json(await Effect.runPromise(memory.inspect(after)));
      if (path === "/export") return Response.json(await Effect.runPromise(memory.export(after)));
      return new Response("Not found", { status: 404 });
    }
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (!trusted) return new Response("Forbidden", { status: 403 });
    const id = request.headers.get("idempotency-key");
    if (!id || !/^[a-zA-Z0-9:_-]{1,160}$/.test(id))
      return new Response("An Idempotency-Key is required", { status: 400 });
    const input = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(await readBounded(request.body, 2_000_000)),
    );
    if (path === "/remember") {
      const change = Schema.decodeUnknownSync(ChangeSchema)(input);
      const evidenceId = `web:${await sha256(`${url.origin}:${scope}:${id}`)}`;
      await Effect.runPromise(
        memory.observe([
          {
            id: evidenceId,
            kind: "owner",
            observedAt: new Date().toISOString(),
            content: change.content,
          },
        ]),
      );
      return Response.json(
        await Effect.runPromise(
          memory.remember({ ...change, evidenceIds: [evidenceId] }, `web:${id}`),
        ),
      );
    }
    if (path === "/forget") {
      const { keys } = Schema.decodeUnknownSync(
        Schema.Struct({
          keys: Schema.Array(Key).check(Schema.isMinLength(1), Schema.isMaxLength(30)),
        }),
      )(input);
      return Response.json(await Effect.runPromise(memory.forget([...keys], `web:${id}`)));
    }
    if (path === "/import") {
      Schema.decodeUnknownSync(ImportSchema)(input);
      return Response.json(
        await Effect.runPromise(memory.import(input as PortableRecord[], `import:${id}`)),
      );
    }
    return new Response("Not found", { status: 404 });
  } catch (error) {
    if (error instanceof MemoryError)
      return Response.json(
        { error: error.message },
        { status: error.code === "conflict" ? 409 : error.code === "invalid" ? 400 : 503 },
      );
    return new Response("Invalid memory request", { status: 400 });
  }
}
