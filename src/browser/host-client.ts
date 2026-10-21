import { Unavailable } from "../protocol/host.ts";
import type { Browser } from "./contract.ts";

/** The business's browser on the trusted Mac host (local mode). */
export function hostBrowser(host: { url: string; token: string }, businessId: string): Browser {
  async function call<T>(path: string, body: Record<string, unknown> = {}): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${host.url}/browser/${path}`, {
        method: "POST",
        headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json" },
        body: JSON.stringify({ business: businessId, ...body }),
      });
    } catch {
      throw new Error("The Mac host is not running, so the browser is unavailable.");
    }
    if (!response.ok)
      throw new Error((await response.text()) || `Mac host error ${response.status}`);
    return (await response.json()) as T;
  }
  return {
    open: (url, driver) => call("open", { url, driver }),
    read: (driver) => call("read", { driver }),
    click: (target, driver) => call("click", { target, driver }),
    type: (target, text, submit, driver) => call("type", { target, text, submit, driver }),
    press: (key, driver) => call("press", { key, driver }),
    status: () => call("status"),
    screenshot: () => call("screenshot"),
    input: (action) => call("input", { action }),
  };
}

/** Cloud mode has no browser yet (Browser Use arrives with cloud mode); every call says so. */
export function unavailableBrowser(): Browser {
  const refuse = () =>
    Promise.reject(
      new Unavailable("The browser runs in local mode only until cloud mode adds one."),
    );
  return {
    open: refuse,
    read: refuse,
    click: refuse,
    type: refuse,
    press: refuse,
    status: async () => ({ open: false, url: null, title: null, driver: null }),
    screenshot: refuse,
    input: refuse,
  };
}
