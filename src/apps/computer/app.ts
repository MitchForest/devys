import { defineApp } from "../../protocol/app.ts";

export const computer = defineApp({
  id: "computer",
  name: "Computer",
  icon: "desktopcomputer",
  summary: "Commands, files, PDFs and skills where each employee works.",
  kind: "system",
  status: "available",
  records: [],
  capabilities: ["run", "read", "write", "printPdf", "importAttachment", "readSkill"],
  skills: [],
  connections: [],
  appears: "never",
});
