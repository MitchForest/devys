import { defineApp } from "../../protocol/app.ts";

export const money = defineApp({
  id: "money",
  name: "Money",
  icon: "creditcard",
  summary: "Payments, cards and transactions.",
  kind: "business",
  status: "coming",
  records: [],
  capabilities: [],
  skills: [],
  connections: [{ provider: "stripe", scopes: [] }],
  appears: "connected",
});
