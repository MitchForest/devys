import { defineApp } from "../../protocol/app.ts";

export const memory = defineApp({
  id: "memory",
  name: "Memory",
  icon: "brain",
  summary: "What the business knows: facts and corrections employees recall, save and forget.",
  kind: "system",
  status: "available",
  records: [],
  capabilities: ["recall", "remember", "forget"],
  skills: [],
  connections: [],
  appears: "never",
});
