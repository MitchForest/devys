import { defineApp } from "../../protocol/app.ts";

export const ads = defineApp({
  id: "ads",
  name: "Ads",
  icon: "megaphone",
  summary: "Ad campaigns, spend and results.",
  kind: "business",
  status: "coming",
  records: [],
  capabilities: [],
  skills: [],
  connections: [{ provider: "meta", scopes: [] }],
  appears: "connected",
});
