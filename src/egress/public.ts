import { WorkerEntrypoint } from "cloudflare:workers";
import { isIP } from "node:net";
import { readBounded } from "../protocol/bytes.ts";
import { packageHosts } from "./contract.ts";

export function publicUrl(value: string, blockedHosts: readonly string[] = []) {
  const url = new URL(value);
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    (url.port && url.port !== "443") ||
    isIP(host) ||
    host.startsWith("[") ||
    !host.includes(".") ||
    /(?:^|\.)(?:localhost|local|internal|test|invalid|onion)$/.test(host) ||
    host === "metadata.google.internal" ||
    blockedHosts.includes(host)
  )
    throw new Error("Only public HTTPS URLs are allowed");
  return url;
}

export function publicAddress(address: string) {
  if (isIP(address) === 4) {
    const [a = 0, b = 0] = address.split(".").map(Number);
    return (
      a !== 0 &&
      a !== 10 &&
      a !== 127 &&
      a < 224 &&
      !(a === 169 && b === 254) &&
      !(a === 172 && b >= 16 && b <= 31) &&
      !(a === 192 && (b === 168 || b === 0 || b === 2)) &&
      !(a === 100 && b >= 64 && b <= 127) &&
      !(a === 198 && (b === 18 || b === 19 || b === 51)) &&
      !(a === 203 && b === 0)
    );
  }
  return (
    isIP(address) === 6 && /^[23]/.test(address) && !address.toLowerCase().startsWith("2001:db8:")
  );
}

async function checkDns(host: string) {
  const answers = await Promise.all(
    ["A", "AAAA"].map(async (type) => {
      const response = await fetch(
        `https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${type}`,
        {
          headers: { accept: "application/dns-json" },
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!response.ok) throw new Error("DNS lookup failed");
      return (await response.json()) as { Answer?: { type: number; data: string }[] };
    }),
  );
  const ips = answers.flatMap(
    (answer) =>
      answer.Answer?.filter((item) => item.type === 1 || item.type === 28).map(
        (item) => item.data,
      ) ?? [],
  );
  if (!ips.length || ips.some((ip) => !publicAddress(ip)))
    throw new Error("Destination is not public");
}

/** Hosts public reads must never reach: Devys itself and the iMessage relay. */
export interface EgressBindings {
  PUBLIC_URL: string;
  PHOTON_HTTP_ADDRESS: string;
}

export async function publicFetch(
  value: string,
  env: EgressBindings,
  maxBytes = 1_000_000,
  method = "GET",
) {
  const blocked = [env.PUBLIC_URL, env.PHOTON_HTTP_ADDRESS]
    .filter(Boolean)
    .map((value) => new URL(value).hostname);
  let url = publicUrl(value, blocked);
  for (let redirects = 0; redirects < 5; redirects++) {
    await checkDns(url.hostname);
    const response = await fetch(url, {
      method,
      redirect: "manual",
      signal: AbortSignal.timeout(20_000),
      headers: { "user-agent": "Devys/0.1 (public resource reader)" },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      await response.body?.cancel();
      if (!location) throw new Error("Redirect has no destination");
      url = publicUrl(new URL(location, url).href, blocked);
      continue;
    }
    const bytes = await readBounded(response.body, maxBytes);
    return {
      url: url.href,
      status: response.status,
      contentType: response.headers.get("content-type") ?? "application/octet-stream",
      bytes,
    };
  }
  throw new Error("Too many redirects");
}

export class PublicEgress extends WorkerEntrypoint<EgressBindings> {
  async fetch(request: Request) {
    if (
      !["GET", "HEAD"].includes(request.method) ||
      !(packageHosts as readonly string[]).includes(new URL(request.url).hostname)
    )
      return new Response("Package download denied", { status: 403 });
    try {
      const result = await publicFetch(request.url, this.env, 20_000_000, request.method);
      return new Response(new Uint8Array(result.bytes), {
        status: result.status,
        headers: { "content-type": result.contentType },
      });
    } catch {
      return new Response("Package download failed", { status: 502 });
    }
  }
}
