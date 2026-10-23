import { hostCallMs, hostPost, Unavailable } from "../protocol/host.ts";
import type { Browser } from "./contract.ts";

/** The business's browser on the trusted Mac host (local mode). */
export function hostBrowser(host: { url: string; token: string }, businessId: string): Browser {
  const call = <T>(path: string, body: Record<string, unknown> = {}, ms?: number) =>
    hostPost<T>(host, `/browser/${path}`, { business: businessId, ...body }, "the browser is", ms);
  return {
    call: (method, params, driver) => call("call", { method, params, driver }),
    events: (after, method, waitMs) =>
      call("events", { after, method, waitMs }, waitMs + hostCallMs),
    tabs: (action, driver) => call("tabs", { ...action, driver }),
    status: () => call("status"),
    screenshot: (viewer) => call("screenshot", { viewer }),
    input: (action) => call("input", { action }),
    fill: (request, driver) => call("fill", { ...request, driver }),
    front: () => call("front"),
  };
}

/** Cloud mode has no browser yet (Browser Use arrives with cloud mode); every call says so. */
export function unavailableBrowser(): Browser {
  const refuse = () =>
    Promise.reject(
      new Unavailable("The browser runs in local mode only until cloud mode adds one."),
    );
  return {
    call: refuse,
    events: refuse,
    tabs: refuse,
    status: async () => ({ open: false, url: null, title: null, driver: null, driving: false }),
    screenshot: refuse,
    input: refuse,
    fill: refuse,
    front: refuse,
  };
}
