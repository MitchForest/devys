import { defineApp } from "../../protocol/app.ts";

const capabilities = ["run", "read", "write", "printPdf", "importAttachment", "readSkill"] as const;
/** The core capabilities, offered to every employee and so granted to every role. */
const core = ["run", "read", "write", "readSkill"] as const;

export const computer = defineApp({
  id: "computer",
  name: "Computer",
  icon: "desktopcomputer",
  summary: "Commands, files, PDFs and skills where each employee works.",
  kind: "system",
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
    custom: core,
  },
});
