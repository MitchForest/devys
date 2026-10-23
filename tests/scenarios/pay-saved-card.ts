/**
 * Paying with a card already saved: the Chief of Staff should find it (secretList) without asking how
 * the business pays, get to the checkout and ask for a spend approval with the exact total. The
 * run stops there: a spend approval is signed on the owner's device. A test card number, never
 * charged.
 */
import type { Scenario } from "../../scripts/scenario.ts";

export default {
  name: "pay-saved-card",
  business: {
    name: "Acme Roasters",
    brief: "A small coffee roaster selling beans online and to two local cafes.",
    secrets: [
      {
        name: "BUSINESS_CARD",
        kind: "spend",
        card: {
          number: "4242424242424242",
          expiry: "04/31",
          cvc: "737",
          name: "Sam Owner",
          postal: "94107",
        },
      },
    ],
  },
  persona: {
    payment: "The saved card",
    years: "1 year",
  },
  turns: [{ say: "Can you buy the domain acmeroasters-sample.com for us?" }, { stop: "spend" }],
} satisfies Scenario;
