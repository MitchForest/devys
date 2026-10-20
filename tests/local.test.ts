import { describe, expect, it } from "vitest";
import { appPort, launchAgent, tailnetUrl } from "../scripts/local.ts";

describe("local mode launcher", () => {
  it("prefers HTTPS Serve, then the TCP forward, and only when they reach the app", () => {
    const serving = {
      Web: {
        "mini.example.ts.net:443": { Handlers: { "/": { Proxy: `http://127.0.0.1:${appPort}` } } },
      },
    };
    expect(tailnetUrl(serving, "mini")).toBe("https://mini.example.ts.net");
    const elsewhere = {
      Web: { "mini.example.ts.net:443": { Handlers: { "/": { Proxy: "http://127.0.0.1:3000" } } } },
    };
    expect(tailnetUrl(elsewhere, "mini")).toBeUndefined();
    expect(tailnetUrl({}, "mini")).toBeUndefined();
    const forwarded = { TCP: { [appPort]: { TCPForward: `127.0.0.1:${appPort}` } } };
    expect(tailnetUrl(forwarded, "mini")).toBe(`http://mini:${appPort}`);
    expect(tailnetUrl({ ...forwarded, ...serving }, "mini")).toBe("https://mini.example.ts.net");
  });

  it("keeps the launcher alive at login and after exits", () => {
    const plist = launchAgent("/opt/bun", "/code/devys & co/scripts/local.ts", "/logs", "/a:/b");
    expect(plist).toContain(
      "<string>/opt/bun</string><string>/code/devys &amp; co/scripts/local.ts</string><string>run</string>",
    );
    expect(plist).toContain("<key>RunAtLoad</key><true/>");
    expect(plist).toContain("<key>KeepAlive</key><true/>");
    expect(plist).toContain("<string>/logs/launcher.log</string>");
    expect(plist).toContain("<key>PATH</key><string>/a:/b</string>");
  });
});
