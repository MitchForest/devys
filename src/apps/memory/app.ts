import { defineApp } from "../../protocol/app.ts";

// Core capabilities: every role is granted them.
const capabilities = ["recall", "remember", "forget"] as const;

export const memory = defineApp({
  id: "memory",
  name: "Memory",
  icon: "brain",
  summary: "What the business knows: facts and corrections employees recall, save and forget.",
  kind: "system",
  records: [],
  capabilities,
  skills: [],
  connections: [],
  appears: "never",
  defaultGrants: {
    "chief-of-staff": capabilities,
    engineering: capabilities,
    growth: capabilities,
    admin: capabilities,
    finance: capabilities,
    custom: capabilities,
  },
});
