import { defineApp } from "../../protocol/app.ts";

const capabilities = [
  "browserOpen",
  "browserRead",
  "browserClick",
  "browserType",
  "browserPress",
] as const;

export const browser = defineApp({
  id: "browser",
  name: "Browser",
  icon: "safari",
  summary: "The business's own browser: open, read, click, type and press keys.",
  kind: "system",
  status: "available",
  records: [],
  capabilities,
  skills: [],
  connections: [],
  appears: "never",
  defaultGrants: {
    operations: capabilities,
    engineering: capabilities,
    growth: capabilities,
    "business-operations": capabilities,
  },
});
