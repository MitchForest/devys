import { defineApp } from "../../protocol/app.ts";

export const web = defineApp({
  id: "web",
  name: "Web",
  icon: "network",
  summary: "Reads public web pages.",
  kind: "system",
  records: [],
  capabilities: ["readPublicUrl"],
  skills: [],
  connections: [],
  appears: "never",
  defaultGrants: {
    operations: ["readPublicUrl"],
    engineering: ["readPublicUrl"],
    growth: ["readPublicUrl"],
    "business-operations": ["readPublicUrl"],
  },
});
