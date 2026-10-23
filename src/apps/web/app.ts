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
    "chief-of-staff": ["readPublicUrl"],
    engineering: ["readPublicUrl"],
    growth: ["readPublicUrl"],
    admin: ["readPublicUrl"],
    finance: ["readPublicUrl"],
  },
});
