/**
 * Google Analytics and Search Console for the business's site: the Chief of Staff should plan it as
 * steps and hand the Google sign-in to the owner (take over) rather than ask for a password,
 * in the business's own Google account.
 */
import type { Scenario } from "../../scripts/scenario.ts";

export default {
  name: "analytics",
  business: {
    name: "Acme Roasters",
    brief: "A small coffee roaster selling beans online and to two local cafes.",
    memories: [
      "Acme's website goes live next month at https://acmeroasters-sample.com; it isn't public yet. The domain is registered at Cloudflare, which also runs its DNS.",
      "Acme's business email is hello@acmeroasters-sample.com.",
    ],
  },
  persona: {
    live: "Not launched yet",
    built: "Not built yet",
    account: "hello@acmeroasters-sample.com",
    registrar: "Cloudflare",
  },
  turns: [
    { say: "Set up Google Analytics and Search Console for our site" },
    { tap: "live", optional: true },
    { tap: "account", optional: true },
    { tap: "built", optional: true },
    { tap: "registrar", optional: true },
    { start: true, optional: true },
    { stop: ["take_over", "connect", "secret", "approve", "decision"] },
  ],
} satisfies Scenario;
