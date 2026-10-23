/**
 * Email on the business's own domain, with nothing set up yet: the Chief of Staff should ask which
 * provider (chips, its recommendation first), plan the work as steps (the mailbox, the DNS
 * records, verification, a test delivery) and stop at the first thing only the owner can do.
 */
import type { Scenario } from "../../scripts/scenario.ts";

export default {
  name: "domain-email",
  business: {
    name: "Acme Roasters",
    brief: "A small coffee roaster selling beans online and to two local cafes.",
    memories: [
      "Acme's domain acmeroasters-sample.com is registered at Cloudflare, which also runs its DNS. The business has no email yet.",
    ],
  },
  persona: {
    provider: "Google Workspace",
    registrar: "Cloudflare",
    address: "hello@",
    payment: "A card",
  },
  turns: [
    { say: "Set up email on acmeroasters-sample.com" },
    { tap: "provider", optional: true },
    { tap: "address", optional: true },
    { tap: "payment", optional: true },
    { tap: "registrar", optional: true },
    { start: true, optional: true },
    { stop: ["connect", "take_over", "secret", "spend", "approve", "decision"] },
  ],
} satisfies Scenario;
