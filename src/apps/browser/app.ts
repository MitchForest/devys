import { defineApp } from "../../protocol/app.ts";

export const browser = defineApp({
  id: "browser",
  name: "Browser",
  icon: "safari",
  summary: "The business's own browser: open, read, click, type and press keys.",
  kind: "system",
  status: "available",
  records: [],
  capabilities: ["browserOpen", "browserRead", "browserClick", "browserType", "browserPress"],
  skills: [],
  connections: [],
  appears: "never",
});
