/**
 * Whether a checkout page belongs to the merchant a spend approval names. Sites are compared by
 * registrable domain (the public suffix plus one label, from the Public Suffix List): an approval
 * for `namecheap.com` covers `www.namecheap.com` and `ap.www.namecheap.com`, not
 * `namecheap.com.evil.example` or `evilnamecheap.com`. A loopback host is its own site (a local
 * test checkout).
 */
import { parse } from "tldts";

const loopback = (host: string) => host === "localhost" || host === "127.0.0.1" || host === "[::1]";

/** A host's site: its registrable domain, or the loopback host itself. */
function siteOf(host: string | null | undefined) {
  if (!host) return undefined;
  if (loopback(host)) return host;
  const parsed = parse(host);
  return parsed.isIp ? undefined : (parsed.domain ?? undefined);
}

/**
 * The merchant's site an approval's counterparty names (`Namecheap (namecheap.com)`,
 * `https://www.namecheap.com/cart`), or undefined when it names none.
 */
export function merchantSite(counterparty: string) {
  for (const token of counterparty.split(/[\s,;()<>"'[\]]+/)) {
    const word = token.replace(/[.:/]+$/, "");
    if (!word.includes(".") && word !== "localhost") continue;
    let host: string;
    try {
      host = new URL(/^[a-z]+:\/\//i.test(word) ? word : `https://${word}`).hostname;
    } catch {
      continue;
    }
    const site = siteOf(host);
    if (site) return site;
  }
  return undefined;
}

/**
 * Why a card may not be filled on `pageUrl` for this counterparty, or undefined when it may: the
 * page must be https (or a loopback test page) on the merchant's site.
 */
export function merchantRefusal(pageUrl: string, counterparty: string) {
  const merchant = merchantSite(counterparty);
  if (!merchant)
    return "The spend approval doesn't name the merchant's site (like namecheap.com): ask again naming it";
  let page: URL;
  try {
    page = new URL(pageUrl);
  } catch {
    return "The page isn't a checkout";
  }
  if (page.protocol !== "https:" && !(page.protocol === "http:" && loopback(page.hostname)))
    return "A card is filled only on an https page";
  if (siteOf(page.hostname) !== merchant)
    return `This page is on ${page.hostname}, not ${merchant}, which the approval names`;
  return undefined;
}
