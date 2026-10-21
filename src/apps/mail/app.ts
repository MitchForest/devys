import { defineApp } from "../../protocol/app.ts";

export const mail = defineApp({
  id: "mail",
  name: "Mail",
  icon: "envelope",
  summary: "The business's mailboxes: threads, drafts and sending.",
  kind: "business",
  status: "coming",
  records: [],
  capabilities: [],
  skills: [],
  connections: [{ provider: "google", scopes: [] }],
  appears: "connected",
});
