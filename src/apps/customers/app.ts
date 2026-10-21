import { defineApp } from "../../protocol/app.ts";

export const customers = defineApp({
  id: "customers",
  name: "Customers",
  icon: "person.2",
  summary: "Customers, conversations and follow-ups.",
  kind: "business",
  status: "coming",
  records: [],
  capabilities: [],
  skills: [],
  connections: [{ provider: "google", scopes: [] }],
  appears: "connected",
});
