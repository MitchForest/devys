import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { terminalRoute } from "../src/app/terminals.ts";
import { Unavailable } from "../src/protocol/host.ts";

const access = (path: string, trusted = true) => ({
  person: { id: "p", display_name: "Owner" } as never,
  business: { id: "b", name: "Business" } as never,
  trusted,
  path,
});

it("terminals are local-only, and acting on the Mac needs a trusted request", async () => {
  const cloud = env as unknown as Env;
  // Cloud mode's adapter refuses; the API answers that as 503.
  await expect(
    terminalRoute(new Request("http://devys.test/terminals"), cloud, access("/terminals")),
  ).rejects.toThrow(Unavailable);
  expect(
    await terminalRoute(new Request("http://devys.test/work"), cloud, access("/work")),
  ).toBeUndefined();
  const local = {
    ...cloud,
    DEVYS_MODE: "local",
    DEVYS_HOST_URL: "http://127.0.0.1:1",
    DEVYS_HOST_TOKEN: "t",
    DEVYS_HOST_HOME: "/Users/owner",
  } as unknown as Env;
  const opened = await terminalRoute(
    new Request("http://devys.test/terminals", { method: "POST", body: "{}" }),
    local,
    access("/terminals", false),
  );
  expect(opened?.status).toBe(403);
});
