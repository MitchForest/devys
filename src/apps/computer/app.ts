import { defineApp } from "../../protocol/app.ts";
import { bundledSkill } from "../../protocol/skill.ts";
import checkingYourWork from "./skills/checking-your-work/SKILL.md?raw";

const capabilities = [
  "run",
  "read",
  "write",
  "printPdf",
  "importAttachment",
  "readSkill",
  "secretList",
] as const;
/**
 * The core capabilities, offered to every employee and so granted to every role, and the list of
 * saved secrets by name: whoever runs commands or fills a checkout needs to know what is saved.
 */
const core = ["run", "read", "write", "readSkill", "secretList"] as const;

export const computer = defineApp({
  id: "computer",
  name: "Computer",
  icon: "desktopcomputer",
  summary: "Commands, files, PDFs and skills where each employee works.",
  kind: "system",
  records: [],
  capabilities,
  skills: [bundledSkill("checking-your-work", checkingYourWork)],
  connections: [],
  appears: "never",
  defaultGrants: {
    "chief-of-staff": capabilities,
    engineering: capabilities,
    growth: capabilities,
    admin: capabilities,
    finance: capabilities,
    custom: core,
  },
});
