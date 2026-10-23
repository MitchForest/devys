import { describe, expect, it } from "vitest";
import { mkdtempSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  advertisement,
  appPort,
  hostEnvironment,
  launchAgent,
  ownerKey,
  tailnetUrl,
  withVar,
} from "../scripts/local.ts";

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

  it("gives the Mac host no secret from .env, only its login folders and settings", () => {
    const dotenv =
      "DEVYS_MODEL_GATEWAY_KEY=k\nexport GOOGLE_CLIENT_SECRET=c\nDEVYS_CODEX_HOME=/codex\n# NOTE=x\n";
    const env = hostEnvironment(
      {
        PATH: "/bin",
        HOME: "/home",
        DEVYS_MODEL_GATEWAY_KEY: "k",
        GOOGLE_CLIENT_SECRET: "c",
        DEVYS_CODEX_HOME: "/codex",
        NOTE: "kept",
      },
      dotenv,
      { DEVYS_HOST_TOKEN: "t" },
    );
    expect(env).toEqual({
      PATH: "/bin",
      HOME: "/home",
      DEVYS_CODEX_HOME: "/codex",
      NOTE: "kept",
      DEVYS_HOST_TOKEN: "t",
    });
  });

  it("writes the host token into the Worker's vars file, replacing an old one", () => {
    expect(withVar("A=1\nDEVYS_HOST_TOKEN=old\n", "DEVYS_HOST_TOKEN", "new")).toBe(
      "A=1\nDEVYS_HOST_TOKEN=new\n",
    );
    expect(withVar("", "X", "1")).toBe("X=1\n");
  });

  it("announces this Mac on the local network with its tailnet address, never its loopback", () => {
    expect(advertisement("Sam's Mac mini", `http://mini:${appPort}`)).toMatchObject({
      command: "/usr/bin/dns-sd",
      args: [
        "-R",
        "Sam's Mac mini",
        "_devys._tcp",
        "local",
        String(appPort),
        `url=http://mini:${appPort}`,
      ],
    });
    expect(advertisement("Mini", "https://mini.example.ts.net")?.args).toContain("443");
    expect(advertisement("Mini", `http://127.0.0.1:${appPort}`)).toBeUndefined();
  });

  it("keeps the owner key in a file only the owner's user reads, made once", () => {
    const file = join(mkdtempSync(join(tmpdir(), "devys-owner-")), "owner.json");
    const key = ownerKey(file, "http://127.0.0.1:8787");
    expect(key).toMatch(/^[a-f0-9]{64}$/);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(JSON.parse(readFileSync(file, "utf8"))).toEqual({
      server: "http://127.0.0.1:8787",
      key,
    });
    expect(ownerKey(file)).toBe(key);
  });
});
