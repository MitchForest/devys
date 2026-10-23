import { defineApp } from "../../protocol/app.ts";

export const team = defineApp({
  id: "team",
  name: "Team",
  icon: "person.3",
  summary: "The business's employees and the apps they use: hiring, and finding apps to connect.",
  kind: "system",
  // A remote app the business connected (an MCP server), whose card the owner connects and turns on.
  records: [{ kind: "app", title: "App" }],
  capabilities: ["hireEmployee", "appSearch"],
  skills: [],
  connections: [],
  appears: "never",
  // The Chief of Staff proposes hires (its template holds hireEmployee in `ask` mode); every employee may
  // look for an app to ask the owner to connect.
  defaultGrants: {
    "chief-of-staff": ["hireEmployee", "appSearch"],
    engineering: ["appSearch"],
    growth: ["appSearch"],
    admin: ["appSearch"],
    finance: ["appSearch"],
    custom: ["appSearch"],
  },
});
