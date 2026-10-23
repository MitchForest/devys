/**
 * Paying with nothing set up: the owner's business pays through Ramp. The Chief of Staff should ask
 * how the business pays with one tap's worth of choices, then propose a plan (connect Ramp, check
 * out, approve the total) that waits for Start. Started, the first request is connecting Ramp,
 * alone; the run stops there, which only the owner can complete.
 */
import type { Scenario } from "../../scripts/scenario.ts";

export default {
  name: "pay-ramp",
  business: {
    name: "Acme Roasters",
    brief: "A small coffee roaster selling beans online and to two local cafes.",
  },
  persona: {
    payment: "Ramp",
    years: "1 year",
  },
  turns: [
    { say: "Can you buy the domain acmeroasters-sample.com for us?" },
    { tap: "payment" },
    { start: true },
    { stop: "connect" },
  ],
} satisfies Scenario;
