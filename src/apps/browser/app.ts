import { defineApp } from "../../protocol/app.ts";
import { bundledSkill } from "../../protocol/skill.ts";
import accountsAndSignIns from "./skills/accounts-and-sign-ins/SKILL.md?raw";
import usingTheBrowser from "./skills/using-the-browser/SKILL.md?raw";

const capabilities = ["browserScript", "browserScreenshot", "browserTabs", "browserFill"] as const;

export const browser = defineApp({
  id: "browser",
  name: "Browser",
  icon: "safari",
  summary:
    "The business's own browser: scripts against the page, screenshots, tabs, and passwords and cards filled by name.",
  kind: "system",
  records: [],
  capabilities,
  skills: [
    bundledSkill("using-the-browser", usingTheBrowser),
    bundledSkill("accounts-and-sign-ins", accountsAndSignIns),
  ],
  connections: [],
  appears: "never",
  defaultGrants: {
    operations: capabilities,
    engineering: capabilities,
    growth: capabilities,
    "business-operations": capabilities,
  },
});
