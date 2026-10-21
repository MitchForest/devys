import { defineApp } from "../../protocol/app.ts";

export const website = defineApp({
  id: "website",
  name: "Website",
  icon: "globe",
  summary: "The business's site, domains and pages.",
  kind: "business",
  status: "coming",
  records: [],
  capabilities: [],
  skills: [],
  connections: [{ provider: "cloudflare", scopes: [] }],
  appears: "connected",
});
