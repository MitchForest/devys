/**
 * A Facebook Page, an Instagram account and a Meta business portfolio, no ads: the Chief of Staff should
 * ask for the name and handle with chips, use the business's email (not the owner's personal
 * one), hand sign-ins and checks to the owner (take over) and create nothing before asking.
 */
import type { Scenario } from "../../scripts/scenario.ts";

export default {
  name: "meta",
  business: {
    name: "Acme Roasters",
    brief: "A small coffee roaster selling beans online and to two local cafes.",
    memories: [
      "Acme's website is https://acmeroasters-sample.com.",
      "Acme's business email is hello@acmeroasters-sample.com.",
    ],
  },
  persona: {
    admin: "my Facebook",
    name: "Acme Roasters",
    handle: "acmeroasters",
    email: "hello@acmeroasters-sample.com",
  },
  turns: [
    { say: "Set up our Facebook Page, Instagram and Meta Business Manager. No ads." },
    { tap: "admin", optional: true },
    { tap: "handle", optional: true },
    { tap: "name", optional: true },
    { tap: "email", optional: true },
    { stop: ["take_over", "connect", "secret", "approve", "decision"] },
  ],
} satisfies Scenario;
