import { createServer } from "node:http";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { TestProject } from "vitest/node";

/** Where the native client's tests read the server's golden responses. */
export const wireFixtures = "apple/Packages/DevysKit/Tests/DevysClientTests/Fixtures/wire";

declare module "vitest" {
  export interface ProvidedContext {
    /** Where the wire test sends golden JSON to be written; empty unless `DEVYS_WRITE_WIRE=1`. */
    wireSink: string;
  }
}

/**
 * The Workers tests run in workerd, which cannot write the repository's files. With
 * `DEVYS_WRITE_WIRE=1` (`bun run wire:write`), this listens on loopback for the wire test's
 * normalized responses and writes each as `<name>.json`.
 */
export default async function setup(project: TestProject) {
  if (process.env.DEVYS_WRITE_WIRE !== "1") {
    project.provide("wireSink", "");
    return;
  }
  mkdirSync(wireFixtures, { recursive: true });
  const server = createServer((request, response) => {
    const name = /^\/([a-z0-9-]{1,64})$/.exec(request.url ?? "")?.[1];
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("end", () => {
      if (!name || request.method !== "PUT") return response.writeHead(400).end();
      writeFileSync(join(wireFixtures, `${name}.json`), Buffer.concat(chunks));
      response.writeHead(204).end();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("The wire sink has no port");
  project.provide("wireSink", `http://127.0.0.1:${address.port}`);
  return () => new Promise<void>((resolve) => server.close(() => resolve()));
}
