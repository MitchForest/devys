import { defineApp } from "../../protocol/app.ts";

export const work = defineApp({
  id: "work",
  name: "Work",
  icon: "checklist",
  summary: "Work items the business owes and the projects they belong to.",
  kind: "system",
  status: "available",
  records: [
    { kind: "item", title: "Work item" },
    { kind: "project", title: "Project" },
  ],
  capabilities: [
    "commitmentList",
    "commitmentCreate",
    "commitmentUpdate",
    "commitmentComplete",
    "projectList",
    "projectCreate",
    "projectUpdate",
    "projectAdd",
  ],
  skills: [],
  connections: [],
  appears: "never",
});
