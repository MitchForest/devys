import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { terminalRoute } from "../src/app/terminals.ts";

const access = (path: string, trusted = true) => ({
  person: { id: "p", display_name: "Owner" } as never,
  business: { id: "b", name: "Business" } as never,
  trusted,
  path,
});

it("terminals are local-only, and acting on the Mac needs a trusted request", async () => {
  const cloud = env as unknown as Env;
  const listed = await terminalRoute(
    new Request("http://devys.test/terminals"),
    cloud,
    access("/terminals"),
  );
  expect(listed?.status).toBe(503);
  expect(
    await terminalRoute(new Request("http://devys.test/work"), cloud, access("/work")),
  ).toBeUndefined();
  const local = {
    ...cloud,
    DEVYS_MODE: "local",
    DEVYS_HOST_URL: "http://127.0.0.1:1",
    DEVYS_HOST_TOKEN: "t",
  } as unknown as Env;
  const opened = await terminalRoute(
    new Request("http://devys.test/terminals", { method: "POST", body: "{}" }),
    local,
    access("/terminals", false),
  );
  expect(opened?.status).toBe(403);
});
