/**
 * What a script sees, defined over the `browser` calls `browserScript` provides: `session`,
 * shaped like browser-harness-js's (every DevTools Protocol domain as `session.<Domain>.<method>`,
 * `use` and `waitFor`), and its `listPageTargets`.
 */
export const scriptPrelude = String.raw`
const session = (() => {
  let cursor = null;
  const send = async (method, params) => {
    const sent = await browser.call({ method, params: params ?? {} });
    cursor = sent.cursor;
    return sent.result;
  };
  const domain = (name) =>
    new Proxy({}, { get: (_, method) => (typeof method === "string" ? (params) => send(name + "." + method, params) : undefined) });
  const helpers = {
    async use(targetId) {
      await browser.tabs({ action: "switch", tab: targetId });
      return targetId;
    },
    async waitFor(method, predicate, timeoutMs = 30000) {
      const deadline = Date.now() + timeoutMs;
      let after = cursor;
      while (Date.now() < deadline) {
        const found = await browser.events({ after, method, waitMs: Math.min(5000, deadline - Date.now()) });
        for (const event of found.events) if (!predicate || predicate(event.params)) return event.params;
        after = found.cursor;
      }
      throw new Error("Timeout waiting for " + method);
    },
  };
  return new Proxy(helpers, {
    get: (target, name) =>
      name in target ? target[name] : typeof name === "string" && /^[A-Z]/.test(name) ? domain(name) : undefined,
  });
})();
const listPageTargets = async () =>
  (await browser.tabs({ action: "list" })).map((tab) => ({ targetId: tab.id, type: "page", title: tab.title, url: tab.url, current: tab.current }));
`;
