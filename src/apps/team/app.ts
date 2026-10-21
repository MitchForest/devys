import { defineApp } from "../../protocol/app.ts";

export const team = defineApp({
  id: "team",
  name: "Team",
  icon: "person.3",
  summary: "The business's employees: hiring from a role template.",
  kind: "system",
  status: "available",
  records: [],
  capabilities: ["hireEmployee"],
  skills: [],
  connections: [],
  appears: "never",
});
