import { createServer, type Server } from "node:http";
import { afterEach, expect, it } from "vitest";
import { hostPost, Unavailable } from "../src/protocol/host.ts";

const servers: Server[] = [];
afterEach(() => {
  for (const server of servers.splice(0)) {
    server.closeAllConnections();
    server.close();
  }
});

const listening = (handler: Parameters<typeof createServer>[1]) =>
  new Promise<string>((resolve) => {
    const server = createServer(handler);
    servers.push(server);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      resolve(`http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`);
    });
  });

it("a Mac host that stops answering ends the call in time instead of holding the turn", async () => {
  const url = await listening(() => undefined);
  const started = Date.now();
  const call = hostPost({ url, token: "t" }, "/browser/call", {}, "the browser is", 200);
  await expect(call).rejects.toBeInstanceOf(Unavailable);
  await expect(call).rejects.toThrow(/didn't answer in time/);
  expect(Date.now() - started).toBeLessThan(2_000);
});

it("a Mac host that isn't running is said to be down; its answer is parsed", async () => {
  await expect(
    hostPost({ url: "http://127.0.0.1:1", token: "t" }, "/vault/seal", {}, "secrets are"),
  ).rejects.toThrow(/not running, so secrets are unavailable/);
  const url = await listening((request, response) => {
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify({ auth: request.headers.authorization }));
  });
  expect(await hostPost({ url, token: "t" }, "/mcp/tools", {}, "remote apps are")).toEqual({
    auth: "Bearer t",
  });
});
